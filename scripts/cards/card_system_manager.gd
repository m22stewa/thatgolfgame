extends Node
class_name CardSystemManager

## Central controller that integrates the card system with the shot lifecycle.
## This node bridges DeckManager with ModifierManager and shot system.

# References to external systems (set via setup or found automatically)
var deck_manager: DeckManager = null
var club_deck_manager: DeckManager = null  # "Swing Deck" in the new flow
var modifier_manager: ModifierManager = null
var shot_manager: ShotManager = null
var card_library: CardLibrary = null
var shot_ui: ShotUI = null  # For updating swing button prerequisites

@export_group("Deck Configuration")
@export var starter_deck_definition: DeckDefinition
@export var club_deck_definition: DeckDefinition  # This is the "Swing Deck"

# UI reference
var deck_view: DeckView3D = null
var club_deck_view: DeckView3D = null
var deck_widget: Control = null  # Modifier deck widget
var club_deck_widget: Control = null  # Swing deck widget (legacy)
var swing_hand: SwingHand = null  # Fanned hand display for swing cards
# Swing card slot is now handled by SwingHand3D (3D card system)
var items_bar: ItemsBar = null  # Item slots display

# Signals for external systems
signal card_system_ready()
signal deck_changed()
signal swing_card_selected(card: CardInstance)  # When player picks from swing deck
signal modifier_card_drawn(card: CardInstance)  # When player draws from modifier deck

# Active card modifiers (cards that are currently affecting the shot)
var active_card_modifiers: Array[CardModifier] = []

# State
var club_selection_locked: bool = false


func _ready() -> void:
	# Auto-find systems if not explicitly set
	# Use deferred to ensure scene tree is ready
	call_deferred("_auto_setup")


func _auto_setup() -> void:
	"""Find and connect to required systems"""
	# Find ModifierManager if not already set
	if modifier_manager == null:
		modifier_manager = _find_node_by_class("ModifierManager")
	
	# Find ShotManager if not already set
	if shot_manager == null:
		shot_manager = _find_node_by_class("ShotManager")
	
	# Find ShotUI if not already set
	if shot_ui == null:
		shot_ui = _find_node_by_class("ShotUI")
	
	# Connect to shot lifecycle if ShotManager found
	if shot_manager:
		if shot_manager.has_signal("shot_started") and not shot_manager.shot_started.is_connected(_on_shot_started):
			shot_manager.shot_started.connect(_on_shot_started)
		if shot_manager.has_signal("shot_completed") and not shot_manager.shot_completed.is_connected(_on_shot_completed):
			shot_manager.shot_completed.connect(_on_shot_completed)
	
	# Create DeckManager if not present
	if deck_manager == null:
		deck_manager = DeckManager.new()
		deck_manager.name = "DeckManager"
		add_child(deck_manager)
	
	# Create ClubDeckManager if not present
	if club_deck_manager == null:
		club_deck_manager = DeckManager.new()
		club_deck_manager.name = "ClubDeckManager"
		add_child(club_deck_manager)
	
	# Connect deck signals
	if not deck_manager.card_activated.is_connected(_on_card_activated):
		deck_manager.card_activated.connect(_on_card_activated)
	if not club_deck_manager.card_activated.is_connected(_on_card_activated):
		club_deck_manager.card_activated.connect(_on_card_activated)
	
	# Create CardLibrary if not present
	if card_library == null:
		card_library = CardLibrary.new()
		card_library.name = "CardLibrary"
		add_child(card_library)
	
	# Setup UI
	_setup_deck_ui()
	
	card_system_ready.emit()


# --- Turn Selection Flow ---
# New flow: Tile -> Swing Deck -> Modifier Deck -> Swing Button
# Tile selection is handled by hex_grid and auto-selects club
# This manager handles swing deck and modifier deck selection

signal turn_selection_complete(swing_card: CardInstance, modifier_card: CardInstance)

var selected_club_card: CardInstance = null  # Now "swing card" (kept name for compatibility)
var selected_modifier_card: CardInstance = null
var current_selection_ui: CardSelectionUI = null
var _current_modifier_candidates: Array[CardInstance] = []

func start_turn_selection() -> void:
	"""Begin the swing deck selection. Called when user clicks swing deck."""
	selected_club_card = null
	selected_modifier_card = null
	_current_modifier_candidates.clear()
	club_selection_locked = false
	
	_start_swing_deck_selection()


