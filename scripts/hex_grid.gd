extends Node3D

enum SurfaceType {
	TEE, FAIRWAY, ROUGH, DEEP_ROUGH, GREEN, SAND, WATER, TREE, FLAG
}

# Golf club types and their max distances in tiles
enum ClubType {
	DRIVER, WOOD_3, WOOD_5, IRON_3, IRON_5, IRON_6, IRON_7, IRON_8, IRON_9, PITCHING_WEDGE, SAND_WEDGE, PUTTER
}

# Spin types affecting ball roll after landing
enum SpinType {
	NONE,      # No spin effect
	TOPSPIN,   # Ball rolls forward (+1 tile)
	BACKSPIN   # Ball rolls backward (-1 tile)
}

# Current shot modifiers
var current_spin: SpinType = SpinType.NONE

# Spin button references
var spin_buttons: Dictionary = {}   # SpinType -> Button

# ============================================================================
# CLUB STATS SYSTEM
# Each club has base stats that can be modified by lie, cards, wind, timing, etc.
# All modifiers are ADDITIVE (+/- values that stack)
# ============================================================================

# Complete club stats dictionary
# distance: max tiles the club can hit
# accuracy: base AOE rings (0=perfect, higher=worse aim spread)
# roll: tiles of roll after landing
# loft: 1-5 scale, affects wind sensitivity & spin potential
const CLUB_STATS = {
	ClubType.DRIVER: {
		"name": "Driver",
		"distance": 22,
		"accuracy": 1,      # Hardest to hit straight
		"roll": 3,          # Hot landing, lots of roll
		"loft": 1,          # Low loft
		"arc_height": 12.0,
	},
	ClubType.WOOD_3: {
		"name": "3 Wood",
		"distance": 20,
		"accuracy": 1,
		"roll": 3,
		"loft": 1,
		"arc_height": 11.0,
	},
	ClubType.WOOD_5: {
		"name": "5 Wood",
		"distance": 18,
		"accuracy": 1,
		"roll": 2,
		"loft": 2,
		"arc_height": 10.0,
	},
	ClubType.IRON_3: {
		"name": "3 Iron",
		"distance": 17,
		"accuracy": 1,
		"roll": 2,
		"loft": 2,
		"arc_height": 9.0,
	},
	ClubType.IRON_5: {
		"name": "5 Iron",
		"distance": 16,
		"accuracy": 0,
		"roll": 2,
		"loft": 2,
		"arc_height": 8.5,
	},
	ClubType.IRON_6: {
		"name": "6 Iron",
		"distance": 15,
		"accuracy": 0,
		"roll": 1,
		"loft": 3,
		"arc_height": 8.0,
	},
	ClubType.IRON_7: {
		"name": "7 Iron",
		"distance": 14,
		"accuracy": 0,
		"roll": 1,
		"loft": 3,
		"arc_height": 7.5,
	},
	ClubType.IRON_8: {
		"name": "8 Iron",
		"distance": 13,
		"accuracy": 0,
		"roll": 1,
		"loft": 3,
		"arc_height": 7.0,
	},
	ClubType.IRON_9: {
		"name": "9 Iron",
		"distance": 12,
		"accuracy": 0,
		"roll": 1,
		"loft": 4,
		"arc_height": 6.5,
	},
	ClubType.PITCHING_WEDGE: {
		"name": "Pitching Wedge",
		"distance": 11,
		"accuracy": 0,
		"roll": 0,
		"loft": 4,
		"arc_height": 6.0,
	},
	ClubType.SAND_WEDGE: {
		"name": "Sand Wedge",
		"distance": 9,
		"accuracy": 0,
		"roll": 0,
		"loft": 5,          # Highest loft
		"arc_height": 5.0,
	},
	ClubType.PUTTER: {
		"name": "Putter",
		"distance": 5,
		"accuracy": 0,
		"roll": 5,
		"loft": 0,
		"arc_height": 0.0,
	}
}

# Current selected club
var current_club: ClubType = ClubType.DRIVER

func set_club_by_name(club_name: String) -> void:
	"""Set current club by string name (e.g. 'DRIVER', 'IRON_5')"""
	var type = ClubType.get(club_name)
	if type != null:
		current_club = type
		_update_club_button_visuals()
		_update_trajectory(Vector3.ZERO) # Refresh trajectory
		_update_dim_overlays()

# Club button references
var club_buttons: Array[Button] = []
var club_range_highlights: Array[MeshInstance3D] = []  # Ring highlights for range preview
var is_previewing_range: bool = false  # True when hovering a club button

# Dim overlays for unavailable tiles (out of range or behind ball)
var dim_overlay_meshes: Array[MeshInstance3D] = []
var dim_overlays_visible: bool = false

const FLAG = preload("uid://cu7517xrwfodv")
const TEEBOX_MODEL = preload("res://scenes/tiles/teebox-model.tscn")
const GOLFBALL = preload("res://scenes/golf_ball.tscn")

# Deck Definitions
@export var starter_deck: DeckDefinition = preload("res://resources/decks/starter_deck.tres")
@export var club_deck: DeckDefinition = preload("res://resources/decks/club_deck.tres")

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
@onready var water_effect: ColorRect = %"shoteffects-water"

# Track previous tile for water penalty
var previous_valid_tile: Vector2i = Vector2i(-1, -1)

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

# Tile mesh height offset - tiles are hex prisms with Y from -0.5 to +0.5
# This offset places objects on top of the tile surface
const TILE_SURFACE_OFFSET := 0.5

# Ball radius offset - the ball mesh scaled at 0.3 has approximate radius 0.15
# Add this to surface position so ball sits ON TOP of tile, not inside it
const BALL_RADIUS_OFFSET := 0.15

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
	3: {"min_yards": 150, "max_yards": 300, "min_width": 10, "max_width": 18},
	4: {"min_yards": 320, "max_yards": 480, "min_width": 14, "max_width": 28},
	5: {"min_yards": 500, "max_yards": 650, "min_width": 20, "max_width": 35}
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

# External camera/viewport for mouse picking (set by HoleViewer)
var external_camera: Camera3D = null
var external_viewport: SubViewport = null

# Tile highlighting - using dictionaries keyed by cell Vector2i for individual access
var highlight_mesh: MeshInstance3D = null  # Main hover highlight
var aoe_highlights: Dictionary = {}  # Key: Vector2i cell position, Value: MeshInstance3D
var hovered_cell: Vector2i = Vector2i(-1, -1)

# Tile nodes storage - keyed by cell position for individual modification
var tile_nodes: Dictionary = {}  # Key: Vector2i cell position, Value: Node3D (the tile instance)

# Trajectory line
var trajectory_mesh: MeshInstance3D = null
var trajectory_shadow_mesh: MeshInstance3D = null  # Shadow line on ground
var curved_trajectory_mesh: MeshInstance3D = null  # Curved trajectory for hook/slice
var trajectory_height: float = 5.0  # Peak height of ball flight arc (will vary by club)

# Target locking
var target_locked: bool = false
var locked_cell: Vector2i = Vector2i(-1, -1)
var locked_target_pos: Vector3 = Vector3.ZERO
var target_highlight_mesh: MeshInstance3D = null  # White highlight on active/locked cell

# Animation state
var pending_next_shot: bool = false  # True if player has pre-aimed during animation
var current_ball_tween: Tween = null  # Reference to current ball animation tween

# Shot system components
var shot_manager: ShotManager = null
var modifier_manager: ModifierManager = null
var aoe_system: AOESystem = null
var lie_system: Node = null  # LieSystem
var shot_ui: ShotUI = null
var putting_system: Node = null  # PuttingSystem for green play
var wind_system: Node = null  # WindSystem for environmental effects
var hole_viewer: Node = null  # HoleViewer reference

# Card system components
var card_system: CardSystemManager = null
var card_library: CardLibrary = null
var deck_manager: DeckManager = null


# UI references for lie info panel
var lie_info_panel: PanelContainer = null
var lie_name_label: Label = null
var lie_description_label: RichTextLabel = null
var lie_modifiers_label: RichTextLabel = null

# Tile data storage - HexTile resources keyed by cell position
var tile_data: Dictionary = {}  # Key: Vector2i, Value: HexTile

# Flag position for distance calculations
var flag_position: Vector2i = Vector2i(-1, -1)

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


func get_grid_width() -> int:
	return grid_width


func get_grid_height() -> int:
	return grid_height


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


func _remove_disconnected_water() -> void:
	"""Remove water tiles that aren't connected to the playable area.
	   Uses flood fill to find water bodies and checks if they touch any playable tile."""
	
	var visited: Dictionary = {}  # Vector2i -> bool
	var playable_types = [SurfaceType.FAIRWAY, SurfaceType.GREEN, SurfaceType.TEE, SurfaceType.ROUGH, SurfaceType.SAND]
	
	# Find all water tiles
	var all_water_tiles: Array[Vector2i] = []
	for col in range(grid_width):
		for row in range(grid_height):
			if get_cell(col, row) == SurfaceType.WATER:
				all_water_tiles.append(Vector2i(col, row))
	
	# Process each water tile that hasn't been visited
	for water_tile in all_water_tiles:
		if visited.has(water_tile):
			continue
		
		# Flood fill to find all connected water tiles in this body
		var water_body: Array[Vector2i] = []
		var touches_playable = false
		var queue: Array[Vector2i] = [water_tile]
		
		while queue.size() > 0:
			var current = queue.pop_front()
			
			if visited.has(current):
				continue
			visited[current] = true
			
			var cx = current.x
			var cy = current.y
			
			if cx < 0 or cx >= grid_width or cy < 0 or cy >= grid_height:
				continue
			
			if get_cell(cx, cy) != SurfaceType.WATER:
				continue
			
			water_body.append(current)
			
			# Check all 8 neighbors
			for dcol in range(-1, 2):
				for drow in range(-1, 2):
					if dcol == 0 and drow == 0:
						continue
					var ncol = cx + dcol
					var nrow = cy + drow
					
					if ncol >= 0 and ncol < grid_width and nrow >= 0 and nrow < grid_height:
						var neighbor_surf = get_cell(ncol, nrow)
						
						# Check if this neighbor is a playable tile
						if neighbor_surf in playable_types:
							touches_playable = true
						
						# Add unvisited water neighbors to queue
						var neighbor_pos = Vector2i(ncol, nrow)
						if neighbor_surf == SurfaceType.WATER and not visited.has(neighbor_pos):
							queue.append(neighbor_pos)
		
		# If this water body doesn't touch any playable tile, remove it
		if not touches_playable:
			for tile in water_body:
				set_cell(tile.x, tile.y, SurfaceType.ROUGH)


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


# Get the surface position for a cell (on top of the tile mesh)
func get_tile_surface_position(cell: Vector2i) -> Vector3:
	"""Returns position on top of the tile surface, accounting for mesh height and ball radius"""
	var pos = get_tile_world_position(cell)
	pos.y += TILE_SURFACE_OFFSET + BALL_RADIUS_OFFSET
	return pos


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
	_init_shot_system()
	_init_club_menu()
	_generate_course()
	_generate_grid()
	_log_hole_info()
	_start_new_shot()
	_play_opening_transition()


func _init_club_menu() -> void:
	"""Initialize club selection buttons"""
	var control = get_node_or_null("../../Control")
	if not control:
		return
	
	var container = control.get_node_or_null("HFlowContainer")
	if not container:
		return
	
	# Map button names to club types
	var button_club_map = {
		"Button": ClubType.DRIVER,
		"Button2": ClubType.WOOD_3,
		"Button3": ClubType.WOOD_5,
		"Button4": ClubType.IRON_3,
		"Button5": ClubType.IRON_5,
		"Button6": ClubType.IRON_6,
		"Button7": ClubType.IRON_7,
		"Button8": ClubType.IRON_8,
		"Button9": ClubType.IRON_9,
		"Button10": ClubType.PITCHING_WEDGE,
		"Button11": ClubType.SAND_WEDGE,
	}
	
	# Connect all club buttons
	for button_name in button_club_map:
		var button = container.get_node_or_null(button_name)
		if button and button is Button:
			var club_type = button_club_map[button_name]
			club_buttons.append(button)
			
			# Connect pressed signal with club type
			button.pressed.connect(_on_club_button_pressed.bind(club_type))
			
			# Connect hover signals for range preview
			button.mouse_entered.connect(_on_club_button_hover.bind(club_type))
			button.mouse_exited.connect(_on_club_button_hover_end)
	
	# Update button visuals to show selected club
	_update_club_button_visuals()


func _on_spin_button_toggled(spin: SpinType) -> void:
	"""Handle spin button toggle - only one spin can be active"""
	var button = spin_buttons.get(spin)
	if button and button.button_pressed:
		# Enable this spin, disable others
		current_spin = spin
		for other_spin in spin_buttons:
			if other_spin != spin:
				spin_buttons[other_spin].button_pressed = false
	else:
		# If toggled off, go back to no spin
		current_spin = SpinType.NONE
	
	# Update trajectory to reflect new spin
	_refresh_trajectory()


func _get_spin_name(spin: SpinType) -> String:
	match spin:
		SpinType.NONE: return "None"
		SpinType.TOPSPIN: return "Topspin"
		SpinType.BACKSPIN: return "Backspin"
		_: return "Unknown"


func _refresh_trajectory() -> void:
	"""Refresh the trajectory display based on current target"""
	if target_locked and locked_target_pos != Vector3.ZERO:
		_update_trajectory(locked_target_pos)
	elif hovered_cell != Vector2i(-1, -1):
		var hx = hovered_cell.x
		var hy = hovered_cell.y
		var x_pos = hx * TILE_SIZE * 1.5
		var z_pos = hy * TILE_SIZE * sqrt(3.0) + (hx % 2) * TILE_SIZE * sqrt(3.0) / 2.0
		var y_pos = get_elevation(hx, hy)
		_update_trajectory(Vector3(x_pos, y_pos, z_pos))


func get_shape_adjusted_landing(aim_tile: Vector2i) -> Vector2i:
	"""Return the aim tile directly - curve is now handled by swing meter."""
	return aim_tile


func _is_valid_landing_tile(tile: Vector2i) -> bool:
	"""Check if a tile is a valid landing spot (in bounds and not water)."""
	if tile.x < 0 or tile.x >= grid_width or tile.y < 0 or tile.y >= grid_height:
		return false
	var surface = get_cell(tile.x, tile.y)
	return surface != -1 and surface != SurfaceType.WATER


