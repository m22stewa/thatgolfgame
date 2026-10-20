extends CardEffect
class_name EffectStinger

## Shot-shape effect: a low stinger that bores through wind.
## Ignores wind, adds roll, extends the along-axis carry by one, tightens the
## footprint, and marks the shot so it can pass through TREE hexes during board
## resolution.

func _init() -> void:
	effect_id = "stinger"
	effect_name = "Stinger"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, _upgrade_level: int = 0) -> void:
	context.add_metadata("ignore_wind", true)
	# Internal flag so board resolution lets a stinger pass through trees.
	context.add_metadata("stinger", true)
	context.roll_mod += 2
	# Extend the along-axis carry by one tile.
	context.add_metadata("along_axis_add", int(context.get_metadata("along_axis_add", 0)) + 1)
	context.spread_mod -= 1


func get_description(_upgrade_level: int = 0) -> String:
	return "Stinger: ignores wind, +2 roll, +1 carry, passes trees"
