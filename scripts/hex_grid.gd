extends Node3D

enum SurfaceType {
	TEE, FAIRWAY, ROUGH, DEEP_ROUGH, GREEN, SAND, WATER, TREE, FLAG
}

const FLAG = preload("uid://cu7517xrwfodv")
const TEEBOX_MODEL = preload("res://scenes/tiles/teebox-model.tscn")
const GOLFBALL = preload("uid://tohiatncovpm")

# Array of tree scenes to randomly choose from
# Add more tree .tscn files here for variety!
var TREE_SCENES: Array[PackedScene] = [
	preload("res://scenes/tiles/trees.tscn"),
	preload("res://scenes/tiles/trees-2.tscn"),  
	preload("res://scenes/tiles/trees-3.tscn"),
	# preload("res://scenes/trees/pine.tscn"),
	# preload("res://scenes/trees/birch.tscn"),
]

# Foliage models for course decoration (from res://models/features/)
var GRASS_MODELS: Array[PackedScene] = [
	preload("res://models/features/Grass_bush_high_011.fbx"),
	preload("res://models/features/Grass_bush_low_011.fbx"),
]
var BUSH_MODELS: Array[PackedScene] = [
	preload("res://models/features/Bush_average1.fbx"),
	preload("res://models/features/Bush_group_average1.fbx"),
]
var ROCK_MODELS: Array[PackedScene] = [
	preload("res://models/features/Stone_average_011.fbx"),
	preload("res://models/features/Stone_average_01_mossy1.fbx"),
	preload("res://models/features/Stone_group_average1.fbx"),
	preload("res://models/features/Stone_group_average_mossy1.fbx"),
]
var FLOWER_MODELS: Array[PackedScene] = [
	preload("res://models/features/Flower_bush_blue1.fbx"),
	preload("res://models/features/Flower_bush_red1.fbx"),
	preload("res://models/features/Flower_bush_white1.fbx"),
]

@onready var holelabel: Label = %Label
@onready var thefloor: CSGBox3D = %floor

var mesh_map = {
	SurfaceType.TEE: preload("res://scenes/tiles/teebox-mesh.tres"),
	SurfaceType.FAIRWAY: preload("res://scenes/tiles/fairway-mesh.tres"),
	SurfaceType.ROUGH: preload("res://scenes/tiles/rough-mesh.tres"),
	SurfaceType.DEEP_ROUGH: preload("res://scenes/tiles/deeprough-mesh.tres"),
	SurfaceType.GREEN: preload("res://scenes/tiles/green-mesh.tres"),
	SurfaceType.SAND: preload("res://scenes/tiles/sand-mesh.tres"),
	SurfaceType.WATER: preload("res://scenes/tiles/water-mesh.tres"),
	SurfaceType.TREE: preload("res://scenes/tiles/fairway-mesh.tres"),
	SurfaceType.FLAG: preload("res://scenes/tiles/green-mesh.tres"),
}

var grid_height: int = 40
var grid_width: int = 10

const TILE_SIZE := 1.0

# Conversion: 1 grid cell ≈ 10 yards (typical hex size for golf visualization)
const YARDS_PER_CELL := 10.0

# Par system - stores current hole info
var current_par: int = 4
var current_yardage: int = 0

# Par distance ranges (in yards) based on USGA guidelines
# Par 3: Under 260 yards (typically 100-250)
# Par 4: 240-490 yards (typically 280-450)  
# Par 5: 450-710 yards (typically 470-600)
const PAR_CONFIG = {
	3: {"min_yards": 100, "max_yards": 250, "min_width": 8, "max_width": 15},
	4: {"min_yards": 280, "max_yards": 450, "min_width": 12, "max_width": 25},
	5: {"min_yards": 470, "max_yards": 600, "min_width": 18, "max_width": 30}
}

# 2D array for grid data (col, row)
var grid: Array = []

# 2D array for elevation data (col, row) - stores Y height for each cell
var elevation: Array = []

# Golf ball reference
var golf_ball: Node3D = null
var tee_position: Vector3 = Vector3.ZERO

# Stored hole info text for label
var hole_info_text: String = ""

# Tile highlighting - using dictionaries keyed by cell Vector2i for individual access
var highlight_mesh: MeshInstance3D = null  # Main hover highlight
var aoe_highlights: Dictionary = {}  # Key: Vector2i cell position, Value: MeshInstance3D
var hovered_cell: Vector2i = Vector2i(-1, -1)

# Tile nodes storage - keyed by cell position for individual modification
var tile_nodes: Dictionary = {}  # Key: Vector2i cell position, Value: Node3D (the tile instance)

# Trajectory line
var trajectory_mesh: MeshInstance3D = null
var trajectory_shadow_mesh: MeshInstance3D = null  # Shadow line on ground
var trajectory_height: float = 5.0  # Peak height of ball flight arc (will vary by club)

# Target locking
var target_locked: bool = false
var locked_cell: Vector2i = Vector2i(-1, -1)
var locked_target_pos: Vector3 = Vector3.ZERO
var target_highlight_mesh: MeshInstance3D = null  # White highlight on active/locked cell

# Mini-map viewports and cameras
var top_viewport: SubViewport = null
var top_camera: Camera3D = null
var side_viewport: SubViewport = null
var side_camera: Camera3D = null
var top_viewport_container: SubViewportContainer = null
var side_viewport_container: SubViewportContainer = null

# Shot system components
var shot_manager: ShotManager = null
var modifier_manager: ModifierManager = null
var aoe_system: AOESystem = null

# Tile data storage - HexTile resources keyed by cell position
var tile_data: Dictionary = {}  # Key: Vector2i, Value: HexTile

# Elevation noise seed (randomized per generation)
var elevation_seed: int = 0

# Elevation configuration
const ELEVATION_SCALE := 0.15  # How much noise affects position sampling
const BASE_ELEVATION := 0.0    # Ground level

# Landform types for procedural terrain features
enum LandformType {
	NONE,
	HILL,           # Rounded elevated area
	MOUND,          # Small bump, often near greens/fairways
	VALLEY,         # Low depression between areas
	RIDGE,          # Linear raised feature
	SWALE,          # Shallow drainage channel
	DUNE            # Links-style rolling sand dune
}

# Landform data storage - each cell can be influenced by nearby landforms
var landforms: Array = []  # Array of landform dictionaries

# Surface-specific elevation offsets (realistic golf terrain)
# Tees are slightly raised, bunkers are depressed, greens are gentle
const ELEVATION_OFFSETS = {
	# TEE: Slightly raised platform for tee box
	0: 0.15,
	# FAIRWAY: Gentle undulations
	1: 0.0,
	# ROUGH: More varied terrain
	2: 0.05,
	# DEEP_ROUGH: Higher mounds and dunes
	3: 0.12,
	# GREEN: Subtle slopes but relatively flat
	4: 0.02,
	# SAND: Depressed bunkers
	5: -0.25,
	# WATER: Lowest points
	6: -0.35,
	# TREE: On elevated rough/mounds
	7: 0.15,
	# FLAG: Same as green
	8: 0.02
}


# --- Helpers ------------------------------------------------------------

func _clear_course_nodes() -> void:
	thefloor.hide()
	golf_ball = null  # Reset golf ball reference
	tile_nodes.clear()  # Clear tile node references
	tile_data.clear()  # Clear HexTile data
	var to_remove: Array = []
	for child in get_children():
		if child is MultiMeshInstance3D:
			to_remove.append(child)
		elif child.is_in_group("flag"):
			to_remove.append(child)
		elif child.is_in_group("trees"):
			to_remove.append(child)
		elif child.is_in_group("teebox"):
			to_remove.append(child)
		elif child.is_in_group("golfball"):
			to_remove.append(child)
		elif child.is_in_group("foliage"):
			to_remove.append(child)
	for child in to_remove:
		remove_child(child)
		child.queue_free()


func _init_grid() -> void:
	grid.clear()
	elevation.clear()
	for col in range(grid_width):
		var column: Array = []
		var elev_column: Array = []
		for row in range(grid_height):
			column.append(SurfaceType.ROUGH)
			elev_column.append(0.0)
		grid.append(column)
		elevation.append(elev_column)


func get_cell(col: int, row: int) -> int:
	if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
		return grid[col][row]
	return -1


func set_cell(col: int, row: int, value: int) -> void:
	if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
		grid[col][row] = value


func _is_adjacent_to_type(col: int, row: int, surface_type: int) -> bool:
	for ncol in range(col - 1, col + 2):
		for nrow in range(row - 1, row + 2):
			if ncol == col and nrow == row:
				continue
			if ncol >= 0 and ncol < grid_width and nrow >= 0 and nrow < grid_height:
				if get_cell(ncol, nrow) == surface_type:
					return true
	return false


func _is_fairway_edge(col: int, row: int) -> bool:
	if get_cell(col, row) != SurfaceType.FAIRWAY:
		return false
	for ncol in range(col - 1, col + 2):
		for nrow in range(row - 1, row + 2):
			if ncol == col and nrow == row:
				continue
			if ncol >= 0 and ncol < grid_width and nrow >= 0 and nrow < grid_height:
				if get_cell(ncol, nrow) == SurfaceType.ROUGH:
					return true
	return false


# Calculates the minimum distance from a cell to the nearest fairway, green, or tee
func _distance_to_play_area(col: int, row: int) -> int:
	var min_dist = 999
	for c in range(grid_width):
		for r in range(grid_height):
			var surf = get_cell(c, r)
			if surf == SurfaceType.FAIRWAY or surf == SurfaceType.GREEN or surf == SurfaceType.TEE:
				var dist = abs(c - col) + abs(r - row)  # Manhattan distance
				if dist < min_dist:
					min_dist = dist
	return min_dist


# Simple noise function for organic patterns
func _noise_at(col: int, row: int, seed_offset: int = 0) -> float:
	var x = col * 0.3 + seed_offset
	var y = row * 0.3
	# Simple pseudo-noise using sin combinations
	return (sin(x * 1.2 + y * 0.8) + sin(x * 0.7 - y * 1.3) + sin((x + y) * 0.5)) / 3.0


# Multi-octave noise for realistic terrain elevation
# Combines multiple frequencies for natural-looking hills and mounds
func _terrain_noise(col: int, row: int) -> float:
	var x = col * ELEVATION_SCALE + elevation_seed
	var y = row * ELEVATION_SCALE
	
	# Octave 1: Large rolling hills (low frequency, high amplitude)
	var octave1 = sin(x * 0.5 + y * 0.3) * cos(y * 0.4 - x * 0.2) * 0.5
	
	# Octave 2: Medium undulations
	var octave2 = sin(x * 1.2 + y * 0.9) * sin(y * 1.1 + x * 0.7) * 0.25
	
	# Octave 3: Small mounds and bumps (high frequency, low amplitude)
	var octave3 = sin(x * 2.5 + y * 2.1) * cos(y * 2.3 - x * 1.8) * 0.12
	
	# Octave 4: Fine detail
	var octave4 = sin(x * 4.0 + y * 3.5) * sin(y * 4.2 + x * 3.8) * 0.06
	
	return octave1 + octave2 + octave3 + octave4


# --- Landform Generation ------------------------------------------------

