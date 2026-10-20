extends CardEffect
class_name EffectBumpRun

## Shot-shape effect: a low bump-and-run.
## Shortens the carry to the band minimum but adds a lot of roll.

func _init() -> void:
	effect_id = "bump_run"
	effect_name = "Bump-and-run"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, _upgrade_level: int = 0) -> void:
	# Set the along-axis carry to the band minimum. band_min is written to the
	# context before modifiers run (TurnController.rebuild).
	context.add_metadata("along_axis_override", context.band_min)
	context.roll_mod += 3
	context.spread_mod -= 1


func get_description(_upgrade_level: int = 0) -> String:
	return "Bump-and-run: short carry, +3 roll, tighter spread"
