extends Node3D

## Emitted when a putt resolves on the green board (before it animates).
signal putt_resolved(result: Dictionary)

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
		   "distance": 24,     # R#4: == band_center
		   "band_min": 22,
		   "band_max": 26,
		   "base_spread": 2,
		   "accuracy": 3,      # 3 AOE rings - hardest to control
		   "roll": 2,          # Hot landing, lots of roll
		   "loft": 1,          # Low loft
		   "arc_height": 5.0,
		   "swing_difficulty": 10,
		   "curve": 0,         # Base curve (0 = straight)
	   },
	   ClubType.WOOD_3: {
		   "name": "3 Wood",
		   "distance": 18,     # R#4: == band_center
		   "band_min": 17,
		   "band_max": 19,
		   "base_spread": 2,
		   "accuracy": 3,
		   "roll": 2,
		   "loft": 1,
		   "arc_height": 6.0,
		   "swing_difficulty": 9,
		   "curve": 0,
	   },
	   ClubType.WOOD_5: {
		   "name": "5 Wood",
		   "distance": 16,     # R#4: == band_center (band 16-18)
		   "band_min": 15,
		   "band_max": 17,
		   "base_spread": 2,
		   "accuracy": 3,
		   "roll": 2,
		   "loft": 1,
		   "arc_height": 7.0,
		   "swing_difficulty": 9,
		   "curve": 0,
	   },
	   ClubType.IRON_3: {
		   "name": "3 Iron",
		   "distance": 16,     # R#4: == band_center
		   "band_min": 15,
		   "band_max": 17,
		   "base_spread": 1,
		   "accuracy": 2,
		   "roll": 2,
		   "loft": 2,
		   "arc_height": 8.0,
		   "swing_difficulty": 8,
		   "curve": 0,
	   },
	   ClubType.IRON_5: {
		   "name": "5 Iron",
		   "distance": 15,     # R#4: == band_center (band 14-16)
		   "band_min": 14,
		   "band_max": 16,
		   "base_spread": 1,
		   "accuracy": 2,
		   "roll": 2,
		   "loft": 2,
		   "arc_height": 9.0,
		   "swing_difficulty": 7,
		   "curve": 0,
	   },
	   ClubType.IRON_6: {
		   "name": "6 Iron",
		   "distance": 13,     # R#4: == band_center
		   "band_min": 12,
		   "band_max": 14,
		   "base_spread": 1,
		   "accuracy": 1,
		   "roll": 2,
		   "loft": 2,
		   "arc_height": 9.0,
		   "swing_difficulty": 6,
		   "curve": 0,
	   },
	   ClubType.IRON_7: {
		   "name": "7 Iron",
		   "distance": 12,      # R#4: == band_center (band 11-13)
		   "band_min": 11,
		   "band_max": 13,
		   "base_spread": 1,
		   "accuracy": 1,
		   "roll": 1,
		   "loft": 3,
		   "arc_height": 10.0,
		   "swing_difficulty": 5,
		   "curve": 0,
	   },
	   ClubType.IRON_8: {
		   "name": "8 Iron",
		   "distance": 11,      # R#4: == band_center (band 10-12)
		   "band_min": 10,
		   "band_max": 12,
		   "base_spread": 1,
		   "accuracy": 1,
		   "roll": 1,
		   "loft": 3,
		   "arc_height": 10.0,
		   "swing_difficulty": 4,
		   "curve": 0,
	   },
	   ClubType.IRON_9: {
		   "name": "9 Iron",
		   "distance": 10,      # R#4: == band_center (band 9-11)
		   "band_min": 9,
		   "band_max": 11,
		   "base_spread": 1,
		   "accuracy": 1,
		   "roll": 1,
		   "loft": 4,
		   "arc_height": 11.0,
		   "swing_difficulty": 3,
		   "curve": 0,
	   },
	   ClubType.PITCHING_WEDGE: {
		   "name": "Pitching Wedge",
		   "distance": 8,      # R#4: == band_center (band 6-9)
		   "band_min": 6,
		   "band_max": 9,
		   "base_spread": 1,
		   "accuracy": 1,
		   "roll": 1,
		   "loft": 4,
		   "arc_height": 12.0,
		   "swing_difficulty": 2,
		   "curve": 0,
	   },
	   ClubType.SAND_WEDGE: {
		   "name": "Sand Wedge",
		   "distance": 5,      # R#4: == band_center (band 2-7, chips)
		   "band_min": 2,
		   "band_max": 7,
		   "base_spread": 1,
		   "accuracy": 1,
		   "roll": 0,
		   "loft": 5,          # Highest loft
		   "arc_height": 13.0,
		   "swing_difficulty": 2,
		   "curve": 0,
	   },
	   ClubType.PUTTER: {
		   "name": "Putter",
		   "distance": 2,      # R#4: == band_center
		   "band_min": 1,
		   "band_max": 4,
		   "base_spread": 1,
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

# --- The bag -----------------------------------------------------------------
# The clubs you own (one per type, each with a quality tier, see ClubItem) and
# the BAG_SIZE you picked for this hole in the Pro Shop after the flyover. The
# putter is always in the bag. An empty hole_bag (no pick made) allows every club.
const BAG_SIZE := 4
const STARTER_CLUBS := [ClubType.DRIVER, ClubType.WOOD_3, ClubType.IRON_3, ClubType.IRON_6, ClubType.IRON_8, ClubType.PITCHING_WEDGE]
var owned_clubs: Dictionary = {}    # ClubType -> ClubItem
var hole_bag: Array[int] = []       # ClubTypes picked for this hole (putter not listed)
var _bag_pending := false           # open the Pro Shop when the flyover ends


func _ensure_owned_clubs() -> void:
	"""A new run starts with a Common version of each starter club."""
	if not owned_clubs.is_empty():
		return
	for club in STARTER_CLUBS:
		owned_clubs[club] = ClubItem.create(club, CLUB_STATS[club].name, ClubItem.Tier.COMMON)


func get_club_stats(club, fallback: Dictionary = {}) -> Dictionary:
	"""A club's stats as you own it: the type's CLUB_STATS plus its tier's
	features (more distance, spin, forgiveness)."""
	if club == null or not CLUB_STATS.has(club):
		return fallback
	var item: ClubItem = owned_clubs.get(club)
	return item.apply(CLUB_STATS[club]) if item else CLUB_STATS[club]


func _in_bag(club: int) -> bool:
	return club == ClubType.PUTTER or hole_bag.is_empty() or hole_bag.has(club)

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
		# FEAT-003: a club change is a plan change -> rebuild the footprint.
		if turn_controller:
			rebuild_turn_plan()

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

# Shared soft-cel + dark-outline foliage material applied to the tree MultiMesh
# instances (per-instance foliage colour rides in MultiMesh custom data).
const TREE_FOLIAGE_MATERIAL := preload("res://scenes/tiles/tree_foliage.tres")
const TREE_SHADOW_SHADER := preload("res://scripts/tree_shadow.gdshader")

# Muted-green foliage variation palette (mirrors tree_spawner.gd::foliage_colors)
# so each placed tree reads as its own game piece.
const TREE_FOLIAGE_COLORS: Array[Color] = [
	Color(0.13, 0.33, 0.25, 1.0),
	Color(0.20, 0.45, 0.15, 1.0),
	Color(0.15, 0.35, 0.10, 1.0),
	Color(0.25, 0.50, 0.20, 1.0),
	Color(0.18, 0.40, 0.12, 1.0),
]

# Cached per-model {mesh, local} data and the shared shadow-disc mesh, built
# lazily on first use (see _get_tree_model_data / _get_tree_shadow_mesh).
var _tree_model_data: Array = []
var _tree_shadow_mesh: QuadMesh = null

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

var holelabel: Label = null
var thefloor: CSGBox3D = null
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
	5: {"min_yards": 520, "max_yards": 650, "min_width": 20, "max_width": 35}
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

# Turn-based loop (FEAT-003): TurnController drives the footprint + board resolution.
var turn_controller: TurnController = null
var hole_context: HoleContext = null
var shoot_button: Button = null  # Turn-based confirm button (lives in MainUI)
var pending_swing: Dictionary = {}
const FLYOVER_DELAY := 0.4  # seconds into the loading fade before the flyover moves  # a swing grade to use when Shoot fires with no hold (bot / tests)
var main_ui_ref: Control = null   # MainUI node (owns the 2D hand strip + Shoot button)
var current_aim_dir: int = 3  # Dominant hex aim direction (0..5); 3 = Down = toward flag
var turn_aim_target: Vector2i = Vector2i(-1, -1)  # Hex the player is aiming at this shot
var club_chosen_by_player: bool = false  # Player picked a club this shot -> don't auto-suggest

# Prototype shot hand: a fresh hand every shot from a deck that lasts the run
# (Strain cards picked up by overspending stay in it).
const SHOT_HAND_SIZE := 4
const MAX_PLANNED_CARDS := 3
var shot_deck: Array = []       # CardInstances, draw pile
var shot_discard: Array = []
var shot_hand: Array = []
var planned_cards: Dictionary = {}  # CardInstance -> CardModifier, played on this shot
# Money: what cards cost to play. Every hole starts with MONEY_PER_HOLE; coins
# add to it, fire takes from it, and the cards on the playmat spend it when
# the shot is taken.
const MONEY_PER_HOLE := 6
var money: int = MONEY_PER_HOLE


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
	_setup_hole_context()
	_create_highlight_mesh()
	_create_trajectory_mesh()
	_init_shot_system()
	_init_club_menu()
	_generate_course()
	_generate_grid()
	_apply_hole_definition_overrides()
	_log_hole_info()
	
	# Initialize run state with first hole info
	if run_state:
		run_state.start_hole(current_par, current_yardage)
	
	# Update UI
	_update_ui_hole_info()
	
	_start_new_shot()
	# FEAT-003: deal the club bag + modifier hand into the on-screen hand UI for
	# the opening hole (reset paths deal in their own flow after _start_new_shot).
	_deal_hand_for_current_hole()
	_play_opening_transition()


func _setup_hole_context() -> void:
	"""FEAT-003: own a HoleContext for this hole, seed its RNG, and route that
	RNG into the shot/wind seams so landing selection and wind are deterministic
	for a given seed. The procedural generation path is unchanged when there is
	no HoleDefinition (definition == null)."""
	hole_context = HoleContext.new()
	hole_context.rng = RandomNumberGenerator.new()

	var definition: HoleDefinition = hole_context.definition
	if definition != null:
		hole_context.seed = definition.seed
	else:
		# No authored definition yet: pick a fresh random seed each hole so the
		# procedural generator behaves exactly as before.
		hole_context.seed = randi()
	hole_context.rng.seed = hole_context.seed

	# Seam into the shot system (deterministic weighted landing selection).
	if shot_manager:
		shot_manager.rng = hole_context.rng
	if turn_controller:
		turn_controller.hole_context = hole_context


func _apply_hole_definition_overrides() -> void:
	"""FEAT-003: if a HoleDefinition is present and non-procedural, build the grid
	from its fixed dimensions + surface/elevation overrides and set tee/flag.
	Additive: when definition == null OR use_procedural is true, nothing changes
	and the existing procedural generation stands."""
	if hole_context == null:
		return
	var definition: HoleDefinition = hole_context.definition
	if definition == null or definition.use_procedural:
		return

	grid_width = definition.grid_width
	grid_height = definition.grid_height
	current_par = definition.par
	_init_grid()

	for key in definition.surface_overrides:
		var cell: Vector2i = key
		if cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height:
			grid[cell.x][cell.y] = int(definition.surface_overrides[key])
	for key in definition.elevation_overrides:
		var cell2: Vector2i = key
		if cell2.x >= 0 and cell2.x < grid_width and cell2.y >= 0 and cell2.y < grid_height:
			elevation[cell2.x][cell2.y] = float(definition.elevation_overrides[key])

	if definition.tee != Vector2i.ZERO:
		grid[definition.tee.x][definition.tee.y] = SurfaceType.TEE
	if definition.flag != Vector2i.ZERO:
		flag_position = definition.flag
		grid[definition.flag.x][definition.flag.y] = SurfaceType.FLAG


# --- FEAT-003: turn-based plan + Shoot button ---------------------------

func rebuild_turn_plan() -> void:
	"""Re-run the TurnController footprint build from the current plan
	(ball tile + played club + active modifier cards + aim) and refresh the
	on-board footprint display. Called on every plan change (club / modifier /
	aim)."""
	if turn_controller == null or golf_ball == null:
		return
	# The resolved shot's context is still being animated: rebuilding now would
	# reset its landing tile mid-flight (ball stops dead). Nothing is aimed
	# between shots either, so there is no plan to build.
	if (shot_manager and shot_manager.is_animating) or turn_aim_target.x < 0:
		return
	if putting_active:
		_update_shoot_button_state()
		return
	var ball_tile := world_to_grid(golf_ball.position)
	turn_controller.ball_tile = ball_tile
	turn_controller.played_club = current_club
	turn_controller.aim_target = turn_aim_target
	# Keep the ShotManager context's aim direction in sync so rebuild() preserves it.
	if shot_manager and shot_manager.current_context:
		shot_manager.current_context.aim_dir = current_aim_dir
	turn_controller.set_aim_dir(current_aim_dir)
	refresh_aoe_display()
	_update_shoot_button_state()


func _auto_aim_new_shot() -> void:
	"""Every shot starts with the caddie's pick (club + safe target within its
	reach), so Shoot is one tap away; the player re-aims by tapping a hex or
	picks another club."""
	if golf_ball == null or flag_position.x < 0 or hole_complete_triggered:
		return
	club_chosen_by_player = false
	var pick := _caddie_pick()
	turn_aim_target = pick.get("target", flag_position)
	target_locked = true
	locked_cell = turn_aim_target
	if pick.has("card"):
		_on_club_card_selected(pick.card)
	else:
		_suggest_club_for_target()
	club_chosen_by_player = false
	rebuild_turn_plan()


# Caddie risk per landing surface, in "hexes further from the flag" units.
const CADDIE_SURFACE_COST := {
	SurfaceType.FLAG: -5.0, SurfaceType.GREEN: -1.0, SurfaceType.FAIRWAY: 0.0,
	SurfaceType.TEE: 0.0, SurfaceType.ROUGH: 1.5, SurfaceType.DEEP_ROUGH: 3.0,
	SurfaceType.SAND: 4.0, SurfaceType.TREE: 8.0, SurfaceType.WATER: 1000.0,
}


func _caddie_pick() -> Dictionary:
	"""Best default shot: for each legal club in the hand, every hex inside its
	carry band, scored on the shot as it would really play (ShotPlan: wind
	drift, trees, landing ring incl. the lie) by distance left to the flag +
	landing risk. Ties go to the shorter club. Returns {card, target} or {}."""
	if card_system == null or card_system.club_deck_manager == null or golf_ball == null:
		return {}
	var ball := world_to_grid(golf_ball.position)
	var lie_spread := 0
	var lie_distance := 0
	if lie_system:
		var lie: Dictionary = lie_system.calculate_lie(self, ball)
		lie_spread = int(lie.get("spread_mod", 0))
		lie_distance = int(lie.get("distance_mod", 0))
	var wind_vec: Vector2 = wind_system.get_direction_vector() if wind_system else Vector2.ZERO
	var wind_strength: int = wind_system.strength if wind_system else 0
	var best := {}
	var best_score := INF
	for card in card_system.club_deck_manager.get_hand():
		if card == null or card.data == null:
			continue
		var club = ClubType.get(card.data.target_club)
		if club == null or not _is_club_legal_at(club, ball):
			continue
		var stats: Dictionary = get_club_stats(club, {})
		var lo: int = maxi(1, int(stats.get("band_min", 1)))
		var hi: int = int(stats.get("band_max", 0))
		for x in range(grid_width):
			for y in range(grid_height):
				var tile := Vector2i(x, y)
				var carry := hex_distance(ball, tile)
				if carry < lo or carry > hi or get_cell(x, y) < 0:
					continue
				# Cheap lower bound first: distance left from the aimed hex
				if hex_distance(tile, flag_position) - 6.0 + 0.01 * hi >= best_score:
					continue
				var plan := ShotPlan.build(self, ball, tile, {
					"power": hi + TurnController.lie_power(lie_distance), "wind_vec": wind_vec, "wind_strength": wind_strength,
					"spread": int(stats.get("base_spread", 1)), "ring_mod": lie_spread,
					"exact_usage": ShotPlan.PUTT_EXACT_USAGE if club == ClubType.PUTTER else ShotPlan.EXACT_USAGE})
				# Missed putts stay on the green, so a putt's ring carries no hazard risk
				var score := _caddie_landing_score(plan.end, 0 if club == ClubType.PUTTER else plan.ring) + 0.01 * hi
				if club == ClubType.PUTTER and plan.end == flag_position:
					score -= 3.0  # always putt at the hole
				if plan.blocked:
					score += 20.0
				score += 50.0 * plan.over  # the default shot never overspends (Strain)
				if score < best_score:
					best_score = score
					best = {"card": card, "target": tile}
	return best


func _caddie_landing_score(center: Vector2i, ring: int) -> float:
	"""Distance left to the flag + terrain risk of where the ball can land."""
	var surface := get_cell(center.x, center.y)
	if surface < 0:
		return 1000.0
	var score: float = hex_distance(center, flag_position) + float(CADDIE_SURFACE_COST.get(surface, 2.0))
	if course_features and course_features.kind_at(center) == "fire":
		score += 1000.0
	if ring > 0:
		score += ring
		for t in aoe_system.compute_circle_aoe(center, ring, self):
			if t == center:
				continue
			var s2 := get_cell(t.x, t.y)
			if s2 == SurfaceType.WATER or s2 < 0 or (course_features and course_features.kind_at(t) == "fire"):
				score += 2.0
			elif s2 == SurfaceType.TREE or s2 == SurfaceType.SAND:
				score += 0.5
	return score


func aim_reach() -> int:
	"""How far (in hexes) a tap may aim: the club's top distance less what the
	lie costs. A club you picked yourself sets it; otherwise the caddie will
	switch clubs to fit the tap, so it's the longest club you can hit from here."""
	if golf_ball == null:
		return 0
	var ball := world_to_grid(golf_ball.position)
	var lie_cost := 0
	if lie_system:
		lie_cost = TurnController.lie_power(int(lie_system.get_lie_data(get_cell(ball.x, ball.y)).get("distance_mod", 0)))
	var clubs: Array = []
	if club_chosen_by_player and current_club >= 0:
		clubs = [current_club]
	else:
		for c in CLUB_STATS:
			if c != ClubType.PUTTER and _is_club_legal_at(c, ball):
				clubs.append(c)
	var best := 0
	for c in clubs:
		best = maxi(best, int(get_club_stats(c).get("band_max", 0)))
	return best + lie_cost


var _reach_note_at := -10000


func _out_of_reach_feedback() -> void:
	"""A short note when a tap is past the club's reach (at most once a second)."""
	var now := Time.get_ticks_msec()
	if now - _reach_note_at < 1000:
		return
	_reach_note_at = now
	if shot_ui and shot_ui.has_method("show_callout"):
		var club: String = get_club_stats(current_club, {}).get("name", "Your clubs") if club_chosen_by_player else "Your clubs"
		shot_ui.show_callout("Out of reach for %s" % club)


func _suggest_club_for_target() -> void:
	"""Pick the legal club in the hand that best reaches turn_aim_target: the
	shortest club whose band covers the distance, else the closest band."""
	if card_system == null or card_system.club_deck_manager == null or golf_ball == null:
		return
	var ball_tile := world_to_grid(golf_ball.position)
	var dist := hex_distance(ball_tile, turn_aim_target)
	var best = null
	var best_cost := INF
	for card in card_system.club_deck_manager.get_hand():
		if card == null or card.data == null:
			continue
		var club_type = ClubType.get(card.data.target_club)
		if club_type == null or not _is_club_legal_at(club_type, ball_tile):
			continue
		var stats: Dictionary = get_club_stats(club_type, {})
		var lo: int = stats.get("band_min", 0)
		var hi: int = stats.get("band_max", 0)
		# Inside the band: prefer the shortest (most control). Outside: closest miss.
		var cost: float = float(hi) if (dist >= lo and dist <= hi) else 1000.0 + float(mini(absi(dist - lo), absi(dist - hi)))
		if cost < best_cost:
			best_cost = cost
			best = card
	if best != null:
		_on_club_card_selected(best)
		club_chosen_by_player = false


func _show_turn_footprint() -> void:
	"""Draw the real shot plan: the aim marker, the weighted landing spread
	(brighter = more likely), the most-likely center and the flight arc."""
	_hide_all_aoe_highlights()
	modifier_trajectory_mesh.visible = false
	curved_trajectory_mesh.visible = false
	if putting_active:
		# The green board draws the putt; course-hex markers would sit over it
		highlight_mesh.visible = false
		target_highlight_mesh.visible = false
		return
	if golf_ball == null or turn_aim_target.x < 0 or hole_complete_triggered:
		highlight_mesh.visible = false
		target_highlight_mesh.visible = false
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false
		return
	
	# Where the player aimed
	highlight_mesh.position = _hex_marker_position(turn_aim_target)
	highlight_mesh.rotation.y = PI / 6.0
	highlight_mesh.visible = true
	
	var ctx: ShotContext = shot_manager.current_context if shot_manager else null
	if current_club < 0 or ctx == null or ctx.aoe_tiles.is_empty():
		target_highlight_mesh.visible = false
		trajectory_mesh.visible = false
		trajectory_shadow_mesh.visible = false
		return
	
	# Landing spread, alpha scaled by weight
	var center: Vector2i = ctx.aim_tile
	var max_w := 0.0
	for t in ctx.aoe_tiles:
		max_w = maxf(max_w, float(ctx.aoe_weights.get(t, 0.0)))
	for t in ctx.aoe_tiles:
		if t == center:
			continue
		var hl := _get_or_create_aoe_highlight(t, _get_hex_distance(center, t))
		hl.position = _hex_marker_position(t)
		hl.rotation.y = PI / 6.0
		var w := float(ctx.aoe_weights.get(t, 0.0)) / max_w if max_w > 0.0 else 0.5
		var mat := hl.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = lerpf(0.12, 0.55, w)
		hl.visible = true
	
	# Most-likely landing hex + flight arc to it
	target_highlight_mesh.position = _hex_marker_position(center)
	target_highlight_mesh.rotation.y = PI / 6.0
	target_highlight_mesh.visible = true
	var ball_tile := world_to_grid(golf_ball.position)
	var carry_yards := int(hex_distance(ball_tile, center) * YARDS_PER_CELL)
	var plan_blocked: bool = ctx.get_metadata("shot_plan", {}).get("blocked", false)
	if target_highlight_mesh.has_method("set_distance_and_club"):
		var caption: String = "Into the trees" if plan_blocked else get_club_stats(current_club, {}).get("name", "---")
		if not plan_blocked:
			caption += {"high": " · High", "low": " · Low"}.get(_flight_kind(ctx), "")
		target_highlight_mesh.set_distance_and_club(carry_yards, caption)
	locked_target_pos = get_tile_surface_position(center)
	var plan: Dictionary = ctx.get_metadata("shot_plan", {})
	if plan.is_empty():
		_draw_trajectory_arc(trajectory_mesh, golf_ball.position, locked_target_pos, Color(1.0, 1.0, 1.0, 0.6))
	else:
		# Over budget = orange, blocked by trees = red, high (Loft) = sky blue
		# and swelling at its peak, low = sand and thin, otherwise white. Seen
		# from behind the ball an arc's height barely shows, so the flight
		# reads by colour and width.
		var color := Color(1.0, 1.0, 1.0, 0.75)
		var flight := _flight_kind(ctx)
		var swell := 1.0
		if flight == "high":
			color = Color(0.55, 0.85, 1.0, 0.9)
			swell = 2.6
		elif flight == "low":
			color = Color(0.95, 0.82, 0.55, 0.9)
			swell = 0.7
		if plan.blocked:
			color = Color(1.0, 0.35, 0.3, 0.85)
		elif int(plan.over) > 0:
			color = Color(1.0, 0.65, 0.2, 0.85)
		_draw_path_ribbon(trajectory_mesh, plan.points, golf_ball.position.y, locked_target_pos.y, color, 0.0 if ctx.get_metadata("all_ground", false) else _flight_arc(trajectory_height, ctx), swell)
	trajectory_mesh.visible = true
	# The straight ground shadow only matches an unshaped arc
	trajectory_shadow_mesh.visible = plan.is_empty()
	if plan.is_empty():
		_draw_trajectory_shadow(golf_ball.position, locked_target_pos, false)
	if shot_ui:
		shot_ui.update_target_info(get_cell(center.x, center.y), carry_yards)


const LOFT_ARC := 2.0  # Loft cards: the flight peaks twice as high (it clears the trees)
const LOW_ARC := 0.45  # Knockdown / wind-proof cards: a low, boring flight


func _flight_kind(ctx) -> String:
	"""'high' (Loft), 'low' (Knockdown and other wind-proof cards) or ''."""
	if ctx == null:
		return ""
	if ctx.get_metadata("loft", false):
		return "high"
	if ctx.get_metadata("ignore_wind", false):
		return "low"
	return ""


func _flight_arc(base: float, ctx) -> float:
	"""How high the flight peaks once the played cards have their say; used by
	the preview and the ball's flight alike."""
	match _flight_kind(ctx):
		"high":
			return base * LOFT_ARC
		"low":
			return base * LOW_ARC
	return base


func _draw_path_ribbon(mesh: MeshInstance3D, points: Array, start_y: float, end_y: float, color: Color, arc_height: float, swell: float = 1.0) -> void:
	"""Ribbon along a ShotPlan's sampled flight (world x,z), lifted into an arc.
	swell: how much wider (or thinner, < 1) it gets toward the peak."""
	var im: ImmediateMesh = mesh.mesh
	im.clear_surfaces()
	if points.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var ribbon_width := 0.12
	var last := points.size() - 1
	for i in range(points.size()):
		var t := float(i) / float(last)
		var alpha := clampf(minf(t, 1.0 - t) / 0.12, 0.0, 1.0)
		im.surface_set_color(Color(color.r, color.g, color.b, alpha * color.a))
		var p: Vector2 = points[i]
		var nxt: Vector2 = points[mini(i + 1, last)] if i < last else p + (p - points[i - 1])
		var dir := (nxt - p).normalized()
		var side := Vector3(-dir.y, 0.0, dir.x) * ribbon_width * (1.0 + (swell - 1.0) * sin(t * PI))
		var center := Vector3(p.x, lerpf(start_y, end_y, t) + sin(t * PI) * arc_height + 0.08, p.y)
		im.surface_add_vertex(center - side)
		im.surface_add_vertex(center + side)
	im.surface_end()


func _hex_marker_position(cell: Vector2i) -> Vector3:
	var hex_height = TILE_SIZE * sqrt(3.0)
	return Vector3(cell.x * TILE_SIZE * 1.5, get_elevation(cell.x, cell.y) + TILE_SURFACE_OFFSET, cell.y * hex_height + (cell.x % 2) * (hex_height / 2.0))


func set_turn_aim_dir(dir: int) -> void:
	"""Map a 6-direction aim input to the TurnController and rebuild."""
	current_aim_dir = ((dir % 6) + 6) % 6
	rebuild_turn_plan()


func _on_shoot_pressed() -> void:
	"""Shoot button handler: confirm the planned shot through TurnController."""
	if putting_active:
		_execute_putt()
		return
	if turn_controller == null:
		return
	if not _is_shoot_legal():
		return
	# The SHOOT meter's grade bends this shot (pure / thin / slice / hook)
	var swing: Dictionary = shoot_button.take_swing() if shoot_button is SwingButton else {}
	if swing.is_empty() and not pending_swing.is_empty():
		swing = pending_swing
		if shoot_button is SwingButton:
			shoot_button.show_result(swing.kind)
	pending_swing = {}
	turn_controller.swing = swing
	# Make sure the ShotManager has a live shot + the latest footprint before
	# confirming (execute_shot -> confirm_shot consumes the built footprint).
	if shot_manager and not shot_manager.is_shot_in_progress and golf_ball:
		var ball_tile := world_to_grid(golf_ball.position)
		turn_controller.ball_tile = ball_tile
		turn_controller.played_club = current_club
		turn_controller.begin_turn()
		turn_controller.set_aim_dir(current_aim_dir)
	elif not swing.is_empty():
		turn_controller.rebuild()
	var plan: Dictionary = shot_manager.current_context.get_metadata("shot_plan", {}) if shot_manager else {}
	if int(plan.get("over", 0)) > 0:
		_add_strain_cards(int(plan.over))
	money -= _planned_cost()  # the playmat's cards are paid for as the shot is struck
	turn_controller.execute_shot()


func _is_shoot_legal() -> bool:
	"""Shoot is legal once a club legal for the current lie is selected and an aim
	direction is set. Putter is only legal on GREEN."""
	if current_club < 0 or golf_ball == null:
		return false
	return _is_club_legal_at(current_club, world_to_grid(golf_ball.position))


func _shoot_block_reason() -> String:
	"""Why Shoot is disabled, in words for the button ("" when it can fire)."""
	if golf_ball == null:
		return "No ball"
	if current_club < 0:
		return "Pick a club"
	var ball := world_to_grid(golf_ball.position)
	if not _is_club_legal_at(current_club, ball):
		if get_cell(ball.x, ball.y) == SurfaceType.GREEN or current_club == ClubType.PUTTER:
			return "Putter only\non the green"
		return "%s can't be\nhit from %s" % [get_club_stats(current_club, {}).get("name", "Club"), _surface_to_lie_name(get_cell(ball.x, ball.y)).capitalize().replace("_", " ")]
	return ""


func _legal_club_cards() -> Array:
	"""The clubs in the bag that can be hit from the ball's lie."""
	var legal: Array = []
	if card_system == null or card_system.club_deck_manager == null or golf_ball == null:
		return legal
	var ball := world_to_grid(golf_ball.position)
	for card in card_system.club_deck_manager.get_hand():
		var club = ClubType.get(card.data.target_club) if card and card.data else null
		if club != null and _is_club_legal_at(club, ball):
			legal.append(card)
	return legal


func _club_subtitles(cards: Array) -> Dictionary:
	"""Carry range per club card, e.g. "220-260 yd"."""
	var subs := {}
	for card in cards:
		var stats: Dictionary = get_club_stats(ClubType.get(card.data.target_club), {})
		if not stats.is_empty():
			subs[card] = "%d-%d yd" % [int(stats.get("band_min", 0) * YARDS_PER_CELL), int(stats.get("band_max", 0) * YARDS_PER_CELL)]
	return subs


func _is_club_legal_at(club: int, ball_tile: Vector2i) -> bool:
	"""A club can be hit when it's in this hole's bag and the lie allows it. If
	the lie allows none of the bag's clubs (say, sand with no wedge picked),
	the shortest club in the bag can punch out instead, so you're never stuck."""
	if not _in_bag(club):
		return false
	if _lie_allows_club(club, ball_tile):
		return true
	if hole_bag.is_empty() or get_cell(ball_tile.x, ball_tile.y) == SurfaceType.GREEN:
		return false
	for c in hole_bag:
		if _lie_allows_club(c, ball_tile):
			return false
	var shortest: int = hole_bag[0]
	for c in hole_bag:
		if int(CLUB_STATS[c].band_max) < int(CLUB_STATS[shortest].band_max):
			shortest = c
	return club == shortest


func _lie_allows_club(club: int, ball_tile: Vector2i) -> bool:
	"""Lie legality for a club: Putter only (and always) on GREEN, otherwise the
	lie's allowed_clubs."""
	var ball_surface := get_cell(ball_tile.x, ball_tile.y)
	if club == ClubType.PUTTER and ball_surface != SurfaceType.GREEN:
		return false
	if ball_surface == SurfaceType.GREEN and club != ClubType.PUTTER:
		return false
	var allowed := _allowed_clubs_for_tile(ball_tile)
	if not allowed.is_empty() and not allowed.has(club):
		return false
	return true


func _allowed_clubs_for_tile(tile: Vector2i) -> Array:
	"""Resolve the lie's allowed_clubs (ClubType ints) for a tile via LieSystem."""
	var result: Array = []
	if lie_system == null:
		return result
	var lie_info: Dictionary = lie_system.calculate_lie(self, tile)
	var allowed = lie_info.get("allowed_clubs", [])
	for c in allowed:
		# LieSystem stores allowed_clubs as ClubType NAME strings (e.g. "DRIVER").
		# Normalize to ClubType ints so _is_shoot_legal() can compare against
		# current_club (an int). Pass through ints unchanged for safety.
		if c is String:
			var type = ClubType.get(c)
			if type != null:
				result.append(int(type))
		else:
			result.append(int(c))
	return result


func _update_shoot_button_state() -> void:
	"""Enable/disable the Shoot button based on shot legality, and refresh the
	SHOOT box face, its swing meter and the THIS SHOT line."""
	if shoot_button == null:
		return
	var stroke_text := "STROKE %d" % ((run_state.strokes_this_hole if run_state else 0) + 1)
	var swing_box := shoot_button as SwingButton
	if putting_active:
		shoot_button.disabled = false
		shoot_button.text = "Putt"
		if swing_box:
			swing_box.set_face("PUTT", stroke_text, false)
		_set_this_shot(_this_shot_text({}))
		return
	shoot_button.disabled = not _is_shoot_legal()
	var plan: Dictionary = shot_manager.current_context.get_metadata("shot_plan", {}) if shot_manager and shot_manager.current_context else {}
	if shoot_button.disabled:
		shoot_button.text = _shoot_block_reason()
	elif plan.is_empty() or current_club < 0:
		shoot_button.text = "Shoot"
	elif int(plan.over) > 0:
		shoot_button.text = "Shoot  %d/%d\n+%d Strain" % [plan.cost, plan.power, plan.over]
	else:
		shoot_button.text = "Shoot  %d/%d" % [plan.cost, plan.power]
	if swing_box:
		if shoot_button.disabled:
			swing_box.set_face(_shoot_block_reason(), "", false)
		else:
			var sub := stroke_text
			if not plan.is_empty() and int(plan.over) > 0:
				sub += "  ·  +%d STRAIN" % int(plan.over)
			swing_box.set_face("SHOOT", sub, true)
			var diff := _swing_difficulty(plan)
			swing_box.set_difficulty(diff.x, diff.y)
	_set_this_shot(_this_shot_text(plan))


func _swing_difficulty(plan: Dictionary) -> Vector2:
	"""(green half-width, meter period) for the SHOOT meter: the target shrinks
	and the box speeds up for bad lies, long clubs, stacked cards, overswinging
	and wind."""
	var green := 0.34
	if golf_ball:
		var ball := world_to_grid(golf_ball.position)
		green -= {SurfaceType.ROUGH: 0.05, SurfaceType.DEEP_ROUGH: 0.1, SurfaceType.SAND: 0.1, SurfaceType.TREE: 0.12}.get(get_cell(ball.x, ball.y), 0.0)
	var band_max: int = get_club_stats(current_club, {}).get("band_max", 0)
	if band_max >= 20:
		green -= 0.06
	elif band_max >= 15:
		green -= 0.03
	green -= 0.025 * planned_cards.size()
	if not plan.is_empty():
		green -= 0.06 * int(plan.get("over", 0))
	var ignore_wind := false
	for card in planned_cards:
		for e in card.data.effects:
			if e is EffectShotShape and e.ignore_wind:
				ignore_wind = true
	if wind_system and not ignore_wind:
		green -= 0.02 * wind_system.strength
	green = clampf(green, 0.1, 0.4)
	var period := lerpf(1.4, 2.2, inverse_lerp(0.1, 0.4, green))
	return Vector2(green, period)


func _this_shot_text(plan: Dictionary) -> String:
	"""THIS SHOT, pencilled: "3 Iron + Fade + Stop -> 150-170"."""
	var parts: Array[String] = []
	parts.append(get_club_stats(current_club, {}).get("name", "—"))
	var cards: Array = putt_cards.keys() if putting_active else planned_cards.keys()
	for card in cards:
		parts.append(card.get_display_name())
	var text := " + ".join(parts)
	if not putting_active and not plan.is_empty():
		var lo := maxi(0, int(plan.carry) - int(plan.ring))
		var hi := int(plan.carry) + int(plan.ring)
		text += "  →  %d–%d" % [int(lo * YARDS_PER_CELL), int(hi * YARDS_PER_CELL)]
	elif putting_active and green_board and golf_ball:
		var ball := _ball_small()
		text += "  →  %d of %d hexes · cup %d" % [GreenBoard.distance(ball, putt_target),
			int(_putt_opts().reach), GreenBoard.distance(ball, green_board.cup)]
	return text


func _set_this_shot(text: String) -> void:
	if main_ui_ref and main_ui_ref.has_method("set_this_shot"):
		main_ui_ref.set_this_shot(text)
	_refresh_tray()


func _refresh_tray() -> void:
	"""Scorecard (pars / scores so far, the hole in play), hand and deck counts,
	points and the run's score line."""
	if main_ui_ref == null or not main_ui_ref.has_method("update_scorecard") or run_state == null:
		return
	var pars := {}
	var scores := {}
	for h in run_state.hole_history:
		pars[h.hole] = h.par
		scores[h.hole] = h.strokes
	if not pars.has(run_state.current_hole):
		pars[run_state.current_hole] = current_par
	main_ui_ref.update_scorecard(run_state.current_hole, pars, scores, run_state.strokes_this_hole)
	var hand: Array = putt_hand if putting_active else shot_hand
	var left: int = putt_deck.size() if putting_active else shot_deck.size()
	var total: int = (putt_deck.size() + putt_discard.size() + putt_hand.size()) if putting_active else (shot_deck.size() + shot_discard.size() + shot_hand.size())
	var points: int = currency_manager.get_balance() if currency_manager else 0
	var run_text := "RUN %s  ·  BLOWOUT %s" % [run_state.format_vs_par(run_state.get_live_vs_par()), run_state.format_vs_par(run_state.blowout_limit)]
	main_ui_ref.set_tray_info(hand.size(), left, total, points, run_text)
	if main_ui_ref.has_method("set_money"):
		main_ui_ref.set_money(money, 0 if putting_active else _planned_cost())


# --- FEAT-003: deal the hand into the live hand UI at hole start ----------

func _deal_hand_for_current_hole() -> void:
	"""Deal a fresh club bag + modifier hand for this hole and bind it to the
	on-screen hand strip. Called once at every hole start (initial load + each
	regenerate/Generate path) AFTER the ball is placed, so Shoot legality can be
	evaluated. Reuses the existing CardSystemManager.deal_hand_for_hole() (clubs
	are a reusable bag; modifiers are drawn into the modifier deck, seeded by the
	hole RNG for determinism)."""
	if card_system == null:
		return
	if card_system.has_method("deal_hand_for_hole"):
		var rng: RandomNumberGenerator = hole_context.rng if hole_context else null
		card_system.deal_hand_for_hole(null, rng)

	# Bind the dealt cards to the 2D hand strip.
	if main_ui_ref and main_ui_ref.has_method("set_hand"):
		var club_hand: Array = []
		var modifier_hand: Array = []
		if card_system.club_deck_manager:
			club_hand = card_system.club_deck_manager.get_hand()
		if card_system.deck_manager:
			modifier_hand = shot_hand
		main_ui_ref.set_hand(club_hand, modifier_hand)

	# Fresh shot deck for the hole, then deal + aim the opening shot.
	_reset_shot_deck_for_hole()
	_begin_shot()
	_update_shoot_button_state()
	_play_hole_flyover()


func _on_club_card_selected(card_instance) -> void:
	"""Hand strip: player picked a club card. Set the current club (this rebuilds
	the turn plan + refreshes the Shoot button via set_club_by_name) and reflect
	the selection in the strip."""
	if card_instance == null or card_instance.data == null:
		return
	club_chosen_by_player = true
	set_club_by_name(card_instance.data.target_club)
	_update_shoot_button_state()
	if main_ui_ref and main_ui_ref.has_method("set_selected_club"):
		main_ui_ref.set_selected_club(card_instance)


func _on_modifier_card_selected(card_instance) -> void:
	"""Hand strip: toggle a shot card on/off for this shot (up to
	MAX_PLANNED_CARDS). Strain cards can't be played."""
	if card_instance == null or card_instance.data == null:
		return
	if putting_active:
		if putt_hand.has(card_instance):
			_toggle_putt_card(card_instance)
		return
	var utility := _utility_action(card_instance.data)
	if utility != "" and shot_hand.has(card_instance):
		if _card_cost(card_instance) > money - _planned_cost():
			if main_ui_ref and main_ui_ref.has_method("flash_money"):
				main_ui_ref.flash_money()
			return
		_play_utility_card(card_instance, utility)
		return
	if planned_cards.has(card_instance):
		if modifier_manager:
			modifier_manager.remove_modifier(planned_cards[card_instance])
		planned_cards.erase(card_instance)
	elif _card_cost(card_instance) > money - _planned_cost():
		if main_ui_ref and main_ui_ref.has_method("flash_money"):
			main_ui_ref.flash_money()
		return
	elif card_instance.data.card_type != CardData.CardType.NEGATIVE and planned_cards.size() < MAX_PLANNED_CARDS:
		var mod := CardModifier.new(card_instance)
		if modifier_manager:
			modifier_manager.add_modifier(mod)
		planned_cards[card_instance] = mod
	if main_ui_ref and main_ui_ref.has_method("set_card_pressed"):
		main_ui_ref.set_card_pressed(card_instance, planned_cards.has(card_instance))
	rebuild_turn_plan()


static func _card_cost(card_instance) -> int:
	return ShotCardFace.cost_for(card_instance.data, card_instance.upgrade_level)


func _planned_cost() -> int:
	"""Money the cards on the playmat will spend when the shot is taken."""
	var total := 0
	for card in planned_cards:
		total += _card_cost(card)
	return total


func _change_money(amount: int, reason: String = "") -> void:
	"""Coins add, fire takes (never below 0); shows a callout when reason is set."""
	money = maxi(0, money + amount)
	if reason != "" and shot_ui and shot_ui.has_method("show_callout"):
		shot_ui.show_callout("%s  %+d Money" % [reason, amount])
	_refresh_tray()


func _utility_action(data: CardData) -> String:
	for e in data.effects:
		if e is EffectCourseUtility:
			return e.action
	return ""


func _play_utility_card(card_instance, action: String) -> void:
	"""Utility cards act at once on the course, then go to the discard."""
	if course_features:
		match action:
			"extinguish":
				for cell in course_features.tiles.keys():
					if course_features.tiles[cell].kind == "fire":
						course_features.tiles[cell] = {"kind": "scorched", "dir": 0, "age": 0}
			"groundskeeper":
				course_features.place(self, _feature_rng)
			"shutoff":
				for cell in course_features.tiles.keys():
					if course_features.tiles[cell].kind in ["tunnel", "sprinkler"]:
						course_features.tiles.erase(cell)
		if feature_overlay:
			feature_overlay.show_features(course_features, self)
	money -= _card_cost(card_instance)
	shot_hand.erase(card_instance)
	shot_discard.append(card_instance)
	if main_ui_ref and main_ui_ref.has_method("set_hand"):
		var clubs := _legal_club_cards()
		main_ui_ref.set_hand(clubs, shot_hand, _club_subtitles(clubs))
		for card in planned_cards:
			main_ui_ref.set_card_pressed(card, true)
	rebuild_turn_plan()
	_refresh_hole_label()


func _clear_planned_cards() -> void:
	"""Take this shot's played cards back out of the modifier manager."""
	for card in planned_cards:
		if modifier_manager:
			modifier_manager.remove_modifier(planned_cards[card])
	planned_cards.clear()


func _begin_shot() -> void:
	"""Every shot: a fresh hand, then aim at the flag with a suggested club."""
	_spread_fire_for_turn()
	_deal_shot_hand()
	if turn_controller:
		turn_controller.swing = {}
	putting_active = false
	if green_overlay:
		green_overlay.hide_target()
	if _ball_on_green():
		_begin_putt()
	else:
		_auto_aim_new_shot()
	_update_green_view()
	_frame_camera_for_shot()
	_refresh_hole_label()


func _frame_camera_for_shot() -> void:
	"""Glide the camera to the ball, facing the shot (the green view frames
	putts itself)."""
	if hole_viewer == null or not hole_viewer.has_method("frame_shot") or golf_ball == null or _ball_on_green():
		return
	var aim := turn_aim_target if turn_aim_target.x >= 0 else flag_position
	hole_viewer.frame_shot(golf_ball.global_position, to_global(get_tile_world_position(aim)))


func _play_hole_flyover() -> void:
	"""New hole: fly the hole tee to green and back, ending framed for the
	opening shot. Starts while the loading screen fades out."""
	if hole_viewer == null or not hole_viewer.has_method("play_flyover") or golf_ball == null or flag_position.x < 0:
		return
	var tee: Vector3 = golf_ball.global_position
	var green := to_global(get_tile_world_position(flag_position))
	var aim := turn_aim_target if turn_aim_target.x >= 0 else flag_position
	# When the flyover ends, the Pro Shop opens to pick this hole's bag
	_bag_pending = true
	if hole_viewer.has_signal("flyover_finished") and not hole_viewer.flyover_finished.is_connected(_on_flyover_finished):
		hole_viewer.flyover_finished.connect(_on_flyover_finished)
	hole_viewer.play_flyover(tee, green, hole_viewer.shot_pose(tee, to_global(get_tile_world_position(aim))), FLYOVER_DELAY)


func _on_flyover_finished() -> void:
	# Not once the hole is under way (a shot taken during the flyover)
	if _bag_pending and (run_state == null or run_state.strokes_this_hole == 0):
		_open_shop()
	_bag_pending = false


func _reset_shot_deck_for_hole() -> void:
	"""Hole start: every card (Strain included) back into one shuffled deck.
	The very first call builds the deck from the starter definition."""
	_clear_planned_cards()
	if shot_deck.is_empty() and shot_discard.is_empty() and shot_hand.is_empty() and starter_deck:
		for data in starter_deck.get_all_cards():
			shot_deck.append(CardInstance.create_from_data(data))
	shot_deck.append_array(shot_discard)
	shot_deck.append_array(shot_hand)
	shot_discard.clear()
	shot_hand.clear()
	_shuffle_cards(shot_deck)


func _deal_shot_hand() -> void:
	"""Discard the last hand and draw SHOT_HAND_SIZE fresh cards."""
	_clear_planned_cards()
	if shot_deck.is_empty() and shot_discard.is_empty() and shot_hand.is_empty():
		_reset_shot_deck_for_hole()
	shot_discard.append_array(shot_hand)
	shot_hand.clear()
	# Shot cards don't apply to putts: the green gets its own game, so deal nothing
	var ball_tile := world_to_grid(golf_ball.position) if golf_ball else Vector2i(-1, -1)
	var putting := get_cell(ball_tile.x, ball_tile.y) == SurfaceType.GREEN
	for i in range(0 if putting else SHOT_HAND_SIZE):
		if shot_deck.is_empty():
			if shot_discard.is_empty():
				break
			shot_deck = shot_discard
			shot_discard = []
			_shuffle_cards(shot_deck)
		shot_hand.append(shot_deck.pop_back())
	if main_ui_ref and main_ui_ref.has_method("set_hand"):
		var clubs := _legal_club_cards()
		main_ui_ref.set_hand(clubs, shot_hand, _club_subtitles(clubs))


func _shuffle_cards(cards: Array) -> void:
	"""Fisher-Yates on the hole's seeded RNG (global RNG as fallback)."""
	var rng: RandomNumberGenerator = hole_context.rng if hole_context else null
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i) if rng else randi_range(0, i)
		var tmp = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


