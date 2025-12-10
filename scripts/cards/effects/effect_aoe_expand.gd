extends CardEffect
class_name EffectAOEExpand

## Modifies the AOE (accuracy) for landing zone.
## Negative = more accurate (fewer rings), Positive = less accurate (more rings)

@export var accuracy_change: int = -1  # -1 = more accurate, +1 = less accurate


func _init() -> void:
	effect_id = "aoe_expand"
	effect_name = "Accuracy Modifier"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, upgrade_level: int = 0) -> void:
	var change = accuracy_change - upgrade_level  # Upgrades make it more accurate (if negative)
	context.accuracy_mod += change


func get_description(upgrade_level: int = 0) -> String:
	var change = accuracy_change - upgrade_level
	if change < 0:
		return "Accuracy %d (more accurate)" % change
	elif change > 0:
		return "Accuracy +%d (less accurate)" % change
	else:
		return "No accuracy change"
