@tool
extends Node3D
class_name DeckView3D

## 3D View for the Deck and Active Slot.
## Replaces DeckUI.

# References
var deck_manager: DeckManager = null
var card_scene: PackedScene = preload("res://scenes/card_3d.tscn")

# Scene Nodes
@onready var deck_anchor: Marker3D = $DeckAnchor
@onready var slot_anchor: Marker3D = $SlotAnchor
@onready var discard_anchor: Marker3D = $DiscardAnchor # New anchor for used clubs
@onready var camera: Camera3D = $Camera3D
@onready var deck_pile_mesh: MeshInstance3D = $DeckAnchor/DeckPileVisual

# State
var active_card_node: Card3D = null
var played_cards: Array[Card3D] = []
var discarded_cards: Array[Card3D] = [] # Legacy support, kept for safety but unused

# Card inspection state
var inspected_card: Card3D = null
var inspected_card_original_pos: Vector3 = Vector3.ZERO
var inspected_card_original_rot: Vector3 = Vector3.ZERO
var inspected_card_original_scale: Vector3 = Vector3.ONE
var inspection_overlay: MeshInstance3D = null

# Cursor hover state
var _last_hover_target: String = ""  # "deck", "card", or ""

# Configuration
@export_group("Visuals")
@export var card_back_texture: Texture2D = preload("res://textures/cards/card-back.png")
@export var card_front_texture: Texture2D = preload("res://textures/cards/card-front.png")

@export var lock_aspect_ratio: bool = true:
	set(value):
		lock_aspect_ratio = value
		if lock_aspect_ratio and deck_size.y > 0:
			_aspect_ratio = deck_size.x / deck_size.y

var _aspect_ratio: float = 4.0 / 2.02

@export var deck_size: Vector3 = Vector3(4.0, 2.02, 0.5):
	set(value):
		if lock_aspect_ratio and deck_size != Vector3.ZERO:
			var x_diff = abs(value.x - deck_size.x)
			var y_diff = abs(value.y - deck_size.y)
			
			if x_diff > 0.001 and y_diff < 0.001:
				value.y = value.x / _aspect_ratio
			elif y_diff > 0.001 and x_diff < 0.001:
				value.x = value.y * _aspect_ratio
		
		deck_size = value
		if is_inside_tree():
			_setup_deck_mesh()

@export var corner_radius: float = 0.25
@export var corner_segments: int = 8

enum InteractionMode { DRAW_TOP, SELECT_FROM_UI }
var interaction_mode: InteractionMode = InteractionMode.DRAW_TOP

# Signals
signal request_club_selection()
signal card_inspection_requested(card_instance: CardInstance)  # Emitted when a card is clicked for inspection
signal inspection_started()  # DEPRECATED: No longer emitted - card animates within viewport
signal inspection_closed()   # DEPRECATED: No longer emitted - card animates within viewport

func _ready() -> void:
	# Setup deck pile visual
	_setup_deck_mesh()
	
	# Increase deck click area for better responsiveness
	_setup_deck_click_area()
	
	# Create discard anchor if missing (for backward compatibility)
	if not has_node("DiscardAnchor"):
		discard_anchor = Marker3D.new()
		discard_anchor.name = "DiscardAnchor"
		add_child(discard_anchor)
		# Position it to the left of the deck (opposite to slot)
		discard_anchor.position = Vector3(-4.0, 0, 0) 
		discard_anchor.rotation = deck_anchor.rotation


func _setup_deck_click_area() -> void:
	"""Setup deck click area to match the visual deck size"""
	var click_area = get_node_or_null("DeckAnchor/DeckClickArea")
	if not click_area:
		return
	
	var collision_shape = click_area.get_node_or_null("CollisionShape3D")
	if not collision_shape or not collision_shape.shape:
		return
	
	# Create box matching deck size exactly
	var box_shape = BoxShape3D.new()
	box_shape.size = deck_size
	collision_shape.shape = box_shape

