extends Area3D
class_name Card3D

## 3D representation of a card.
## Handles visualization and animation.

# References
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var title_label: Label3D = $MeshInstance3D/TitleLabel
@onready var desc_label: Label3D = $MeshInstance3D/DescLabel
@onready var icon_sprite: Sprite3D = $MeshInstance3D/IconSprite
@onready var flavor_label: Label3D = $MeshInstance3D/FlavorLabel
@onready var tags_label: Label3D = $MeshInstance3D/TagsLabel
@onready var rarity_bar: MeshInstance3D = $MeshInstance3D/RarityBar

# Rarity colors
const RARITY_COLORS = {
	CardData.Rarity.COMMON: Color(0.6, 0.6, 0.6),
	CardData.Rarity.UNCOMMON: Color(0.2, 0.6, 0.2),
	CardData.Rarity.RARE: Color(0.2, 0.4, 0.8),
	CardData.Rarity.LEGENDARY: Color(0.9, 0.7, 0.1)
}

# Data
var card_instance: CardInstance = null

# State
var target_position: Vector3
var target_rotation: Vector3
var is_animating: bool = false

# Constants
const CARD_SIZE = Vector3(4.0, 2.02, 0.05) # World units (approx aspect ratio of 953x482)
const CORNER_RADIUS = 0.25
const CORNER_SEGMENTS = 8

# Static cache for the mesh
static var _shared_rounded_mesh: ArrayMesh

# Texture overrides
var front_texture_override: Texture2D
var back_texture_override: Texture2D

func _ready() -> void:
	# Setup collision shape if not present (for clicks)
	if not has_node("CollisionShape3D"):
		var shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = CARD_SIZE
		shape.shape = box
		add_child(shape)
	
	_setup_rounded_mesh()
	
	if card_instance:
		_update_visuals()


func setup(card: CardInstance) -> void:
	card_instance = card
	if is_inside_tree():
		_update_visuals()


func set_textures(front: Texture2D, back: Texture2D) -> void:
	front_texture_override = front
	back_texture_override = back
	if is_inside_tree():
		_setup_rounded_mesh()


func _update_visuals() -> void:
	if not card_instance:
		return
		
	if title_label:
		title_label.text = card_instance.data.card_name
		
	if rarity_bar:
		var mat = rarity_bar.get_active_material(0)
		if mat:
			# Duplicate to ensure unique instance
			mat = mat.duplicate()
			mat.albedo_color = RARITY_COLORS.get(card_instance.data.rarity, Color.GRAY)
			rarity_bar.set_surface_override_material(0, mat)
		
	if desc_label:
		desc_label.text = card_instance.get_full_description()
		
	if flavor_label:
		flavor_label.text = card_instance.data.flavor_text
		flavor_label.visible = not card_instance.data.flavor_text.is_empty()
		
	if tags_label:
		var tags_text = ""
		for tag in card_instance.data.tags:
			tags_text += "#" + tag + " "
		tags_label.text = tags_text.strip_edges()
		tags_label.visible = not tags_text.is_empty()
		
	if icon_sprite and card_instance.data.icon:
		icon_sprite.texture = card_instance.data.icon
		icon_sprite.visible = true
	elif icon_sprite:
		icon_sprite.visible = false
		
	# TODO: Set texture based on card type/data
	# For now, we rely on the material set in the scene


func _setup_rounded_mesh() -> void:
	# Handle the transition from the scene-based BoxMesh to our procedural mesh
	var back_mesh_node = mesh_instance.get_node_or_null("BackMesh")
	var front_mat = mesh_instance.get_surface_override_material(0)
	var back_mat = null
	
	if back_mesh_node:
		back_mat = back_mesh_node.get_surface_override_material(0)
		back_mesh_node.queue_free()
	
	# Generate or retrieve mesh
	if not _shared_rounded_mesh:
		_shared_rounded_mesh = _generate_rounded_box(CARD_SIZE, CORNER_RADIUS, CORNER_SEGMENTS)
	
	mesh_instance.mesh = _shared_rounded_mesh
	
	# Assign materials and disable transparency since geometry handles the shape
	if front_mat:
		# Duplicate material to ensure uniqueness per card instance
		front_mat = front_mat.duplicate()
		
		front_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		front_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		front_mat.uv1_scale = Vector3(1, 1, 1)
		front_mat.uv1_offset = Vector3(0, 0, 0)
		# Force correct texture to be sure
		# Swapping textures based on user report that front shows back
		if back_texture_override:
			front_mat.albedo_texture = back_texture_override
		else:
			front_mat.albedo_texture = load("res://textures/card-back.png")
		mesh_instance.set_surface_override_material(0, front_mat)
	
	if back_mat:
		# Duplicate material to ensure uniqueness per card instance
		back_mat = back_mat.duplicate()
		
		back_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		back_mat.uv1_scale = Vector3(1, 1, 1)
		back_mat.uv1_offset = Vector3(0, 0, 0)
		# Force correct texture to be sure
		if front_texture_override:
			back_mat.albedo_texture = front_texture_override
		else:
			back_mat.albedo_texture = load("res://textures/card-front.png")
		mesh_instance.set_surface_override_material(1, back_mat)
	
	# Edge material
	var edge_mat = StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.9, 0.9, 0.9)
	edge_mat.roughness = 0.8
	mesh_instance.set_surface_override_material(2, edge_mat)


