extends Node3D
class_name MobileHoleGenerator

signal hole_generated(hole_data: Dictionary)

# Mobile-optimized generator with FULL hole variety from the original HexGrid.
# Uses MultiMeshInstance3D per surface type for efficient rendering.

enum SurfaceType {
	TEE, FAIRWAY, ROUGH, DEEP_ROUGH, GREEN, SAND, WATER, TREE, FLAG
}

enum UniqueHoleType {
	NONE,
	TRUE_DOGLEG,
	ISLAND_GREEN,
	S_CURVE,
	NARROW_FAIRWAY
}

# Par configuration (matches original)
const PAR_CONFIG = {
	3: { "min_yards": 120, "max_yards": 220, "min_width": 12, "max_width": 18 },
	4: { "min_yards": 280, "max_yards": 450, "min_width": 14, "max_width": 22 },
	5: { "min_yards": 460, "max_yards": 600, "min_width": 16, "max_width": 26 },
}
const YARDS_PER_CELL: int = 10

@export var tile_size: float = 1.0
@export_range(3, 5) var par: int = 4
@export var random_par: bool = true
@export var seed_value: int = -1
@export var regenerate_on_ready: bool = true
@export var elevation_amplitude: float = 0.8
@export var elevation_frequency: float = 0.06

# Visual alignment / decoration
@export var tile_yaw_degrees: float = 30.0
@export_range(0.0, 0.2, 0.005) var rock_density: float = 0.03
@export_range(0.0, 0.2, 0.005) var bush_density: float = 0.05

# Internal state
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()

var grid_width: int = 13
var grid_height: int = 34
var current_yardage: int = 0
var current_unique_type: int = UniqueHoleType.NONE
var current_dogleg_type: int = 3  # 0-2 = dogleg, 3 = straight

var surface_grid: PackedInt32Array
var elevation_grid: PackedFloat32Array
var tee_tile: Vector2i = Vector2i(-1, -1)
var green_center_tile: Vector2i = Vector2i(-1, -1)
var flag_tile: Vector2i = Vector2i(-1, -1)
var green_radius: int = 3

var hole_data: Dictionary = {}

# Decorations (do not overwrite the ground surface grid)
var tree_tiles: Array[Vector2i] = []
var _tree_idx_set: Dictionary = {}
var rock_tiles: Array[Vector2i] = []
var _rock_idx_set: Dictionary = {}
var bush_tiles: Array[Vector2i] = []
var _bush_idx_set: Dictionary = {}

# Rendering
var _surface_multimesh: Dictionary = {}

# Mesh resources
const _MESH_TEE := preload("res://scenes/tiles/teebox-mesh.tres")
const _MESH_FAIRWAY := preload("res://scenes/tiles/fairway-mesh.tres")
const _MESH_ROUGH := preload("res://scenes/tiles/rough-mesh.tres")
const _MESH_DEEP_ROUGH := preload("res://scenes/tiles/deeprough-mesh.tres")
const _MESH_GREEN := preload("res://scenes/tiles/green-mesh.tres")
const _MESH_SAND := preload("res://scenes/tiles/sand-mesh.tres")
const _MESH_WATER := preload("res://scenes/tiles/water-mesh.tres")

var _mesh_tree: Mesh
var _mesh_flag: Mesh
var _mesh_rock: Mesh
var _mesh_bush: Mesh
var _tree_base_y: float = 0.0
var _rock_base_y: float = 0.0
var _bush_base_y: float = 0.0
var _flag_base_y: float = 0.0

func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_noise.frequency = elevation_frequency
	_init_feature_meshes()
	if regenerate_on_ready:
		regenerate()


func _init_feature_meshes() -> void:
	# Prefer real meshes from imported model assets; fall back to a simple procedural mesh.
	_mesh_tree = _load_mesh_from_path("res://models/Coniferous_Trees/Tree_Spruce_small_01.fbx")
	if _mesh_tree == null:
		_mesh_tree = _load_mesh_from_path("res://models/Deciduous_Trees/Tree_small_regular.fbx")
	if _mesh_tree == null:
		_mesh_tree = _create_tree_mesh()
	_tree_base_y = _compute_mesh_base_y(_mesh_tree)

	_mesh_rock = _load_mesh_from_path("res://models/Stones/Stone_average_01.fbx")
	if _mesh_rock == null:
		var rock := SphereMesh.new()
		rock.radius = 0.55
		rock.height = 1.0
		_mesh_rock = rock
	_rock_base_y = _compute_mesh_base_y(_mesh_rock)

	_mesh_bush = _load_mesh_from_path("res://models/Bushes/Bush_group_small.fbx")
	if _mesh_bush == null:
		_mesh_bush = _load_mesh_from_path("res://models/Bushes/Bush_average.fbx")
	_bush_base_y = _compute_mesh_base_y(_mesh_bush)
	
	# Flag pole mesh
	var flag_mesh := CylinderMesh.new()
	flag_mesh.top_radius = 0.04
	flag_mesh.bottom_radius = 0.04
	flag_mesh.height = 2.8
	_mesh_flag = flag_mesh
	_flag_base_y = _compute_mesh_base_y(_mesh_flag)


func _load_mesh_from_path(res_path: String) -> Mesh:
	var res := ResourceLoader.load(res_path)
	if res == null:
		return null
	if res is Mesh:
		return res
	if res is PackedScene:
		var inst := (res as PackedScene).instantiate()
		var mesh := _find_mesh_in_node(inst)
		inst.queue_free()
		return mesh
	return null