func _setup_deck_mesh() -> void:
	var mesh = _generate_rounded_box(deck_size, corner_radius, corner_segments)
	
	var meshes = []
	if deck_pile_mesh:
		meshes.append(deck_pile_mesh)
	
	if has_node("DeckAnchor/DeckPileVisual2"):
		meshes.append(get_node("DeckAnchor/DeckPileVisual2"))
		
	for m in meshes:
		# Capture existing edge material BEFORE replacing the mesh (mesh replacement clears overrides)
		var existing_edge_mat = m.get_surface_override_material(2)
		
		m.mesh = mesh
		
		# Setup materials
		# Surface 0: Top (Back of card visual)
		# Surface 1: Bottom (Back of card visual)
		# Surface 2: Edges
		
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if card_back_texture:
			mat.albedo_texture = card_back_texture
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED # Disable culling to debug visibility
		
		m.set_surface_override_material(0, mat)
		m.set_surface_override_material(1, mat)
		
		# Use existing edge material from scene if it was set, otherwise create a dark one
		if existing_edge_mat:
			m.set_surface_override_material(2, existing_edge_mat)
		else:
			# No material was set - create a default dark edge
			var edge_mat = StandardMaterial3D.new()
			edge_mat.albedo_color = Color(0.1, 0.1, 0.1)  # Dark gray/black
			edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.set_surface_override_material(2, edge_mat)
		
		# Position mesh so Z=0 is at the bottom of the pile
		# Original pile was centered at 0, thickness 0.5. So bottom was at -0.25.
		m.position.z = -deck_size.z / 2.0
		
	_update_deck_height()


func _update_deck_height() -> void:
	if not deck_manager:
		return
		
	var count = deck_manager.get_draw_pile_count()
	var max_cards = deck_manager.deck_size
	if max_cards <= 0: max_cards = 20 # Fallback
	
	var ratio = float(count) / float(max_cards)
	ratio = clamp(ratio, 0.0, 1.0)
	
	# Scale Z axis
	# We want at least a tiny bit of thickness if count > 0
	if count > 0 and ratio < 0.1:
		ratio = 0.1
	elif count == 0:
		ratio = 0.0
		
	if deck_pile_mesh:
		deck_pile_mesh.scale.z = ratio
		
	if has_node("DeckAnchor/DeckPileVisual2"):
		get_node("DeckAnchor/DeckPileVisual2").scale.z = ratio


func _generate_rounded_box(size: Vector3, radius: float, segments: int) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var half_size = size / 2.0
	var depth = size.z
	
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
	
	# --- Surface 0: Front (Top) ---
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
		st.add_vertex(Vector3(0, 0, depth))
		
		st.set_uv(uv1)
		st.add_vertex(Vector3(p1.x, p1.y, depth))
		
		st.set_uv(uv2)
		st.add_vertex(Vector3(p2.x, p2.y, depth))
		
	st.commit(mesh)
	
	# --- Surface 1: Back (Bottom) ---
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, -1))
	
	for i in range(profile_points.size()):
		var p1 = profile_points[i]
		var p2 = profile_points[(i + 1) % profile_points.size()]
		var uv1 = profile_uvs[i]
		var uv2 = profile_uvs[(i + 1) % profile_uvs.size()]
		
		# Flip U for back face
		var b_center_uv = Vector2(1.0 - center_uv.x, center_uv.y)
		var b_uv1 = Vector2(1.0 - uv1.x, uv1.y)
		var b_uv2 = Vector2(1.0 - uv2.x, uv2.y)
		
		st.set_uv(b_center_uv)
		st.add_vertex(Vector3(0, 0, 0.0))
		
		st.set_uv(b_uv2)
		st.add_vertex(Vector3(p2.x, p2.y, 0.0))
		
		st.set_uv(b_uv1)
		st.add_vertex(Vector3(p1.x, p1.y, 0.0))
		
	st.commit(mesh)
	
	# --- Surface 2: Edges ---
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for i in range(profile_points.size()):
		var p1 = profile_points[i]
		var p2 = profile_points[(i + 1) % profile_points.size()]
		
		var v1 = Vector3(p1.x, p1.y, depth)
		var v2 = Vector3(p2.x, p2.y, depth)
		var v3 = Vector3(p2.x, p2.y, 0.0)
		var v4 = Vector3(p1.x, p1.y, 0.0)
		
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

