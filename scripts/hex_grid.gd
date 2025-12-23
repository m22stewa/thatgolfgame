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
# accuracy: base AOE rings (higher = more rings = less accurate)
# roll: tiles of roll after landing
# loft: 1-5 scale, affects wind sensitivity & arc visual
# arc_height: visual height of ball flight arc
# swing_difficulty: 1-10 scale for future swing mechanics
const CLUB_STATS = {
	   ClubType.DRIVER: {
		   "name": "Driver",
		   "distance": 22,
		   "accuracy": 3,      # 3 AOE rings - hardest to control
		   "roll": 3,          # Hot landing, lots of roll
		   "loft": 1,          # Low loft
		   "arc_height": 5.0,
		   "swing_difficulty": 10,
		   "curve": 0,         # Base curve (0 = straight)
	   },
	   ClubType.WOOD_3: {
		   "name": "3 Wood",
		   "distance": 20,
		   "accuracy": 3,
		   "roll": 3,
		   "loft": 1,
		   "arc_height": 6.0,
		   "swing_difficulty": 9,
		   "curve": 0,
	   },
	   ClubType.WOOD_5: {
		   "name": "5 Wood",
		   "distance": 18,
		   "accuracy": 3,
		   "roll": 3,
		   "loft": 1,
		   "arc_height": 7.0,
		   "swing_difficulty": 9,
		   "curve": 0,
	   },
	   ClubType.IRON_3: {
		   "name": "3 Iron",
		   "distance": 17,
		   "accuracy": 2,
		   "roll": 2,
		   "loft": 2,
		   "arc_height": 8.0,
		   "swing_difficulty": 8,
		   "curve": 0,
	   },
	   ClubType.IRON_5: {
		   "name": "5 Iron",
		   "distance": 16,
		   "accuracy": 2,
		   "roll": 2,
		   "loft": 2,
		   "arc_height": 9.0,
		   "swing_difficulty": 7,
		   "curve": 0,
	   },
	   ClubType.IRON_6: {
		   "name": "6 Iron",
		   "distance": 15,
		   "accuracy": 1,
		   "roll": 2,
		   "loft": 2,
		   "arc_height": 9.0,
		   "swing_difficulty": 6,
		   "curve": 0,
	   },
	   ClubType.IRON_7: {
		   "name": "7 Iron",
		   "distance": 14,
		   "accuracy": 1,
		   "roll": 1,
		   "loft": 3,
		   "arc_height": 10.0,
		   "swing_difficulty": 5,
		   "curve": 0,
	   },
	   ClubType.IRON_8: {
		   "name": "8 Iron",
		   "distance": 13,
		   "accuracy": 1,
		   "roll": 1,
		   "loft": 3,
		   "arc_height": 10.0,
		   "swing_difficulty": 4,
		   "curve": 0,
	   },
	   ClubType.IRON_9: {
		   "name": "9 Iron",
		   "distance": 12,
		   "accuracy": 1,
		   "roll": 1,
		   "loft": 4,
		   "arc_height": 11.0,
		   "swing_difficulty": 3,
		   "curve": 0,
	   },
	   ClubType.PITCHING_WEDGE: {
		   "name": "Pitching Wedge",
		   "distance": 11,
		   "accuracy": 1,
		   "roll": 1,
		   "loft": 4,
		   "arc_height": 12.0,
		   "swing_difficulty": 2,
		   "curve": 0,
	   },
	   ClubType.SAND_WEDGE: {
		   "name": "Sand Wedge",
		   "distance": 9,
		   "accuracy": 1,
		   "roll": 0,
		   "loft": 5,          # Highest loft
		   "arc_height": 13.0,
		   "swing_difficulty": 2,
		   "curve": 0,
	   },
	   ClubType.PUTTER: {
		   "name": "Putter",
		   "distance": 5,
		   "accuracy": 1,
		   "roll": 5,
		   "loft": 0,
		   "arc_height": 0.0,
		   "swing_difficulty": 1,
		   "curve": 0,
	   }
}

# Current selected club
var current_club: int = -1 # -1 = None

func is_club_selected() -> bool:
	return current_club != -1

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
@export var club_deck: DeckDefinition = preload("res://resources/decks/swing_deck.tres")  # Swing deck (shot modifiers)

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

# Tile vertical stretch - extends tile mesh downward to prevent gaps
# between tiles at different elevations
const TILE_Y_STRETCH := 2.5  # Multiplier for Y scale to fill gaps
const TILE_Y_OFFSET := -0.5  # Offset to push stretched mesh downward

# Tile surface offset - accounts for stretched mesh geometry
# Original mesh top is at +0.5, after 2.5x Y stretch → +1.25, then TILE_Y_OFFSET (-0.5) → +0.75
# This places objects correctly ON TOP of the visible tile surface
const TILE_SURFACE_OFFSET := 0.75  # Actual tile surface relative to elevation

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
var modifier_trajectory_mesh: MeshInstance3D = null  # Shows modified distance (green for +, red for -)
var trajectory_height: float = 5.0  # Peak height of ball flight arc (will vary by club)

# Target locking
var target_locked: bool = false
var locked_cell: Vector2i = Vector2i(-1, -1)
var locked_target_pos: Vector3 = Vector3.ZERO
var target_highlight_mesh: Node3D = null  # White highlight on active/locked cell (TargetMarker instance)
# var target_distance_label: Label3D = null # Now handled inside TargetMarker

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
var run_state: RunStateManager = null  # Tracks progression across holes

# Economy system components
var currency_manager: CurrencyManager = null
var shop_manager: ShopManager = null
var shop_ui: ShopUI = null

# Card system components
var card_system: CardSystemManager = null
var card_library: CardLibrary = null
var deck_manager: DeckManager = null


# UI references for lie info panel
var lie_info_panel: PanelContainer = null
var lie_name_label: Label = null
var lie_description_label: RichTextLabel = null
var lie_modifiers_label: RichTextLabel = null
var lie_view: Control = null  # LieView widget

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
# Values increased 2.5x for more dramatic terrain
const ELEVATION_OFFSETS = {
	# TEE: Raised platform for tee box
	0: 0.4,
	# FAIRWAY: Gentle undulations
	1: 0.0,
	# ROUGH: More varied terrain
	2: 0.12,
	# DEEP_ROUGH: Higher mounds and dunes
	3: 0.3,
	# GREEN: Subtle slopes but relatively flat
	4: 0.05,
	# SAND: Depressed bunkers
	5: -0.6,
	# WATER: Lowest points
	6: -0.8,
	# TREE: On elevated rough/mounds
	7: 0.4,
	# FLAG: Same as green
	8: 0.05
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
		elif child.is_in_group("slope_arrows"):
			to_remove.append(child)
		elif child.is_in_group("coins"):
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
# Amplitudes increased 2x for more dramatic terrain
func _terrain_noise(col: int, row: int) -> float:
	var x = col * ELEVATION_SCALE + elevation_seed
	var y = row * ELEVATION_SCALE
	
	# Octave 1: Large rolling hills (low frequency, high amplitude)
	var octave1 = sin(x * 0.5 + y * 0.3) * cos(y * 0.4 - x * 0.2) * 1.0
	
	# Octave 2: Medium undulations
	var octave2 = sin(x * 1.2 + y * 0.9) * sin(y * 1.1 + x * 0.7) * 0.5
	
	# Octave 3: Small mounds and bumps (high frequency, low amplitude)
	var octave3 = sin(x * 2.5 + y * 2.1) * cos(y * 2.3 - x * 1.8) * 0.25
	
	# Octave 4: Fine detail
	var octave4 = sin(x * 4.0 + y * 3.5) * sin(y * 4.2 + x * 3.8) * 0.12
	
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
			"height": 1.0 + randf() * 0.8,    # 1.0-1.8 height (increased)
			"falloff": 2.0                     # Gradual falloff
		})
	
	# Generate mounds (smaller bumps, often framing fairways)
	for i in range(num_mounds):
		_place_landform(LandformType.MOUND, {
			"radius": 1.5 + randf() * 2.0,    # 1.5-3.5 cell radius
			"height": 0.4 + randf() * 0.4,    # 0.4-0.8 height (increased)
			"falloff": 1.5                     # Steeper falloff
		})
	
	# Generate valleys (depressions, often containing water or swales)
	for i in range(num_valleys):
		_place_landform(LandformType.VALLEY, {
			"radius": 3.0 + randf() * 3.0,    # 3-6 cell radius
			"height": -0.7 - randf() * 0.5,   # -0.7 to -1.2 depth (increased)
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
		"height": 0.6 + randf() * 0.4,  # 0.6-1.0 height (increased)
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
		"depth": -0.4 - randf() * 0.3,  # -0.4 to -0.7 depth (increased)
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
			"height": 0.5 + randf() * 0.5,  # 0.5-1.0 height (increased)
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
		terrain_multiplier = 0.35  # Greens have gentle undulations (hills/valleys)
		landform_multiplier = 0.5  # Landforms create natural breaks
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
	
	# Initialize run state with first hole info
	if run_state:
		run_state.start_hole(current_par, current_yardage)
	
	# Update UI
	_update_ui_hole_info()
	
	_start_new_shot()
	_play_opening_transition()


func _init_club_menu() -> void:
	"""Initialize club selection buttons"""
	# Deprecated: Club selection is now handled by the card system
	pass


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
	else:
		# No target, hide all trajectory arcs
		if trajectory_mesh:
			trajectory_mesh.visible = false
		if trajectory_shadow_mesh:
			trajectory_shadow_mesh.visible = false
		if curved_trajectory_mesh:
			curved_trajectory_mesh.visible = false
		if modifier_trajectory_mesh:
			modifier_trajectory_mesh.visible = false


func get_shape_adjusted_landing(aim_tile: Vector2i) -> Vector2i:
	"""Return the landing tile offset by curve_strength.
	   Negated so landing matches the direction the ball curves TO."""
	var offset = 0
	if shot_manager and shot_manager.current_context:
		offset = -int(round(shot_manager.current_context.curve_strength))
	var landing = Vector2i(aim_tile.x + offset, aim_tile.y)
	landing.x = clampi(landing.x, 0, grid_width - 1)
	return landing


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
	"""DEPRECATED: AOE no longer shifts based on curve.
	   AOE is always centered on the target tile.
	   Curve affects the trajectory arc preview, not the AOE position."""
	return 0


func _on_club_button_pressed(club_type: ClubType) -> void:
	"""Handle club button click - select the club"""
	current_club = club_type
	trajectory_height = CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).arc_height
	# _update_club_button_visuals() # Deprecated
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
					var y_pos = get_elevation(col, row) + TILE_SURFACE_OFFSET
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
	# Deprecated: Club selection is now handled by the card system
	pass


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
	
	# Apply lie distance modifier if we have a shot context with lie info
	if shot_manager and shot_manager.current_context:
		var distance_mod = shot_manager.current_context.distance_mod
		return maxi(1, base_distance + distance_mod)
	
	return base_distance


func get_current_club_base_distance() -> int:
	"""Get unmodified max distance in tiles for current club"""
	return CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).distance


func get_club_for_tile_distance(tile_distance: int) -> Dictionary:
	"""Get the best club for a given tile distance.
	Returns dictionary with 'type', 'name', 'distance', 'accuracy' or null if out of range.
	Excludes putter (only used in putting mode).
	Excludes driver after the tee shot (ball not on tee)."""
	
	# Check if ball is on tee to determine driver availability
	var ball_on_tee = false
	if golf_ball:
		var ball_tile = world_to_grid(golf_ball.position)
		var surface = get_cell(ball_tile.x, ball_tile.y)
		ball_on_tee = (surface == SurfaceType.TEE)
	
	# Find the club with the smallest distance that can still reach the target
	var best_club: int = -1
	var best_club_data: Dictionary = {}
	
	for club_type in CLUB_STATS:
		# Skip putter - it's exclusive to putting mode
		if club_type == ClubType.PUTTER:
			continue
		
		# Skip driver if not on tee
		if club_type == ClubType.DRIVER and not ball_on_tee:
			continue
		
		var stats = CLUB_STATS[club_type]
		# Club can reach if its distance >= tile distance
		if stats.distance >= tile_distance:
			# Prefer the club with smallest distance that can still reach (shorter = more control)
			if best_club == -1 or stats.distance < best_club_data.distance:
				best_club = club_type
				best_club_data = stats
	
	if best_club == -1:
		return {}  # Out of range
	
	return {
		"type": best_club,
		"name": best_club_data.name,
		"distance": best_club_data.distance,
		"accuracy": best_club_data.accuracy,
		"roll": best_club_data.roll,
	}


func get_max_club_distance() -> int:
	"""Get the maximum distance any club can reach.
	Returns driver distance if on tee, otherwise 3-wood distance."""
	if golf_ball:
		var ball_tile = world_to_grid(golf_ball.position)
		var surface = get_cell(ball_tile.x, ball_tile.y)
		if surface == SurfaceType.TEE:
			return CLUB_STATS[ClubType.DRIVER].distance
	# Not on tee - max is 3-wood
	return CLUB_STATS[ClubType.WOOD_3].distance


func get_current_club_loft() -> int:
	"""Get loft value for current club (1-5 scale)"""
	return CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).loft


