extends RefCounted
class_name CardInstance

## CardInstance - Runtime instance of a card.
## Tracks per-instance state like upgrade level, uses remaining, etc.
## Multiple instances can exist of the same CardData.

# Reference to the card definition
var data: CardData = null

# Instance-specific state
var upgrade_level: int = 0
var uses_remaining: int = -1        # -1 = unlimited
var is_exhausted: bool = false      # Some cards exhaust after use
var is_locked: bool = false         # Locked cards can't be played

# Temporary modifiers for this instance
var temp_chips_bonus: int = 0
var temp_mult_bonus: float = 0.0

# Unique instance ID for tracking
var instance_id: int = 0
static var _next_instance_id: int = 0


func _init(card_data: CardData = null) -> void:
	if card_data:
		data = card_data
		if data.max_uses > 0:
			uses_remaining = data.max_uses
	instance_id = _next_instance_id
	_next_instance_id += 1


# --- Factory ---

static func create_from_data(card_data: CardData) -> CardInstance:
	"""Create a new card instance from card data"""
	var instance = CardInstance.new()
	instance.data = card_data
	return instance


static func create_upgraded(card_data: CardData, level: int) -> CardInstance:
	"""Create an upgraded card instance"""
	var instance = CardInstance.new()
	instance.data = card_data
	instance.upgrade_level = clampi(level, 0, card_data.max_upgrade_level)
	return instance


# --- State Management ---

func upgrade() -> bool:
	"""Upgrade this card. Returns true if successful."""
	if data == null or not data.can_upgrade:
		return false
	if upgrade_level >= data.max_upgrade_level:
		return false
	
	upgrade_level += 1
	return true


func use() -> bool:
	"""Use this card (for limited-use cards). Returns true if card still has uses."""
	if uses_remaining == -1:
		return true  # Unlimited
	
	uses_remaining -= 1
	if uses_remaining <= 0:
		is_exhausted = true
		return false
	return true


func reset_temp_modifiers() -> void:
	"""Reset temporary modifiers (called between shots)"""
	temp_chips_bonus = 0
	temp_mult_bonus = 0.0


func can_play() -> bool:
	"""Check if this card can currently be played"""
	if data == null:
		return false
	if is_exhausted:
		return false
	if is_locked:
		return false
	if uses_remaining == 0:
		return false
	return true


# --- Effect Application ---

func apply_effects(context: ShotContext, phase: int) -> void:
	"""Apply all effects for this card at the given phase"""
	if data == null or data.effects.is_empty():
		return
	
	for effect in data.effects:
		if effect == null or not effect is CardEffect:
			continue
		
		# Check if effect applies at this phase
		if effect.apply_phase != phase:
			continue
		
		# Check trigger conditions
		if not effect.can_trigger(context):
			continue
		
		# Apply the effect
		match phase:
			0:  # BeforeAim
				effect.apply_before_aim(context, upgrade_level)
			1:  # OnAOE
				effect.apply_on_aoe(context, upgrade_level)
			2:  # OnLanding
				effect.apply_on_landing(context, upgrade_level)
			3:  # OnScoring
				effect.apply_on_scoring(context, upgrade_level)
			4:  # AfterShot
				effect.apply_after_shot(context, upgrade_level)


# --- Display Helpers ---

func get_display_name() -> String:
	if data == null:
		return "Unknown Card"
	
	var name = data.card_name
	if upgrade_level > 0:
		name += " +" + str(upgrade_level)
	return name


func get_full_description() -> String:
	"""Get complete description including all effect descriptions"""
	if data == null:
		return ""
	
	var parts: Array[String] = []
	
	# Base description
	if not data.description.is_empty():
		parts.append(data.description)
	
	# Add effect descriptions
	for effect in data.effects:
		if effect and effect is CardEffect:
			var effect_desc = effect.get_description(upgrade_level)
			if not effect_desc.is_empty():
				parts.append(effect_desc)
	
	return "\n".join(parts)


func get_description() -> String:
	if data == null:
		return ""
	return data.get_formatted_description(upgrade_level)


func get_rarity_color() -> Color:
	if data == null:
		return Color.WHITE
	return data.get_rarity_color()


# --- Serialization ---

func to_dict() -> Dictionary:
	"""Serialize card instance for saving"""
	return {
		"card_id": data.card_id if data else "",
		"upgrade_level": upgrade_level,
		"uses_remaining": uses_remaining,
		"is_exhausted": is_exhausted,
		"is_locked": is_locked,
		"instance_id": instance_id
	}


static func from_dict(dict: Dictionary, card_registry: Dictionary) -> CardInstance:
	"""Deserialize card instance from save data"""
	var card_id = dict.get("card_id", "")
	if card_id.is_empty() or not card_registry.has(card_id):
		return null
	
	var instance = CardInstance.new()
	instance.data = card_registry[card_id]
	instance.upgrade_level = dict.get("upgrade_level", 0)
	instance.uses_remaining = dict.get("uses_remaining", -1)
	instance.is_exhausted = dict.get("is_exhausted", false)
	instance.is_locked = dict.get("is_locked", false)
	instance.instance_id = dict.get("instance_id", _next_instance_id)
	_next_instance_id = maxi(_next_instance_id, instance.instance_id + 1)
	return instance