# Generate procedural landforms (hills, valleys, ridges, etc.)
func _generate_landforms() -> void:
	landforms.clear()
	
	# Number of landforms scales with course size
	var num_hills = 1 + randi() % 3      # 1-3 large hills
	var num_mounds = 3 + randi() % 5     # 3-7 small mounds
	var num_valleys = 1 + randi() % 2    # 1-2 valleys
	var num_ridges = randi() % 2         # 0-1 ridges
	var num_swales = 1 + randi() % 3     # 1-3 swales
	var num_dunes = randi() % 3          # 0-2 dune clusters
	
	# Generate hills (large rounded elevated areas in rough/deep rough)
	for i in range(num_hills):
		_place_landform(LandformType.HILL, {
			"radius": 4.0 + randf() * 4.0,    # 4-8 cell radius
			"height": 0.4 + randf() * 0.4,    # 0.4-0.8 height
			"falloff": 2.0                     # Gradual falloff
		})
	
	# Generate mounds (smaller bumps, often framing fairways)
	for i in range(num_mounds):
		_place_landform(LandformType.MOUND, {
			"radius": 1.5 + randf() * 2.0,    # 1.5-3.5 cell radius
			"height": 0.15 + randf() * 0.2,   # 0.15-0.35 height
			"falloff": 1.5                     # Steeper falloff
		})
	
	# Generate valleys (depressions, often containing water or swales)
	for i in range(num_valleys):
		_place_landform(LandformType.VALLEY, {
			"radius": 3.0 + randf() * 3.0,    # 3-6 cell radius
			"height": -0.3 - randf() * 0.2,   # -0.3 to -0.5 depth
			"falloff": 2.5                     # Very gradual edges
		})
	
	# Generate ridges (linear raised features)
	for i in range(num_ridges):
		_place_ridge()
	
	# Generate swales (shallow channels for drainage)
	for i in range(num_swales):
		_place_swale()
	
	# Generate dunes (links-style rolling mounds, typically in rough)
	for i in range(num_dunes):
		_place_dune_cluster()


# Place a circular landform (hill, mound, valley)
func _place_landform(type: int, params: Dictionary) -> void:
	var attempts = 0
	var placed = false
	
	while not placed and attempts < 20:
		var center_col = 1 + randi() % (grid_width - 2)
		var center_row = 1 + randi() % (grid_height - 2)
		var surf = get_cell(center_col, center_row)
		
		# Hills and valleys prefer rough/deep rough areas
		# Mounds can be anywhere except water
		var valid_placement = false
		if type == LandformType.HILL or type == LandformType.VALLEY:
			valid_placement = surf == SurfaceType.ROUGH or surf == SurfaceType.DEEP_ROUGH
		elif type == LandformType.MOUND:
			valid_placement = surf != SurfaceType.WATER and surf != SurfaceType.GREEN
		
		if valid_placement:
			landforms.append({
				"type": type,
				"col": center_col,
				"row": center_row,
				"radius": params.radius,
				"height": params.height,
				"falloff": params.falloff
			})
			placed = true
		
		attempts += 1


# Place a linear ridge feature
func _place_ridge() -> void:
	# Ridge runs roughly parallel or perpendicular to hole direction
	var start_col = 1 + randi() % (grid_width - 2)
	var start_row = int(grid_height * 0.3) + randi() % int(grid_height * 0.4)
	
	# Ridge direction (mostly horizontal with some variation)
	var angle = randf() * PI * 0.3 - PI * 0.15  # -15 to +15 degrees from horizontal
	var length = 5 + randi() % 8  # 5-12 cells long
	
	landforms.append({
		"type": LandformType.RIDGE,
		"col": start_col,
		"row": start_row,
		"angle": angle,
		"length": length,
		"height": 0.25 + randf() * 0.2,  # 0.25-0.45 height
		"width": 1.5 + randf() * 1.0     # 1.5-2.5 cells wide
	})


# Place a swale (shallow drainage channel)
func _place_swale() -> void:
	# Swales typically run down the course (following water flow)
	var start_col = 2 + randi() % (grid_width - 4)
	var start_row = 2 + randi() % int(grid_height * 0.3)
	
	# Swale curves slightly as it goes down
	var curve = (randf() - 0.5) * 0.3  # Slight curve factor
	var length = 6 + randi() % 10  # 6-15 cells long
	
	landforms.append({
		"type": LandformType.SWALE,
		"col": start_col,
		"row": start_row,
		"curve": curve,
		"length": length,
		"depth": -0.15 - randf() * 0.1,  # -0.15 to -0.25 depth
		"width": 2.0 + randf() * 1.5     # 2-3.5 cells wide
	})


# Place a cluster of dunes (links-style rolling terrain)
func _place_dune_cluster() -> void:
	var center_col = 1 + randi() % (grid_width - 2)
	var center_row = 1 + randi() % (grid_height - 2)
	
	# Only place dunes in rough/deep rough areas
	var surf = get_cell(center_col, center_row)
	if surf != SurfaceType.ROUGH and surf != SurfaceType.DEEP_ROUGH:
		return
	
	# Create 3-6 overlapping dune mounds
	var num_dunes = 3 + randi() % 4
	for i in range(num_dunes):
		var offset_col = center_col + (randi() % 5 - 2)
		var offset_row = center_row + (randi() % 5 - 2)
		
		landforms.append({
			"type": LandformType.DUNE,
			"col": offset_col,
			"row": offset_row,
			"radius": 1.5 + randf() * 2.0,
			"height": 0.2 + randf() * 0.25,
			"falloff": 1.2
		})


# Calculate the elevation contribution from all landforms at a point
func _get_landform_elevation(col: int, row: int) -> float:
	var total_elevation = 0.0
	
	for lf in landforms:
		var contribution = 0.0
		
		match lf.type:
			LandformType.HILL, LandformType.MOUND, LandformType.VALLEY, LandformType.DUNE:
				# Circular falloff from center
				var dx = col - lf.col
				var dy = row - lf.row
				var dist = sqrt(dx * dx + dy * dy)
				
				if dist < lf.radius * lf.falloff:
					# Smooth falloff using cosine interpolation
					var t = dist / (lf.radius * lf.falloff)
					var falloff = (1.0 + cos(t * PI)) * 0.5
					contribution = lf.height * falloff
			
			LandformType.RIDGE:
				# Linear feature with perpendicular falloff
				contribution = _calculate_ridge_elevation(col, row, lf)
			
			LandformType.SWALE:
				# Curved channel with gradual sides
				contribution = _calculate_swale_elevation(col, row, lf)
		
		total_elevation += contribution
	
	return total_elevation


# Calculate elevation contribution from a ridge
func _calculate_ridge_elevation(col: int, row: int, ridge: Dictionary) -> float:
	var start_col = ridge.col
	var start_row = ridge.row
	var angle = ridge.angle
	var length = ridge.length
	var height = ridge.height
	var width = ridge.width
	
	# Direction vector of ridge
	var dir_x = cos(angle)
	var dir_y = sin(angle)
	
	# Vector from ridge start to point
	var dx = col - start_col
	var dy = row - start_row
	
	# Project point onto ridge line
	var proj_length = dx * dir_x + dy * dir_y
	
	# Check if projection is within ridge length
	if proj_length < 0 or proj_length > length:
		return 0.0
	
	# Perpendicular distance from ridge line
	var perp_dist = abs(dx * (-dir_y) + dy * dir_x)
	
	if perp_dist > width * 2:
		return 0.0
	
	# Falloff perpendicular to ridge
	var t = perp_dist / (width * 2)
	var falloff = (1.0 + cos(t * PI)) * 0.5
	
	# Taper at ends
	var end_taper = 1.0
	if proj_length < length * 0.2:
		end_taper = proj_length / (length * 0.2)
	elif proj_length > length * 0.8:
		end_taper = (length - proj_length) / (length * 0.2)
	
	return height * falloff * end_taper


# Calculate elevation contribution from a swale
func _calculate_swale_elevation(col: int, row: int, swale: Dictionary) -> float:
	var start_col = swale.col
	var start_row = swale.row
	var curve = swale.curve
	var length = swale.length
	var depth = swale.depth
	var width = swale.width
	
	# Swale runs roughly downward (increasing row) with curve
	var dy = row - start_row
	
	if dy < 0 or dy > length:
		return 0.0
	
	# Expected col position along curved path
	var expected_col = start_col + curve * dy
	var dx = abs(col - expected_col)
	
	if dx > width * 2:
		return 0.0
	
	# Cross-section is U-shaped
	var t = dx / (width * 2)
	var cross_section = (1.0 + cos(t * PI)) * 0.5
	
	# Taper at start and end
	var taper = 1.0
	if dy < length * 0.15:
		taper = dy / (length * 0.15)
	elif dy > length * 0.85:
		taper = (length - dy) / (length * 0.15)
	
	return depth * cross_section * taper


# Calculate elevation for a cell based on surface type and terrain noise
func _calculate_elevation(col: int, row: int, surface_type: int) -> float:
	# Base terrain noise
	var terrain = _terrain_noise(col, row)
	
	# Landform contributions (hills, valleys, ridges, etc.)
	var landform_elev = _get_landform_elevation(col, row)
	
	# Surface-specific offset
	var surface_offset = ELEVATION_OFFSETS.get(surface_type, 0.0)
	
	# Reduce terrain variation for flat surfaces (greens, tees)
	var terrain_multiplier = 1.0
	var landform_multiplier = 1.0
	
	if surface_type == SurfaceType.GREEN:
		terrain_multiplier = 0.15  # Greens are relatively flat
		landform_multiplier = 0.3  # Landforms still affect greens slightly
	elif surface_type == SurfaceType.TEE:
		terrain_multiplier = 0.1   # Tees are very flat
		landform_multiplier = 0.2  # Minimal landform influence
	elif surface_type == SurfaceType.WATER:
		terrain_multiplier = 0.05  # Water is level
		landform_multiplier = 0.5  # Water follows major terrain
	elif surface_type == SurfaceType.FAIRWAY:
		terrain_multiplier = 0.6   # Fairways have gentle undulations
		landform_multiplier = 0.7  # Reduced landform impact on fairway
	elif surface_type == SurfaceType.SAND:
		terrain_multiplier = 0.3   # Bunkers have some internal variation
		landform_multiplier = 0.4  # Bunkers are dug into terrain
	elif surface_type == SurfaceType.DEEP_ROUGH or surface_type == SurfaceType.TREE:
		terrain_multiplier = 1.2   # More dramatic mounds in rough areas
		landform_multiplier = 1.0  # Full landform influence
	
	var final_elevation = BASE_ELEVATION
	final_elevation += terrain * terrain_multiplier
	final_elevation += landform_elev * landform_multiplier
	final_elevation += surface_offset
	
	return final_elevation


# Get stored elevation for a cell
func get_elevation(col: int, row: int) -> float:
	if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
		return elevation[col][row]
	return 0.0


# Set elevation for a cell
func set_elevation(col: int, row: int, value: float) -> void:
	if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
		elevation[col][row] = value


# --- Tile ID Helpers ----------------------------------------------------

# Get a unique string ID for a cell (useful for debugging/logging)
func get_tile_id(col: int, row: int) -> String:
	return "tile_%d_%d" % [col, row]


# Get cell position from string ID
func parse_tile_id(tile_id: String) -> Vector2i:
	var parts = tile_id.split("_")
	if parts.size() == 3 and parts[0] == "tile":
		return Vector2i(int(parts[1]), int(parts[2]))
	return Vector2i(-1, -1)


# Get the world position for a cell
func get_tile_world_position(cell: Vector2i) -> Vector3:
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	var x_pos = cell.x * width * 1.5
	var z_pos = cell.y * hex_height + (cell.x % 2) * (hex_height / 2.0)
	var y_pos = get_elevation(cell.x, cell.y)
	return Vector3(x_pos, y_pos, z_pos)


