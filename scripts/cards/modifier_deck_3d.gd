extends Node3D
class_name ModifierDeck3D
## A deck of modifier cards that can be clicked to draw/flip a card

signal card_drawn(card_instance: CardInstance)

const ModifierCard3DScene = preload("res://scenes/cards/modifier_card_3d.tscn")

@onready var deck_collection: CardCollection3D = $DragController/Deck
@onready var drawn_collection: CardCollection3D = $DragController/DrawnCard
@onready var deck_placeholder: MeshInstance3D = $DeckPlaceholder
@onready var drawn_placeholder: MeshInstance3D = $DrawnPlaceholder

var deck_manager: DeckManager = null
var current_drawn_card: ModifierCard3D = null


func _ready() -> void:
	print("ModifierDeck3D _ready called")
	print("  deck_collection: ", deck_collection)
	print("  drawn_collection: ", drawn_collection)
	
	# Set up pile layout for both collections
	var pile_layout = PileCardLayout.new()
	deck_collection.card_layout_strategy = pile_layout
	
	var drawn_pile_layout = PileCardLayout.new()
	drawn_collection.card_layout_strategy = drawn_pile_layout
	
	# Disable hover and dragging on deck
	deck_collection.highlight_on_hover = false
	
	# Disable hover on drawn collection
	drawn_collection.highlight_on_hover = false
	
	# Create drag strategy that prevents removal/insertion but allows selection (click)
	var deck_drag_strategy = DragStrategy.new()
	deck_drag_strategy.can_select = true
	deck_drag_strategy.can_remove = false
	deck_drag_strategy.can_reorder = false
	deck_drag_strategy.can_insert = false
	deck_collection.drag_strategy = deck_drag_strategy
	
	# Prevent interaction with drawn cards
	var drawn_drag_strategy = DragStrategy.new()
	drawn_drag_strategy.can_select = false
	drawn_drag_strategy.can_remove = false
	drawn_drag_strategy.can_reorder = false
	drawn_drag_strategy.can_insert = false
	drawn_collection.drag_strategy = drawn_drag_strategy
	
	# Connect signals
	deck_collection.card_selected.connect(_on_deck_card_selected)


func setup(manager: DeckManager) -> void:
	"""Setup with a deck manager"""
	print("ModifierDeck3D setup called with manager: ", manager)
	deck_manager = manager
	_populate_deck()


func _populate_deck() -> void:
	"""Create visual cards for all cards in the deck"""
	print("ModifierDeck3D _populate_deck called")
	if not deck_manager:
		print("  No deck_manager!")
		return
	
	# Hide placeholders when we have cards
	if deck_placeholder:
		deck_placeholder.visible = false
	if drawn_placeholder:
		drawn_placeholder.visible = false
	
	# Get all cards from the deck
	var deck_cards = deck_manager.get_all_deck_cards()
	print("  Deck has ", deck_cards.size(), " cards")
	
	# Create a visual card for each one (face down)
	var card_count = 0
	for card_instance in deck_cards:
		card_count += 1
		var card = ModifierCard3DScene.instantiate()
		card.set_card_data(card_instance)
		card.face_down = true
		deck_collection.append_card(card)
		card.set_meta("card_instance", card_instance)


func _on_deck_card_selected(_card: Card3D) -> void:
	"""Handle clicking the deck - draw a card"""
	print("ModifierDeck3D: Deck clicked! Cards in deck: ", deck_collection.cards.size())
	if deck_collection.cards.size() == 0:
		print("  Deck is empty!")
		return
	
	# Remove the top card from deck (same as solitaire)
	var cards = deck_collection.cards
	var card_global_position = cards[cards.size() - 1].global_position
	var drawn_card = deck_collection.remove_card(cards.size() - 1) as ModifierCard3D
	
	# If there's already a card in the drawn pile, remove it
	if current_drawn_card:
		current_drawn_card.queue_free()
		drawn_collection.remove_all()
	
	# Add to drawn pile and set position (same as solitaire)
	drawn_collection.append_card(drawn_card)
	drawn_card.global_position = card_global_position
	drawn_card.face_down = false
	
	current_drawn_card = drawn_card
	
	# Get the card instance and emit signal
	var card_instance = drawn_card.get_meta("card_instance") as CardInstance
	if card_instance:
		card_drawn.emit(card_instance)
	
	print("Modifier card drawn: ", card_instance.data.card_name if card_instance else "Unknown")


func get_drawn_card() -> CardInstance:
	"""Get the currently drawn card instance"""
	if current_drawn_card:
		return current_drawn_card.get_meta("card_instance") as CardInstance
	return null


func clear_drawn_card() -> void:
	"""Remove the drawn card from view"""
	if current_drawn_card:
		current_drawn_card.queue_free()
		drawn_collection.remove_all()
		current_drawn_card = null
