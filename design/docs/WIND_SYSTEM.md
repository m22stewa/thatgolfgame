# Wind System Design for Godot Golf Game

## Overview
A wind system that adds strategic depth to golf shots through directional forces that affect ball trajectory, distance, and accuracy. Wind interacts with club loft, shot direction, and elevation to create realistic flight dynamics.

---

## 1. Wind Parameters

### 1.1 Core Wind Data Structure
```gdscript
class_name WindData
extends RefCounted

var enabled: bool = false              # Whether wind is active this hole
var direction: Vector2 = Vector2.ZERO  # Normalized 2D vector (world space)
var speed_kmh: float = 0.0             # Base wind speed in km/h
var gustiness: float = 0.0             # Variability factor (0.0 - 1.0)

# Computed per-shot (cached for consistency during a single shot)
var _current_gust_speed: float = 0.0
var _current_gust_angle: float = 0.0
```

### 1.2 Direction System
**8-directional cardinal system** (easier for players to understand):
```gdscript
enum WindDirection {
	NONE = -1,  # No wind
	N = 0,      # North (negative Z in Godot)
	NE = 1,     # Northeast
	E = 2,      # East (positive X)
	SE = 3,     # Southeast
	S = 4,      # South (positive Z)
	SW = 5,     # Southwest
	W = 6,      # West (negative X)
	NW = 7      # Northwest
}

# Convert enum to normalized Vector2
const DIRECTION_VECTORS = {
	WindDirection.N:  Vector2(0, -1),
	WindDirection.NE: Vector2(0.707, -0.707),
	WindDirection.E:  Vector2(1, 0),
	WindDirection.SE: Vector2(0.707, 0.707),
	WindDirection.S:  Vector2(0, 1),
	WindDirection.SW: Vector2(-0.707, 0.707),
	WindDirection.W:  Vector2(-1, 0),
	WindDirection.NW: Vector2(-0.707, -0.707),
}
```

### 1.3 Parameter Ranges (Based on Real Golf Game Standards)

| Parameter | Min | Max | Typical Range | Description |
|-----------|-----|-----|---------------|-------------|
| **speed_kmh** | 0 | 60 | 5-30 km/h | Light breeze to strong gale |
| **gustiness** | 0.0 | 1.0 | 0.0-0.5 | 0 = steady, 1 = highly variable |

**Wind Speed Categories:**
- **0-10 km/h**: Light breeze (minimal effect)
- **10-20 km/h**: Moderate wind (noticeable)
- **20-30 km/h**: Strong wind (significant impact)
- **30-40 km/h**: Very strong (major challenge)
- **40+ km/h**: Extreme conditions (rare, special holes)

**Conversion:** 1 km/h ≈ 0.621 mph, so 20 km/h ≈ 12 mph

---

## 2. Wind Effects on Shots

### 2.1 Core Formula: Wind Force Calculation
```gdscript
func calculate_wind_effect(shot_vector: Vector2, club_loft: int, shot_distance: float, wind_data: WindData) -> Dictionary:
	"""
	Returns: { distance_modifier: float, lateral_drift: Vector2, accuracy_penalty: int }
	"""
	if not wind_data.enabled:
		return { "distance_modifier": 0.0, "lateral_drift": Vector2.ZERO, "accuracy_penalty": 0 }
	
	# Apply gustiness variation (done once per shot, not per frame)
	var effective_speed = wind_data.speed_kmh + randf_range(-wind_data.gustiness * 10, wind_data.gustiness * 10)
	effective_speed = max(0, effective_speed)  # Never negative
	
	var effective_direction = wind_data.direction.rotated(randf_range(-wind_data.gustiness * 0.3, wind_data.gustiness * 0.3))
	effective_direction = effective_direction.normalized()
	
	# 1. Calculate headwind/tailwind component
	var shot_direction = shot_vector.normalized()
	var alignment = shot_direction.dot(effective_direction)  # -1 (headwind) to +1 (tailwind)
	
	# 2. Calculate crosswind component
	var crosswind = shot_direction.rotated(PI/2).dot(effective_direction)  # -1 (left) to +1 (right)
	
	# 3. Loft multiplier (higher loft = more wind sensitivity)
	# Loft scale: 1 (driver) = 1.0x, 3 (mid-iron) = 1.4x, 5 (wedge) = 2.0x
	var loft_mult = 1.0 + (club_loft - 1) * 0.25
	
	# 4. Distance multiplier (longer shots = more wind exposure time)
	# Base: 10 tiles = 1.0x, 20 tiles = 1.5x
	var distance_mult = sqrt(shot_distance / 10.0)
	
	# 5. HEADWIND/TAILWIND: Affects distance (tiles)
	# Formula: -0.15 tiles per km/h headwind, +0.10 tiles per km/h tailwind
	# (headwinds hurt more than tailwinds help - realistic)
	var wind_distance_mod = 0.0
	if alignment < 0:  # Headwind
		wind_distance_mod = alignment * effective_speed * 0.15 * loft_mult * distance_mult
	else:  # Tailwind
		wind_distance_mod = alignment * effective_speed * 0.10 * loft_mult * distance_mult
	
	# 6. CROSSWIND: Lateral drift (perpendicular tiles)
	# Formula: 0.08 tiles per km/h crosswind
	var lateral_drift_amount = crosswind * effective_speed * 0.08 * loft_mult * distance_mult
	var lateral_drift_vector = shot_direction.rotated(PI/2) * lateral_drift_amount
	
	# 7. ACCURACY PENALTY: High wind increases AOE
	# Add +1 AOE ring per 20 km/h effective wind (rounded)
	var accuracy_penalty = int(effective_speed / 20.0)
	if wind_data.gustiness > 0.3:
		accuracy_penalty += 1  # Extra penalty for gusty conditions
	
	return {
		"distance_modifier": wind_distance_mod,       # Tiles to add/subtract from distance
		"lateral_drift": lateral_drift_vector,        # Vector2 offset in hex space
		"accuracy_penalty": accuracy_penalty,         # AOE rings to add
		"effective_speed": effective_speed,           # For UI display
		"effective_direction": effective_direction    # For UI display
	}
```

