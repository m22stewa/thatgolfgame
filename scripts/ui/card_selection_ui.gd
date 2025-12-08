extends Control
class_name CardSelectionUI

signal card_selected(card: CardInstance)
signal cancelled()

@export var card_scene: PackedScene = preload("res://scenes/ui/card_ui.tscn")
@export var animation_duration: float = 0.4
@export var stagger_delay: float = 0.05

var cards: Array[CardInstance] = []
var origin_position: Vector2 = Vector2.ZERO
var card_nodes: Array[CardUI] = []
var custom_front_texture: Texture2D = null

func setup(available_cards: Array[CardInstance], deck_screen_pos: Vector2, front_texture: Texture2D = null) -> void:
	cards = available_cards
	origin_position = deck_screen_pos
	custom_front_texture = front_texture
	
	# If origin is zero (e.g. not provided), default to bottom left
	if origin_position == Vector2.ZERO:
		origin_position = Vector2(100, get_viewport_rect().size.y - 100)
		
	_create_cards()
	_animate_entrance()

func _create_cards() -> void:
	for card in cards:
		var card_ui = card_scene.instantiate() as CardUI
		add_child(card_ui)
		
		# Setup card
		card_ui.card_instance = card
		if custom_front_texture:
			card_ui.set_custom_front_texture(custom_front_texture)
		card_ui.refresh_display()
		
		# Initial state
		card_ui.position = origin_position
		card_ui.scale = Vector2(0.1, 0.1)
		card_ui.modulate.a = 0.0
		card_ui.manual_positioning = true # Take control of positioning
		
		# Disable normal card interactions if needed, or override them
		# For now, we just listen to clicked signal
		if not card_ui.card_clicked.is_connected(_on_card_clicked):
			card_ui.card_clicked.connect(_on_card_clicked)
		
		card_nodes.append(card_ui)

func _animate_entrance() -> void:
	# Calculate grid layout
	var screen_size = get_viewport_rect().size
	var card_size = Vector2(240, 160) # Approximate size (3:2 aspect ratio)
	if card_nodes.size() > 0:
		card_size = card_nodes[0].custom_minimum_size
		if card_size == Vector2.ZERO: card_size = Vector2(240, 160)
	
	var padding = 20
	var columns = 5 # Wider grid for clubs
	
	var total_width = (columns * card_size.x) + ((columns - 1) * padding)
	var start_x = (screen_size.x - total_width) / 2.0
	var start_y = 150.0 # Top margin
	
	for i in range(card_nodes.size()):
		var card_ui = card_nodes[i]
		var col = i % columns
		var row = i / columns
		
		var target_pos = Vector2(
			start_x + (col * (card_size.x + padding)),
			start_y + (row * (card_size.y + padding))
		)
		
		# Position Tween
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(card_ui, "position", target_pos, animation_duration).set_delay(i * stagger_delay)
		
		# Scale Tween
		var scale_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		scale_tween.tween_property(card_ui, "scale", Vector2.ONE, animation_duration).set_delay(i * stagger_delay)
		
		# Alpha Tween
		var alpha_tween = create_tween()
		alpha_tween.tween_property(card_ui, "modulate:a", 1.0, animation_duration * 0.5).set_delay(i * stagger_delay)
		
		# On finish, enable internal logic for hover effects
		# We need to capture variables for the closure
		var final_pos = target_pos
		tween.finished.connect(func():
			card_ui.target_position = final_pos
			card_ui.target_scale = Vector2.ONE
			card_ui.manual_positioning = false
		)

func _on_card_clicked(card_ui: CardUI) -> void:
	card_selected.emit(card_ui.card_instance)
	_close()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Clicked background - cancel
			cancelled.emit()
			_close()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# Consume release events too
			accept_event()

func _close() -> void:
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		_close()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Close if clicking background (not on a card)
		# Since cards handle their own input, if we get here it's likely background
		cancelled.emit()
		_close()
