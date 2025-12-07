extends CardEffect
class_name EffectAOEPerfect

## Sets AOE to perfect accuracy (radius 0) - ball lands exactly on aimed tile.
## This overrides all other accuracy modifiers.

func _init() -> void:
	effect_id = "aoe_perfect"
	effect_name = "Perfect Accuracy"
	apply_phase = 1  # OnAOE
	trigger_condition = 0  # Always


func apply_on_aoe(context: ShotContext, upgrade_level: int = 0) -> void:
	# Override AOE radius to 0 (perfect accuracy)
	context.aoe_radius = 0


func get_description(upgrade_level: int = 0) -> String:
	return "Perfect accuracy - ball lands exactly on target"
