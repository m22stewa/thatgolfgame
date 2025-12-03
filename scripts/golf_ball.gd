extends Node3D
class_name GolfBall

## GolfBall - Stylized golf ball with shader support
## Attach shaders and effects here, used by hex_grid for gameplay

# Shader material reference (set in scene or via code)
@export var ball_material: ShaderMaterial = null

# Trail effect (optional)
@export var enable_trail: bool = true
@export var trail_color: Color = Color(1.0, 1.0, 1.0, 0.5)

# Ground shadow settings
@export var enable_shadow: bool = true
@export var shadow_base_size: float = 0.6  # Size when close to ground (roughly ball size)
@export var shadow_min_size: float = 0.3   # Size when at max height
@export var shadow_max_height: float = 15.0  # Height at which shadow is smallest
@export var shadow_opacity: float = 0.5

# Reference to the actual mesh
var ball_mesh: MeshInstance3D = null

# Shadow components
var shadow_mesh: MeshInstance3D = null
var shadow_material: StandardMaterial3D = null
var shadow_tween: Tween = null
var shadow_visible: bool = false


func _ready() -> void:
	# Find the mesh in the model
	_find_and_setup_mesh()
	
	# Create ground shadow
	if enable_shadow:
		_create_shadow()
	
	# Apply shader material if set
	if ball_material:
		apply_material(ball_material)


func _find_and_setup_mesh() -> void:
	"""Find the MeshInstance3D in the imported model"""
	# GLB imports usually have the mesh as a child
	var model = get_node_or_null("Model")
	if model:
		ball_mesh = _find_mesh_recursive(model)
	
	if ball_mesh == null:
		# Try finding any MeshInstance3D child
		ball_mesh = _find_mesh_recursive(self)
	
	if ball_mesh:
		print("GolfBall: Found mesh - ", ball_mesh.name)
	else:
		push_warning("GolfBall: Could not find MeshInstance3D in model")


func _create_shadow() -> void:
	"""Create a ground shadow mesh that follows the ball"""
	# Create a circular mesh for the shadow using a cylinder (flat disc)
	var circle_mesh = CylinderMesh.new()
	circle_mesh.top_radius = shadow_base_size / 2.0
	circle_mesh.bottom_radius = shadow_base_size / 2.0
	circle_mesh.height = 0.01  # Very flat
	circle_mesh.radial_segments = 32  # Smooth circle
	circle_mesh.rings = 1
	
	# Create shadow material (dark, semi-transparent)
	shadow_material = StandardMaterial3D.new()
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.albedo_color = Color(0.0, 0.0, 0.0, shadow_opacity)
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Disable depth test so shadow renders on top of ground
	shadow_material.no_depth_test = true
	
	# Create the mesh instance
	shadow_mesh = MeshInstance3D.new()
	shadow_mesh.mesh = circle_mesh
	shadow_mesh.material_override = shadow_material
	shadow_mesh.name = "GroundShadow"
	shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Add as child - we'll position it in world space
	add_child(shadow_mesh)
	shadow_mesh.top_level = true  # Don't inherit parent transform
	shadow_mesh.visible = false  # Start hidden, only show during flight
	print("GolfBall: Shadow created")


func update_shadow(ground_y: float = 0.0) -> void:
	"""Update shadow position and size based on ball height.
	   Call this every frame during ball flight.
	   ground_y: the Y position of the ground below the ball"""
	if shadow_mesh == null or not enable_shadow:
		return
	
	# Show the shadow (handles fade in)
	show_shadow()
	
	# Position shadow on ground below ball (slightly above to avoid z-fighting)
	shadow_mesh.global_position = Vector3(global_position.x, ground_y + 0.05, global_position.z)
	
	# Keep shadow flat (no rotation from ball)
	shadow_mesh.global_rotation = Vector3.ZERO
	
	# Calculate height above ground
	var height = global_position.y - ground_y
	
	# Scale shadow based on height (smaller when higher, larger when closer)
	var height_factor = clamp(1.0 - (height / shadow_max_height), 0.3, 1.0)
	var scale_factor = lerp(shadow_min_size / shadow_base_size, 1.0, height_factor)
	shadow_mesh.scale = Vector3(scale_factor, 1.0, scale_factor)
	
	# Fade shadow based on height (fainter when higher)
	if shadow_tween == null or not shadow_tween.is_running():
		var alpha = shadow_opacity * height_factor
		shadow_material.albedo_color.a = alpha