func get_shape_adjusted_world_position(aim_tile: Vector2i) -> Vector3:
	"""Get the world position of the shape-adjusted landing tile."""
	var adjusted_tile = get_shape_adjusted_landing(aim_tile)
	return get_tile_surface_position(adjusted_tile)


func get_shape_aoe_offset() -> int:
	"""Returns 0 - curve is now handled by swing meter."""
	return 0


func _on_club_button_pressed(club_type: ClubType) -> void:
	"""Handle club button click - select the club"""
	current_club = club_type
	trajectory_height = CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).arc_height
	_update_club_button_visuals()
	_hide_range_preview()
	_update_dim_overlays()  # Update dim overlays for new club range


func _on_club_button_hover(club_type: ClubType) -> void:
	"""Show range preview when hovering over a club button"""
	is_previewing_range = true
	var max_dist = CLUB_STATS.get(club_type, CLUB_STATS[ClubType.IRON_7]).distance
	_show_range_preview(max_dist)


func _on_club_button_hover_end() -> void:
	"""Hide range preview when mouse leaves club button"""
	is_previewing_range = false
	_hide_range_preview()


func _show_range_preview(max_distance: int) -> void:
	"""Show a ring of highlights at max distance from ball (only forward from ball)"""
	_hide_range_preview()
	
	if golf_ball == null:
		return
	
	var ball_tile = world_to_grid(golf_ball.position)
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	
	# Find all tiles at approximately max_distance from ball (only forward)
	for col in range(grid_width):
		for row in range(grid_height):
			var cell = Vector2i(col, row)
			
			# Only show forward tiles (row >= ball row)
			if row < ball_tile.y:
				continue
			
			var dist = get_tile_distance(ball_tile, cell)
			
			# Show tiles at max distance (the range boundary)
			if dist == max_distance:
				var surface = get_cell(col, row)
				if surface != -1 and surface != SurfaceType.WATER:
					var highlight = _create_range_highlight()
					var x_pos = col * width * 1.5
					var z_pos = row * hex_height + (col % 2) * (hex_height / 2.0)
					var y_pos = get_elevation(col, row) + 0.6
					highlight.position = Vector3(x_pos, y_pos, z_pos)
					highlight.rotation.y = PI / 6.0
					highlight.visible = true
					club_range_highlights.append(highlight)


func _create_range_highlight() -> MeshInstance3D:
	"""Create a range preview highlight mesh"""
	var mesh = MeshInstance3D.new()
	
	# Create a torus/ring shape to show range boundary
	var torus = TorusMesh.new()
	torus.inner_radius = TILE_SIZE * 0.35
	torus.outer_radius = TILE_SIZE * 0.5
	torus.rings = 8
	torus.ring_segments = 6
	mesh.mesh = torus
	
	# Cyan/blue color for range preview
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.5)  # Cyan, semi-transparent
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(mesh)
	return mesh


func _hide_range_preview() -> void:
	"""Hide and clean up range preview highlights"""
	for highlight in club_range_highlights:
		if is_instance_valid(highlight):
			highlight.queue_free()
	club_range_highlights.clear()


func _update_club_button_visuals() -> void:
	"""Update button appearance to show which club is selected"""
	var club_types = [
		ClubType.DRIVER, ClubType.WOOD_3, ClubType.WOOD_5,
		ClubType.IRON_3, ClubType.IRON_5, ClubType.IRON_6,
		ClubType.IRON_7, ClubType.IRON_8, ClubType.IRON_9,
		ClubType.PITCHING_WEDGE, ClubType.SAND_WEDGE
	]
	
	for i in range(mini(club_buttons.size(), club_types.size())):
		var button = club_buttons[i]
		var club_type = club_types[i]
		
		if club_type == current_club:
			# Selected club - make it stand out
			button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))  # Gold
			button.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.0))
			button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.3))
		else:
			# Unselected - normal appearance
			button.remove_theme_color_override("font_color")
			button.remove_theme_color_override("font_pressed_color")
			button.remove_theme_color_override("font_hover_color")


func _get_club_name(club: ClubType) -> String:
	"""Get display name for a club"""
	match club:
		ClubType.DRIVER: return "Driver"
		ClubType.WOOD_3: return "3 Wood"
		ClubType.WOOD_5: return "5 Wood"
		ClubType.IRON_3: return "3 Iron"
		ClubType.IRON_5: return "5 Iron"
		ClubType.IRON_6: return "6 Iron"
		ClubType.IRON_7: return "7 Iron"
		ClubType.IRON_8: return "8 Iron"
		ClubType.IRON_9: return "9 Iron"
		ClubType.PITCHING_WEDGE: return "Pitching Wedge"
		ClubType.SAND_WEDGE: return "Sand Wedge"
		_: return "Unknown"


func get_current_club_distance() -> int:
	"""Get max distance in tiles for current club, modified by current lie"""
	var base_distance = CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).distance
	
	# Apply lie power modifier if we have a shot context with lie info
	if shot_manager and shot_manager.current_context:
		var power_mod = int(shot_manager.current_context.power_mod)
		return maxi(1, base_distance + power_mod)
	
	return base_distance


func get_current_club_base_distance() -> int:
	"""Get unmodified max distance in tiles for current club"""
	return CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).distance


func get_current_club_loft() -> int:
	"""Get loft value for current club (1-5 scale)"""
	return CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).loft


func get_current_shot_stats() -> Dictionary:
	"""Get complete shot stats: base club stats + all modifiers = final stats"""
	var club_stats = CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7])
	
	# Base stats from club
	var base = {
		"distance": club_stats.distance,
		"accuracy": club_stats.accuracy,
		"roll": club_stats.roll,
		"loft": club_stats.loft,
		"curve": 0,  # Base curve is 0 (straight shot)
	}
	
	# Modifiers from all sources (lie, cards, wind, etc.)
	var mods = {
		"distance_mod": 0,
		"accuracy_mod": 0,
		"roll_mod": 0,
		"curve_mod": 0,
	}
	
	# Get modifiers from shot context (lie effects, cards, etc.)
	if shot_manager and shot_manager.current_context:
		var ctx = shot_manager.current_context
		mods.distance_mod = int(ctx.power_mod)
		mods.accuracy_mod = int(ctx.accuracy_mod)
		mods.roll_mod = int(ctx.roll_mod)
		mods.curve_mod = ctx.curve_mod
	
	# Final calculated stats
	var final = {
		"distance": maxi(1, base.distance + mods.distance_mod),
		"accuracy": maxi(0, base.accuracy + mods.accuracy_mod),
		"roll": maxi(0, base.roll + mods.roll_mod),
		"curve": base.curve + mods.curve_mod,
		"loft": base.loft,
	}
	
	return {
		"club_name": club_stats.name,
		"base": base,
		"mods": mods,
		"final": final,
	}


func _set_club(club_type: ClubType) -> void:
	"""Set the current club and update visuals."""
	current_club = club_type
	trajectory_height = CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).arc_height
	_update_club_button_visuals()
	_update_dim_overlays()
	_refresh_stats_panel()


func _refresh_stats_panel() -> void:
	"""Refresh the lie info panel with current club stats."""
	if shot_manager and shot_manager.current_context and lie_system:
		var ctx = shot_manager.current_context
		if ctx.start_tile.x >= 0:
			var lie_info = lie_system.calculate_lie(self, ctx.start_tile)
			_update_lie_info_panel(lie_info)


func get_tile_distance(from: Vector2i, to: Vector2i) -> int:
	"""Calculate hex grid distance between two tiles (in tiles, not yards)"""
	# For hex grids, we use axial distance calculation
	var dx = abs(to.x - from.x)
	var dy = abs(to.y - from.y)
	# Approximate hex distance (works well for pointy-top offset coords)
	return maxi(dx, dy + dx / 2)


func is_forward_from_ball(target_cell: Vector2i) -> bool:
	"""Check if target is forward (toward flag direction) from ball position.
	   In this course layout, tee is at low Y and flag is at high Y,
	   so forward means target.y >= ball.y.
	   EXCEPTION: If the flag/hole is behind the ball (ball overshot), allow backward shots."""
	if golf_ball == null:
		return true
	var ball_tile = world_to_grid(golf_ball.position)
	
	# Check if flag is behind the ball (ball has overshot the hole)
	var flag_is_behind = false
	if flag_position.x >= 0 and flag_position.y >= 0:
		flag_is_behind = flag_position.y < ball_tile.y
	
	# If flag is behind us, allow backward shots (toward the flag)
	if flag_is_behind:
		return true
	
	# Normal case: Target must be at same row or further down the course (higher Y = toward flag)
	return target_cell.y >= ball_tile.y


func is_tile_available(cell: Vector2i) -> bool:
	"""Check if a tile is available to hit (in range AND forward)"""
	if golf_ball == null:
		return true
	
	var ball_tile = world_to_grid(golf_ball.position)
	var tile_dist = get_tile_distance(ball_tile, cell)
	var max_dist = get_current_club_distance()
	
	# Must be within range AND forward from ball
	return tile_dist <= max_dist and is_forward_from_ball(cell)


func _update_dim_overlays() -> void:
	"""Create or update dim overlays for unavailable tiles (only forward, out of range)"""
	# Clear existing overlays
	_clear_dim_overlays()
	
	if golf_ball == null:
		return
	
	var ball_tile = world_to_grid(golf_ball.position)
	var max_dist = get_current_club_distance()
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	
	var overlay_count = 0
	
	# Iterate all tiles and dim those that are out of range (but only forward tiles)
	for col in range(grid_width):
		for row in range(grid_height):
			var cell = Vector2i(col, row)
			var surface = get_cell(col, row)
			
			# Skip empty tiles and water (already visually distinct)
			if surface == -1 or surface == SurfaceType.WATER:
				continue
			
			# Skip tiles behind the ball - don't dim those at all
			if not is_forward_from_ball(cell):
				continue
			
			# Only dim forward tiles that are out of range
			var tile_dist = get_tile_distance(ball_tile, cell)
			if tile_dist > max_dist:
				# Create dim overlay for this tile
				var overlay = _create_dim_overlay()
				var x_pos = col * width * 1.5
				var z_pos = row * hex_height + (col % 2) * (hex_height / 2.0)
				var y_pos = get_elevation(col, row) + 0.3  # Higher to be visible above tiles
				overlay.position = Vector3(x_pos, y_pos, z_pos)
				overlay.rotation.y = PI / 6.0
				overlay.visible = true
				dim_overlay_meshes.append(overlay)
				overlay_count += 1
	
	dim_overlays_visible = true


func _create_dim_overlay() -> MeshInstance3D:
	"""Create a dark semi-transparent overlay mesh for unavailable tiles"""
	var mesh_inst = MeshInstance3D.new()
	
	# Use a hexagon mesh that matches tile shape
	var hex_mesh = CylinderMesh.new()
	hex_mesh.height = 0.02
	hex_mesh.top_radius = TILE_SIZE * 0.9
	hex_mesh.bottom_radius = TILE_SIZE * 0.9
	hex_mesh.radial_segments = 6  # Hexagon
	mesh_inst.mesh = hex_mesh
	
	# Dark semi-transparent material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.3)  # 30% opacity
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true  # Render on top of other geometry
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(mesh_inst)
	return mesh_inst


func _clear_dim_overlays() -> void:
	"""Clear all dim overlay meshes"""
	for overlay in dim_overlay_meshes:
		if is_instance_valid(overlay):
			overlay.queue_free()
	dim_overlay_meshes.clear()
	dim_overlays_visible = false


func _process(delta: float) -> void:
	_update_tile_highlight()
	_process_ball_spin(delta)
	_update_ball_shadow()


func _input(event: InputEvent) -> void:
	# Handle animation skip/fast-forward
	if shot_manager and shot_manager.is_animating:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				# Single click during animation = fast forward
				if shot_manager.animation_speed < shot_manager.FAST_FORWARD_SPEED:
					shot_manager.fast_forward_animation()
				else:
					# Already fast-forwarding, skip to end
					shot_manager.skip_animation()
					_skip_current_animation()
				return
		elif event is InputEventKey:
			if event.pressed and event.keycode == KEY_SPACE:
				# Space bar = skip animation entirely
				shot_manager.skip_animation()
				_skip_current_animation()
				return
	
	# Only process mouse clicks if not handled by UI
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Don't process if mouse is over UI (let UI handle it)
			if _is_mouse_over_ui():
				return
			
			# Lock target to currently hovered cell
			_try_lock_target(hovered_cell)


func _is_mouse_over_ui() -> bool:
	"""Check if mouse is over any UI element"""
	# Get all Control nodes that might block input
	var viewport = get_viewport()
	if viewport == null:
		return false
	
	# Check if any GUI element has focus or mouse is over it
	var focused = viewport.gui_get_focus_owner()
	if focused != null:
		return true
	
	# Check hovered control
	var gui_path = viewport.gui_get_hovered_control()
	if gui_path != null:
		return true
	
	return false


func _try_lock_target(cell: Vector2i) -> void:
	"""Attempt to lock target to the specified cell"""
	if cell.x < 0 or cell.y < 0:
		return
	
	# Check if forward from ball
	if golf_ball:
		if not is_forward_from_ball(cell):
			return
	
	# Lock to this cell
	locked_cell = cell
	target_locked = true
	
	# Calculate locked target position
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	var x_pos = locked_cell.x * width * 1.5
	var z_pos = locked_cell.y * hex_height + (locked_cell.x % 2) * (hex_height / 2.0)
	var y_pos = get_elevation(locked_cell.x, locked_cell.y)
	locked_target_pos = Vector3(x_pos, y_pos, z_pos)
	
	# Position highlights on locked cell
	highlight_mesh.position = Vector3(x_pos, y_pos + 0.5, z_pos)
	highlight_mesh.rotation.y = PI / 6.0
	highlight_mesh.visible = true
	
	target_highlight_mesh.position = Vector3(x_pos, y_pos + 0.5, z_pos)
	target_highlight_mesh.rotation.y = PI / 6.0
	target_highlight_mesh.visible = true
	
	# Update AOE highlights around the locked cell
	_update_aoe_for_cell(locked_cell)
	
	# Update trajectory
	_update_trajectory(locked_target_pos)
	
	# Calculate shape-adjusted landing tile and update shot manager
	var adjusted_landing = get_shape_adjusted_landing(locked_cell)
	if shot_manager and shot_manager.is_shot_in_progress:
		shot_manager.set_aim_target(adjusted_landing)
	
	# Update UI
	if shot_ui and golf_ball:
		var terrain = get_cell(adjusted_landing.x, adjusted_landing.y)
		var ball_tile = world_to_grid(golf_ball.position)
		var distance = _calculate_distance_yards(ball_tile, adjusted_landing)
		shot_ui.update_target_info(terrain, distance)


