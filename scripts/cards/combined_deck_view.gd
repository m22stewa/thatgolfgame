extends Node3D
class_name CombinedDeckView

## Combined view showing swing deck (left) and modifier deck (right) side by side
## This view handles all input and routes to the correct deck for better performance.

# Deck references
@onready var swing_deck: DeckView3D = $SwingDeck
@onready var modifier_deck: DeckView3D = $ModifierDeck
@onready var camera: Camera3D = $Camera3D

# Manager references (set externally)
var swing_deck_manager: DeckManager = null
var modifier_deck_manager: DeckManager = null

# Configuration exports for each deck
@export_group("Swing Deck (Left)")
@export var swing_card_back_texture: Texture2D
@export var swing_card_front_texture: Texture2D
@export var swing_interaction_mode: DeckView3D.InteractionMode = DeckView3D.InteractionMode.SELECT_FROM_UI

@export_group("Modifier Deck (Right)")
@export var modifier_card_back_texture: Texture2D
@export var modifier_card_front_texture: Texture2D
@export var modifier_interaction_mode: DeckView3D.InteractionMode = DeckView3D.InteractionMode.SELECT_FROM_UI

# Signals (forwarded from child decks)
signal swing_request_club_selection()
signal modifier_request_club_selection()
signal swing_card_inspection_requested(card_instance: CardInstance)
signal modifier_card_inspection_requested(card_instance: CardInstance)

func _ready() -> void:
	print("[CombinedDeckView] _ready called")
	
	# Disable cameras on child deck views (we use our own camera)
	if swing_deck and swing_deck.has_node("Camera3D"):
		swing_deck.get_node("Camera3D").queue_free()
	if modifier_deck and modifier_deck.has_node("Camera3D"):
		modifier_deck.get_node("Camera3D").queue_free()
	
	# Update camera references in child decks to use our camera
	if swing_deck:
		swing_deck.camera = camera
		swing_deck.set_process_unhandled_input(false)  # We handle input centrally
		print("[CombinedDeckView] Swing deck input disabled")
	if modifier_deck:
		modifier_deck.camera = camera
		modifier_deck.set_process_unhandled_input(false)  # We handle input centrally
		print("[CombinedDeckView] Modifier deck input disabled")
	
	# Apply exported configurations
	_apply_deck_configs()
	
	# Wire up signals from swing deck
	if swing_deck:
		swing_deck.request_club_selection.connect(_on_swing_request_club_selection)
		swing_deck.card_inspection_requested.connect(_on_swing_card_inspection_requested)
	
	# Wire up signals from modifier deck
	if modifier_deck:
		modifier_deck.request_club_selection.connect(_on_modifier_request_club_selection)
		modifier_deck.card_inspection_requested.connect(_on_modifier_card_inspection_requested)


func _apply_deck_configs() -> void:
	"""Apply exported configuration to child decks"""
	if swing_deck:
		if swing_card_back_texture:
			swing_deck.card_back_texture = swing_card_back_texture
		if swing_card_front_texture:
			swing_deck.card_front_texture = swing_card_front_texture
		swing_deck.interaction_mode = swing_interaction_mode
	
	if modifier_deck:
		if modifier_card_back_texture:
			modifier_deck.card_back_texture = modifier_card_back_texture
		if modifier_card_front_texture:
			modifier_deck.card_front_texture = modifier_card_front_texture
		modifier_deck.interaction_mode = modifier_interaction_mode


# Cursor hover state
var _last_hover_target: String = ""  # "deck", "card", or ""

func _unhandled_input(event: InputEvent) -> void:
	"""Central input handler - only used when NOT inside a SubViewport"""
	# When inside a SubViewportContainer, input is forwarded via handle_click_from_container
	if get_viewport() != get_tree().root:
		return  # We're in a SubViewport, input comes from container
	
	if event is InputEventMouseMotion:
		_handle_hover(event.position)
		return
	
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	
	_handle_click(event.position)


func handle_click_from_container(viewport_pos: Vector2) -> void:
	"""Called by DeckWidget to handle clicks with SubViewport-relative coordinates"""
	_handle_click(viewport_pos)


func handle_hover_from_container(viewport_pos: Vector2) -> void:
	"""Called by DeckWidget to handle hover with SubViewport-relative coordinates"""
	_handle_hover(viewport_pos)


