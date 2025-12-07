extends Node
class_name WindModifier

## Wind Modifier - Applies wind effects to golf shots
## Plugs into the existing modifier system

var wind_system: WindSystem = null


func _init(wind_sys: WindSystem = null):
	wind_system = wind_sys


func apply_before_aim(context: ShotContext) -> void:
	"""Phase 2: Apply wind effects before player aims"""
	if not wind_system or not wind_system.enabled:
		return
	
	# Store wind info in context metadata for later use
	context.add_metadata("wind_enabled", true)
	context.add_metadata("wind_direction", wind_system.get_direction_name())
	context.add_metadata("wind_speed", wind_system.speed_kmh)


func apply_on_shot(context: ShotContext, hole_controller) -> void:
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
	
	# Get club loft from hole controller
	var club_loft = 2  # Default medium loft
	if hole_controller and hole_controller.has_method("get_current_club_loft"):
		club_loft = hole_controller.get_current_club_loft()
	
	# Calculate wind effects
	var wind_effects = wind_system.calculate_wind_effect(shot_direction, club_loft)
	
	# Apply modifiers to context
	context.power_mod += wind_effects.distance_mod
	context.accuracy_mod += wind_effects.accuracy_mod
	context.curve_mod += wind_effects.curve_mod
	
	# Store individual wind effects in metadata for UI display
	context.add_metadata("wind_distance_mod", wind_effects.distance_mod)
	context.add_metadata("wind_accuracy_mod", wind_effects.accuracy_mod)
	context.add_metadata("wind_curve_mod", wind_effects.curve_mod)