func _update_aoe_for_cell(cell: Vector2i) -> void:
	"""Update AOE highlights around a cell"""
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	
	_hide_all_aoe_highlights()
	
	# Get AOE radius from shot context
	var aoe_radius = 1  # Default
	if shot_manager and shot_manager.current_context:
		aoe_radius = shot_manager.current_context.aoe_radius
	
	var aoe_offset = get_shape_aoe_offset()
	var aoe_center = Vector2i(cell.x + aoe_offset, cell.y)
	aoe_center.x = clampi(aoe_center.x, 0, grid_width - 1)
	
	# Show ring 1 AOE
	var neighbors = get_adjacent_cells(aoe_center.x, aoe_center.y)
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
	
	# Show ring 2 AOE only if radius >= 2
	if aoe_radius >= 2:
		var outer_cells = get_outer_ring_cells(aoe_center.x, aoe_center.y)
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


## Public function to set aim target from external sources (like HoleViewer)
func set_aim_cell(cell: Vector2i) -> bool:
	"""Set the aim target to a specific cell. Returns true if successful."""
	# Validate cell is in bounds
	if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
		return false
	
	# Check if target is forward from ball
	if golf_ball:
		if not is_forward_from_ball(cell):
			return false
	
	# Lock target to this cell
	locked_cell = cell
	target_locked = true
	
	# Calculate locked target position
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	var x_pos = locked_cell.x * width * 1.5
	var z_pos = locked_cell.y * hex_height + (locked_cell.x % 2) * (hex_height / 2.0)
	var y_pos = get_elevation(locked_cell.x, locked_cell.y)
	locked_target_pos = Vector3(x_pos, y_pos, z_pos)
	
	# Position highlight mesh on the locked cell
	highlight_mesh.position = Vector3(x_pos, y_pos + 0.5, z_pos)
	highlight_mesh.rotation.y = PI / 6.0
	highlight_mesh.visible = true
	
	# Show white target highlight on the locked cell (original aim point)
	target_highlight_mesh.position = Vector3(x_pos, y_pos + 0.5, z_pos)
	target_highlight_mesh.rotation.y = PI / 6.0
	target_highlight_mesh.visible = true
	
	# Update AOE highlights around the locked cell
	_update_aoe_for_cell(locked_cell)
	
	# Update trajectory
	_update_trajectory(locked_target_pos)
	
	# Calculate shape-adjusted landing tile
	var adjusted_landing = get_shape_adjusted_landing(locked_cell)
	
	# Update shot manager with the shape-adjusted landing tile
	if shot_manager and shot_manager.is_shot_in_progress:
		shot_manager.set_aim_target(adjusted_landing)
	
	# Update UI with target info (show adjusted landing info)
	if shot_ui and golf_ball:
		var terrain = get_cell(adjusted_landing.x, adjusted_landing.y)
		var ball_tile = world_to_grid(golf_ball.position)
		var distance = _calculate_distance_yards(ball_tile, adjusted_landing)
		shot_ui.update_target_info(terrain, distance)
	
	# Display debug info for the clicked tile
	_display_tile_debug_info(locked_cell)
	
	return true


## Set hovered cell for highlighting (from external sources like HoleViewer)
func set_hover_cell(cell: Vector2i) -> void:
	"""Set the currently hovered cell and update all highlighting"""
	# Validate cell bounds
	if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
		if not target_locked:
			hovered_cell = Vector2i(-1, -1)
			highlight_mesh.visible = false
			_hide_all_aoe_highlights()
			trajectory_mesh.visible = false
			trajectory_shadow_mesh.visible = false
			curved_trajectory_mesh.visible = false
		return
	
	var surface = get_cell(cell.x, cell.y)
	if surface == -1 or surface == SurfaceType.WATER:
		if not target_locked:
			hovered_cell = Vector2i(-1, -1)
			highlight_mesh.visible = false
			_hide_all_aoe_highlights()
		return
	
	# Always track hovered_cell for click detection
	hovered_cell = cell
	
	# If target is locked, don't update visuals - keep it on locked cell
	if target_locked:
		_update_trajectory(locked_target_pos)
		return
	
	# Check if cell is forward from ball
	var is_forward = is_forward_from_ball(cell)
	
	# Hide all previous AOE highlights before showing new ones
	_hide_all_aoe_highlights()
	
	# Don't show any highlight for tiles behind the ball
	if not is_forward:
		highlight_mesh.visible = false
		hovered_cell = Vector2i(-1, -1)
		return
	
	# Check if cell is in range
	var in_range = true
	if golf_ball:
		var ball_tile = world_to_grid(golf_ball.position)
		var tile_dist = get_tile_distance(ball_tile, cell)
		var max_dist = get_current_club_distance()
		in_range = tile_dist <= max_dist
	
	# Position highlight mesh at the cell
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	var x_pos = cell.x * width * 1.5
	var z_pos = cell.y * hex_height + (cell.x % 2) * (hex_height / 2.0)
	var y_pos = get_elevation(cell.x, cell.y) + 0.5
	
	highlight_mesh.position = Vector3(x_pos, y_pos, z_pos)
	highlight_mesh.rotation.y = PI / 6.0
	highlight_mesh.visible = true
	
	# Change highlight color based on range
	var mat = highlight_mesh.material_override as StandardMaterial3D
	if mat:
		if in_range:
			mat.albedo_color = Color(1.0, 0.85, 0.0, 0.6)  # Gold = in range
		else:
			mat.albedo_color = Color(1.0, 0.2, 0.2, 0.6)  # Red = out of range
	
	# Only show AOE and trajectory if in range
	if in_range:
		# Get AOE offset based on shot shape
		var aoe_offset = get_shape_aoe_offset()
		var aoe_center = Vector2i(cell.x + aoe_offset, cell.y)
		aoe_center.x = clampi(aoe_center.x, 0, grid_width - 1)
		
		# Get AOE radius from shot context (accuracy modifiers applied)
		var aoe_radius = 1  # Default
		if shot_manager and shot_manager.current_context:
			aoe_radius = shot_manager.current_context.aoe_radius
		
		# Show AOE rings based on calculated radius
		if aoe_radius >= 1:
			# Update adjacent highlights (ring 1)
			var neighbors = get_adjacent_cells(aoe_center.x, aoe_center.y)
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
		if aoe_radius >= 2:
			var outer_cells = get_outer_ring_cells(aoe_center.x, aoe_center.y)
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
		
		# Update trajectory arc
		if target_locked:
			_update_trajectory(locked_target_pos)
		else:
			var target_y = get_elevation(cell.x, cell.y)
			_update_trajectory(Vector3(x_pos, target_y, z_pos))
	else:
		# Out of range - hide trajectory unless locked
		if not target_locked:
			trajectory_mesh.visible = false
			trajectory_shadow_mesh.visible = false
			curved_trajectory_mesh.visible = false


## Set the external camera/viewport for mouse picking (called by HoleViewer)
func set_external_camera(cam: Camera3D, vp: SubViewport, viewer: Node = null) -> void:
	external_camera = cam
	external_viewport = vp
	if viewer:
		hole_viewer = viewer
		# Setup putting system with hole viewer
		if putting_system and putting_system.has_method("setup"):
			putting_system.setup(self, hole_viewer)
		# Tell hole_viewer about putting system
		if hole_viewer.has_method("set_putting_system"):
			hole_viewer.set_putting_system(putting_system)


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
	
	# Create lie system
	lie_system = LieSystem.new()
	lie_system.name = "LieSystem"
	add_child(lie_system)
	
	# Create wind system
	wind_system = WindSystem.new()
	wind_system.name = "WindSystem"
	add_child(wind_system)
	
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
	
	# Initialize card system
	_init_card_system()
	
	# Initialize putting system
	_init_putting_system()
	
	# Look for ShotUI in the scene tree
	_find_and_setup_ui()


func _init_card_system() -> void:
	"""Initialize the card/deck system"""
	# Create card library (holds all card definitions)
	card_library = CardLibrary.new()
	card_library.name = "CardLibrary"
	add_child(card_library)
	
	# Create deck manager
	deck_manager = DeckManager.new()
	deck_manager.name = "DeckManager"
	add_child(deck_manager)
	
	# Create card system manager (bridges cards with modifiers)
	card_system = CardSystemManager.new()
	card_system.name = "CardSystemManager"
	card_system.deck_manager = deck_manager
	card_system.modifier_manager = modifier_manager
	card_system.shot_manager = shot_manager
	card_system.card_library = card_library
	add_child(card_system)
	
	# Initialize starter deck
	card_system.starter_deck_definition = starter_deck
	card_system.club_deck_definition = club_deck
	card_system.initialize_starter_deck()

	
	# Register wind modifier (always active when wind is present)
	if modifier_manager and wind_system:
		var wind_modifier = WindModifier.new(wind_system)
		modifier_manager.add_modifier(wind_modifier)


func _init_putting_system() -> void:
	"""Initialize putting system for green play"""
	# Load and create putting system
	var PuttingSystemClass = load("res://scripts/putting_system.gd")
	if PuttingSystemClass:
		putting_system = PuttingSystemClass.new()
		putting_system.name = "PuttingSystem"
		add_child(putting_system)
		
		# Connect signals
		putting_system.putting_mode_entered.connect(_on_putting_mode_entered)
		putting_system.putting_mode_exited.connect(_on_putting_mode_exited)
		putting_system.putt_started.connect(_on_putt_started)
		putting_system.putt_completed.connect(_on_putt_completed)
	else:
		push_warning("Could not load putting_system.gd")


func _on_putting_mode_entered() -> void:
	"""Called when entering putting mode"""
	# Hide regular shot UI elements
	_hide_shot_visuals()


func _on_putting_mode_exited() -> void:
	"""Called when exiting putting mode"""
	# Show regular shot UI elements again
	_show_shot_visuals()


func _on_putt_started(target_tile: Vector2i, power: float) -> void:
	"""Called when a putt is executed"""
	pass


func _on_putt_completed(final_tile: Vector2i) -> void:
	"""Called when putt roll completes"""
	
	# Check if still on/near green - if so, stay in putting mode
	var surface = get_cell(final_tile.x, final_tile.y)
	var near_green = _is_near_green(final_tile, 2)
	if surface == SurfaceType.GREEN or surface == SurfaceType.FLAG or near_green:
		# Still on/near green, ready for next putt
		pass
	else:
		# Off the green area, exit putting mode
		if putting_system:
			putting_system.exit_putting_mode()


func _hide_shot_visuals() -> void:
	"""Hide trajectory arc, AOE highlights for putting mode"""
	if trajectory_mesh:
		trajectory_mesh.visible = false
	if trajectory_shadow_mesh:
		trajectory_shadow_mesh.visible = false
	if curved_trajectory_mesh:
		curved_trajectory_mesh.visible = false
	if target_highlight_mesh:
		target_highlight_mesh.visible = false
	_hide_all_aoe_highlights()
	_clear_dim_overlays()


func _show_shot_visuals() -> void:
	"""Restore shot visuals after putting mode"""
	# Visuals will be restored when next shot starts
	_update_dim_overlays()


func _is_near_green(tile: Vector2i, max_distance: int) -> bool:
	"""Check if a tile is within max_distance tiles of any green tile"""
	for col in range(grid_width):
		for row in range(grid_height):
			var surface = get_cell(col, row)
			if surface == SurfaceType.GREEN or surface == SurfaceType.FLAG:
				var dist = get_tile_distance(tile, Vector2i(col, row))
				if dist <= max_distance:
					return true
	return false


func _find_and_setup_ui() -> void:
	"""Find ShotUI nodes and connect them to systems"""
	# Try to find UI nodes in the Control node
	var control = get_tree().current_scene.get_node_or_null("Control")
	if control:
		shot_ui = control.get_node_or_null("ShotUI")
		
		# Find lie info panel
		lie_info_panel = control.get_node_or_null("LieInfoPanel")
		if lie_info_panel:
			lie_name_label = lie_info_panel.get_node_or_null("VBoxContainer/LieName")
			lie_description_label = lie_info_panel.get_node_or_null("VBoxContainer/LieDescription")
			lie_modifiers_label = lie_info_panel.get_node_or_null("VBoxContainer/LieModifiers")
			# Ensure BBCode is enabled for rich text
			if lie_description_label:
				lie_description_label.bbcode_enabled = true
			if lie_modifiers_label:
				lie_modifiers_label.bbcode_enabled = true
	
	# Also try as direct children of scene root
	if shot_ui == null:
		shot_ui = get_tree().current_scene.get_node_or_null("ShotUI")
	
	# Connect ShotUI
	if shot_ui:
		shot_ui.setup(shot_manager, self)


func _update_ui_hole_info() -> void:
	"""Update UI with current hole information"""
	if shot_ui:
		shot_ui.set_hole_info(1, current_par, current_yardage)


func _start_new_shot() -> void:
	"""Start a new shot from the ball's current position"""
	if golf_ball == null:
		push_warning("No golf ball to start shot from")
		return
	
	# Get ball's current tile
	var ball_tile = world_to_grid(golf_ball.position)
	var ball_surface = get_cell(ball_tile.x, ball_tile.y)
	
	# Check if ball is in the hole - don't start a new shot, trigger hole complete
	if ball_tile == flag_position:
		_trigger_hole_complete()
		return
	
	# Check if ball is ON the green - ONLY green tiles trigger putting mode
	var should_putt = ball_surface == SurfaceType.GREEN
	
	if should_putt:
		if putting_system:
			# Hide ALL shot mode visuals before entering putting mode
			if target_highlight_mesh:
				target_highlight_mesh.visible = false
			if highlight_mesh:
				highlight_mesh.visible = false
			_hide_range_preview()
			_hide_all_aoe_highlights()
			
			putting_system.golf_ball = golf_ball
			putting_system.setup(self, hole_viewer)
			putting_system.enter_putting_mode()
			return
	
	# Normal shot mode
	if putting_system and putting_system.is_putting_mode:
		putting_system.exit_putting_mode()
	
	shot_manager.start_shot(golf_ball, ball_tile)
	
	# Update dim overlays for new ball position
	_update_dim_overlays()
	
	# Update UI with distance to flag
	if shot_ui and flag_position.x >= 0:
		var dist_to_flag = _calculate_distance_yards(ball_tile, flag_position)
		shot_ui.update_shot_info(shot_manager.current_context.shot_index, dist_to_flag)