func get_current_shot_stats() -> Dictionary:
	"""Get complete shot stats: base club stats + all modifiers = final stats.
	Uses the club that would be needed for the current aim target distance."""
	
	# Determine which club to use based on aim target distance
	var club_type = current_club
	if shot_manager and shot_manager.current_context and golf_ball:
		var ball_tile = world_to_grid(golf_ball.position)
		var aim_tile = shot_manager.current_context.aim_tile
		if aim_tile.x >= 0:
			var tile_dist = get_tile_distance(ball_tile, aim_tile)
			var club_info = get_club_for_tile_distance(tile_dist)
			if club_info and club_info.has("type"):
				club_type = club_info.type
	
	var club_stats = CLUB_STATS.get(club_type, CLUB_STATS[ClubType.IRON_7])
	
	# Base stats from club
	var base = {
		"distance": club_stats.distance,
		"accuracy": club_stats.accuracy,
		"roll": club_stats.roll,
		"loft": club_stats.loft,
		"curve": club_stats.curve,
	}

	print("[SHOT] Base club stats: %s" % str(base))

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
		mods.distance_mod = ctx.distance_mod
		mods.accuracy_mod = ctx.accuracy_mod
		mods.roll_mod = ctx.roll_mod
		mods.curve_mod = ctx.curve_strength

		print("[SHOT] Surface mods: distance_mod=%s, accuracy_mod=%s, roll_mod=%s, curve_mod=%s" % [str(ctx.distance_mod), str(ctx.accuracy_mod), str(ctx.roll_mod), str(ctx.curve_strength)])

	# Final calculated stats
	var final = {
		"distance": maxi(1, base.distance + mods.distance_mod),
		"accuracy": maxi(0, base.accuracy + mods.accuracy_mod),
		"roll": maxi(0, base.roll + mods.roll_mod),
		"loft": base.loft,
		"curve": base.curve + mods.curve_mod,
	}

	print("[SHOT] Final shot stats: %s" % str(final))

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
				# Always refresh AOE/trajectory visuals when stats change (including curve/accuracy)
				_refresh_trajectory()


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
	"""Check if a tile is available to hit (in range of any club AND forward)"""
	if golf_ball == null:
		return true
	
	var ball_tile = world_to_grid(golf_ball.position)
	var tile_dist = get_tile_distance(ball_tile, cell)
	var max_dist = get_max_club_distance()  # Use max of any club (Driver)
	
	# Must be within range AND forward from ball
	return tile_dist <= max_dist and is_forward_from_ball(cell)


func _update_dim_overlays() -> void:
	"""Create or update dim overlays for unavailable tiles (only forward, out of range).
	   Shows overlays for tiles beyond the max club range (Driver distance)."""
	# Clear existing overlays
	_clear_dim_overlays()
	
	if golf_ball == null:
		return
	
	var ball_tile = world_to_grid(golf_ball.position)
	var max_dist = get_max_club_distance()  # Max range = Driver distance
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
				var y_pos = get_elevation(col, row) + TILE_SURFACE_OFFSET
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


func is_valid_target(cell: Vector2i) -> bool:
	"""Check if a cell is a valid target for the current shot.
	   No longer requires pre-selected club - auto-selects based on distance."""
	# Check bounds
	if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
		return false
	
	# Check surface (no water, no empty)
	var surface = get_cell(cell.x, cell.y)
	if surface == -1 or surface == SurfaceType.WATER:
		return false
	
	# Must be forward from ball
	if golf_ball:
		if not is_forward_from_ball(cell):
			return false
		
		# Must be within range of ANY club (max is Driver distance)
		var ball_tile = world_to_grid(golf_ball.position)
		var max_dist = get_max_club_distance()
		var tile_dist = get_tile_distance(ball_tile, cell)
		if tile_dist > max_dist:
			return false
		
		# Check if there's a club that can reach this distance
		var club_info = get_club_for_tile_distance(tile_dist)
		if club_info.is_empty():
			return false
	
	return true


func _try_lock_target(cell: Vector2i) -> void:
	"""Attempt to lock target to the specified cell.
	   Auto-selects the appropriate club based on distance."""
	if not is_valid_target(cell):
		return
	
	# Lock to this cell
	locked_cell = cell
	target_locked = true
	
	# Auto-select club based on distance to target
	if golf_ball:
		var ball_tile = world_to_grid(golf_ball.position)
		var tile_dist = get_tile_distance(ball_tile, cell)
		var club_info = get_club_for_tile_distance(tile_dist)
		if club_info and club_info.has("type"):
			current_club = club_info.type
			trajectory_height = CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).arc_height
	
	# Calculate locked target position
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	var x_pos = locked_cell.x * width * 1.5
	var z_pos = locked_cell.y * hex_height + (locked_cell.x % 2) * (hex_height / 2.0)
	var y_pos = get_elevation(locked_cell.x, locked_cell.y)
	locked_target_pos = Vector3(x_pos, y_pos, z_pos)
	
	# Position highlights on locked cell
	highlight_mesh.position = Vector3(x_pos, y_pos + TILE_SURFACE_OFFSET, z_pos)
	highlight_mesh.rotation.y = PI / 6.0
	highlight_mesh.visible = true
	
	target_highlight_mesh.position = Vector3(x_pos, y_pos + TILE_SURFACE_OFFSET, z_pos)
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
	
	# Notify UI that a tile was selected
	if shot_ui:
		print("[HexGrid] Calling shot_ui.set_tile_selected(true)")
		shot_ui.set_tile_selected(true)
	else:
		push_warning("[HexGrid] shot_ui is null, cannot set tile_selected!")
	
	# Update UI
	if shot_ui and golf_ball:
		var terrain = get_cell(adjusted_landing.x, adjusted_landing.y)
		var ball_tile = world_to_grid(golf_ball.position)
		var distance = _calculate_distance_yards(ball_tile, adjusted_landing)
		var tile_dist = get_tile_distance(ball_tile, adjusted_landing)
		shot_ui.update_target_info(terrain, distance)
		
		# Update on-screen label with club name
		var club_info = get_club_for_tile_distance(tile_dist)
		var club_name_str = club_info.get("name", "---") if club_info else "---"
		var club_range_str = ""
		if club_info:
			var max_range = club_info.get("distance", 0)
			club_range_str = "%d tiles" % max_range
		
		# Update shot_ui ClubName and ClubRange labels
		print("[HexGrid] Updating club: %s, range: %s" % [club_name_str, club_range_str])
		if shot_ui and shot_ui.club_name:
			shot_ui.club_name.text = club_name_str
		if shot_ui and shot_ui.club_range:
			shot_ui.club_range.text = club_range_str
		
		if target_highlight_mesh and target_highlight_mesh.has_method("set_distance_and_club"):
			target_highlight_mesh.set_distance_and_club(distance, club_name_str)
		elif target_highlight_mesh and target_highlight_mesh.has_method("set_distance"):
			target_highlight_mesh.set_distance(distance)


func _update_aoe_for_cell(cell: Vector2i) -> void:
	"""Update AOE highlights around a cell based on card-driven AOE patterns.
	   Default is single tile (no AOE) unless cards provide AOE patterns."""
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	
	_hide_all_aoe_highlights()
	
	# Only show multi-tile AOE after a swing card has been played/selected.
	# Before that, the only highlight should be the single target tile.
	if not (card_system and card_system.selected_club_card != null):
		return
	
	# AOE is card-driven only - default to 0 (single tile, no spread)
	var aoe_radius := 0
	var aoe_shape := "single"
	
	# Get AOE settings from shot context (set by cards)
	if shot_manager and shot_manager.current_context:
		# Combine base AOE (from AOE effects) with accuracy_mod (from stat effects).
		# Negative accuracy_mod tightens the spread; positive expands it.
		aoe_radius = maxi(0, shot_manager.current_context.aoe_radius + shot_manager.current_context.accuracy_mod)
		aoe_shape = shot_manager.current_context.aoe_shape
	
	# No AOE highlights if radius is 0 (single tile)
	if aoe_radius == 0:
		return
	
	# AOE is always centered on the target tile (no curve offset)
	var aoe_center = cell
	
	# Calculate shot direction for line patterns
	var shot_direction = Vector2i.ZERO
	if golf_ball:
		var ball_tile = world_to_grid(golf_ball.position)
		shot_direction = aoe_center - ball_tile
	
	# Use AOESystem to compute tiles based on shape
	var aoe_tiles: Array[Vector2i] = []
	if aoe_system:
		aoe_tiles = aoe_system.compute_aoe(aoe_center, aoe_radius, aoe_shape, self, shot_direction)
	else:
		# Fallback: just use circle pattern manually
		aoe_tiles = _compute_circle_aoe_fallback(aoe_center, aoe_radius)
	
	# Display highlights for all AOE tiles (except center which has its own highlight)
	for aoe_tile in aoe_tiles:
		if aoe_tile == aoe_center:
			continue  # Skip center tile, it has the target highlight
		if aoe_tile.x >= 0 and aoe_tile.x < grid_width and aoe_tile.y >= 0 and aoe_tile.y < grid_height:
			var surface = get_cell(aoe_tile.x, aoe_tile.y)
			if surface != -1 and surface != SurfaceType.WATER:
				# Determine ring distance for coloring
				var ring = _get_hex_distance(aoe_center, aoe_tile)
				var highlight = _get_or_create_aoe_highlight(aoe_tile, ring)
				var t_x = aoe_tile.x * width * 1.5
				var t_z = aoe_tile.y * hex_height + (aoe_tile.x % 2) * (hex_height / 2.0)
				var t_y = get_elevation(aoe_tile.x, aoe_tile.y) + TILE_SURFACE_OFFSET
				highlight.position = Vector3(t_x, t_y, t_z)
				highlight.rotation.y = PI / 6.0
				highlight.visible = true


func _compute_circle_aoe_fallback(center: Vector2i, radius: int) -> Array[Vector2i]:
	"""Fallback circle AOE computation if AOESystem not available"""
	var tiles: Array[Vector2i] = [center]
	if radius >= 1:
		tiles.append_array(get_adjacent_cells(center.x, center.y))
	if radius >= 2:
		tiles.append_array(get_outer_ring_cells(center.x, center.y))
	if radius >= 3:
		tiles.append_array(get_ring_3_cells(center.x, center.y))
	return tiles


func _get_hex_distance(a: Vector2i, b: Vector2i) -> int:
	"""Calculate hex distance between two tiles"""
	# Convert to cube coordinates for accurate hex distance
	var ax = a.x
	var ay = a.y - (a.x - (a.x & 1)) / 2
	var az = -ax - ay
	
	var bx = b.x
	var by = b.y - (b.x - (b.x & 1)) / 2
	var bz = -bx - by
	
	return (abs(ax - bx) + abs(ay - by) + abs(az - bz)) / 2


func refresh_aoe_display() -> void:
	"""Public function to refresh AOE display after modifiers change.
	   Call this when cards are applied that affect accuracy.
	   Also hides AOE if no target is selected."""
	if target_locked and locked_cell.x >= 0:
		_update_aoe_for_cell(locked_cell)
	elif hovered_cell.x >= 0:
		# For hover preview, re-run the hover logic
		set_hover_cell(hovered_cell)
	else:
		# No target selected, hide AOE
		_hide_all_aoe_highlights()


## Public function to set aim target from external sources (like HoleViewer)
func set_aim_cell(cell: Vector2i) -> bool:
	"""Set the aim target to a specific cell. Returns true if successful."""
	# Use unified validation
	if not is_valid_target(cell):
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
	highlight_mesh.position = Vector3(x_pos, y_pos + TILE_SURFACE_OFFSET, z_pos)
	highlight_mesh.rotation.y = PI / 6.0
	highlight_mesh.visible = true
	
	# Show white target highlight on the locked cell (original aim point)
	target_highlight_mesh.position = Vector3(x_pos, y_pos + TILE_SURFACE_OFFSET, z_pos)
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
		var tile_dist = get_tile_distance(ball_tile, adjusted_landing)
		shot_ui.update_target_info(terrain, distance)
		
		# Update on-screen label with club name
		var club_info = get_club_for_tile_distance(tile_dist)
		var club_name_str = club_info.get("name", "---") if club_info else "---"
		var club_range_str = ""
		if club_info:
			var max_range = club_info.get("distance", 0)
			club_range_str = "%d tiles" % max_range
		
		# Update shot_ui ClubName and ClubRange labels
		print("[HexGrid] set_aim_cell: Updating club: %s, range: %s" % [club_name_str, club_range_str])
		if shot_ui.club_name:
			shot_ui.club_name.text = club_name_str
		if shot_ui.club_range:
			shot_ui.club_range.text = club_range_str
		
		if target_highlight_mesh and target_highlight_mesh.has_method("set_distance_and_club"):
			target_highlight_mesh.set_distance_and_club(distance, club_name_str)
		elif target_highlight_mesh and target_highlight_mesh.has_method("set_distance"):
			target_highlight_mesh.set_distance(distance)
	
	# Display debug info for the clicked tile
	_display_tile_debug_info(locked_cell)
	
	return true