func _add_strain_cards(count: int) -> void:
	"""Overspending power adds Strain to the deck (it shows up in later hands)."""
	var data = CardLibrary.instance.get_card("strain") if CardLibrary.instance else null
	if data == null:
		return
	for i in range(count):
		shot_discard.append(CardInstance.create_from_data(data))


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
	trajectory_height = get_club_stats(current_club, CLUB_STATS[ClubType.IRON_7]).arc_height
	# _update_club_button_visuals() # Deprecated
	_hide_range_preview()
	_update_dim_overlays()  # Update dim overlays for new club range


func _on_club_button_hover(club_type: ClubType) -> void:
	"""Show range preview when hovering over a club button"""
	is_previewing_range = true
	var max_dist = get_club_stats(club_type, CLUB_STATS[ClubType.IRON_7]).distance
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
	var base_distance = get_club_stats(current_club, CLUB_STATS[ClubType.IRON_7]).distance
	
	# Apply lie distance modifier if we have a shot context with lie info
	if shot_manager and shot_manager.current_context:
		var distance_mod = shot_manager.current_context.distance_mod
		return maxi(1, base_distance + distance_mod)
	
	return base_distance


func get_current_club_base_distance() -> int:
	"""Get unmodified max distance in tiles for current club"""
	return get_club_stats(current_club, CLUB_STATS[ClubType.IRON_7]).distance


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
		
		var stats = get_club_stats(club_type)
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
	return get_club_stats(current_club, CLUB_STATS[ClubType.IRON_7]).loft


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
	
	var club_stats = get_club_stats(club_type, CLUB_STATS[ClubType.IRON_7])
	
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
	trajectory_height = get_club_stats(current_club, CLUB_STATS[ClubType.IRON_7]).arc_height
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


