extends CardEffect
class_name EffectAOEExpand

## Expands the AOE radius for landing zone.
## Useful for accuracy/control builds.

@export var radius_bonus: int = 1


func _init() -> void:
	effect_id = "aoe_expand"
	effect_name = "AOE Expand"
	apply_phase = 1  # OnAOE
	trigger_condition = 0  # Always


func apply_on_aoe(context: ShotContext, upgrade_level: int = 0) -> void:
	var bonus = radius_bonus + int(upgrade_level * value_per_upgrade)
	context.aoe_radius += bonus


func get_description(upgrade_level: int = 0) -> String:
	var bonus = radius_bonus + int(upgrade_level * value_per_upgrade)
	return "+%d AOE Radius" % bonus