func _find_mesh_in_node(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh
	for child in node.get_children():
		var m := _find_mesh_in_node(child)
		if m != null:
			return m
	return null


func _compute_mesh_base_y(mesh: Mesh) -> float:
	if mesh == null:
		return 0.0
	var aabb := mesh.get_aabb()
	return -aabb.position.y


func _create_tree_mesh() -> Mesh:
	# Create a simple but nice-looking evergreen tree using ArrayMesh
	# Trunk + 2-3 stacked cones for foliage
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Tree parameters
	var trunk_height := 0.5
	var trunk_radius := 0.12
	var foliage_layers := 3
	var base_cone_radius := 0.8
	var cone_height := 0.9
	var cone_taper := 0.7  # Each layer shrinks by this factor
	
	# Trunk color (dark brown)
	var trunk_color := Color(0.35, 0.22, 0.1)
	# Foliage color (forest green)
	var foliage_color := Color(0.15, 0.45, 0.15)
	
	# Build trunk as simple cylinder approximation (8 sides)
	var sides := 8
	for i in range(sides):
		var angle1 := TAU * float(i) / float(sides)
		var angle2 := TAU * float(i + 1) / float(sides)
		var x1 := cos(angle1) * trunk_radius
		var z1 := sin(angle1) * trunk_radius
		var x2 := cos(angle2) * trunk_radius
		var z2 := sin(angle2) * trunk_radius
		
		st.set_color(trunk_color)
		# Bottom triangle
		st.set_normal(Vector3(cos(angle1), 0, sin(angle1)))
		st.add_vertex(Vector3(x1, 0, z1))
		st.set_normal(Vector3(cos(angle2), 0, sin(angle2)))
		st.add_vertex(Vector3(x2, 0, z2))
		st.set_normal(Vector3(cos(angle1), 0, sin(angle1)))
		st.add_vertex(Vector3(x1, trunk_height, z1))
		# Top triangle
		st.set_normal(Vector3(cos(angle2), 0, sin(angle2)))
		st.add_vertex(Vector3(x2, 0, z2))
		st.add_vertex(Vector3(x2, trunk_height, z2))
		st.set_normal(Vector3(cos(angle1), 0, sin(angle1)))
		st.add_vertex(Vector3(x1, trunk_height, z1))
	
	# Build foliage as stacked cones
	var current_height := trunk_height - 0.1
	var current_radius := base_cone_radius
	
	for layer in range(foliage_layers):
		var layer_offset := current_height
		var layer_height := cone_height * pow(0.85, layer)
		
		# Slight color variation per layer
		var layer_color := foliage_color.lerp(Color(0.2, 0.55, 0.2), float(layer) * 0.15)
		
		# Build cone (8 sides)
		var tip_y := layer_offset + layer_height
		for i in range(sides):
			var angle1 := TAU * float(i) / float(sides)
			var angle2 := TAU * float(i + 1) / float(sides)
			var x1 := cos(angle1) * current_radius
			var z1 := sin(angle1) * current_radius
			var x2 := cos(angle2) * current_radius
			var z2 := sin(angle2) * current_radius
			
			st.set_color(layer_color)
			# Cone side triangle
			var n1 := Vector3(cos(angle1), 0.5, sin(angle1)).normalized()
			var n2 := Vector3(cos(angle2), 0.5, sin(angle2)).normalized()
			st.set_normal(n1)
			st.add_vertex(Vector3(x1, layer_offset, z1))
			st.set_normal(n2)
			st.add_vertex(Vector3(x2, layer_offset, z2))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(0, tip_y, 0))
		
		current_height += layer_height * 0.55  # Overlap layers
		current_radius *= cone_taper
	
	st.generate_normals()
	return st.commit()


func regenerate() -> void:
	_clear_render()
	tree_tiles.clear()
	_tree_idx_set.clear()
	rock_tiles.clear()
	_rock_idx_set.clear()
	bush_tiles.clear()
	_bush_idx_set.clear()
	_generate_course()
	_scatter_rocks_and_foliage()
	_hydrate_hole_data()
	_build_multimesh_render()
	hole_generated.emit(hole_data)


func _scatter_rocks_and_foliage() -> void:
	# Lightweight decoration pass for visual variety.
	# Avoid placing near tee/green/fairway and never on water/sand/green/tee.
	if rock_density <= 0.0 and bush_density <= 0.0:
		return
	var deco_seed := _rng.randi() % 100000
	for y in range(grid_height):
		for x in range(grid_width):
			var surf := get_surface(x, y)
			if surf != SurfaceType.ROUGH and surf != SurfaceType.DEEP_ROUGH:
				continue
			if _is_adjacent_to_type(x, y, SurfaceType.TEE) or _is_adjacent_to_type(x, y, SurfaceType.GREEN) or _is_adjacent_to_type(x, y, SurfaceType.FAIRWAY):
				continue
			if _is_adjacent_to_type(x, y, SurfaceType.WATER) or _is_adjacent_to_type(x, y, SurfaceType.SAND):
				continue
			var dist := _distance_to_play_area(x, y)
			if dist < 2.0:
				continue
			var noise_val := _noise_at(x, y, deco_seed)
			var edge_boost := clampf((dist - 2.0) / 7.0, 0.0, 1.0)
			var rough_boost := 1.0 if surf == SurfaceType.ROUGH else 1.35
			var n := clampf((noise_val + 1.0) * 0.5, 0.0, 1.0)

			if rock_density > 0.0:
				var p_rock := rock_density * rough_boost * edge_boost * (0.35 + 0.65 * n)
				if _rng.randf() < p_rock:
					var id := _idx(x, y)
					if not _rock_idx_set.has(id):
						_rock_idx_set[id] = true
						rock_tiles.append(Vector2i(x, y))

			if bush_density > 0.0:
				var p_bush := bush_density * rough_boost * edge_boost * (0.45 + 0.55 * (1.0 - n))
				if _rng.randf() < p_bush:
					var id2 := _idx(x, y)
					if not _bush_idx_set.has(id2):
						_bush_idx_set[id2] = true
						bush_tiles.append(Vector2i(x, y))


func _place_tree(col: int, row: int) -> void:
	if col < 0 or col >= grid_width or row < 0 or row >= grid_height:
		return
	var surf := get_surface(col, row)
	if surf == SurfaceType.WATER or surf == SurfaceType.SAND or surf == SurfaceType.GREEN or surf == SurfaceType.TEE:
		return
	var id := _idx(col, row)
	if _tree_idx_set.has(id):
		return
	_tree_idx_set[id] = true
	tree_tiles.append(Vector2i(col, row))


func _place_tree_clump(start_x: int, start_y: int, size: int) -> void:
	_place_tree(start_x, start_y)
	var tiles: Array[Vector2i] = [Vector2i(start_x, start_y)]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]
	for _j in range(1, size):
		var base: Vector2i = tiles[_rng.randi() % tiles.size()]
		var dir: Vector2i = dirs[_rng.randi() % dirs.size()]
		var nx := base.x + dir.x
		var ny := base.y + dir.y
		if nx > 0 and nx < grid_width - 1 and ny > 0 and ny < grid_height - 1:
			var surf := get_surface(nx, ny)
			if surf == SurfaceType.ROUGH or surf == SurfaceType.FAIRWAY or surf == SurfaceType.DEEP_ROUGH:
				if not _is_adjacent_to_type(nx, ny, SurfaceType.TEE) and not _is_adjacent_to_type(nx, ny, SurfaceType.GREEN):
					_place_tree(nx, ny)
					tiles.append(Vector2i(nx, ny))


