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

# AOE (Area of Effect) data
var aoe_tiles: Array[Vector2i] = []           # All tiles in AOE
var aoe_radius: int = 1                       # Base AOE radius in hex rings
var aoe_shape: String = "circle"              # Shape: "circle", "cone", "strip", etc.
var aoe_weights: Dictionary = {}              # Optional: tile -> weight for weighted landing

# Path data (tiles ball travels through)
var path_tiles: Array[Vector2i] = []          # Tiles along ball trajectory

# Physics modifiers
var max_bounces: int = 0                      # Allowed bounces
var roll_distance: float = 0.0                # Roll after landing
var elevation_influence: float = 1.0          # How much elevation affects shot

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
	aoe_tiles.clear()
	aoe_radius = 1
	aoe_shape = "circle"
	aoe_weights.clear()
	path_tiles.clear()
	max_bounces = 0
	roll_distance = 0.0
	elevation_influence = 1.0
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
