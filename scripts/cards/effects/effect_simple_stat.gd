extends CardEffect
class_name EffectSimpleStat

## Generic effect to modify simple stats in ShotContext.
## Supports: power_mod, roll_mod, aoe_radius

@export_enum("power_mod", "roll_mod", "aoe_radius") var target_stat: String = "power_mod"
@export var value: float = 1.0
@export var set_mode: bool = false # If true, sets the value instead of adding

func _init() -> void:
	effect_id = "simple_stat"
	effect_name = "Stat Modifier"
	# Phase depends on stat
	# power_mod -> BeforeAim (0)
	# aoe_radius -> OnAOE (1)
	# roll_mod -> OnLanding (2) (or BeforeAim, but context says lie info affects modifiers)
	apply_phase = 0 
	trigger_condition = 0

func apply_before_aim(context: ShotContext, _upgrade: int = 0) -> void:
	if target_stat == "power_mod":
		if set_mode:
			context.power_mod = value
		else:
			context.power_mod += value

func apply_on_aoe(context: ShotContext, _upgrade: int = 0) -> void:
	if target_stat == "aoe_radius":
		if set_mode:
			context.aoe_radius = int(value)
		else:
			context.aoe_radius += int(value)
			# Ensure minimum 0
			if context.aoe_radius < 0:
				context.aoe_radius = 0

func apply_on_landing(context: ShotContext, _upgrade: int = 0) -> void:
	if target_stat == "roll_mod":
		if set_mode:
			context.roll_mod = value
		else:
			context.roll_mod += value

func get_description(_upgrade_level: int = 0) -> String:
	var op = "+" if value >= 0 else ""
	return "%s %s%s" % [target_stat, op, str(value)]
