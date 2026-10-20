extends CardEffect
class_name EffectIgnoreWind

## Shot-shape effect: the shot ignores wind entirely.
## The footprint builder zeroes both the crosswind shift and the head/tail
## distance when metadata["ignore_wind"] is set.

func _init() -> void:
	effect_id = "ignore_wind"
	effect_name = "Ignore Wind"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, _upgrade_level: int = 0) -> void:
	context.add_metadata("ignore_wind", true)


func get_description(_upgrade_level: int = 0) -> String:
	return "Shot ignores wind this turn"