func _start_swing_deck_selection() -> void:
	"""Show swing deck cards for selection"""
	# Get available swing cards
	var cards = club_deck_manager._draw_pile
	
	if cards.is_empty():
		# No cards available - auto-complete this step
		if shot_ui:
			shot_ui.set_swing_card_selected(true)
		return
	
	# Show UI
	_show_selection_ui(cards, _on_club_selected, club_deck_widget, club_deck_view)


func _on_club_selected(card: CardInstance) -> void:
	"""Player selected a card from the swing deck.
	   In the new flow, this is a shot modifier, not a club selector.
	   Club is auto-selected based on target tile distance."""
	if selected_club_card != null:
		return # Already selected
		
	selected_club_card = card
	
	# Close UI
	if current_selection_ui:
		current_selection_ui.queue_free()
		current_selection_ui = null
	
	# Move card to active pile
	club_deck_manager.draw_specific_card(card)
	
	# Apply card as modifier (not club selection)
	# Only apply club selection if card has target_club AND user hasn't locked a tile
	if card.data.target_club and not card.data.target_club.is_empty():
		# Legacy club card - apply it (this may override auto-selected club)
		_apply_club_selection(card)
	else:
		# Shot modifier card - apply its effects
		activate_card_modifier(card)
	
	# Notify UI that swing card is selected
	print("[CardSystem] Swing card selected: %s" % card.data.card_name)
	swing_card_selected.emit(card)
	if shot_ui:
		print("[CardSystem] Calling shot_ui.set_swing_card_selected(true)")
		shot_ui.set_swing_card_selected(true)
	else:
		push_warning("[CardSystem] shot_ui is null, cannot set swing_card_selected!")
	
	# Proceed to modifier selection
	# Don't auto-start modifier selection. Wait for user to click modifier deck.
	# _start_modifier_selection()


func _start_modifier_selection() -> void:
	print("[CardSystem] _start_modifier_selection called")
	
	# Guard: Don't start if already selecting
	if current_selection_ui != null:
		print("[CardSystem] Already showing selection UI, skipping")
		return
	
	# In new flow, modifier selection can happen at any time after tile is selected
	# No need to require swing card first

	# Draw hand for modifiers (e.g. 3 cards)
	var hand_size = 3
	_current_modifier_candidates = deck_manager.draw_candidates(hand_size)
	
	print("[CardSystem] Drew %d modifier candidates" % _current_modifier_candidates.size())
	
	if _current_modifier_candidates.is_empty():
		# No cards? Skip to end
		print("[CardSystem] No modifier candidates, auto-completing")
		_on_modifier_selected(null)
		return
		
	# Show UI
	_show_selection_ui(_current_modifier_candidates, _on_modifier_selected, deck_widget, deck_view)


func _on_modifier_selected(card: CardInstance) -> void:
	selected_modifier_card = card
	
	# Close UI
	if current_selection_ui:
		current_selection_ui.queue_free()
		current_selection_ui = null
	
	# Handle candidates
	if card:
		# Play the selected card
		deck_manager.play_candidate(card)
		activate_card_modifier(card)
		
		# Remove from candidates list so we don't discard it
		_current_modifier_candidates.erase(card)
	
	# Discard the rest
	deck_manager.discard_candidates(_current_modifier_candidates)
	_current_modifier_candidates.clear()
	
	# Notify UI that modifier is drawn
	print("[CardSystem] Modifier card drawn: %s" % (card.data.card_name if card else "(none)"))
	modifier_card_drawn.emit(card)
	if shot_ui:
		print("[CardSystem] Calling shot_ui.set_modifier_drawn(true)")
		shot_ui.set_modifier_drawn(true)
	else:
		push_warning("[CardSystem] shot_ui is null, cannot set modifier_drawn!")
	
	# Signal completion
	turn_selection_complete.emit(selected_club_card, selected_modifier_card)


func _show_selection_ui(cards: Array[CardInstance], callback: Callable, source_widget: Control = null, source_deck_view: DeckView3D = null) -> void:
	var selection_ui_scene = load("res://scenes/ui/card_selection_ui.tscn")
	if not selection_ui_scene:
		push_error("CardSelectionUI scene not found!")
		return
		
	var selection_ui = selection_ui_scene.instantiate()
	current_selection_ui = selection_ui
	
	# Calculate deck position
	var deck_pos = Vector2.ZERO
	var front_texture = null
	
	if source_widget:
		deck_pos = source_widget.global_position + (source_widget.size / 2.0)
	
	# Get texture from deck view (more reliable than widget)
	if source_deck_view:
		front_texture = source_deck_view.card_front_texture
	
	# Add to UI layer
	var control = get_tree().current_scene.get_node_or_null("Control")
	# Or find MainUI
	if not control:
		control = get_tree().current_scene.find_child("MainUI", true, false)
		
	if control:
		control.add_child(selection_ui)
		selection_ui.setup(cards, deck_pos, front_texture)
		selection_ui.card_selected.connect(callback)