func _calculate_distance_yards(from: Vector2i, to: Vector2i) -> int:
	"""Calculate distance between two cells in yards"""
	var dx = to.x - from.x
	var dy = to.y - from.y
	return int(sqrt(dx * dx + dy * dy) * YARDS_PER_CELL)


func _on_shot_started(context: ShotContext) -> void:
	"""Called when shot begins - calculate lie and update UI"""
	
	# Calculate lie effects for starting position
	if lie_system and context.start_tile.x >= 0:
		var lie_info = lie_system.calculate_lie(self, context.start_tile)
		lie_system.apply_lie_to_shot(context, lie_info)
		
		# Update lie info panel in Control overlay
		_update_lie_info_panel(lie_info)
		
		# Also update shot_ui if it has the method
		if shot_ui and shot_ui.has_method("update_lie_info"):
			shot_ui.update_lie_info(lie_info)
	
	# Update UI with current terrain
	if shot_ui and context.start_tile.x >= 0:
		var terrain = get_cell(context.start_tile.x, context.start_tile.y)
		shot_ui.update_current_terrain(terrain)


func _update_lie_info_panel(lie_info: Dictionary) -> void:
	"""Update the lie info panel in the Control overlay with stats table"""
	if lie_info_panel == null:
		return
	
	# Update lie name with color
	if lie_name_label:
		var lie_color = lie_info.get("color", Color.WHITE)
		lie_name_label.text = lie_info.get("display_name", "Unknown")
		lie_name_label.add_theme_color_override("font_color", lie_color)
	
	# Update description
	if lie_description_label:
		lie_description_label.text = "[i]%s[/i]" % lie_info.get("description", "")
	
	# Build stats table showing Base | Mod | Final
	if lie_modifiers_label:
		var stats = get_current_shot_stats()
		var base = stats.base
		var mods = stats.mods
		var final = stats.final
		
		var lines = []
		lines.append("[b]%s[/b]" % stats.club_name)
		lines.append("")
		lines.append("[code]Stat     Base  Mod  Final[/code]")
		lines.append("[code]─────────────────────────[/code]")
		
		# Distance row
		lines.append(_format_stat_row("Distance", base.distance, mods.distance_mod, final.distance, true))
		
		# Accuracy row (lower is better, so positive mod is bad)
		lines.append(_format_stat_row("Accuracy", base.accuracy, mods.accuracy_mod, final.accuracy, false))
		
		# Roll row
		lines.append(_format_stat_row("Roll", base.roll, mods.roll_mod, final.roll, true))
		
		# Curve row
		lines.append(_format_stat_row("Curve", base.curve, mods.curve_mod, final.curve, true))
		
		# Add scoring bonuses if present
		var chip_bonus = lie_info.get("chip_bonus", 0)
		var mult_bonus = lie_info.get("mult_bonus", 0.0)
		if chip_bonus != 0 or mult_bonus != 0.0:
			lines.append("")
			lines.append("[u]Scoring:[/u]")
			if chip_bonus != 0:
				var color = "lime" if chip_bonus > 0 else "red"
				lines.append("[color=%s]Chips: %s%d[/color]" % [color, "+" if chip_bonus > 0 else "", chip_bonus])
			if mult_bonus != 0.0:
				var color = "lime" if mult_bonus > 0 else "red"
				lines.append("[color=%s]Mult: %s%.1f[/color]" % [color, "+" if mult_bonus > 0 else "", mult_bonus])
		
		lie_modifiers_label.text = "\n".join(lines)


func _format_stat_row(stat_name: String, base_val: float, mod_val: float, final_val: float, positive_is_good: bool) -> String:
	"""Format a row in the stats table with color coding"""
	# Pad stat name to 8 chars
	var name_padded = stat_name.substr(0, 8).rpad(8)
	
	# Format base value
	var base_str = str(int(base_val)).rpad(4)
	
	# Format mod with color
	var mod_str = ""
	var mod_color = "gray"
	if mod_val != 0:
		var is_good = (mod_val > 0) == positive_is_good
		mod_color = "lime" if is_good else "red"
		var sign = "+" if mod_val > 0 else ""
		mod_str = "%s%d" % [sign, int(mod_val)]
	else:
		mod_str = "0"
	mod_str = mod_str.rpad(4)
	
	# Format final with color based on comparison to base
	var final_str = str(int(final_val))
	var final_color = "white"
	if final_val > base_val:
		final_color = "lime" if positive_is_good else "red"
	elif final_val < base_val:
		final_color = "red" if positive_is_good else "lime"
	
	return "[code]%s %s[color=%s]%s[/color] [color=%s]%s[/color][/code]" % [
		name_padded, base_str, mod_color, mod_str, final_color, final_str
	]


func _format_lie_modifier_additive(stat_name: String, value: float, positive_is_good: bool) -> String:
	"""Format an additive modifier with color coding"""
	if value == 0:
		return "[color=white]%s: 0[/color]" % stat_name
	
	var is_good = (value > 0) == positive_is_good
	var color = "lime" if is_good else ("orange" if abs(value) <= 2 else "red")
	var sign = "+" if value > 0 else ""
	
	if abs(value) == int(abs(value)):
		return "[color=%s]%s: %s%d[/color]" % [color, stat_name, sign, int(value)]
	else:
		return "[color=%s]%s: %s%.1f[/color]" % [color, stat_name, sign, value]


func _format_lie_modifier(stat_name: String, value: int) -> String:
	"""Format a modifier with color coding"""
	var color = "white"
	if value > 100:
		color = "lime"
	elif value < 100:
		color = "orange" if value >= 70 else "red"
	return "[color=%s]%s: %d%%[/color]" % [color, stat_name, value]


func _on_aoe_computed(context: ShotContext) -> void:
	"""Called when AOE is calculated - update visuals"""
	# The existing highlight system handles this via _update_tile_highlight
	pass


func _on_landing_resolved(context: ShotContext) -> void:
	"""Called when landing tile is determined"""
	pass


func _on_shot_completed(context: ShotContext) -> void:
	"""Called when shot is finished - animate ball flight, then update state"""
	
	# Reset target lock state
	target_locked = false
	target_highlight_mesh.visible = false
	
	# Store previous valid tile before shot (for water penalty)
	previous_valid_tile = context.start_tile
	
	# Mark animation as started
	if shot_manager:
		shot_manager.start_animation()
	
	# Track if ball hit water
	var hit_water = false
	
	# Animate ball flight to landing position, then bounces
	if golf_ball and context.landing_tile.x >= 0:
		var ball_tile = world_to_grid(golf_ball.position)
		
		# Check if landing tile is water
		var landing_surface = get_cell(context.landing_tile.x, context.landing_tile.y)
		if landing_surface == SurfaceType.WATER:
			hit_water = true
		
		# Get base bounce count from club (drivers bounce more, wedges less)
		var num_bounces = CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).roll
		
		# Calculate carry position (num_bounces tiles before target)
		var carry_tile = _get_carry_position(ball_tile, context.landing_tile, num_bounces)
		var carry_pos = get_tile_surface_position(carry_tile)
		
		# Animate ball flight to carry position
		await _animate_ball_flight_with_bounce(golf_ball.position, carry_pos)
		
		# Check if carry tile is water
		var carry_surface = get_cell(carry_tile.x, carry_tile.y)
		if carry_surface == SurfaceType.WATER:
			hit_water = true
			# Ball splashes in water at carry position
			await _handle_water_hazard()
		else:
			# Calculate roll direction from ball's starting position through carry position
			# This maintains the shot's forward direction, not toward the pin
			var roll_direction = _get_roll_direction(ball_tile, carry_tile)
			
			# Now apply bounces from carry position in the shot's direction
			var final_tile = await _apply_bounce_rollout(carry_tile, roll_direction, num_bounces)
			
			# Check if final tile is water
			var final_surface = get_cell(final_tile.x, final_tile.y)
			if final_surface == SurfaceType.WATER:
				hit_water = true
				await _handle_water_hazard()
		
		# Stop ball spin after all bouncing is complete
		if golf_ball:
			golf_ball.set_meta("is_spinning", false)
	
	# Mark animation as ended
	if shot_manager:
		shot_manager.end_animation()
	
	# Show score popup now that ball has landed
	if shot_ui:
		var is_water_hit = context.has_metadata("hit_water")
		var is_sand_hit = context.has_metadata("hit_sand")
		shot_ui.show_score_popup(context.chips, context.mult, context.final_score, is_water_hit, is_sand_hit)
		
		# Wait for popup to be visible for a bit (allow animation to play)
		await get_tree().create_timer(2.0).timeout
	
	# Hide trajectory after landing
	trajectory_mesh.visible = false
	trajectory_shadow_mesh.visible = false
	curved_trajectory_mesh.visible = false
	
	# Update dim overlays now that ball has moved
	_update_dim_overlays()
	
	# Check if reached flag (note: rollout may have already triggered hole complete)
	if context.has_metadata("reached_flag"):
		# Show hole complete popup
		if shot_ui:
			# Pass 0 for total_points as ShotUI tracks it internally
			shot_ui.show_hole_complete(context.shot_index, current_par, 0)
	else:
		# Start next shot
		_start_new_shot()


func _skip_current_animation() -> void:
	"""Skip the current ball animation by killing the tween"""
	if current_ball_tween and current_ball_tween.is_valid():
		# Get the final position from the tween if possible
		current_ball_tween.custom_step(100.0)  # Fast forward to end
		current_ball_tween.kill()
		current_ball_tween = null


func _handle_water_hazard() -> void:
	"""Handle ball landing in water - show effect, return ball to previous tile, add penalty"""
	
	# Show and fade in water effect overlay
	if water_effect:
		water_effect.color = Color(1, 1, 1, 0)  # Start transparent
		water_effect.visible = true
		var tween = create_tween()
		tween.tween_property(water_effect, "color:a", 1.0, 0.3)
		await tween.finished
	
	# Wait a moment for dramatic effect
	await get_tree().create_timer(0.5).timeout
	
	# Move ball back to previous valid tile
	if golf_ball and previous_valid_tile.x >= 0:
		var return_pos = get_tile_surface_position(previous_valid_tile)
		golf_ball.position = return_pos
	
	# Add penalty stroke
	if shot_manager and shot_manager.current_context:
		shot_manager.current_context.shot_index += 1
	
	# Wait a moment before fading out
	await get_tree().create_timer(0.3).timeout
	
	# Fade out water effect overlay
	if water_effect:
		var tween = create_tween()
		tween.tween_property(water_effect, "color:a", 0.0, 0.7)
		await tween.finished
		water_effect.visible = false  # Hide when done


var hole_complete_triggered: bool = false  # Prevent multiple triggers

func _trigger_hole_complete() -> void:
	"""Called when ball reaches the hole/flag during any phase (carry, roll, spin)"""
	if hole_complete_triggered:
		return  # Already triggered
	
	hole_complete_triggered = true
	
	# End animation state
	if shot_manager:
		shot_manager.end_animation()
	
	# Stop ball spin
	if golf_ball:
		golf_ball.set_meta("is_spinning", false)
	
	# Hide trajectory
	trajectory_mesh.visible = false
	trajectory_shadow_mesh.visible = false
	curved_trajectory_mesh.visible = false
	
	# Trigger confetti on the flag
	_play_hole_confetti()
	
	# Wait 0.5 seconds for confetti celebration
	await get_tree().create_timer(0.5).timeout
	
	# Play transition while generating new hole
	_play_transition_loading(func():
		# Reset for next hole
		hole_complete_triggered = false
		
		# Reset shot counter and club selection
		if shot_manager and shot_manager.current_context:
			shot_manager.current_context.shot_index = 0
		current_club = ClubType.DRIVER
		_update_club_button_visuals()
		
		# Reset target lock
		target_locked = false
		locked_cell = Vector2i(-1, -1)
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false
		curved_trajectory_mesh.visible = false
		target_highlight_mesh.visible = false
		_hide_all_aoe_highlights()
		
		# Cancel any in-progress shot
		if shot_manager:
			shot_manager.cancel_shot()
		
		_clear_course_nodes()
		_generate_course()
		_generate_grid()
		_log_hole_info()
		
		# Start a fresh shot
		_start_new_shot()
	)


func _play_hole_confetti() -> void:
	"""Show confetti particle effect on the flag"""
	# Find the flag node (it's in the "flag" group)
	var flags = get_tree().get_nodes_in_group("flag")
	if flags.size() > 0:
		var flag_node = flags[0]
		var confetti = flag_node.get_node_or_null("%confetti")
		if confetti:
			confetti.visible = true
			# If it's a particle emitter, restart it
			if confetti.has_method("restart"):
				confetti.restart()
			elif confetti is GPUParticles3D or confetti is CPUParticles3D:
				confetti.emitting = true
			
			# Hide after 2 seconds (check if still valid - may be freed on regenerate)
			await get_tree().create_timer(2.0).timeout
			if is_instance_valid(confetti):
				confetti.visible = false