## Set hovered cell for highlighting (from external sources like HoleViewer)
func set_hover_cell(cell: Vector2i) -> void:
	"""Set the currently hovered cell and update all highlighting"""
	# If target is locked, don't update visuals - keep it on locked cell
	if target_locked:
		_update_trajectory(locked_target_pos)
		return
	
	# Check basic validity (bounds, surface type)
	if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
		hovered_cell = Vector2i(-1, -1)
		highlight_mesh.visible = false
		target_highlight_mesh.visible = false
		_hide_all_aoe_highlights()
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false
		curved_trajectory_mesh.visible = false
		return
	
	var surface = get_cell(cell.x, cell.y)
	if surface == -1 or surface == SurfaceType.WATER:
		hovered_cell = Vector2i(-1, -1)
		highlight_mesh.visible = false
		target_highlight_mesh.visible = false
		_hide_all_aoe_highlights()
		return
	
	# Check if forward from ball
	if not is_forward_from_ball(cell):
		hovered_cell = Vector2i(-1, -1)
		highlight_mesh.visible = false
		target_highlight_mesh.visible = false
		_hide_all_aoe_highlights()
		return
	
	# Hide all previous AOE highlights before showing new ones
	_hide_all_aoe_highlights()
	
	# Use unified validation to check if this is a clickable target
	var is_clickable = is_valid_target(cell)
	
	# Only set hovered_cell for valid, clickable targets
	if is_clickable:
		hovered_cell = cell
	else:
		hovered_cell = Vector2i(-1, -1)
	
	# Position highlight mesh at the cell (show for both clickable and non-clickable for feedback)
	var width = TILE_SIZE
	var hex_height = TILE_SIZE * sqrt(3.0)
	var x_pos = cell.x * width * 1.5
	var z_pos = cell.y * hex_height + (cell.x % 2) * (hex_height / 2.0)
	var y_pos = get_elevation(cell.x, cell.y) + TILE_SURFACE_OFFSET
	
	highlight_mesh.position = Vector3(x_pos, y_pos, z_pos)
	highlight_mesh.rotation.y = PI / 6.0
	highlight_mesh.visible = true
	
	# Change highlight color based on clickability
	var mat = highlight_mesh.material_override as StandardMaterial3D
	if mat:
		if is_clickable:
			mat.albedo_color = Color(1.0, 0.85, 0.0, 0.6)  # Gold = clickable
		else:
			mat.albedo_color = Color(1.0, 0.2, 0.2, 0.6)  # Red = not clickable
	
	# Always show target marker and distance when hovering any valid tile
	target_highlight_mesh.position = Vector3(x_pos, y_pos, z_pos)
	target_highlight_mesh.rotation.y = PI / 6.0
	target_highlight_mesh.visible = true
	
	# Always show distance and club name on hover
	if golf_ball:
		var ball_tile = world_to_grid(golf_ball.position)
		var tile_dist = get_tile_distance(ball_tile, cell)
		var distance_yards = _calculate_distance_yards(ball_tile, cell)
		
		# Get the best club for this distance
		var club_info = get_club_for_tile_distance(tile_dist)
		var club_name = club_info.get("name", "Out of Range") if club_info else "Out of Range"
		
		if target_highlight_mesh and target_highlight_mesh.has_method("set_distance_and_club"):
			target_highlight_mesh.set_distance_and_club(distance_yards, club_name)
		elif target_highlight_mesh and target_highlight_mesh.has_method("set_distance"):
			target_highlight_mesh.set_distance(distance_yards)
	
	# Only show AOE and trajectory if valid target (in range)
	if is_clickable:
		# Don't show AOE after hole complete
		if hole_complete_triggered:
			_hide_all_aoe_highlights()
			return
		
		# Use the centralized AOE display function (card-driven)
		_update_aoe_for_cell(cell)
		
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
	# Create Run State Manager
	run_state = RunStateManager.new()
	run_state.name = "RunStateManager"
	add_child(run_state)
	run_state.start_new_run(9)  # 9-hole round by default
	
	# Initialize economy system (must be after run_state)
	_init_economy_system()
	
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
	# shot_ui is assigned later in _find_and_setup_ui() after UI is found
	add_child(card_system)
	
	# Initialize starter deck
	card_system.starter_deck_definition = starter_deck
	card_system.club_deck_definition = club_deck
	card_system.initialize_starter_deck()
	
	# Connect swing hand 3D to club_deck_manager (contains swing cards from swing_deck.tres)
	var swing_hand_3d = get_node_or_null("/root/GOLF/Control/MainUI/SwingHand/SubViewportContainer/SubViewport/SwingHand3D")
	if swing_hand_3d:
		print("SwingHand3D found, setting up with club_deck_manager (swing cards)")
		swing_hand_3d.setup(card_system.club_deck_manager)
		# IMPORTANT: SwingHand3D is wired directly here (not via the SwingHand Control wrapper),
		# so we must forward slot play/unplay events to CardSystemManager for dynamic AOE.
		if swing_hand_3d.has_signal("card_played") and not swing_hand_3d.card_played.is_connected(card_system._on_swing_slot_card_dropped):
			swing_hand_3d.card_played.connect(card_system._on_swing_slot_card_dropped)
		if swing_hand_3d.has_signal("card_unplayed") and not swing_hand_3d.card_unplayed.is_connected(card_system._on_swing_hand_card_unplayed):
			swing_hand_3d.card_unplayed.connect(card_system._on_swing_hand_card_unplayed)
		# Draw initial hand of swing cards
		for i in range(5):
			card_system.club_deck_manager.draw_card()
		print("Swing hand has ", card_system.club_deck_manager.get_hand().size(), " cards")
	else:
		print("SwingHand3D not found!")
	
	# Connect modifier deck 3D to deck_manager (contains modifier cards from starter_deck.tres)
	var modifier_deck_ui = get_node_or_null("/root/GOLF/Control/MainUI/ModifierDeckUI")
	if modifier_deck_ui:
		print("ModifierDeckUI found, setting up with deck_manager (modifier cards)")
		modifier_deck_ui.setup(card_system.deck_manager)
		print("Modifier deck has ", card_system.deck_manager.get_all_deck_cards().size(), " cards")
	else:
		print("ModifierDeckUI not found!")

	
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


func _init_economy_system() -> void:
	"""Initialize the economy/shop system for between-hole purchases"""
	# Create currency manager
	currency_manager = CurrencyManager.new()
	currency_manager.name = "CurrencyManager"
	add_child(currency_manager)
	
	# Connect to run state
	currency_manager.set_run_state(run_state)
	
	# Create shop manager
	shop_manager = ShopManager.new()
	shop_manager.name = "ShopManager"
	add_child(shop_manager)
	
	# Connect shop manager signals
	if shop_manager:
		shop_manager.card_purchased.connect(_on_shop_card_purchased)
		shop_manager.shop_closed.connect(_on_shop_closed)
	
	# Shop UI will be found/created in _find_and_setup_ui


func _on_shop_card_purchased(card_data: CardData) -> void:
	"""Called when a card is purchased from the shop"""
	# Add to deck via card system
	if deck_manager:
		deck_manager.add_card_to_deck(card_data)
	print("[HexGrid] Card purchased: %s" % card_data.card_name)


func _on_shop_closed() -> void:
	"""Called when player closes the shop - proceed to next hole"""
	_proceed_to_next_hole()


func _on_putting_mode_entered() -> void:
	"""Called when entering putting mode"""
	# Hide regular shot UI elements
	_hide_shot_visuals()
	# Show green contour overlay
	_set_green_overlay_visible(true)


func _on_putting_mode_exited() -> void:
	"""Called when exiting putting mode"""
	# Show regular shot UI elements again
	_show_shot_visuals()
	# Hide green contour overlay
	_set_green_overlay_visible(false)


func _set_green_overlay_visible(visible: bool) -> void:
	"""Show or hide the green contour overlay (slope_arrows group)"""
	for child in get_children():
		if child.is_in_group("slope_arrows"):
			child.visible = visible


func _on_putt_started(_direction: Vector3, _power: float) -> void:
	"""Called when a putt is executed"""
	# Record the stroke in run state
	if run_state:
		run_state.record_stroke(0)  # Putts don't score points
		# Update UI with new stroke count
		if shot_ui:
			var dist_to_flag = 0
			if golf_ball and flag_position.x >= 0:
				var ball_tile = world_to_grid(golf_ball.position)
				dist_to_flag = _calculate_distance_yards(ball_tile, flag_position)
			shot_ui.update_shot_info(run_state.strokes_this_hole, dist_to_flag)


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
	# Try to find MainUI first
	var main_ui = get_tree().current_scene.find_child("MainUI", true, false)
	if main_ui and main_ui.has_method("get_class") and main_ui.get_script():
		# If it's our MainUI script
		shot_ui = main_ui.shot_ui
		lie_info_panel = main_ui.lie_info_panel
		lie_name_label = main_ui.lie_name_label
		lie_description_label = main_ui.lie_desc_label
		lie_modifiers_label = main_ui.lie_mods_label
		
		# Get LieView widget reference
		if main_ui.has_method("get") and main_ui.get("lie_view"):
			lie_view = main_ui.lie_view
		
		# Also get hole label if needed
		holelabel = main_ui.hole_info_label
		
		# Connect Generate Button
		if main_ui.generate_button:
			if not main_ui.generate_button.pressed.is_connected(_on_button_pressed):
				main_ui.generate_button.pressed.connect(_on_button_pressed)
		
		# Connect Generate Unique Button
		if main_ui.generate_unique_button:
			if not main_ui.generate_unique_button.pressed.is_connected(_on_generate_unique_pressed):
				main_ui.generate_unique_button.pressed.connect(_on_generate_unique_pressed)
		
		# Connect ShotUI
		if shot_ui:
			shot_ui.setup(shot_manager, self)
			# Connect next hole signal
			if not shot_ui.next_hole_requested.is_connected(_on_next_hole_requested):
				shot_ui.next_hole_requested.connect(_on_next_hole_requested)
			# Pass run state reference
			shot_ui.run_state = run_state
			# Connect currency manager for chips display
			if currency_manager:
				shot_ui.set_currency_manager(currency_manager)
			# Connect card system to shot_ui for swing button prerequisites
			if card_system:
				card_system.shot_ui = shot_ui
		
		# Setup shop UI
		_setup_shop_ui()
		return

	# Fallback to old search method
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
		# Connect next hole signal
		if not shot_ui.next_hole_requested.is_connected(_on_next_hole_requested):
			shot_ui.next_hole_requested.connect(_on_next_hole_requested)
		# Pass run state reference
		shot_ui.run_state = run_state
		# Connect currency manager for chips display
		if currency_manager:
			shot_ui.set_currency_manager(currency_manager)
		# Connect card system to shot_ui for swing button prerequisites
		if card_system:
			card_system.shot_ui = shot_ui
	
	# Setup shop UI
	_setup_shop_ui()


func _setup_shop_ui() -> void:
	"""Find or create shop UI"""
	# Try to find existing shop UI in scene
	shop_ui = get_tree().current_scene.find_child("ShopUI", true, false)
	
	# If not found, try to instantiate from scene
	if not shop_ui:
		var shop_scene_path = "res://scenes/ui/shop_ui.tscn"
		if ResourceLoader.exists(shop_scene_path):
			var shop_scene = load(shop_scene_path)
			if shop_scene:
				shop_ui = shop_scene.instantiate()
				shop_ui.name = "ShopUI"
				
				# Add to scene tree (as sibling of other UI)
				var ui_root = get_tree().current_scene.find_child("CanvasLayer", true, false)
				if ui_root:
					ui_root.add_child(shop_ui)
				else:
					get_tree().current_scene.add_child(shop_ui)
	
	# Connect shop signals
	if shop_ui:
		shop_ui.set_managers(shop_manager, currency_manager, deck_manager)
		if not shop_ui.shop_closed.is_connected(_on_shop_closed):
			shop_ui.shop_closed.connect(_on_shop_closed)


func _update_ui_hole_info() -> void:
	"""Update UI with current hole information"""
	if shot_ui:
		var hole_num = run_state.current_hole if run_state else 1
		shot_ui.set_hole_info(hole_num, current_par, current_yardage)
		if run_state:
			shot_ui.total_points = run_state.total_score
			shot_ui.set_hole_display(run_state.get_hole_display())
			# Reset stroke display for new hole
			shot_ui.update_shot_info(run_state.strokes_this_hole, current_yardage)


func _start_new_shot() -> void:
	"""Start a new shot from the ball's current position"""
	if golf_ball == null:
		push_warning("No golf ball to start shot from")
		return
	
	# Get ball's current tile
	var ball_tile = world_to_grid(golf_ball.position)
	var ball_surface = get_cell(ball_tile.x, ball_tile.y)
	
	# Update LieView widget with current surface
	if lie_view and lie_view.has_method("set_lie"):
		var lie_name = _surface_to_lie_name(ball_surface)
		lie_view.set_lie(lie_name)
	
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
	
	# Reset club selection for new shot
	current_club = -1
	
	# Hide swing meter (will show again when club is selected and target locked)
	if shot_ui and shot_ui.swing_meter:
		shot_ui.swing_meter.hide_meter()
	
	# Update UI with distance to flag (useful for club selection)
	if shot_ui and flag_position.x >= 0:
		var dist_to_flag = _calculate_distance_yards(ball_tile, flag_position)
		var stroke_count = run_state.strokes_this_hole if run_state else (shot_manager.current_context.shot_index if shot_manager and shot_manager.current_context else 0)
		shot_ui.update_shot_info(stroke_count, dist_to_flag)
	
	# Start turn selection flow (Club -> Modifier -> Shot)
	if card_system:
		if not card_system.turn_selection_complete.is_connected(_on_turn_selection_complete):
			card_system.turn_selection_complete.connect(_on_turn_selection_complete)
		
		# Don't auto-start selection. Wait for user to click deck.
		# card_system.start_turn_selection()
		
		# Just update overlays for current state (likely empty/default)
		_update_dim_overlays()
	else:
		# Fallback
		shot_manager.start_shot(golf_ball, ball_tile)
		_update_dim_overlays()


func _on_turn_selection_complete(club_card: CardInstance, modifier_card: CardInstance) -> void:
	"""Called when player has finished selecting club and modifiers"""
	if golf_ball == null:
		return
		
	var ball_tile = world_to_grid(golf_ball.position)
	
	# Start the actual shot lifecycle
	shot_manager.start_shot(golf_ball, ball_tile)
	
	# If we have a locked target from pre-aiming, apply it to the new shot
	if target_locked and locked_cell.x >= 0:
		var adjusted_landing = get_shape_adjusted_landing(locked_cell)
		shot_manager.set_aim_target(adjusted_landing)
		
		# Also refresh UI to show SwingMeter now that shot is in progress
		if shot_ui:
			var terrain = get_cell(adjusted_landing.x, adjusted_landing.y)
			var distance = _calculate_distance_yards(ball_tile, adjusted_landing)
			shot_ui.update_target_info(terrain, distance)
	else:
		# If no target locked, try to lock to current hovered cell if valid
		if hovered_cell.x >= 0:
			_try_lock_target(hovered_cell)
		else:
			# If not hovering, we can't show meter yet. User must point at grid.
			pass
	
	# Update dim overlays for new ball position and selected club
	_update_dim_overlays()


func force_start_shot() -> void:
	"""Force start the shot lifecycle - used when player completes swing before card selection"""
	if golf_ball == null:
		return
	
	var ball_tile = world_to_grid(golf_ball.position)
	
	# Start the shot lifecycle
	shot_manager.start_shot(golf_ball, ball_tile)
	
	# If we have a locked target, apply it
	if target_locked and locked_cell.x >= 0:
		var adjusted_landing = get_shape_adjusted_landing(locked_cell)
		shot_manager.set_aim_target(adjusted_landing)


func _calculate_distance_yards(from: Vector2i, to: Vector2i) -> int:
	"""Calculate distance between two cells in yards"""
	var dx = to.x - from.x
	var dy = to.y - from.y
	return int(sqrt(dx * dx + dy * dy) * YARDS_PER_CELL)