# Get tile data as a dictionary (useful for serialization or debugging)
func get_tile_data(cell: Vector2i) -> Dictionary:
	if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
		return {}
	return {
		"id": get_tile_id(cell.x, cell.y),
		"cell": cell,
		"surface": get_cell(cell.x, cell.y),
		"elevation": get_elevation(cell.x, cell.y),
		"world_position": get_tile_world_position(cell)
	}


# --- Lifecycle ----------------------------------------------------------

func _ready() -> void:
	_create_highlight_mesh()
	_create_trajectory_mesh()
	_create_mini_viewports()
	_init_shot_system()
	_generate_course()
	_generate_grid()
	_log_hole_info()
	_update_mini_cameras()
	_start_new_shot()


func _process(_delta: float) -> void:
	_update_tile_highlight()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Lock target to currently hovered cell
			if hovered_cell.x >= 0 and hovered_cell.y >= 0:
				locked_cell = hovered_cell
				target_locked = true
				
				# Calculate locked target position
				var width = TILE_SIZE
				var hex_height = TILE_SIZE * sqrt(3.0)
				var x_pos = locked_cell.x * width * 1.5
				var z_pos = locked_cell.y * hex_height + (locked_cell.x % 2) * (hex_height / 2.0)
				var y_pos = get_elevation(locked_cell.x, locked_cell.y)
				locked_target_pos = Vector3(x_pos, y_pos, z_pos)
				
				# Show white target highlight on the locked cell
				target_highlight_mesh.position = Vector3(x_pos, y_pos + 0.5, z_pos)
				target_highlight_mesh.rotation.y = PI / 6.0
				target_highlight_mesh.visible = true
				
				# Update shot manager with aim target
				if shot_manager and shot_manager.is_shot_in_progress:
					shot_manager.set_aim_target(locked_cell)
				
				# Display debug info for the clicked tile
				_display_tile_debug_info(locked_cell)
		
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right-click to confirm shot (if target is locked)
			if target_locked and shot_manager and shot_manager.is_shot_in_progress:
				shot_manager.confirm_shot()
				target_locked = false
				target_highlight_mesh.visible = false
				_hide_all_aoe_highlights()


# Display debug information about a tile in the info label
func _display_tile_debug_info(cell: Vector2i) -> void:
	if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
		return
	
	var surface = get_cell(cell.x, cell.y)
	var elev = get_elevation(cell.x, cell.y)
	var world_pos = get_tile_world_position(cell)
	
	# Get surface type name
	var surface_names = {
		SurfaceType.TEE: "Tee",
		SurfaceType.FAIRWAY: "Fairway",
		SurfaceType.ROUGH: "Rough",
		SurfaceType.DEEP_ROUGH: "Deep Rough",
		SurfaceType.GREEN: "Green",
		SurfaceType.SAND: "Sand",
		SurfaceType.WATER: "Water",
		SurfaceType.TREE: "Tree",
		SurfaceType.FLAG: "Flag"
	}
	var surface_name = surface_names.get(surface, "Unknown")
	
	# Get neighbors
	var neighbors = get_adjacent_cells(cell.x, cell.y)
	var neighbor_info = ""
	for i in range(neighbors.size()):
		var n = neighbors[i]
		if n.x >= 0 and n.x < grid_width and n.y >= 0 and n.y < grid_height:
			var n_surface = get_cell(n.x, n.y)
			var n_name = surface_names.get(n_surface, "---")
			var n_elev = get_elevation(n.x, n.y)
			neighbor_info += "  [%d,%d] %s (%.2f)\n" % [n.x, n.y, n_name, n_elev]
		else:
			neighbor_info += "  [%d,%d] Out of bounds\n" % [n.x, n.y]
	
	# Check for nearby landforms
	var nearby_landforms = ""
	for lf in landforms:
		var lf_center = Vector2(lf["col"], lf["row"])
		var dist = Vector2(cell.x, cell.y).distance_to(lf_center)
		
		# Different landform types have different size keys
		var influence_range = 5.0  # Default
		if lf.has("radius"):
			influence_range = lf["radius"] * 1.5
		elif lf.has("length"):
			influence_range = lf["length"]
		elif lf.has("width"):
			influence_range = lf["width"] * 2.0
		
		if dist <= influence_range:
			var lf_names = {
				LandformType.HILL: "Hill",
				LandformType.MOUND: "Mound",
				LandformType.VALLEY: "Valley",
				LandformType.RIDGE: "Ridge",
				LandformType.SWALE: "Swale",
				LandformType.DUNE: "Dune"
			}
			var size_info = ""
			if lf.has("radius"):
				size_info = "r: %.1f" % lf["radius"]
			elif lf.has("length"):
				size_info = "len: %d" % lf["length"]
			nearby_landforms += "  %s (dist: %.1f, %s)\n" % [lf_names.get(lf["type"], "?"), dist, size_info]
	
	if nearby_landforms == "":
		nearby_landforms = "  None\n"
	
	# Build debug text
	# Calculate yardage from tee
	var yards_from_tee = cell.y * YARDS_PER_CELL
	
	var debug_text = "=== TILE DEBUG ===\n"
	debug_text += "Cell: [%d, %d]\n" % [cell.x, cell.y]
	debug_text += "ID: %s\n" % get_tile_id(cell.x, cell.y)
	debug_text += "Surface: %s\n" % surface_name
	debug_text += "Yardage: %d yards from tee\n" % yards_from_tee
	debug_text += "Elevation: %.3f\n" % elev
	debug_text += "World Pos: (%.2f, %.2f, %.2f)\n" % [world_pos.x, world_pos.y, world_pos.z]
	debug_text += "\nNeighbors (6):\n%s" % neighbor_info
	debug_text += "\nNearby Landforms:\n%s" % nearby_landforms
	
	# Update the label - append to hole info
	if holelabel:
		holelabel.text = hole_info_text + "\n" + debug_text


# --- Shot System Integration -------------------------------------------

func _init_shot_system() -> void:
	"""Initialize shot system components and connect signals"""
	# Create AOE system
	aoe_system = AOESystem.new()
	aoe_system.name = "AOESystem"
	add_child(aoe_system)
	
	# Create modifier manager
	modifier_manager = ModifierManager.new()
	modifier_manager.name = "ModifierManager"
	add_child(modifier_manager)
	
	# Create shot manager
	shot_manager = ShotManager.new()
	shot_manager.name = "ShotManager"
	add_child(shot_manager)
	
	# Wire up shot manager references
	shot_manager.set_hole_controller(self)
	shot_manager.set_aoe_system(aoe_system)
	shot_manager.set_modifier_manager(modifier_manager)
	
	# Connect shot lifecycle signals
	shot_manager.shot_started.connect(_on_shot_started)
	shot_manager.aoe_computed.connect(_on_aoe_computed)
	shot_manager.landing_resolved.connect(_on_landing_resolved)
	shot_manager.shot_completed.connect(_on_shot_completed)


func _start_new_shot() -> void:
	"""Start a new shot from the ball's current position"""
	if golf_ball == null:
		push_warning("No golf ball to start shot from")
		return
	
	# Get ball's current tile
	var ball_tile = world_to_grid(golf_ball.position)
	shot_manager.start_shot(golf_ball, ball_tile)


func _on_shot_started(context: ShotContext) -> void:
	"""Called when shot begins - update UI"""
	print("Shot %d started from tile [%d, %d]" % [context.shot_index, context.start_tile.x, context.start_tile.y])


func _on_aoe_computed(context: ShotContext) -> void:
	"""Called when AOE is calculated - update visuals"""
	# The existing highlight system handles this via _update_tile_highlight
	pass


func _on_landing_resolved(context: ShotContext) -> void:
	"""Called when landing tile is determined"""
	print("Ball landing at tile [%d, %d]" % [context.landing_tile.x, context.landing_tile.y])


func _on_shot_completed(context: ShotContext) -> void:
	"""Called when shot is finished - update ball position, scoring, UI"""
	print("Shot completed! Score: %d (chips: %d x mult: %.1f)" % [context.final_score, context.chips, context.mult])
	
	# Move ball to landing position
	if golf_ball and context.landing_tile.x >= 0:
		var new_pos = get_tile_world_position(context.landing_tile)
		golf_ball.position = new_pos + Vector3(0, 0.1, 0)  # Slight offset above ground
	
	# Check if reached flag
	if context.has_metadata("reached_flag"):
		print("HOLE COMPLETE!")
	else:
		# Start next shot
		_start_new_shot()


func get_hex_tile(cell: Vector2i) -> HexTile:
	"""Get HexTile data for a cell, creating if needed"""
	if tile_data.has(cell):
		return tile_data[cell]
	
	# Create new HexTile from current grid data
	var tile = HexTile.new()
	tile.col = cell.x
	tile.row = cell.y
	tile.terrain_type = get_cell(cell.x, cell.y)
	tile.elevation = get_elevation(cell.x, cell.y)
	tile_data[cell] = tile
	return tile


func set_tile_terrain(cell: Vector2i, terrain_type: int) -> void:
	"""Set terrain type for a tile (updates both grid and HexTile)"""
	set_cell(cell.x, cell.y, terrain_type)
	var tile = get_hex_tile(cell)
	tile.terrain_type = terrain_type


func add_tile_tag(cell: Vector2i, tag: String) -> void:
	"""Add a tag to a tile"""
	var tile = get_hex_tile(cell)
	tile.add_tag(tag)


func remove_tile_tag(cell: Vector2i, tag: String) -> void:
	"""Remove a tag from a tile"""
	var tile = get_hex_tile(cell)
	tile.remove_tag(tag)


func tile_has_tag(cell: Vector2i, tag: String) -> bool:
	"""Check if tile has a tag"""
	var tile = get_hex_tile(cell)
	return tile.has_tag(tag)


# Create the highlight mesh used to show hovered tile
func _create_highlight_mesh() -> void:
	highlight_mesh = MeshInstance3D.new()
	
	# Use a CylinderMesh as a ring - make it very short (flat) and hollow looking
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = TILE_SIZE * 0.55
	cylinder.bottom_radius = TILE_SIZE * 0.55
	cylinder.height = 0.05  # Very thin/flat
	cylinder.radial_segments = 6  # Hexagonal shape
	highlight_mesh.mesh = cylinder
	
	# Create a bright, unshaded material for maximum visibility
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.0, 0.6)  # Bright yellow/gold, semi-transparent
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Always fully bright
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_mesh.material_override = mat
	highlight_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	highlight_mesh.visible = false
	add_child(highlight_mesh)
	
	# Create white target highlight for locked/active cell
	target_highlight_mesh = MeshInstance3D.new()
	var target_cylinder = CylinderMesh.new()
	target_cylinder.top_radius = TILE_SIZE * 0.55
	target_cylinder.bottom_radius = TILE_SIZE * 0.55
	target_cylinder.height = 0.05
	target_cylinder.radial_segments = 6
	target_highlight_mesh.mesh = target_cylinder
	
	var target_mat = StandardMaterial3D.new()
	target_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.6)  # White, semi-transparent
	target_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	target_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	target_highlight_mesh.material_override = target_mat
	target_highlight_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	target_highlight_mesh.visible = false
	add_child(target_highlight_mesh)
	
	# AOE highlights are now created dynamically via _get_or_create_aoe_highlight()


