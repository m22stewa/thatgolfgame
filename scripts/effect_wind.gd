extends Node
class_name WindModifier

## Wind Modifier - Applies wind effects to golf shots
## Simplified to use wind_curve (0-3 range) for lateral ball push during flight

var wind_system: WindSystem = null


func _init(wind_sys: WindSystem = null):
	wind_system = wind_sys


func apply_before_aim(context: ShotContext) -> void:
	"""Phase 2: Apply wind effects before player aims"""
	if not wind_system or not wind_system.enabled:
		return
	
	# Store wind info in context metadata for UI display
	context.add_metadata("wind_enabled", true)
	context.add_metadata("wind_direction", wind_system.get_direction_name())
	context.add_metadata("wind_strength", wind_system.strength)


func apply_on_shot(context: ShotContext, _hole_controller) -> void:
	"""Phase 7: Apply wind effects to the shot after aim is set"""
	if not wind_system or not wind_system.enabled:
		return
	
	if context.aim_tile.x < 0 or context.start_tile.x < 0:
		return
	
	# Calculate shot direction vector
	var shot_direction = Vector2(
		float(context.aim_tile.x - context.start_tile.x),
		float(context.aim_tile.y - context.start_tile.y)
	)
	
	if shot_direction.length() < 0.1:
		return  # No direction, skip wind
	
	# Calculate wind curve (tiles of lateral push)
	var wind_curve = wind_system.calculate_wind_curve(shot_direction)
	
	# Apply to context
	context.wind_curve = wind_curve
	
	# Store in metadata for UI display
	context.add_metadata("wind_curve", wind_curve)
