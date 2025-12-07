extends Node3D
## Spawns random trees with varied scale, rotation, and appearance
## Attach this to a Node3D and call spawn_trees() or let it auto-spawn in _ready()

# Default tree scene (used if no tree_scenes are set)
const DEFAULT_TREE = preload("res://scenes/tiles/trees.tscn")

# Configuration
@export_group("Tree Models")
## Array of tree scenes to randomly choose from. Add your .tscn files here in the Inspector.
@export var tree_scenes: Array[PackedScene] = []

@export_group("Spawn Settings")
@export var auto_spawn: bool = true
@export var tree_count: int = 10
@export var spawn_radius: float = 5.0
@export var min_spacing: float = 0.8  # Minimum distance between trees

@export_group("Scale Variation")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.4
@export var scale_y_bias: float = 1.2  # Multiplier for height variation

@export_group("Rotation Variation")
@export var random_y_rotation: bool = true
@export var random_tilt: bool = true
@export var max_tilt_degrees: float = 8.0  # Max lean angle

@export_group("Foliage Color Variation")
@export var vary_foliage_color: bool = true
@export var foliage_colors: Array[Color] = [
	Color(0.13, 0.33, 0.25, 1),   # Dark green
	Color(0.2, 0.45, 0.15, 1),    # Forest green
	Color(0.15, 0.35, 0.1, 1),    # Deep green
	Color(0.25, 0.5, 0.2, 1),     # Bright green
	Color(0.18, 0.4, 0.12, 1),    # Natural green
]

# Internal tracking
var spawned_trees: Array[Node3D] = []
var tree_positions: Array[Vector3] = []


func _ready() -> void:
	if auto_spawn:
		spawn_trees()


## Spawn trees randomly within the configured radius
func spawn_trees() -> void:
	clear_trees()
	
	for i in range(tree_count):
		var pos = _get_random_position()
		if pos != Vector3.INF:  # Valid position found
			_spawn_single_tree(pos)


## Spawn trees at specific positions with random variations
func spawn_trees_at_positions(positions: Array[Vector3]) -> void:
	clear_trees()
	
	for pos in positions:
		_spawn_single_tree(pos)


## Spawn a single tree with random properties
func _spawn_single_tree(pos: Vector3) -> void:
	# Pick a random tree scene from the array, or use default
	var tree_scene: PackedScene
	if tree_scenes.size() > 0:
		tree_scene = tree_scenes[randi() % tree_scenes.size()]
	else:
		tree_scene = DEFAULT_TREE
	
	var tree_instance = tree_scene.instantiate()
	add_child(tree_instance)
	
	# Position
	tree_instance.position = pos
	tree_positions.append(pos)
	
	# Random scale with height bias
	var base_scale = randf_range(min_scale, max_scale)
	var scale_y = base_scale * randf_range(0.9, scale_y_bias)
	tree_instance.scale = Vector3(base_scale, scale_y, base_scale)
	
	# Random rotation
	var rotation_euler = Vector3.ZERO
	if random_y_rotation:
		rotation_euler.y = randf() * TAU  # Full 360 degree rotation
	if random_tilt:
		rotation_euler.x = deg_to_rad(randf_range(-max_tilt_degrees, max_tilt_degrees))
		rotation_euler.z = deg_to_rad(randf_range(-max_tilt_degrees, max_tilt_degrees))
	tree_instance.rotation = rotation_euler

	# Vary foliage color if enabled
	if vary_foliage_color and foliage_colors.size() > 0:
		_apply_random_foliage_color(tree_instance)
	
	spawned_trees.append(tree_instance)


## Apply a random foliage color to the tree's shader materials
func _apply_random_foliage_color(tree: Node3D) -> void:
	var color = foliage_colors[randi() % foliage_colors.size()]
	
	# Find MeshInstance3D nodes with shader materials
	for child in tree.get_children():
		if child is MeshInstance3D and child.material_overlay:
			var mat = child.material_overlay
			if mat is ShaderMaterial:
				# Create a unique copy to avoid sharing
				var new_mat = mat.duplicate()
				new_mat.set_shader_parameter("foliage_colour", color)
				child.material_overlay = new_mat
		
		# Also check CSGSphere3D nodes (foliage spheres)
		if child is CSGSphere3D and child.material:
			var sphere_mat = child.material
			if sphere_mat is StandardMaterial3D:
				var new_mat = sphere_mat.duplicate()
				# Vary the green channel slightly
				var base_color = new_mat.albedo_color
				var hue_shift = randf_range(-0.05, 0.05)
				var sat_shift = randf_range(-0.1, 0.1)
				var val_shift = randf_range(-0.15, 0.15)
				var h = base_color.h + hue_shift
				var s = clamp(base_color.s + sat_shift, 0.3, 1.0)
				var v = clamp(base_color.v + val_shift, 0.2, 1.0)
				new_mat.albedo_color = Color.from_hsv(h, s, v)
				child.material = new_mat


## Get a random position that respects minimum spacing
func _get_random_position() -> Vector3:
	var max_attempts = 30
	
	for _attempt in range(max_attempts):
		var angle = randf() * TAU
		var distance = sqrt(randf()) * spawn_radius  # sqrt for uniform distribution
		var pos = Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)
		
		# Check spacing from existing trees
		var valid = true
		for existing_pos in tree_positions:
			if pos.distance_to(existing_pos) < min_spacing:
				valid = false
				break
		
		if valid:
			return pos
	
	return Vector3.INF  # No valid position found


## Clear all spawned trees
func clear_trees() -> void:
	for tree in spawned_trees:
		if is_instance_valid(tree):
			tree.queue_free()
	spawned_trees.clear()
	tree_positions.clear()


## Spawn trees in a grid pattern with randomization
func spawn_trees_grid(cols: int, rows: int, cell_size: float, jitter: float = 0.3) -> void:
	clear_trees()
	
	var offset_x = -cols * cell_size * 0.5
	var offset_z = -rows * cell_size * 0.5
	
	for col in range(cols):
		for row in range(rows):
			# Skip some cells randomly for natural look
			if randf() < 0.3:
				continue
			
			var base_pos = Vector3(
				offset_x + col * cell_size + cell_size * 0.5,
				0,
				offset_z + row * cell_size + cell_size * 0.5
			)
			
			# Add jitter
			base_pos.x += randf_range(-jitter, jitter) * cell_size
			base_pos.z += randf_range(-jitter, jitter) * cell_size
			
			_spawn_single_tree(base_pos)


## Spawn a cluster of trees around a center point
func spawn_tree_cluster(center: Vector3, count: int, cluster_radius: float) -> void:
	for i in range(count):
		var angle = randf() * TAU
		var distance = sqrt(randf()) * cluster_radius
		var pos = center + Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)
		_spawn_single_tree(pos)