func _get_carry_position(from_tile: Vector2i, target_tile: Vector2i, bounce_count: int) -> Vector2i:
	"""Calculate the carry/landing position based on bounce count.
	   Ball lands bounce_count tiles before target, then bounces forward."""
	# Direction from ball to target
	var dx = target_tile.x - from_tile.x
	var dy = target_tile.y - from_tile.y
	
	# If target is same tile or no bounces needed, land on target
	var distance = get_tile_distance(from_tile, target_tile)
	if distance <= bounce_count or bounce_count <= 0:
		return target_tile
	
	# Normalize direction and step back bounce_count tiles from target
	var dir_x = 0
	var dir_y = 0
	if abs(dx) > abs(dy):
		dir_x = 1 if dx > 0 else -1
	else:
		dir_y = 1 if dy > 0 else -1
	
	# If diagonal-ish, favor Y direction (toward/away from flag)
	if abs(dx) > 0 and abs(dy) > 0:
		dir_y = 1 if dy > 0 else -1
		dir_x = 0
	
	# Step back bounce_count tiles
	var carry_tile = Vector2i(target_tile.x - dir_x * bounce_count, target_tile.y - dir_y * bounce_count)
	
	# Validate carry tile is valid
	if carry_tile.x < 0 or carry_tile.x >= grid_width or carry_tile.y < 0 or carry_tile.y >= grid_height:
		# Try stepping back fewer tiles
		for i in range(bounce_count - 1, 0, -1):
			carry_tile = Vector2i(target_tile.x - dir_x * i, target_tile.y - dir_y * i)
			if carry_tile.x >= 0 and carry_tile.x < grid_width and carry_tile.y >= 0 and carry_tile.y < grid_height:
				break
			else:
				return target_tile
	
	var surface = get_cell(carry_tile.x, carry_tile.y)
	if surface == -1 or surface == SurfaceType.WATER:
		return target_tile
	
	return carry_tile


func _apply_bounce_rollout(carry_tile: Vector2i, roll_direction: Vector2i, num_bounces: int) -> Vector2i:
	"""Apply bounce-based rollout after ball lands. Ball bounces forward based on:
	   - Club base rollout determines number of bounces
	   - Each bounce gets progressively smaller
	   - Ball follows negative elevation (rolls downhill) while moving forward
	   Spin (topspin/backspin) is applied AFTER bouncing finishes.
	   Ball stops at water/sand hazards."""
	
	# Use the provided roll direction (based on shot trajectory)
	var base_direction = roll_direction
	
	var current_tile = carry_tile
	var bounces_done = 0
	var reached_hole = false
	var current_direction = base_direction
	
	# Check if carry position is already on the hole
	if current_tile == flag_position:
		_trigger_hole_complete()
		return current_tile
	
	# Do bounces one at a time
	while bounces_done < num_bounces:
		# Get elevation-influenced direction (follows downhill while moving forward)
		current_direction = _get_elevation_influenced_direction(current_tile, base_direction)
		var next_tile = current_tile + current_direction
		
		# Check bounds
		if next_tile.x < 0 or next_tile.x >= grid_width or next_tile.y < 0 or next_tile.y >= grid_height:
			break
		
		# Check for hazards that stop the ball
		var next_surface = get_cell(next_tile.x, next_tile.y)
		if next_surface == -1:
			break
		if next_surface == SurfaceType.WATER:
			break
		if next_surface == SurfaceType.SAND:
			break
		if next_surface == SurfaceType.TREE:
			break
		
		# Check elevation change for bounce adjustments
		var current_elev = get_elevation(current_tile.x, current_tile.y)
		var next_elev = get_elevation(next_tile.x, next_tile.y)
		var elev_diff = next_elev - current_elev
		
		# Adjust bounces based on elevation
		if elev_diff < -0.3:
			num_bounces += 1  # Downhill = extra bounce
		elif elev_diff > 0.3:
			# Uphill kills the bounce early
			break
		
		# Animate bounce to next tile (height decreases with each bounce)
		var bounce_number = bounces_done + 1
		var next_pos = get_tile_surface_position(next_tile)
		await _animate_ball_bounce_to_tile(golf_ball.position, next_pos, bounce_number, num_bounces)
		
		current_tile = next_tile
		bounces_done += 1
		
		# Check if ball bounced into the hole
		if current_tile == flag_position:
			reached_hole = true
			break
	
	# If ball reached hole, trigger completion and skip spin
	if reached_hole:
		_trigger_hole_complete()
		return current_tile
	
	# Now apply spin effect AFTER bouncing (use current direction for spin)
	if current_spin != SpinType.NONE:
		current_tile = await _apply_spin_effect(current_tile, current_direction)
	
	return current_tile


func _animate_ball_bounce_to_tile(start_pos: Vector3, end_pos: Vector3, bounce_num: int, total_bounces: int) -> void:
	"""Animate ball bouncing from one tile to the next.
	   bounce_num: which bounce this is (1, 2, 3...)
	   total_bounces: total expected bounces (used to scale height)"""
	if golf_ball == null:
		return
	
	# Get animation speed multiplier
	var speed_mult = shot_manager.get_animation_speed() if shot_manager else 1.0
	
	var distance = start_pos.distance_to(end_pos)
	
	# Bounce height decreases with each bounce (first bounce highest)
	# First bounce: ~0.8 units, subsequent bounces get smaller
	var height_factor = 1.0 / float(bounce_num)
	var bounce_height = clamp(0.8 * height_factor, 0.15, 0.8)
	
	# Duration also decreases slightly with each bounce
	var base_duration = clamp(distance * 0.15, 0.2, 0.5) / speed_mult
	var duration = base_duration * (0.7 + 0.3 * height_factor)
	
	# Keep ball spinning during bounces
	var travel_dir = (end_pos - start_pos).normalized()
	var spin_axis = travel_dir.cross(Vector3.UP).normalized()
	if spin_axis.length() < 0.1:
		spin_axis = Vector3.RIGHT
	
	var spin_speed = 8.0 * height_factor * speed_mult  # Spin slows down with bounces
	golf_ball.set_meta("spin_axis", spin_axis)
	golf_ball.set_meta("spin_speed", spin_speed)
	golf_ball.set_meta("is_spinning", true)
	
	# Animate the bounce arc
	current_ball_tween = create_tween()
	var steps = 15
	var step_duration = duration / steps
	
	for i in range(1, steps + 1):
		var t = float(i) / float(steps)
		
		# Horizontal position (linear)
		var pos = start_pos.lerp(end_pos, t)
		
		# Vertical position (parabolic arc)
		var arc_height = 4.0 * bounce_height * t * (1.0 - t)
		var base_y = lerp(start_pos.y, end_pos.y, t)
		pos.y = base_y + arc_height
		
		# Easing: fast up, slow at peak, fast down
		if t < 0.3:
			current_ball_tween.set_ease(Tween.EASE_OUT)
			current_ball_tween.set_trans(Tween.TRANS_QUAD)
		elif t > 0.7:
			current_ball_tween.set_ease(Tween.EASE_IN)
			current_ball_tween.set_trans(Tween.TRANS_QUAD)
		else:
			current_ball_tween.set_ease(Tween.EASE_IN_OUT)
			current_ball_tween.set_trans(Tween.TRANS_SINE)
		
		current_ball_tween.tween_property(golf_ball, "position", pos, step_duration)
	
	await current_ball_tween.finished
	golf_ball.position = end_pos
	current_ball_tween = null


func _apply_spin_effect(from_tile: Vector2i, roll_dir: Vector2i) -> Vector2i:
	"""Apply topspin/backspin effect after natural rollout finishes.
	   Topspin: +1 tile forward, Backspin: -1 tile backward"""
	
	var spin_direction = roll_dir
	if current_spin == SpinType.BACKSPIN:
		spin_direction = Vector2i(-roll_dir.x, -roll_dir.y)  # Reverse direction
	
	var spin_tiles = 1  # Spin adds 1 tile of roll
	var current_tile = from_tile
	
	for i in range(spin_tiles):
		var next_tile = Vector2i(current_tile.x + spin_direction.x, current_tile.y + spin_direction.y)
		
		# Check bounds
		if next_tile.x < 0 or next_tile.x >= grid_width or next_tile.y < 0 or next_tile.y >= grid_height:
			break
		
		# Check for hazards
		var next_surface = get_cell(next_tile.x, next_tile.y)
		if next_surface == -1 or next_surface == SurfaceType.WATER or next_surface == SurfaceType.SAND or next_surface == SurfaceType.TREE:
			break
		
		# Animate the spin roll (slightly slower than natural roll)
		var next_pos = get_tile_surface_position(next_tile)
		await _animate_ball_roll(golf_ball.position, next_pos, true)  # true = spin roll (slower)
		
		current_tile = next_tile
		
		# Check if ball spun into the hole
		if current_tile == flag_position:
			_trigger_hole_complete()
			break
	
	return current_tile


func _get_roll_direction(from_tile: Vector2i, to_tile: Vector2i) -> Vector2i:
	"""Get the primary roll direction (unit vector) from one tile toward another.
	   Returns a normalized direction that can be diagonal (e.g., (1,1) for northeast)."""
	var dx = to_tile.x - from_tile.x
	var dy = to_tile.y - from_tile.y
	
	# Normalize to unit direction, preserving diagonals
	var dir = Vector2i(0, 0)
	
	if dx != 0:
		dir.x = 1 if dx > 0 else -1
	if dy != 0:
		dir.y = 1 if dy > 0 else -1
	
	# Default to forward if no direction
	if dir == Vector2i(0, 0):
		dir.y = 1
	
	return dir


func _get_elevation_influenced_direction(current_tile: Vector2i, base_direction: Vector2i) -> Vector2i:
	"""Get the next roll direction influenced by elevation.
	   Ball always moves forward but can curve left/right following lower ground.
	   base_direction: the general forward direction of travel."""
	
	var current_elev = get_elevation(current_tile.x, current_tile.y)
	
	# Get the three forward-ish tiles (forward, forward-left, forward-right)
	var candidates: Array[Dictionary] = []
	
	# Always consider the base forward direction
	var forward = current_tile + base_direction
	if _is_valid_roll_tile(forward):
		var elev = get_elevation(forward.x, forward.y)
		candidates.append({"tile": forward, "elev": elev, "priority": 0})
	
	# Determine left and right based on base direction
	var left_offset: Vector2i
	var right_offset: Vector2i
	
	if base_direction.y != 0:
		# Moving forward/backward - left/right are on X axis
		left_offset = Vector2i(base_direction.y, base_direction.y)  # Diagonal forward-left
		right_offset = Vector2i(-base_direction.y, base_direction.y)  # Diagonal forward-right
	else:
		# Moving sideways - left/right are on Y axis
		left_offset = Vector2i(base_direction.x, base_direction.x)  # Diagonal
		right_offset = Vector2i(base_direction.x, -base_direction.x)  # Diagonal
	
	var forward_left = current_tile + left_offset
	if _is_valid_roll_tile(forward_left):
		var elev = get_elevation(forward_left.x, forward_left.y)
		candidates.append({"tile": forward_left, "elev": elev, "priority": 1})
	
	var forward_right = current_tile + right_offset
	if _is_valid_roll_tile(forward_right):
		var elev = get_elevation(forward_right.x, forward_right.y)
		candidates.append({"tile": forward_right, "elev": elev, "priority": 1})
	
	if candidates.is_empty():
		return base_direction  # No valid options, keep going straight
	
	# Sort by elevation (lowest first), then by priority (straight preferred)
	candidates.sort_custom(func(a, b):
		# Prefer significantly lower elevation
		var elev_diff = a.elev - b.elev
		if abs(elev_diff) > 0.15:  # Significant elevation difference
			return elev_diff < 0
		# If similar elevation, prefer straight ahead
		return a.priority < b.priority
	)
	
	# Return direction to the best tile
	var best_tile = candidates[0].tile
	return Vector2i(sign(best_tile.x - current_tile.x), sign(best_tile.y - current_tile.y))


func _is_valid_roll_tile(tile: Vector2i) -> bool:
	"""Check if a tile is valid for rolling onto."""
	if tile.x < 0 or tile.x >= grid_width or tile.y < 0 or tile.y >= grid_height:
		return false
	var surface = get_cell(tile.x, tile.y)
	if surface == -1 or surface == SurfaceType.WATER or surface == SurfaceType.TREE:
		return false
	return true


func _animate_ball_roll(start_pos: Vector3, end_pos: Vector3, is_spin_roll: bool = false) -> void:
	"""Animate ball rolling along the ground from start to end.
	   is_spin_roll: if true, uses slower animation for spin effect"""
	if golf_ball == null:
		return
	
	# Get animation speed multiplier
	var speed_mult = shot_manager.get_animation_speed() if shot_manager else 1.0
	
	var distance = start_pos.distance_to(end_pos)
	
	# Spin rolls are slower and more deliberate
	var roll_duration: float
	if is_spin_roll:
		roll_duration = clamp(distance * 0.25, 0.4, 0.8) / speed_mult  # Slower for spin
	else:
		roll_duration = clamp(distance * 0.12, 0.15, 0.4) / speed_mult  # Quick natural roll
	
	# Calculate roll spin (ball rotates forward along ground) - MUCH slower
	var travel_dir = (end_pos - start_pos).normalized()
	var spin_axis = travel_dir.cross(Vector3.UP).normalized()
	if spin_axis.length() < 0.1:
		spin_axis = Vector3.RIGHT
	
	# Slower, more realistic spin - about 1 rotation per tile
	var total_rotations = distance * 0.3  # Much slower spin
	var spin_speed = (total_rotations * TAU) / roll_duration
	golf_ball.set_meta("spin_axis", spin_axis)
	golf_ball.set_meta("spin_speed", spin_speed * speed_mult)
	golf_ball.set_meta("is_spinning", true)
	
	# Tween position along ground with smooth deceleration
	current_ball_tween = create_tween()
	current_ball_tween.set_ease(Tween.EASE_OUT)
	current_ball_tween.set_trans(Tween.TRANS_QUAD)
	current_ball_tween.tween_property(golf_ball, "position", end_pos, roll_duration)
	
	await current_ball_tween.finished
	current_ball_tween = null
	
	# Don't stop spin here - let it continue into next roll segment for smoothness
	# Spin will be stopped after all rolling is complete


# --- Ball Flight Animation ---

# Ball spin tracking
var ball_spin_tween: Tween = null