# Get or create an AOE highlight for a specific cell
# ring: 0 = center (not used), 1 = adjacent, 2 = outer ring
func _get_or_create_aoe_highlight(cell: Vector2i, ring: int) -> MeshInstance3D:
	if aoe_highlights.has(cell):
		return aoe_highlights[cell]
	
	# Create a new highlight mesh for this cell
	var mesh = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = TILE_SIZE * 0.55
	cylinder.bottom_radius = TILE_SIZE * 0.55
	cylinder.height = 0.05
	cylinder.radial_segments = 6
	mesh.mesh = cylinder
	
	var mat = StandardMaterial3D.new()
	# Set opacity based on ring distance
	var alpha = 0.05 if ring == 1 else 0.025  # Ring 1 = 0.05, Ring 2 = 0.025
	mat.albedo_color = Color(1.0, 0.85, 0.0, alpha)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visible = false
	
	# Store metadata for future reference
	mesh.set_meta("cell_id", cell)
	mesh.set_meta("ring", ring)
	
	add_child(mesh)
	aoe_highlights[cell] = mesh
	return mesh


# Set the color of an AOE highlight by cell ID
func set_aoe_highlight_color(cell: Vector2i, color: Color) -> void:
	if aoe_highlights.has(cell):
		var mesh: MeshInstance3D = aoe_highlights[cell]
		mesh.material_override.albedo_color = color


# Get all currently visible AOE highlight cell IDs
func get_visible_aoe_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in aoe_highlights.keys():
		if aoe_highlights[cell].visible:
			cells.append(cell)
	return cells


# Clear all AOE highlights (hide them, keep for reuse)
func _hide_all_aoe_highlights() -> void:
	for cell in aoe_highlights.keys():
		aoe_highlights[cell].visible = false


# Create the trajectory arc mesh
func _create_trajectory_mesh() -> void:
	trajectory_mesh = MeshInstance3D.new()
	trajectory_mesh.mesh = ImmediateMesh.new()
	
	# Create a bright material for the trajectory ribbon
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)  # Base white, alpha controlled by vertex color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Render both sides
	mat.no_depth_test = true  # Always visible, ignore depth
	mat.vertex_color_use_as_albedo = true  # Use vertex colors for the fade effect
	trajectory_mesh.material_override = mat
	trajectory_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Set a large custom AABB so it doesn't get frustum culled
	trajectory_mesh.custom_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
	
	add_child(trajectory_mesh)
	
	# Create trajectory shadow mesh (dark line on ground)
	trajectory_shadow_mesh = MeshInstance3D.new()
	trajectory_shadow_mesh.mesh = ImmediateMesh.new()
	
	var shadow_mat = StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.3)  # Dark, semi-transparent
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_mat.no_depth_test = true  # Draw over terrain
	trajectory_shadow_mesh.material_override = shadow_mat
	trajectory_shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trajectory_shadow_mesh.custom_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
	
	add_child(trajectory_shadow_mesh)


# Create mini viewports for top and side views
func _create_mini_viewports() -> void:
	# Find the Control node to parent the viewport containers
	var control_node = get_tree().current_scene.get_node("Control")
	if control_node == null:
		push_warning("Control node not found - mini viewports not created")
		return
	
	# Viewport size
	var viewport_size = Vector2i(300, 250)
	
	# --- TOP VIEW (looking down at the hole) ---
	top_viewport_container = SubViewportContainer.new()
	top_viewport_container.stretch = true
	top_viewport_container.custom_minimum_size = Vector2(viewport_size)
	top_viewport_container.size = Vector2(viewport_size)
	# Position in bottom-right corner
	# Position in bottom-right corner to avoid covering debug text
	top_viewport_container.position = Vector2(1600, 450)
	
	top_viewport = SubViewport.new()
	top_viewport.size = viewport_size
	top_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	top_viewport.transparent_bg = false
	top_viewport.handle_input_locally = false
	top_viewport.gui_disable_input = true
	
	top_camera = Camera3D.new()
	top_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_camera.size = 30.0  # Orthographic size, will be adjusted per hole
	top_camera.near = 0.1
	top_camera.far = 200.0
	# Look straight down, rotated 180 degrees so tee is at bottom
	top_camera.rotation_degrees = Vector3(-90, 180, 0)
	
	top_viewport.add_child(top_camera)
	top_viewport_container.add_child(top_viewport)
	control_node.add_child(top_viewport_container)
	
	# Add a border/label for the top view
	var top_label = Label.new()
	top_label.text = "TOP VIEW"
	top_label.position = Vector2(5, 5)
	top_label.add_theme_color_override("font_color", Color.WHITE)
	top_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	top_label.add_theme_constant_override("shadow_offset_x", 1)
	top_label.add_theme_constant_override("shadow_offset_y", 1)
	top_viewport_container.add_child(top_label)
	
	# --- SIDE VIEW (looking at the hole from the side) ---
	side_viewport_container = SubViewportContainer.new()
	side_viewport_container.stretch = true
	side_viewport_container.custom_minimum_size = Vector2(viewport_size)
	side_viewport_container.size = Vector2(viewport_size)
	# Position below top view
	side_viewport_container.position = Vector2(20, 720)
	
	side_viewport = SubViewport.new()
	side_viewport.size = viewport_size
	side_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	side_viewport.transparent_bg = false
	side_viewport.handle_input_locally = false
	side_viewport.gui_disable_input = true
	
	side_camera = Camera3D.new()
	side_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	side_camera.size = 20.0  # Will be adjusted per hole
	side_camera.near = 0.1
	side_camera.far = 200.0
	# Look from the side (along X axis looking at Z)
	side_camera.rotation_degrees = Vector3(0, -90, 0)
	
	side_viewport.add_child(side_camera)
	side_viewport_container.add_child(side_viewport)
	control_node.add_child(side_viewport_container)
	side_viewport_container.visible = false  # Hidden for now
	
	# Add a border/label for the side view
	var side_label = Label.new()
	side_label.text = "SIDE VIEW"
	side_label.position = Vector2(5, 5)
	side_label.add_theme_color_override("font_color", Color.WHITE)
	side_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	side_label.add_theme_constant_override("shadow_offset_x", 1)
	side_label.add_theme_constant_override("shadow_offset_y", 1)
	side_viewport_container.add_child(side_label)


# Update mini cameras to frame the current hole
func _update_mini_cameras() -> void:
	if top_camera == null or side_camera == null:
		return
	
	# Calculate bounds of the hole
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	
	# Find min/max positions of the grid
	var min_x = 0.0
	var max_x = (grid_width - 1) * width * 1.5
	var min_z = 0.0
	var max_z = (grid_height - 1) * hex_height + hex_height / 2.0
	
	# Find elevation range
	var min_y = 0.0
	var max_y = 0.0
	for col in range(grid_width):
		for row in range(grid_height):
			var elev = get_elevation(col, row)
			min_y = min(min_y, elev)
			max_y = max(max_y, elev)
	
	# Add some padding
	var padding = 2.0
	min_x -= padding
	max_x += padding
	min_z -= padding
	max_z += padding
	min_y -= 1.0
	max_y += 3.0
	
	# Center of the hole
	var center_x = (min_x + max_x) / 2.0
	var center_z = (min_z + max_z) / 2.0
	var center_y = (min_y + max_y) / 2.0
	
	# Size of the hole
	var size_x = max_x - min_x
	var size_z = max_z - min_z
	var size_y = max_y - min_y
	
	# --- TOP CAMERA ---
	# Position above the center looking down
	top_camera.position = Vector3(center_x, max_y + 50.0, center_z)
	# Set orthographic size to fit the hole (use the larger dimension)
	top_camera.size = max(size_x, size_z) * 1.1  # 10% padding
	
	# --- SIDE CAMERA ---
	# Position to the side of the hole looking along the length
	# We want to look from tee to green, so position on -X side looking toward +X
	side_camera.position = Vector3(min_x - 50.0, center_y + 5.0, center_z)
	# Set orthographic size based on height and length
	side_camera.size = max(size_y + 5.0, size_z) * 0.7


# Update the trajectory arc from ball to target
func _update_trajectory(target_pos: Vector3) -> void:
	if golf_ball == null:
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false
		return
	
	var im: ImmediateMesh = trajectory_mesh.mesh
	im.clear_surfaces()
	
	var start_pos = golf_ball.position
	var end_pos = target_pos
	
	# Number of segments in the arc
	var segments = 30
	
	# Width of the ribbon (horizontal spread)
	var ribbon_width = 0.15
	
	# Invisible sections at start and end (0% opacity)
	var invisible_amount = 0.10  # First and last 10% are invisible
	# Fade sections after invisible parts
	var fade_amount = 0.15  # Fade over 15% of the arc after/before invisible
	
	# Calculate the horizontal direction perpendicular to the arc
	var forward_dir = (end_pos - start_pos).normalized()
	forward_dir.y = 0  # Keep it horizontal
	if forward_dir.length() > 0.001:
		forward_dir = forward_dir.normalized()
	else:
		forward_dir = Vector3.FORWARD
	
	# Perpendicular horizontal direction (for ribbon width)
	var right_dir = forward_dir.cross(Vector3.UP).normalized()
	
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		
		# Calculate alpha with invisible sections and fades
		var alpha = 0.0
		if t < invisible_amount:
			# Invisible at start
			alpha = 0.0
		elif t < invisible_amount + fade_amount:
			# Fade in after invisible section
			alpha = (t - invisible_amount) / fade_amount
		elif t > (1.0 - invisible_amount):
			# Invisible at end
			alpha = 0.0
		elif t > (1.0 - invisible_amount - fade_amount):
			# Fade out before invisible section
			alpha = (1.0 - invisible_amount - t) / fade_amount
		else:
			# Full opacity in the middle
			alpha = 1.0
		
		# Set vertex color with alpha
		var vertex_color = Color(1.0, 1.0, 1.0, alpha * 0.8)
		im.surface_set_color(vertex_color)
		
		# Linear interpolation for X and Z
		var center_pos = start_pos.lerp(end_pos, t)
		
		# Parabolic arc for Y (height)
		var arc_height = sin(t * PI) * trajectory_height
		center_pos.y = start_pos.y + (end_pos.y - start_pos.y) * t + arc_height
		
		# Add left and right vertices to create the ribbon
		var left_pos = center_pos - right_dir * ribbon_width
		var right_pos = center_pos + right_dir * ribbon_width
		
		im.surface_add_vertex(left_pos)
		im.surface_add_vertex(right_pos)
	
	im.surface_end()
	trajectory_mesh.visible = true
	
	# Draw shadow line on ground (straight line from ball to target)
	var shadow_im: ImmediateMesh = trajectory_shadow_mesh.mesh
	shadow_im.clear_surfaces()
	
	var shadow_width = 0.1
	var shadow_segments = 20
	
	shadow_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	for i in range(shadow_segments + 1):
		var t = float(i) / float(shadow_segments)
		
		# Fade at start and end
		var shadow_alpha = 1.0
		if t < 0.1:
			shadow_alpha = t / 0.1
		elif t > 0.9:
			shadow_alpha = (1.0 - t) / 0.1
		
		shadow_im.surface_set_color(Color(0.0, 0.0, 0.0, shadow_alpha * 0.3))
		
		# Straight line on ground, slightly above to avoid z-fighting
		var ground_pos = Vector3(
			lerp(start_pos.x, end_pos.x, t),
			lerp(start_pos.y, end_pos.y, t) + 0.02,  # Slightly above ground
			lerp(start_pos.z, end_pos.z, t)
		)
		
		var left_shadow = ground_pos - right_dir * shadow_width
		var right_shadow = ground_pos + right_dir * shadow_width
		
		shadow_im.surface_add_vertex(left_shadow)
		shadow_im.surface_add_vertex(right_shadow)
	
	shadow_im.surface_end()
	trajectory_shadow_mesh.visible = true


