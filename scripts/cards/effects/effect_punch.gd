extends CardEffect
class_name EffectPunch

## Shot-shape effect: a low, boring punch shot.
## Adds roll, tightens the footprint, caps along-axis carry to the band center,
## and marks the shot so it can pass through TREE hexes during board resolution.

func _init() -> void:
	effect_id = "punch"
	effect_name = "Punch"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, _upgrade_level: int = 0) -> void:
	context.add_metadata("punch", true)
	context.roll_mod += 1
	context.spread_mod -= 1
	# Cap the along-axis carry distance to the band center. band_center is
	# written to the context before modifiers run (TurnController.rebuild).
	context.add_metadata("along_axis_cap", context.band_center)


func get_description(_upgrade_level: int = 0) -> String:
	return "Punch: low runner, +1 roll, tighter spread, passes trees"