const SHOW_OUT_OF_REACH_DIM := false  # the dark overlay past the club's reach (off: hidden, kept)


func _update_dim_overlays() -> void:
	"""Create or update dim overlays for unavailable tiles (only forward, out of range).
	   Shows overlays for tiles beyond the max club range (Driver distance)."""
	# Clear existing overlays
	_clear_dim_overlays()
	
	if golf_ball == null or not SHOW_OUT_OF_REACH_DIM:
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
			trajectory_height = get_club_stats(current_club, CLUB_STATS[ClubType.IRON_7]).arc_height
	
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
	if turn_aim_target.x >= 0:
		_show_turn_footprint()
		return
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
	if putting_active:
		return false  # the green view aims putts through putt_aim_ray
	# Turn loop: aim at any hex on the board; the club band caps the carry.
	if turn_controller and golf_ball:
		if shot_manager and shot_manager.is_animating:
			return false
		if hole_complete_triggered or (run_state and run_state.is_blown_out):
			return false
		if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
			return false
		if cell == world_to_grid(golf_ball.position):
			return false
		if hex_distance(world_to_grid(golf_ball.position), cell) > aim_reach():
			_out_of_reach_feedback()
			return false  # past what the club can reach
		turn_aim_target = cell
		locked_cell = cell
		target_locked = true
		if not club_chosen_by_player:
			_suggest_club_for_target()
		rebuild_turn_plan()
		return true
	
	# Legacy path (no turn controller): unified validation
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
	# Turn loop: the aimed footprint stays on screen while hovering
	if turn_aim_target.x >= 0:
		hovered_cell = cell
		return
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
		# The opening hole was dealt before the viewer registered: fly it now
		if run_state and run_state.strokes_this_hole == 0 and golf_ball:
			_play_hole_flyover.call_deferred()


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
	_refresh_hole_label(debug_text)


