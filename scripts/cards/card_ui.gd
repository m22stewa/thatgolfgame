@tool
extends Control
class_name CardUI

## Visual representation of a card in the hand.
## Handles hover, selection, drag & drop, and animation states.

signal card_clicked(card_ui: CardUI)
signal card_hovered(card_ui: CardUI, hovering: bool)
signal card_played(card_ui: CardUI)
signal card_drag_started(card_ui: CardUI)
signal card_drag_ended(card_ui: CardUI)
signal card_dropped(card_ui: CardUI, global_pos: Vector2)
signal card_inspect_requested(card_ui: CardUI)  # Click without drag

# Card data
var card_instance: CardInstance = null
var custom_front_texture: Texture2D = null

# Visual state
var is_selected: bool = false
var is_hovered: bool = false
var is_playable: bool = true
var manual_positioning: bool = false # If true, disables internal position/scale animation
var hover_offset: float = 30.0
var select_offset: float = 50.0

# Drag state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var drag_start_position: Vector2 = Vector2.ZERO
var return_position: Vector2 = Vector2.ZERO
var return_rotation: float = 0.0
var mouse_down_position: Vector2 = Vector2.ZERO  # For click vs drag detection
var is_mouse_down: bool = false
const DRAG_THRESHOLD: float = 8.0  # Pixels to move before it's a drag

# Physics-like drag
var velocity: Vector2 = Vector2.ZERO
var drag_smoothing: float = 20.0  # Faster response to mouse
var wiggle_amount: float = 0.0
var wiggle_speed: float = 8.0     # Slower wiggle oscillation
var wiggle_decay: float = 12.0    # Faster decay

# Animation
var target_position: Vector2 = Vector2.ZERO
var target_rotation: float = 0.0
var target_scale: Vector2 = Vector2.ONE
var animation_speed: float = 12.0  # Snappier animations
var hand_index: int = 0  # Position in hand for gap calculation

# Inspection mode - card reacts to mouse
var is_inspecting: bool = false
var inspect_center: Vector2 = Vector2.ZERO  # Center position during inspection
var inspect_tilt_amount: float = 5.0  # Max tilt in degrees (subtle 3D effect)

# Child node references
@onready var card_3d_view = $SubViewportContainer/SubViewport/Node3D/Card3D

# Rarity colors
const RARITY_COLORS = {
	CardData.Rarity.COMMON: Color(0.6, 0.6, 0.6),
	CardData.Rarity.UNCOMMON: Color(0.2, 0.6, 0.2),
	CardData.Rarity.RARE: Color(0.2, 0.4, 0.8),
	CardData.Rarity.LEGENDARY: Color(0.9, 0.7, 0.1)
}

# Card type background colors
const TYPE_COLORS = {
	CardData.CardType.SHOT: Color(0.3, 0.5, 0.3),
	CardData.CardType.PASSIVE: Color(0.3, 0.3, 0.5),
	CardData.CardType.CONSUMABLE: Color(0.5, 0.3, 0.3),
	CardData.CardType.JOKER: Color(0.5, 0.4, 0.2)
}


func _ready() -> void:
	# Connect mouse signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	
	# Initial setup
	pivot_offset = size / 2
	
	if card_instance:
		refresh_display()


func _process(delta: float) -> void:
	if is_dragging:
		_process_drag(delta)
	else:
		_process_idle(delta)


func _process_drag(delta: float) -> void:
	# Get mouse position relative to parent
	var mouse_pos = get_parent().get_local_mouse_position() - drag_offset
	
	# Calculate velocity for subtle tilt effect
	var old_pos = position
	
	# Smooth lerp to mouse position
	position = position.lerp(mouse_pos, delta * drag_smoothing)
	
	# Calculate velocity and add subtle tilt based on horizontal movement
	velocity = (position - old_pos) / delta
	wiggle_amount += velocity.x * 0.0003  # Much smaller multiplier
	wiggle_amount = clamp(wiggle_amount, -0.1, 0.1)  # Smaller max rotation
	
	# Apply smooth tilt (no oscillation, just direct tilt based on movement)
	if card_3d_view:
		card_3d_view.rotation.z = lerp(card_3d_view.rotation.z, -wiggle_amount, delta * 10.0)
	else:
		rotation = lerp(rotation, wiggle_amount, delta * 10.0)
	
	# Decay tilt when not moving
	wiggle_amount = move_toward(wiggle_amount, 0.0, delta * wiggle_decay * 0.3)
	
	# Dragging scale - card grows when picked up
	scale = scale.lerp(Vector2(1.4, 1.4), delta * animation_speed)