func _surface_to_lie_name(surface: int) -> String:
	"""Convert a SurfaceType to the lie name string used by LieView"""
	match surface:
		SurfaceType.TEE:
			return "TEE"
		SurfaceType.FAIRWAY:
			return "FAIRWAY"
		SurfaceType.ROUGH:
			return "ROUGH"
		SurfaceType.DEEP_ROUGH:
			return "DEEP_ROUGH"
		SurfaceType.GREEN:
			return "GREEN"
		SurfaceType.SAND:
			return "SAND"
		SurfaceType.WATER:
			return "WATER"
		_:
			return "FAIRWAY"


func _on_shot_started(context: ShotContext) -> void:
	"""Called when shot begins - calculate lie and update UI"""
	
	# Calculate lie effects for starting position
	if lie_system and context.start_tile.x >= 0:
		var lie_info = lie_system.calculate_lie(self, context.start_tile)
		lie_system.apply_lie_to_shot(context, lie_info)
		
		# Update lie info panel in Control overlay
		_update_lie_info_panel(lie_info)
		
		# Update LieView widget with current lie
		if lie_view and lie_view.has_method("set_lie"):
			var lie_name = lie_info.get("lie_name", "FAIRWAY")
			lie_view.set_lie(lie_name)
		
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
	
	# Record the stroke in run state
	if run_state:
		run_state.record_stroke(context.final_score)
		# Update UI with new stroke count
		if shot_ui:
			var dist_to_flag = 0
			if golf_ball and flag_position.x >= 0:
				var ball_tile = world_to_grid(golf_ball.position)
				dist_to_flag = _calculate_distance_yards(ball_tile, flag_position)
			shot_ui.update_shot_info(run_state.strokes_this_hole, dist_to_flag)
	
	# Reset target lock state
	target_locked = false
	locked_cell = Vector2i(-1, -1)
	locked_target_pos = Vector3.ZERO
	hovered_cell = Vector2i(-1, -1)
	target_highlight_mesh.visible = false
	
	# Hide all AOE and trajectory visuals
	_hide_all_aoe_highlights()
	if trajectory_mesh:
		trajectory_mesh.visible = false
	if trajectory_shadow_mesh:
		trajectory_shadow_mesh.visible = false
	if curved_trajectory_mesh:
		curved_trajectory_mesh.visible = false
	if modifier_trajectory_mesh:
		modifier_trajectory_mesh.visible = false
	
	# Store previous valid tile before shot (for water penalty)
	previous_valid_tile = context.start_tile
	
	# Mark animation as started
	if shot_manager:
		shot_manager.start_animation()
	
	# Track if ball hit water or went out of bounds
	var hit_water = false
	var hit_oob = false
	
	# Animate ball flight to landing position, then bounces
	if golf_ball and context.landing_tile.x >= 0:
		var ball_tile = world_to_grid(golf_ball.position)
		
		# Check if landing tile is water or out of bounds
		var landing_surface = get_cell(context.landing_tile.x, context.landing_tile.y)
		if landing_surface == SurfaceType.WATER:
			hit_water = true
		elif landing_surface == -1:
			hit_oob = true
		
		# Get base bounce count from club (drivers bounce more, wedges less)
		var num_bounces = CLUB_STATS.get(current_club, CLUB_STATS[ClubType.IRON_7]).roll
		
		# Calculate carry position (num_bounces tiles before target)
		var carry_tile = _get_carry_position(ball_tile, context.landing_tile, num_bounces)
		var carry_pos = get_tile_surface_position(carry_tile)
		
		# Check if carry tile is out of bounds BEFORE animating flight
		var carry_surface = get_cell(carry_tile.x, carry_tile.y)
		if carry_surface == -1:
			hit_oob = true
			# Animate ball to OOB position, then handle penalty
			await _animate_ball_flight_with_bounce(golf_ball.position, carry_pos)
			await _handle_out_of_bounds()
		elif carry_surface == SurfaceType.WATER:
			hit_water = true
			# Animate ball flight then splash
			await _animate_ball_flight_with_bounce(golf_ball.position, carry_pos)
			await _handle_water_hazard()
		else:
			# Animate ball flight to carry position
			await _animate_ball_flight_with_bounce(golf_ball.position, carry_pos)
			
			# Calculate roll direction from ball's starting position through carry position
			# This maintains the shot's forward direction, not toward the pin
			var roll_direction = _get_roll_direction(ball_tile, carry_tile)
			
			# Now apply bounces from carry position in the shot's direction
			var final_tile = await _apply_bounce_rollout(carry_tile, roll_direction, num_bounces)
			
			# Check if final tile is OOB (special indicator) or water
			if final_tile == Vector2i(-999, -999):
				# Ball rolled out of bounds
				hit_oob = true
				await _handle_out_of_bounds()
			else:
				var final_surface = get_cell(final_tile.x, final_tile.y)
				if final_surface == SurfaceType.WATER:
					hit_water = true
					await _handle_water_hazard()
				elif final_surface == -1:
					hit_oob = true
					await _handle_out_of_bounds()
		
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
			var strokes = run_state.strokes_this_hole if run_state else context.shot_index
			shot_ui.show_hole_complete(strokes, current_par, 0)
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
	"""Handle ball landing in water - show effect, return ball to previous tile, add penalty stroke"""
	
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
	
	# Add penalty stroke (1 stroke penalty for water hazard per golf rules)
	# This is in ADDITION to the stroke taken to hit into the water
	if run_state:
		run_state.record_stroke(0)  # Penalty stroke with 0 score bonus
		# Update UI with new stroke count
		if shot_ui:
			var dist_to_flag = 0
			if golf_ball and flag_position.x >= 0:
				var ball_tile = world_to_grid(golf_ball.position)
				dist_to_flag = _calculate_distance_yards(ball_tile, flag_position)
			shot_ui.update_shot_info(run_state.strokes_this_hole, dist_to_flag)
	
	# Wait a moment before fading out
	await get_tree().create_timer(0.3).timeout
	
	# Fade out water effect overlay
	if water_effect:
		var tween = create_tween()
		tween.tween_property(water_effect, "color:a", 0.0, 0.7)
		await tween.finished
		water_effect.visible = false  # Hide when done


func _handle_out_of_bounds() -> void:
	"""Handle ball going out of bounds - ball falls for 0.3s, then reset to shot start + penalty stroke"""
	
	# Make the ball fall for 0.3 seconds
	if golf_ball:
		var start_pos = golf_ball.position
		var fall_tween = create_tween()
		# Fall 10 units down over 0.3 seconds with acceleration (gravity feel)
		fall_tween.tween_property(golf_ball, "position:y", start_pos.y - 10.0, 0.3).set_ease(Tween.EASE_IN)
		await fall_tween.finished
		
		# Optional: brief pause for dramatic effect
		await get_tree().create_timer(0.1).timeout
		
		# Move ball back to the shot's starting position (previous_valid_tile)
		if previous_valid_tile.x >= 0:
			var return_pos = get_tile_surface_position(previous_valid_tile)
			golf_ball.position = return_pos
	
	# Add penalty stroke (stroke-and-distance penalty per golf rules)
	if run_state:
		run_state.record_stroke(0)  # Penalty stroke with 0 score bonus
		# Update UI with new stroke count
		if shot_ui:
			var dist_to_flag = 0
			if golf_ball and flag_position.x >= 0:
				var ball_tile = world_to_grid(golf_ball.position)
				dist_to_flag = _calculate_distance_yards(ball_tile, flag_position)
			shot_ui.update_shot_info(run_state.strokes_this_hole, dist_to_flag)


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
	
	# Hide target highlight and club/distance overlay
	if target_highlight_mesh:
		target_highlight_mesh.visible = false
	
	# Hide shot UI club/distance info
	if shot_ui:
		if shot_ui.club_name:
			shot_ui.club_name.visible = false
		if shot_ui.club_range:
			shot_ui.club_range.visible = false
		if shot_ui.distance_label:
			shot_ui.distance_label.visible = false
		if shot_ui.current_terrain:
			shot_ui.current_terrain.visible = false
		if shot_ui.target_terrain:
			shot_ui.target_terrain.visible = false
	
	# Dim the played cards to show they've been used this hole
	if card_system:
		card_system.dim_played_cards()
	
	# Trigger confetti on the flag
	_play_hole_confetti()
	
	# Complete the hole in run state
	var hole_result = {}
	if run_state:
		hole_result = run_state.complete_hole()
	
	# Wait for confetti celebration
	await get_tree().create_timer(0.8).timeout
	
	# Show hole complete popup
	if shot_ui:
		var strokes = run_state.strokes_this_hole if run_state else (shot_manager.current_context.shot_index if shot_manager and shot_manager.current_context else 0)
		var hole_score = hole_result.get("score", 0)
		shot_ui.show_hole_complete(strokes, current_par, hole_score)
		
		# Update total score display
		if run_state:
			shot_ui.total_points = run_state.total_score
	
	# Don't auto-advance - wait for player to click "Next Hole" button


func _on_next_hole_requested() -> void:
	"""Called when player clicks Next Hole button in shot_ui"""
	if not run_state:
		# Fallback: just regenerate
		_regenerate_hole()
		return
	
	# Check if run is complete
	if run_state.is_final_hole():
		# Show run complete screen (for now, just restart)
		_show_run_complete()
		return
	
	# Show shop between holes
	_open_shop()


func _open_shop() -> void:
	"""Open the between-hole shop"""
	if shop_ui:
		shop_ui.set_managers(shop_manager, currency_manager, deck_manager)
		shop_ui.open()
	else:
		# No shop UI - skip directly to next hole
		_proceed_to_next_hole()


func _proceed_to_next_hole() -> void:
	"""Actually advance to the next hole (called after shop closes)"""
	# Advance to next hole
	run_state.advance_to_next_hole()
	
	# Regenerate with transition
	_play_transition_loading(func():
		_regenerate_hole()
	)


func _show_run_complete() -> void:
	"""Show run completion screen - TODO: implement full run complete UI"""
	# For now, start a new run
	if run_state:
		run_state.start_new_run(9)
	
	_play_transition_loading(func():
		_regenerate_hole()
	)