func _select_club_card(card: CardInstance) -> void:
	"""Player selected a club from the list"""
	club_deck_manager.draw_specific_card(card)


func _apply_club_selection(card_instance: CardInstance) -> void:
	"""Handle club card selection"""
	var club_name = card_instance.data.target_club
	if club_name.is_empty():
		return
		
	# Find HexGrid (hole controller) to set the club
	var hex_grid = _find_node_by_class("Node3D") # HexGrid extends Node3D and is usually root or close
	# Better way: use shot_manager's hole_controller reference
	if shot_manager and shot_manager.hole_controller:
		if shot_manager.hole_controller.has_method("set_club_by_name"):
			shot_manager.hole_controller.set_club_by_name(club_name)
			
			# Lock selection after choosing
			club_selection_locked = true


func _find_node_by_class(class_name_str: String) -> Node:
	"""Search the scene tree for a node of the given class"""
	var root = get_tree().current_scene
	return _recursive_find(root, class_name_str)


func _recursive_find(node: Node, class_name_str: String) -> Node:
	# Check built-in class name
	if node.get_class() == class_name_str:
		return node
	# Check node name
	if node.name == class_name_str:
		return node
	# Check script class name (for custom classes like ShotUI, ShotManager, etc.)
	var script = node.get_script()
	if script and script.get_global_name() == class_name_str:
		return node
	
	for child in node.get_children():
		var result = _recursive_find(child, class_name_str)
		if result:
			return result
	
	return null


func _setup_deck_ui() -> void:
	"""Find and setup deck widgets - supports swing hand, card slot, and modifier deck"""
	
	# Try to find MainUI first
	var main_ui = get_tree().current_scene.find_child("MainUI", true, false)
	if not main_ui:
		push_warning("[CardSystem] MainUI not found")
		return
	
	# Setup SwingHand for swing cards (fanned display at bottom)
	if main_ui.get("swing_hand") and main_ui.swing_hand:
		_setup_swing_hand(main_ui.swing_hand)
	
	# Swing card slot is now part of SwingHand3D (3D card system)
	
	# Setup ItemsBar
	if main_ui.get("items_bar") and main_ui.items_bar:
		items_bar = main_ui.items_bar
	
	# Setup Modifier deck widget
	if main_ui.get("modifier_deck_widget") and main_ui.modifier_deck_widget and main_ui.modifier_deck_widget.visible:
		_setup_modifier_deck(main_ui.modifier_deck_widget)
	
	# Look for combined mode DeckWidget (legacy - for modifier deck only now)
	for child in main_ui.get_children():
		if child is DeckWidget and child.visible and child.is_combined_mode():
			_setup_combined_deck_mode(child)
			break


func _setup_swing_hand(hand: SwingHand) -> void:
	"""Setup the SwingHand for displaying swing cards as a fanned hand"""
	print("[CardSystem] Setting up SwingHand for swing cards")
	swing_hand = hand
	
	# Setup hand with swing deck manager
	swing_hand.setup(club_deck_manager)
	
	# Connect hand signals for card selection
	if not swing_hand.card_selected.is_connected(_on_swing_hand_card_selected):
		swing_hand.card_selected.connect(_on_swing_hand_card_selected)
	if not swing_hand.card_played.is_connected(_on_swing_hand_card_played):
		swing_hand.card_played.connect(_on_swing_hand_card_played)
	if swing_hand.has_signal("card_unplayed") and not swing_hand.card_unplayed.is_connected(_on_swing_hand_card_unplayed):
		swing_hand.card_unplayed.connect(_on_swing_hand_card_unplayed)
	
	print("[CardSystem] SwingHand setup complete")


# _setup_swing_card_slot removed - swing cards now handled by SwingHand3D


func _setup_modifier_deck(widget: DeckWidget) -> void:
	"""Setup standalone modifier deck widget"""
	print("[CardSystem] Setting up modifier deck widget")
	deck_widget = widget
	
	if widget.has_method("get_deck_view"):
		deck_view = widget.get_deck_view()
		widget.setup(deck_manager)
	
	# Connect modifier deck signals
	if deck_view and not deck_view.request_club_selection.is_connected(_start_modifier_selection):
		deck_view.request_club_selection.connect(_start_modifier_selection)
	
	print("[CardSystem] Modifier deck setup complete")