func get_hole_data() -> Dictionary:
	return hole_data


func get_surface(x: int, y: int) -> int:
	if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
		return -1
	return surface_grid[_idx(x, y)]


func set_cell(x: int, y: int, surface: int) -> void:
	if x >= 0 and x < grid_width and y >= 0 and y < grid_height:
		surface_grid[_idx(x, y)] = surface


func get_elevation(x: int, y: int) -> float:
	if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
		return 0.0
	return elevation_grid[_idx(x, y)]


func grid_to_world(tile: Vector2i) -> Vector3:
	var x_pos := float(tile.x) * tile_size * 1.5
	var z_pos := float(tile.y) * tile_size * sqrt(3.0) + float(tile.x % 2) * tile_size * sqrt(3.0) / 2.0
	var y_pos := get_elevation(tile.x, tile.y)
	return Vector3(x_pos, y_pos, z_pos)


func _idx(x: int, y: int) -> int:
	return y * grid_width + x


# ============================================================================
# COURSE GENERATION (ported from HexGrid)
# ============================================================================

func _generate_course() -> void:
	# Seed
	if seed_value < 0:
		_rng.randomize()
		seed_value = int(Time.get_unix_time_from_system()) ^ _rng.randi()
	_rng.seed = seed_value
	_noise.seed = seed_value & 0x7fffffff

	# Par
	if random_par:
		par = 3 + (_rng.randi() % 3)
	par = clampi(par, 3, 5)

	var config: Dictionary = PAR_CONFIG[par]
	current_yardage = config.min_yards + (_rng.randi() % (config.max_yards - config.min_yards + 1))
	grid_height = int(current_yardage / YARDS_PER_CELL)

	# Unique hole decision (30% chance)
	current_unique_type = UniqueHoleType.NONE
	if _rng.randf() < 0.30:
		var available: Array = []
		if par >= 4:
			available.append(UniqueHoleType.TRUE_DOGLEG)
		if par == 3:
			available.append(UniqueHoleType.ISLAND_GREEN)
		available.append(UniqueHoleType.S_CURVE)
		available.append(UniqueHoleType.NARROW_FAIRWAY)
		if available.size() > 0:
			current_unique_type = available[_rng.randi() % available.size()]

	# Dogleg type
	if current_unique_type == UniqueHoleType.TRUE_DOGLEG:
		current_dogleg_type = 1 + (_rng.randi() % 2)
	elif current_unique_type == UniqueHoleType.S_CURVE:
		current_dogleg_type = 3
	else:
		current_dogleg_type = _rng.randi() % 4

	# Width
	var base_width: int = config.min_width + (_rng.randi() % (config.max_width - config.min_width + 1))
	if current_unique_type == UniqueHoleType.TRUE_DOGLEG:
		grid_width = 45 + (_rng.randi() % 10)
	elif current_unique_type == UniqueHoleType.S_CURVE:
		grid_width = 40 + (_rng.randi() % 10)
	elif current_dogleg_type < 3:
		grid_width = base_width + 6 + (_rng.randi() % 8)
	elif current_unique_type == UniqueHoleType.ISLAND_GREEN:
		grid_width = maxi(base_width, 14)
	else:
		grid_width = base_width

	_init_grid()
	_generate_course_features()


func _init_grid() -> void:
	var total := grid_width * grid_height
	surface_grid = PackedInt32Array()
	surface_grid.resize(total)
	elevation_grid = PackedFloat32Array()
	elevation_grid.resize(total)
	for i in range(total):
		surface_grid[i] = SurfaceType.ROUGH
		elevation_grid[i] = 0.0


func _generate_course_features() -> void:
	var noise_seed := _rng.randi() % 1000

	# Tee at BOTTOM center (player starts here)
	var tee_col := grid_width / 2
	var tee_row := grid_height - 2
	set_cell(tee_col, tee_row, SurfaceType.TEE)
	tee_tile = Vector2i(tee_col, tee_row)

	# Green near TOP (goal)
	green_radius = 3 + (_rng.randi() % 2)
	var min_col := 1 + green_radius
	var max_col := grid_width - 2 - green_radius
	var min_row := 2 + green_radius
	var max_row := int(grid_height / 6) + green_radius
	if max_col < min_col:
		min_col = grid_width / 2
		max_col = grid_width / 2
	if max_row < min_row:
		max_row = min_row

	var green_col := min_col + (_rng.randi() % maxi(1, max_col - min_col + 1))
	var green_row := min_row + (_rng.randi() % maxi(1, max_row - min_row + 1))
	green_center_tile = Vector2i(green_col, green_row)

	_carve_disk(green_col, green_row, green_radius, SurfaceType.GREEN)

	# Fairway
	var fairway_cells: Dictionary = {}
	if current_unique_type == UniqueHoleType.ISLAND_GREEN:
		fairway_cells = _generate_island_green_hole(tee_col, tee_row, green_col, green_row)
	elif current_unique_type == UniqueHoleType.TRUE_DOGLEG:
		fairway_cells = _generate_true_dogleg_hole(tee_col, tee_row, green_col, green_row)
	elif current_unique_type == UniqueHoleType.S_CURVE:
		fairway_cells = _generate_s_curve_hole(tee_col, tee_row, green_col, green_row)
	else:
		fairway_cells = _generate_standard_fairway(tee_col, tee_row, green_col, green_row)

	if current_unique_type == UniqueHoleType.NARROW_FAIRWAY:
		_apply_narrow_fairway_trees(fairway_cells)

	# Water features
	if current_unique_type != UniqueHoleType.ISLAND_GREEN:
		_place_body_of_water()
		_place_pond()
		if _rng.randf() < 0.10:
			_surround_green_with_water(green_col, green_row)

	# Sand bunkers
	_place_greenside_bunkers(green_col, green_row)
	_place_fairway_bunkers(tee_row)

	# Strategic hazards
	_place_strategic_fairway_hazards()

	# Deep rough + trees
	_apply_deep_rough_and_trees(noise_seed)

	# Organic edge trim
	_trim_organic_edges(noise_seed)

	# Elevation
	_generate_elevation()

	# Flag
	flag_tile = green_center_tile
	# (do not overwrite green surface)


# ============================================================================
# STANDARD FAIRWAY
# ============================================================================