func _handle_hover(screen_pos: Vector2) -> void:
	"""Check what the mouse is hovering over and update cursor"""
	if not camera:
		return
	
	var cursor_manager = get_node_or_null("/root/CursorManager")
	if not cursor_manager:
		return
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 100.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	
	var result = space_state.intersect_ray(query)
	
	var new_hover_target = ""
	if result:
		var collider = result.collider
		if collider.name == "DeckClickArea":
			new_hover_target = "deck"
		elif collider is Card3D:
			new_hover_target = "card"
	
	# Only update cursor if hover target changed
	if new_hover_target != _last_hover_target:
		_last_hover_target = new_hover_target
		match new_hover_target:
			"deck":
				cursor_manager.set_hand_open()
			"card":
				cursor_manager.set_zoom()
			_:
				cursor_manager.set_default()


func _handle_click(screen_pos: Vector2) -> void:
	"""Handle click by raycasting to find deck or card"""
	if not camera:
		print("[CombinedDeckView] No camera!")
		return
	
	print("[CombinedDeckView] Click at %s" % [screen_pos])
	
	# Check if either deck is inspecting - close on click
	if swing_deck and swing_deck.inspected_card:
		swing_deck._close_inspection()
		return
	if modifier_deck and modifier_deck.inspected_card:
		modifier_deck._close_inspection()
		return
	
	# Raycast to find what was clicked
	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)
	var to = from + dir * 100.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	
	var result = space_state.intersect_ray(query)
	
	if not result:
		print("[CombinedDeckView] Raycast hit nothing")
		return
	
	var collider = result.collider
	print("[CombinedDeckView] Raycast hit: %s" % collider.name)
	
	# If we hit a card, handle it
	if collider is Card3D:
		var owner_deck = _get_owner_deck(collider)
		if owner_deck:
			owner_deck._on_card_clicked(collider)
		return
	
	# If we hit a deck click area, determine which deck and trigger click
	var parent = collider.get_parent()
	if parent and parent.name == "DeckAnchor":
		var owner_deck = _get_owner_deck(collider)
		if owner_deck:
			print("[CombinedDeckView] Deck click area hit for %s" % ("swing" if owner_deck == swing_deck else "modifier"))
			owner_deck._on_deck_clicked()


func _get_owner_deck(node: Node) -> DeckView3D:
	"""Find which deck owns this node"""
	var current = node
	while current:
		if current == swing_deck:
			return swing_deck
		if current == modifier_deck:
			return modifier_deck
		current = current.get_parent()
	return null


func setup(swing_manager: DeckManager, modifier_manager: DeckManager) -> void:
	"""Setup both deck managers"""
	print("[CombinedDeckView] setup called - swing_manager=%s, modifier_manager=%s" % [swing_manager, modifier_manager])
	swing_deck_manager = swing_manager
	modifier_deck_manager = modifier_manager
	
	if swing_deck and swing_manager:
		swing_deck.setup(swing_manager)
		print("[CombinedDeckView] Swing deck setup complete, deck_manager=%s" % swing_deck.deck_manager)
	else:
		print("[CombinedDeckView] WARNING: swing_deck=%s, swing_manager=%s" % [swing_deck, swing_manager])
	
	if modifier_deck and modifier_manager:
		modifier_deck.setup(modifier_manager)
		print("[CombinedDeckView] Modifier deck setup complete, deck_manager=%s" % modifier_deck.deck_manager)
	else:
		print("[CombinedDeckView] WARNING: modifier_deck=%s, modifier_manager=%s" % [modifier_deck, modifier_manager])


# Swing deck signal handlers
func _on_swing_request_club_selection() -> void:
	swing_request_club_selection.emit()

func _on_swing_card_inspection_requested(card_instance: CardInstance) -> void:
	swing_card_inspection_requested.emit(card_instance)


# Modifier deck signal handlers
func _on_modifier_request_club_selection() -> void:
	modifier_request_club_selection.emit()

func _on_modifier_card_inspection_requested(card_instance: CardInstance) -> void:
	modifier_card_inspection_requested.emit(card_instance)


# Utility methods for controlling both decks
func set_swing_interaction_mode(mode: DeckView3D.InteractionMode) -> void:
	swing_interaction_mode = mode
	if swing_deck:
		swing_deck.interaction_mode = mode

func set_modifier_interaction_mode(mode: DeckView3D.InteractionMode) -> void:
	modifier_interaction_mode = mode
	if modifier_deck:
		modifier_deck.interaction_mode = mode

func dim_all_played_cards() -> void:
	"""Dim played cards in both decks"""
	if swing_deck:
		swing_deck.dim_played_cards()
	if modifier_deck:
		modifier_deck.dim_played_cards()

func undim_all_cards() -> void:
	"""Restore normal appearance to all cards in both decks"""
	if swing_deck:
		swing_deck.undim_all_cards()
	if modifier_deck:
		modifier_deck.undim_all_cards()
