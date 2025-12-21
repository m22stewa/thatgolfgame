class_name SwingSlotDragStrategy
extends DragStrategy
## Custom drag strategy for swing slot - only allows one card at a time

func can_insert_card(
	_card,
	to_collection: CardCollection3D,
	_from_collection: CardCollection3D
	) -> bool:
	# Only allow inserting if slot is empty
	return to_collection.cards.size() == 0