func _generate_standard_fairway(tee_col: int, tee_row: int, green_col: int, green_row: int) -> Dictionary:
	var fairway_cells: Dictionary = {}
	var green_fairway_gap := 1 + (_rng.randi() % 2)
	var fairway_end_row := green_row + green_radius - green_fairway_gap
	var fairway_start_row := tee_row - 2
	var start_row := mini(fairway_start_row, fairway_end_row)
	var end_row := maxi(fairway_start_row, fairway_end_row)

	var control_col := tee_col
	if current_dogleg_type == 0:
		var offset := int((_rng.randf() - 0.5) * float(grid_width) * 1.6)
		control_col = clampi(tee_col + offset, 1, grid_width - 2)
	elif current_dogleg_type == 1:
		control_col = 1
	elif current_dogleg_type == 2:
		control_col = grid_width - 2
	else:
		var offset := int((_rng.randf() - 0.5) * float(grid_width) * 0.8)
		control_col = clampi(tee_col + offset, 1, grid_width - 2)

	var num_segments := absi(end_row - start_row)
	var path_points: Array = []
	for i in range(num_segments + 1):
		var t := float(i) / float(num_segments)
		var px := int((1.0 - t) * (1.0 - t) * float(tee_col) + 2.0 * (1.0 - t) * t * float(control_col) + t * t * float(green_col))
		var py := int(lerpf(float(tee_row), float(fairway_end_row), t))
		path_points.append(Vector2(px, py))

	var min_fw := 3.0
	var max_fw := 10.0
	for i in range(path_points.size()):
		var t2 := float(i) / float(path_points.size() - 1)
		var fw_width := lerpf(min_fw, max_fw, pow(sin(t2 * PI), 1.5))
		var half := int(fw_width / 2.0)
		var center: Vector2 = path_points[i]
		for dcol in range(-half, half + 1):
			for drow in range(-half, half + 1):
				if dcol * dcol + drow * drow <= half * half:
					var fx := int(center.x) + dcol
					var fy := int(center.y) + drow
					if fx > 0 and fx < grid_width - 1 and fy > 0 and fy < grid_height - 1:
						if not _is_adjacent_to_type(fx, fy, SurfaceType.GREEN) and not _is_adjacent_to_type(fx, fy, SurfaceType.TEE):
							var surf := get_surface(fx, fy)
							if surf != SurfaceType.GREEN and surf != SurfaceType.TEE:
								set_cell(fx, fy, SurfaceType.FAIRWAY)
								fairway_cells[Vector2i(fx, fy)] = true
	return fairway_cells


# ============================================================================
# UNIQUE HOLE TYPES
# ============================================================================

func _generate_island_green_hole(tee_col: int, tee_row: int, green_col: int, green_row: int) -> Dictionary:
	var fairway_cells: Dictionary = {}
	# Small tee area
	for dcol in range(-3, 4):
		for drow in range(-2, 4):
			var col := tee_col + dcol
			var row := tee_row + drow
			if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
				var dist := sqrt(float(dcol * dcol + drow * drow))
				if dist <= 1.5:
					continue
				elif dist <= 3.0:
					set_cell(col, row, SurfaceType.ROUGH)
				elif dist <= 4.0:
					set_cell(col, row, SurfaceType.DEEP_ROUGH)
	# Fill between with water
	for col in range(grid_width):
		for row in range(grid_height):
			var surf := get_surface(col, row)
			if surf == SurfaceType.TEE or surf == SurfaceType.GREEN:
				continue
			var tee_dist := sqrt(pow(float(col - tee_col), 2) + pow(float(row - tee_row), 2))
			var green_dist := sqrt(pow(float(col - green_col), 2) + pow(float(row - green_row), 2))
			if tee_dist <= 4.0:
				continue
			if green_dist <= float(green_radius) + 2.0:
				if green_dist > float(green_radius):
					set_cell(col, row, SurfaceType.ROUGH)
				continue
			set_cell(col, row, SurfaceType.WATER)
	return fairway_cells


func _generate_true_dogleg_hole(tee_col: int, tee_row: int, _green_col: int, _green_row: int) -> Dictionary:
	var fairway_cells: Dictionary = {}
	var dogleg_left := current_dogleg_type == 1
	var vertical_dist := 18 + (_rng.randi() % 5)
	var horizontal_dist := 18 + (_rng.randi() % 5)
	var elbow_row := tee_row - vertical_dist  # Go UP from tee
	var elbow_col := tee_col

	var actual_green_col: int
	if dogleg_left:
		actual_green_col = maxi(green_radius + 3, elbow_col - horizontal_dist)
	else:
		actual_green_col = mini(grid_width - green_radius - 3, elbow_col + horizontal_dist)
	var actual_green_row := elbow_row - 5 - (_rng.randi() % 3)  # Green above elbow

	# Clear old green, place new
	for col in range(grid_width):
		for row in range(grid_height):
			if get_surface(col, row) == SurfaceType.GREEN:
				set_cell(col, row, SurfaceType.ROUGH)
	_carve_disk(actual_green_col, actual_green_row, green_radius, SurfaceType.GREEN)
	green_center_tile = Vector2i(actual_green_col, actual_green_row)

	var fw_width := 4
	var path_points: Array = []
	var p0 := Vector2(elbow_col, tee_row - 2)  # Start near tee (going up)
	var p1 := Vector2(elbow_col, elbow_row + 5)  # Approach elbow from below
	var p2 := Vector2(elbow_col, elbow_row)  # Elbow
	var p3 := Vector2(actual_green_col, elbow_row)  # Horizontal section
	var p4 := Vector2(actual_green_col, actual_green_row + green_radius + 1)  # Approach green from below

	for i in range(16):
		var t := float(i) / 15.0
		path_points.append(Vector2(lerpf(p0.x, p1.x, t), lerpf(p0.y, p1.y, t)))
	for i in range(9):
		var t := float(i) / 8.0
		var mt := 1.0 - t
		var px := mt * mt * p1.x + 2.0 * mt * t * p2.x + t * t * p3.x
		var py := mt * mt * p1.y + 2.0 * mt * t * p2.y + t * t * p3.y
		path_points.append(Vector2(px, py))
	for i in range(9):
		var t := float(i) / 8.0
		path_points.append(Vector2(lerpf(p3.x, p4.x, t), lerpf(p3.y, p4.y, t)))

	for pt in path_points:
		for dcol in range(-fw_width, fw_width + 1):
			for drow in range(-fw_width, fw_width + 1):
				if dcol * dcol + drow * drow <= fw_width * fw_width:
					var fx := int(pt.x) + dcol
					var fy := int(pt.y) + drow
					if fx > 0 and fx < grid_width - 1 and fy > 0 and fy < grid_height - 1:
						var surf := get_surface(fx, fy)
						if surf != SurfaceType.GREEN and surf != SurfaceType.TEE:
							if not _is_adjacent_to_type(fx, fy, SurfaceType.GREEN) and not _is_adjacent_to_type(fx, fy, SurfaceType.TEE):
								set_cell(fx, fy, SurfaceType.FAIRWAY)
								fairway_cells[Vector2i(fx, fy)] = true

	# Trees at inside corner
	var tree_col: int = elbow_col + (fw_width + 3 if not dogleg_left else -(fw_width + 3))
	for dcol in range(-4, 5):
		for drow in range(-5, 6):
			var col := tree_col + dcol
			var row := elbow_row + drow
			if col >= 1 and col < grid_width - 1 and row >= 1 and row < grid_height - 1:
				var surf := get_surface(col, row)
				if surf == SurfaceType.ROUGH or surf == SurfaceType.DEEP_ROUGH:
					if _rng.randf() < 0.75:
						_place_tree(col, row)
	return fairway_cells


