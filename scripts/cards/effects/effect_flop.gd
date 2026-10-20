extends CardEffect
class_name EffectFlop

## Shot-shape effect: a high flop shot that lands soft and dead.
## Forces the along-axis carry to the band minimum, kills roll, and tightens
## the footprint.

func _init() -> void:
	effect_id = "flop"
	effect_name = "Flop"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, _upgrade_level: int = 0) -> void:
	# Set the along-axis carry to the band minimum. band_min is written to the
	# context before modifiers run (TurnController.rebuild).
	context.add_metadata("along_axis_override", context.band_min)
	context.roll_mod -= 99
	context.spread_mod -= 1


func get_description(_upgrade_level: int = 0) -> String:
	return "Flop: shortest carry, no roll, tighter spread"