# --- Shot System Integration -------------------------------------------

func _init_shot_system() -> void:
	"""Initialize shot system components and connect signals"""
	# Create Run State Manager
	run_state = RunStateManager.new()
	run_state.name = "RunStateManager"
	add_child(run_state)
	run_state.start_new_run(9)  # 9-hole round by default
	run_state.vs_par_changed.connect(func(_v): _refresh_hole_label())
	
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
	
	# Points: trick shots score through the ShotManager scoring phase
	trick_detector = TrickShotDetector.new()
	trick_detector.hole = self
	shot_manager.trick_detector = trick_detector
	run_state.hole_started.connect(func(_h, _p, _y): _on_run_hole_started())
	if currency_manager:
		currency_manager.currency_changed.connect(func(_a, _d): _refresh_hole_label())
	
	# Initialize card system
	_init_card_system()
	
	# Initialize putting system
	_init_putting_system()
	
	# Look for ShotUI in the scene tree
	_find_and_setup_ui()


func _init_card_system() -> void:
	"""Initialize the card/deck system"""
	# Defensive fallback: allow scenes to omit/override exported decks without breaking the UI.
	# (If a scene sets these exports to null, the hand would appear empty.)
	if starter_deck == null:
		starter_deck = load("res://resources/decks/starter_deck.tres") as DeckDefinition
	if club_deck == null:
		club_deck = load("res://resources/decks/swing_deck.tres") as DeckDefinition

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
	
	# FEAT-003 (R4, Finding 7): the SwingHand3D SubViewport card-slot chain is
	# retired. The turn-based loop plays cards through the 2D hand strip + the
	# Shoot button (TurnController), so the 3D swing-hand wiring is removed.
	
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

	# --- FEAT-003: Turn-based loop controller ---
	# TurnController builds the weighted landing footprint from the current plan
	# (club + modifiers + aim) and reconstructs the board-resolution roll line
	# after the ball lands. It is wired alongside the legacy flow (add-before-
	# remove): both the Shoot button and the legacy confirm path can drive a shot
	# until the real-time pieces are retired.
	turn_controller = TurnController.new()
	turn_controller.name = "TurnController"
	turn_controller.shot_manager = shot_manager
	turn_controller.card_system = card_system
	turn_controller.aoe_system = aoe_system
	turn_controller.wind_system = wind_system
	turn_controller.lie_system = lie_system
	turn_controller.hole_context = hole_context
	turn_controller.hex_grid = self
	add_child(turn_controller)

	# Board resolution runs on the landing_resolved callback (R#2 roll/tree/water
	# walk + green slope nudge), mutating landing_tile in place before scoring.
	if shot_manager and not shot_manager.landing_resolved.is_connected(turn_controller.apply_board_resolution):
		shot_manager.landing_resolved.connect(turn_controller.apply_board_resolution)


func _init_putting_system() -> void:
	"""FEAT-003 (R2): the real-time putting mini-game is retired. GREEN is a
	normal lie (lie table restricts to PUTTER) resolved through the play-card-
	then-Shoot loop, so no PuttingSystem is instantiated. Left as a no-op to keep
	the init call site stable; putting_system stays null."""
	pass


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
		main_ui_ref = main_ui
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

		# FEAT-003: wire the turn-based Shoot button to TurnController.execute_shot.
		if main_ui.get("shoot_button") and main_ui.shoot_button:
			shoot_button = main_ui.shoot_button
			if turn_controller and not shoot_button.pressed.is_connected(_on_shoot_pressed):
				shoot_button.pressed.connect(_on_shoot_pressed)
			_update_shoot_button_state()

		# FEAT-003: wire the 2D hand strip selection signals. Selecting a club
		# sets the current club (which rebuilds the plan + refreshes Shoot);
		# selecting a modifier applies it through the card system.
		if main_ui.has_signal("club_card_selected") and not main_ui.club_card_selected.is_connected(_on_club_card_selected):
			main_ui.club_card_selected.connect(_on_club_card_selected)
		if main_ui.has_signal("modifier_card_selected") and not main_ui.modifier_card_selected.is_connected(_on_modifier_card_selected):
			main_ui.modifier_card_selected.connect(_on_modifier_card_selected)

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
	# A ball in flight finishes its own shot and starts the next one
	if shot_manager and shot_manager.is_animating:
		return
	# Run over: the last stroke pushed the score to the blowout limit.
	if run_state and run_state.is_blown_out:
		_show_blowout()
		return
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
	_show_lie_in_tray(ball_surface)
	
	# Check if ball is in the hole - don't start a new shot, trigger hole complete.
	# On the green board only the cup's own small hex is the hole.
	var in_cup: bool = ball_tile == flag_position
	if in_cup and green_board and green_board.tiles.has(_ball_small()):
		in_cup = _ball_small() == green_board.cup
	if in_cup:
		_trigger_hole_complete()
		return
	
	# FEAT-003 (R2): GREEN is now a normal lie. The lie table restricts the
	# allowed club to PUTTER on GREEN, and the player resolves the putt through
	# the play-card-then-Shoot loop. The real-time putting mini-game is retired,
	# so there is no enter_putting_mode() branch here.
	
	# Reset club selection for new shot
	current_club = -1
	
	# FEAT-003 (R4): the swing meter is retired; nothing to hide here.
	
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
		_begin_shot()
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
		
		# Also refresh UI target info now that the shot is in progress
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
		_show_lie_in_tray(int(lie_info.get("surface_type", SurfaceType.FAIRWAY)))
		
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
	# This coroutine awaits the flight, penalties and popups; a later shot or a
	# new hole bumps the serial so a stale coroutine never starts a turn.
	shot_serial += 1
	var my_serial := shot_serial
	
	# Record the stroke in run state
	if run_state:
		run_state.record_stroke(0)
	if context.final_score > 0:
		var names: Array = []
		for t in context.get_metadata("tricks", []):
			names.append(t.name)
		_award_points(context.final_score, " + ".join(names) if names.size() > 0 else "Shot bonus")
		# Update UI with new stroke count
		if shot_ui:
			var dist_to_flag = 0
			if golf_ball and flag_position.x >= 0:
				var ball_tile = world_to_grid(golf_ball.position)
				dist_to_flag = _calculate_distance_yards(ball_tile, flag_position)
			shot_ui.update_shot_info(run_state.strokes_this_hole, dist_to_flag)
	
	_clear_planned_cards()
	
	# Reset target lock state
	target_locked = false
	turn_aim_target = Vector2i(-1, -1)
	locked_cell = Vector2i(-1, -1)
	locked_target_pos = Vector3.ZERO
	hovered_cell = Vector2i(-1, -1)
	target_highlight_mesh.visible = false
	highlight_mesh.visible = false
	
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
	
	# Card-built shots replay their resolved journey exactly: fly the plan's
	# curve to the carry hex, then roll hex by hex.
	if golf_ball and context.has_metadata("roll_tiles"):
		var carry_tile: Vector2i = context.get_metadata("carry_tile")
		var carry_surface := get_cell(carry_tile.x, carry_tile.y)
		var plan: Dictionary = context.get_metadata("shot_plan", {})
		await _animate_ball_along_plan(plan.get("points", []), get_tile_surface_position(carry_tile), context.get_metadata("all_ground", false))
		if carry_surface < 0:
			hit_oob = true
			await _handle_out_of_bounds()
		elif carry_surface == SurfaceType.WATER:
			hit_water = true
			await _handle_water_hazard()
		elif carry_tile == flag_position and context.landing_tile == flag_position:
			_trigger_hole_complete()
		else:
			# Only a ball that finishes on the cup drops (fast balls run over it)
			# Roll each run of neighbouring hexes on one smooth curve; a
			# trampoline bounce hops between runs
			var prev := carry_tile
			var run: Array[Vector3] = [golf_ball.position]
			for t in context.get_metadata("roll_tiles", []):
				if hex_distance(prev, t) > 1:  # a trampoline bounce
					await _animate_ball_smooth_roll(run, 0.16)
					await _animate_ball_hop(golf_ball.position, get_tile_surface_position(t))
					run = [golf_ball.position]
				else:
					run.append(get_tile_surface_position(t))
				prev = t
			await _animate_ball_smooth_roll(run, 0.16)
			if context.landing_tile == flag_position:
				_trigger_hole_complete()
			elif context.get_metadata("hit_water", false):  # blown or bounced into water
				hit_water = true
				await _handle_water_hazard()
			elif context.get_metadata("hit_fire", false):
				_change_money(-1, "Fire")  # burnt: costs Money, the ball plays on from where it stopped
		if golf_ball:
			golf_ball.set_meta("is_spinning", false)
			golf_ball.set_meta("is_rolling", false)
	
	# Animate ball flight to landing position, then bounces
	elif golf_ball and context.landing_tile.x >= 0:
		var ball_tile = world_to_grid(golf_ball.position)
		
		# Check if landing tile is water or out of bounds
		var landing_surface = get_cell(context.landing_tile.x, context.landing_tile.y)
		if landing_surface == SurfaceType.WATER:
			hit_water = true
		elif landing_surface == -1:
			hit_oob = true
		
		# Get base bounce count from club (drivers bounce more, wedges less)
		var num_bounces = get_club_stats(current_club, CLUB_STATS[ClubType.IRON_7]).roll
		
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
			golf_ball.set_meta("is_rolling", false)
	
	# Mark animation as ended
	if shot_manager:
		shot_manager.end_animation()
	
	# Coins under the ball (hole-outs collect theirs in _trigger_hole_complete)
	if not hit_water and not hit_oob and not hole_complete_triggered:
		_collect_coins_at_ball()
	
	# Show score popup now that ball has landed - only for trick shots
	if shot_ui and context.final_score > 0:
		var names: Array = []
		for t in context.get_metadata("tricks", []):
			names.append(t.name)
		shot_ui.show_score_popup(context.chips, context.mult, context.final_score, false, false, "\n".join(names))
		
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
	elif my_serial == shot_serial:
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
var blowout_shown: bool = false  # Run-over popup already displayed
var shot_serial: int = 0  # Bumped per shot and per hole; stale shot coroutines check it
var run_shop: RunShop = null      # Pro Shop rules + this visit's offers
var course_features: CourseFeatures = null           # ice / fire / sprinklers on this hole
var feature_overlay: CourseFeatureOverlay = null
var _feature_rng := RandomNumberGenerator.new()      # seeded per hole; drives fire spread
var _fire_spread_at_stroke := -1                     # fire spreads once per stroke
var shop_panel: ShopPanel = null  # Pro Shop overlay
var green_overlay: GreenOverlay = null  # Height tint + arrows, shown on the green
var _green_overlay_dirty: bool = true   # Rebuilt once per hole, the first time the ball reaches the green
var green_board: GreenBoard = null       # The small-hex putting surface for this hole