func setup(manager: DeckManager) -> void:
	deck_manager = manager
	
	if deck_manager:
		deck_manager.active_cards_changed.connect(_on_active_cards_changed)
		deck_manager.card_drawn.connect(_on_card_drawn)
		
		# Initial state
		if not deck_manager.get_active_cards().is_empty():
			_spawn_active_card(deck_manager.get_active_cards().back())


func _unhandled_input(event: InputEvent) -> void:
	# Skip if input is disabled (e.g., when used in CombinedDeckView)
	if not is_processing_unhandled_input():
		return
	# Skip if not visible
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_check_click(event.position)
	elif event is InputEventMouseMotion:
		_check_hover(event.position)


func _check_hover(screen_pos: Vector2) -> void:
	"""Check what the mouse is hovering over and update cursor"""
	if not camera or not is_processing_unhandled_input() or not visible:
		return
	
	var cursor_manager = get_node_or_null("/root/CursorManager")
	if not cursor_manager:
		return
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	
	var result = space_state.intersect_ray(query)
	
	var new_hover_target = ""
	if result:
		var collider = result.collider
		if collider.name == "DeckClickArea":
			new_hover_target = "deck"
		elif collider is Card3D:
			new_hover_target = "card"
	
	# Only update cursor if hover target changed
	if new_hover_target != _last_hover_target:
		_last_hover_target = new_hover_target
		match new_hover_target:
			"deck":
				cursor_manager.set_hand_open()
			"card":
				cursor_manager.set_zoom()
			_:
				cursor_manager.set_default()


func _check_click(screen_pos: Vector2) -> void:
	if not camera:
		return
	
	# If currently inspecting, click closes inspection
	if inspected_card:
		_close_inspection()
		return
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		if collider.name == "DeckClickArea":
			_on_deck_clicked()
		elif collider is Card3D:
			_on_card_clicked(collider)


func _on_card_clicked(card: Card3D) -> void:
	"""Handle clicking on a drawn card - show local inspection and signal parent to expand"""
	if card and card.card_instance:
		_show_inspection(card)


func _show_inspection(card: Card3D) -> void:
	"""Animate card to center of view, straightened for inspection"""
	if not card or not is_instance_valid(card):
		return
	
	inspected_card = card
	inspected_card_original_pos = card.global_position
	inspected_card_original_rot = card.global_rotation
	inspected_card_original_scale = card.scale
	
	# Create dark overlay behind card
	if not inspection_overlay:
		inspection_overlay = MeshInstance3D.new()
		var quad = QuadMesh.new()
		quad.size = Vector2(50, 50)  # Large enough to cover view
		inspection_overlay.mesh = quad
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0, 0, 0, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		inspection_overlay.material_override = mat
		add_child(inspection_overlay)
	
	# Position overlay behind the card (in world space, facing camera)
	if camera:
		var camera_forward = -camera.global_transform.basis.z
		var overlay_distance = 3.5
		inspection_overlay.global_position = camera.global_position + camera_forward * overlay_distance
		inspection_overlay.look_at(camera.global_position, Vector3.UP)
	inspection_overlay.visible = true
	
	# Calculate center position between the two decks (X=0) at same Y as card
	# Keep Y at card's original Y for consistent visual
	var center_pos = Vector3(0, card.global_position.y + 0.5, card.global_position.z - 1.0)
	
	# Straighten the card - flat rotation facing up (no tilt)
	var straight_rotation = Vector3(-1.05, 0, 0)
	
	# Animate card to center, straightened, and scaled up
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "global_position", center_pos, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "global_rotation", straight_rotation, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector3(2.4, 2.4, 2.4), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _close_inspection() -> void:
	"""Return inspected card to original position, rotation, and scale"""
	if not inspected_card or not is_instance_valid(inspected_card):
		inspected_card = null
		if inspection_overlay:
			inspection_overlay.visible = false
		return
	
	# Hide overlay
	if inspection_overlay:
		inspection_overlay.visible = false
	
	# Animate card back to original position, rotation, and scale
	var card = inspected_card
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "global_position", inspected_card_original_pos, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "global_rotation", inspected_card_original_rot, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "scale", inspected_card_original_scale, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	inspected_card = null


