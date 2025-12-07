extends CardEffect
class_name EffectMultBonus

## Adds multiplicative bonus to the score.
## Powerful effect for rare cards.

@export var bonus_mult: float = 1.0


func _init() -> void:
	effect_id = "mult_bonus"
	effect_name = "Mult Bonus"
	apply_phase = 3  # OnScoring
	trigger_condition = 0  # Always


func apply_on_scoring(context: ShotContext, upgrade_level: int = 0) -> void:
	var scaled_bonus = bonus_mult + (upgrade_level * value_per_upgrade)
	context.mult += scaled_bonus


func get_description(upgrade_level: int = 0) -> String:
	var scaled_bonus = bonus_mult + (upgrade_level * value_per_upgrade)
	return "+%.1f Mult" % scaled_bonus