func _animate_ball_flight(start_pos: Vector3, end_pos: Vector3) -> void:
	"""Animate the golf ball along an arc from start to end position with spin"""
	if golf_ball == null:
		return
	
	# Calculate flight parameters based on distance
	var distance = start_pos.distance_to(end_pos)
	var flight_duration = clamp(distance * 0.08, 0.5, 2.5)  # 0.5 to 2.5 seconds based on distance
	
	# Peak height based on distance (longer shots go higher)
	var peak_height = clamp(distance * 0.3, 2.0, 12.0)
	
	# Add extra height if going uphill
	var height_diff = end_pos.y - start_pos.y
	if height_diff > 0:
		peak_height += height_diff * 0.5
	
	# Calculate spin direction (ball spins in direction of travel)
	var travel_dir = (end_pos - start_pos).normalized()
	# Spin axis is perpendicular to travel direction (cross with up vector)
	var spin_axis = travel_dir.cross(Vector3.UP).normalized()
	if spin_axis.length() < 0.1:
		spin_axis = Vector3.RIGHT  # Fallback if traveling straight up/down
	
	# Start ball spin animation
	_start_ball_spin(spin_axis, flight_duration, distance)
	
	# Create tween for position animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	
	# Number of steps for arc calculation
	var steps = 30
	var step_duration = flight_duration / steps
	
	# Animate through arc points
	for i in range(1, steps + 1):
		var t = float(i) / float(steps)
		var arc_pos = _calculate_arc_position(start_pos, end_pos, t, peak_height)
		
		# Use different easing for up vs down portion
		if t < 0.5:
			tween.set_trans(Tween.TRANS_SINE)
			tween.set_ease(Tween.EASE_OUT)
		else:
			tween.set_trans(Tween.TRANS_QUAD)
			tween.set_ease(Tween.EASE_IN)
		
		tween.tween_property(golf_ball, "position", arc_pos, step_duration)
	
	# Wait for animation to complete
	await tween.finished
	
	# Stop spin
	_stop_ball_spin()
	
	# Ensure ball is at exact landing position
	golf_ball.position = end_pos
	
	# Add a small bounce effect on landing
	await _animate_ball_bounce(end_pos)


func _animate_ball_flight_with_bounce(start_pos: Vector3, end_pos: Vector3) -> void:
	"""Animate ball flight with a smooth bounce-and-roll transition at landing.
	   The ball lands, does a small bounce, and is ready to roll.
	   Uses curved flight path when swing_curve is non-zero."""
	if golf_ball == null:
		return
	
	# Get animation speed multiplier
	var speed_mult = shot_manager.get_animation_speed() if shot_manager else 1.0
	
	# Get curve amount from shot context (if available)
	var curve_amount: float = 0.0
	var curve_type: String = "draw"
	if shot_manager and shot_manager.current_context:
		curve_amount = shot_manager.current_context.swing_curve
		# Also add any card-based curve effects
		curve_amount += shot_manager.current_context.curve_strength
		curve_amount += shot_manager.current_context.curve_mod
		
		# Determine curve type based on direction
		if curve_amount < 0:
			curve_type = "draw"  # Hook/Draw curves left
		else:
			curve_type = "fade"  # Slice/Fade curves right
	
	# Calculate flight parameters based on distance
	var distance = start_pos.distance_to(end_pos)
	var flight_duration = clamp(distance * 0.08, 0.5, 2.5) / speed_mult
	
	# Peak height based on distance and club arc height
	var peak_height = clamp(trajectory_height * 1.5, 2.0, 15.0)
	
	# Add extra height if going uphill
	var height_diff = end_pos.y - start_pos.y
	if height_diff > 0:
		peak_height += height_diff * 0.5
	
	# Scale curve by distance - longer shots curve more visibly
	# Each unit of curve = roughly 0.5 world units of lateral movement at peak
	var scaled_curve = curve_amount * distance * 0.15
	
	# Calculate spin direction (ball spins in direction of travel, with tilt for curve)
	var travel_dir = (end_pos - start_pos).normalized()
	var spin_axis = travel_dir.cross(Vector3.UP).normalized()
	if spin_axis.length() < 0.1:
		spin_axis = Vector3.RIGHT
	
	# Tilt spin axis based on curve (adds sidespin appearance)
	if abs(curve_amount) > 0.1:
		var tilt_amount = curve_amount * 0.3  # Subtle tilt
		spin_axis = spin_axis.rotated(travel_dir, tilt_amount)
	
	# Start ball spin animation (slower, more realistic)
	var total_rotations = clamp(distance * 0.2, 1.0, 8.0)  # Fewer rotations
	var spin_speed = (total_rotations * TAU) / flight_duration
	golf_ball.set_meta("spin_axis", spin_axis)
	golf_ball.set_meta("spin_speed", spin_speed * speed_mult)  # Speed up spin too
	golf_ball.set_meta("is_spinning", true)
	
	# Create tween for flight arc
	current_ball_tween = create_tween()
	var steps = 30  # More steps for smoother curves
	var step_duration = flight_duration / steps
	
	for i in range(1, steps + 1):
		var t = float(i) / float(steps)
		
		# Use curved arc if there's significant curve, otherwise straight
		var arc_pos: Vector3
		if abs(scaled_curve) > 0.3:
			arc_pos = _calculate_curved_arc_position(start_pos, end_pos, t, peak_height, scaled_curve, curve_type)
		else:
			arc_pos = _calculate_arc_position(start_pos, end_pos, t, peak_height)
		
		if t < 0.5:
			current_ball_tween.set_trans(Tween.TRANS_SINE)
			current_ball_tween.set_ease(Tween.EASE_OUT)
		else:
			current_ball_tween.set_trans(Tween.TRANS_QUAD)
			current_ball_tween.set_ease(Tween.EASE_IN)
		
		current_ball_tween.tween_property(golf_ball, "position", arc_pos, step_duration)
	
	await current_ball_tween.finished
	golf_ball.position = end_pos
	current_ball_tween = null
	
	# Skip the landing bounce - go straight into the bounce rollout
	# The first bounce in _apply_bounce_rollout will handle the transition
	
	# Don't stop spin - let it continue into the roll for smooth transition


func _start_ball_spin(spin_axis: Vector3, duration: float, distance: float) -> void:
	"""Start the ball spinning during flight"""
	if golf_ball == null:
		return
	
	# Calculate spin speed based on distance (faster spin for longer shots)
	# More rotations for longer distance
	var total_rotations = clamp(distance * 0.5, 2.0, 15.0)  # 2 to 15 full rotations
	var spin_speed = (total_rotations * TAU) / duration  # radians per second
	
	# Reset ball rotation
	golf_ball.rotation = Vector3.ZERO
	
	# Kill any existing spin tween
	if ball_spin_tween and ball_spin_tween.is_valid():
		ball_spin_tween.kill()
	
	# Create continuous spin using process
	ball_spin_tween = create_tween()
	ball_spin_tween.set_loops()  # Infinite loops
	
	# Rotate around the spin axis
	# We'll use a short interval and rotate incrementally
	var spin_interval = 0.016  # ~60fps
	var rotation_per_interval = spin_speed * spin_interval
	
	# Store spin data for _process to use
	golf_ball.set_meta("spin_axis", spin_axis)
	golf_ball.set_meta("spin_speed", spin_speed)
	golf_ball.set_meta("is_spinning", true)


func _stop_ball_spin() -> void:
	"""Stop the ball spinning"""
	if golf_ball == null:
		return
	
	golf_ball.set_meta("is_spinning", false)
	
	if ball_spin_tween and ball_spin_tween.is_valid():
		ball_spin_tween.kill()
		ball_spin_tween = null


func _process_ball_spin(delta: float) -> void:
	"""Update ball spin rotation each frame"""
	if golf_ball == null:
		return
	
	if not golf_ball.has_meta("is_spinning") or not golf_ball.get_meta("is_spinning"):
		return
	
	var spin_axis = golf_ball.get_meta("spin_axis")
	var spin_speed = golf_ball.get_meta("spin_speed")
	
	# Rotate around the spin axis
	golf_ball.rotate(spin_axis, spin_speed * delta)


func _update_ball_shadow() -> void:
	"""Update the ball's ground shadow position during flight"""
	if golf_ball == null:
		return
	
	# Only show shadow when ball is actively in flight (spinning)
	var is_in_flight = golf_ball.has_meta("is_spinning") and golf_ball.get_meta("is_spinning")
	if not is_in_flight:
		golf_ball.hide_shadow()
		return
	
	# Get the ground height below the ball
	var ball_grid_pos = world_to_grid(golf_ball.global_position)
	var ground_y = get_elevation(ball_grid_pos.x, ball_grid_pos.y)
	
	# Calculate height above ground
	var height = golf_ball.global_position.y - ground_y
	
	# Hide shadow if ball is close to ground (aggressive threshold)
	if height < 2.0:
		golf_ball.hide_shadow()
		return
	
	# Update the shadow position and visibility
	golf_ball.update_shadow(ground_y)


func _calculate_arc_position(start: Vector3, end: Vector3, t: float, peak_height: float) -> Vector3:
	"""Calculate position along a parabolic arc at time t (0 to 1).
	   The curve is already baked into the end position, so this just does the height arc."""
	# Linear interpolation for X and Z
	var pos = start.lerp(end, t)
	
	# Parabolic arc for Y (peaks at t=0.5)
	# Using formula: h = 4 * peak * t * (1 - t)
	var arc_height = 4.0 * peak_height * t * (1.0 - t)
	
	# Start from the higher of the two elevations for the arc base
	var base_y = lerp(start.y, end.y, t)
	pos.y = base_y + arc_height
	
	return pos


func _calculate_curved_arc_position(start: Vector3, end: Vector3, t: float, peak_height: float, curve_amount: float, curve_type: String = "draw") -> Vector3:
	"""Calculate position along a curved parabolic arc at time t (0 to 1).
	   curve_amount: lateral offset at landing (positive = right, negative = left)
	   
	   The ball follows a curved path from start to end, where the curve builds
	   progressively throughout the flight (not a banana that goes out and back).
	   
	   Real golf curve physics:
	   - Ball starts relatively straight (initial velocity dominates)
	   - Sidespin effect increases as ball slows down
	   - Curve accelerates in the second half of flight
	   - Ball lands at the offset position (curve_amount applied to end)
	"""
	# The end position already has the curve offset baked in from shot calculation
	# We need to animate a smooth curve FROM start TO end, not through a side point
	
	# Calculate shot direction vector (horizontal only)
	var shot_dir = Vector3(end.x - start.x, 0, end.z - start.z).normalized()
	
	# Perpendicular vector (90 degrees to the right of shot direction)
	var perp = Vector3(-shot_dir.z, 0, shot_dir.x)
	
	# For a proper golf curve:
	# - At t=0: ball is at start, no lateral offset
	# - At t=1: ball is at end (which includes full curve offset)
	# - During flight: ball curves progressively, with more curve late
	#
	# We use a quadratic bezier-like curve where the control point is
	# offset in the OPPOSITE direction of the curve (since the ball
	# starts straight and curves toward the end)
	
	# Calculate how much the ball should "lag" behind the straight line
	# Early in flight: ball is closer to the straight-to-original-aim line
	# Late in flight: ball curves toward the actual end position
	
	# Curve profile: starts straight, accelerates curve in second half
	# Using smoothstep-like curve for natural acceleration
	var curve_progress: float
	if curve_type == "push" or curve_type == "pull":
		# Push/Pull: Linear curve from start
		curve_progress = t
	else:
		# Draw/Fade/Hook/Slice: Slow start, fast finish
		# This makes the ball appear to start straight then curve hard
		curve_progress = t * t * (3.0 - 2.0 * t)  # Smoothstep
		# Make it even more back-loaded for dramatic curve
		curve_progress = pow(curve_progress, 0.7)  # Bias toward end
	
	# The "straight line" aim point (where ball would go without curve)
	# This is offset from the end by the negative of the curve amount
	var straight_aim = end - perp * curve_amount
	
	# Interpolate between straight path and curved path
	var straight_pos = start.lerp(straight_aim, t)
	var curved_end_pos = start.lerp(end, t)
	
	# Blend from straight trajectory toward curved end based on progress
	var pos = straight_pos.lerp(curved_end_pos, curve_progress)
	
	# Parabolic arc for Y (peaks at t=0.5)
	var arc_height = 4.0 * peak_height * t * (1.0 - t)
	var base_y = lerp(start.y, end.y, t)
	pos.y = base_y + arc_height
	
	return pos


func _animate_ball_bounce(land_pos: Vector3) -> void:
	"""Add a small bounce effect when ball lands"""
	if golf_ball == null:
		return
	
	var bounce_height = 0.3  # Small bounce
	var bounce_duration = 0.15
	
	var tween = create_tween()
	
	# Bounce up
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(golf_ball, "position:y", land_pos.y + bounce_height, bounce_duration)
	
	# Fall back down
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(golf_ball, "position:y", land_pos.y, bounce_duration)
	
	# Tiny second bounce
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(golf_ball, "position:y", land_pos.y + bounce_height * 0.3, bounce_duration * 0.6)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(golf_ball, "position:y", land_pos.y, bounce_duration * 0.6)
	
	await tween.finished


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
	
	# Create a bright material for the trajectory ribbon (white for original aim)
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
	
	# Create curved trajectory mesh (cyan for shape-adjusted path)
	curved_trajectory_mesh = MeshInstance3D.new()
	curved_trajectory_mesh.mesh = ImmediateMesh.new()
	
	var curved_mat = StandardMaterial3D.new()
	curved_mat.albedo_color = Color(0.2, 1.0, 1.0, 1.0)  # Cyan
	curved_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	curved_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	curved_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	curved_mat.no_depth_test = true
	curved_mat.vertex_color_use_as_albedo = true
	curved_trajectory_mesh.material_override = curved_mat
	curved_trajectory_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curved_trajectory_mesh.custom_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
	
	add_child(curved_trajectory_mesh)
	
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


# Update the trajectory arc from ball to target
func _update_trajectory(target_pos: Vector3) -> void:
	if golf_ball == null:
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false
		curved_trajectory_mesh.visible = false
		return
	
	var start_pos = golf_ball.position
	var end_pos = target_pos
	
	# Check if there's any pre-applied curve from cards/modifiers
	var pre_curve: float = 0.0
	if shot_manager and shot_manager.current_context:
		pre_curve = shot_manager.current_context.curve_strength + shot_manager.current_context.curve_mod
	
	# Draw the aim trajectory
	if abs(pre_curve) > 0.1:
		# Show curved trajectory preview if cards add curve
		var distance = start_pos.distance_to(end_pos)
		var scaled_curve = pre_curve * distance * 0.15
		_draw_trajectory_arc_curved(trajectory_mesh, start_pos, end_pos, scaled_curve, Color(1.0, 1.0, 1.0, 0.8))
	else:
		# Straight trajectory (curve comes from swing meter later)
		_draw_trajectory_arc(trajectory_mesh, start_pos, end_pos, Color(1.0, 1.0, 1.0, 0.8))
	trajectory_mesh.visible = true
	
	# Curved trajectory mesh not used anymore
	curved_trajectory_mesh.visible = false
	
	# Draw shadow line on ground
	_draw_trajectory_shadow(start_pos, end_pos, abs(pre_curve) > 0.1)