func _on_swing_hand_card_selected(card: CardInstance) -> void:
	"""Handler when a card is selected (hovered/clicked) in the swing hand"""
	print("[CardSystem] Swing hand card selected: %s" % (card.data.card_name if card else "null"))
	# This is just highlighting, no action needed


func _on_swing_hand_card_played(card: CardInstance) -> void:
	"""Handler when a card is played from the swing hand (clicked twice to play)"""
	if not card:
		return
	
	# The card needs to go to the swing card slot
	# For now, just trigger the same logic as slot drop
	_on_swing_slot_card_dropped(card)


func _on_swing_slot_card_dropped(card: CardInstance) -> void:
	"""Handler when a swing card is dropped into the slot"""
	if not card:
		return
	
	# Allow replacing the currently selected swing card.
	if selected_club_card != null and selected_club_card != card:
		_clear_selected_swing_card()
	elif selected_club_card == card:
		return
	
	print("[CardSystem] Swing card played to slot: %s" % card.data.card_name)
	selected_club_card = card
	
	# Do NOT consume the card yet; the player may put it back or swap it.
	# The card is consumed when the shot starts.
	
	# Apply card as modifier (shot modifier, not club selection)
	if card.data.target_club and not card.data.target_club.is_empty():
		# Legacy club card - apply it
		_apply_club_selection(card)
	else:
		# Shot modifier card - apply its effects
		activate_card_modifier(card)
	
	# Notify UI that swing card is selected
	swing_card_selected.emit(card)
	if shot_ui:
		shot_ui.set_swing_card_selected(true)
	
	# Refresh hand display
	# Note: Do not refresh/rebuild the hand here; the card was moved visually into the slot,
	# but the deck state hasn't changed yet. Rebuilding would re-add it to the hand.


func _on_swing_hand_card_unplayed(card: CardInstance) -> void:
	"""Handler when a swing card is removed from the swing slot (put back in hand)."""
	if not card:
		return
	if selected_club_card != card:
		return
	
	_clear_selected_swing_card()
	
	# Notify UI and refresh AOE visuals.
	if shot_ui:
		shot_ui.set_swing_card_selected(false)
	_refresh_aoe_display()


func _clear_selected_swing_card() -> void:
	"""Clear the currently selected swing card and remove its modifier effects."""
	if selected_club_card == null:
		return
	
	# Remove matching card modifier (only one swing card allowed).
	var to_remove: Array = []
	for card_mod in active_card_modifiers:
		if card_mod is CardModifier and card_mod.card == selected_club_card:
			to_remove.append(card_mod)
	for card_mod in to_remove:
		if modifier_manager:
			modifier_manager.remove_modifier(card_mod)
		active_card_modifiers.erase(card_mod)
	
	selected_club_card = null
	club_selection_locked = false

	# Reset preview context fields and re-apply remaining modifiers (lie, etc.).
	if shot_manager and shot_manager.current_context and modifier_manager:
		var ctx := shot_manager.current_context
		ctx.distance_mod = 0
		ctx.accuracy_mod = 0
		ctx.roll_mod = 0
		ctx.curve_strength = 0.0
		ctx.wind_curve = 0
		ctx.aoe_radius = 0
		ctx.aoe_shape = "circle"
		modifier_manager.apply_before_aim(ctx)


func _setup_combined_deck_mode(widget: DeckWidget) -> void:
	"""Setup combined deck mode where both swing and modifier decks are in one widget"""
	print("[CardSystem] Setting up combined deck mode")
	
	# Store the widget reference
	deck_widget = widget
	club_deck_widget = widget  # Both point to same widget in combined mode
	
	# Get the individual deck views from the combined view
	club_deck_view = widget.get_swing_deck_view()
	deck_view = widget.get_modifier_deck_view()
	
	# Setup both deck managers
	widget.setup_combined(club_deck_manager, deck_manager)
	
	# Connect swing deck signals
	if not widget.swing_request_club_selection.is_connected(start_turn_selection):
		widget.swing_request_club_selection.connect(start_turn_selection)
		print("[CardSystem] Swing deck connected to start_turn_selection")
	
	# Connect modifier deck signals
	if not widget.modifier_request_club_selection.is_connected(_start_modifier_selection):
		widget.modifier_request_club_selection.connect(_start_modifier_selection)
		print("[CardSystem] Modifier deck connected to _start_modifier_selection")
	
	print("[CardSystem] Combined deck mode setup complete")