func _process_idle(delta: float) -> void:
	# Handle inspection mode mouse reaction
	if is_inspecting:
		_process_inspection(delta)
		return
	
	if not manual_positioning:
		# Smooth animation toward target
		position = position.lerp(target_position, delta * animation_speed)
		rotation = lerp(rotation, target_rotation, delta * animation_speed)
		scale = scale.lerp(target_scale, delta * animation_speed)
	
	# Decay any remaining wiggle
	wiggle_amount = move_toward(wiggle_amount, 0.0, delta * wiggle_decay)
	
	# Reset 3D rotation when idle
	if card_3d_view:
		card_3d_view.rotation.x = lerp(card_3d_view.rotation.x, 0.0, delta * 5.0)
		card_3d_view.rotation.y = lerp(card_3d_view.rotation.y, 0.0, delta * 5.0)


func _process_inspection(delta: float) -> void:
	"""Handle mouse reaction during card inspection - simulated 3D tilt effect"""
	# Ensure pivot is at center for rotation
	pivot_offset = custom_minimum_size / 2.0
	
	# Get mouse position relative to card center (in screen space)
	var mouse_pos = get_global_mouse_position()
	var card_global_center = global_position + (custom_minimum_size * scale.x) / 2.0
	var offset_from_center = mouse_pos - card_global_center
	
	# Normalize the offset based on scaled card size (extended beyond card for smooth falloff)
	var card_half_size = (custom_minimum_size * target_scale.x) / 2.0
	var normalized_x = clamp(offset_from_center.x / (card_half_size.x * 1.5), -1.0, 1.0)
	var normalized_y = clamp(offset_from_center.y / (card_half_size.y * 1.5), -1.0, 1.0)
	
	if card_3d_view:
		# Apply 3D rotation
		# Mouse X -> Rotate Y (Yaw)
		# Mouse Y -> Rotate X (Pitch)
		var target_rot_y = normalized_x * deg_to_rad(inspect_tilt_amount * 3.0)
		var target_rot_x = -normalized_y * deg_to_rad(inspect_tilt_amount * 3.0)
		
		card_3d_view.rotation.y = lerp(card_3d_view.rotation.y, target_rot_y, delta * 10.0)
		card_3d_view.rotation.x = lerp(card_3d_view.rotation.x, target_rot_x, delta * 10.0)
		
		# Reset 2D rotation/scale to base target
		rotation = lerp(rotation, 0.0, delta * 10.0)
		scale = scale.lerp(target_scale, delta * 10.0)
	else:
		# Fallback for no 3D view (shouldn't happen after refactor)
		pass
	
	# Smooth animation
	position = position.lerp(target_position, delta * animation_speed)


func setup(instance: CardInstance) -> void:
	"""Initialize card with data"""
	card_instance = instance
	if is_node_ready():
		refresh_display()


func set_custom_front_texture(texture: Texture2D) -> void:
	custom_front_texture = texture
	if is_node_ready() and card_3d_view:
		# Note: Card3D seems to swap front/back textures internally, so we pass as back to show on front
		card_3d_view.set_textures(null, texture)


func refresh_display() -> void:
	"""Update visual display from card data"""
	if not card_instance:
		return
	
	if card_3d_view:
		card_3d_view.setup(card_instance)
		if custom_front_texture:
			# Note: Card3D seems to swap front/back textures internally, so we pass as back to show on front
			card_3d_view.set_textures(null, custom_front_texture)
	
	# Apply exhausted visual if needed
	_update_exhausted_visual()


func _update_exhausted_visual() -> void:
	if card_instance and card_instance.is_exhausted:
		modulate = Color(0.5, 0.5, 0.5, 0.7)
		is_playable = false
	else:
		modulate = Color.WHITE
		is_playable = true


