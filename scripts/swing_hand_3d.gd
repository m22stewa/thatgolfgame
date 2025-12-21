extends Node3D

## Swing Hand Manager
## Manages the player's hand of swing cards using the Card3D addon

const SwingCard3DScene = preload("res://scenes/cards/swing_card_3d.tscn")

@onready var swing_hand: CardCollection3D = $DragController/SwingHand
@onready var swing_slot: CardCollection3D = $DragController/SwingSlot
@onready var drag_controller = $DragController

# Reference to deck manager
var deck_manager: DeckManager = null


func _ready() -> void:
	# Set up the swing hand with a fan layout
	var fan_layout = FanCardLayout.new()
	fan_layout.arc_angle_deg = 40.0
	fan_layout.arc_radius = 14.0
	swing_hand.card_layout_strategy = fan_layout
	
	# Set up the swing slot with a pile layout (single card)
	var pile_layout = PileCardLayout.new()
	swing_slot.card_layout_strategy = pile_layout
	
	# Apply custom drag strategy that only allows one card
	var slot_drag_strategy = SwingSlotDragStrategy.new()
	swing_slot.drag_strategy = slot_drag_strategy
	
	# Connect signals
	swing_hand.card_clicked.connect(_on_card_clicked)
	swing_slot.card_clicked.connect(_on_card_clicked)
	drag_controller.card_moved.connect(_on_card_moved)
	
	# Set the SubViewport camera for the drag controller
	var viewport_camera = get_viewport().get_camera_3d()
	if viewport_camera:
		drag_controller._camera = viewport_camera


func setup(manager: DeckManager) -> void:
	"""Connect to a deck manager to display swing cards"""
	deck_manager = manager
	
	if deck_manager:
		# Listen for hand changes
		if deck_manager.has_signal("hand_changed"):
			deck_manager.hand_changed.connect(_on_hand_changed)
		# Wait for ready if nodes aren't initialized yet
		if swing_hand:
			refresh_hand()
		else:
			await ready
			refresh_hand()



func refresh_hand() -> void:
	"""Rebuild the hand display from deck manager"""
	if not swing_hand:
		return
		
	# Clear existing cards
	var existing_cards = swing_hand.remove_all()
	for card in existing_cards:
		card.queue_free()
	
	if not deck_manager:
		return
	
	# Get swing cards from hand
	var hand = deck_manager.get_hand()
	
	var shot_count = 0
	for card_instance in hand:
		# Only show SHOT type cards (swing cards from resources/cards/swing/)
		if card_instance.data.card_type == CardData.CardType.SHOT:
			# Additional check: make sure it's a swing card, not a modifier
			# Swing cards typically have tempo_cost >= 1
			if card_instance.data.tempo_cost > 0:
				shot_count += 1
				_create_card(card_instance)


func _create_card(card_instance: CardInstance) -> void:
	"""Create a SwingCard3D from a CardInstance"""
	var card = SwingCard3DScene.instantiate()
	card.name = card_instance.data.card_name
	
	# Set the card instance data (this updates texture and power label)
	card.set_card_data(card_instance)
	
	swing_hand.append_card(card)
	
	# Store reference to card instance for later
	card.set_meta("card_instance", card_instance)


func _on_card_clicked(card: Card3D) -> void:
	pass


func _on_card_moved(card: Card3D, from_collection: CardCollection3D, to_collection: CardCollection3D, from_index: int, to_index: int) -> void:
	
	# If card moved to swing slot, notify game that a swing card was played
	if to_collection == swing_slot:
		var card_instance = card.get_meta("card_instance") as CardInstance
		if card_instance:
			_on_swing_card_played(card_instance)
	
	# If card moved away from swing slot, show the drop zone again
	if from_collection == swing_slot and to_collection != swing_slot:
		_show_drop_zone()


func _on_swing_card_played(card_instance: CardInstance) -> void:
	"""Handle when a swing card is played"""
	# Hide the drop zone visual when a card is in the slot
	var dropzone_visual = swing_slot.get_node_or_null("DropZoneVisual")
	if dropzone_visual:
		dropzone_visual.visible = false
	# TODO: Signal to game flow manager or shot system


func _show_drop_zone() -> void:
	"""Show the drop zone visual when slot is empty"""
	var dropzone_visual = swing_slot.get_node_or_null("DropZoneVisual")
	if dropzone_visual:
		dropzone_visual.visible = true


func _on_hand_changed() -> void:
	refresh_hand()


func get_selected_swing_card() -> CardInstance:
	"""Get the card currently in the swing slot"""
	if swing_slot.cards.size() > 0:
		var card = swing_slot.cards[0]
		return card.get_meta("card_instance") as CardInstance
	return null
