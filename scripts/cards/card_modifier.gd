extends RefCounted
class_name CardModifier

## CardModifier - Bridges a CardInstance with the ModifierManager system.
## Wraps a card's effects so they can participate in the shot lifecycle.
## Created when a card is played, removed after shot completes.

var card: CardInstance = null
var is_active: bool = true


func _init(card_instance: CardInstance = null) -> void:
	card = card_instance


# --- Modifier Interface Methods ---
# These are called by ModifierManager during shot phases

func apply_before_aim(context: ShotContext) -> void:
	"""Apply card effects during before-aim phase"""
	if not is_active or card == null:
		return
	card.apply_effects(context, 0)  # Phase 0 = BeforeAim


func apply_on_aoe(context: ShotContext) -> void:
	"""Apply card effects during AOE computation phase"""
	if not is_active or card == null:
		return
	card.apply_effects(context, 1)  # Phase 1 = OnAOE


func apply_on_landing(context: ShotContext) -> void:
	"""Apply card effects when ball lands"""
	if not is_active or card == null:
		return
	card.apply_effects(context, 2)  # Phase 2 = OnLanding


func apply_on_scoring(context: ShotContext) -> void:
	"""Apply card effects during scoring"""
	if not is_active or card == null:
		return
	card.apply_effects(context, 3)  # Phase 3 = OnScoring


func apply_after_shot(context: ShotContext) -> void:
	"""Apply card effects after shot completes"""
	if not is_active or card == null:
		return
	card.apply_effects(context, 4)  # Phase 4 = AfterShot


# --- Utility ---

func get_modifier_type() -> String:
	"""Return type for filtering"""
	return "card"


func get_card_id() -> String:
	if card and card.data:
		return card.data.card_id
	return ""


func deactivate() -> void:
	"""Deactivate this modifier"""
	is_active = false
