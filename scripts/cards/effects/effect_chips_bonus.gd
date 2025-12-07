extends CardEffect
class_name EffectChipsBonus

## Adds flat chips to the score.
## Common effect for basic scoring cards.

@export var bonus_chips: int = 10


func _init() -> void:
	effect_id = "chips_bonus"
	effect_name = "Chips Bonus"
	apply_phase = 3  # OnScoring
	trigger_condition = 0  # Always


func apply_on_scoring(context: ShotContext, upgrade_level: int = 0) -> void:
	var scaled_bonus = bonus_chips + int(upgrade_level * value_per_upgrade)
	context.chips += scaled_bonus


func get_description(upgrade_level: int = 0) -> String:
	var scaled_bonus = bonus_chips + int(upgrade_level * value_per_upgrade)
	return "+%d Chips" % scaled_bonus