# Putting: on the green a turn is a putt on the green board
const PUTT_POINTS_PER_HEX := 5           # a holed putt pays per small hex it touched
const BANK_SHOT_POINTS := 30             # holed after bouncing off a forgotten putter
var putting_active: bool = false
var putt_target: Vector2i = Vector2i.ZERO   # small hex the putt is struck to

# Green cards: their own deck (lasts the run), a fresh hand each putt
const PUTT_DECK_IDS := ["read_green", "read_green", "firm_putt", "firm_putt", "dead_weight", "dead_weight"]
const PUTT_HAND_SIZE := 2
var putt_deck: Array = []
var putt_discard: Array = []
var putt_hand: Array = []
var putt_cards: Dictionary = {}  # green cards played on this putt -> true
var trick_detector: TrickShotDetector = null  # Awards points for trick shots
var hole_points_log: Array = []  # [{label, points}] earned this hole, for the hole-complete breakdown

func _trigger_hole_complete() -> void:
	"""Called when ball reaches the hole/flag during any phase (carry, roll, spin)"""
	if hole_complete_triggered:
		return  # Already triggered
	
	hole_complete_triggered = true
	_update_green_view()
	
	# End animation state
	if shot_manager:
		shot_manager.end_animation()
	
	# Stop ball spin
	if golf_ball:
		golf_ball.set_meta("is_spinning", false)
		golf_ball.set_meta("is_rolling", false)
	
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
	
	# Points: coins at the cup and hole-out tricks (chip-in, long putt, ace)
	_collect_coins_at_ball()
	if trick_detector and run_state:
		for t in trick_detector.score_hole_out(previous_valid_tile, run_state.strokes_this_hole):
			_award_points(t.points, t.name)
			if shot_ui:
				shot_ui.show_bonus(t.name, t.points)
	
	# Complete the hole in run state
	var hole_result = {}
	if run_state:
		hole_result = run_state.complete_hole()
		# Par result pays out last
		if currency_manager:
			var par_diff: int = run_state.strokes_this_hole - current_par
			_award_points(currency_manager.calculate_hole_earnings(run_state.strokes_this_hole, current_par), run_state.get_par_name(par_diff))
	
	# Wait for confetti celebration
	await get_tree().create_timer(0.8).timeout
	
	# Holing out can still be the stroke that blows the run.
	if run_state and run_state.is_blown_out:
		_show_blowout()
		return
	
	_refresh_tray()  # pencil the score into the card
	# Show hole complete popup
	if shot_ui:
		var strokes = run_state.strokes_this_hole if run_state else (shot_manager.current_context.shot_index if shot_manager and shot_manager.current_context else 0)
		var hole_score = run_state.score_this_hole if run_state else 0
		var balance = currency_manager.get_balance() if currency_manager else -1
		shot_ui.show_hole_complete(strokes, current_par, hole_score, hole_points_log, balance)
		
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
	
	# Blown-out run: the popup button starts a fresh run
	if run_state.is_blown_out:
		_show_run_complete()
		return
	
	# Check if run is complete
	if run_state.is_final_hole():
		# Show run complete screen (for now, just restart)
		_show_run_complete()
		return
	
	# The Pro Shop opens after the next hole's flyover
	_proceed_to_next_hole()


func _open_shop() -> void:
	"""Open the Pro Shop at the start of a hole, after its flyover: pick the
	BAG_SIZE clubs for the hole; buy clubs and cards, remove and upgrade cards
	with points."""
	if main_ui_ref == null or currency_manager == null:
		return
	_ensure_owned_clubs()
	if run_shop == null:
		run_shop = RunShop.new()
	if shop_panel == null:
		shop_panel = ShopPanel.new()
		shop_panel.name = "ShopPanel"
		main_ui_ref.add_child(shop_panel)
	var rng: RandomNumberGenerator = hole_context.rng if hole_context else RandomNumberGenerator.new()
	run_shop.roll_offers(rng)
	run_shop.roll_club_offers(rng, owned_clubs)
	# Start from last hole's picks (still owned), topped up longest first
	var keep: Array[int] = []
	for c in hole_bag:
		if owned_clubs.has(c) and keep.size() < BAG_SIZE:
			keep.append(c)
	hole_bag = keep
	shop_panel.open(run_shop, self, main_ui_ref, run_state.current_hole if run_state else 1)


# --- Pro Shop actions (called by ShopPanel) ---

func shop_clubs() -> Array:
	"""Owned clubs, longest first (the putter isn't listed)."""
	var out: Array = owned_clubs.values()
	out.sort_custom(func(a, b): return int(CLUB_STATS[a.club].band_max) > int(CLUB_STATS[b.club].band_max))
	return out


func shop_hole_info() -> Dictionary:
	"""The Pro Shop's header: {title: "HOLE 3  ·  PAR 4  ·  412 YDS", details}."""
	var hole_no: int = run_state.current_hole if run_state else 1
	var yards := 0
	if golf_ball and flag_position.x >= 0:
		yards = _calculate_distance_yards(world_to_grid(golf_ball.position), flag_position)
	var details: Array[String] = []
	if wind_system and wind_system.enabled and wind_system.strength > 0:
		details.append("WIND %s %d KM/H" % [wind_system.get_strength_name().to_upper(), int(wind_system.speed_kmh)])
	else:
		details.append("NO WIND")
	if course_features:
		var fires := course_features.count("fire")
		if fires > 0:
			details.append("FIRE IN THE ROUGH")
	var water := false
	var sand := false
	for x in range(grid_width):
		for y in range(grid_height):
			var s := get_cell(x, y)
			water = water or s == SurfaceType.WATER
			sand = sand or s == SurfaceType.SAND
	if water:
		details.append("WATER IN PLAY")
	if sand:
		details.append("BUNKERS")
	return {"title": "HOLE %d  ·  PAR %d  ·  %d YDS" % [hole_no, current_par, yards], "details": "  ·  ".join(details)}


func shop_putter() -> ClubItem:
	return ClubItem.create(ClubType.PUTTER, "Putter", ClubItem.Tier.COMMON)


func shop_bag_size() -> int:
	return BAG_SIZE


func shop_club_yards(club: int) -> String:
	if club == ClubType.PUTTER:
		return ""
	var st := get_club_stats(club)
	return "%d–%d yd" % [int(st.get("band_min", 0) * YARDS_PER_CELL), int(st.get("band_max", 0) * YARDS_PER_CELL)]


func shop_bag_has(club: int) -> bool:
	return hole_bag.has(club)


func shop_bag_needed() -> int:
	"""Clubs still to pick before teeing off."""
	return mini(BAG_SIZE, owned_clubs.size()) - hole_bag.size()


func shop_toggle_bag(club: int) -> void:
	if hole_bag.has(club):
		hole_bag.erase(club)
	elif hole_bag.size() < BAG_SIZE:
		hole_bag.append(club)
	shop_panel.refresh()


func shop_buy_club(index: int) -> void:
	"""A better club replaces the one of its type (and keeps its bag spot)."""
	if index < 0 or index >= run_shop.club_offers.size():
		return
	var item: ClubItem = run_shop.club_offers[index]
	if not _shop_spend(item.price(), "Bought %s %s" % [item.tier_name().capitalize(), item.club_name]):
		return
	owned_clubs[item.club] = item
	run_shop.club_offers.remove_at(index)
	_refresh_club_tiers()
	shop_panel.refresh()


func _refresh_club_tiers() -> void:
	"""Tier colours on the tray's club list."""
	if main_ui_ref == null:
		return
	var colors := {}
	for club in owned_clubs:
		colors[ClubType.keys()[club]] = owned_clubs[club].color()
	main_ui_ref.set("club_tier_colors", colors)

func shop_balance() -> int:
	return currency_manager.get_balance() if currency_manager else 0


func shop_deck_cards() -> Array:
	"""Every card in the run's decks (shot + green); Strain first."""
	_ensure_putt_deck()
	var cards: Array = []
	for pile in [shot_deck, shot_discard, shot_hand, putt_deck, putt_discard, putt_hand]:
		cards.append_array(pile)
	cards.sort_custom(func(a, b):
		var sa: bool = a.data.card_type == CardData.CardType.NEGATIVE
		var sb: bool = b.data.card_type == CardData.CardType.NEGATIVE
		if sa != sb:
			return sa
		return a.get_display_name() < b.get_display_name())
	return cards


func _shop_spend(price: int, reason: String) -> bool:
	if currency_manager == null or not currency_manager.remove_chips(price, reason):
		return false
	_refresh_hole_label()
	return true


func shop_buy(index: int) -> void:
	if index < 0 or index >= run_shop.offers.size():
		return
	var data: CardData = run_shop.offers[index]
	if not _shop_spend(RunShop.price_of(data), "Bought %s" % data.card_name):
		return
	var card := CardInstance.create_from_data(data)
	if RunShop.is_green_card(data):
		putt_discard.append(card)
	else:
		shot_discard.append(card)
	run_shop.offers.remove_at(index)
	shop_panel.refresh()


func shop_buy_eraser() -> void:
	if not run_shop.eraser_available or not _shop_spend(RunShop.ERASER_PRICE, "Eraser"):
		return
	run_shop.eraser_available = false
	if run_state:
		run_state.adjust_score(-1, "Eraser")
	shop_panel.refresh()


func shop_reroll() -> void:
	if not _shop_spend(RunShop.REROLL_PRICE, "Shop reroll"):
		return
	var rng: RandomNumberGenerator = hole_context.rng if hole_context else RandomNumberGenerator.new()
	var eraser := run_shop.eraser_available
	run_shop.roll_offers(rng)
	run_shop.eraser_available = eraser
	shop_panel.refresh()


func shop_remove(card) -> void:
	if card == null or not _shop_spend(RunShop.REMOVE_PRICE, "Removed %s" % card.get_display_name()):
		return
	for pile in [shot_deck, shot_discard, shot_hand, putt_deck, putt_discard, putt_hand]:
		pile.erase(card)
	shop_panel.clear_selection()
	shop_panel.refresh()


func shop_upgrade(card) -> void:
	if card == null or not RunShop.can_upgrade(card):
		return
	if not _shop_spend(RunShop.UPGRADE_PRICE, "Upgraded %s" % card.get_display_name()):
		return
	card.upgrade()
	shop_panel.refresh()


func shop_continue() -> void:
	"""Tee off with the picked bag: the club list shows only those clubs, and
	the caddie re-picks the opening shot from them."""
	if shop_bag_needed() > 0:
		return
	shop_panel.visible = false
	_refresh_club_tiers()
	if main_ui_ref and main_ui_ref.has_method("set_hand"):
		var clubs := _legal_club_cards()
		main_ui_ref.set_hand(clubs, shot_hand, _club_subtitles(clubs))
	_auto_aim_new_shot()
	_update_shoot_button_state()
	_refresh_tray()


func _proceed_to_next_hole() -> void:
	"""Actually advance to the next hole (called after shop closes)"""
	# Advance to next hole
	run_state.advance_to_next_hole()
	
	# Regenerate with transition
	_play_transition_loading(func():
		_regenerate_hole()
	)


func _update_green_view() -> void:
	"""On the green: show the slope overlay and frame the whole green. Anywhere
	else (incl. after putting off the green): back to the shot view."""
	var on_green := _ball_on_green()
	# The club/yards label is huge this close in and covers the read
	if target_highlight_mesh and target_highlight_mesh.get("label"):
		target_highlight_mesh.label.visible = not on_green
	if not on_green:
		if green_overlay:
			green_overlay.visible = false
		if hole_viewer and hole_viewer.get("is_green_view"):
			hole_viewer.exit_green_view()
		return
	_ensure_green_board()
	green_overlay.visible = true
	if hole_viewer and hole_viewer.has_method("enter_green_view"):
		var frame := _green_frame()
		hole_viewer.enter_green_view(frame.center, frame.extent, frame.yaw)


func _ball_on_green() -> bool:
	"""Ball at rest on the green (incl. the cup's course hex) during play."""
	if golf_ball == null or hole_complete_triggered:
		return false
	var ball := world_to_grid(golf_ball.position)
	var surface := get_cell(ball.x, ball.y)
	return surface == SurfaceType.GREEN or surface == SurfaceType.FLAG or ball == flag_position


func _ensure_green_board() -> void:
	"""Build this hole's green board + overlay once (seeded from the hole)."""
	if green_overlay == null:
		green_overlay = GreenOverlay.new()
		green_overlay.name = "GreenOverlay"
		add_child(green_overlay)
	if not _green_overlay_dirty and green_board != null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (hole_context.seed if hole_context else randi()) ^ 0x5EED
	green_board = GreenBoard.new()
	green_board.build(self, rng)
	green_overlay.show_board(green_board, self)
	_green_overlay_dirty = false


func _ball_small() -> Vector2i:
	"""The green-board hex under the ball."""
	return GreenBoard.from_world(Vector2(golf_ball.position.x, golf_ball.position.z))


func _begin_putt() -> void:
	"""A putting turn: aim straight at the cup (within reach); tap to re-aim."""
	_ensure_green_board()
	putting_active = true
	club_chosen_by_player = false
	current_club = ClubType.PUTTER
	_deal_putt_hand()
	if main_ui_ref and main_ui_ref.has_method("set_hand"):
		var clubs := _legal_club_cards()
		main_ui_ref.set_hand(clubs, putt_hand, _club_subtitles(clubs))
		for card in clubs:
			if card.data.target_club == "PUTTER" and main_ui_ref.has_method("set_selected_club"):
				main_ui_ref.set_selected_club(card)
	turn_aim_target = flag_position  # a turn is aimed (the real aim is putt_target)
	target_locked = true
	set_putt_target(green_board.cup)


