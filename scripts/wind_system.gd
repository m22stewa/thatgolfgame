extends Node
class_name WindSystem

## Wind System - Handles wind generation and effects on golf shots
## Integrated with the existing modifier system using integer modifiers

# Wind state
var enabled: bool = false
var direction_index: int = 0  # 0-7 for 8 cardinal/ordinal directions
var speed_kmh: float = 0.0    # 0-60 km/h range
var gustiness: float = 0.0    # 0.0-1.0 (variation amount)

# Direction vectors and names (N, NE, E, SE, S, SW, W, NW)
const DIRECTIONS = [
	Vector2(0, -1),   # 0: N
	Vector2(1, -1),   # 1: NE
	Vector2(1, 0),    # 2: E
	Vector2(1, 1),    # 3: SE
	Vector2(0, 1),    # 4: S
	Vector2(-1, 1),   # 5: SW
	Vector2(-1, 0),   # 6: W
	Vector2(-1, -1)   # 7: NW
]

const DIRECTION_NAMES = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

# Wind speed categories
enum WindStrength { CALM, LIGHT, MODERATE, STRONG, VERY_STRONG }


func generate_wind(difficulty: float = 0.5) -> void:
	"""Generate random wind conditions for a hole.
	difficulty: 0.0-1.0, affects wind probability and strength"""
	
	# Wind probability increases with difficulty (30% easy -> 80% hard)
	var wind_chance = lerp(0.3, 0.8, difficulty)
	enabled = randf() < wind_chance
	
	if not enabled:
		speed_kmh = 0.0
		direction_index = 0
		gustiness = 0.0
		return
	
	# Random direction (0-7)
	direction_index = randi() % 8
	
	# Wind speed scales with difficulty (5-15 easy -> 15-35 hard)
	var min_speed = lerp(5.0, 15.0, difficulty)
	var max_speed = lerp(15.0, 35.0, difficulty)
	speed_kmh = randf_range(min_speed, max_speed)
	
	# Gustiness (0.0-0.4, higher on harder holes)
	gustiness = randf_range(0.0, lerp(0.2, 0.4, difficulty))


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


func get_strength_category() -> WindStrength:
	"""Categorize wind strength"""
	if not enabled or speed_kmh < 5:
		return WindStrength.CALM
	elif speed_kmh < 13:
		return WindStrength.LIGHT
	elif speed_kmh < 26:
		return WindStrength.MODERATE
	elif speed_kmh < 41:
		return WindStrength.STRONG
	else:
		return WindStrength.VERY_STRONG


func apply_gustiness() -> int:
	"""Randomly shift wind direction due to gustiness.
	Returns modified direction_index for this specific shot."""
	if not enabled or gustiness <= 0.0:
		return direction_index
	
	# Gustiness causes ±1 direction shift
	if randf() < gustiness:
		var shift = 1 if randf() < 0.5 else -1
		return (direction_index + shift + 8) % 8
	
	return direction_index


func calculate_wind_effect(shot_direction: Vector2, club_loft: int) -> Dictionary:
	"""Calculate wind effects on a shot.
	Returns: {distance_mod: int, accuracy_mod: int, curve_mod: int}"""
	
	if not enabled or speed_kmh < 1.0:
		return {"distance_mod": 0, "accuracy_mod": 0, "curve_mod": 0}
	
	# Apply gustiness to get actual wind direction for this shot
	var actual_direction_index = apply_gustiness()
	var wind_vec = DIRECTIONS[actual_direction_index].normalized()
	
	# Normalize shot direction
	var shot_vec = shot_direction.normalized()
	
	# Calculate alignment: 1.0 = tailwind, -1.0 = headwind, 0.0 = crosswind
	var alignment = wind_vec.dot(shot_vec)
	
	# Loft factor: Higher loft = more wind effect (1.0 to 2.0)
	var loft_factor = 1.0 + (float(club_loft) / 5.0)
	
	# Base wind strength: 1 tile per ~10 km/h
	# Max speed is around 40 km/h -> 4 tiles
	var base_strength = speed_kmh / 10.0
	
	# Distance modifier (integer tiles)
	var distance_mod = 0
	if abs(alignment) > 0.1:
		# Calculate raw effect: strength * alignment * loft
		# Tailwind (+), Headwind (-)
		var raw_dist = base_strength * alignment * loft_factor
		distance_mod = int(round(raw_dist))
		
		# Clamp to +/- 4 range
		distance_mod = clampi(distance_mod, -4, 4)
	
	# Crosswind effect: perpendicular component
	var cross_component = abs(wind_vec.cross(shot_vec))
	
	# Curve modifier (integer tiles of lateral push)
	var curve_mod = 0
	if cross_component > 0.1:
		# Determine left or right push
		var cross_direction = sign(wind_vec.cross(shot_vec))
		var raw_curve = base_strength * cross_component * loft_factor * cross_direction
		curve_mod = int(round(raw_curve))
		
		# Clamp to +/- 4 range
		curve_mod = clampi(curve_mod, -4, 4)
	
	# Accuracy modifier: Strong crosswinds increase AOE
	var accuracy_mod = 0
	if cross_component > 0.5 and speed_kmh > 20:
		accuracy_mod = 1  # Add 1 AOE ring for strong crosswinds
	
	return {
		"distance_mod": distance_mod,
		"accuracy_mod": accuracy_mod,
		"curve_mod": curve_mod
	}


func get_display_text() -> String:
	"""Get formatted text for UI display"""
	if not enabled:
		return "Calm"
	return "%s %d km/h" % [get_direction_name(), int(speed_kmh)]


func get_arrow_rotation() -> float:
	"""Get rotation in radians for wind arrow indicator.
	0 = pointing up (North), rotates clockwise"""
	if not enabled:
		return 0.0
	# Each direction is 45 degrees (PI/4 radians)
	return direction_index * (PI / 4.0)