### 2.2 Practical Examples

**Example 1: Driver into 20 km/h headwind**
- Club: Driver (loft 1, distance 22 tiles)
- Wind: 20 km/h directly against shot
- Result: -6 tiles distance loss (22 → 16 tiles)

**Example 2: Wedge into 15 km/h tailwind**
- Club: Sand Wedge (loft 5, distance 9 tiles)
- Wind: 15 km/h with shot
- Result: +2.5 tiles distance gain (9 → 11.5 tiles)

**Example 3: 7-Iron with 25 km/h crosswind**
- Club: 7-Iron (loft 3, distance 14 tiles)
- Wind: 25 km/h perpendicular to shot
- Result: ~3 tiles lateral drift + 1 AOE ring penalty

### 2.3 Integration with Shot Context

Add to `ShotContext` class:
```gdscript
# Wind data
var wind_data: WindData = null           # Reference to current hole's wind
var wind_distance_mod: float = 0.0       # Calculated wind effect on distance
var wind_lateral_drift: Vector2 = Vector2.ZERO  # Calculated lateral push
var wind_accuracy_penalty: int = 0       # AOE rings added by wind
```

Apply in `shot_manager.gd` during `_apply_modifiers_before_aim()`:
```gdscript
func _apply_wind_modifiers(context: ShotContext) -> void:
	if not context.wind_data or not context.wind_data.enabled:
		return
	
	# Get shot vector (from start to aim)
	var start_pos = hole_controller.hex_to_world(context.start_tile)
	var aim_pos = hole_controller.hex_to_world(context.aim_tile)
	var shot_vector = Vector2(aim_pos.x - start_pos.x, aim_pos.z - start_pos.z)
	
	# Get club loft
	var club_loft = hole_controller.CLUB_STATS[hole_controller.current_club]["loft"]
	var shot_distance = shot_vector.length() / TILE_SIZE  # Convert to tiles
	
	# Calculate wind effects
	var wind_effect = calculate_wind_effect(shot_vector, club_loft, shot_distance, context.wind_data)
	
	# Apply to context
	context.wind_distance_mod = wind_effect["distance_modifier"]
	context.wind_lateral_drift = wind_effect["lateral_drift"]
	context.wind_accuracy_penalty = wind_effect["accuracy_penalty"]
	
	# Modify shot parameters
	context.power_mod += wind_effect["distance_modifier"]
	context.accuracy_mod += wind_effect["accuracy_penalty"]
```

---

## 3. Wind Generation & Storage

### 3.1 Per-Hole Wind Generation
```gdscript
func generate_hole_wind(hole_difficulty: int, seed_value: int = 0) -> WindData:
	"""
	Generate wind conditions for a hole based on difficulty.
	hole_difficulty: 1-10 (1=easy, 10=expert)
	"""
	var rng = RandomNumberGenerator.new()
	if seed_value > 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	
	var wind = WindData.new()
	
	# Probability of wind (increases with difficulty)
	# Easy holes: 30% chance, Hard holes: 80% chance
	var wind_chance = 0.2 + (hole_difficulty * 0.06)
	wind.enabled = rng.randf() < wind_chance
	
	if not wind.enabled:
		return wind
	
	# Random direction (8-directional)
	var dir_enum = rng.randi_range(0, 7)
	wind.direction = DIRECTION_VECTORS[dir_enum]
	
	# Speed scales with difficulty
	# Easy: 5-15 km/h, Medium: 10-25 km/h, Hard: 15-35 km/h
	var min_speed = 5 + (hole_difficulty * 1.0)
	var max_speed = 15 + (hole_difficulty * 2.0)
	wind.speed_kmh = rng.randf_range(min_speed, max_speed)
	
	# Gustiness scales with difficulty
	# Easy: 0-0.2, Hard: 0.2-0.6
	wind.gustiness = rng.randf_range(0.0, 0.2 + hole_difficulty * 0.04)
	
	return wind
```