func set_hand_position(index: int, total_cards: int, hand_width: float, skip_index: int = -1) -> void:
	"""Calculate position in a fanned hand layout"""
	hand_index = index
	var center = hand_width / 2.0
	
	# Adjust index if we need to leave a gap for dragged card
	var adjusted_index = index
	if skip_index >= 0 and index >= skip_index:
		adjusted_index += 1
	
	# Spacing based on card count (account for potential gap)
	var display_count = total_cards
	if skip_index >= 0:
		display_count += 1
	
	var spacing = min(custom_minimum_size.x + 10, hand_width / (display_count + 1))
	
	# Calculate base position
	var x = center + (adjusted_index - (display_count - 1) / 2.0) * spacing
	var y = 0.0
	
	# Add arc effect - cards at edges are lower
	var normalized_pos = (adjusted_index - (display_count - 1) / 2.0) / max(1, (display_count - 1) / 2.0)
	y += abs(normalized_pos) * 20.0  # Lower cards at edges
	
	# Add rotation for fan effect
	var rotation_degrees = -normalized_pos * 5.0  # ±5 degrees
	
	target_position = Vector2(x - custom_minimum_size.x / 2, y)
	target_rotation = deg_to_rad(rotation_degrees)
	return_position = target_position
	return_rotation = target_rotation
	
	if not is_dragging and not is_selected:
		target_scale = Vector2.ONE


func set_hovered(hovered: bool) -> void:
	if is_dragging or is_inspecting:
		return
		
	is_hovered = hovered
	
	if hovered and is_playable:
		target_scale = Vector2(2, 2)  # Larger hover for readability
		z_index = 10
	else:
		target_scale = Vector2.ONE
		z_index = 0


func set_selected(selected: bool) -> void:
	is_selected = selected
	
	if selected:
		target_scale = Vector2(1.15, 1.15)
		z_index = 20
		# Lift the card up
		target_position.y -= select_offset
	else:
		set_hovered(is_hovered)  # Reset to hover state or normal


func start_drag(mouse_position: Vector2) -> void:
	"""Begin dragging this card"""
	if not is_playable:
		return
	
	is_dragging = true
	drag_start_position = position
	drag_offset = mouse_position - position
	z_index = 100
	wiggle_amount = 0.0
	velocity = Vector2.ZERO
	
	card_drag_started.emit(self)


func end_drag() -> void:
	"""End dragging, either playing or returning to hand"""
	if not is_dragging:
		return
	
	is_dragging = false
	var drop_pos = global_position + size / 2
	
	card_drag_ended.emit(self)
	card_dropped.emit(self, drop_pos)


func return_to_hand() -> void:
	"""Animate back to hand position"""
	target_position = return_position
	target_rotation = return_rotation
	target_scale = Vector2.ONE
	z_index = 0
	is_selected = false


func play_animation() -> void:
	"""Play a 'card played' animation before removal"""
	# Quick scale up then fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.15)
	tween.tween_property(self, "modulate:a", 0.0, 0.2).set_delay(0.1)
	tween.chain().tween_callback(queue_free)


func _on_mouse_entered() -> void:
	if not is_dragging:
		set_hovered(true)
		card_hovered.emit(self, true)
		# Set hand point cursor for UI cards
		if has_node("/root/CursorManager"):
			get_node("/root/CursorManager").set_hand_point()


func _on_mouse_exited() -> void:
	if not is_dragging and not is_selected and not is_inspecting:
		set_hovered(false)
	card_hovered.emit(self, false)
	# Reset cursor
	if has_node("/root/CursorManager"):
		get_node("/root/CursorManager").set_default()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Record mouse down position for click vs drag detection
				is_mouse_down = true
				mouse_down_position = event.global_position
				accept_event() # Consume press
			else:
				if is_dragging:
					# End drag
					end_drag()
				elif is_mouse_down:
					# This was a click (not a drag)
					card_clicked.emit(self)
					card_inspect_requested.emit(self)
					accept_event() # Consume the event so it doesn't bubble to parent
				is_mouse_down = false
				accept_event() # Consume release
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right click to play selected card
			if is_selected and is_playable:
				card_played.emit(self)
	
	elif event is InputEventMouseMotion:
		# Dragging disabled for now
		pass
		# Check if we should start dragging (moved beyond threshold)
		# if is_mouse_down and not is_dragging and is_playable:
		# 	var distance = event.global_position.distance_to(mouse_down_position)
		# 	if distance > DRAG_THRESHOLD:
		# 		start_drag(get_parent().get_local_mouse_position())