func hide_shadow() -> void:
	"""Hide the shadow with fade out"""
	if shadow_mesh == null or not shadow_visible:
		return
	
	shadow_visible = false
	
	# Kill any existing tween
	if shadow_tween and shadow_tween.is_valid():
		shadow_tween.kill()
	
	# Fade out the shadow
	shadow_tween = create_tween()
	shadow_tween.tween_property(shadow_material, "albedo_color:a", 0.0, 0.2)
	shadow_tween.tween_callback(func(): shadow_mesh.visible = false)


func show_shadow() -> void:
	"""Show the shadow with fade in"""
	if shadow_mesh == null or shadow_visible:
		return
	
	shadow_visible = true
	
	# Kill any existing tween
	if shadow_tween and shadow_tween.is_valid():
		shadow_tween.kill()
	
	# Make visible and fade in
	shadow_mesh.visible = true
	shadow_tween = create_tween()
	shadow_tween.tween_property(shadow_material, "albedo_color:a", shadow_opacity, 0.15)


func _find_mesh_recursive(node: Node) -> MeshInstance3D:
	"""Recursively search for a MeshInstance3D"""
	if node is MeshInstance3D and node.mesh != null:
		return node
	
	for child in node.get_children():
		var result = _find_mesh_recursive(child)
		if result:
			return result
	
	return null


func apply_material(material: Material) -> void:
	"""Apply a material to the ball mesh"""
	if ball_mesh:
		ball_mesh.material_override = material
		print("GolfBall: Material applied")
	else:
		push_warning("GolfBall: No mesh found to apply material to")


func set_color(color: Color) -> void:
	"""Set the base color of the ball (if using shader)"""
	if ball_mesh and ball_mesh.material_override is ShaderMaterial:
		var mat = ball_mesh.material_override as ShaderMaterial
		mat.set_shader_parameter("base_color", color)


func set_shadow_color(color: Color) -> void:
	"""Set the shadow color (if using shader)"""
	if ball_mesh and ball_mesh.material_override is ShaderMaterial:
		var mat = ball_mesh.material_override as ShaderMaterial
		mat.set_shader_parameter("shadow_color", color)


func set_rim_intensity(intensity: float) -> void:
	"""Set rim light intensity (if using shader)"""
	if ball_mesh and ball_mesh.material_override is ShaderMaterial:
		var mat = ball_mesh.material_override as ShaderMaterial
		mat.set_shader_parameter("rim_intensity", intensity)


func flash(flash_color: Color = Color.WHITE, duration: float = 0.2) -> void:
	"""Flash the ball a color (for effects like scoring)"""
	if ball_mesh == null:
		return
	
	var original_material = ball_mesh.material_override
	
	# Create a simple flash material
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = flash_color
	flash_mat.emission_enabled = true
	flash_mat.emission = flash_color
	flash_mat.emission_energy_multiplier = 2.0
	
	ball_mesh.material_override = flash_mat
	
	await get_tree().create_timer(duration).timeout
	
	ball_mesh.material_override = original_material


func pulse(scale_amount: float = 1.2, duration: float = 0.3) -> void:
	"""Pulse the ball size (for effects)"""
	var original_scale = scale
	var target_scale = original_scale * scale_amount
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(self, "scale", target_scale, duration * 0.3)
	tween.tween_property(self, "scale", original_scale, duration * 0.7)
	
	await tween.finished