func _setup_legacy_modifier_deck(widget: DeckWidget) -> void:
	"""Setup legacy separate modifier deck widget"""
	deck_widget = widget
	
	if widget.has_method("get_deck_view"):
		deck_view = widget.get_deck_view()
		widget.setup(deck_manager)
	else:
		deck_view = widget.get_node_or_null("SubViewport/DeckView3D")
		if deck_view:
			deck_view.setup(deck_manager)
			deck_view.interaction_mode = DeckView3D.InteractionMode.SELECT_FROM_UI
	
	# Connect modifier deck click to modifier selection
	if deck_view:
		if deck_view.request_club_selection.is_connected(start_turn_selection):
			deck_view.request_club_selection.disconnect(start_turn_selection)
		if not deck_view.request_club_selection.is_connected(_start_modifier_selection):
			deck_view.request_club_selection.connect(_start_modifier_selection)


func _setup_legacy_club_deck(widget: DeckWidget) -> void:
	"""Setup legacy separate club/swing deck widget"""
	club_deck_widget = widget
	
	if widget.has_method("get_deck_view"):
		club_deck_view = widget.get_deck_view()
		widget.setup(club_deck_manager)
	else:
		club_deck_view = widget.get_node_or_null("SubViewport/DeckView3D")
		if club_deck_view:
			club_deck_view.setup(club_deck_manager)
			club_deck_view.interaction_mode = DeckView3D.InteractionMode.SELECT_FROM_UI
	
	if club_deck_view and not club_deck_view.request_club_selection.is_connected(start_turn_selection):
		club_deck_view.request_club_selection.connect(start_turn_selection)


# --- Public API ---

func initialize_starter_deck() -> void:
	"""Initialize the deck with starter cards for a new run"""
	# Reset lock
	club_selection_locked = false

	# Ensure ClubDeckManager exists (it might not be set by external caller)
	if club_deck_manager == null:
		club_deck_manager = DeckManager.new()
		club_deck_manager.name = "ClubDeckManager"
		add_child(club_deck_manager)
		# Connect signal
		if not club_deck_manager.card_activated.is_connected(_on_card_activated):
			club_deck_manager.card_activated.connect(_on_card_activated)

	if not card_library or not deck_manager:
		push_warning("CardSystemManager: Cannot init deck - systems not ready")
		return
	
	# Initialize Modifier Deck
	var starter_cards: Array[CardInstance] = []
	if starter_deck_definition:
		var card_datas = starter_deck_definition.get_all_cards()
		for data in card_datas:
			starter_cards.append(CardInstance.create_from_data(data))
	else:
		# Fallback to library default
		starter_cards = card_library.get_starter_deck()
	
	deck_manager.initialize_with_instances(starter_cards)
	
	# Initialize Club Deck
	if club_deck_manager:
		var club_cards: Array[CardInstance] = []
		if club_deck_definition:
			var card_datas = club_deck_definition.get_all_cards()
			for data in card_datas:
				club_cards.append(CardInstance.create_from_data(data))
		else:
			# Fallback to library default
			club_cards = card_library.get_club_deck()
			
		club_deck_manager.initialize_with_instances(club_cards)


func activate_card_modifier(card_instance: CardInstance) -> void:
	"""Apply a card's effects to the modifier system and update visuals"""
	if not card_instance or not modifier_manager:
		return
		
	# If it's a CLUB card, we don't create a modifier, we set the club
	if card_instance.data.card_type == CardData.CardType.CLUB:
		_apply_club_selection(card_instance)
		return
	
	print("[CardSystem] Activating card modifier: %s" % card_instance.data.card_name)
	
	# Create modifier wrapper for the card
	var card_modifier = CardModifier.new(card_instance)
	
	# Add to modifier manager - this applies effects to shot_context
	modifier_manager.add_modifier(card_modifier)
	active_card_modifiers.append(card_modifier)
	
	# Apply the modifier's effects to shot context immediately
	if shot_manager and shot_manager.current_context:
		print("[CardSystem] Applying modifier to shot context")
		if card_modifier.has_method("apply_before_aim"):
			card_modifier.apply_before_aim(shot_manager.current_context)
		print("[CardSystem] Shot context after modifier - accuracy_mod: %d, distance_mod: %d, roll_mod: %d" % [
			shot_manager.current_context.accuracy_mod,
			shot_manager.current_context.distance_mod,
			shot_manager.current_context.roll_mod
		])
	
	# Refresh AOE display if hex_grid is available (in case accuracy changed)
	print("[CardSystem] Refreshing AOE display")
	_refresh_aoe_display()


