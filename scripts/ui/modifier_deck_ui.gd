extends Control
class_name ModifierDeckUI
## UI wrapper for the 3D modifier deck

signal card_drawn(card_instance: CardInstance)

@onready var modifier_deck_3d: ModifierDeck3D = $SubViewportContainer/SubViewport/ModifierDeck3D


func _ready() -> void:
	# Connect the 3D deck's signal
	if modifier_deck_3d:
		modifier_deck_3d.card_drawn.connect(_on_card_drawn)


func setup(deck_manager: DeckManager) -> void:
	"""Setup the deck with a deck manager"""
	if modifier_deck_3d:
		modifier_deck_3d.setup(deck_manager)


func _on_card_drawn(card_instance: CardInstance) -> void:
	"""Forward the card drawn signal"""
	card_drawn.emit(card_instance)


func get_drawn_card() -> CardInstance:
	"""Get the currently drawn card"""
	if modifier_deck_3d:
		return modifier_deck_3d.get_drawn_card()
	return null


func clear_drawn_card() -> void:
	"""Clear the drawn card"""
	if modifier_deck_3d:
		modifier_deck_3d.clear_drawn_card()