func _ensure_putt_deck() -> void:
	"""The green deck is built the first time it's needed (first putt or the
	first Pro Shop visit)."""
	if putt_deck.is_empty() and putt_discard.is_empty() and putt_hand.is_empty() and CardLibrary.instance:
		for id in PUTT_DECK_IDS:
			putt_deck.append(CardInstance.create_from_data(CardLibrary.instance.get_card(id)))
		_shuffle_cards(putt_deck)


func _deal_putt_hand() -> void:
	"""Discard the last green hand and draw PUTT_HAND_SIZE fresh cards."""
	putt_cards.clear()
	_ensure_putt_deck()
	putt_discard.append_array(putt_hand)
	putt_hand.clear()
	for i in range(PUTT_HAND_SIZE):
		if putt_deck.is_empty():
			if putt_discard.is_empty():
				break
			putt_deck = putt_discard
			putt_discard = []
			_shuffle_cards(putt_deck)
		putt_hand.append(putt_deck.pop_back())


func _putt_opts() -> Dictionary:
	"""The green cards played on this putt, as GreenBoard.roll() options."""
	var opts := {"reach": GreenBoard.PUTT_REACH, "dead_weight": false, "read": false}
	for card in putt_cards:
		for e in card.data.effects:
			if e is EffectPuttCard:
				opts.reach += e.reach_bonus
				opts.dead_weight = opts.dead_weight or e.dead_weight
				opts.read = opts.read or e.read_green
	return opts


func _toggle_putt_card(card) -> void:
	if putt_cards.has(card):
		putt_cards.erase(card)
	else:
		putt_cards[card] = true
	if main_ui_ref and main_ui_ref.has_method("set_card_pressed"):
		main_ui_ref.set_card_pressed(card, putt_cards.has(card))
	set_putt_target(putt_target)


func set_putt_target(small: Vector2i) -> void:
	"""Strike the putt toward small (clamped to reach) and preview it: the
	struck line only. Reading the arrows beyond is the player's plan."""
	if not putting_active or green_board == null:
		return
	var ball := _ball_small()
	if small == ball:
		return
	var opts := _putt_opts()
	putt_target = green_board.clamp_target(ball, small, opts.reach)
	_hide_all_aoe_highlights()
	highlight_mesh.visible = false
	target_highlight_mesh.visible = false
	modifier_trajectory_mesh.visible = false
	curved_trajectory_mesh.visible = false
	trajectory_shadow_mesh.visible = false
	# The struck line; with Read the Green, the whole route the ball will take
	var route: Array[Vector2i] = GreenBoard.line(ball, putt_target)
	var color := Color(1, 1, 1, 0.85)
	if opts.read:
		route = [ball]
		route.append_array(green_board.roll(ball, putt_target, opts).path)
		color = Color(1.0, 0.75, 0.25, 0.95)
	var points: Array = []
	for a in route:
		points.append(GreenBoard.to_world(a))
	var end_y := green_overlay.surface_point(route[route.size() - 1], self).y if green_board.tiles.has(route[route.size() - 1]) else golf_ball.position.y
	_draw_path_ribbon(trajectory_mesh, points, golf_ball.position.y, end_y, color, 0.0)
	trajectory_mesh.visible = true
	green_overlay.show_target(putt_target, self)
	green_overlay.show_gauge(putt_target, self, GreenBoard.distance(ball, putt_target), opts.reach,
		GreenBoard.distance(ball, green_board.cup))
	green_overlay.show_reach(ball, opts.reach, self)
	_update_shoot_button_state()


func putt_aim_ray(from: Vector3, dir: Vector3) -> bool:
	"""Tap on the green view: aim the putt at the small hex under the ray
	(intersected with the green's surface height)."""
	if not putting_active or green_board == null or absf(dir.y) < 0.001:
		return false
	var plane_y := green_overlay.surface_point(green_board.cup, self).y
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return false
	var hit := from + dir * t
	set_putt_target(GreenBoard.from_world(Vector2(hit.x, hit.z)))
	return true


func _execute_putt() -> void:
	"""Roll the putt on the green board: struck line, then arrow pushes. Holed
	putts pay per hex touched; off the green it's back to the shot view."""
	var result := green_board.roll(_ball_small(), putt_target, _putt_opts())
	putting_active = false
	putt_cards.clear()
	green_overlay.hide_target()
	trajectory_mesh.visible = false
	previous_valid_tile = world_to_grid(golf_ball.position)
	if run_state:
		run_state.record_stroke(0)
	putt_resolved.emit(result)
	shot_serial += 1
	var my_serial := shot_serial
	if shot_manager:
		shot_manager.start_animation()
	var route: Array[Vector3] = [golf_ball.position]
	for a in result.path:
		if green_board.tiles.has(a):
			route.append(green_overlay.surface_point(a, self) + Vector3(0, BALL_RADIUS_OFFSET, 0))
		else:
			# Off the green: the ball stops on the fringe course hex it ran onto
			var w := GreenBoard.to_world(a)
			route.append(get_tile_surface_position(world_to_grid(Vector3(w.x, 0.0, w.y))))
	await _animate_ball_smooth_roll(route, 0.11)
	if shot_manager:
		shot_manager.end_animation()
	if my_serial != shot_serial:
		return
	# Coins rolled over pay whether or not the putt drops, and leave the green
	for c in result.coins:
		green_board.features.erase(c)
		green_overlay.remove_coin(c)
		if run_state:
			run_state.add_coins(1)
		_award_points(TrickShotDetector.COIN_POINTS, "Coin")
	if result.coins.size() > 0:
		_change_money(result.coins.size(), "Coin" if result.coins.size() == 1 else "Coins")
	if result.holed:
		var points: int = result.touched * PUTT_POINTS_PER_HEX
		_award_points(points, "Putt: %d hexes" % result.touched)
		if result.banked:
			_award_points(BANK_SHOT_POINTS, "Bank shot")
		if shot_ui:
			shot_ui.show_bonus("Bank shot! %d-hex putt" % result.touched if result.banked else "%d-hex putt" % result.touched, points + (BANK_SHOT_POINTS if result.banked else 0))
		_trigger_hole_complete()
	else:
		_start_new_shot()


func _green_frame() -> Dictionary:
	"""World centre + extent of the green (and the ball), and the camera yaw
	that puts the ball at the bottom with the cup ahead."""
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var points: Array[Vector3] = [golf_ball.position]
	for a in (green_board.tiles.keys() if green_board else []):
		var w := GreenBoard.to_world(a)
		points.append(Vector3(w.x, 0.0, w.y))
	for p in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var center := Vector3((lo.x + hi.x) / 2.0, 0.0, (lo.y + hi.y) / 2.0)
	var extent := maxf(hi.x - lo.x, hi.y - lo.y) + TILE_SIZE
	var cup := get_tile_world_position(flag_position)
	var dir := Vector2(cup.x - golf_ball.position.x, cup.z - golf_ball.position.z)
	# hole_viewer places the camera at target + (sin(yaw), -cos(yaw)) * dist:
	# put it behind the ball, looking at the cup
	var yaw := atan2(-dir.x, dir.y) if dir.length() > 0.01 else 0.0
	return {"center": center, "extent": extent, "yaw": yaw}


func _place_course_features() -> void:
	"""Seed this hole's ice, sprinklers and (sometimes) fire, and draw them."""
	if course_features == null:
		course_features = CourseFeatures.new()
	if feature_overlay == null:
		feature_overlay = CourseFeatureOverlay.new()
		feature_overlay.name = "CourseFeatureOverlay"
		add_child(feature_overlay)
	_feature_rng.seed = (hole_context.seed if hole_context else randi()) ^ 0xF17E
	course_features.place(self, _feature_rng)
	_fire_spread_at_stroke = 0
	feature_overlay.show_features(course_features, self)
	if turn_controller:
		turn_controller.course_features = course_features


func _show_lie_in_tray(surface: int) -> void:
	"""The tray's LIE box: where the ball sits and what that does to the shot."""
	if main_ui_ref == null or not main_ui_ref.has_method("set_lie") or lie_system == null:
		return
	var lie: Dictionary = lie_system.get_lie_data(surface)
	var effects: Array[String] = []
	if int(lie.get("distance_mod", 0)) != 0:
		effects.append("%+d CARRY" % int(lie.distance_mod))
	if int(lie.get("spread_mod", 0)) != 0:
		effects.append("%+d RING" % int(lie.spread_mod))
	if int(lie.get("roll_mod", 0)) != 0:
		effects.append("%+d ROLL" % int(lie.roll_mod))
	main_ui_ref.set_lie(lie.get("display_name", "Fairway"), "  ·  ".join(effects) if not effects.is_empty() else "CLEAN LIE")


func _spread_fire_for_turn() -> void:
	"""Fire spreads once per stroke taken on this hole."""
	if course_features == null or run_state == null:
		return
	var strokes: int = run_state.strokes_this_hole
	if strokes == 0 or strokes == _fire_spread_at_stroke:
		return
	_fire_spread_at_stroke = strokes
	var wind: Vector2 = wind_system.get_direction_vector() if wind_system else Vector2.ZERO
	var wind_strength: int = wind_system.strength if wind_system else 0
	if course_features.spread_fire(self, _feature_rng, strokes, wind, wind_strength):
		feature_overlay.show_features(course_features, self)


func _on_run_hole_started() -> void:
	"""New hole: clear the points log and the trick streak; Money back to
	MONEY_PER_HOLE."""
	money = MONEY_PER_HOLE
	_place_course_features()
	_green_overlay_dirty = true
	if green_overlay:
		green_overlay.visible = false
	hole_points_log.clear()
	if trick_detector:
		trick_detector.reset_hole()


func _award_points(amount: int, label: String) -> void:
	"""Pay points into the wallet (CurrencyManager) and log them for the hole."""
	if amount <= 0:
		return
	if currency_manager:
		currency_manager.add_chips(amount, label)
	if run_state:
		run_state.add_points(amount)
	hole_points_log.append({"label": label, "points": amount})


func _collect_coins_at_ball() -> void:
	"""Collect coins within magnet radius of the ball and pay them out."""
	if golf_ball == null:
		return
	var count := collect_coins_at(world_to_grid(golf_ball.position))
	if count <= 0:
		return
	if run_state:
		run_state.add_coins(count)
	var points := count * TrickShotDetector.COIN_POINTS
	_award_points(points, "Coin x%d" % count if count > 1 else "Coin")
	_change_money(count, "Coin" if count == 1 else "Coins")


func _show_blowout() -> void:
	"""Run ended: the score vs par reached the blowout limit."""
	if blowout_shown:
		return
	blowout_shown = true
	if shot_ui and shot_ui.has_method("show_run_over"):
		shot_ui.show_run_over(
			"Blowout!",
			"Run over at %s\n(limit %s)" % [run_state.format_vs_par(run_state.get_live_vs_par()), run_state.format_vs_par(run_state.blowout_limit)],
			"Holes completed: %d of %d\nTotal strokes: %d" % [run_state.holes_completed, run_state.total_holes, run_state.total_strokes],
			"New Run")


func _refresh_hole_label(extra: String = "") -> void:
	"""HUD hole label: run score line on top, then hole info (+ optional debug)."""
	_refresh_tray()
	if holelabel == null:
		return
	# Prototype: one status line, no hole stats or tile debug
	if main_ui_ref and main_ui_ref.get("prototype_ui") and run_state:
		holelabel.text = "Hole %d · Par %d · Stroke %d  |  Run %s (blowout %s)" % [
			run_state.current_hole, current_par, run_state.strokes_this_hole + 1,
			run_state.format_vs_par(run_state.get_live_vs_par()),
			run_state.format_vs_par(run_state.blowout_limit)]
		if currency_manager:
			holelabel.text += "  |  %d pts" % currency_manager.get_balance()
		if putting_active and green_board:
			holelabel.text += "  |  %s green" % green_board.style.capitalize()
		return
	var text := ""
	if run_state:
		text = "%s  |  Run %s  (blowout %s)" % [
			run_state.get_hole_display(),
			run_state.format_vs_par(run_state.get_live_vs_par()),
			run_state.format_vs_par(run_state.blowout_limit)]
		if currency_manager:
			text += "  |  %d pts" % currency_manager.get_balance()
		text += "\n"
	text += hole_info_text
	if extra != "":
		text += "\n" + extra
	holelabel.text = text


func _show_run_complete() -> void:
	"""Show run completion screen - TODO: implement full run complete UI"""
	# For now, start a new run
	if run_state:
		run_state.start_new_run(9)
	if currency_manager:
		currency_manager.reset_currency()
	shot_deck.clear()
	shot_discard.clear()
	shot_hand.clear()
	owned_clubs.clear()
	hole_bag.clear()
	putt_deck.clear()
	putt_discard.clear()
	putt_hand.clear()
	blowout_shown = false
	
	_play_transition_loading(func():
		_regenerate_hole()
	)


func _regenerate_hole() -> void:
	"""Internal helper to regenerate the hole"""
	# Reset for next hole
	shot_serial += 1
	hole_complete_triggered = false
	
	# Reset shot counter (club selection happens in _start_new_shot)
	if shot_manager and shot_manager.current_context:
		shot_manager.current_context.shot_index = 0
	current_club = -1  # Reset club selection
	
	# Reset card deck for new hole
	if card_system and card_system.has_method("reset_swing_deck_for_new_hole"):
		card_system.reset_swing_deck_for_new_hole()
	
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
	
	# Every new hole gets its own seed (authored holes keep theirs); the shot,
	# wind and green systems share this RNG object, so they follow along
	if hole_context and hole_context.definition == null:
		hole_context.seed = randi()
		hole_context.rng.seed = hole_context.seed
	
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
	_show_lie_in_tray(SurfaceType.TEE)
	
	# Start a fresh shot
	_start_new_shot()
	# FEAT-003: re-deal the hand into the hand UI for the regenerated hole.
	_deal_hand_for_current_hole()


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
	
	# The ball turns forward with the ground it covers between bounces
	_set_ball_rolling(true)
	
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


func _animate_ball_hop(start_pos: Vector3, end_pos: Vector3) -> void:
	"""A short bounce off a trampoline."""
	if golf_ball == null:
		return
	var speed_mult: float = shot_manager.get_animation_speed() if shot_manager else 1.0
	var peak := 1.5 + start_pos.distance_to(end_pos) * 0.2
	var hop := func(t: float) -> void:
		golf_ball.position = start_pos.lerp(end_pos, t) + Vector3(0, sin(t * PI) * peak, 0)
	current_ball_tween = create_tween()
	current_ball_tween.tween_method(hop, 0.0, 1.0, 0.45 / speed_mult)
	await current_ball_tween.finished
	golf_ball.position = end_pos


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
	
	# The ball turns with the distance it rolls
	_set_ball_rolling(true)
	
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
var _ball_last_pos := Vector3.ZERO  # for rolling: rotation follows the distance moved
const BALL_ROLL_RADIUS := 0.46       # the ball model's radius in world units (mesh 1.53 x scale 0.3)

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