func _refresh_aoe_display() -> void:
	"""Refresh the AOE display and trajectory on hex_grid after modifiers change"""
	var hex_grid = null
	if shot_manager and shot_manager.hole_controller:
		hex_grid = shot_manager.hole_controller
	
	if hex_grid:
		if hex_grid.has_method("refresh_aoe_display"):
			hex_grid.refresh_aoe_display()
		if hex_grid.has_method("_refresh_trajectory"):
			hex_grid._refresh_trajectory()


func get_deck_manager() -> DeckManager:
	return deck_manager


func get_card_library() -> CardLibrary:
	return card_library


# --- Shot Lifecycle Hooks ---

func _on_shot_started(context: ShotContext) -> void:
	"""Called when a new shot begins"""
	# NOTE: We don't re-apply modifiers here because shot_manager._apply_modifiers_before_aim()
	# will call modifier_manager.apply_before_aim() which handles all modifiers including cards.
	# The card modifiers are already registered with modifier_manager.
	print("[CardSystem] Shot started - %d active card modifiers registered with modifier_manager" % active_card_modifiers.size())
	
	# Consume the selected swing card now that the shot is committed.
	if selected_club_card != null and club_deck_manager:
		club_deck_manager.play_card(selected_club_card)
		club_selection_locked = true


func _on_shot_completed(context: ShotContext) -> void:
	"""Called when shot finishes"""
	# Clear active modifiers
	_clear_active_modifiers()
	selected_club_card = null
	
	# Dim played cards at end of shot
	dim_played_cards()
	
	# Reset the context modifier values so they don't persist to next shot preview
	if shot_manager and shot_manager.current_context:
		shot_manager.current_context.distance_mod = 0
		shot_manager.current_context.accuracy_mod = 0
		shot_manager.current_context.roll_mod = 0
		shot_manager.current_context.curve_strength = 0.0
		shot_manager.current_context.wind_curve = 0
	
	# Clear active cards in deck manager (move to discard)
	if deck_manager:
		deck_manager.clear_active_cards()
	if club_deck_manager:
		club_deck_manager.clear_active_cards()
	
	# Unlock club selection for next shot
	club_selection_locked = false
	if shot_ui:
		shot_ui.set_swing_card_selected(false)
	
	# Refresh AOE and trajectory display to reset visuals
	_refresh_aoe_display()
	if shot_manager and shot_manager.hole_controller:
		var hex_grid = shot_manager.hole_controller
		if hex_grid.has_method("_refresh_trajectory"):
			hex_grid._refresh_trajectory()


func _clear_active_modifiers() -> void:
	"""Remove all active card modifiers from the system"""
	if modifier_manager:
		for card_mod in active_card_modifiers:
			modifier_manager.remove_modifier(card_mod)
	
	active_card_modifiers.clear()


func dim_played_cards() -> void:
	"""Dim all drawn cards to indicate they've been used this hole"""
	if deck_view:
		deck_view.dim_played_cards()
	if club_deck_view:
		club_deck_view.dim_played_cards()


func undim_all_cards() -> void:
	"""Restore normal appearance to all cards (for new hole)"""
	if deck_view:
		deck_view.undim_all_cards()
	if club_deck_view:
		club_deck_view.undim_all_cards()


# --- Event Handlers ---

func _on_card_activated(card: CardInstance) -> void:
	"""Handle card activated from deck manager (direct draw, not selection UI)"""
	print("[CardSystem] _on_card_activated: %s" % card.data.card_name)
	
	# Skip cards from swing deck - they're handled by _on_club_selected
	if club_deck_manager and card in club_deck_manager._active_cards:
		print("[CardSystem] Card is from swing deck, skipping (handled by _on_club_selected)")
		return
	
	activate_card_modifier(card)
	
	# Also notify shot_ui that a modifier was drawn (if this is from modifier deck)
	# Check if card came from modifier deck (not swing deck)
	if deck_manager and card in deck_manager._active_cards:
		print("[CardSystem] Card is from modifier deck, setting modifier_drawn=true")
		modifier_card_drawn.emit(card)
		if shot_ui:
			shot_ui.set_modifier_drawn(true)
