extends Resource
class_name HexTile

## HexTile - Data class for individual hex tile state.
## Stores terrain type, elevation, and tags for special effects.
## Can be attached to tile nodes or stored in a dictionary.

# Terrain/surface type (matches SurfaceType enum in hex_grid.gd)
@export var terrain_type: int = 1  # Default to FAIRWAY

# Elevation (Y height)
@export var elevation: float = 0.0

# Grid position
@export var col: int = 0
@export var row: int = 0

# Tags for special effects (e.g., "gold", "warp", "springboard", "cursed")
var tags: Dictionary = {}  # Using Dictionary as a set for O(1) lookup


# --- Tag Management ---

func add_tag(tag: String) -> void:
	"""Add a tag to this tile"""
	tags[tag] = true


func remove_tag(tag: String) -> void:
	"""Remove a tag from this tile"""
	tags.erase(tag)


func has_tag(tag: String) -> bool:
	"""Check if this tile has a specific tag"""
	return tags.has(tag)


func get_tags() -> Array:
	"""Get all tags as an array"""
	return tags.keys()


func clear_tags() -> void:
	"""Remove all tags"""
	tags.clear()


func set_tags(tag_array: Array) -> void:
	"""Set tags from an array"""
	tags.clear()
	for tag in tag_array:
		tags[tag] = true


# --- Position Helpers ---

func get_grid_position() -> Vector2i:
	"""Get grid position as Vector2i"""
	return Vector2i(col, row)


func set_grid_position(pos: Vector2i) -> void:
	"""Set grid position from Vector2i"""
	col = pos.x
	row = pos.y


func get_tile_id() -> String:
	"""Get unique string ID for this tile"""
	return "tile_%d_%d" % [col, row]


# --- Terrain Helpers ---

func is_playable() -> bool:
	"""Check if ball can land on this tile"""
	# TEE=0, FAIRWAY=1, ROUGH=2, DEEP_ROUGH=3, GREEN=4, SAND=5, WATER=6, TREE=7, FLAG=8
	return terrain_type != 6 and terrain_type != 7  # Not water or tree


func is_hazard() -> bool:
	"""Check if this is a hazard tile"""
	return terrain_type == 5 or terrain_type == 6  # Sand or water


func is_rough() -> bool:
	"""Check if this is any type of rough"""
	return terrain_type == 2 or terrain_type == 3  # Rough or deep rough


func is_scoring_area() -> bool:
	"""Check if this is a scoring area (green or flag)"""
	return terrain_type == 4 or terrain_type == 8  # Green or flag


func get_terrain_name() -> String:
	"""Get human-readable terrain name"""
	match terrain_type:
		0: return "Tee"
		1: return "Fairway"
		2: return "Rough"
		3: return "Deep Rough"
		4: return "Green"
		5: return "Sand"
		6: return "Water"
		7: return "Tree"
		8: return "Flag"
		_: return "Unknown"


# --- Serialization ---

func to_dict() -> Dictionary:
	"""Convert to dictionary for serialization"""
	return {
		"col": col,
		"row": row,
		"terrain_type": terrain_type,
		"elevation": elevation,
		"tags": tags.keys()
	}


static func from_dict(data: Dictionary) -> HexTile:
	"""Create HexTile from dictionary"""
	var tile = HexTile.new()
	tile.col = data.get("col", 0)
	tile.row = data.get("row", 0)
	tile.terrain_type = data.get("terrain_type", 1)
	tile.elevation = data.get("elevation", 0.0)
	tile.set_tags(data.get("tags", []))
	return tile


# --- Duplicate ---

func duplicate_tile() -> HexTile:
	"""Create a copy of this tile"""
	var copy = HexTile.new()
	copy.col = col
	copy.row = row
	copy.terrain_type = terrain_type
	copy.elevation = elevation
	copy.tags = tags.duplicate()
	return copy
