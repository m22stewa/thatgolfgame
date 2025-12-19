extends Control
class_name SwingCardSlot

## A drop zone for swing cards. Accepts cards dragged from the hand.

signal card_dropped(card_instance: CardInstance)
signal card_removed()

# Node references - use @onready to get from scene
@onready var drop_zone: Panel = $DropZone
@onready var card_container: Control = $CardContainer
@onready var slot_label: Label = $DropZone/Label

# Currently slotted card
var current_card: SwingCardUI = null
var current_card_instance: CardInstance = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Make sure children don't block input to us
	if drop_zone:
		drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in drop_zone.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if card_container:
		card_container.mouse_filter = Control.MOUSE_FILTER_IGNORE


# =============================================================================
# DROP TARGET API - Called by SwingCardUI during manual drag
# =============================================================================

func can_accept_card(_card: SwingCardUI) -> bool:
	"""Check if this slot can accept a card"""
	return current_card == null


func accept_card(card: SwingCardUI) -> void:
	"""Accept a card into this slot"""
	if current_card:
		return  # Already have a card
	
	# Reparent the card to our container
	if card.get_parent():
		card.get_parent().remove_child(card)
	
	card_container.add_child(card)
	
	# Reset transforms and make non-draggable
	card.rotation = 0
	card.scale = Vector2.ONE
	card.z_index = 0
	card.set_playable(false)  # Card can no longer be dragged
	
	# Position at top-left (0,0) to cover the placeholder
	card.position = Vector2.ZERO
	
	current_card = card
	current_card_instance = card.card_instance
	
	# Hide the label
	if slot_label:
		slot_label.visible = false
	
	card_dropped.emit(current_card_instance)


func remove_card() -> SwingCardUI:
	"""Remove and return the current card"""
	var card = current_card
	current_card = null
	current_card_instance = null
	
	if card and card.get_parent() == card_container:
		card_container.remove_child(card)
	
	if slot_label:
		slot_label.visible = true
	
	card_removed.emit()
	return card


func get_card_instance() -> CardInstance:
	return current_card_instance


func has_card() -> bool:
	return current_card != null