func _generate_rounded_box(size: Vector3, radius: float, segments: int) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var half_size = size / 2.0
	var half_depth = size.z / 2.0
	
	# Generate profile points (CCW)
	var profile_points = PackedVector2Array()
	var profile_uvs = PackedVector2Array()
	
	# Corners: TR, TL, BL, BR (CCW order)
	var centers = [
		Vector2(half_size.x - radius, half_size.y - radius),  # TR
		Vector2(-half_size.x + radius, half_size.y - radius), # TL
		Vector2(-half_size.x + radius, -half_size.y + radius),# BL
		Vector2(half_size.x - radius, -half_size.y + radius)  # BR
	]
	
	var start_angles = [0.0, PI/2, PI, 3*PI/2]
	
	for i in range(4):
		var center = centers[i]
		var start = start_angles[i]
		for j in range(segments + 1):
			var theta = start + (PI/2 * j / segments)
			var p = center + Vector2(cos(theta), sin(theta)) * radius
			profile_points.append(p)
			
			var u = (p.x + half_size.x) / size.x
			var v = (-p.y + half_size.y) / size.y
			profile_uvs.append(Vector2(u, v))
	
	# --- Surface 0: Front ---
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, 1))
	
	var center_uv = Vector2(0.5, 0.5)
	
	for i in range(profile_points.size()):
		var p1 = profile_points[i]
		var p2 = profile_points[(i + 1) % profile_points.size()]
		var uv1 = profile_uvs[i]
		var uv2 = profile_uvs[(i + 1) % profile_uvs.size()]
		
		st.set_uv(center_uv)
		st.add_vertex(Vector3(0, 0, half_depth))
		
		st.set_uv(uv1)
		st.add_vertex(Vector3(p1.x, p1.y, half_depth))
		
		st.set_uv(uv2)
		st.add_vertex(Vector3(p2.x, p2.y, half_depth))
		
	st.commit(mesh)
	
	# --- Surface 1: Back ---
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, -1))
	
	for i in range(profile_points.size()):
		var p1 = profile_points[i]
		var p2 = profile_points[(i + 1) % profile_points.size()]
		var uv1 = profile_uvs[i]
		var uv2 = profile_uvs[(i + 1) % profile_uvs.size()]
		
		# Flip U for back face so texture isn't mirrored
		var b_center_uv = Vector2(1.0 - center_uv.x, center_uv.y)
		var b_uv1 = Vector2(1.0 - uv1.x, uv1.y)
		var b_uv2 = Vector2(1.0 - uv2.x, uv2.y)
		
		st.set_uv(b_center_uv)
		st.add_vertex(Vector3(0, 0, -half_depth))
		
		st.set_uv(b_uv2)
		st.add_vertex(Vector3(p2.x, p2.y, -half_depth))
		
		st.set_uv(b_uv1)
		st.add_vertex(Vector3(p1.x, p1.y, -half_depth))
		
	st.commit(mesh)
	
	# --- Surface 2: Edges ---
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for i in range(profile_points.size()):
		var p1 = profile_points[i]
		var p2 = profile_points[(i + 1) % profile_points.size()]
		
		var v1 = Vector3(p1.x, p1.y, half_depth)
		var v2 = Vector3(p2.x, p2.y, half_depth)
		var v3 = Vector3(p2.x, p2.y, -half_depth)
		var v4 = Vector3(p1.x, p1.y, -half_depth)
		
		var segment_vec = p2 - p1
		var normal_2d = Vector2(segment_vec.y, -segment_vec.x).normalized()
		var normal = Vector3(normal_2d.x, normal_2d.y, 0)
		
		st.set_normal(normal)
		
		st.add_vertex(v1)
		st.add_vertex(v2)
		st.add_vertex(v4)
		
		st.add_vertex(v2)
		st.add_vertex(v3)
		st.add_vertex(v4)
		
	st.commit(mesh)
	
	return mesh


func animate_move_to(pos: Vector3, rot: Vector3, duration: float = 0.5, delay: float = 0.0, arc_height: float = 0.0) -> void:
	is_animating = true
	var tween = create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	
	tween.set_parallel(true)
	
	# Rotation
	tween.tween_property(self, "rotation", rot, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	if arc_height > 0.0:
		var start_pos = position
		tween.tween_method(func(t: float):
			var current_base = start_pos.lerp(pos, t)
			var height_offset = Vector3(0, arc_height * 4 * t * (1 - t), 0)
			position = current_base + height_offset
		, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		tween.tween_property(self, "position", pos, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	tween.chain().tween_callback(func(): is_animating = false)


func animate_flip(duration: float = 0.4) -> void:
	var tween = create_tween()
	var target_rot = rotation
	target_rot.x -= PI
	
	var peak_y = position.y + 1.0
	var end_y = position.y
	
	tween.set_parallel(true)
	tween.tween_property(self, "rotation", target_rot, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	tween.tween_property(self, "position:y", peak_y, duration/2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "position:y", end_y, duration/2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