func _draw_trajectory_arc(mesh: MeshInstance3D, start_pos: Vector3, end_pos: Vector3, color: Color) -> void:
	"""Draw a simple parabolic arc trajectory ribbon"""
	var im: ImmediateMesh = mesh.mesh
	im.clear_surfaces()
	
	var segments = 30
	var ribbon_width = 0.12
	var invisible_amount = 0.10
	var fade_amount = 0.15
	
	var forward_dir = (end_pos - start_pos).normalized()
	forward_dir.y = 0
	if forward_dir.length() > 0.001:
		forward_dir = forward_dir.normalized()
	else:
		forward_dir = Vector3.FORWARD
	var right_dir = forward_dir.cross(Vector3.UP).normalized()
	
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		
		# Calculate alpha with invisible sections and fades
		var alpha = 0.0
		if t < invisible_amount:
			alpha = 0.0
		elif t < invisible_amount + fade_amount:
			alpha = (t - invisible_amount) / fade_amount
		elif t > (1.0 - invisible_amount):
			alpha = 0.0
		elif t > (1.0 - invisible_amount - fade_amount):
			alpha = (1.0 - invisible_amount - t) / fade_amount
		else:
			alpha = 1.0
		
		im.surface_set_color(Color(color.r, color.g, color.b, alpha * color.a))
		
		# Simple lerp + parabola for straight trajectory
		var center_pos = start_pos.lerp(end_pos, t)
		var arc_height = sin(t * PI) * trajectory_height
		center_pos.y = lerp(start_pos.y, end_pos.y, t) + arc_height
		
		var left_pos = center_pos - right_dir * ribbon_width
		var right_pos = center_pos + right_dir * ribbon_width
		
		im.surface_add_vertex(left_pos)
		im.surface_add_vertex(right_pos)
	
	im.surface_end()


func _draw_trajectory_arc_curved(mesh: MeshInstance3D, start_pos: Vector3, end_pos: Vector3, curve_amount: float, color: Color) -> void:
	"""Draw a curved parabolic arc trajectory ribbon (for draw/fade shots).
	   The curve starts straight and progressively curves toward the end position."""
	var im: ImmediateMesh = mesh.mesh
	im.clear_surfaces()
	
	var segments = 35  # More segments for smoother curve
	var ribbon_width = 0.12
	var invisible_amount = 0.10
	var fade_amount = 0.15
	
	# Calculate perpendicular direction for curve offset
	var shot_dir = Vector3(end_pos.x - start_pos.x, 0, end_pos.z - start_pos.z).normalized()
	var perp = Vector3(-shot_dir.z, 0, shot_dir.x)  # 90 degrees to the right
	
	# The "straight line" aim point (where ball would go without curve)
	var straight_aim = end_pos - perp * curve_amount
	
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		
		# Calculate alpha with invisible sections and fades
		var alpha = 0.0
		if t < invisible_amount:
			alpha = 0.0
		elif t < invisible_amount + fade_amount:
			alpha = (t - invisible_amount) / fade_amount
		elif t > (1.0 - invisible_amount):
			alpha = 0.0
		elif t > (1.0 - invisible_amount - fade_amount):
			alpha = (1.0 - invisible_amount - t) / fade_amount
		else:
			alpha = 1.0
		
		im.surface_set_color(Color(color.r, color.g, color.b, alpha * color.a))
		
		# Curve progress: starts straight, accelerates curve late
		var curve_progress = t * t * (3.0 - 2.0 * t)  # Smoothstep
		curve_progress = pow(curve_progress, 0.7)  # Bias toward end
		
		# Blend from straight path toward curved end
		var straight_pos = start_pos.lerp(straight_aim, t)
		var curved_end_lerp = start_pos.lerp(end_pos, t)
		var center_pos = straight_pos.lerp(curved_end_lerp, curve_progress)
		
		# Height arc
		var arc_height = sin(t * PI) * trajectory_height
		center_pos.y = lerp(start_pos.y, end_pos.y, t) + arc_height
		
		# Calculate tangent for ribbon orientation (derivative of curve)
		var tangent: Vector3
		if t < 0.99:
			var next_t = t + 0.02
			var next_progress = next_t * next_t * (3.0 - 2.0 * next_t)
			next_progress = pow(next_progress, 0.7)
			var next_straight = start_pos.lerp(straight_aim, next_t)
			var next_curved = start_pos.lerp(end_pos, next_t)
			var next_pos = next_straight.lerp(next_curved, next_progress)
			tangent = (next_pos - center_pos).normalized()
		else:
			tangent = (end_pos - center_pos).normalized()
		tangent.y = 0
		if tangent.length() < 0.001:
			tangent = shot_dir
		tangent = tangent.normalized()
		var local_right = tangent.cross(Vector3.UP).normalized()
		
		var left_pos = center_pos - local_right * ribbon_width
		var right_pos = center_pos + local_right * ribbon_width
		
		im.surface_add_vertex(left_pos)
		im.surface_add_vertex(right_pos)
	
	im.surface_end()


func _draw_curved_trajectory_arc(mesh: MeshInstance3D, start_pos: Vector3, aim_pos: Vector3, curved_end_pos: Vector3, color: Color) -> void:
	"""Draw a bezier curved trajectory ribbon from start toward aim, curving to end"""
	var im: ImmediateMesh = mesh.mesh
	im.clear_surfaces()
	
	var segments = 30
	var ribbon_width = 0.15
	var invisible_amount = 0.10
	var fade_amount = 0.15
	
	var forward_dir = (curved_end_pos - start_pos).normalized()
	forward_dir.y = 0
	if forward_dir.length() > 0.001:
		forward_dir = forward_dir.normalized()
	else:
		forward_dir = Vector3.FORWARD
	var right_dir = forward_dir.cross(Vector3.UP).normalized()
	
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		
		# Calculate alpha
		var alpha = 0.0
		if t < invisible_amount:
			alpha = 0.0
		elif t < invisible_amount + fade_amount:
			alpha = (t - invisible_amount) / fade_amount
		elif t > (1.0 - invisible_amount):
			alpha = 0.0
		elif t > (1.0 - invisible_amount - fade_amount):
			alpha = (1.0 - invisible_amount - t) / fade_amount
		else:
			alpha = 1.0
		
		im.surface_set_color(Color(color.r, color.g, color.b, alpha * color.a))
		
		# Calculate curved position using bezier
		var center_pos = _calculate_trajectory_point(start_pos, aim_pos, curved_end_pos, t)
		
		var left_pos = center_pos - right_dir * ribbon_width
		var right_pos = center_pos + right_dir * ribbon_width
		
		im.surface_add_vertex(left_pos)
		im.surface_add_vertex(right_pos)
	
	im.surface_end()


func _draw_trajectory_shadow(start_pos: Vector3, end_pos: Vector3, is_curved: bool) -> void:
	"""Draw shadow line on ground"""
	var shadow_im: ImmediateMesh = trajectory_shadow_mesh.mesh
	shadow_im.clear_surfaces()
	
	var shadow_width = 0.1
	var shadow_segments = 20
	
	var forward_dir = (end_pos - start_pos).normalized()
	forward_dir.y = 0
	if forward_dir.length() > 0.001:
		forward_dir = forward_dir.normalized()
	else:
		forward_dir = Vector3.FORWARD
	var right_dir = forward_dir.cross(Vector3.UP).normalized()
	
	shadow_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	for i in range(shadow_segments + 1):
		var t = float(i) / float(shadow_segments)
		
		var shadow_alpha = 1.0
		if t < 0.1:
			shadow_alpha = t / 0.1
		elif t > 0.9:
			shadow_alpha = (1.0 - t) / 0.1
		
		shadow_im.surface_set_color(Color(0.0, 0.0, 0.0, shadow_alpha * 0.3))
		
		var ground_pos = Vector3(
			lerp(start_pos.x, end_pos.x, t),
			lerp(start_pos.y, end_pos.y, t) + 0.02,
			lerp(start_pos.z, end_pos.z, t)
		)
		
		var left_shadow = ground_pos - right_dir * shadow_width
		var right_shadow = ground_pos + right_dir * shadow_width
		
		shadow_im.surface_add_vertex(left_shadow)
		shadow_im.surface_add_vertex(right_shadow)
	
	shadow_im.surface_end()
	trajectory_shadow_mesh.visible = true


func _calculate_trajectory_point(start_pos: Vector3, aim_pos: Vector3, curved_end_pos: Vector3, t: float) -> Vector3:
	"""Calculate a point along the trajectory arc with curve.
	   The ball starts toward aim_pos but curves toward curved_end_pos."""
	# Use quadratic bezier for smooth curve from start -> (aim direction) -> curved end
	# Control point is along the original aim direction
	var distance = start_pos.distance_to(aim_pos)
	var control_t = 0.5  # Control point at 50% of distance along original aim
	var control_pos = start_pos.lerp(aim_pos, control_t)
	
	# Quadratic bezier: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
	var one_minus_t = 1.0 - t
	var pos = Vector3.ZERO
	pos.x = one_minus_t * one_minus_t * start_pos.x + 2 * one_minus_t * t * control_pos.x + t * t * curved_end_pos.x
	pos.z = one_minus_t * one_minus_t * start_pos.z + 2 * one_minus_t * t * control_pos.z + t * t * curved_end_pos.z
	
	# Parabolic arc for Y (height) - peaks at t=0.5
	var arc_height = sin(t * PI) * trajectory_height
	var base_y = lerp(start_pos.y, curved_end_pos.y, t)
	pos.y = base_y + arc_height
	
	return pos


# Update tile highlight based on mouse position
func _update_tile_highlight() -> void:
	# Use external camera if set (from HoleViewer), otherwise fall back to main viewport
	var camera: Camera3D = null
	var mouse_pos: Vector2
	
	if external_camera and external_viewport:
		camera = external_camera
		# Get mouse position relative to the external viewport's container
		# The HoleViewer will update hovered_cell directly via set_hover_cell
		# So we skip mouse-based updates when using external camera
		return
	else:
		camera = get_viewport().get_camera_3d()
		mouse_pos = get_viewport().get_mouse_position()
	
	if not camera:
		highlight_mesh.visible = false
		return
	
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
				# Always track hovered_cell for click detection
				hovered_cell = cell
				
				# If target is locked, don't update visuals - keep highlight and AOE on locked cell
				if target_locked:
					_update_trajectory(locked_target_pos)
					return
				
				# Check if cell is forward from ball (or if flag is behind, allow all directions)
				var is_forward = is_forward_from_ball(cell)
				
				# Hide all previous AOE highlights before showing new ones
				_hide_all_aoe_highlights()
				
				# Don't show any highlight for tiles behind the ball (unless flag is behind)
				if not is_forward:
					highlight_mesh.visible = false
					hovered_cell = Vector2i(-1, -1)  # Clear hovered cell so click won't work
					return
				
				# Check if cell is in range
				var in_range = true
				if golf_ball:
					var ball_tile = world_to_grid(golf_ball.position)
					var tile_dist = get_tile_distance(ball_tile, cell)
					var max_dist = get_current_club_distance()
					in_range = tile_dist <= max_dist
				
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
				
				# Change highlight color based on range (gold=in range, red=out of range)
				var mat = highlight_mesh.material_override as StandardMaterial3D
				if mat:
					if in_range:
						mat.albedo_color = Color(1.0, 0.85, 0.0, 0.6)  # Gold = in range
					else:
						mat.albedo_color = Color(1.0, 0.2, 0.2, 0.6)  # Red = out of range
				
				# Only show AOE and trajectory if in range
				if in_range:
					# Get AOE offset based on shot shape (shifts AOE center laterally)
					var aoe_offset = get_shape_aoe_offset()
					var aoe_center = Vector2i(cell.x + aoe_offset, cell.y)
					
					# Clamp AOE center to grid bounds
					aoe_center.x = clampi(aoe_center.x, 0, grid_width - 1)
					
					# Update adjacent highlights (ring 1) around the offset AOE center
					var neighbors = get_adjacent_cells(aoe_center.x, aoe_center.y)
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
					
					# Update outer ring highlights (ring 2) around the offset AOE center
					var outer_cells = get_outer_ring_cells(aoe_center.x, aoe_center.y)
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
				else:
					# Out of range - hide trajectory unless locked
					if not target_locked:
						trajectory_mesh.visible = false
						trajectory_shadow_mesh.visible = false
						curved_trajectory_mesh.visible = false
				return
	
	# No valid hover
	hovered_cell = Vector2i(-1, -1)
	highlight_mesh.visible = false
	_hide_all_aoe_highlights()
	# Keep trajectory visible if locked
	if not target_locked:
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false
		curved_trajectory_mesh.visible = false


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
	
	# flag_position is set in _generate_grid() when flag is placed
	
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
	
	# Generate wind conditions for this hole
	if wind_system:
		# Calculate difficulty based on par and yardage
		var difficulty = 0.5  # Default medium
		if current_par == 5 or current_yardage > 500:
			difficulty = 0.7  # Harder holes get more wind
		elif current_par == 3 or current_yardage < 200:
			difficulty = 0.3  # Easier holes get less wind
		
		wind_system.generate_wind(difficulty)
		
		# Debug wind info
		# print("--- WIND DEBUG ---")
		# print("Speed: %.1f km/h" % wind_system.speed_kmh)
		# print("Direction: %s" % wind_system.get_direction_name())
		# print("Gustiness: %.2f" % wind_system.gustiness)
		# print("------------------")
		
		# Add wind info to on-screen debug text
		hole_info_text += "\n\nWind: %s %d km/h (Gust: %.2f)" % [
			wind_system.get_direction_name(), 
			int(wind_system.speed_kmh),
			wind_system.gustiness
		]
	
	# Update UI Label
	if holelabel:
		holelabel.text = hole_info_text
	
	# Update ShotUI with hole info
	_update_ui_hole_info()


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


