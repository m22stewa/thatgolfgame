extends RefCounted
class_name ShotContext

## ShotContext - Data object carrying all state for a single shot
## Modifiers read/write fields during each shot lifecycle phase.

# References
var hole: Node3D = null          # Reference to current hole/grid controller
var ball: Node3D = null          # Reference to ball node

# Tile coordinates (Vector2i for grid positions)
var start_tile: Vector2i = Vector2i(-1, -1)   # Tile where shot starts
var aim_tile: Vector2i = Vector2i(-1, -1)     # Tile chosen by player
var landing_tile: Vector2i = Vector2i(-1, -1) # Final landing tile (resolved from AOE)

# Shot modifiers (additive: 0 = no change, +/- values modify)
# All int-based for simplicity and predictability
var distance_mod: int = 0                    # Distance modifier (e.g., -2 = 2 tiles less distance)
var accuracy_mod: int = 0                    # Accuracy modifier (e.g., +1 = 1 extra AOE ring)
var roll_mod: int = 0                        # Roll distance modifier (tiles)

# Wind effect on ball curve (0-3 range, applied during flight)
var wind_curve: int = 0                      # Tiles of lateral wind push

# AOE (Area of Effect) data
var aoe_tiles: Array[Vector2i] = []           # All tiles in AOE
var aoe_radius: int = 1                       # Base AOE radius in hex rings
var aoe_shape: String = "circle"              # Shape: "circle", "cone", "strip", etc.
var aoe_weights: Dictionary = {}              # Optional: tile -> weight for weighted landing

# Path data (tiles ball travels through)
var path_tiles: Array[Vector2i] = []          # Tiles along ball trajectory

# Physics modifiers
var max_bounces: int = 0                      # Allowed bounces
var bounce_count: int = 0                     # Actual bounces during shot
var roll_distance: int = 0                    # Total roll tiles after landing
var elevation_influence: float = 1.0          # How much elevation affects roll

# Curve for shaped shots (from cards)
var curve_strength: float = 0.0               # How much ball curves mid-flight (from cards)
var did_curve: bool = false                   # Whether ball curved this shot

# Scoring
var base_chips: int = 0                       # Base chips from distance/path
var chips: int = 0                            # Modified chips
var mult: float = 1.0                         # Multiplier
var final_score: int = 0                      # chips × mult (rounded)

# Shot tracking
var shot_index: int = 0                       # Which shot this is in the hole (0-indexed)

# Metadata for misc tags and flags
var metadata: Dictionary = {}                 # e.g. {"hit_hazard": true, "hit_water": false}


# --- Helper Methods ---

func reset() -> void:
	"""Reset context for a new shot (keeps hole/ball references)"""
	start_tile = Vector2i(-1, -1)
	aim_tile = Vector2i(-1, -1)
	landing_tile = Vector2i(-1, -1)
	distance_mod = 0
	accuracy_mod = 0
	roll_mod = 0
	wind_curve = 0
	aoe_tiles.clear()
	aoe_radius = 0  # Start at 0 (perfect accuracy)
	aoe_shape = "circle"
	aoe_weights.clear()
	path_tiles.clear()
	max_bounces = 0
	bounce_count = 0
	roll_distance = 0
	elevation_influence = 1.0
	curve_strength = 0.0
	did_curve = false
	base_chips = 0
	chips = 0
	mult = 1.0
	final_score = 0
	metadata.clear()


func add_metadata(key: String, value: Variant) -> void:
	metadata[key] = value


func get_metadata(key: String, default: Variant = null) -> Variant:
	return metadata.get(key, default)


func has_metadata(key: String) -> bool:
	return metadata.has(key)


func calculate_final_score() -> int:
	"""Calculate and store final score from chips and mult"""
	final_score = int(round(chips * mult))
	return final_score


func get_shot_distance() -> float:
	"""Calculate distance from start to aim tile in grid units"""
	if start_tile.x < 0 or aim_tile.x < 0:
		return 0.0
	var dx = aim_tile.x - start_tile.x
	var dy = aim_tile.y - start_tile.y
	return sqrt(dx * dx + dy * dy)


func get_shot_distance_yards() -> float:
	"""Calculate distance in yards (assuming 10 yards per cell)"""
	return get_shot_distance() * 10.0


func get_start_terrain() -> String:
	"""Get terrain type of starting tile"""
	return get_metadata("start_terrain", "Unknown")


func get_landing_terrain() -> String:
	"""Get terrain type of landing tile"""
	return get_metadata("landing_terrain", "Unknown")


func set_start_terrain(terrain: String) -> void:
	"""Set terrain type of starting tile"""
	add_metadata("start_terrain", terrain)


func set_landing_terrain(terrain: String) -> void:
	"""Set terrain type of landing tile"""
	add_metadata("landing_terrain", terrain)