# Update tile highlight based on mouse position
func _update_tile_highlight() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		highlight_mesh.visible = false
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	# Raycast against a horizontal plane at y=0 (approximate ground level)
	var plane = Plane(Vector3.UP, 0)
	var intersection = plane.intersects_ray(ray_origin, ray_dir)
	
	if intersection:
		# Convert world position to grid coordinates
		var cell = world_to_grid(intersection)
		
		if cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height:
			var surface = get_cell(cell.x, cell.y)
			if surface != -1 and surface != SurfaceType.WATER:
				hovered_cell = cell
				
				# Hide all previous AOE highlights before showing new ones
				_hide_all_aoe_highlights()
				
				# Position highlight mesh at the cell
				var width = TILE_SIZE
				var hex_height = TILE_SIZE * sqrt(3.0)
				var x_pos = cell.x * width * 1.5
				var z_pos = cell.y * hex_height + (cell.x % 2) * (hex_height / 2.0)
				# Position well above the tile to be visible
				var y_pos = get_elevation(cell.x, cell.y) + 0.5
				
				highlight_mesh.position = Vector3(x_pos, y_pos, z_pos)
				highlight_mesh.rotation.y = PI / 6.0  # Match tile rotation
				highlight_mesh.visible = true
				
				# Update adjacent highlights (ring 1)
				var neighbors = get_adjacent_cells(cell.x, cell.y)
				for neighbor in neighbors:
					if neighbor.x >= 0 and neighbor.x < grid_width and neighbor.y >= 0 and neighbor.y < grid_height:
						var n_surface = get_cell(neighbor.x, neighbor.y)
						if n_surface != -1 and n_surface != SurfaceType.WATER:
							var highlight = _get_or_create_aoe_highlight(neighbor, 1)
							var n_x = neighbor.x * width * 1.5
							var n_z = neighbor.y * hex_height + (neighbor.x % 2) * (hex_height / 2.0)
							var n_y = get_elevation(neighbor.x, neighbor.y) + 0.5
							highlight.position = Vector3(n_x, n_y, n_z)
							highlight.rotation.y = PI / 6.0
							highlight.visible = true
				
				# Update outer ring highlights (ring 2)
				var outer_cells = get_outer_ring_cells(cell.x, cell.y)
				for outer_cell in outer_cells:
					if outer_cell.x >= 0 and outer_cell.x < grid_width and outer_cell.y >= 0 and outer_cell.y < grid_height:
						var o_surface = get_cell(outer_cell.x, outer_cell.y)
						if o_surface != -1 and o_surface != SurfaceType.WATER:
							var highlight = _get_or_create_aoe_highlight(outer_cell, 2)
							var o_x = outer_cell.x * width * 1.5
							var o_z = outer_cell.y * hex_height + (outer_cell.x % 2) * (hex_height / 2.0)
							var o_y = get_elevation(outer_cell.x, outer_cell.y) + 0.5
							highlight.position = Vector3(o_x, o_y, o_z)
							highlight.rotation.y = PI / 6.0
							highlight.visible = true
				
				# Update trajectory arc - use locked target if set, otherwise hovered
				if target_locked:
					_update_trajectory(locked_target_pos)
				else:
					var target_y = get_elevation(cell.x, cell.y)
					_update_trajectory(Vector3(x_pos, target_y, z_pos))
				return
	
	# No valid hover
	hovered_cell = Vector2i(-1, -1)
	highlight_mesh.visible = false
	_hide_all_aoe_highlights()
	# Keep trajectory visible if locked
	if not target_locked:
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false


# Convert world position to grid cell coordinates
func world_to_grid(world_pos: Vector3) -> Vector2i:
	var width = TILE_SIZE
	var height = TILE_SIZE * sqrt(3.0)
	
	# Approximate column from x position
	var col = roundi(world_pos.x / (width * 1.5))
	
	# Adjust z for row offset based on column
	var z_offset = (col % 2) * (height / 2.0)
	var row = roundi((world_pos.z - z_offset) / height)
	
	return Vector2i(col, row)


# Get the 6 adjacent hex cells for a given cell (ring 1)
func get_adjacent_cells(col: int, row: int) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	
	# Hex grid neighbor offsets depend on whether column is even or odd
	if col % 2 == 0:
		# Even column
		neighbors.append(Vector2i(col - 1, row - 1))  # Upper left
		neighbors.append(Vector2i(col - 1, row))      # Lower left
		neighbors.append(Vector2i(col, row - 1))      # Up
		neighbors.append(Vector2i(col, row + 1))      # Down
		neighbors.append(Vector2i(col + 1, row - 1))  # Upper right
		neighbors.append(Vector2i(col + 1, row))      # Lower right
	else:
		# Odd column
		neighbors.append(Vector2i(col - 1, row))      # Upper left
		neighbors.append(Vector2i(col - 1, row + 1))  # Lower left
		neighbors.append(Vector2i(col, row - 1))      # Up
		neighbors.append(Vector2i(col, row + 1))      # Down
		neighbors.append(Vector2i(col + 1, row))      # Upper right
		neighbors.append(Vector2i(col + 1, row + 1))  # Lower right
	
	return neighbors


# Get the 12 outer ring hex cells for a given cell (ring 2)
# These are the cells that are 2 steps away from the center
func get_outer_ring_cells(col: int, row: int) -> Array[Vector2i]:
	var outer: Array[Vector2i] = []
	var inner = get_adjacent_cells(col, row)
	var seen: Dictionary = {}
	
	# Mark center and inner ring as seen
	seen[Vector2i(col, row)] = true
	for cell in inner:
		seen[cell] = true
	
	# For each inner ring cell, get its neighbors and add ones we haven't seen
	for inner_cell in inner:
		var inner_neighbors = get_adjacent_cells(inner_cell.x, inner_cell.y)
		for neighbor in inner_neighbors:
			if not seen.has(neighbor):
				seen[neighbor] = true
				outer.append(neighbor)
	
	return outer


# Display hole information in the UI Label
func _log_hole_info() -> void:
	# Calculate elevation stats
	var min_elev = 999.0
	var max_elev = -999.0
	for col in range(grid_width):
		for row in range(grid_height):
			var elev = get_elevation(col, row)
			if elev < min_elev:
				min_elev = elev
			if elev > max_elev:
				max_elev = elev
	
	# Count landforms by type
	var hills = 0
	var mounds = 0
	var valleys = 0
	var ridges = 0
	var swales = 0
	var dunes = 0
	for lf in landforms:
		match lf.type:
			LandformType.HILL: hills += 1
			LandformType.MOUND: mounds += 1
			LandformType.VALLEY: valleys += 1
			LandformType.RIDGE: ridges += 1
			LandformType.SWALE: swales += 1
			LandformType.DUNE: dunes += 1
	
	# Build info text
	hole_info_text = "Par %d  |  %d yards\n" % [current_par, current_yardage]
	hole_info_text += "Grid: %d x %d\n" % [grid_width, grid_height]
	hole_info_text += "Elevation: %.2f to %.2f\n" % [min_elev, max_elev]
	hole_info_text += "Landforms: %d hills, %d mounds, %d valleys\n" % [hills, mounds, valleys]
	hole_info_text += "%d ridges, %d swales, %d dunes" % [ridges, swales, dunes]
	
	# Update UI Label
	if holelabel:
		holelabel.text = hole_info_text
	else:
		# Fallback to console if label not found
		print(hole_info_text)


# Generate a specific par hole (3, 4, or 5)
func generate_hole_with_par(par: int) -> void:
	if par < 3 or par > 5:
		push_warning("Invalid par %d, must be 3, 4, or 5. Using par 4." % par)
		par = 4
	
	_clear_course_nodes()
	
	# Set the specified par instead of random
	current_par = par
	var config = PAR_CONFIG[current_par]
	current_yardage = config.min_yards + randi() % (config.max_yards - config.min_yards + 1)
	grid_height = int(current_yardage / YARDS_PER_CELL)
	grid_width = config.min_width + randi() % (config.max_width - config.min_width + 1)
	
	_init_grid()
	_generate_course_features()
	_generate_grid()
	_log_hole_info()
	_update_mini_cameras()


# --- Course generation --------------------------------------------------

func _generate_course() -> void:
	# Randomly select par (3, 4, or 5)
	var par_options = [3, 4, 5]
	current_par = par_options[randi() % par_options.size()]
	
	# Get config for this par
	var config = PAR_CONFIG[current_par]
	
	# Calculate yardage within the par's range
	current_yardage = config.min_yards + randi() % (config.max_yards - config.min_yards + 1)
	
	# Convert yardage to grid height (length of hole)
	grid_height = int(current_yardage / YARDS_PER_CELL)
	
	# Set width based on par (longer holes are wider)
	grid_width = config.min_width + randi() % (config.max_width - config.min_width + 1)
	
	_init_grid()
	_generate_course_features()


