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

# Card data
var card_instance: CardInstance = null

# Visual state
var is_selected: bool = false
var is_hovered: bool = false
var is_playable: bool = true
var hover_offset: float = 30.0
var select_offset: float = 50.0

# Drag state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var drag_start_position: Vector2 = Vector2.ZERO
var return_position: Vector2 = Vector2.ZERO
var return_rotation: float = 0.0

# Physics-like drag
var velocity: Vector2 = Vector2.ZERO
var drag_smoothing: float = 15.0
var wiggle_amount: float = 0.0
var wiggle_speed: float = 12.0
var wiggle_decay: float = 8.0

# Animation
var target_position: Vector2 = Vector2.ZERO
var target_rotation: float = 0.0
var target_scale: Vector2 = Vector2.ONE
var animation_speed: float = 10.0
var hand_index: int = 0  # Position in hand for gap calculation

# Child node references
@onready var background: ColorRect = $Background
@onready var card_name_label: Label = $CardName
@onready var description_label: RichTextLabel = $Description
@onready var rarity_indicator: ColorRect = $RarityIndicator
@onready var type_icon: TextureRect = $TypeIcon
@onready var cost_label: Label = $CostLabel

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
	
	# Calculate velocity for wiggle effect
	var old_pos = position
	
	# Smooth lerp to mouse position
	position = position.lerp(mouse_pos, delta * drag_smoothing)
	
	# Calculate velocity and add wiggle based on movement
	velocity = (position - old_pos) / delta
	wiggle_amount += velocity.x * 0.001
	wiggle_amount = clamp(wiggle_amount, -0.3, 0.3)
	
	# Apply wiggle rotation
	var wiggle_rotation = sin(Time.get_ticks_msec() * 0.001 * wiggle_speed) * wiggle_amount
	rotation = wiggle_rotation
	
	# Decay wiggle
	wiggle_amount = move_toward(wiggle_amount, 0.0, delta * wiggle_decay * 0.1)
	
	# Dragging scale
	scale = scale.lerp(Vector2(1.1, 1.1), delta * animation_speed)


func _process_idle(delta: float) -> void:
	# Smooth animation toward target
	position = position.lerp(target_position, delta * animation_speed)
	rotation = lerp(rotation, target_rotation, delta * animation_speed)
	scale = scale.lerp(target_scale, delta * animation_speed)
	
	# Decay any remaining wiggle
	wiggle_amount = move_toward(wiggle_amount, 0.0, delta * wiggle_decay)


func setup(instance: CardInstance) -> void:
	"""Initialize card with data"""
	card_instance = instance
	if is_node_ready():
		refresh_display()


func refresh_display() -> void:
	"""Update visual display from card data"""
	if not card_instance or not card_instance.data:
		return
	
	var data = card_instance.data
	
	# Card name
	if card_name_label:
		card_name_label.text = data.card_name
		if card_instance.upgrade_level > 0:
			card_name_label.text += " +" + str(card_instance.upgrade_level)
	
	# Description
	if description_label:
		description_label.text = card_instance.get_full_description()
	
	# Rarity indicator
	if rarity_indicator:
		rarity_indicator.color = RARITY_COLORS.get(data.rarity, Color.GRAY)
	
	# Background color based on type
	if background:
		background.color = TYPE_COLORS.get(data.card_type, Color(0.2, 0.2, 0.2))
	
	# Cost/uses display
	if cost_label:
		if data.card_type == CardData.CardType.CONSUMABLE:
			cost_label.text = "%d/%d" % [card_instance.uses_remaining, data.max_uses]
			cost_label.visible = true
		else:
			cost_label.visible = false
	
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
	if is_dragging:
		return
		
	is_hovered = hovered
	
	if hovered and is_playable:
		target_scale = Vector2(1.1, 1.1)
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


func _on_mouse_exited() -> void:
	if not is_dragging and not is_selected:
		set_hovered(false)
	card_hovered.emit(self, false)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_playable:
					# Start drag
					start_drag(get_parent().get_local_mouse_position())
			else:
				if is_dragging:
					# End drag
					end_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right click to play selected card
			if is_selected and is_playable:
				card_played.emit(self)