func _regenerate_hole() -> void:
	"""Internal helper to regenerate the hole"""
	# Reset for next hole
	hole_complete_triggered = false
	
	# Reset shot counter (club selection happens in _start_new_shot)
	if shot_manager and shot_manager.current_context:
		shot_manager.current_context.shot_index = 0
	current_club = -1  # Reset club selection
	
	# Reset card deck for new hole
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
	
	# Notify run state of new hole
	if run_state:
		run_state.start_hole(current_par, current_yardage)
	
	# Update UI with new hole info
	_update_ui_hole_info()
	
	# Set initial lie view to TEE
	if lie_view and lie_view.has_method("set_lie"):
		lie_view.set_lie("TEE")
	
	# Start a fresh shot
	_start_new_shot()


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
		
		# Check bounds - ball goes OOB
		if next_tile.x < 0 or next_tile.x >= grid_width or next_tile.y < 0 or next_tile.y >= grid_height:
			# Ball rolls off the grid - animate into the void, then OOB will be handled by caller
			var oob_pos = get_tile_world_position(next_tile)  # Get world pos even for OOB tile
			await _animate_ball_bounce_to_tile(golf_ball.position, oob_pos, bounces_done + 1, num_bounces)
			return Vector2i(-999, -999)  # Special OOB indicator
		
		# Check for hazards that stop the ball
		var next_surface = get_cell(next_tile.x, next_tile.y)
		if next_surface == -1:
			# Ball rolls into empty cell (OOB) - animate into it then return special indicator
			var oob_pos = get_tile_world_position(next_tile)
			await _animate_ball_bounce_to_tile(golf_ball.position, oob_pos, bounces_done + 1, num_bounces)
			return Vector2i(-999, -999)  # Special OOB indicator
		if next_surface == SurfaceType.WATER:
			# Animate into water then return water tile for caller to handle
			var water_pos = get_tile_surface_position(next_tile)
			await _animate_ball_bounce_to_tile(golf_ball.position, water_pos, bounces_done + 1, num_bounces)
			return next_tile  # Return water tile, caller checks surface
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
	   Uses curved flight path when curve_strength or wind_curve is non-zero."""
	if golf_ball == null:
		return
	
	# Get animation speed multiplier
	var speed_mult = shot_manager.get_animation_speed() if shot_manager else 1.0
	
	# Get curve amount from shot context (if available)
	var curve_amount: float = 0.0
	var curve_type: String = "draw"
	if shot_manager and shot_manager.current_context:
		# Curve comes from cards (curve_strength) and wind (wind_curve)
		curve_amount = shot_manager.current_context.curve_strength
		curve_amount += float(shot_manager.current_context.wind_curve)
		
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
	
	# Get the ground height below the ball (tile surface)
	var ball_grid_pos = world_to_grid(golf_ball.global_position)
	var ground_y = get_elevation(ball_grid_pos.x, ball_grid_pos.y) + TILE_SURFACE_OFFSET
	
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
	mat.albedo_color = Color(1.0, 0.85, 0.0, 0.3)  # Bright yellow/gold, lower opacity
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Always fully bright
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_mesh.material_override = mat
	highlight_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	highlight_mesh.visible = false
	add_child(highlight_mesh)
	
	# Create white target highlight for locked/active cell
	var target_marker_scene = load("res://scenes/ui/target_marker.tscn")
	if target_marker_scene:
		target_highlight_mesh = target_marker_scene.instantiate()
	else:
		# Fallback if scene missing
		target_highlight_mesh = Node3D.new()
		
	target_highlight_mesh.visible = false
	add_child(target_highlight_mesh)
	
	# AOE highlights are now created dynamically via _get_or_create_aoe_highlight()


# Get or create an AOE highlight for a specific cell
# ring: 0 = center (not used), 1 = adjacent, 2 = outer ring, 3 = third ring
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
	# Set opacity based on ring distance - more transparent for outer rings
	var alpha: float
	match ring:
		1: alpha = 0.4   # Ring 1 = 40%
		2: alpha = 0.3   # Ring 2 = 30%
		3: alpha = 0.2   # Ring 3 = 20%
		_: alpha = 0.25
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
	
	# Create modifier trajectory mesh (shows modified distance from cards)
	modifier_trajectory_mesh = MeshInstance3D.new()
	modifier_trajectory_mesh.mesh = ImmediateMesh.new()
	
	var mod_mat = StandardMaterial3D.new()
	mod_mat.albedo_color = Color(0.0, 1.0, 0.0, 1.0)  # Default green, will be set per-draw
	mod_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mod_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mod_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mod_mat.no_depth_test = true
	mod_mat.vertex_color_use_as_albedo = true
	modifier_trajectory_mesh.material_override = mod_mat
	modifier_trajectory_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	modifier_trajectory_mesh.custom_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
	
	add_child(modifier_trajectory_mesh)
	
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
	# Safety check: need ball reference and hole not complete
	if golf_ball == null or hole_complete_triggered:
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false
		curved_trajectory_mesh.visible = false
		modifier_trajectory_mesh.visible = false
		return
	
	var start_pos = golf_ball.position
	var end_pos = target_pos
	
	# Check if there's any curve from cards or wind
	var pre_curve: float = 0.0
	var distance_mod: int = 0
	if shot_manager and shot_manager.current_context:
		pre_curve = shot_manager.current_context.curve_strength + float(shot_manager.current_context.wind_curve)
		distance_mod = shot_manager.current_context.distance_mod
	
	# Draw the aim trajectory (base trajectory to aimed tile)
	if abs(pre_curve) > 0.1:
		# Show curved trajectory preview if cards add curve
		var distance = start_pos.distance_to(end_pos)
		var scaled_curve = pre_curve * distance * 0.15
		_draw_trajectory_arc_curved(trajectory_mesh, start_pos, end_pos, scaled_curve, Color(1.0, 1.0, 1.0, 0.8))
	else:
		# Straight trajectory
		_draw_trajectory_arc(trajectory_mesh, start_pos, end_pos, Color(1.0, 1.0, 1.0, 0.8))
	trajectory_mesh.visible = true
	
	# Draw modifier trajectory if distance modifier is active
	if distance_mod != 0:
		# Calculate modified end position (extend or shorten the trajectory)
		var direction = (end_pos - start_pos).normalized()
		direction.y = 0  # Keep horizontal direction only
		if direction.length() > 0.001:
			direction = direction.normalized()
		else:
			direction = Vector3.FORWARD
		
		# Each tile is roughly TILE_SIZE * 1.5 in world units (hex spacing)
		var tile_world_size = TILE_SIZE * 1.5
		var mod_offset = float(distance_mod) * tile_world_size
		var mod_end_pos = end_pos + direction * mod_offset
		# Get elevation at modified position using world_to_grid
		var mod_tile = world_to_grid(mod_end_pos)
		mod_end_pos.y = get_elevation(mod_tile.x, mod_tile.y)
		
		# Choose color based on modifier direction
		var mod_color: Color
		if distance_mod > 0:
			mod_color = Color(0.2, 1.0, 0.2, 0.7)  # Green for + distance
		else:
			mod_color = Color(1.0, 0.2, 0.2, 0.7)  # Red for - distance
		
		# Draw the modifier arc with curve if applicable
		if abs(pre_curve) > 0.1:
			var distance = start_pos.distance_to(mod_end_pos)
			var scaled_curve = pre_curve * distance * 0.15
			_draw_trajectory_arc_curved(modifier_trajectory_mesh, start_pos, mod_end_pos, scaled_curve, mod_color)
		else:
			_draw_trajectory_arc(modifier_trajectory_mesh, start_pos, mod_end_pos, mod_color)
		modifier_trajectory_mesh.visible = true
	else:
		modifier_trajectory_mesh.visible = false
	
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
	# Don't update highlights after hole is complete
	if hole_complete_triggered:
		highlight_mesh.visible = false
		return
	
	# Use external camera if set (from HoleViewer), otherwise fall back to main viewport
	var camera: Camera3D = null
	var mouse_pos: Vector2
	
	if external_camera and external_viewport:
		camera = external_camera
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
	
	# Iterative raycast to handle tile elevation:
	# 1. First, raycast to y=0 plane to get approximate cell
	# 2. Get that cell's elevation and raycast again at that height
	# 3. Repeat once more for better accuracy on steep terrain
	var current_elevation = 0.0
	var cell = Vector2i(-1, -1)
	
	for _i in range(3):  # 3 iterations for convergence
		var plane = Plane(Vector3.UP, current_elevation)
		var intersection = plane.intersects_ray(ray_origin, ray_dir)
		
		if not intersection:
			# No valid hover - clear everything
			set_hover_cell(Vector2i(-1, -1))
			return
		
		# Convert world position to grid coordinates
		cell = world_to_grid(intersection)
		
		# Check bounds before getting elevation
		if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
			break
		
		# Get this cell's elevation and refine
		var new_elevation = get_elevation(cell.x, cell.y)
		if abs(new_elevation - current_elevation) < 0.01:
			break  # Converged
		current_elevation = new_elevation
	
	# Use set_hover_cell to handle all validation and highlighting
	set_hover_cell(cell)


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


# Get ring 3 hex cells for a given cell (3 steps away from center)
func get_ring_3_cells(col: int, row: int) -> Array[Vector2i]:
	var ring3: Array[Vector2i] = []
	var ring1 = get_adjacent_cells(col, row)
	var ring2 = get_outer_ring_cells(col, row)
	var seen: Dictionary = {}
	
	# Mark center, ring 1, and ring 2 as seen
	seen[Vector2i(col, row)] = true
	for cell in ring1:
		seen[cell] = true
	for cell in ring2:
		seen[cell] = true
	
	# For each ring 2 cell, get its neighbors and add ones we haven't seen
	for ring2_cell in ring2:
		var neighbors = get_adjacent_cells(ring2_cell.x, ring2_cell.y)
		for neighbor in neighbors:
			if not seen.has(neighbor):
				seen[neighbor] = true
				ring3.append(neighbor)
	
	return ring3


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
	
	# Add unique hole type if applicable
	if current_unique_type != UniqueHoleType.NONE:
		var unique_name = ""
		match current_unique_type:
			UniqueHoleType.TRUE_DOGLEG: unique_name = "True Dogleg"
			UniqueHoleType.ISLAND_GREEN: unique_name = "Island Green"
			UniqueHoleType.S_CURVE: unique_name = "S-Curve"
			UniqueHoleType.NARROW_FAIRWAY: unique_name = "Narrow Fairway"
		hole_info_text += "Special: %s\n" % unique_name
	
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
		# print("Strength: %d" % wind_system.strength)
		# print("------------------")
		
		# Add wind info to on-screen debug text
		hole_info_text += "\n\nWind: %s %d km/h (%s)" % [
			wind_system.get_direction_name(), 
			int(wind_system.speed_kmh),
			wind_system.get_strength_name()
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

# ============================================================================
# UNIQUE HOLE TYPES
# 30% chance of generating a unique/special hole layout
# ============================================================================
enum UniqueHoleType {
	NONE,           # Standard hole generation
	TRUE_DOGLEG,    # Sharp 90° turn with trees at corner (par 4/5 only)
	ISLAND_GREEN,   # Full island green surrounded by water (par 3 only)
	S_CURVE,        # S-shaped fairway for interesting routing
	NARROW_FAIRWAY  # Trees encroaching creating narrow choke points
}

var current_unique_type: int = UniqueHoleType.NONE

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
	
	# ============================================================
	# UNIQUE HOLE DECISION (30% chance)
	# ============================================================
	current_unique_type = UniqueHoleType.NONE
	if randf() < 0.30:
		# Pick a unique hole type appropriate for this par
		var available_types: Array = []
		
		if current_par >= 4:
			# Par 4/5 can have true doglegs
			available_types.append(UniqueHoleType.TRUE_DOGLEG)
		if current_par == 3:
			# Par 3 can have full island green
			available_types.append(UniqueHoleType.ISLAND_GREEN)
		
		# S-curves and narrow fairways work for all pars
		available_types.append(UniqueHoleType.S_CURVE)
		available_types.append(UniqueHoleType.NARROW_FAIRWAY)
		
		if available_types.size() > 0:
			current_unique_type = available_types[randi() % available_types.size()]
	
	# Decide dogleg type BEFORE setting width
	# For TRUE_DOGLEG unique type, force a dogleg direction
	# 0 = random dogleg, 1 = dogleg left, 2 = dogleg right, 3 = mostly straight
	if current_unique_type == UniqueHoleType.TRUE_DOGLEG:
		# Force a left or right dogleg for true dogleg holes
		current_dogleg_type = 1 + randi() % 2  # 1 or 2
	elif current_unique_type == UniqueHoleType.S_CURVE:
		# S-curves need extra width but use their own path logic
		current_dogleg_type = 3  # Mark as straight, S-curve handles its own path
	else:
		current_dogleg_type = randi() % 4
	
	# Set width based on par - unique holes ignore normal restrictions
	var base_width = config.min_width + randi() % (config.max_width - config.min_width + 1)
	if current_unique_type == UniqueHoleType.TRUE_DOGLEG:
		# True doglegs need massive width for the horizontal section (20+ tiles)
		grid_width = 45 + randi() % 10  # 45-54 tiles wide
	elif current_unique_type == UniqueHoleType.S_CURVE:
		# S-curves need extra width for dramatic curves
		grid_width = 40 + randi() % 10  # 40-49 tiles wide
	elif current_dogleg_type < 3:
		# Dogleg holes can be wider - add extra width based on how severe the dogleg is
		var dogleg_extra_width = 6 + randi() % 8  # Add 6-13 extra tiles for doglegs
		grid_width = base_width + dogleg_extra_width
	elif current_unique_type == UniqueHoleType.ISLAND_GREEN:
		# Island green par 3s can be narrower since it's mostly water
		grid_width = max(base_width, 14)
	else:
		grid_width = base_width
	
	# Log unique hole type if generated
	if current_unique_type != UniqueHoleType.NONE:
		var type_name = ""
		match current_unique_type:
			UniqueHoleType.TRUE_DOGLEG: type_name = "TRUE_DOGLEG"
			UniqueHoleType.ISLAND_GREEN: type_name = "ISLAND_GREEN"
			UniqueHoleType.S_CURVE: type_name = "S_CURVE"
			UniqueHoleType.NARROW_FAIRWAY: type_name = "NARROW_FAIRWAY"
		print("[UNIQUE HOLE] Generating %s (Par %d, %d yards, %dx%d grid)" % [type_name, current_par, current_yardage, grid_width, grid_height])
	
	# Reset deck for new hole
	if card_system:
		card_system.initialize_starter_deck()
	
	_init_grid()
	_generate_course_features()


func _generate_unique_course() -> void:
	"""Generate a course with a guaranteed unique hole type"""
	# Randomly select par (3, 4, or 5)
	var par_options = [3, 4, 5]
	current_par = par_options[randi() % par_options.size()]
	
	# Get config for this par
	var config = PAR_CONFIG[current_par]
	
	# Calculate yardage within the par's range
	current_yardage = config.min_yards + randi() % (config.max_yards - config.min_yards + 1)
	
	# Convert yardage to grid height (length of hole)
	grid_height = int(current_yardage / YARDS_PER_CELL)
	
	# ============================================================
	# FORCE A UNIQUE HOLE TYPE (guaranteed)
	# ============================================================
	var available_types: Array = []
	
	if current_par >= 4:
		# Par 4/5 can have true doglegs
		available_types.append(UniqueHoleType.TRUE_DOGLEG)
	if current_par == 3:
		# Par 3 can have full island green
		available_types.append(UniqueHoleType.ISLAND_GREEN)
	
	# S-curves and narrow fairways work for all pars
	available_types.append(UniqueHoleType.S_CURVE)
	available_types.append(UniqueHoleType.NARROW_FAIRWAY)
	
	# Always pick a unique type
	current_unique_type = available_types[randi() % available_types.size()]
	
	# Decide dogleg type BEFORE setting width
	# For TRUE_DOGLEG unique type, force a dogleg direction
	if current_unique_type == UniqueHoleType.TRUE_DOGLEG:
		# Force a left or right dogleg for true dogleg holes
		current_dogleg_type = 1 + randi() % 2  # 1 or 2
	elif current_unique_type == UniqueHoleType.S_CURVE:
		# S-curves need extra width but use their own path logic
		current_dogleg_type = 3  # Mark as straight, S-curve handles its own path
	else:
		current_dogleg_type = randi() % 4
	
	# Set width based on par - unique holes ignore normal restrictions
	var base_width = config.min_width + randi() % (config.max_width - config.min_width + 1)
	if current_unique_type == UniqueHoleType.TRUE_DOGLEG:
		# True doglegs need massive width for the horizontal section (20+ tiles)
		grid_width = 45 + randi() % 10  # 45-54 tiles wide
	elif current_unique_type == UniqueHoleType.S_CURVE:
		# S-curves need extra width for dramatic curves
		grid_width = 40 + randi() % 10  # 40-49 tiles wide
	elif current_dogleg_type < 3:
		var dogleg_extra_width = 6 + randi() % 8
		grid_width = base_width + dogleg_extra_width
	elif current_unique_type == UniqueHoleType.ISLAND_GREEN:
		grid_width = max(base_width, 14)
	else:
		grid_width = base_width
	
	# Log unique hole type
	if current_unique_type != UniqueHoleType.NONE:
		var type_name = ""
		match current_unique_type:
			UniqueHoleType.TRUE_DOGLEG: type_name = "TRUE_DOGLEG"
			UniqueHoleType.ISLAND_GREEN: type_name = "ISLAND_GREEN"
			UniqueHoleType.S_CURVE: type_name = "S_CURVE"
			UniqueHoleType.NARROW_FAIRWAY: type_name = "NARROW_FAIRWAY"
		print("[UNIQUE HOLE] Generating %s (Par %d, %d yards, %dx%d grid)" % [type_name, current_par, current_yardage, grid_width, grid_height])
	
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
	var green_radius = 3 + randi() % 2 # 3 or 4
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
	# Handle unique hole types differently
	# ============================================================
	
	# Store fairway cells for later reference (water should avoid these)
	var fairway_cells: Dictionary = {}
	
	# Check for special unique hole types that override standard fairway generation
	if current_unique_type == UniqueHoleType.ISLAND_GREEN:
		# Full island green - mostly water with small tee area and green island
		fairway_cells = _generate_island_green_hole(tee_col, tee_row, green_center_col, green_center_row, green_radius)
	elif current_unique_type == UniqueHoleType.TRUE_DOGLEG:
		# True 90-degree dogleg with trees at corner
		fairway_cells = _generate_true_dogleg_hole(tee_col, tee_row, green_center_col, green_center_row, green_radius)
	elif current_unique_type == UniqueHoleType.S_CURVE:
		# S-shaped fairway
		fairway_cells = _generate_s_curve_hole(tee_col, tee_row, green_center_col, green_center_row, green_radius)
	else:
		# Standard fairway generation (also used as base for NARROW_FAIRWAY)
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

		# Apply standard fairway width along path
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
	
	# Apply narrow fairway modifications if needed
	if current_unique_type == UniqueHoleType.NARROW_FAIRWAY:
		_apply_narrow_fairway_trees(fairway_cells)

	# ============================================================
	# STEP 3: Place water features AFTER tee/green/fairway exist
	# Skip most water features for island green holes (they already have water set up)
	# ============================================================
	
	# --- BODY OF WATER (edge feature that fills solidly from edge to playable area) ---
	if current_unique_type != UniqueHoleType.ISLAND_GREEN and randf() < 0.35:  # 35% chance of body of water
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
	# Skip for island green holes
	if current_unique_type != UniqueHoleType.ISLAND_GREEN and randf() < 0.7:  # 70% chance of pond
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
	# Skip if we already have a full island green unique hole
	if current_unique_type != UniqueHoleType.ISLAND_GREEN and randf() < 0.10:
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

	# --- STRATEGIC FAIRWAY HAZARDS (trees and rough patches) ---
	# Add occasional hazards on the fairway for strategic decision-making
	
	# Collect all fairway tiles that aren't near tee/green for hazard placement
	var fairway_hazard_candidates: Array = []
	for col in range(1, grid_width - 1):
		for row in range(1, grid_height - 1):
			if get_cell(col, row) == SurfaceType.FAIRWAY:
				if not _is_adjacent_to_type(col, row, SurfaceType.TEE) \
				and not _is_adjacent_to_type(col, row, SurfaceType.GREEN):
					fairway_hazard_candidates.append(Vector2i(col, row))
	
	if fairway_hazard_candidates.size() > 0:
		# 1. Large single tree on fairway (30% chance)
		if randf() < 0.3:
			var tree_pos = fairway_hazard_candidates[randi() % fairway_hazard_candidates.size()]
			set_cell(tree_pos.x, tree_pos.y, SurfaceType.TREE)
			# Remove this tile from candidates
			fairway_hazard_candidates.erase(tree_pos)
		
		# 2. Small tree groupings (40% chance for 1-2 groupings)
		if randf() < 0.4 and fairway_hazard_candidates.size() > 0:
			var groupings = 1 + randi() % 2  # 1-2 groupings
			for g in range(groupings):
				if fairway_hazard_candidates.size() == 0:
					break
				var group_start = fairway_hazard_candidates[randi() % fairway_hazard_candidates.size()]
				var group_size = 2 + randi() % 3  # 2-4 trees
				var tree_tiles: Array = [group_start]
				set_cell(group_start.x, group_start.y, SurfaceType.TREE)
				fairway_hazard_candidates.erase(group_start)
				
				var tree_dirs = [
					Vector2i(1, 0), Vector2i(-1, 0),
					Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, -1)
				]
				
				for t in range(1, group_size):
					var placed_tree = false
					var tries = 0
					while not placed_tree and tries < 8:
						var base = tree_tiles[randi() % tree_tiles.size()]
						var dir = tree_dirs[randi() % tree_dirs.size()]
						var nx = base.x + dir.x
						var ny = base.y + dir.y
						if nx > 0 and nx < grid_width - 1 and ny > 0 and ny < grid_height - 1:
							if get_cell(nx, ny) == SurfaceType.FAIRWAY \
							and not _is_adjacent_to_type(nx, ny, SurfaceType.TEE) \
							and not _is_adjacent_to_type(nx, ny, SurfaceType.GREEN):
								set_cell(nx, ny, SurfaceType.TREE)
								tree_tiles.append(Vector2i(nx, ny))
								var pos = Vector2i(nx, ny)
								fairway_hazard_candidates.erase(pos)
								placed_tree = true
						tries += 1
		
		# 3. Rough patches on fairway (25% chance for 1-2 patches)
		if randf() < 0.25 and fairway_hazard_candidates.size() > 0:
			var patches = 1 + randi() % 2  # 1-2 patches
			for p in range(patches):
				if fairway_hazard_candidates.size() == 0:
					break
				var patch_start = fairway_hazard_candidates[randi() % fairway_hazard_candidates.size()]
				var patch_size = 2 + randi() % 4  # 2-5 tiles
				var rough_tiles: Array = [patch_start]
				set_cell(patch_start.x, patch_start.y, SurfaceType.ROUGH)
				fairway_hazard_candidates.erase(patch_start)
				
				var rough_dirs = [
					Vector2i(1, 0), Vector2i(-1, 0),
					Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, -1)
				]
				
				for r in range(1, patch_size):
					var placed_rough = false
					var tries_r = 0
					while not placed_rough and tries_r < 8:
						var base_r = rough_tiles[randi() % rough_tiles.size()]
						var dir_r = rough_dirs[randi() % rough_dirs.size()]
						var nx_r = base_r.x + dir_r.x
						var ny_r = base_r.y + dir_r.y
						if nx_r > 0 and nx_r < grid_width - 1 and ny_r > 0 and ny_r < grid_height - 1:
							if get_cell(nx_r, ny_r) == SurfaceType.FAIRWAY \
							and not _is_adjacent_to_type(nx_r, ny_r, SurfaceType.TEE) \
							and not _is_adjacent_to_type(nx_r, ny_r, SurfaceType.GREEN):
								set_cell(nx_r, ny_r, SurfaceType.ROUGH)
								rough_tiles.append(Vector2i(nx_r, ny_r))
								var pos_r = Vector2i(nx_r, ny_r)
								fairway_hazard_candidates.erase(pos_r)
								placed_rough = true
						tries_r += 1

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
				# Further cells (4+) have chance to become trees for hole framing (more trees)
				var tree_threshold = 4.0 + noise_val * 1.5
				if dist >= tree_threshold and randf() < 0.45:
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


# ============================================================================
# UNIQUE HOLE GENERATION FUNCTIONS
# ============================================================================

func _generate_island_green_hole(tee_col: int, tee_row: int, green_col: int, green_row: int, green_radius: int) -> Dictionary:
	"""Generate a full island green par 3 hole.
	Features:
	- Tee box with rough/deep rough around it
	- Mostly water between tee and green
	- Green island surrounded by a ring of rough/fringe
	"""
	var fairway_cells: Dictionary = {}
	
	# Create a small tee area with rough around it
	for dcol in range(-3, 4):
		for drow in range(-2, 4):
			var col = tee_col + dcol
			var row = tee_row + drow
			if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
				var dist = sqrt(dcol * dcol + drow * drow)
				if dist <= 1.5:
					# Keep tee area clear
					continue
				elif dist <= 3:
					set_cell(col, row, SurfaceType.ROUGH)
				elif dist <= 4:
					set_cell(col, row, SurfaceType.DEEP_ROUGH)
	
	# Fill most of the area between tee and green with water
	for col in range(grid_width):
		for row in range(grid_height):
			var surf = get_cell(col, row)
			if surf == SurfaceType.TEE or surf == SurfaceType.GREEN:
				continue
			
			# Distance from tee area
			var tee_dist = sqrt(pow(col - tee_col, 2) + pow(row - tee_row, 2))
			# Distance from green
			var green_dist = sqrt(pow(col - green_col, 2) + pow(row - green_row, 2))
			
			# Near tee - keep rough
			if tee_dist <= 4:
				continue
			
			# Near green - create fringe/rough ring
			if green_dist <= green_radius + 2:
				if green_dist > green_radius:
					set_cell(col, row, SurfaceType.ROUGH)
				continue
			
			# Everything else is water
			set_cell(col, row, SurfaceType.WATER)
	
	return fairway_cells


func _generate_true_dogleg_hole(tee_col: int, tee_row: int, green_col: int, green_row: int, green_radius: int) -> Dictionary:
	"""Generate a true dogleg hole with rounded corner turn.
	Features:
	- Straight fairway for ~20 tiles (driver distance)
	- Smooth rounded corner at the elbow (not sharp 90°)
	- Trees placed at the inside of the corner to prevent cutting
	- Horizontal fairway section (~20 tiles) leading to green
	"""
	var fairway_cells: Dictionary = {}
	
	# Determine dogleg direction (1 = left, 2 = right)
	var dogleg_left = current_dogleg_type == 1
	
	# Calculate the elbow position (where the turn happens)
	var vertical_distance = 18 + randi() % 5  # 18-22 tiles straight
	var horizontal_distance = 18 + randi() % 5  # 18-22 tiles horizontal
	var elbow_row = tee_row + vertical_distance
	
	# Elbow column - start in center
	var elbow_col = tee_col
	
	# Green position for dogleg - place it at end of horizontal run
	var actual_green_col: int
	if dogleg_left:
		actual_green_col = max(green_radius + 3, elbow_col - horizontal_distance)
	else:
		actual_green_col = min(grid_width - green_radius - 3, elbow_col + horizontal_distance)
	
	# Green row - at the end of horizontal section with a small approach
	var actual_green_row = elbow_row + 5 + randi() % 3
	
	# First, clear the existing green and reposition it
	for col in range(grid_width):
		for row in range(grid_height):
			if get_cell(col, row) == SurfaceType.GREEN:
				set_cell(col, row, SurfaceType.ROUGH)
	
	# Place new green at dogleg position
	for dcol in range(-green_radius, green_radius + 1):
		for drow in range(-green_radius, green_radius + 1):
			var dist = sqrt(dcol * dcol + drow * drow)
			if dist <= green_radius:
				var col = actual_green_col + dcol
				var row = actual_green_row + drow
				if col >= 1 and col < grid_width - 1 and row >= 1 and row < grid_height - 1:
					set_cell(col, row, SurfaceType.GREEN)
	
	var fw_width = 4  # Consistent fairway width
	
	# Build the path with a rounded corner using bezier curve
	var path_points: Array = []
	
	# Control points for the path:
	# P0 = just past tee
	# P1 = before the corner (still on vertical)
	# P2 = at the corner (elbow)
	# P3 = after the corner (on horizontal)
	# P4 = end of horizontal (near green)
	
	var p0 = Vector2(elbow_col, tee_row + 2)
	var p1 = Vector2(elbow_col, elbow_row - 5)  # Approach to corner
	var corner_col = actual_green_col if dogleg_left else actual_green_col
	var p2 = Vector2(elbow_col, elbow_row)  # The corner vertex
	var p3 = Vector2(actual_green_col, elbow_row)  # After corner on horizontal
	var p4 = Vector2(actual_green_col, actual_green_row - green_radius - 1)  # Approach to green
	
	# SEGMENT 1: Straight section from tee to before corner
	var seg1_points = 15
	for i in range(seg1_points + 1):
		var t = float(i) / seg1_points
		var px = lerp(p0.x, p1.x, t)
		var py = lerp(p0.y, p1.y, t)
		path_points.append(Vector2(int(px), int(py)))
	
	# SEGMENT 2: Rounded corner using quadratic bezier
	# Corner goes from p1 through p2 (control point) to p3
	var corner_radius = 8  # How many points for the curve
	for i in range(corner_radius + 1):
		var t = float(i) / corner_radius
		var t2 = t * t
		var mt = 1.0 - t
		var mt2 = mt * mt
		# Quadratic bezier: P = (1-t)²P1 + 2(1-t)tP2 + t²P3
		var px = mt2 * p1.x + 2 * mt * t * p2.x + t2 * p3.x
		var py = mt2 * p1.y + 2 * mt * t * p2.y + t2 * p3.y
		path_points.append(Vector2(int(px), int(py)))
	
	# SEGMENT 3: Approach to green (from horizontal to green)
	var seg3_points = 8
	for i in range(seg3_points + 1):
		var t = float(i) / seg3_points
		var px = lerp(p3.x, p4.x, t)
		var py = lerp(p3.y, p4.y, t)
		path_points.append(Vector2(int(px), int(py)))
	
	# Carve fairway along the path
	for i in range(path_points.size()):
		var center = path_points[i]
		for dcol in range(-fw_width, fw_width + 1):
			for drow in range(-fw_width, fw_width + 1):
				if dcol * dcol + drow * drow <= fw_width * fw_width:
					var fx = int(center.x + dcol)
					var fy = int(center.y + drow)
					if fx > 0 and fx < grid_width - 1 and fy > 0 and fy < grid_height - 1:
						var surf_here = get_cell(fx, fy)
						if surf_here != SurfaceType.GREEN and surf_here != SurfaceType.TEE:
							if not _is_adjacent_to_type(fx, fy, SurfaceType.GREEN) and not _is_adjacent_to_type(fx, fy, SurfaceType.TEE):
								set_cell(fx, fy, SurfaceType.FAIRWAY)
								fairway_cells[Vector2i(fx, fy)] = true
	
	# Place trees at the INSIDE corner to punish cutting the dogleg
	var tree_corner_col: int
	var tree_corner_row = elbow_row
	if dogleg_left:
		# Inside corner is to the right of the elbow
		tree_corner_col = elbow_col + fw_width + 3
	else:
		# Inside corner is to the left of the elbow
		tree_corner_col = elbow_col - fw_width - 3
	
	# Create a large cluster of trees at the corner
	for dcol in range(-4, 5):
		for drow in range(-5, 6):
			var col = tree_corner_col + dcol
			var row = tree_corner_row + drow
			if col >= 1 and col < grid_width - 1 and row >= 1 and row < grid_height - 1:
				var surf = get_cell(col, row)
				if surf == SurfaceType.ROUGH or surf == SurfaceType.DEEP_ROUGH:
					if randf() < 0.75:  # 75% tree density
						set_cell(col, row, SurfaceType.TREE)
	
	return fairway_cells


func _generate_s_curve_hole(tee_col: int, tee_row: int, green_col: int, green_row: int, green_radius: int) -> Dictionary:
	"""Generate a dramatic S-shaped fairway hole.
	Features:
	- Fairway curves dramatically left then right (or right then left)
	- Wide sweeping curves that are visually distinct
	- Smooth rounded transitions
	"""
	var fairway_cells: Dictionary = {}
	
	# Decide S direction: true = left-then-right, false = right-then-left
	var left_first = randf() < 0.5
	
	# Calculate control points for the S-curve with DRAMATIC offsets
	var hole_length = green_row - tee_row
	var quarter = hole_length / 4
	
	# First curve apex (1/4 of the way) - dramatic offset
	var curve1_row = tee_row + quarter
	var curve1_offset = 12 + randi() % 6  # 12-17 tiles offset (very dramatic)
	var curve1_col = tee_col + (curve1_offset if left_first else -curve1_offset)
	curve1_col = clamp(curve1_col, 6, grid_width - 7)
	
	# Second curve apex (3/4 of the way) - dramatic offset in opposite direction
	var curve2_row = tee_row + 3 * quarter
	var curve2_offset = 12 + randi() % 6  # 12-17 tiles offset
	var curve2_col = tee_col + (-curve2_offset if left_first else curve2_offset)
	curve2_col = clamp(curve2_col, 6, grid_width - 7)
	
	# Reposition green to align with the end of the S
	for col in range(grid_width):
		for row in range(grid_height):
			if get_cell(col, row) == SurfaceType.GREEN:
				set_cell(col, row, SurfaceType.ROUGH)
	
	# Place new green near the center (S should end near center)
	var actual_green_col = tee_col  # S comes back to center
	var actual_green_row = green_row
	for dcol in range(-green_radius, green_radius + 1):
		for drow in range(-green_radius, green_radius + 1):
			var dist = sqrt(dcol * dcol + drow * drow)
			if dist <= green_radius:
				var col = actual_green_col + dcol
				var row = actual_green_row + drow
				if col >= 1 and col < grid_width - 1 and row >= 1 and row < grid_height - 1:
					set_cell(col, row, SurfaceType.GREEN)
	
	# Build path points using cubic bezier for smooth S
	var path_points: Array = []
	var num_segments = hole_length * 2  # More points for smoother curve
	
	for i in range(num_segments + 1):
		var t = float(i) / num_segments
		var px: float
		var py = lerp(float(tee_row + 2), float(actual_green_row - green_radius - 1), t)
		
		# S-curve using cubic bezier with 4 control points
		# P0 = tee, P1 = curve1, P2 = curve2, P3 = green
		var t2 = t * t
		var t3 = t2 * t
		var mt = 1.0 - t
		var mt2 = mt * mt
		var mt3 = mt2 * mt
		
		px = mt3 * tee_col + 3 * mt2 * t * curve1_col + 3 * mt * t2 * curve2_col + t3 * actual_green_col
		path_points.append(Vector2(int(px), int(py)))
	
	# Carve fairway along the S-curve with consistent width
	var fw_width = 4  # Consistent width for clean look
	for i in range(path_points.size()):
		var center = path_points[i]
		
		for dcol in range(-fw_width, fw_width + 1):
			for drow in range(-fw_width, fw_width + 1):
				if dcol * dcol + drow * drow <= fw_width * fw_width:
					var fx = int(center.x + dcol)
					var fy = int(center.y + drow)
					if fx > 0 and fx < grid_width - 1 and fy > 0 and fy < grid_height - 1:
						var is_adjacent_to_green = _is_adjacent_to_type(fx, fy, SurfaceType.GREEN)
						var is_adjacent_to_tee = _is_adjacent_to_type(fx, fy, SurfaceType.TEE)
						var surf_here = get_cell(fx, fy)
						if surf_here != SurfaceType.GREEN and surf_here != SurfaceType.TEE \
						and not is_adjacent_to_green and not is_adjacent_to_tee:
							set_cell(fx, fy, SurfaceType.FAIRWAY)
							fairway_cells[Vector2i(fx, fy)] = true
	
	return fairway_cells


func _apply_narrow_fairway_trees(fairway_cells: Dictionary) -> void:
	"""Add trees encroaching aggressively on the fairway to create very narrow (3-tile) choke points.
	Called after standard fairway is generated.
	"""
	if fairway_cells.is_empty():
		return
	
	# First, find the fairway width at each row
	var row_fairway_cols: Dictionary = {}  # row -> Array of columns that are fairway
	for cell in fairway_cells.keys():
		if not row_fairway_cols.has(cell.y):
			row_fairway_cols[cell.y] = []
		row_fairway_cols[cell.y].append(cell.x)
	
	# Sort columns for each row
	for row in row_fairway_cols.keys():
		row_fairway_cols[row].sort()
	
	# Find rows to narrow (skip rows near tee and green)
	var rows_to_narrow: Array = []
	for row in row_fairway_cols.keys():
		var cols = row_fairway_cols[row]
		if cols.size() < 6:  # Need at least 6 wide to narrow to 3
			continue
		
		# Check if this row is near tee or green
		var near_tee = false
		var near_green = false
		for col in cols:
			if _is_adjacent_to_type(col, row, SurfaceType.TEE):
				near_tee = true
			if _is_adjacent_to_type(col, row, SurfaceType.GREEN):
				near_green = true
		
		if not near_tee and not near_green:
			rows_to_narrow.append(row)
	
	if rows_to_narrow.is_empty():
		return
	
	# Sort rows
	rows_to_narrow.sort()
	
	# Create 4-6 choke points, evenly distributed
	var num_chokes = 4 + randi() % 3  # 4-6 chokes
	var spacing = rows_to_narrow.size() / (num_chokes + 1)
	var choke_length = 4 + randi() % 3  # 4-6 rows long each choke
	
	for i in range(num_chokes):
		var target_idx = int((i + 1) * spacing)
		if target_idx >= rows_to_narrow.size():
			continue
		
		var center_row = rows_to_narrow[target_idx]
		
		# Narrow this section of fairway to exactly 3 tiles wide
		for drow in range(-choke_length / 2, choke_length / 2 + 1):
			var row = center_row + drow
			if not row_fairway_cols.has(row):
				continue
			
			var cols = row_fairway_cols[row]
			if cols.size() <= 3:
				continue
			
			# Find the center of the fairway
			var min_col = cols[0]
			var max_col = cols[cols.size() - 1]
			var center_col = (min_col + max_col) / 2
			
			# Keep only 3 tiles centered
			var keep_min = center_col - 1
			var keep_max = center_col + 1
			
			# Convert excess fairway to trees
			for col in cols:
				if col < keep_min or col > keep_max:
					# Don't narrow at the very edge of the choke (taper effect)
					var taper = abs(drow) / float(choke_length / 2 + 1)
					if randf() > taper * 0.5:  # More likely to narrow in center
						set_cell(col, row, SurfaceType.TREE)
			
			# Add extra trees just outside the choke for visual impact
			for tree_col in [keep_min - 1, keep_min - 2, keep_max + 1, keep_max + 2]:
				if tree_col >= 1 and tree_col < grid_width - 1:
					var surf = get_cell(tree_col, row)
					if surf == SurfaceType.ROUGH or surf == SurfaceType.DEEP_ROUGH:
						set_cell(tree_col, row, SurfaceType.TREE)


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


# Remove water cells that are isolated or form invalid patterns
# - Single isolated water tiles
# - Water tiles adjacent only to empty cells
# - Small floating water clusters not connected to land
func _cleanup_floating_water() -> void:
	# First pass: Remove water adjacent to empty cells (creates "empty lines")
	# Run this multiple times to erode from edges
	for _pass in range(3):
		var water_to_remove: Array = []
		
		for col in range(grid_width):
			for row in range(grid_height):
				if get_cell(col, row) != SurfaceType.WATER:
					continue
				
				# Count neighbor types
				var water_neighbors = 0
				var land_neighbors = 0
				var empty_neighbors = 0
				
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
							elif neighbor_surf == -1:
								empty_neighbors += 1
							else:
								land_neighbors += 1
						else:
							empty_neighbors += 1  # Out of bounds = empty
				
				# Remove water if:
				# 1. No land neighbors AND has empty neighbors (floating near void)
				# 2. Completely isolated (no water or land neighbors)
				# 3. Only 1-2 water neighbors and no land (small cluster in void)
				if land_neighbors == 0 and empty_neighbors > 0:
					water_to_remove.append(Vector2i(col, row))
				elif water_neighbors == 0 and land_neighbors == 0:
					water_to_remove.append(Vector2i(col, row))
				elif water_neighbors <= 2 and land_neighbors == 0 and empty_neighbors > 3:
					water_to_remove.append(Vector2i(col, row))
		
		# Remove floating water cells
		for cell in water_to_remove:
			set_cell(cell.x, cell.y, -1)
	
	# Second pass: Use flood fill to find water bodies and remove those not touching land
	var visited: Dictionary = {}
	var playable_types = [SurfaceType.FAIRWAY, SurfaceType.GREEN, SurfaceType.TEE, 
						  SurfaceType.ROUGH, SurfaceType.SAND, SurfaceType.DEEP_ROUGH, SurfaceType.TREE]
	
	for col in range(grid_width):
		for row in range(grid_height):
			if get_cell(col, row) != SurfaceType.WATER:
				continue
			if visited.has(Vector2i(col, row)):
				continue
			
			# Flood fill to find connected water body
			var water_body: Array[Vector2i] = []
			var touches_land = false
			var queue: Array[Vector2i] = [Vector2i(col, row)]
			
			while queue.size() > 0:
				var current = queue.pop_front()
				if visited.has(current):
					continue
				visited[current] = true
				
				var cx = current.x
				var cy = current.y
				
				if cx < 0 or cx >= grid_width or cy < 0 or cy >= grid_height:
					continue
				
				var surf = get_cell(cx, cy)
				if surf != SurfaceType.WATER:
					continue
				
				water_body.append(current)
				
				# Check neighbors
				for dc in range(-1, 2):
					for dr in range(-1, 2):
						if dc == 0 and dr == 0:
							continue
						var nc = cx + dc
						var nr = cy + dr
						if nc >= 0 and nc < grid_width and nr >= 0 and nr < grid_height:
							var neighbor_surf = get_cell(nc, nr)
							if neighbor_surf in playable_types:
								touches_land = true
							var neighbor_pos = Vector2i(nc, nr)
							if neighbor_surf == SurfaceType.WATER and not visited.has(neighbor_pos):
								queue.append(neighbor_pos)
			
			# Remove water body if it doesn't touch any land
			if not touches_land:
				for tile in water_body:
					set_cell(tile.x, tile.y, -1)


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
	
	# Ensure tee box is never lower than its neighbors
	_raise_tee_above_neighbors()


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


# Ensure tee box tiles are never lower than their neighbors
func _raise_tee_above_neighbors() -> void:
	# Find all tee tiles and raise them if needed
	for col in range(grid_width):
		for row in range(grid_height):
			var surf = get_cell(col, row)
			if surf != SurfaceType.TEE:
				continue
			
			# Get the current tee elevation
			var tee_elev = get_elevation(col, row)
			
			# Find the maximum neighbor elevation
			var max_neighbor_elev = tee_elev
			for dc in range(-1, 2):
				for dr in range(-1, 2):
					if dc == 0 and dr == 0:
						continue
					var nc = col + dc
					var nr = row + dr
					if nc >= 0 and nc < grid_width and nr >= 0 and nr < grid_height:
						var neighbor_elev = get_elevation(nc, nr)
						max_neighbor_elev = max(max_neighbor_elev, neighbor_elev)
			
			# If tee is lower than any neighbor, raise it slightly above the highest neighbor
			if tee_elev < max_neighbor_elev:
				set_elevation(col, row, max_neighbor_elev + 0.15)


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
	var fairway_cells: Array = []

	for col in range(grid_width):
		for row in range(grid_height):
			var surf = get_cell(col, row)
			if surf == -1:
				continue

			var idx = offsets[surf]
			var x_pos = col * width * 1.5
			var z_pos = row * height + (col % 2) * (height / 2.0)
			var y_pos = get_elevation(col, row)  # Use elevation for Y position
			
			# Create basis with rotation and Y stretch to fill gaps
			var rot = Basis(Vector3.UP, PI / 6.0)
			# Scale Y to extend tile downward and prevent gaps
			var scale_basis = Basis.from_scale(Vector3(1.0, TILE_Y_STRETCH, 1.0))
			var combined_basis = rot * scale_basis
			# Offset Y position to account for stretch (push mesh down so top stays at elevation)
			var adjusted_y = y_pos + TILE_Y_OFFSET
			var xform = Transform3D(combined_basis, Vector3(x_pos, adjusted_y, z_pos))
			multimesh_nodes[surf].multimesh.set_instance_transform(idx, xform)
			offsets[surf] += 1

			if surf == SurfaceType.GREEN:
				green_cells.append(Vector2i(col, row))
			elif surf == SurfaceType.FAIRWAY:
				fairway_cells.append(Vector2i(col, row))

	if green_cells.size() > 0:
		# Place pin with bias toward center of green (70% chance within inner half)
		var flag_cell: Vector2i
		if randf() < 0.7 and green_cells.size() >= 4:
			# Find green center
			var sum_col = 0
			var sum_row = 0
			for gc in green_cells:
				sum_col += gc.x
				sum_row += gc.y
			var center_col = sum_col / green_cells.size()
			var center_row = sum_row / green_cells.size()
			
			# Pick from tiles closer to center (within 40% of max distance)
			var center_tiles = []
			var max_dist = 0.0
			for gc in green_cells:
				var dist = sqrt(pow(gc.x - center_col, 2) + pow(gc.y - center_row, 2))
				if dist > max_dist:
					max_dist = dist
			
			for gc in green_cells:
				var dist = sqrt(pow(gc.x - center_col, 2) + pow(gc.y - center_row, 2))
				if dist <= max_dist * 0.5:  # Within inner 50% radius
					center_tiles.append(gc)
			
			if center_tiles.size() > 0:
				flag_cell = center_tiles[randi() % center_tiles.size()]
			else:
				flag_cell = green_cells[randi() % green_cells.size()]
		else:
			# 30% chance: anywhere on green
			flag_cell = green_cells[randi() % green_cells.size()]
		
		flag_position = flag_cell  # Store flag position for gameplay logic
		var flag_scene = FLAG
		var flag_instance = flag_scene.instantiate()
		var flag_elev = get_elevation(flag_cell.x, flag_cell.y)
		var flag_pos = Vector3(
			flag_cell.x * width * 1.5,
			flag_elev + TILE_SURFACE_OFFSET,  # Flag sits on top of green tile
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
				var tee_y = get_elevation(col, row) + TILE_SURFACE_OFFSET
				teebox_instance.position = Vector3(tee_x, tee_y, tee_z)
				teebox_instance.add_to_group("teebox")
				add_child(teebox_instance)
				
				# Place golf ball at center of tee box
				if golf_ball == null:
					golf_ball = GOLFBALL.instantiate()
					golf_ball.scale = Vector3(0.3, 0.3, 0.3)  # 50% size
					# Position ball on top of tile surface plus ball radius
					tee_position = Vector3(tee_x, tee_y + TILE_SURFACE_OFFSET + BALL_RADIUS_OFFSET, tee_z)
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
				var tree_y = get_elevation(col, row) + TILE_SURFACE_OFFSET  # Position on tile surface
				
				# Add random position offset for natural variation
				tree_x += (randf() - 0.5) * 0.4
				tree_z += (randf() - 0.5) * 0.4
				tree_instance.position = Vector3(tree_x, tree_y, tree_z)
				
				# Random Y rotation for variety
				tree_instance.rotation.y = randf() * TAU
				
				# Random slight tilt for natural look (max ~5 degrees)
				tree_instance.rotation.x = deg_to_rad(randf_range(-5.0, 5.0))
				tree_instance.rotation.z = deg_to_rad(randf_range(-5.0, 5.0))
				
				# Random scale with height bias for tree variety (larger trees)
				var base_scale = randf_range(1.5, 2.5)
				var height_scale = base_scale * randf_range(0.9, 1.3)  # Trees can be taller
				tree_instance.scale = Vector3(base_scale, height_scale, base_scale)
				
				# Apply random color variation to foliage (CSGSphere3D children)
				_apply_random_tree_colors(tree_instance)
				
				# Add collision body so shots can hit trees
				var collision_shape = CollisionShape3D.new()
				var cylinder = CylinderShape3D.new()
				cylinder.radius = 0.3 * base_scale  # Scale with tree size
				cylinder.height = 3.0 * height_scale  # Trunk height
				collision_shape.shape = cylinder
				collision_shape.position = Vector3(0, cylinder.height / 2.0, 0)  # Center on trunk
				
				var static_body = StaticBody3D.new()
				static_body.add_child(collision_shape)
				tree_instance.add_child(static_body)
				
				tree_instance.add_to_group("trees")
				add_child(tree_instance)
	
	# Spawn coins based on par: Par 5 = 3 coins, Par 4 = 2 coins, Par 3 = 1 coin
	_spawn_coins(fairway_cells)
	
	# Spawn foliage (grass patches, bushes, rocks, flowers) based on surface type
	_spawn_foliage()
	
	# Add slope arrows on green tiles
	_spawn_green_slope_arrows(green_cells)


# Coin magnet radius - base is 1 tile, can be increased by items
var coin_magnet_radius: int = 1


# Spawn coins on fairway tiles based on par
# Par 5 = 3 coins, Par 4 = 2 coins, Par 3 = 1 coin
func _spawn_coins(fairway_cells: Array) -> void:
	if fairway_cells.is_empty():
		print("WARNING: No fairway tiles found for coin placement!")
		return
	
	# Determine coin count based on par
	var coin_count: int = 1
	match current_par:
		5: coin_count = 3
		4: coin_count = 2
		3: coin_count = 1
		_: coin_count = 2  # Default
	
	var width = TILE_SIZE
	var height = TILE_SIZE * sqrt(3.0)
	
	# Shuffle fairway cells to get random positions
	var shuffled_cells = fairway_cells.duplicate()
	shuffled_cells.shuffle()
	
	# Spawn coins (up to available fairway cells)
	var coins_to_spawn = min(coin_count, shuffled_cells.size())
	for i in range(coins_to_spawn):
		var coin_cell = shuffled_cells[i]
		var coin_scene = load("res://scenes/coin.tscn")
		var coin_instance = coin_scene.instantiate()
		
		var coin_col = coin_cell.x
		var coin_row = coin_cell.y
		var coin_x = coin_col * width * 1.5
		var coin_z = coin_row * height + (coin_col % 2) * (height / 2.0)
		var coin_y = get_elevation(coin_col, coin_row) + TILE_SURFACE_OFFSET + 0.5
		
		# Wrap coin in a parent Node3D so animation doesn't override world position
		var coin_holder = Node3D.new()
		coin_holder.position = Vector3(coin_x, coin_y, coin_z)
		coin_holder.add_child(coin_instance)
		coin_holder.add_to_group("coins")
		# Store cell position for magnet detection
		coin_holder.set_meta("cell", Vector2i(coin_col, coin_row))
		add_child(coin_holder)
	
	print("[HexGrid] Spawned %d coins for Par %d hole" % [coins_to_spawn, current_par])


# Collect coins within magnet radius of a landing cell
func collect_coins_at(landing_cell: Vector2i) -> int:
	"""Collect any coins within magnet radius of landing position. Returns count collected."""
	var collected = 0
	var coins_to_remove: Array[Node] = []
	
	for child in get_children():
		if child.is_in_group("coins"):
			var coin_cell = child.get_meta("cell", Vector2i(-999, -999))
			var distance = hex_distance(landing_cell, coin_cell)
			
			if distance <= coin_magnet_radius:
				coins_to_remove.append(child)
				collected += 1
	
	# Remove collected coins with animation
	for coin in coins_to_remove:
		_animate_coin_collection(coin)
	
	if collected > 0:
		print("[HexGrid] Collected %d coins at %s (magnet radius: %d)" % [collected, landing_cell, coin_magnet_radius])
	
	return collected


func _animate_coin_collection(coin_node: Node3D) -> void:
	"""Animate coin being collected then remove it"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(coin_node, "position:y", coin_node.position.y + 2.0, 0.3)
	tween.tween_property(coin_node, "scale", Vector3.ZERO, 0.3)
	tween.set_parallel(false)
	tween.tween_callback(coin_node.queue_free)