func _generate_course_features() -> void:
	# Generate random seeds for noise variation each generation
	var noise_seed = randi() % 1000
	elevation_seed = randi() % 10000

	# --- POND WATER FEATURE ---
	if randf() < 1.0:
		var pond_size = 4 + randi() % 5
		var attempts = 0
		var placed = false
		while not placed and attempts < 20:
			var pond_col = 1 + randi() % (grid_width - 2)
			var pond_row = 1 + randi() % (grid_height - 2)

			var touching_green_or_tee = false
			for dcol in range(-2, 3):
				for drow in range(-2, 3):
					var ncol = pond_col + dcol
					var nrow = pond_row + drow
					if ncol >= 0 and ncol < grid_width \
					and nrow >= 0 and nrow < grid_height:
						var surf = get_cell(ncol, nrow)
						if surf == SurfaceType.GREEN or surf == SurfaceType.TEE:
							touching_green_or_tee = true

			if not touching_green_or_tee:
				for dcol in range(-3, 4):
					for drow in range(-3, 4):
						if dcol * dcol + drow * drow \
						<= int(pow(float(pond_size) / 2.0, 2)):
							var col = pond_col + dcol
							var row = pond_row + drow
							if col >= 0 and col < grid_width \
							and row >= 0 and row < grid_height:
								var surf2 = get_cell(col, row)
								if surf2 != SurfaceType.GREEN \
								and surf2 != SurfaceType.TEE:
									set_cell(col, row, SurfaceType.WATER)
				placed = true

			attempts += 1

	# --- BODY OF WATER (dynamic edge feature, random chance) ---
	if randf() < 0.25:
		var edge = randi() % 4 # 0=left, 1=right, 2=top, 3=bottom
		var max_depth = 2 + randi() % 3 # 2 to 4 tiles deep
		var min_length = int(grid_height * 0.5)
		var min_body_width = int(grid_width * 0.5)

		if edge == 0:
			var start_row_l = randi() % int(grid_height * 0.3)
			var end_row_l = start_row_l + min_length + randi() % (grid_height - start_row_l - min_length + 1)
			end_row_l = min(end_row_l, grid_height)
			for row in range(start_row_l, end_row_l):
				var depth_l = 2 + randi() % (max_depth - 1)
				for col in range(0, depth_l):
					if randf() < 0.85 or col == 0:
						set_cell(col, row, SurfaceType.WATER)

		elif edge == 1:
			var start_row_r = randi() % int(grid_height * 0.3)
			var end_row_r = start_row_r + min_length + randi() % (grid_height - start_row_r - min_length + 1)
			end_row_r = min(end_row_r, grid_height)
			for row in range(start_row_r, end_row_r):
				var depth_r = 2 + randi() % (max_depth - 1)
				for col in range(grid_width - depth_r, grid_width):
					if randf() < 0.85 or col == grid_width - 1:
						set_cell(col, row, SurfaceType.WATER)

		elif edge == 2:
			var start_col_t = randi() % int(grid_width * 0.3)
			var end_col_t = start_col_t + min_body_width + randi() % (grid_width - start_col_t - min_body_width + 1)
			end_col_t = min(end_col_t, grid_width)
			for col in range(start_col_t, end_col_t):
				var depth_t = 2 + randi() % (max_depth - 1)
				for row in range(0, depth_t):
					if randf() < 0.85 or row == 0:
						set_cell(col, row, SurfaceType.WATER)

		else:
			var start_col_b = randi() % int(grid_width * 0.3)
			var end_col_b = start_col_b + min_body_width + randi() % (grid_width - start_col_b - min_body_width + 1)
			end_col_b = min(end_col_b, grid_width)
			for col in range(start_col_b, end_col_b):
				var depth_b = 2 + randi() % (max_depth - 1)
				for row in range(grid_height - depth_b, grid_height):
					if randf() < 0.85 or row == grid_height - 1:
						set_cell(col, row, SurfaceType.WATER)

	# Place tee at top center
	var tee_col = int(grid_width / 2)
	var tee_row = 1
	set_cell(tee_col, tee_row, SurfaceType.TEE)

	# Place green near bottom third
	var green_radius = 2 + randi() % 2 # 2 or 3
	var min_col = 1 + green_radius
	var max_col = grid_width - 2 - green_radius
	var min_row = grid_height - int(grid_height / 6) + 1
	var max_row = grid_height - 2 - green_radius

	if max_col < min_col:
		min_col = int(grid_width / 2)
		max_col = int(grid_width / 2)
	if max_row < min_row:
		min_row = max_row
		max_row = max_row

	var green_center_col = min_col + randi() % max(1, max_col - min_col + 1)
	var green_center_row = min_row + randi() % max(1, max_row - min_row + 1)

	for col in range(grid_width):
		for row in range(grid_height):
			if col < 1 or col > grid_width - 2 or row < 1 or row > grid_height - 2:
				continue
			var dist = sqrt(pow(col - green_center_col, 2) + pow(row - green_center_row, 2))
			if dist <= green_radius:
				set_cell(col, row, SurfaceType.GREEN)

	# --- ISLAND GREEN FEATURE (10% chance) ---
	# Surrounds the green with water, creating a dramatic approach
	if randf() < 0.10:
		var island_green_cells: Array = []
		for col in range(grid_width):
			for row in range(grid_height):
				if get_cell(col, row) == SurfaceType.GREEN:
					island_green_cells.append(Vector2i(col, row))

		for cell in island_green_cells:
			for dcol in range(-1, 2):
				for drow in range(-1, 2):
					var ncol = cell.x + dcol
					var nrow = cell.y + drow
					if (dcol != 0 or drow != 0) \
					and ncol >= 0 and ncol < grid_width \
					and nrow >= 0 and nrow < grid_height:
						var surf = get_cell(ncol, nrow)
						if surf != SurfaceType.GREEN and surf != SurfaceType.TEE:
							set_cell(ncol, nrow, SurfaceType.WATER)

	# --- Shaped fairway with dogleg ---
	var green_fairway_gap = 1 + randi() % 2
	var fairway_end_row = green_center_row - green_radius + green_fairway_gap
	var fairway_start_row = tee_row + 2
	var start_row = min(fairway_start_row, fairway_end_row)
	var end_row = max(fairway_start_row, fairway_end_row)

	var dogleg_type = randi() % 4
	var control_col = tee_col
	if dogleg_type == 0:
		var dogleg_offset0 = int((randf() - 0.5) * grid_width * 1.6)
		control_col = clamp(tee_col + dogleg_offset0, 1, grid_width - 2)
	elif dogleg_type == 1:
		control_col = 1
	elif dogleg_type == 2:
		control_col = grid_width - 2
	else:
		var dogleg_offset3 = int((randf() - 0.5) * grid_width * 0.8)
		control_col = clamp(tee_col + dogleg_offset3, 1, grid_width - 2)

	var num_segments = abs(end_row - start_row)
	var path_points: Array = []
	for i in range(num_segments + 1):
		var t = float(i) / num_segments
		var px = int((1.0 - t) * (1.0 - t) * tee_col \
			+ 2.0 * (1.0 - t) * t * control_col \
			+ t * t * green_center_col)
		var py = int(lerp(tee_row, fairway_end_row, t))
		path_points.append(Vector2(px, py))

	var min_width = 3.0
	var max_width = 10.0
	for i in range(path_points.size()):
		var t2 = float(i) / float(path_points.size() - 1)
		var width = lerp(min_width, max_width, pow(sin(t2 * PI), 1.5))
		var half_width = int(width / 2.0)
		var center = path_points[i]
		for dcol in range(-half_width, half_width + 1):
			for drow in range(-half_width, half_width + 1):
				if dcol * dcol + drow * drow <= half_width * half_width:
					var fx = int(center.x + dcol)
					var fy = int(center.y + drow)
					if fx > 0 and fx < grid_width - 1 and fy > 0 and fy < grid_height - 1:
						var is_adjacent_to_green = _is_adjacent_to_type(fx, fy, SurfaceType.GREEN)
						var is_adjacent_to_tee = _is_adjacent_to_type(fx, fy, SurfaceType.TEE)
						var surf_here = get_cell(fx, fy)
						if surf_here != SurfaceType.GREEN \
						and surf_here != SurfaceType.TEE \
						and not is_adjacent_to_green \
						and not is_adjacent_to_tee:
							set_cell(fx, fy, SurfaceType.FAIRWAY)

	# --- SAND / WATER HAZARDS ---
	var sand_roll = randf()
	if sand_roll < 0.85:  # 85% of holes have bunkers (most real holes do)
		# 1. GREENSIDE BUNKERS - Strategic placement around the green
		# Real golf courses place bunkers at strategic angles to defend the green
		# Common positions: front-left, front-right, rear bunkers
		var green_adjacent: Array = []
		for col in range(grid_width):
			for row in range(grid_height):
				var surf_g = get_cell(col, row)
				if surf_g == SurfaceType.ROUGH or surf_g == SurfaceType.FAIRWAY:
					if _is_adjacent_to_type(col, row, SurfaceType.GREEN):
						# Calculate position relative to green center for strategic placement
						var rel_col = col - green_center_col
						var rel_row = row - green_center_row
						green_adjacent.append({"pos": Vector2i(col, row), "rel": Vector2(rel_col, rel_row)})

		# Place 1-3 greenside bunkers at strategic positions
		var greenside_bunker_count = 1 + randi() % 3
		var bunker_positions_used: Array = []  # Track which quadrants have bunkers
		var used = {}
		
		for i in range(greenside_bunker_count):
			if green_adjacent.size() == 0:
				break
			
			# Try to pick positions in different quadrants for strategic variety
			var best_idx = -1
			var best_score = -999.0
			for idx in range(green_adjacent.size()):
				var candidate = green_adjacent[idx]
				var rel = candidate.rel
				# Score based on strategic position (front and sides preferred over rear)
				var position_score = 0.0
				# Front bunkers (approaching from tee = higher row) are more common
				if rel.y < 0:  # Front of green
					position_score += 2.0
				elif rel.y > 1:  # Rear
					position_score += 0.5
				# Side bunkers add lateral challenge
				if abs(rel.x) > 0:
					position_score += 1.0
				# Penalize if similar position already used
				for used_pos in bunker_positions_used:
					if sign(rel.x) == sign(used_pos.x) and sign(rel.y) == sign(used_pos.y):
						position_score -= 3.0
				# Add randomness
				position_score += randf() * 2.0
				
				if position_score > best_score:
					best_score = position_score
					best_idx = idx
			
			if best_idx == -1:
				best_idx = randi() % green_adjacent.size()
			
			var start_data = green_adjacent[best_idx]
			var start = start_data.pos
			bunker_positions_used.append(start_data.rel)
			green_adjacent.remove_at(best_idx)

			# Greenside bunkers are typically 2-5 cells (smaller than fairway bunkers)
			var clump_size = 2 + randi() % 4
			var sand_tiles: Array = [start]
			set_cell(start.x, start.y, SurfaceType.SAND)
			used[Vector2(start.x, start.y)] = true

			var directions = [
				Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, -1)
			]

			for j in range(1, clump_size):
				var placed_sand = false
				var tries_sand = 0
				while not placed_sand and tries_sand < 8:
					var base = sand_tiles[randi() % sand_tiles.size()]
					var dir = directions[randi() % directions.size()]
					var nx = base.x + dir.x
					var ny = base.y + dir.y
					var key = Vector2(nx, ny)
					if nx > 0 and nx < grid_width - 1 and ny > 0 and ny < grid_height - 1:
						var surf_n = get_cell(nx, ny)
						if (surf_n == SurfaceType.ROUGH or surf_n == SurfaceType.FAIRWAY) \
						and not used.has(key) \
						and not _is_adjacent_to_type(nx, ny, SurfaceType.TEE):
							set_cell(nx, ny, SurfaceType.SAND)
							sand_tiles.append(Vector2i(nx, ny))
							used[key] = true
							placed_sand = true
					tries_sand += 1

		# 2. FAIRWAY BUNKERS - Placed at landing zones to challenge tee shots
		# Landing zone is typically 200-250 yards from tee, roughly 1/3 to 1/2 of hole
		if randf() < 0.6:  # 60% of holes have fairway bunkers
			var landing_zone_start = tee_row + int(grid_height * 0.25)
			var landing_zone_end = tee_row + int(grid_height * 0.45)
			var fairway_bunker_count = 1 + randi() % 2  # 1-2 fairway bunkers
			
			var fb_directions = [
				Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, -1)
			]
			
			for fb in range(fairway_bunker_count):
				var attempts = 0
				var placed = false
				while not placed and attempts < 15:
					var fb_row = landing_zone_start + randi() % max(1, landing_zone_end - landing_zone_start)
					var fb_col = 1 + randi() % (grid_width - 2)
					
					# Must be on fairway edge (strategic) or just off fairway
					if _is_fairway_edge(fb_col, fb_row) or \
					   (get_cell(fb_col, fb_row) == SurfaceType.ROUGH and _is_adjacent_to_type(fb_col, fb_row, SurfaceType.FAIRWAY)):
						# Don't place near tee or green
						if not _is_adjacent_to_type(fb_col, fb_row, SurfaceType.TEE) \
						and not _is_adjacent_to_type(fb_col, fb_row, SurfaceType.GREEN):
							var fb_size = 2 + randi() % 4
							var fb_tiles: Array = [Vector2i(fb_col, fb_row)]
							set_cell(fb_col, fb_row, SurfaceType.SAND)
							used[Vector2(fb_col, fb_row)] = true
							
							for j in range(1, fb_size):
								var placed_fb = false
								var tries_fb = 0
								while not placed_fb and tries_fb < 8:
									var base_fb = fb_tiles[randi() % fb_tiles.size()]
									var dir_fb = fb_directions[randi() % fb_directions.size()]
									var nx_fb = base_fb.x + dir_fb.x
									var ny_fb = base_fb.y + dir_fb.y
									var key_fb = Vector2(nx_fb, ny_fb)
									if nx_fb > 0 and nx_fb < grid_width - 1 and ny_fb > 0 and ny_fb < grid_height - 1:
										var surf_fb = get_cell(nx_fb, ny_fb)
										if (surf_fb == SurfaceType.ROUGH or surf_fb == SurfaceType.FAIRWAY) \
										and not used.has(key_fb) \
										and not _is_adjacent_to_type(nx_fb, ny_fb, SurfaceType.TEE) \
										and not _is_adjacent_to_type(nx_fb, ny_fb, SurfaceType.GREEN):
											set_cell(nx_fb, ny_fb, SurfaceType.SAND)
											fb_tiles.append(Vector2i(nx_fb, ny_fb))
											used[key_fb] = true
											placed_fb = true
									tries_fb += 1
							placed = true
					attempts += 1

		# 3. Water clumps on fairway edges (ponds/streams)
		var water_clump_chance = 0.02
		var water_clump_attempts = int(grid_width * grid_height * water_clump_chance)
		var dir_edges = [
			Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1)
		]

		for i in range(water_clump_attempts):
			var col_w = 1 + randi() % (grid_width - 2)
			var row_w = 1 + randi() % (grid_height - 2)
			if get_cell(col_w, row_w) == SurfaceType.FAIRWAY:
				var adj_green_w = _is_adjacent_to_type(col_w, row_w, SurfaceType.GREEN)
				var adj_tee_w = _is_adjacent_to_type(col_w, row_w, SurfaceType.TEE)
				var is_edge = _is_fairway_edge(col_w, row_w)

				if is_edge and not adj_green_w and not adj_tee_w:
					var clump_size_w = 1 + randi() % 6
					var water_tiles: Array = [Vector2i(col_w, row_w)]
					set_cell(col_w, row_w, SurfaceType.WATER)

					for j in range(1, clump_size_w):
						var placed_water = false
						var tries_water = 0
						while not placed_water and tries_water < 8:
							var base_w = water_tiles[randi() % water_tiles.size()]
							var dir_w = dir_edges[randi() % dir_edges.size()]
							var nx_w = base_w.x + dir_w.x
							var ny_w = base_w.y + dir_w.y
							if nx_w > 0 and nx_w < grid_width - 1 and ny_w > 0 and ny_w < grid_height - 1:
								if get_cell(nx_w, ny_w) == SurfaceType.FAIRWAY:
									set_cell(nx_w, ny_w, SurfaceType.WATER)
									water_tiles.append(Vector2i(nx_w, ny_w))
									placed_water = true
							tries_water += 1

		# 3. Sand clumps on fairway edges
		var sand_clump_chance2 = 0.04
		var sand_clump_attempts2 = int(grid_width * grid_height * sand_clump_chance2)

		for i in range(sand_clump_attempts2):
			var col_s = 1 + randi() % (grid_width - 2)
			var row_s = 1 + randi() % (grid_height - 2)
			if get_cell(col_s, row_s) == SurfaceType.FAIRWAY:
				var adj_green_s = _is_adjacent_to_type(col_s, row_s, SurfaceType.GREEN)
				var adj_tee_s = _is_adjacent_to_type(col_s, row_s, SurfaceType.TEE)
				var is_edge_s = _is_fairway_edge(col_s, row_s)

				if is_edge_s and not adj_green_s and not adj_tee_s:
					var clump_size_s = 1 + randi() % 6
					var sand_tiles2: Array = [Vector2i(col_s, row_s)]
					set_cell(col_s, row_s, SurfaceType.SAND)
					for j in range(1, clump_size_s):
						var placed_s2 = false
						var tries_s2 = 0
						while not placed_s2 and tries_s2 < 8:
							var base_s = sand_tiles2[randi() % sand_tiles2.size()]
							var dir_s = dir_edges[randi() % dir_edges.size()]
							var nx_s = base_s.x + dir_s.x
							var ny_s = base_s.y + dir_s.y
							if nx_s > 0 and nx_s < grid_width - 1 and ny_s > 0 and ny_s < grid_height - 1:
								if get_cell(nx_s, ny_s) == SurfaceType.FAIRWAY:
									set_cell(nx_s, ny_s, SurfaceType.SAND)
									sand_tiles2.append(Vector2i(nx_s, ny_s))
									placed_s2 = true
							tries_s2 += 1

		# 4. Rare sand in fairway
		for col in range(grid_width):
			for row in range(grid_height):
				if get_cell(col, row) == SurfaceType.FAIRWAY:
					var adj_green_f = _is_adjacent_to_type(col, row, SurfaceType.GREEN)
					var adj_tee_f = _is_adjacent_to_type(col, row, SurfaceType.TEE)
					if not adj_green_f and not adj_tee_f and randf() < 0.01:
						set_cell(col, row, SurfaceType.SAND)

	# --- NATURAL DEEP ROUGH & TREES (distance-based with noise) ---
	# Deep rough appears naturally at distance from play areas with organic variation
	# Trees are placed in deep rough areas to frame the hole
	for col in range(grid_width):
		for row in range(grid_height):
			var surf = get_cell(col, row)
			# Only convert ROUGH cells to DEEP_ROUGH or TREE
			if surf != SurfaceType.ROUGH:
				continue
			
			var dist = _distance_to_play_area(col, row)
			var noise_val = _noise_at(col, row, noise_seed)
			
			# Edge of grid always gets deep rough for boundary definition
			var is_edge = col == 0 or col == grid_width - 1 or row == 0 or row == grid_height - 1
			
			# Deep rough threshold: base distance of 3+ cells from play area
			# Noise adds organic variation (-1 to +2 cell variance)
			var deep_rough_threshold = 3.0 + noise_val * 1.5
			
			if is_edge or dist >= deep_rough_threshold:
				# Further cells (5+) have chance to become trees for hole framing
				var tree_threshold = 5.0 + noise_val * 2.0
				if dist >= tree_threshold and randf() < 0.35:
					set_cell(col, row, SurfaceType.TREE)
				else:
					set_cell(col, row, SurfaceType.DEEP_ROUGH)
			elif dist >= 2 and noise_val > 0.3 and randf() < 0.25:
				# Occasional deep rough patches closer to fairway for visual interest
				set_cell(col, row, SurfaceType.DEEP_ROUGH)

	# --- ORGANIC EDGE TRIMMING ---
	# Remove cells far from the playable area to create natural, irregular hole boundaries
	_trim_organic_edges()

	# --- GENERATE ELEVATION MAP ---
	# Calculate elevation for each cell based on surface type and terrain noise
	# This creates realistic golf course topography with mounds, depressions, etc.
	_generate_elevation()


