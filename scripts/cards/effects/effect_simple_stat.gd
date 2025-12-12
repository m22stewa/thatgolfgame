extends CardEffect
class_name EffectSimpleStat

## Generic effect to modify simple stats in ShotContext.
## Supports: distance_mod, accuracy_mod, roll_mod, aoe_radius, curve_strength

@export_enum("distance_mod", "accuracy_mod", "roll_mod", "aoe_radius", "curve_strength") var target_stat: String = "distance_mod"
@export var value: int = 1
@export var set_mode: bool = false # If true, sets the value instead of adding

func _init() -> void:
	effect_id = "simple_stat"
	effect_name = "Stat Modifier"
	# Phase depends on stat - all apply before aim for simplicity
	apply_phase = 0 
	trigger_condition = 0

func apply_before_aim(context: ShotContext, _upgrade: int = 0) -> void:
	print("[EffectSimpleStat] Applying %s: value=%d, set_mode=%s" % [target_stat, value, set_mode])
	print("[EffectSimpleStat] Before: distance_mod=%d, accuracy_mod=%d, roll_mod=%d, aoe_radius=%d" % [
		context.distance_mod, context.accuracy_mod, context.roll_mod, context.aoe_radius
	])
	
	match target_stat:
		"distance_mod":
			if set_mode:
				context.distance_mod = value
			else:
				context.distance_mod += value
		"accuracy_mod":
			if set_mode:
				context.accuracy_mod = value
			else:
				context.accuracy_mod += value
		"roll_mod":
			if set_mode:
				context.roll_mod = value
			else:
				context.roll_mod += value
		"aoe_radius":
			if set_mode:
				context.aoe_radius = value
			else:
				context.aoe_radius += value
		"curve_strength":
			if set_mode:
				context.curve_strength = value
			else:
				context.curve_strength += value
		_:
			push_warning("[EffectSimpleStat] Unknown target_stat: %s" % target_stat)
	
	print("[EffectSimpleStat] After: distance_mod=%d, accuracy_mod=%d, roll_mod=%d, aoe_radius=%d" % [
		context.distance_mod, context.accuracy_mod, context.roll_mod, context.aoe_radius
	])

func get_description(_upgrade_level: int = 0) -> String:
	var op = "+" if value >= 0 else ""
	var stat_name = target_stat.replace("_mod", "").replace("_", " ").capitalize()
	if target_stat == "aoe_radius":
		stat_name = "AOE Radius"
	return "%s %s%d" % [stat_name, op, value]