func _animate_ball_along_plan(points: Array, end_pos: Vector3, rolling: bool = false) -> void:
	"""Fly the ball along a ShotPlan's curve (world x,z samples) in an arc,
	easing onto end_pos (the drawn carry hex, which the ring may have moved)."""
	if golf_ball == null:
		return
	if points.size() < 2:
		await _animate_ball_flight_with_bounce(golf_ball.position, end_pos)
		return
	var start_pos := golf_ball.position
	var last: Vector2 = points[points.size() - 1]
	var miss := Vector2(end_pos.x, end_pos.z) - last  # ring scatter, blended in late
	var length := 0.0
	for i in range(1, points.size()):
		length += (points[i] - points[i - 1]).length()
	var speed_mult: float = shot_manager.get_animation_speed() if shot_manager else 1.0
	var duration: float = clampf(length * 0.08, 0.5, 2.5) / speed_mult
	var peak: float = 0.0 if rolling else _flight_arc(clampf(trajectory_height * 1.25 + length * 0.05, 2.0, 18.0), shot_manager.current_context if shot_manager else null)
	if rolling:
		duration *= 1.6  # a putt rolls slower than a ball flies
		_set_ball_rolling(true)
	else:
		_start_flight_spin(points, duration, length)
	var fly := func(t: float) -> void:
		var f := t * float(points.size() - 1)
		var i := mini(int(f), points.size() - 2)
		var p: Vector2 = (points[i] as Vector2).lerp(points[i + 1], f - i) + miss * t * t
		var y := lerpf(start_pos.y, end_pos.y, t) + sin(t * PI) * peak
		if rolling:
			y = get_tile_surface_position(world_to_grid(Vector3(p.x, 0.0, p.y))).y  # hug the green
		golf_ball.position = Vector3(p.x, y, p.y)
	current_ball_tween = create_tween()
	current_ball_tween.tween_method(fly, 0.0, 1.0, duration)
	await current_ball_tween.finished
	golf_ball.position = end_pos


func _start_flight_spin(points: Array, duration: float, length: float) -> void:
	"""Backspin about the flight's right-hand axis, tilted by how far the
	plan's curve bends off the straight line: a draw (bends left) leans the
	axis one way, a fade (bends right) the other, more for a harder shape."""
	var a: Vector2 = points[0]
	var b: Vector2 = points[points.size() - 1]
	var chord := b - a
	var forward := Vector3(chord.x, 0.0, chord.y).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	if right.length() < 0.1:
		right = Vector3.RIGHT
	# Signed bend: the furthest the curve strays right (+) or left (-) of the chord
	var bend := 0.0
	var right2 := Vector2(right.x, right.z)
	for p in points:
		var off: float = ((p as Vector2) - a).dot(right2)
		if absf(off) > absf(bend):
			bend = off
	var tilt := clampf(bend / maxf(length, 0.001) * 4.0, -0.8, 0.8)
	golf_ball.set_meta("spin_axis", right.rotated(forward, tilt) if tilt != 0.0 else right)
	var speed_mult: float = shot_manager.get_animation_speed() if shot_manager else 1.0
	var turns := clampf(length * 0.15, 2.0, 6.0)
	golf_ball.set_meta("spin_speed", TAU * turns / duration * speed_mult)
	golf_ball.set_meta("is_spinning", true)
	golf_ball.set_meta("is_rolling", false)


func _animate_ball_smooth_roll(points: Array[Vector3], per_step: float) -> void:
	"""Roll the ball through points (its own position first) on one smooth
	curve: quick off the face, easing to a stop. Catmull-Rom through the hex
	centres, sharp only where the ball turns right back (a bank)."""
	if golf_ball == null or points.size() < 2:
		return
	var speed_mult: float = shot_manager.get_animation_speed() if shot_manager else 1.0
	var samples := _smooth_path(points, 8)
	var lengths: Array[float] = [0.0]
	for i in range(1, samples.size()):
		lengths.append(lengths[i - 1] + samples[i].distance_to(samples[i - 1]))
	var total: float = lengths[lengths.size() - 1]
	if total < 0.001:
		return
	_set_ball_rolling(true)
	var roll := func(u: float) -> void:
		# Mostly ease-out (the ball loses pace), with some constant speed so a
		# long chain doesn't crawl at the end
		var d := total * lerpf(u, 1.0 - (1.0 - u) * (1.0 - u), 0.7)
		var i := clampi(lengths.bsearch(d), 1, samples.size() - 1)
		var seg := lengths[i] - lengths[i - 1]
		var f := 0.0 if seg < 0.0001 else (d - lengths[i - 1]) / seg
		golf_ball.position = samples[i - 1].lerp(samples[i], f)
	current_ball_tween = create_tween()
	var steps := points.size() - 1
	current_ball_tween.tween_method(roll, 0.0, 1.0, clampf(per_step * steps, 0.3, 4.0) / speed_mult)
	await current_ball_tween.finished
	golf_ball.position = points[points.size() - 1]


static func _smooth_path(points: Array[Vector3], per_segment: int) -> Array[Vector3]:
	"""Catmull-Rom samples through points. Where the path reverses (a bank off
	the putter) the tangent is zero, so the ball stops and comes back rather
	than looping."""
	var n := points.size()
	var tangents: Array[Vector3] = []
	for i in range(n):
		var prev: Vector3 = points[maxi(i - 1, 0)]
		var next: Vector3 = points[mini(i + 1, n - 1)]
		var m := (next - prev) * 0.5
		if i > 0 and i < n - 1:
			var din := points[i] - prev
			var dout := next - points[i]
			if din.length() > 0.001 and dout.length() > 0.001 and din.normalized().dot(dout.normalized()) < -0.3:
				m = Vector3.ZERO
		tangents.append(m)
	var out: Array[Vector3] = [points[0]]
	for i in range(n - 1):
		var p1 := points[i]
		var p2 := points[i + 1]
		for k in range(1, per_segment + 1):
			var t := float(k) / float(per_segment)
			var t2 := t * t
			var t3 := t2 * t
			out.append(p1 * (2.0 * t3 - 3.0 * t2 + 1.0) + tangents[i] * (t3 - 2.0 * t2 + t)
				+ p2 * (-2.0 * t3 + 3.0 * t2) + tangents[i + 1] * (t3 - t2))
	return out


func _animate_ball_flight_with_bounce(start_pos: Vector3, end_pos: Vector3) -> void:
	"""Animate ball flight with a smooth bounce-and-roll transition at landing.
	   The ball lands, does a small bounce, and is ready to roll.
	   Uses curved flight path when curve_strength or wind_curve is non-zero."""
	if golf_ball == null:
		return
	
	# Get animation speed multiplier
	var speed_mult = shot_manager.get_animation_speed() if shot_manager else 1.0
	
	# Determine curve profile from shot context (if available)
	var curve_type: String = ""
	var curve_amount_world: float = 0.0
	if shot_manager and shot_manager.current_context:
		var ctx: ShotContext = shot_manager.current_context
		curve_type = _get_effective_curve_profile_from_context(ctx)
		
		# Derive a world-space curve amount by comparing the actual carry end (end_pos)
		# to the carry end that would occur with distance-only targeting (no curve/wind).
		# This makes the arc match the actual shot offset, rather than an arbitrary scale.
		var start_tile := ctx.start_tile
		var aim_tile := ctx.aim_tile
		if start_tile.x >= 0 and aim_tile.x >= 0:
			var num_bounces = get_club_stats(current_club, CLUB_STATS[ClubType.IRON_7]).roll
			var uncurved_target_tile := _calculate_uncurved_target_tile(start_tile, aim_tile, ctx.distance_mod)
			var uncurved_carry_tile := _get_carry_position(start_tile, uncurved_target_tile, num_bounces)
			var uncurved_carry_pos := get_tile_surface_position(uncurved_carry_tile)
			curve_amount_world = _compute_lateral_offset_world(start_pos, uncurved_carry_pos, end_pos)
		
		if curve_type == "":
			curve_type = "draw" if curve_amount_world < 0.0 else "fade"
	
	# Calculate flight parameters based on distance
	var distance = start_pos.distance_to(end_pos)
	var flight_duration = clamp(distance * 0.08, 0.5, 2.5) / speed_mult
	
	# Peak height based on distance and club arc height.
	# Keep club differences visible while letting longer shots arc slightly higher.
	var peak_height = clamp((trajectory_height * 1.25) + (distance * 0.05), 2.0, 18.0)
	
	# Add extra height if going uphill
	var height_diff = end_pos.y - start_pos.y
	if height_diff > 0:
		peak_height += height_diff * 0.5
	
	# Use the derived world-space curve amount directly.
	var scaled_curve = curve_amount_world
	
	# Calculate spin direction (ball spins in direction of travel, with tilt for curve)
	var travel_dir = (end_pos - start_pos).normalized()
	var spin_axis = travel_dir.cross(Vector3.UP).normalized()
	if spin_axis.length() < 0.1:
		spin_axis = Vector3.RIGHT
	
	# Tilt spin axis based on curve (adds sidespin appearance)
	if abs(curve_amount_world) > 0.1:
		# Convert world-space lateral offset into a small, stable tilt.
		var tilt_norm: float = float(curve_amount_world) / max(distance, 0.001)
		var tilt_amount: float = clamp(tilt_norm, -1.0, 1.0) * 0.4
		spin_axis = spin_axis.rotated(travel_dir, tilt_amount)
	
	# Start ball spin animation (slower, more realistic)
	var total_rotations = clamp(distance * 0.2, 1.0, 8.0)  # Fewer rotations
	var spin_speed = (total_rotations * TAU) / flight_duration
	golf_ball.set_meta("spin_axis", spin_axis)
	golf_ball.set_meta("spin_speed", spin_speed * speed_mult)  # Speed up spin too
	golf_ball.set_meta("is_spinning", true)
	golf_ball.set_meta("is_rolling", false)
	
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
	golf_ball.set_meta("is_rolling", false)


func _stop_ball_spin() -> void:
	"""Stop the ball spinning"""
	if golf_ball == null:
		return
	
	golf_ball.set_meta("is_spinning", false)
	golf_ball.set_meta("is_rolling", false)
	
	if ball_spin_tween and ball_spin_tween.is_valid():
		ball_spin_tween.kill()
		ball_spin_tween = null


func _process_ball_spin(delta: float) -> void:
	"""Update ball spin rotation each frame. On the ground (is_rolling) the
	ball turns by exactly how far it moved, so it rolls without slipping; in
	the air it spins about spin_axis (backspin, tilted for draw / fade)."""
	if golf_ball == null:
		return
	var pos := golf_ball.position
	var moved := pos - _ball_last_pos
	_ball_last_pos = pos
	if golf_ball.get_meta("is_rolling", false):
		moved.y = 0.0
		if moved.length() > 0.0001 and moved.length() < 5.0:
			golf_ball.rotate(Vector3.UP.cross(moved.normalized()), moved.length() / BALL_ROLL_RADIUS)
		return
	
	if not golf_ball.has_meta("is_spinning") or not golf_ball.get_meta("is_spinning"):
		return
	
	var spin_axis = golf_ball.get_meta("spin_axis")
	var spin_speed = golf_ball.get_meta("spin_speed")
	
	# Rotate around the spin axis
	golf_ball.rotate(spin_axis, spin_speed * delta)


func _set_ball_rolling(rolling: bool) -> void:
	"""Ground mode (turn with the distance moved) or air mode (spin_axis)."""
	if golf_ball == null:
		return
	golf_ball.set_meta("is_rolling", rolling)
	if rolling:
		golf_ball.set_meta("is_spinning", false)


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
	
	# Curve progress: controls how quickly the ball "commits" to the curved end.
	# Hook/Slice should feel more late-breaking than Draw/Fade.
	var curve_progress: float
	if curve_type == "push" or curve_type == "pull" or curve_type == "wind":
		curve_progress = t
	else:
		curve_progress = t * t * (3.0 - 2.0 * t)  # Smoothstep
		match curve_type:
			"hook", "slice":
				curve_progress = pow(curve_progress, 1.8)  # Later break
			_:
				curve_progress = pow(curve_progress, 1.0)  # Default
	
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
	var aim_tile := world_to_grid(target_pos)
	
	# Draw the raw aim trajectory (player intent)
	_draw_trajectory_arc(trajectory_mesh, start_pos, end_pos, Color(1.0, 1.0, 1.0, 0.6))
	trajectory_mesh.visible = true
	
	# Draw predicted trajectory (mods + curve + wind) on modifier mesh
	var predicted_pos := Vector3.ZERO
	var distance_mod: int = 0
	var curve_amount_world: float = 0.0
	var curve_type: String = ""
	if shot_manager and shot_manager.current_context:
		var ctx: ShotContext = shot_manager.current_context
		distance_mod = ctx.distance_mod
		curve_type = _get_effective_curve_profile_from_context(ctx)
		
		var start_tile := world_to_grid(start_pos)
		if start_tile.x >= 0 and aim_tile.x >= 0:
			var uncurved_tile := _calculate_uncurved_target_tile(start_tile, aim_tile, distance_mod)
			var predicted_tile := _calculate_predicted_target_tile(start_tile, aim_tile, distance_mod, ctx.curve_strength, ctx.wind_curve, curve_type)
			var uncurved_pos := get_tile_surface_position(uncurved_tile)
			predicted_pos = get_tile_surface_position(predicted_tile)
			curve_amount_world = _compute_lateral_offset_world(start_pos, uncurved_pos, predicted_pos)
			if curve_type == "":
				curve_type = "draw" if curve_amount_world < 0.0 else "fade"
	
	if predicted_pos != Vector3.ZERO and (abs(distance_mod) > 0 or abs(curve_amount_world) > 0.3):
		var mod_color: Color
		if distance_mod > 0:
			mod_color = Color(0.2, 1.0, 0.2, 0.75)  # Green for + distance
		elif distance_mod < 0:
			mod_color = Color(1.0, 0.2, 0.2, 0.75)  # Red for - distance
		else:
			mod_color = Color(0.6, 0.8, 1.0, 0.7)   # Blue-ish when curve/wind only
		
		if abs(curve_amount_world) > 0.3:
			_draw_trajectory_arc_curved(modifier_trajectory_mesh, start_pos, predicted_pos, curve_amount_world, mod_color)
		else:
			_draw_trajectory_arc(modifier_trajectory_mesh, start_pos, predicted_pos, mod_color)
		modifier_trajectory_mesh.visible = true
	else:
		modifier_trajectory_mesh.visible = false
	
	# Curved trajectory mesh not used anymore
	curved_trajectory_mesh.visible = false
	
	# Draw shadow line on ground (prefer predicted path when shown)
	var shadow_end: Vector3 = predicted_pos if modifier_trajectory_mesh.visible else end_pos
	_draw_trajectory_shadow(start_pos, shadow_end, modifier_trajectory_mesh.visible and abs(curve_amount_world) > 0.3)


func _get_effective_curve_profile_from_context(ctx: ShotContext) -> String:
	if ctx == null:
		return ""
	if ctx.curve_profile != "":
		return ctx.curve_profile
	if abs(ctx.curve_strength) < 0.01:
		return ""
	return "draw" if ctx.curve_strength < 0.0 else "fade"