# Trim edges organically to create natural hole boundaries
# Removes cells that are far from play areas using noise for irregular edges
func _trim_organic_edges() -> void:
	var trim_seed = randi() % 10000
	
	# Calculate the minimum distance needed to keep cells
	# Cells closer to play area are always kept, distant cells are trimmed based on noise
	for col in range(grid_width):
		for row in range(grid_height):
			var surf = get_cell(col, row)
			
			# Never trim essential play areas
			if surf == SurfaceType.TEE or surf == SurfaceType.GREEN or surf == SurfaceType.FAIRWAY or surf == SurfaceType.FLAG:
				continue
			
			# Never trim water (it's a feature)
			if surf == SurfaceType.WATER:
				continue
			
			var dist = _distance_to_play_area(col, row)
			
			# Use noise for organic variation in trim distance
			var noise_val = _noise_at(col, row, trim_seed)
			
			# Base trim threshold - cells beyond this distance may be removed
			# Higher values = more edge space kept
			var base_threshold = 7.0
			var threshold_variance = 3.0
			var trim_threshold = base_threshold + noise_val * threshold_variance
			
			# Gentle corner trimming only at the very edges
			var col_normalized = float(col) / float(grid_width - 1)  # 0 to 1
			var row_normalized = float(row) / float(grid_height - 1)  # 0 to 1
			
			# Distance from center line (0 at center, 0.5 at edges)
			var col_from_center = abs(col_normalized - 0.5)
			
			# Only trim corners, not sides - and less aggressively
			var corner_factor = 0.0
			if col_from_center > 0.35:  # Only outer edges
				corner_factor = (col_from_center - 0.35) * 2.0
				if row_normalized < 0.1 or row_normalized > 0.9:
					corner_factor *= 1.3  # Slight extra trimming at corners
			
			trim_threshold -= corner_factor * 1.5
			
			# Trim if distance exceeds threshold
			if dist > trim_threshold:
				# Mark as empty (will not be rendered)
				set_cell(col, row, -1)
	
	# Second pass: clean up isolated cells (cells with mostly empty neighbors)
	for col in range(grid_width):
		for row in range(grid_height):
			var surf = get_cell(col, row)
			if surf == -1 or surf == SurfaceType.TEE or surf == SurfaceType.GREEN or surf == SurfaceType.FAIRWAY or surf == SurfaceType.FLAG:
				continue
			
			# Count empty neighbors
			var empty_neighbors = 0
			var total_neighbors = 0
			for dc in range(-1, 2):
				for dr in range(-1, 2):
					if dc == 0 and dr == 0:
						continue
					var nc = col + dc
					var nr = row + dr
					if nc >= 0 and nc < grid_width and nr >= 0 and nr < grid_height:
						total_neighbors += 1
						if get_cell(nc, nr) == -1:
							empty_neighbors += 1
			
			# If more than half neighbors are empty, trim this cell too
			if total_neighbors > 0 and float(empty_neighbors) / float(total_neighbors) > 0.5:
				set_cell(col, row, -1)
	
	# Third pass: remove floating water (water not adjacent to any land)
	_cleanup_floating_water()


# Remove water cells that are not connected to land (floating water)
func _cleanup_floating_water() -> void:
	var water_to_remove: Array = []
	
	for col in range(grid_width):
		for row in range(grid_height):
			if get_cell(col, row) != SurfaceType.WATER:
				continue
			
			# Check if this water cell is adjacent to any land (non-empty, non-water)
			var has_land_neighbor = false
			for dc in range(-1, 2):
				for dr in range(-1, 2):
					if dc == 0 and dr == 0:
						continue
					var nc = col + dc
					var nr = row + dr
					if nc >= 0 and nc < grid_width and nr >= 0 and nr < grid_height:
						var neighbor_surf = get_cell(nc, nr)
						# Land is anything that's not water and not empty
						if neighbor_surf != -1 and neighbor_surf != SurfaceType.WATER:
							has_land_neighbor = true
							break
				if has_land_neighbor:
					break
			
			if not has_land_neighbor:
				water_to_remove.append(Vector2i(col, row))
	
	# Remove floating water cells
	for cell in water_to_remove:
		set_cell(cell.x, cell.y, -1)
	
	# Repeat until no more floating water (for water bodies that lost connection gradually)
	if water_to_remove.size() > 0:
		_cleanup_floating_water()


# Generate elevation map after all surface types are determined
func _generate_elevation() -> void:
	# First, generate landforms (hills, mounds, valleys, etc.)
	_generate_landforms()
	
	# Then calculate elevation for each cell including landform contributions
	for col in range(grid_width):
		for row in range(grid_height):
			var surf = get_cell(col, row)
			var elev = _calculate_elevation(col, row, surf)
			set_elevation(col, row, elev)
	
	# Smooth transitions between dramatically different elevations
	_smooth_elevation_transitions()


