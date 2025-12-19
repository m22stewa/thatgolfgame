extends Node
class_name WindSystem

## Wind System - Handles wind generation and effects on golf shots
## Simplified to use 4 strength ranges (0-3) affecting ball curve

# Wind state
var enabled: bool = false
var direction_index: int = 0  # 0-7 for 8 cardinal/ordinal directions
var speed_kmh: float = 0.0    # 0-40 km/h range
var strength: int = 0          # 0-3 simplified strength range

# Direction vectors and names - Rotated 90° clockwise to align with hole, then 180° to fix N/S
# Hole runs W→E (left to right), so W points along fairway
# Note: Y is negated because Godot 2D has Y+ pointing down
const DIRECTIONS = [
	Vector2(-1, 0),   # 0: W (along hole direction)
	Vector2(-1, -1),  # 1: SW
	Vector2(0, -1),   # 2: S (right side of hole)
	Vector2(1, -1),   # 3: SE
	Vector2(1, 0),    # 4: E (against hole direction)
	Vector2(1, 1),    # 5: NE
	Vector2(0, 1),    # 6: N (left side of hole)
	Vector2(-1, 1)    # 7: NW
]

const DIRECTION_NAMES = ["W", "SW", "S", "SE", "E", "NE", "N", "NW"]

# Wind strength names for display
const STRENGTH_NAMES = ["Calm", "Light", "Moderate", "Strong"]


func generate_wind(difficulty: float = 0.5) -> void:
	"""Generate random wind conditions for a hole.
	difficulty: 0.0-1.0, affects wind probability and strength"""
	
	# Wind probability increases with difficulty (30% easy -> 80% hard)
	var wind_chance = lerp(0.3, 0.8, difficulty)
	enabled = randf() < wind_chance
	
	if not enabled:
		speed_kmh = 0.0
		direction_index = 0
		strength = 0
		return
	
	# Random direction (0-7)
	direction_index = randi() % 8
	
	# Wind speed scales with difficulty (5-15 easy -> 15-40 hard)
	var min_speed = lerp(5.0, 15.0, difficulty)
	var max_speed = lerp(15.0, 40.0, difficulty)
	speed_kmh = randf_range(min_speed, max_speed)
	
	# Calculate strength (0-3) from speed
	strength = _calculate_strength()


func _calculate_strength() -> int:
	"""Convert speed to simplified 0-3 strength range"""
	if not enabled or speed_kmh < 5:
		return 0  # Calm
	elif speed_kmh < 15:
		return 1  # Light
	elif speed_kmh < 28:
		return 2  # Moderate
	else:
		return 3  # Strong


func get_direction_vector() -> Vector2:
	"""Get normalized direction vector for current wind"""
	if not enabled or direction_index < 0 or direction_index >= DIRECTIONS.size():
		return Vector2.ZERO
	return DIRECTIONS[direction_index].normalized()


func get_direction_name() -> String:
	"""Get human-readable direction name"""
	if not enabled:
		return "CALM"
	if direction_index < 0 or direction_index >= DIRECTION_NAMES.size():
		return "?"
	return DIRECTION_NAMES[direction_index]


func get_strength_name() -> String:
	"""Get human-readable strength name"""
	return STRENGTH_NAMES[clampi(strength, 0, 3)]


func calculate_wind_curve(shot_direction: Vector2) -> int:
	"""Calculate wind curve effect on a shot.
	Returns: int tiles of lateral push (positive = right, negative = left)"""
	
	if not enabled or strength == 0:
		return 0
	
	var wind_vec = DIRECTIONS[direction_index].normalized()
	var shot_vec = shot_direction.normalized()
	
	# Calculate crosswind component (perpendicular to shot)
	var cross_component = wind_vec.cross(shot_vec)
	
	# Apply strength to crosswind
	# Strength 1 = max 1 tile, strength 2 = max 2 tiles, strength 3 = max 3 tiles
	var curve_tiles = int(round(cross_component * strength))
	
	# Clamp to strength range
	return clampi(curve_tiles, -strength, strength)


func get_display_text() -> String:
	"""Get formatted text for UI display"""
	if not enabled or speed_kmh < 5:
		return "Calm"
	return "%s\n%dkm/h" % [get_direction_name(), int(speed_kmh)]


func get_arrow_rotation() -> float:
	"""Get rotation in radians for wind arrow indicator.
	0 = pointing up (North), rotates clockwise"""
	if not enabled:
		return 0.0
	# Each direction is 45 degrees (PI/4 radians)
	return direction_index * (PI / 4.0)