func _generate_s_curve_hole(tee_col: int, tee_row: int, _green_col: int, green_row: int) -> Dictionary:
	var fairway_cells: Dictionary = {}
	var left_first := _rng.randf() < 0.5
	var hole_length := tee_row - green_row  # Tee is at bottom (higher row), green at top
	var quarter := hole_length / 4

	var curve1_row := tee_row - quarter  # Go UP from tee
	var curve1_offset := 12 + (_rng.randi() % 6)
	var curve1_col := clampi(tee_col + (curve1_offset if left_first else -curve1_offset), 6, grid_width - 7)

	var curve2_row := tee_row - 3 * quarter
	var curve2_offset := 12 + (_rng.randi() % 6)
	var curve2_col := clampi(tee_col + (-curve2_offset if left_first else curve2_offset), 6, grid_width - 7)

	# Reposition green to center
	for col in range(grid_width):
		for row in range(grid_height):
			if get_surface(col, row) == SurfaceType.GREEN:
				set_cell(col, row, SurfaceType.ROUGH)
	var actual_green_col := tee_col
	var actual_green_row := green_row
	_carve_disk(actual_green_col, actual_green_row, green_radius, SurfaceType.GREEN)
	green_center_tile = Vector2i(actual_green_col, actual_green_row)

	var num_seg := hole_length * 2
	var path_points: Array = []
	for i in range(num_seg + 1):
		var t := float(i) / float(num_seg)
		var py := lerpf(float(tee_row - 2), float(actual_green_row + green_radius + 1), t)  # Go from tee (bottom) to green (top)
		var mt := 1.0 - t
		var px := mt * mt * mt * float(tee_col) + 3.0 * mt * mt * t * float(curve1_col) + 3.0 * mt * t * t * float(curve2_col) + t * t * t * float(actual_green_col)
		path_points.append(Vector2(px, py))

	var fw_width := 4
	for pt in path_points:
		for dcol in range(-fw_width, fw_width + 1):
			for drow in range(-fw_width, fw_width + 1):
				if dcol * dcol + drow * drow <= fw_width * fw_width:
					var fx := int(pt.x) + dcol
					var fy := int(pt.y) + drow
					if fx > 0 and fx < grid_width - 1 and fy > 0 and fy < grid_height - 1:
						var surf := get_surface(fx, fy)
						if surf != SurfaceType.GREEN and surf != SurfaceType.TEE:
							if not _is_adjacent_to_type(fx, fy, SurfaceType.GREEN) and not _is_adjacent_to_type(fx, fy, SurfaceType.TEE):
								set_cell(fx, fy, SurfaceType.FAIRWAY)
								fairway_cells[Vector2i(fx, fy)] = true
	return fairway_cells


func _apply_narrow_fairway_trees(fairway_cells: Dictionary) -> void:
	if fairway_cells.is_empty():
		return
	var row_cols: Dictionary = {}
	for cell in fairway_cells.keys():
		if not row_cols.has(cell.y):
			row_cols[cell.y] = []
		row_cols[cell.y].append(cell.x)
	for row in row_cols.keys():
		row_cols[row].sort()

	var rows_to_narrow: Array = []
	for row in row_cols.keys():
		var cols: Array = row_cols[row]
		if cols.size() < 6:
			continue
		var near_tee := false
		var near_green := false
		for col in cols:
			if _is_adjacent_to_type(col, row, SurfaceType.TEE):
				near_tee = true
			if _is_adjacent_to_type(col, row, SurfaceType.GREEN):
				near_green = true
		if not near_tee and not near_green:
			rows_to_narrow.append(row)
	if rows_to_narrow.is_empty():
		return
	rows_to_narrow.sort()

	var num_chokes := 4 + (_rng.randi() % 3)
	var spacing := rows_to_narrow.size() / (num_chokes + 1)
	var choke_len := 4 + (_rng.randi() % 3)
	for i in range(num_chokes):
		var idx := int((i + 1) * spacing)
		if idx >= rows_to_narrow.size():
			continue
		var center_row: int = rows_to_narrow[idx]
		for drow in range(-choke_len / 2, choke_len / 2 + 1):
			var row := center_row + drow
			if not row_cols.has(row):
				continue
			var cols: Array = row_cols[row]
			if cols.size() <= 3:
				continue
			var min_c: int = cols[0]
			var max_c: int = cols[cols.size() - 1]
			var center_col := (min_c + max_c) / 2
			var keep_min := center_col - 1
			var keep_max := center_col + 1
			for col in cols:
				if col < keep_min or col > keep_max:
					var taper := absf(float(drow)) / float(choke_len / 2 + 1)
					if _rng.randf() > taper * 0.5:
						_place_tree(col, row)


# ============================================================================
# WATER FEATURES
# ============================================================================