func hex_distance(a: Vector2i, b: Vector2i) -> int:
	"""Calculate hex grid distance between two cells (axial coordinates)"""
	# Convert offset to cube coordinates for proper hex distance
	var a_cube = offset_to_cube(a)
	var b_cube = offset_to_cube(b)
	return (abs(a_cube.x - b_cube.x) + abs(a_cube.y - b_cube.y) + abs(a_cube.z - b_cube.z)) / 2


func offset_to_cube(offset: Vector2i) -> Vector3i:
	"""Convert offset coordinates to cube coordinates for hex math"""
	var col = offset.x
	var row = offset.y
	var x = col
	var z = row - (col - (col & 1)) / 2
	var y = -x - z
	return Vector3i(x, y, z)


func set_coin_magnet_radius(radius: int) -> void:
	"""Set the coin collection radius (for Coin Magnet item)"""
	coin_magnet_radius = radius
	print("[HexGrid] Coin magnet radius set to %d" % radius)


func reset_coin_magnet_radius() -> void:
	"""Reset coin magnet radius to default"""
	coin_magnet_radius = 1


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


# Spawn contour grid overlay on green tiles to show elevation (like PGA Tour games)
func _spawn_green_slope_arrows(green_cells: Array) -> void:
	var width = TILE_SIZE
	var height = TILE_SIZE * sqrt(3.0)
	
	# Find elevation range on the green for color mapping
	var min_elev = INF
	var max_elev = -INF
	for cell in green_cells:
		var elev = get_elevation(cell.x, cell.y)
		min_elev = min(min_elev, elev)
		max_elev = max(max_elev, elev)
	
	var elev_range = max_elev - min_elev
	if elev_range < 0.01:
		elev_range = 0.01  # Prevent division by zero
	
	# Create a single grid mesh for all green tiles (more efficient)
	var grid_mesh = _create_green_contour_grid(green_cells, min_elev, elev_range)
	if grid_mesh:
		var grid_instance = MeshInstance3D.new()
		grid_instance.mesh = grid_mesh
		grid_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grid_instance.add_to_group("slope_arrows")
		grid_instance.visible = false  # Hidden until putting mode
		add_child(grid_instance)
	
	# Spawn elevation dots at sub-tile resolution for smoother visualization
	var dot_mesh = SphereMesh.new()
	dot_mesh.radius = 0.05  # Slightly smaller
	dot_mesh.height = 0.10
	dot_mesh.radial_segments = 8
	dot_mesh.rings = 4
	
	for cell in green_cells:
		var col = cell.x
		var row = cell.y
		
		# Base cell position
		var cell_x = col * width * 1.5
		var cell_z = row * height + (col % 2) * (height / 2.0)
		
		# Spawn 4 dots per cell in a grid pattern
		var dot_offsets = [
			Vector2(-0.25, -0.25), Vector2(0.25, -0.25),
			Vector2(-0.25, 0.25), Vector2(0.25, 0.25)
		]
		
		for offset in dot_offsets:
			var x_pos = cell_x + offset.x * width * 0.5
			var z_pos = cell_z + offset.y * height * 0.5
			var y_pos = get_elevation(col, row) + TILE_SURFACE_OFFSET + 0.02
			
			# Get elevation and map to color
			var elev = get_elevation(col, row)
			var elev_norm = (elev - min_elev) / elev_range
			
			# Color gradient: blue (low) -> cyan -> green -> yellow -> orange (high)
			var dot_color = _get_elevation_color(elev_norm)
			
			var dot = MeshInstance3D.new()
			dot.mesh = dot_mesh
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = dot_color
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dot.material_override = mat
			dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			
			dot.position = Vector3(x_pos, y_pos, z_pos)
			dot.visible = false  # Hidden until putting mode
			dot.add_to_group("slope_arrows")
			add_child(dot)


