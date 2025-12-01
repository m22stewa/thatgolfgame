extends Node3D
class_name GolfBall

## GolfBall - Stylized golf ball with shader support
## Attach shaders and effects here, used by hex_grid for gameplay

# Shader material reference (set in scene or via code)
@export var ball_material: ShaderMaterial = null

# Trail effect (optional)
@export var enable_trail: bool = true
@export var trail_color: Color = Color(1.0, 1.0, 1.0, 0.5)

# Reference to the actual mesh
var ball_mesh: MeshInstance3D = null


func _ready() -> void:
	# Find the mesh in the model
	_find_and_setup_mesh()
	
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