### 3.2 Storage in Hex Grid
Add to `hex_grid.gd`:
```gdscript
# Wind data for current hole
var current_wind: WindData = null

func setup_new_hole() -> void:
	# ... existing hole setup ...
	
	# Generate wind for this hole
	current_wind = generate_hole_wind(current_hole_difficulty, current_hole_seed)
	
	# Update UI to show wind
	_update_wind_display()
```

### 3.3 Persistence (Optional - for run saving)
```gdscript
func serialize_wind() -> Dictionary:
	if not current_wind or not current_wind.enabled:
		return { "enabled": false }
	
	return {
		"enabled": true,
		"direction_x": current_wind.direction.x,
		"direction_y": current_wind.direction.y,
		"speed_kmh": current_wind.speed_kmh,
		"gustiness": current_wind.gustiness
	}

func deserialize_wind(data: Dictionary) -> WindData:
	var wind = WindData.new()
	wind.enabled = data.get("enabled", false)
	if wind.enabled:
		wind.direction = Vector2(data["direction_x"], data["direction_y"])
		wind.speed_kmh = data["speed_kmh"]
		wind.gustiness = data["gustiness"]
	return wind
```

---

## 4. UI Display

### 4.1 Wind Indicator Components

**Minimal HUD Elements:**
1. **Wind Arrow**: Rotating arrow showing direction (world-space)
2. **Wind Speed**: Text display "15 km/h" or "12 mph"
3. **Gustiness Indicator**: Icon or color (calm/breezy/gusty)

**Recommended Layout:**
```
┌─────────────────────────┐
│   Wind: 18 km/h  ↗️      │  ← Arrow rotates to show direction
│   Gusts: Moderate       │  ← Optional gustiness text
└─────────────────────────┘
```

### 4.2 Implementation Example
```gdscript
@onready var wind_container: Control = %WindDisplay
@onready var wind_arrow: TextureRect = %WindArrow
@onready var wind_speed_label: Label = %WindSpeed
@onready var wind_gust_label: Label = %WindGust

func _update_wind_display() -> void:
	if not current_wind or not current_wind.enabled:
		wind_container.visible = false
		return
	
	wind_container.visible = true
	
	# Rotate arrow to match wind direction
	# Convert Vector2(x, z) to rotation angle
	var angle = atan2(current_wind.direction.y, current_wind.direction.x)
	wind_arrow.rotation = angle
	
	# Display speed
	wind_speed_label.text = "%d km/h" % int(current_wind.speed_kmh)
	
	# Gustiness indicator
	if current_wind.gustiness < 0.2:
		wind_gust_label.text = "Calm"
		wind_gust_label.modulate = Color.GREEN
	elif current_wind.gustiness < 0.5:
		wind_gust_label.text = "Breezy"
		wind_gust_label.modulate = Color.YELLOW
	else:
		wind_gust_label.text = "Gusty"
		wind_gust_label.modulate = Color.ORANGE
```

### 4.3 Advanced: Shot Preview with Wind
Show predicted landing zone accounting for wind drift:
```gdscript
func preview_wind_affected_landing(aim_tile: Vector2i, context: ShotContext) -> Vector2i:
	"""Return the tile the ball will likely land on with wind applied"""
	if not context.wind_lateral_drift or context.wind_lateral_drift.length() < 0.1:
		return aim_tile
	
	# Convert aim tile to world position
	var aim_world = hex_to_world(aim_tile)
	
	# Apply wind drift
	var drifted_world = Vector3(
		aim_world.x + context.wind_lateral_drift.x,
		aim_world.y,
		aim_world.z + context.wind_lateral_drift.y
	)
	
	# Convert back to hex tile
	return world_to_hex(drifted_world)
```

---

## 5. Special Mechanics

### 5.1 Elevation Interaction
Wind is stronger at higher elevations:
```gdscript
func get_elevation_wind_multiplier(elevation: float) -> float:
	# +0.1x per elevation unit above sea level
	return 1.0 + max(0, elevation * 0.1)
```