# --- Course generation --------------------------------------------------

# Dogleg type for current hole (set during generation, used for width calculation)
var current_dogleg_type: int = 3  # 0-2 = dogleg, 3 = straight

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
	
	# Decide dogleg type BEFORE setting width
	# 0 = random dogleg, 1 = dogleg left, 2 = dogleg right, 3 = mostly straight
	current_dogleg_type = randi() % 4
	
	# Set width based on par (longer holes are wider)
	# If there's a dogleg (types 0-2), ignore the max_width limit to accommodate curves
	var base_width = config.min_width + randi() % (config.max_width - config.min_width + 1)
	if current_dogleg_type < 3:
		# Dogleg holes can be wider - add extra width based on how severe the dogleg is
		var dogleg_extra_width = 6 + randi() % 8  # Add 6-13 extra tiles for doglegs
		grid_width = base_width + dogleg_extra_width
	else:
		grid_width = base_width
	
	# Reset deck for new hole
	if card_system:
		card_system.initialize_starter_deck()
	
	_init_grid()
	_generate_course_features()


func _generate_course_features() -> void:
	# Generate random seeds for noise variation each generation
	var noise_seed = randi() % 1000
	elevation_seed = randi() % 10000

	# ============================================================
	# STEP 1: Place tee and green FIRST (fixed points of the hole)
	# ============================================================
	
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

	# ============================================================
	# STEP 2: Carve fairway (path from tee to green)
	# ============================================================
	
	var green_fairway_gap = 1 + randi() % 2
	var fairway_end_row = green_center_row - green_radius + green_fairway_gap
	var fairway_start_row = tee_row + 2
	var start_row = min(fairway_start_row, fairway_end_row)
	var end_row = max(fairway_start_row, fairway_end_row)

	# Use pre-determined dogleg type from _generate_course()
	var control_col = tee_col
	if current_dogleg_type == 0:
		# Random dogleg - can curve either direction
		var dogleg_offset0 = int((randf() - 0.5) * grid_width * 1.6)
		control_col = clamp(tee_col + dogleg_offset0, 1, grid_width - 2)
	elif current_dogleg_type == 1:
		# Dogleg left
		control_col = 1
	elif current_dogleg_type == 2:
		# Dogleg right
		control_col = grid_width - 2
	else:
		# Mostly straight (type 3) - slight variation
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

	# Store fairway cells for later reference (water should avoid these)
	var fairway_cells: Dictionary = {}
	
	var min_fw_width = 3.0
	var max_fw_width = 10.0
	for i in range(path_points.size()):
		var t2 = float(i) / float(path_points.size() - 1)
		var fw_width = lerp(min_fw_width, max_fw_width, pow(sin(t2 * PI), 1.5))
		var half_width = int(fw_width / 2.0)
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
							fairway_cells[Vector2i(fx, fy)] = true

	# ============================================================
	# STEP 3: Place water features AFTER tee/green/fairway exist
	# ============================================================
	
	# --- BODY OF WATER (edge feature that fills solidly from edge to playable area) ---
	if randf() < 0.35:  # 35% chance of body of water
		var edge = randi() % 2  # 0=left, 1=right (sides only for better gameplay)
		
		# Vertical range for the body of water (almost full height)
		var start_row_water = randi() % max(1, int(grid_height * 0.1))
		var end_row_water = grid_height - randi() % max(1, int(grid_height * 0.1))
		
		# Track water tiles per row for trimming later
		var water_rows: Dictionary = {}  # row -> Array of columns with water
		
		if edge == 0:  # Left edge water
			# Fill each row individually from edge to its nearest playable tile
			for row in range(start_row_water, end_row_water):
				water_rows[row] = []
				# Find the closest playable tile for THIS row
				var row_playable_col = grid_width  # Default to end if no playable found
				for check_col in range(grid_width):
					var surf = get_cell(check_col, row)
					if surf == SurfaceType.FAIRWAY or surf == SurfaceType.TEE or surf == SurfaceType.GREEN:
						row_playable_col = check_col
						break
				
				# Only place water if there's room on this row
				if row_playable_col > 2:
					var fill_to_col = row_playable_col - 1  # 1 tile buffer
					for col in range(0, fill_to_col):
						set_cell(col, row, SurfaceType.WATER)
						water_rows[row].append(col)
			
			# Trim each row to max 10 tiles, keeping tiles closest to playable area (rightmost)
			for row in water_rows.keys():
				var cols = water_rows[row]
				if cols.size() > 10:
					# Sort descending (rightmost first) and keep only first 10
					cols.sort()
					cols.reverse()
					var cols_to_remove = cols.slice(10)
					for col in cols_to_remove:
						# Set back to rough instead of water
						set_cell(col, row, SurfaceType.ROUGH)
		
		else:  # Right edge water (edge == 1)
			# Fill each row individually from its nearest playable tile to edge
			for row in range(start_row_water, end_row_water):
				water_rows[row] = []
				# Find the closest playable tile for THIS row from the right
				var row_playable_col = -1  # Default to start if no playable found
				for check_col in range(grid_width - 1, -1, -1):
					var surf = get_cell(check_col, row)
					if surf == SurfaceType.FAIRWAY or surf == SurfaceType.TEE or surf == SurfaceType.GREEN:
						row_playable_col = check_col
						break
				
				# Only place water if there's room on this row
				if row_playable_col >= 0 and row_playable_col < grid_width - 3:
					var fill_from_col = row_playable_col + 2  # 1 tile buffer
					for col in range(fill_from_col, grid_width):
						set_cell(col, row, SurfaceType.WATER)
						water_rows[row].append(col)
			
			# Trim each row to max 10 tiles, keeping tiles closest to playable area (leftmost)
			for row in water_rows.keys():
				var cols = water_rows[row]
				if cols.size() > 10:
					# Sort ascending (leftmost first) and keep only first 10
					cols.sort()
					var cols_to_remove = cols.slice(10)
					for col in cols_to_remove:
						# Set back to rough instead of water
						set_cell(col, row, SurfaceType.ROUGH)

	# --- POND WATER FEATURE (solid circular shape in rough areas) ---
	if randf() < 0.7:  # 70% chance of pond
		var pond_radius = 2 + randi() % 3  # 2-4 radius
		var attempts = 0
		var placed = false
		
		while not placed and attempts < 50:
			# Pick a random center point (avoid edges)
			var pond_col = pond_radius + 1 + randi() % max(1, grid_width - pond_radius * 2 - 2)
			var pond_row = int(grid_height * 0.2) + randi() % max(1, int(grid_height * 0.6))

			# Check if pond area is clear of playable tiles (with buffer)
			var area_is_clear = true
			var buffer = 2  # Stay 2 tiles away from playable areas
			
			for dcol in range(-pond_radius - buffer, pond_radius + buffer + 1):
				if not area_is_clear:
					break
				for drow in range(-pond_radius - buffer, pond_radius + buffer + 1):
					var ncol = pond_col + dcol
					var nrow = pond_row + drow
					if ncol >= 0 and ncol < grid_width and nrow >= 0 and nrow < grid_height:
						var surf = get_cell(ncol, nrow)
						if surf == SurfaceType.GREEN or surf == SurfaceType.TEE or surf == SurfaceType.FAIRWAY:
							area_is_clear = false
							break

			if area_is_clear:
				# Place the pond - SOLID circle, no conditions inside the radius
				for dcol in range(-pond_radius, pond_radius + 1):
					for drow in range(-pond_radius, pond_radius + 1):
						# Use distance check for circular shape
						var dist_sq = dcol * dcol + drow * drow
						if dist_sq <= pond_radius * pond_radius:
							var col = pond_col + dcol
							var row = pond_row + drow
							# Only check bounds, always fill within the circle
							if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
								set_cell(col, row, SurfaceType.WATER)
				placed = true

			attempts += 1

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

	# --- REMOVE DISCONNECTED WATER ---
	# Hide water that isn't touching any playable tile (fairway, green, tee, rough)
	# Use flood fill to find connected water bodies, remove those that don't touch the hole
	_remove_disconnected_water()

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
			if surf == -1 or surf == SurfaceType.TEE or surf == SurfaceType.GREEN or surf == SurfaceType.FAIRWAY or surf == SurfaceType.FLAG or surf == SurfaceType.WATER:
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


# Remove water cells that are isolated single tiles (not part of a water body)
# Large connected water bodies are kept - only truly isolated water is removed
func _cleanup_floating_water() -> void:
	var water_to_remove: Array = []
	
	for col in range(grid_width):
		for row in range(grid_height):
			if get_cell(col, row) != SurfaceType.WATER:
				continue
			
			# Water at grid edges is always kept
			var is_edge_water = col <= 1 or col >= grid_width - 2 or row <= 1 or row >= grid_height - 2
			if is_edge_water:
				continue
			
			# Count water neighbors and land neighbors
			var water_neighbors = 0
			var land_neighbors = 0
			for dc in range(-1, 2):
				for dr in range(-1, 2):
					if dc == 0 and dr == 0:
						continue
					var nc = col + dc
					var nr = row + dr
					if nc >= 0 and nc < grid_width and nr >= 0 and nr < grid_height:
						var neighbor_surf = get_cell(nc, nr)
						if neighbor_surf == SurfaceType.WATER:
							water_neighbors += 1
						elif neighbor_surf != -1:  # Land (not empty, not water)
							land_neighbors += 1
			
			# Only remove water if it has NO water neighbors AND no land neighbors
			# (truly isolated single tile) OR if it only has 1-2 water neighbors
			# and no land (small floating cluster)
			if water_neighbors == 0 and land_neighbors == 0:
				water_to_remove.append(Vector2i(col, row))
			elif water_neighbors <= 2 and land_neighbors == 0:
				# Small cluster not connected to land - mark for potential removal
				# But only if it's really small (will be caught in subsequent passes)
				water_to_remove.append(Vector2i(col, row))
	
	# Remove floating water cells
	for cell in water_to_remove:
		set_cell(cell.x, cell.y, -1)


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
		flag_position = flag_cell  # Store flag position for gameplay logic
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
	curved_trajectory_mesh.visible = false
	target_highlight_mesh.visible = false
	_hide_all_aoe_highlights()
	
	# Cancel any in-progress shot
	if shot_manager:
		shot_manager.cancel_shot()
	
	_clear_course_nodes()
	_generate_course()
	_generate_grid()
	_log_hole_info()
	
	# Start a fresh shot
	_start_new_shot()


func _on_button_pressed() -> void:
	"""Handle Generate New Hole button - play transition while regenerating"""
	_play_transition_loading(func():
		# Reset shot counter and club selection
		if shot_manager and shot_manager.current_context:
			shot_manager.current_context.shot_index = 0
		current_club = ClubType.DRIVER
		_update_club_button_visuals()
		
		# Reset card deck
		if card_system:
			card_system.initialize_starter_deck()
		
		# Reset target lock
		target_locked = false
		locked_cell = Vector2i(-1, -1)
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false
		curved_trajectory_mesh.visible = false
		target_highlight_mesh.visible = false
		_hide_all_aoe_highlights()
		
		# Cancel any in-progress shot
		if shot_manager:
			shot_manager.cancel_shot()
		
		_clear_course_nodes()
		_generate_course()
		_generate_grid()
		_log_hole_info()
		
		# Start a fresh shot
		_start_new_shot()
	)


# ============================================================================
# SCREEN TRANSITION SYSTEM
# ============================================================================

func _play_opening_transition() -> void:
	"""Animate the screen transition from 1.0 to 0.0 on game start"""
	_play_transition_out()


func _play_transition_out(duration: float = 1.5, show_loading: bool = false) -> void:
	"""Transition OUT (1.0 -> 0.0) to reveal the scene"""
	var transition_rect = get_node_or_null("%sceen-transition")
	if not transition_rect:
		return
	
	transition_rect.visible = true
	var material = transition_rect.material
	if not material or not material is ShaderMaterial:
		return
	
	# Get loading message control
	var loading_message = transition_rect.get_node_or_null("LoadingMessage")
	
	material.set_shader_parameter("animation_progress", 1.0)
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_method(
		func(value: float):
			material.set_shader_parameter("animation_progress", value)
			# Fade loading message out immediately as transition starts
			if loading_message and show_loading:
				# Fade out from the start: progress 1.0->0 maps to opacity 1->0
				loading_message.modulate.a = value,
		1.0,
		0.0,
		duration
	)
	
	tween.tween_callback(func(): 
		transition_rect.visible = false
		if loading_message:
			loading_message.modulate.a = 0.0
	)


func _play_transition_in(duration: float = 0.8, show_loading: bool = false) -> void:
	"""Transition IN (0.0 -> 1.0) to cover the scene"""
	var transition_rect = get_node_or_null("%sceen-transition")
	if not transition_rect:
		return
	
	transition_rect.visible = true
	var material = transition_rect.material
	if not material or not material is ShaderMaterial:
		return
	
	# Get loading message control
	var loading_message = transition_rect.get_node_or_null("LoadingMessage")
	if loading_message:
		loading_message.modulate.a = 0.0
	
	material.set_shader_parameter("animation_progress", 0.0)
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_method(
		func(value: float):
			material.set_shader_parameter("animation_progress", value)
			# Fade loading message in as we cover (only if show_loading is true)
			if loading_message and show_loading:
				# Fade in: progress 0->0.5 stays at 0, then 0.5->1.0 fades to 1
				var opacity = clamp((value - 0.5) * 2.0, 0.0, 1.0)
				loading_message.modulate.a = opacity,
		0.0,
		1.0,
		duration
	)


func _play_transition_loading(loading_action: Callable) -> void:
	"""Play full transition: IN (cover), execute action, then OUT (reveal)
	   The loading_action should be a Callable that performs the loading work"""
	# Transition in to cover screen (with loading message)
	_play_transition_in(0.8, true)
	
	# Wait for transition to complete
	await get_tree().create_timer(0.8).timeout
	
	# Execute the loading action (e.g., generate new hole)
	if loading_action.is_valid():
		loading_action.call()
	
	# Small delay to ensure everything is loaded
	await get_tree().create_timer(0.1).timeout
	
	# Transition out to reveal new content (with loading message fading out)
	_play_transition_out(1.2, true)
