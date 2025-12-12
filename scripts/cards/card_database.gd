extends Node
class_name CardDatabase

## CardDatabase - Loads and manages card definitions from JSON.
## Use this as an autoload/singleton for easy access across the game.

const CARDS_JSON_PATH = "res://resources/cards/cards.json"

# Cached card data by ID
var _cards: Dictionary = {}  # card_id -> CardData
var _swing_cards: Array[CardData] = []
var _modifier_cards: Array[CardData] = []
var _club_cards: Array[CardData] = []

var _loaded: bool = false


func _ready() -> void:
	load_cards()


func load_cards() -> void:
	"""Load all cards from the JSON file"""
	if _loaded:
		return
	
	var file = FileAccess.open(CARDS_JSON_PATH, FileAccess.READ)
	if not file:
		push_error("[CardDatabase] Failed to open %s" % CARDS_JSON_PATH)
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("[CardDatabase] JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	
	var data = json.data
	if not data is Dictionary:
		push_error("[CardDatabase] JSON root must be a dictionary")
		return
	
	# Load each category
	if "swing_cards" in data:
		for card_json in data["swing_cards"]:
			var card = _parse_card(card_json)
			if card:
				_cards[card.card_id] = card
				_swing_cards.append(card)
	
	if "modifier_cards" in data:
		for card_json in data["modifier_cards"]:
			var card = _parse_card(card_json)
			if card:
				_cards[card.card_id] = card
				_modifier_cards.append(card)
	
	if "club_cards" in data:
		for card_json in data["club_cards"]:
			var card = _parse_card(card_json)
			if card:
				_cards[card.card_id] = card
				_club_cards.append(card)
	
	_loaded = true
	print("[CardDatabase] Loaded %d cards (%d swing, %d modifier, %d club)" % [
		_cards.size(), _swing_cards.size(), _modifier_cards.size(), _club_cards.size()
	])


func _parse_card(json: Dictionary) -> CardData:
	"""Parse a single card from JSON into a CardData resource"""
	var card = CardData.new()
	
	# Required fields
	card.card_id = json.get("card_id", "")
	card.card_name = json.get("card_name", "Unknown")
	card.description = json.get("description", "")
	card.flavor_text = json.get("flavor_text", "")
	
	# Rarity (string to enum)
	var rarity_str = json.get("rarity", "COMMON").to_upper()
	match rarity_str:
		"COMMON": card.rarity = CardData.Rarity.COMMON
		"UNCOMMON": card.rarity = CardData.Rarity.UNCOMMON
		"RARE": card.rarity = CardData.Rarity.RARE
		"LEGENDARY": card.rarity = CardData.Rarity.LEGENDARY
	
	# Card type (string to enum)
	var type_str = json.get("card_type", "SHOT").to_upper()
	match type_str:
		"SHOT": card.card_type = CardData.CardType.SHOT
		"PASSIVE": card.card_type = CardData.CardType.PASSIVE
		"CONSUMABLE": card.card_type = CardData.CardType.CONSUMABLE
		"JOKER": card.card_type = CardData.CardType.JOKER
		"CLUB": card.card_type = CardData.CardType.CLUB
	
	# Optional fields
	card.target_club = json.get("target_club", "")
	card.play_cost = json.get("play_cost", 0)
	card.requires_target = json.get("requires_target", false)
	card.requires_shot_in_progress = json.get("requires_shot_in_progress", true)
	card.can_upgrade = json.get("can_upgrade", true)
	card.max_upgrade_level = json.get("max_upgrade_level", 3)
	card.max_uses = json.get("max_uses", -1)
	
	# Tags (array of strings)
	var tags_array = json.get("tags", [])
	card.tags = PackedStringArray(tags_array)
	
	# Parse effects
	var effects_json = json.get("effects", [])
	card.effects = _parse_effects(effects_json)
	
	return card


func _parse_effects(effects_json: Array) -> Array[Resource]:
	"""Parse effect definitions from JSON into CardEffect resources"""
	var effects: Array[Resource] = []
	
	for effect_data in effects_json:
		if not effect_data is Dictionary:
			continue
		
		var effect_type = effect_data.get("type", "")
		var effect: Resource = null
		
		match effect_type:
			# Simple stat modifiers
			"distance_mod", "accuracy_mod", "roll_mod", "aoe_radius", "curve_strength":
				effect = EffectSimpleStat.new()
				effect.target_stat = effect_type
				effect.value = effect_data.get("value", 0)
				effect.set_mode = effect_data.get("set_mode", false)
			
			# Power modifier (legacy name, maps to distance_mod)
			"power_modifier":
				effect = EffectSimpleStat.new()
				effect.target_stat = "distance_mod"
				# Convert multiplier to additive bonus (e.g., 1.15 -> +15)
				var mult = effect_data.get("value", 1.0)
				effect.value = int((mult - 1.0) * 100)
			
			# Curve shot
			"curve", "curve_shot":
				effect = EffectCurveShot.new()
				var curve_val = effect_data.get("value", 0.0)
				# Negative = draw, positive = fade
				if curve_val < 0:
					effect.curve_direction = 0  # Draw
					effect.curve_tiles = int(abs(curve_val) * 10)
				else:
					effect.curve_direction = 1  # Fade
					effect.curve_tiles = int(curve_val * 10)
			
			# Distance bonus
			"distance_bonus":
				effect = EffectDistanceBonus.new()
				effect.distance_mode = effect_data.get("mode", 0)
				effect.threshold_distance = effect_data.get("threshold", 10.0)
				effect.chips_per_unit = effect_data.get("chips_per_unit", 1.0)
				effect.flat_bonus_chips = effect_data.get("flat_chips", 0)
				effect.flat_bonus_mult = effect_data.get("flat_mult", 0.0)
			
			# Chips bonus
			"chips_bonus":
				effect = EffectChipsBonus.new()
				effect.bonus_chips = effect_data.get("value", 0)
			
			# Mult bonus
			"mult_bonus":
				effect = EffectMultBonus.new()
				effect.bonus_mult = effect_data.get("value", 0.0)
			
			# Roll modifier
			"roll_modifier":
				effect = EffectRollModifier.new()
				effect.roll_tiles = effect_data.get("value", 0)
			
			# Bounce bonus
			"bounce_bonus":
				effect = EffectBounceBonus.new()
				effect.extra_bounces = effect_data.get("value", 0)
			
			# Terrain bonus
			"terrain_bonus":
				effect = EffectTerrainBonus.new()
				effect.target_terrain = effect_data.get("terrain", "")
				effect.bonus_chips = effect_data.get("chips", 0)
				effect.bonus_mult = effect_data.get("mult", 0.0)
			
			_:
				push_warning("[CardDatabase] Unknown effect type: %s" % effect_type)
		
		if effect:
			effects.append(effect)
	
	return effects


# --- Public API ---

func get_card(card_id: String) -> CardData:
	"""Get a card by its ID"""
	if not _loaded:
		load_cards()
	return _cards.get(card_id, null)


func get_all_cards() -> Array[CardData]:
	"""Get all cards"""
	if not _loaded:
		load_cards()
	var all_cards: Array[CardData] = []
	all_cards.append_array(_swing_cards)
	all_cards.append_array(_modifier_cards)
	all_cards.append_array(_club_cards)
	return all_cards


func get_swing_cards() -> Array[CardData]:
	"""Get all swing/shot cards"""
	if not _loaded:
		load_cards()
	return _swing_cards.duplicate()


func get_modifier_cards() -> Array[CardData]:
	"""Get all modifier cards"""
	if not _loaded:
		load_cards()
	return _modifier_cards.duplicate()


func get_club_cards() -> Array[CardData]:
	"""Get all club cards"""
	if not _loaded:
		load_cards()
	return _club_cards.duplicate()


func get_cards_by_rarity(rarity: CardData.Rarity) -> Array[CardData]:
	"""Get all cards of a specific rarity"""
	if not _loaded:
		load_cards()
	var result: Array[CardData] = []
	for card in _cards.values():
		if card.rarity == rarity:
			result.append(card)
	return result


func get_cards_by_tag(tag: String) -> Array[CardData]:
	"""Get all cards with a specific tag"""
	if not _loaded:
		load_cards()
	var result: Array[CardData] = []
	for card in _cards.values():
		if card.has_tag(tag):
			result.append(card)
	return result


func reload() -> void:
	"""Force reload from JSON (useful for hot-reloading during development)"""
	_cards.clear()
	_swing_cards.clear()
	_modifier_cards.clear()
	_club_cards.clear()
	_loaded = false
	load_cards()