### 5.2 Wind Cards/Modifiers
Example card effects:
- **"Windbreaker"**: Reduce wind effects by 50%
- **"Tailwind Master"**: Double tailwind benefits, normal headwind penalty
- **"Eye of the Storm"**: Ignore gustiness (use base wind only)
- **"Weathervane"**: Show exact landing tile with wind preview

### 5.3 Wind Zones (Advanced)
Per-tile wind modifiers for special hazards:
```gdscript
# In HexTile class
var wind_modifier: float = 1.0  # Multiplier for wind effects on this tile

# Example: Trees reduce wind
if tile.surface_type == SurfaceType.TREE:
	tile.wind_modifier = 0.5  # 50% wind reduction
```

---

## 6. Implementation Checklist

### Phase 1: Core Wind System
- [ ] Create `WindData` class in `scripts/wind_data.gd`
- [ ] Add wind generation function to `hex_grid.gd`
- [ ] Add `current_wind` variable to `hex_grid.gd`
- [ ] Generate wind in `setup_new_hole()`

### Phase 2: Shot Integration
- [ ] Add wind fields to `ShotContext`
- [ ] Add `calculate_wind_effect()` function to `shot_manager.gd` or new `wind_system.gd`
- [ ] Call wind calculation in `_apply_modifiers_before_aim()`
- [ ] Apply `wind_distance_mod` to `power_mod`
- [ ] Apply `wind_accuracy_penalty` to `accuracy_mod`

### Phase 3: UI Display
- [ ] Create wind indicator UI scene
- [ ] Add wind arrow texture/icon
- [ ] Implement `_update_wind_display()` function
- [ ] Show/hide based on `current_wind.enabled`
- [ ] Update display when hole changes

### Phase 4: Testing & Tuning
- [ ] Test with driver into headwind (expect major distance loss)
- [ ] Test with wedge into crosswind (expect lateral drift)
- [ ] Verify loft scaling (wedges more affected than driver)
- [ ] Adjust multipliers for game feel

### Phase 5: Polish (Optional)
- [ ] Add wind sound effects (whoosh, gusts)
- [ ] Add visual wind particles/grass waving
- [ ] Implement shot preview with wind drift
- [ ] Add wind-themed cards/modifiers

---

## 7. Recommended Starting Values

For initial implementation, use these conservative values:

```gdscript
# Conservative wind settings for initial testing
const WIND_SETTINGS = {
	"headwind_tiles_per_kmh": 0.12,  # Start gentle
	"tailwind_tiles_per_kmh": 0.08,
	"crosswind_tiles_per_kmh": 0.06,
	"loft_scaling": 0.20,            # 20% increase per loft level
	"distance_scaling": 0.8,         # sqrt(distance/10) * 0.8
	"aoe_penalty_threshold": 25,     # +1 AOE per 25 km/h (instead of 20)
}
```

**Why conservative?** You can always increase wind effects later. Starting too strong will frustrate players.

---

## 8. Future Enhancements

1. **Weather Patterns**: Multiple holes share wind direction (simulate front passing through)
2. **Wind Forecast**: Show next hole's wind in advance
3. **Wind Streaks**: Bonus multiplier for consecutive holes played in strong wind
4. **Hurricane Holes**: Special challenge holes with extreme wind (40+ km/h)
5. **Wind Shader**: Visual grass/flag animation based on wind direction
6. **Club Recommendations**: UI suggests best club for current wind conditions

---

## Summary: Quick Reference

**Key Formulas:**
- Distance Loss (headwind): `-0.15 × speed_kmh × loft_mult × distance_mult`
- Distance Gain (tailwind): `+0.10 × speed_kmh × loft_mult × distance_mult`
- Lateral Drift: `0.08 × speed_kmh × crosswind × loft_mult × distance_mult`
- Loft Multiplier: `1.0 + (loft - 1) × 0.25`
- AOE Penalty: `+1 ring per 20 km/h`

**Typical Wind Ranges:**
- Light: 5-15 km/h
- Medium: 15-25 km/h
- Strong: 25-40 km/h

**Integration Points:**
1. Generate wind in `hex_grid.setup_new_hole()`
2. Calculate effects in `shot_manager._apply_modifiers_before_aim()`
3. Apply to `context.power_mod` and `context.accuracy_mod`
4. Display in dedicated UI panel

**Data Structure:**
```gdscript
class WindData:
	enabled: bool
	direction: Vector2  # Normalized world-space vector
	speed_kmh: float    # 0-60 typical
	gustiness: float    # 0.0-1.0
```

This design balances realism with arcade gameplay, integrates cleanly with your existing modifier system, and provides clear player feedback. Start with conservative values and tune based on playtest feedback!