func _get_elevation_color(normalized_elev: float) -> Color:
	"""Map normalized elevation (0-1) to a subtle gradient color"""
	# Subtle pastels: light blue (low) -> light green (mid) -> light yellow (high)
	if normalized_elev < 0.33:
		# Light blue to light cyan
		var t = normalized_elev / 0.33
		return Color(0.5, 0.6 + t * 0.15, 0.85, 0.45)
	elif normalized_elev < 0.66:
		# Light cyan to light green
		var t = (normalized_elev - 0.33) / 0.33
		return Color(0.5 + t * 0.2, 0.75, 0.7 - t * 0.2, 0.45)
	else:
		# Light green to light yellow/cream
		var t = (normalized_elev - 0.66) / 0.34
		return Color(0.7 + t * 0.15, 0.75, 0.5 - t * 0.1, 0.45)


func _create_green_contour_grid(green_cells: Array, min_elev: float, elev_range: float) -> ArrayMesh:
	"""Create a grid mesh with contour lines colored by elevation"""
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	var width = TILE_SIZE
	var height = TILE_SIZE * sqrt(3.0)
	
	for cell in green_cells:
		var col = cell.x
		var row = cell.y
		
		var cell_x = col * width * 1.5
		var cell_z = row * height + (col % 2) * (height / 2.0)
		var y_pos = get_elevation(col, row) + TILE_SURFACE_OFFSET + 0.01
		
		# Get elevation-based color
		var elev_norm = (get_elevation(col, row) - min_elev) / elev_range
		var line_color = _get_elevation_color(elev_norm)
		line_color.a = 0.25  # Very subtle lines
		st.set_color(line_color)
		
		# Draw grid lines within the cell
		var half_w = width * 0.4
		var half_h = height * 0.4
		
		# Horizontal line
		st.add_vertex(Vector3(cell_x - half_w, y_pos, cell_z))
		st.add_vertex(Vector3(cell_x + half_w, y_pos, cell_z))
		
		# Vertical line  
		st.add_vertex(Vector3(cell_x, y_pos, cell_z - half_h))
		st.add_vertex(Vector3(cell_x, y_pos, cell_z + half_h))
	
	var mesh = st.commit()
	
	# Create material for the mesh
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, mat)
	
	return mesh


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


func _on_generate_unique_pressed() -> void:
	"""Handle Generate Unique Hole button - forces a unique hole type"""
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
		_generate_unique_course()  # Use unique course generator
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
	# Try to find transition rect in MainUI first
	var transition_rect = null
	var main_ui = get_tree().current_scene.find_child("MainUI", true, false)
	if main_ui:
		transition_rect = main_ui.find_child("sceen-transition", true, false)
	
	# Fallback to old path
	if not transition_rect:
		transition_rect = get_node_or_null("%sceen-transition")
		
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
			# Fade loading message faster - gone by 50% of transition
			if loading_message and show_loading:
				# Map progress 1.0->0.5 to opacity 1->0, then stay at 0
				var text_opacity = clamp((value - 0.5) * 2.0, 0.0, 1.0)
				loading_message.modulate.a = text_opacity,
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
	# Try to find transition rect in MainUI first
	var transition_rect = null
	var main_ui = get_tree().current_scene.find_child("MainUI", true, false)
	if main_ui:
		transition_rect = main_ui.find_child("sceen-transition", true, false)
	
	# Fallback to old path
	if not transition_rect:
		transition_rect = get_node_or_null("%sceen-transition")
		
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