func _place_body_of_water() -> void:
	if _rng.randf() >= 0.35:
		return
	var edge := _rng.randi() % 2
	var start_row := _rng.randi() % maxi(1, int(grid_height * 0.1))
	var end_row := grid_height - (_rng.randi() % maxi(1, int(grid_height * 0.1)))
	for row in range(start_row, end_row):
		if edge == 0:
			var row_playable := grid_width
			for col in range(grid_width):
				var surf := get_surface(col, row)
				if surf == SurfaceType.FAIRWAY or surf == SurfaceType.TEE or surf == SurfaceType.GREEN:
					row_playable = col
					break
			if row_playable > 2:
				var fill_to := mini(row_playable - 1, 10)
				for col in range(fill_to):
					set_cell(col, row, SurfaceType.WATER)
		else:
			var row_playable := -1
			for col in range(grid_width - 1, -1, -1):
				var surf := get_surface(col, row)
				if surf == SurfaceType.FAIRWAY or surf == SurfaceType.TEE or surf == SurfaceType.GREEN:
					row_playable = col
					break
			if row_playable >= 0 and row_playable < grid_width - 3:
				var fill_from := maxi(row_playable + 2, grid_width - 10)
				for col in range(fill_from, grid_width):
					set_cell(col, row, SurfaceType.WATER)


func _place_pond() -> void:
	if _rng.randf() >= 0.70:
		return
	var pond_radius := 2 + (_rng.randi() % 3)
	for _attempt in range(50):
		var pond_col := pond_radius + 1 + (_rng.randi() % maxi(1, grid_width - pond_radius * 2 - 2))
		var pond_row := int(grid_height * 0.2) + (_rng.randi() % maxi(1, int(grid_height * 0.6)))
		if _area_clear_for_hazard(pond_col, pond_row, pond_radius + 2):
			_carve_disk(pond_col, pond_row, pond_radius, SurfaceType.WATER)
			return


func _surround_green_with_water(green_col: int, green_row: int) -> void:
	for col in range(grid_width):
		for row in range(grid_height):
			if get_surface(col, row) == SurfaceType.GREEN:
				for dcol in range(-1, 2):
					for drow in range(-1, 2):
						var nc := col + dcol
						var nr := row + drow
						if (dcol != 0 or drow != 0) and nc >= 0 and nc < grid_width and nr >= 0 and nr < grid_height:
							var surf := get_surface(nc, nr)
							if surf != SurfaceType.GREEN and surf != SurfaceType.TEE:
								set_cell(nc, nr, SurfaceType.WATER)


# ============================================================================
# SAND BUNKERS
# ============================================================================

func _place_greenside_bunkers(green_col: int, green_row: int) -> void:
	if _rng.randf() >= 0.85:
		return
	var adjacent: Array = []
	for col in range(grid_width):
		for row in range(grid_height):
			var surf := get_surface(col, row)
			if surf == SurfaceType.ROUGH or surf == SurfaceType.FAIRWAY:
				if _is_adjacent_to_type(col, row, SurfaceType.GREEN):
					adjacent.append(Vector2i(col, row))
	var count := 1 + (_rng.randi() % 3)
	for _i in range(count):
		if adjacent.is_empty():
			break
		var idx := _rng.randi() % adjacent.size()
		var start: Vector2i = adjacent[idx]
		adjacent.remove_at(idx)
		_carve_clump(start.x, start.y, 2 + (_rng.randi() % 4), SurfaceType.SAND)


func _place_fairway_bunkers(tee_row: int) -> void:
	if _rng.randf() >= 0.60:
		return
	# Landing zone is 25-45% of hole length FROM tee going UP (toward green)
	var landing_start := tee_row - int(grid_height * 0.45)
	var landing_end := tee_row - int(grid_height * 0.25)
	var count := 1 + (_rng.randi() % 2)
	for _i in range(count):
		for _attempt in range(15):
			var col := 1 + (_rng.randi() % (grid_width - 2))
			var row := landing_start + (_rng.randi() % maxi(1, landing_end - landing_start))
			if _is_fairway_edge(col, row) or (get_surface(col, row) == SurfaceType.ROUGH and _is_adjacent_to_type(col, row, SurfaceType.FAIRWAY)):
				if not _is_adjacent_to_type(col, row, SurfaceType.TEE) and not _is_adjacent_to_type(col, row, SurfaceType.GREEN):
					_carve_clump(col, row, 2 + (_rng.randi() % 4), SurfaceType.SAND)
					break


# ============================================================================
# STRATEGIC HAZARDS
# ============================================================================

func _place_strategic_fairway_hazards() -> void:
	var candidates: Array = []
	for col in range(1, grid_width - 1):
		for row in range(1, grid_height - 1):
			if get_surface(col, row) == SurfaceType.FAIRWAY:
				if not _is_adjacent_to_type(col, row, SurfaceType.TEE) and not _is_adjacent_to_type(col, row, SurfaceType.GREEN):
					candidates.append(Vector2i(col, row))
	if candidates.is_empty():
		return
	# Large single tree
	if _rng.randf() < 0.30:
		var pos: Vector2i = candidates[_rng.randi() % candidates.size()]
		_place_tree(pos.x, pos.y)
		candidates.erase(pos)
	# Small tree groupings
	if _rng.randf() < 0.40 and candidates.size() > 0:
		var groupings := 1 + (_rng.randi() % 2)
		for _g in range(groupings):
			if candidates.is_empty():
				break
			var pos: Vector2i = candidates[_rng.randi() % candidates.size()]
			candidates.erase(pos)
			_place_tree_clump(pos.x, pos.y, 2 + (_rng.randi() % 3))
	# Rough patches
	if _rng.randf() < 0.25 and candidates.size() > 0:
		var patches := 1 + (_rng.randi() % 2)
		for _p in range(patches):
			if candidates.is_empty():
				break
			var pos: Vector2i = candidates[_rng.randi() % candidates.size()]
			candidates.erase(pos)
			_carve_clump(pos.x, pos.y, 2 + (_rng.randi() % 4), SurfaceType.ROUGH)


# ============================================================================
# DEEP ROUGH + TREES
# ============================================================================

func _apply_deep_rough_and_trees(noise_seed: int) -> void:
	for col in range(grid_width):
		for row in range(grid_height):
			var surf := get_surface(col, row)
			if surf != SurfaceType.ROUGH:
				continue
			var dist := _distance_to_play_area(col, row)
			var noise_val := _noise_at(col, row, noise_seed)
			var is_edge := col == 0 or col == grid_width - 1 or row == 0 or row == grid_height - 1
			var deep_thresh := 3.0 + noise_val * 1.5
			if is_edge or dist >= deep_thresh:
				var tree_thresh := 4.0 + noise_val * 1.5
				if dist >= tree_thresh and _rng.randf() < 0.45:
					set_cell(col, row, SurfaceType.DEEP_ROUGH)
					_place_tree(col, row)
				else:
					set_cell(col, row, SurfaceType.DEEP_ROUGH)
			elif dist >= 2.0 and noise_val > 0.3 and _rng.randf() < 0.25:
				set_cell(col, row, SurfaceType.DEEP_ROUGH)


