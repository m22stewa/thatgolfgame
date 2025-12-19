extends CardEffect
class_name EffectAOEVerticalStrip

## DEPRECATED: Use EffectAOELineVertical instead.
## Sets AOE to vertical line pattern (along shot direction).
## Kept for backwards compatibility with existing card resources.

@export var strip_length: int = 3  # Total tiles in strip

func _init() -> void:
	effect_id = "aoe_vertical_strip"
	effect_name = "Vertical Strip"
	apply_phase = 0  # BeforeAim - to match new system
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, upgrade_level: int = 0) -> void:
	# Use the new line_vertical shape
	context.aoe_shape = "line_vertical"
	# Convert strip_length to distance (strip_length of 3 = 1 tile each direction)
	var length = strip_length + int(upgrade_level * value_per_upgrade)
	var distance = (length - 1) / 2  # 3 tiles = distance 1, 5 tiles = distance 2
	context.aoe_radius = maxi(context.aoe_radius, distance)


func get_description(upgrade_level: int = 0) -> String:
	var length = strip_length + int(upgrade_level * value_per_upgrade)
	return "%d-tile vertical strip" % length
