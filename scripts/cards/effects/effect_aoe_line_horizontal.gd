extends CardEffect
class_name EffectAOELineHorizontal

## Sets AOE to a horizontal line pattern perpendicular to the shot direction.
## Distance determines how far the line extends: +2 = 2 tiles left, center, 2 tiles right (5 total).
## This represents draw/fade variance in the shot (lateral uncertainty).

@export var line_distance: int = 2  # Tiles in each direction from center


func _init() -> void:
	effect_id = "aoe_line_horizontal"
	effect_name = "Horizontal Line AOE"
	apply_phase = 0  # BeforeAim - sets up AOE parameters
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, upgrade_level: int = 0) -> void:
	# Set AOE shape to horizontal line (perpendicular to shot direction)
	context.aoe_shape = "line_horizontal"
	# Set the distance (how far the line extends in each direction)
	var distance = line_distance + int(upgrade_level * value_per_upgrade)
	context.aoe_radius = maxi(context.aoe_radius, distance)  # Use max to allow stacking


func get_description(upgrade_level: int = 0) -> String:
	var distance = line_distance + int(upgrade_level * value_per_upgrade)
	var total_tiles = distance * 2 + 1  # +N left, center, +N right
	return "Horizontal Line +%d (%d tiles: draw/fade variance)" % [distance, total_tiles]