func _trim_organic_edges(trim_seed: int) -> void:
	for col in range(grid_width):
		for row in range(grid_height):
			var surf := get_surface(col, row)
			if surf == SurfaceType.TEE or surf == SurfaceType.GREEN or surf == SurfaceType.FAIRWAY or surf == SurfaceType.WATER:
				continue
			var dist := _distance_to_play_area(col, row)
			var noise_val := _noise_at(col, row, trim_seed)
			var base_thresh := 7.0
			var thresh := base_thresh + noise_val * 3.0
			var col_norm := float(col) / float(grid_width - 1)
			var row_norm := float(row) / float(grid_height - 1)
			var col_from_center := absf(col_norm - 0.5)
			var corner_factor := 0.0
			if col_from_center > 0.35:
				corner_factor = (col_from_center - 0.35) * 2.0
				if row_norm < 0.1 or row_norm > 0.9:
					corner_factor *= 1.3
			thresh -= corner_factor * 1.5
			if dist > thresh:
				set_cell(col, row, -1)


# ============================================================================
# ELEVATION
# ============================================================================

func _generate_elevation() -> void:
	for col in range(grid_width):
		for row in range(grid_height):
			var n := _noise.get_noise_2d(float(col), float(row))
			elevation_grid[_idx(col, row)] = n * elevation_amplitude
	# Smooth tee + green
	_smooth_area(tee_tile, 2)
	_smooth_area(green_center_tile, green_radius + 1)