func _on_deck_clicked() -> void:
	print("[DeckView3D] Deck clicked! interaction_mode=%s, deck_manager=%s" % [interaction_mode, deck_manager != null])
	if deck_manager:
		if interaction_mode == InteractionMode.DRAW_TOP:
			print("[DeckView3D] DRAW_TOP mode - drawing card")
			deck_manager.draw_card()
		elif interaction_mode == InteractionMode.SELECT_FROM_UI:
			print("[DeckView3D] SELECT_FROM_UI mode - emitting request_club_selection")
			request_club_selection.emit()


func _on_card_drawn(card: CardInstance) -> void:
	_update_deck_height()
	_animate_draw(card)


func _on_active_cards_changed(cards: Array[CardInstance]) -> void:
	# If empty, it means the round/shot ended.
	if cards.is_empty():
		# Just keep the active card in the stack (it becomes "played")
		if active_card_node:
			played_cards.append(active_card_node)
			active_card_node = null
		
		# Check if the deck was fully reset (discard pile empty)
		# This happens when generating a new hole
		if deck_manager and deck_manager.get_discard_pile_count() == 0:
			_clear_visual_stack()


func dim_played_cards() -> void:
	"""Dim all played cards to indicate they've been used this hole"""
	for card in played_cards:
		if is_instance_valid(card):
			card.set_dimmed(true)
	if active_card_node and is_instance_valid(active_card_node):
		active_card_node.set_dimmed(true)


func undim_all_cards() -> void:
	"""Restore normal appearance to all cards"""
	for card in played_cards:
		if is_instance_valid(card):
			card.set_dimmed(false)
	if active_card_node and is_instance_valid(active_card_node):
		active_card_node.set_dimmed(false)


func _clear_visual_stack() -> void:
	# Clear all played cards
	for card in played_cards:
		if is_instance_valid(card):
			card.queue_free()
	played_cards.clear()
	
	# Clear active card if any
	if active_card_node:
		if is_instance_valid(active_card_node):
			active_card_node.queue_free()
		active_card_node = null
	
	# Clear discarded cards (legacy cleanup)
	for card in discarded_cards:
		if is_instance_valid(card):
			card.queue_free()
	discarded_cards.clear()


func _spawn_active_card(card: CardInstance) -> void:
	# Just spawn it on top
	var node = card_scene.instantiate()
	add_child(node)
	node.setup(card)
	
	var stack_count = played_cards.size()
	if active_card_node:
		stack_count += 1
	
	var target_pos = slot_anchor.position
	target_pos.y += (stack_count + 1) * 0.06
	
	node.position = target_pos
	node.rotation = slot_anchor.rotation
	
	if active_card_node:
		played_cards.append(active_card_node)
	active_card_node = node


func _animate_draw(card: CardInstance) -> void:
	# Spawn card at deck position
	var node = card_scene.instantiate()
	add_child(node)
	node.setup(card)
	node.set_textures(card_front_texture, card_back_texture)
	
	# Start at deck, face down
	# Offset Y to spawn on TOP of the deck mesh (thickness 0.5, so top is +0.25)
	var start_pos = deck_anchor.position
	start_pos.y += 0.26
	
	node.position = start_pos
	node.rotation = deck_anchor.rotation
	# Flip face down (rotate around local X axis which is World X in this orientation)
	node.rotate_object_local(Vector3(1, 0, 0), PI) 
	
	# Animate to slot
	# Flip over during move
	var target_rot = slot_anchor.rotation # Face up
	
	# Calculate stack position
	# Add slight random rotation for natural look
	var random_rot_offset = Vector3(0, randf_range(-0.05, 0.05), 0)
	target_rot += random_rot_offset
	
	var stack_count = played_cards.size()
	if active_card_node:
		stack_count += 1
	
	var target_pos = slot_anchor.position
	# Stack up in Y (World Y is Local Z of the anchor, but we are setting global position)
	# Since camera is looking down Y, increasing Y moves it closer to camera (on top)
	target_pos.y += (stack_count + 1) * 0.08 # Increased spacing to prevent z-fighting
	
	# Use arc height of 2.0 for a nice flip effect
	# Speed up animation from 1.0 to 0.6
	node.animate_move_to(target_pos, target_rot, 0.6, 0.0, 2.0)
	
	# Track as active
	if active_card_node:
		played_cards.append(active_card_node)
	active_card_node = node