# Smooth elevation to avoid jarring transitions between areas
func _smooth_elevation_transitions() -> void:
	# Create a copy of current elevation for reference
	var smoothed: Array = []
	for col in range(grid_width):
		var col_array: Array = []
		for row in range(grid_height):
			col_array.append(elevation[col][row])
		smoothed.append(col_array)
	
	# Apply smoothing pass - average with neighbors for transition areas
	for col in range(1, grid_width - 1):
		for row in range(1, grid_height - 1):
			var surf = get_cell(col, row)
			
			# Only smooth certain transitions (e.g., bunker edges, water edges)
			if surf == SurfaceType.SAND or surf == SurfaceType.WATER:
				var sum_elev = elevation[col][row]
				var count = 1
				
				# Sample neighbors
				for dc in range(-1, 2):
					for dr in range(-1, 2):
						if dc == 0 and dr == 0:
							continue
						var nc = col + dc
						var nr = row + dr
						if nc >= 0 and nc < grid_width and nr >= 0 and nr < grid_height:
							var neighbor_surf = get_cell(nc, nr)
							# Only blend with non-water/sand neighbors for edge smoothing
							if neighbor_surf != SurfaceType.SAND and neighbor_surf != SurfaceType.WATER:
								sum_elev += elevation[nc][nr] * 0.3
								count += 0.3
				
				smoothed[col][row] = sum_elev / count
	
	# Apply smoothed values
	for col in range(grid_width):
		for row in range(grid_height):
			elevation[col][row] = smoothed[col][row]


# --- Mesh generation ----------------------------------------------------

func _generate_grid() -> void:
	_clear_course_nodes()

	var width = TILE_SIZE
	var height = TILE_SIZE * sqrt(3.0)

	var multimesh_nodes = {}
	for surf_type in SurfaceType.values():
		var mm_instance = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.mesh = mesh_map[surf_type]
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm_instance.multimesh = mm
		add_child(mm_instance)
		multimesh_nodes[surf_type] = mm_instance

	var counts = {}
	for surf_type in SurfaceType.values():
		counts[surf_type] = 0

	for col in range(grid_width):
		for row in range(grid_height):
			var surf = get_cell(col, row)
			if surf != -1:
				counts[surf] += 1

	for surf_type in SurfaceType.values():
		multimesh_nodes[surf_type].multimesh.instance_count = counts[surf_type]

	var offsets = {}
	for surf_type in SurfaceType.values():
		offsets[surf_type] = 0

	var green_cells: Array = []

	for col in range(grid_width):
		for row in range(grid_height):
			var surf = get_cell(col, row)
			if surf == -1:
				continue

			var idx = offsets[surf]
			var x_pos = col * width * 1.5
			var z_pos = row * height + (col % 2) * (height / 2.0)
			var y_pos = get_elevation(col, row)  # Use elevation for Y position
			var rot = Basis(Vector3.UP, PI / 6.0)
			var xform = Transform3D(rot, Vector3(x_pos, y_pos, z_pos))
			multimesh_nodes[surf].multimesh.set_instance_transform(idx, xform)
			offsets[surf] += 1

			if surf == SurfaceType.GREEN:
				green_cells.append(Vector2i(col, row))

	if green_cells.size() > 0:
		var flag_cell = green_cells[randi() % green_cells.size()]
		var flag_scene = FLAG
		var flag_instance = flag_scene.instantiate()
		var flag_elev = get_elevation(flag_cell.x, flag_cell.y)
		var flag_pos = Vector3(
			flag_cell.x * width * 1.5,
			flag_elev + 0.5,  # Flag sits on top of green elevation
			flag_cell.y * height + (flag_cell.x % 2) * (height / 2.0)
		)
		flag_instance.position = flag_pos
		flag_instance.add_to_group("flag")
		add_child(flag_instance)

	# Instance teebox model on TEE cells
	for col in range(grid_width):
		for row in range(grid_height):
			if get_cell(col, row) == SurfaceType.TEE:
				var teebox_instance = TEEBOX_MODEL.instantiate()
				var tee_x = col * width * 1.5
				var tee_z = row * height + (col % 2) * (height / 2.0)
				var tee_y = get_elevation(col, row)
				teebox_instance.position = Vector3(tee_x, tee_y, tee_z)
				teebox_instance.add_to_group("teebox")
				add_child(teebox_instance)
				
				# Place golf ball at center of tee box
				if golf_ball == null:
					golf_ball = GOLFBALL.instantiate()
					golf_ball.scale = Vector3(0.3, 0.3, 0.3)  # 50% size
					tee_position = Vector3(tee_x, tee_y + 0.7, tee_z)  # On top of teebox model
					golf_ball.position = tee_position
					golf_ball.add_to_group("golfball")
					add_child(golf_ball)

	# Instance trees at TREE cells
	# Trees are placed to frame the hole and provide visual boundaries
	for col in range(grid_width):
		for row in range(grid_height):
			if get_cell(col, row) == SurfaceType.TREE:
				# Pick a random tree model from the array
				var tree_scene = TREE_SCENES[randi() % TREE_SCENES.size()]
				var tree_instance = tree_scene.instantiate()
				
				var tree_x = col * width * 1.5
				var tree_z = row * height + (col % 2) * (height / 2.0)
				var tree_y = get_elevation(col, row)  # Use terrain elevation
				
				# Add random position offset for natural variation
				tree_x += (randf() - 0.5) * 0.4
				tree_z += (randf() - 0.5) * 0.4
				tree_instance.position = Vector3(tree_x, tree_y, tree_z)
				
				# Random Y rotation for variety
				tree_instance.rotation.y = randf() * TAU
				
				# Random slight tilt for natural look (max ~5 degrees)
				tree_instance.rotation.x = deg_to_rad(randf_range(-5.0, 5.0))
				tree_instance.rotation.z = deg_to_rad(randf_range(-5.0, 5.0))
				
				# Random scale with height bias for tree variety
				var base_scale = randf_range(0.6, 1.3)
				var height_scale = base_scale * randf_range(0.9, 1.3)  # Trees can be taller
				tree_instance.scale = Vector3(base_scale, height_scale, base_scale)
				
				# Apply random color variation to foliage (CSGSphere3D children)
				_apply_random_tree_colors(tree_instance)
				
				tree_instance.add_to_group("trees")
				add_child(tree_instance)
	
	# Spawn foliage (grass patches, bushes, rocks, flowers) based on surface type
	_spawn_foliage()


# Spawn grass, bushes, rocks, and flowers based on golf course landscaping rules
# Instantiates models directly from the features folder
func _spawn_foliage() -> void:
	var width = TILE_SIZE
	var height = TILE_SIZE * sqrt(3.0)
	
	# Foliage placement config: surface type -> list of {models, chance, scale_range}
	var foliage_config = {
		SurfaceType.ROUGH: [
			{"models": GRASS_MODELS, "chance": 0.20, "scale": Vector2(0.2, 0.4)},
			{"models": BUSH_MODELS, "chance": 0.04, "scale": Vector2(0.15, 0.3)},
			{"models": ROCK_MODELS, "chance": 0.02, "scale": Vector2(0.1, 0.2)},
		],
		SurfaceType.DEEP_ROUGH: [
			{"models": GRASS_MODELS, "chance": 0.15, "scale": Vector2(0.25, 0.45)},
			{"models": BUSH_MODELS, "chance": 0.10, "scale": Vector2(0.2, 0.4)},
			{"models": ROCK_MODELS, "chance": 0.04, "scale": Vector2(0.12, 0.25)},
			{"models": FLOWER_MODELS, "chance": 0.06, "scale": Vector2(0.15, 0.3)},
		],
		SurfaceType.SAND: [
			{"models": ROCK_MODELS, "chance": 0.06, "scale": Vector2(0.08, 0.15)},
		],
		SurfaceType.TREE: [
			{"models": BUSH_MODELS, "chance": 0.08, "scale": Vector2(0.12, 0.25)},
			{"models": GRASS_MODELS, "chance": 0.08, "scale": Vector2(0.15, 0.3)},
		],
	}
	
	for col in range(grid_width):
		for row in range(grid_height):
			var surface = get_cell(col, row)
			if surface not in foliage_config:
				continue
			
			var configs = foliage_config[surface]
			for cfg in configs:
				if randf() > cfg["chance"]:
					continue
				
				var models = cfg["models"]
				if models.is_empty():
					continue
				
				# Pick random model and instantiate it
				var model_scene: PackedScene = models[randi() % models.size()]
				var instance = model_scene.instantiate()
				
				# Calculate position with offset from cell center
				var offset_x = (randf() - 0.5) * 0.6
				var offset_z = (randf() - 0.5) * 0.6
				var pos_x = col * width * 1.5 + offset_x
				var pos_z = row * height + (col % 2) * (height / 2.0) + offset_z
				
				# Sample elevation at the actual offset position for more accurate placement
				# Find the nearest cell to the offset position
				var world_pos = Vector3(pos_x, 0, pos_z)
				var nearest_cell = world_to_grid(world_pos)
				var pos_y = get_elevation(nearest_cell.x, nearest_cell.y)
				
				# FBX models typically have their origin at center, not bottom
				# We need to raise them by roughly half their height to sit on terrain
				# Model base height is ~1-2 units, scaled down significantly
				var scale_range = cfg["scale"]
				var base_scale = randf_range(scale_range.x, scale_range.y)
				var estimated_model_height = 1.5  # Approximate unscaled model height
				var vertical_offset = (estimated_model_height * base_scale) * 0.5  # Raise by half the scaled height
				
				instance.position = Vector3(pos_x, pos_y + vertical_offset, pos_z)
				
				# Random rotation
				instance.rotation.y = randf() * TAU
				instance.rotation.x = deg_to_rad(randf_range(-3.0, 3.0))
				instance.rotation.z = deg_to_rad(randf_range(-3.0, 3.0))
				
				# Apply scale (already calculated above for vertical offset)
				instance.scale = Vector3(base_scale, base_scale * randf_range(0.9, 1.1), base_scale)
				
				instance.add_to_group("foliage")
				add_child(instance)


# Apply random color variation to tree foliage spheres
func _apply_random_tree_colors(tree: Node3D) -> void:
	for child in tree.get_children():
		if child is CSGSphere3D and child.material:
			var mat = child.material
			if mat is StandardMaterial3D:
				var new_mat = mat.duplicate()
				var base_color = new_mat.albedo_color
				# Vary hue, saturation, and value slightly
				var h = base_color.h + randf_range(-0.03, 0.03)
				var s = clamp(base_color.s + randf_range(-0.15, 0.15), 0.3, 1.0)
				var v = clamp(base_color.v + randf_range(-0.2, 0.2), 0.15, 0.9)
				new_mat.albedo_color = Color.from_hsv(h, s, v)
				child.material = new_mat


# --- UI callbacks -------------------------------------------------------

func _on_regenerate_button_pressed() -> void:
	# Reset target lock
	target_locked = false
	locked_cell = Vector2i(-1, -1)
	trajectory_mesh.visible = false
	trajectory_shadow_mesh.visible = false
	target_highlight_mesh.visible = false
	_hide_all_aoe_highlights()
	
	# Cancel any in-progress shot
	if shot_manager:
		shot_manager.cancel_shot()
	
	_clear_course_nodes()
	_generate_course()
	_generate_grid()
	_log_hole_info()
	_update_mini_cameras()
	
	# Start a fresh shot
	_start_new_shot()


func _on_button_pressed() -> void:
	# Reset target lock
	target_locked = false
	locked_cell = Vector2i(-1, -1)
	trajectory_mesh.visible = false
	trajectory_shadow_mesh.visible = false
	target_highlight_mesh.visible = false
	_hide_all_aoe_highlights()
	
	# Cancel any in-progress shot
	if shot_manager:
		shot_manager.cancel_shot()
	
	_clear_course_nodes()
	_generate_course()
	_generate_grid()
	_log_hole_info()
	_update_mini_cameras()
	
	# Start a fresh shot
	_start_new_shot()