func _calculate_uncurved_target_tile(start_tile: Vector2i, aim_tile: Vector2i, distance_mod: int) -> Vector2i:
	# Distance-only adjustment along shot direction.
	var dir_x = float(aim_tile.x - start_tile.x)
	var dir_y = float(aim_tile.y - start_tile.y)
	var length = sqrt(dir_x * dir_x + dir_y * dir_y)
	if length < 0.1:
		return aim_tile
	var norm_x = dir_x / length
	var norm_y = dir_y / length
	var target_x = float(aim_tile.x) + (norm_x * float(distance_mod))
	var target_y = float(aim_tile.y) + (norm_y * float(distance_mod))
	var final_x = int(round(target_x))
	var final_y = int(round(target_y))
	final_x = clampi(final_x, 0, grid_width - 1)
	final_y = clampi(final_y, 0, grid_height - 1)
	return Vector2i(final_x, final_y)


func _calculate_predicted_target_tile(start_tile: Vector2i, aim_tile: Vector2i, distance_mod: int, curve_strength: float, wind_curve: int, curve_profile: String) -> Vector2i:
	var uncurved := _calculate_uncurved_target_tile(start_tile, aim_tile, distance_mod)
	
	var dir_x = float(aim_tile.x - start_tile.x)
	var dir_y = float(aim_tile.y - start_tile.y)
	var length = sqrt(dir_x * dir_x + dir_y * dir_y)
	if length < 0.1:
		return uncurved
	var norm_x = dir_x / length
	var norm_y = dir_y / length
	
	var perp_x = -norm_y
	var perp_y = norm_x
	
	var endpoint_mult := 1.0
	if curve_profile == "hook" or curve_profile == "slice":
		endpoint_mult = 1.75
	
	var total_curve := (curve_strength * endpoint_mult) + float(wind_curve)
	var target_x = float(uncurved.x) + (perp_x * total_curve)
	var target_y = float(uncurved.y) + (perp_y * total_curve)
	
	var final_x = clampi(int(round(target_x)), 0, grid_width - 1)
	var final_y = clampi(int(round(target_y)), 0, grid_height - 1)
	return Vector2i(final_x, final_y)


func _compute_lateral_offset_world(start_pos: Vector3, uncurved_end_pos: Vector3, curved_end_pos: Vector3) -> float:
	# Returns signed lateral offset in world units, relative to the start->uncurved direction.
	var dir = Vector3(uncurved_end_pos.x - start_pos.x, 0, uncurved_end_pos.z - start_pos.z)
	if dir.length() < 0.001:
		dir = Vector3(curved_end_pos.x - start_pos.x, 0, curved_end_pos.z - start_pos.z)
	if dir.length() < 0.001:
		return 0.0
	dir = dir.normalized()
	var perp = Vector3(-dir.z, 0, dir.x)  # right of travel direction
	var delta = Vector3(curved_end_pos.x - uncurved_end_pos.x, 0, curved_end_pos.z - uncurved_end_pos.z)
	return delta.dot(perp)


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
		
		# FEAT-003: seed wind from the HoleContext RNG for determinism.
		var wind_rng: RandomNumberGenerator = hole_context.rng if hole_context else null
		wind_system.generate_wind(difficulty, wind_rng)
		
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
	_refresh_hole_label()
	
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
	if card_system and card_system.has_method("reset_swing_deck_for_new_hole"):
		card_system.reset_swing_deck_for_new_hole()
	
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
	if card_system and card_system.has_method("reset_swing_deck_for_new_hole"):
		card_system.reset_swing_deck_for_new_hole()
	
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
	
	# A narrow-fairway hole already has its trees: random ones would plug the gaps
	if current_unique_type == UniqueHoleType.NARROW_FAIRWAY:
		fairway_hazard_candidates.clear()
	if fairway_hazard_candidates.size() > 0:
		# 1. Large single tree on fairway (30% chance)
		if randf() < 0.3:
			var tree_pos = fairway_hazard_candidates[randi() % fairway_hazard_candidates.size()]
			if _fairway_row_open(tree_pos.y) > MIN_OPEN_FAIRWAY:
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
				fairway_hazard_candidates.erase(group_start)
				if _fairway_row_open(group_start.y) <= MIN_OPEN_FAIRWAY:
					continue
				set_cell(group_start.x, group_start.y, SurfaceType.TREE)
				
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
							and _fairway_row_open(ny) > MIN_OPEN_FAIRWAY \
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


const MIN_OPEN_FAIRWAY := 4  # random fairway trees never leave a row with fewer open fairway hexes


func _fairway_row_open(row: int) -> int:
	"""Open fairway hexes across a row."""
	var n := 0
	for col in range(grid_width):
		if get_cell(col, row) == SurfaceType.FAIRWAY:
			n += 1
	return n


func _apply_narrow_fairway_trees(fairway_cells: Dictionary) -> void:
	"""Add trees encroaching on the fairway to create 2-3 narrow (4-tile) choke points.
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
	
	# 2-3 choke points, evenly distributed (4-6 long ones walled off most of
	# the fairway and left few clean landing spots)
	var num_chokes = 2 + randi() % 2  # 2-3 chokes
	var spacing = rows_to_narrow.size() / (num_chokes + 1)
	var choke_length = 3 + randi() % 2  # 3-4 rows long each choke
	
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
			
			# Keep a 4-wide gap round the centre
			var keep_min = center_col - 1
			var keep_max = center_col + 2
			
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

	# Instance trees at TREE cells.
	# Trees are placed to frame the hole and provide visual boundaries.
	#
	# VISUALS are drawn with one MultiMeshInstance3D per tree model (GPU
	# instancing) so a forest of trees stays cheap. COLLISIONS stay as a
	# lightweight per-cell StaticBody3D + CylinderShape3D (gameplay depends on
	# tree collisions), each added to the "trees" group just as before.
	#
	# IMPORTANT: placement (which cells, position jitter, rotation, scale ranges)
	# is UNCHANGED - only the render path moved from one scene instance per cell
	# to shared MultiMeshes. Per-tree foliage colour variation is carried as
	# MultiMesh per-instance custom data (see tree_toon.gdshader INSTANCE_CUSTOM).
	var tree_models := _get_tree_model_data()
	# Per-model accumulated transforms + custom colours, indexed by model.
	var tree_xforms: Array = []
	var tree_colors: Array = []
	var shadow_xforms: Array = []
	for _m in range(tree_models.size()):
		tree_xforms.append([] as Array[Transform3D])
		tree_colors.append([] as Array[Color])
	for col in range(grid_width):
		for row in range(grid_height):
			if get_cell(col, row) == SurfaceType.TREE:
				# Pick a random tree model from the array
				var model_idx := randi() % tree_models.size()

				var tree_x = col * width * 1.5
				var tree_z = row * height + (col % 2) * (height / 2.0)
				var tree_y = get_elevation(col, row) + TILE_SURFACE_OFFSET  # Position on tile surface

				# Add random position offset for natural variation
				tree_x += (randf() - 0.5) * 0.4
				tree_z += (randf() - 0.5) * 0.4
				var tree_pos := Vector3(tree_x, tree_y, tree_z)

				# Random Y rotation for variety + slight tilt for natural look
				var tree_rot := Vector3(
					deg_to_rad(randf_range(-5.0, 5.0)),
					randf() * TAU,
					deg_to_rad(randf_range(-5.0, 5.0))
				)

				# Random scale with height bias for tree variety (larger trees)
				var base_scale = randf_range(1.5, 2.5)
				var height_scale = base_scale * randf_range(0.9, 1.3)  # Trees can be taller

				# Build the placement transform exactly as the old per-scene
				# instance did (position, euler rotation, non-uniform scale),
				# then fold in the model's own node-tree local transform so the
				# MultiMesh instance lands where the scene instance would have.
				var basis := Basis.from_euler(tree_rot) * Basis.from_scale(
					Vector3(base_scale, height_scale, base_scale))
				var placement := Transform3D(basis, tree_pos)
				var mesh_xform: Transform3D = placement * tree_models[model_idx]["local"]
				tree_xforms[model_idx].append(mesh_xform)
				tree_colors[model_idx].append(_pick_tree_foliage_color())

				# Faux contact shadow disc flat on the tile surface under the tree.
				var disc_scale: float = 0.9 * base_scale
				var shadow_basis := Basis.from_scale(Vector3(disc_scale, 1.0, disc_scale))
				shadow_xforms.append(Transform3D(
					shadow_basis, Vector3(tree_x, tree_y + 0.02, tree_z)))

				# Lightweight per-cell collision so shots can hit trees.
				var collision_shape = CollisionShape3D.new()
				var cylinder = CylinderShape3D.new()
				cylinder.radius = 0.3 * base_scale  # Scale with tree size
				cylinder.height = 3.0 * height_scale  # Trunk height
				collision_shape.shape = cylinder
				collision_shape.position = Vector3(0, cylinder.height / 2.0, 0)  # Center on trunk

				var static_body = StaticBody3D.new()
				static_body.position = tree_pos
				static_body.add_child(collision_shape)
				static_body.add_to_group("trees")
				add_child(static_body)

	# Build one MultiMeshInstance3D per tree model for the visual meshes.
	for model_idx in range(tree_models.size()):
		var xlist: Array = tree_xforms[model_idx]
		if xlist.is_empty():
			continue
		var clist: Array = tree_colors[model_idx]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = tree_models[model_idx]["mesh"]
		mm.instance_count = xlist.size()
		for i in range(xlist.size()):
			mm.set_instance_transform(i, xlist[i])
			var c: Color = clist[i]
			# a=1 flags the shader to use this per-instance foliage tint.
			mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = TREE_FOLIAGE_MATERIAL
		add_child(mmi)

	# One MultiMesh for every faux contact-shadow disc.
	if not shadow_xforms.is_empty():
		var smm := MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.mesh = _get_tree_shadow_mesh()
		smm.instance_count = shadow_xforms.size()
		for i in range(shadow_xforms.size()):
			smm.set_instance_transform(i, shadow_xforms[i])
		var smmi := MultiMeshInstance3D.new()
		smmi.multimesh = smm
		smmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(smmi)
	
	# Spawn coins based on par: Par 5 = 3 coins, Par 4 = 2 coins, Par 3 = 1 coin
	_spawn_coins(fairway_cells)
	
	# Spawn foliage (grass patches, bushes, rocks, flowers) based on surface type
	_spawn_foliage()
	
	# Add slope arrows on green tiles
	_spawn_green_slope_arrows(green_cells)

	# Align fairway/green mowing stripes to the hole's tee->flag play direction
	_apply_mowing_direction()


# Align mowing stripes on the fairway and green turf materials to the hole's
# play direction (tee -> flag). Both tiles share one MultiMesh material each
# (reached via mesh_map), so setting stripe_dir once updates every instance.
# Does not alter any tile transforms, generation, or layout.
func _apply_mowing_direction() -> void:
	var stripe_dir := Vector2(0.0, 1.0)
	if flag_position.x >= 0 and flag_position.y >= 0 and tee_position != Vector3.ZERO:
		var width := TILE_SIZE
		var height := TILE_SIZE * sqrt(3.0)
		var flag_x := flag_position.x * width * 1.5
		var flag_z := flag_position.y * height + (flag_position.x % 2) * (height / 2.0)
		var dir := Vector2(flag_x - tee_position.x, flag_z - tee_position.z)
		if dir.length() > 0.001:
			stripe_dir = dir.normalized()

	for surf_type in [SurfaceType.FAIRWAY, SurfaceType.GREEN]:
		var mesh := mesh_map[surf_type] as ArrayMesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mat := mesh.surface_get_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("stripe_dir", stripe_dir)


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


# Pick a random muted-green foliage tint from the variation palette.
func _pick_tree_foliage_color() -> Color:
	return TREE_FOLIAGE_COLORS[randi() % TREE_FOLIAGE_COLORS.size()]


# Apply random foliage colour variation to a single tree scene instance.
#
# The tree meshes are soft-cel ShaderMaterial meshes (tree_toon.gdshader); this
# walks the MeshInstance3D children, duplicates the ShaderMaterial per tree so
# they don't share, and sets the foliage_colour parameter. This is the real
# recolor path for a standalone tree scene instance (the in-course forest uses
# the MultiMesh per-instance custom-data path instead). Rewritten from the old
# no-op that only touched CSGSphere3D children (the trees have none).
func _apply_random_tree_colors(tree: Node3D) -> void:
	var color := _pick_tree_foliage_color()
	for mi in _find_mesh_instances(tree):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for surf in range(mesh.get_surface_count()):
			# Prefer an explicit surface override; otherwise start from the
			# mesh's surface material so we never mutate the shared resource.
			var src: Material = mi.get_surface_override_material(surf)
			if src == null:
				src = mesh.surface_get_material(surf)
			if src is ShaderMaterial:
				var dup := (src as ShaderMaterial).duplicate() as ShaderMaterial
				dup.set_shader_parameter("foliage_colour", color)
				mi.set_surface_override_material(surf, dup)


# Depth-first collect all MeshInstance3D nodes under a tree scene root.
func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_find_mesh_instances(child))
	return out


# Instantiate each tree scene once to harvest its mesh and the accumulated
# node-tree local transform down to the MeshInstance3D (the scenes nest the
# mesh under scaled Node3D parents). Cached so regeneration is cheap.
func _get_tree_model_data() -> Array:
	if not _tree_model_data.is_empty():
		return _tree_model_data
	for scene in TREE_SCENES:
		var root := scene.instantiate() as Node3D
		var mi := _find_mesh_instances(root)
		if not mi.is_empty():
			var inst := mi[0]
			# Accumulate transforms from the scene root down to the mesh.
			var xform := Transform3D.IDENTITY
			var chain: Array = []
			var n: Node = inst
			while n != null and n != root:
				chain.push_front(n)
				n = n.get_parent()
			for step_node in chain:
				xform = xform * (step_node as Node3D).transform
			_tree_model_data.append({"mesh": inst.mesh, "local": xform})
		root.free()
	return _tree_model_data


# Build (once) the shared flat disc used for faux tree contact shadows.
func _get_tree_shadow_mesh() -> QuadMesh:
	if _tree_shadow_mesh != null:
		return _tree_shadow_mesh
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	# Lay the quad flat (facing +Y) so it reads as a shadow on the ground.
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = TREE_SHADOW_SHADER
	quad.material = mat
	_tree_shadow_mesh = quad
	return _tree_shadow_mesh


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
	# FEAT-003: re-deal the hand into the hand UI for the regenerated hole.
	_deal_hand_for_current_hole()


func _on_button_pressed() -> void:
	"""Handle Generate New Hole button - play transition while regenerating"""
	_play_transition_loading(func():
		# Reset shot counter and club selection
		if shot_manager and shot_manager.current_context:
			shot_manager.current_context.shot_index = 0
		current_club = ClubType.DRIVER
		_update_club_button_visuals()
		
		# Reset card deck
		if card_system and card_system.has_method("reset_swing_deck_for_new_hole"):
			card_system.reset_swing_deck_for_new_hole()
		
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
		# FEAT-003: re-deal the hand into the hand UI for the new hole.
		_deal_hand_for_current_hole()
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
		if card_system and card_system.has_method("reset_swing_deck_for_new_hole"):
			card_system.reset_swing_deck_for_new_hole()
		
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
		# FEAT-003: re-deal the hand into the hand UI for the new unique hole.
		_deal_hand_for_current_hole()
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
