extends CardEffect
class_name EffectAOELineVertical

## Sets AOE to a vertical line pattern along the shot direction.
## Distance determines how far the line extends: +2 = 2 tiles short, center, 2 tiles long (5 total).
## This represents short/long variance in the shot (distance uncertainty).

@export var line_distance: int = 2  # Tiles in each direction from center


func _init() -> void:
	effect_id = "aoe_line_vertical"
	effect_name = "Vertical Line AOE"
	apply_phase = 0  # BeforeAim - sets up AOE parameters
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, upgrade_level: int = 0) -> void:
	# Set AOE shape to vertical line (along shot direction)
	context.aoe_shape = "line_vertical"
	# Set the distance (how far the line extends in each direction)
	var distance = line_distance + int(upgrade_level * value_per_upgrade)
	context.aoe_radius = maxi(context.aoe_radius, distance)  # Use max to allow stacking


func get_description(upgrade_level: int = 0) -> String:
	var distance = line_distance + int(upgrade_level * value_per_upgrade)
	var total_tiles = distance * 2 + 1  # +N forward, center, +N backward
	return "Vertical Line +%d (%d tiles: short/long variance)" % [distance, total_tiles]
