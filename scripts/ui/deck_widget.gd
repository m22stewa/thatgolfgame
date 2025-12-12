@tool
extends SubViewportContainer
class_name DeckWidget

## DeckWidget - A self-contained UI widget that displays 3D decks.
## Supports both single DeckView3D and CombinedDeckView modes.

# Internal references - supports both modes
var deck_view: DeckView3D = null  # Single deck mode
var combined_deck_view: CombinedDeckView = null  # Combined mode
var sub_viewport: SubViewport = null

# Signals forwarded from DeckView3D or CombinedDeckView
signal card_inspection_requested(card_instance: CardInstance)
signal swing_request_club_selection()
signal modifier_request_club_selection()

func _ready() -> void:
	# Find the internal views and SubViewport
	sub_viewport = get_node_or_null("SubViewport")
	
	# Check for CombinedDeckView (primary mode)
	combined_deck_view = get_node_or_null("SubViewport/CombinedDeckView")
	if combined_deck_view:
		_setup_combined_mode()
	else:
		# Fall back to single DeckView3D (legacy mode)
		deck_view = get_node_or_null("SubViewport/DeckView3D")
		if deck_view:
			_setup_single_mode()
	
	# Connect to resize signal to keep SubViewport in sync
	resized.connect(_on_resized)
	# Initial sync
	_on_resized()


func _on_resized() -> void:
	"""Keep SubViewport size in sync with container for proper raycast coordinates"""
	if sub_viewport and size.x > 0 and size.y > 0:
		sub_viewport.size = Vector2i(int(size.x), int(size.y))


func _setup_combined_mode() -> void:
	"""Setup for combined deck view mode (both swing + modifier decks in one view)"""
	if not combined_deck_view:
		return
	
	# Forward signals from swing deck
	if not combined_deck_view.swing_request_club_selection.is_connected(_on_swing_request_club_selection):
		combined_deck_view.swing_request_club_selection.connect(_on_swing_request_club_selection)
	if not combined_deck_view.swing_card_inspection_requested.is_connected(_on_card_inspection_requested):
		combined_deck_view.swing_card_inspection_requested.connect(_on_card_inspection_requested)
	
	# Forward signals from modifier deck
	if not combined_deck_view.modifier_request_club_selection.is_connected(_on_modifier_request_club_selection):
		combined_deck_view.modifier_request_club_selection.connect(_on_modifier_request_club_selection)
	if not combined_deck_view.modifier_card_inspection_requested.is_connected(_on_card_inspection_requested):
		combined_deck_view.modifier_card_inspection_requested.connect(_on_card_inspection_requested)


func _setup_single_mode() -> void:
	"""Setup for single deck view mode (legacy)"""
	if not deck_view:
		return
	
	# Forward inspection signal (kept for compatibility)
	if not deck_view.card_inspection_requested.is_connected(_on_card_inspection_requested):
		deck_view.card_inspection_requested.connect(_on_card_inspection_requested)


func _on_card_inspection_requested(card_instance: CardInstance) -> void:
	card_inspection_requested.emit(card_instance)


func _on_swing_request_club_selection() -> void:
	swing_request_club_selection.emit()


func _on_modifier_request_club_selection() -> void:
	modifier_request_club_selection.emit()


func _gui_input(event: InputEvent) -> void:
	"""Handle mouse input and forward to deck views"""
	# Handle hover for cursor changes
	if event is InputEventMouseMotion:
		var local_pos = event.position
		if combined_deck_view:
			combined_deck_view.handle_hover_from_container(local_pos)
		elif deck_view:
			deck_view._check_hover(local_pos)
		return
	
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	
	# Position is already in local coordinates which match SubViewport (we sync sizes)
	var local_pos = event.position
	
	print("[DeckWidget] Container size=%s, SubViewport size=%s" % [size, Vector2(sub_viewport.size) if sub_viewport else Vector2.ZERO])
	print("[DeckWidget] Click at %s" % local_pos)
	
	# Forward to combined or single deck view
	if combined_deck_view:
		combined_deck_view.handle_click_from_container(local_pos)
	elif deck_view:
		deck_view._check_click(local_pos)


# Legacy inspection expansion code removed - card now animates within existing viewport


func setup(manager: DeckManager) -> void:
	"""Legacy single-deck setup"""
	if deck_view:
		deck_view.setup(manager)


func setup_combined(swing_manager: DeckManager, modifier_manager: DeckManager) -> void:
	"""Combined deck setup - sets up both swing and modifier decks"""
	if combined_deck_view:
		combined_deck_view.setup(swing_manager, modifier_manager)


func get_deck_view() -> DeckView3D:
	"""Get the single deck view (legacy mode)"""
	return deck_view


func get_combined_deck_view() -> CombinedDeckView:
	"""Get the combined deck view (new mode)"""
	return combined_deck_view


func get_swing_deck_view() -> DeckView3D:
	"""Get the swing deck from combined view"""
	if combined_deck_view:
		return combined_deck_view.swing_deck
	return null


func get_modifier_deck_view() -> DeckView3D:
	"""Get the modifier deck from combined view"""
	if combined_deck_view:
		return combined_deck_view.modifier_deck
	return null


func is_combined_mode() -> bool:
	"""Returns true if using combined deck view"""
	return combined_deck_view != null
