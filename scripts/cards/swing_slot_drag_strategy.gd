class_name SwingSlotDragStrategy
extends DragStrategy
## Custom drag strategy for swing slot.
## - Slot can contain a stack of locked (already-used) cards.
## - At most one *unlocked* card may exist in the slot at a time.
## - Locked cards (and non-top cards) cannot be picked up.
## - New cards can be placed on top of locked cards.


func _is_locked(card) -> bool:
	return card != null and card.has_meta("locked") and bool(card.get_meta("locked"))


func _get_swing_hand_3d(collection: CardCollection3D):
	# Scene structure: SwingHand3D -> DragController -> SwingSlot/SwingHand
	if collection == null:
		return null
	var drag_controller = collection.get_parent()
	if drag_controller == null:
		return null
	return drag_controller.get_parent()


func _slot_accepts_new_cards(to_collection: CardCollection3D) -> bool:
	var swing_hand_3d = _get_swing_hand_3d(to_collection)
	if swing_hand_3d == null:
		return true
	if swing_hand_3d.has_method("can_accept_new_slot_card"):
		return bool(swing_hand_3d.can_accept_new_slot_card())
	if "slot_accepts_new_cards" in swing_hand_3d:
		return bool(swing_hand_3d.slot_accepts_new_cards)
	return true


func _has_unlocked_card(to_collection: CardCollection3D) -> bool:
	for c in to_collection.cards:
		if not _is_locked(c):
			return true
	return false


func _is_top_card(card, in_collection: CardCollection3D) -> bool:
	return in_collection != null and in_collection.cards.size() > 0 and in_collection.cards[in_collection.cards.size() - 1] == card


func can_select_card(card, to_collection: CardCollection3D) -> bool:
	if _is_locked(card):
		return false
	return _is_top_card(card, to_collection)


func can_remove_card(card, to_collection: CardCollection3D) -> bool:
	return can_select_card(card, to_collection)


func can_reorder_card(_card, _to_collection: CardCollection3D) -> bool:
	return false

func can_insert_card(
	_card,
	to_collection: CardCollection3D,
	_from_collection: CardCollection3D
	) -> bool:
	if not _slot_accepts_new_cards(to_collection):
		return false
	return not _has_unlocked_card(to_collection)
