extends Control
class_name SwingHand

## Displays swing cards in a horizontal row at the bottom of the screen.
## Cards can be dragged to the swing card slot.

# Preload the scene file so we get proper visual nodes
const SwingCardUIScene = preload("res://scenes/ui/swing_card_ui.tscn")

signal card_selected(card_instance: CardInstance)
signal card_played(card_instance: CardInstance)
signal card_hovered(card_instance: CardInstance)

# Layout settings - exposed for editor tweaking
@export_group("Layout")
@export var card_spacing: float = 10.0  # Gap between cards
@export var hover_lift: float = 20.0  # How much a hovered card lifts up

@export_group("Card Size")
@export var card_width: float = 120.0
@export var card_height: float = 180.0

# Container for cards - from scene
@onready var cards_container: Control = $CardsContainer

# Card data
var deck_manager: DeckManager = null
var card_uis: Array[SwingCardUI] = []
var hovered_card: SwingCardUI = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let cards handle their own input


func setup(manager: DeckManager) -> void:
	"""Connect to a deck manager to display its hand"""
	if deck_manager:
		if deck_manager.hand_changed.is_connected(_on_hand_changed):
			deck_manager.hand_changed.disconnect(_on_hand_changed)
	
	deck_manager = manager
	
	if deck_manager:
		if deck_manager.has_signal("hand_changed"):
			deck_manager.hand_changed.connect(_on_hand_changed)
		refresh_hand()


func refresh_hand() -> void:
	"""Rebuild the hand display from deck manager"""
	_clear_cards()
	
	if not deck_manager:
		return
	
	var hand = deck_manager.get_hand()
	for card_instance in hand:
		_create_card(card_instance)
	
	_arrange_cards()


func _clear_cards() -> void:
	"""Remove all card UIs"""
	for card_ui in card_uis:
		if is_instance_valid(card_ui):
			card_ui.queue_free()
	card_uis.clear()
	hovered_card = null


func _create_card(card_instance: CardInstance) -> SwingCardUI:
	"""Create a card UI for a card instance"""
	var card_ui = SwingCardUIScene.instantiate() as SwingCardUI
	card_ui.custom_minimum_size = Vector2(card_width, card_height)
	card_ui.size = Vector2(card_width, card_height)
	
	cards_container.add_child(card_ui)
	card_ui.setup(card_instance)
	
	# Connect signals
	card_ui.card_clicked.connect(_on_card_clicked)
	card_ui.card_hovered.connect(_on_card_hovered)
	card_ui.card_unhovered.connect(_on_card_unhovered)
	card_ui.card_drag_started.connect(_on_card_drag_started)
	card_ui.card_drag_ended.connect(_on_card_drag_ended)
	
	card_uis.append(card_ui)
	return card_ui


func _on_card_drag_started(card_ui: SwingCardUI) -> void:
	"""Called when a card starts dragging - remove from our tracking immediately"""
	card_uis.erase(card_ui)
	_arrange_cards()


func _on_card_drag_ended(card_ui: SwingCardUI, was_dropped: bool) -> void:
	"""Called when a card drag ends"""
	if was_dropped:
		# Card was successfully dropped somewhere
		card_played.emit(card_ui.card_instance)
	else:
		# Card returned to hand - add back to tracking
		if is_instance_valid(card_ui) and card_ui.get_parent() == cards_container:
			if not card_uis.has(card_ui):
				card_uis.append(card_ui)
				_arrange_cards()


func _arrange_cards() -> void:
	"""Arrange cards in a simple horizontal row"""
	var num_cards = card_uis.size()
	if num_cards == 0:
		return
	
	# Calculate total width
	var total_width = num_cards * card_width + (num_cards - 1) * card_spacing
	
	# Center horizontally in our bounds
	var start_x = (size.x - total_width) / 2
	var base_y = (size.y - card_height) / 2  # Center vertically
	
	for i in num_cards:
		var card_ui = card_uis[i]
		var x = start_x + i * (card_width + card_spacing)
		
		card_ui.position = Vector2(x, base_y)
		card_ui.rotation = 0
		
		# Store base position for hover animations
		card_ui.set_meta("base_position", card_ui.position)


func _on_card_clicked(card_instance: CardInstance) -> void:
	card_selected.emit(card_instance)


func _on_card_hovered(card_instance: CardInstance) -> void:
	for card_ui in card_uis:
		if card_ui.card_instance == card_instance:
			_hover_card(card_ui)
			break
	card_hovered.emit(card_instance)


func _on_card_unhovered(_card_instance: CardInstance) -> void:
	if hovered_card:
		_unhover_card(hovered_card)


func _hover_card(card_ui: SwingCardUI) -> void:
	"""Lift card on hover"""
	if hovered_card and hovered_card != card_ui:
		_unhover_card(hovered_card)
	
	hovered_card = card_ui
	
	var base_pos = card_ui.get_meta("base_position", card_ui.position)
	var tween = create_tween()
	tween.tween_property(card_ui, "position:y", base_pos.y - hover_lift, 0.1).set_ease(Tween.EASE_OUT)


func _unhover_card(card_ui: SwingCardUI) -> void:
	"""Return card to base position"""
	if not is_instance_valid(card_ui):
		hovered_card = null
		return
	
	if hovered_card == card_ui:
		hovered_card = null
	
	var base_pos = card_ui.get_meta("base_position", card_ui.position)
	var tween = create_tween()
	tween.tween_property(card_ui, "position:y", base_pos.y, 0.1).set_ease(Tween.EASE_OUT)


func _on_hand_changed() -> void:
	refresh_hand()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_arrange_cards()