func _smooth_area(center: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := center.x + dx
			var y := center.y + dy
			if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
				continue
			var sum := 0.0
			var n := 0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var xx := x + ox
					var yy := y + oy
					if xx >= 0 and xx < grid_width and yy >= 0 and yy < grid_height:
						sum += elevation_grid[_idx(xx, yy)]
						n += 1
			if n > 0:
				elevation_grid[_idx(x, y)] = sum / float(n)


# ============================================================================
# HELPERS
# ============================================================================

func _carve_disk(cx: int, cy: int, radius: int, surface: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var x := cx + dx
				var y := cy + dy
				if x >= 0 and x < grid_width and y >= 0 and y < grid_height:
					var cur := get_surface(x, y)
					if cur == SurfaceType.TEE:
						continue
					if cur == SurfaceType.GREEN and surface != SurfaceType.GREEN:
						continue
					set_cell(x, y, surface)


func _carve_clump(start_x: int, start_y: int, size: int, surface: int) -> void:
	var tiles: Array = [Vector2i(start_x, start_y)]
	set_cell(start_x, start_y, surface)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]
	for _j in range(1, size):
		var base: Vector2i = tiles[_rng.randi() % tiles.size()]
		var dir: Vector2i = dirs[_rng.randi() % dirs.size()]
		var nx := base.x + dir.x
		var ny := base.y + dir.y
		if nx > 0 and nx < grid_width - 1 and ny > 0 and ny < grid_height - 1:
			var surf := get_surface(nx, ny)
			if surf == SurfaceType.ROUGH or surf == SurfaceType.FAIRWAY or surf == SurfaceType.DEEP_ROUGH:
				if not _is_adjacent_to_type(nx, ny, SurfaceType.TEE) and not _is_adjacent_to_type(nx, ny, SurfaceType.GREEN):
					set_cell(nx, ny, surface)
					tiles.append(Vector2i(nx, ny))


func _is_adjacent_to_type(x: int, y: int, surface: int) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if get_surface(x + dx, y + dy) == surface:
				return true
	return false


func _is_fairway_edge(x: int, y: int) -> bool:
	if get_surface(x, y) != SurfaceType.FAIRWAY:
		return false
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var surf := get_surface(x + dx, y + dy)
			if surf != SurfaceType.FAIRWAY and surf != SurfaceType.GREEN and surf != SurfaceType.TEE:
				return true
	return false


func _area_clear_for_hazard(cx: int, cy: int, radius: int) -> bool:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var nx := cx + dx
			var ny := cy + dy
			if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
				var surf := get_surface(nx, ny)
				if surf == SurfaceType.GREEN or surf == SurfaceType.TEE or surf == SurfaceType.FAIRWAY:
					return false
	return true


func _distance_to_play_area(x: int, y: int) -> float:
	var min_dist := 999.0
	for col in range(grid_width):
		for row in range(grid_height):
			var surf := get_surface(col, row)
			if surf == SurfaceType.TEE or surf == SurfaceType.FAIRWAY or surf == SurfaceType.GREEN:
				var d := sqrt(float((col - x) * (col - x) + (row - y) * (row - y)))
				if d < min_dist:
					min_dist = d
	return min_dist


func _noise_at(x: int, y: int, offset: int) -> float:
	return _noise.get_noise_2d(float(x) + float(offset), float(y))


# ============================================================================
# HYDRATE HOLE DATA
# ============================================================================

func _hydrate_hole_data() -> void:
	hole_data = {
		"seed": seed_value,
		"par": par,
		"yardage": current_yardage,
		"unique_type": current_unique_type,
		"dogleg_type": current_dogleg_type,
		"tile_size": tile_size,
		"grid_width": grid_width,
		"grid_height": grid_height,
		"tee_tile": tee_tile,
		"green_center_tile": green_center_tile,
		"green_radius": green_radius,
		"flag_tile": flag_tile,
		"surface_grid": surface_grid,
		"elevation_grid": elevation_grid,
	}


# ============================================================================
# RENDERING (MultiMesh)
# ============================================================================

func _clear_render() -> void:
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()
	_surface_multimesh.clear()


func _build_multimesh_render() -> void:
	# Hex meshes in this project are authored in a pointy-top orientation.
	# Rotating by ~30° yaw makes them flat-top (flat edge at the top).
	var tile_rot := Basis(Vector3.UP, deg_to_rad(tile_yaw_degrees))
	var deco_rng := RandomNumberGenerator.new()
	deco_rng.seed = int(seed_value ^ 0x51C0FFEE) & 0x7fffffff

	var surface_to_mesh := {
		SurfaceType.TEE: _MESH_TEE,
		SurfaceType.FAIRWAY: _MESH_FAIRWAY,
		SurfaceType.ROUGH: _MESH_ROUGH,
		SurfaceType.DEEP_ROUGH: _MESH_DEEP_ROUGH,
		SurfaceType.GREEN: _MESH_GREEN,
		SurfaceType.SAND: _MESH_SAND,
		SurfaceType.WATER: _MESH_WATER,
	}
	var surface_to_color := {
		SurfaceType.TEE: Color(0.6, 0.9, 0.6, 1.0),
		SurfaceType.FAIRWAY: Color(0.25, 0.8, 0.35, 1.0),
		SurfaceType.ROUGH: Color(0.15, 0.55, 0.2, 1.0),
		SurfaceType.DEEP_ROUGH: Color(0.08, 0.38, 0.13, 1.0),
		SurfaceType.GREEN: Color(0.2, 0.95, 0.35, 1.0),
		SurfaceType.SAND: Color(0.85, 0.75, 0.45, 1.0),
		SurfaceType.WATER: Color(0.2, 0.4, 0.85, 0.9),
	}

	var counts: Dictionary = {}
	for y in range(grid_height):
		for x in range(grid_width):
			var s := get_surface(x, y)
			if s < 0:
				continue
			if s == SurfaceType.TREE or s == SurfaceType.FLAG:
				continue
			counts[s] = int(counts.get(s, 0)) + 1

	for s in counts.keys():
		var mesh_res: Mesh = surface_to_mesh.get(s, _MESH_ROUGH)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = int(counts[s])
		mm.mesh = mesh_res

		var mi := MultiMeshInstance3D.new()
		mi.name = "Surface_%s" % str(s)
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var c: Color = surface_to_color.get(s, Color.WHITE)
		mat.albedo_color = c
		if c.a < 0.999:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat

		add_child(mi)
		_surface_multimesh[s] = mi

	var indices: Dictionary = {}
	for y in range(grid_height):
		for x in range(grid_width):
			var s := get_surface(x, y)
			if s < 0:
				continue
			if s == SurfaceType.TREE or s == SurfaceType.FLAG:
				continue
			var mi: MultiMeshInstance3D = _surface_multimesh.get(s)
			if mi == null:
				continue
			var mm: MultiMesh = mi.multimesh
			var i := int(indices.get(s, 0))
			indices[s] = i + 1
			var pos := grid_to_world(Vector2i(x, y))
			var basis := tile_rot
			var xf := Transform3D(basis, pos)
			mm.set_instance_transform(i, xf)

	# Decorations (trees, rocks, bushes, flag)
	_build_decoration_multimeshes(deco_rng)


func _build_decoration_multimeshes(deco_rng: RandomNumberGenerator) -> void:
	# Trees
	if _mesh_tree != null and tree_tiles.size() > 0:
		var tree_xforms: Array[Transform3D] = []
		tree_xforms.resize(tree_tiles.size())
		var base_scale := _scale_to_height(_mesh_tree, 2.4)
		for i in range(tree_tiles.size()):
			var t := tree_tiles[i]
			var pos := grid_to_world(t)
			pos += _rand_jitter_xz(deco_rng, tile_size * 0.35)
			pos.y += _tree_base_y
			var yaw := deco_rng.randf_range(0.0, TAU)
			var s := base_scale * deco_rng.randf_range(0.85, 1.15)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
			tree_xforms[i] = Transform3D(basis, pos)
		_add_multimesh_instances("Decor_Trees", _mesh_tree, tree_xforms, null, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

	# Rocks
	if _mesh_rock != null and rock_tiles.size() > 0:
		var rock_xforms: Array[Transform3D] = []
		rock_xforms.resize(rock_tiles.size())
		var rock_scale := _scale_to_height(_mesh_rock, 0.7)
		for i in range(rock_tiles.size()):
			var t := rock_tiles[i]
			var pos := grid_to_world(t)
			pos += _rand_jitter_xz(deco_rng, tile_size * 0.40)
			pos.y += _rock_base_y
			var yaw := deco_rng.randf_range(0.0, TAU)
			var s := rock_scale * deco_rng.randf_range(0.65, 1.25)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
			rock_xforms[i] = Transform3D(basis, pos)
		_add_multimesh_instances("Decor_Rocks", _mesh_rock, rock_xforms, null, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

	# Bushes
	if _mesh_bush != null and bush_tiles.size() > 0:
		var bush_xforms: Array[Transform3D] = []
		bush_xforms.resize(bush_tiles.size())
		var bush_scale := _scale_to_height(_mesh_bush, 0.9)
		for i in range(bush_tiles.size()):
			var t := bush_tiles[i]
			var pos := grid_to_world(t)
			pos += _rand_jitter_xz(deco_rng, tile_size * 0.35)
			pos.y += _bush_base_y
			var yaw := deco_rng.randf_range(0.0, TAU)
			var s := bush_scale * deco_rng.randf_range(0.85, 1.20)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
			bush_xforms[i] = Transform3D(basis, pos)
		_add_multimesh_instances("Decor_Bushes", _mesh_bush, bush_xforms, null, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	# Flag
	if _mesh_flag != null and flag_tile.x >= 0 and flag_tile.y >= 0:
		var pos := grid_to_world(flag_tile)
		pos.y += _flag_base_y
		var basis := Basis.IDENTITY
		var xf := Transform3D(basis, pos)
		var flag_mat := StandardMaterial3D.new()
		flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flag_mat.albedo_color = Color(0.95, 0.2, 0.2, 1.0)
		_add_multimesh_instances("Decor_Flag", _mesh_flag, [xf], flag_mat, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _add_multimesh_instances(name: String, mesh: Mesh, transforms: Array, material_override: Material, shadow_casting: int) -> void:
	if mesh == null or transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	mi.multimesh = mm
	mi.cast_shadow = shadow_casting
	if material_override != null:
		mi.material_override = material_override
	add_child(mi)
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])


func _rand_jitter_xz(rng: RandomNumberGenerator, radius: float) -> Vector3:
	if radius <= 0.0:
		return Vector3.ZERO
	var a := rng.randf_range(0.0, TAU)
	var r := sqrt(rng.randf()) * radius
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func _scale_to_height(mesh: Mesh, target_height: float) -> float:
	if mesh == null:
		return 1.0
	var h := mesh.get_aabb().size.y
	if h <= 0.0001:
		return 1.0
	return target_height / h
