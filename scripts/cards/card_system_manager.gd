extends Node
class_name CardSystemManager

## Central controller that integrates the card system with the shot lifecycle.
## This node bridges DeckManager with ModifierManager and shot system.

# References to external systems (set via setup or found automatically)
var deck_manager: DeckManager = null
var club_deck_manager: DeckManager = null
var modifier_manager: ModifierManager = null
var shot_manager: ShotManager = null
var card_library: CardLibrary = null

@export_group("Deck Configuration")
@export var starter_deck_definition: DeckDefinition
@export var club_deck_definition: DeckDefinition

# UI reference
var deck_view: DeckView3D = null
var club_deck_view: DeckView3D = null
var deck_widget: Control = null
var club_deck_widget: Control = null

# Signals for external systems
signal card_system_ready()
signal deck_changed()

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

signal turn_selection_complete(club_card: CardInstance, modifier_card: CardInstance)

var selected_club_card: CardInstance = null
var selected_modifier_card: CardInstance = null
var current_selection_ui: CardSelectionUI = null
var _current_modifier_candidates: Array[CardInstance] = []

func start_turn_selection() -> void:
	"""Begin the turn sequence: Club -> Modifier -> Shot"""
	selected_club_card = null
	selected_modifier_card = null
	_current_modifier_candidates.clear()
	club_selection_locked = false
	
	_start_club_selection()


func _start_club_selection() -> void:
	# Get available club cards
	var cards = club_deck_manager._draw_pile
	
	# Show UI
	_show_selection_ui(cards, _on_club_selected, club_deck_widget)


func _on_club_selected(card: CardInstance) -> void:
	if selected_club_card != null:
		return # Already selected
		
	selected_club_card = card
	
	# Close UI
	if current_selection_ui:
		current_selection_ui.queue_free()
		current_selection_ui = null
	
	# Move card to active pile
	club_deck_manager.draw_specific_card(card)
	
	# Apply club immediately
	_apply_club_selection(card)
	
	# Proceed to modifier selection
	# Don't auto-start modifier selection. Wait for user to click modifier deck.
	# _start_modifier_selection()


func _start_modifier_selection() -> void:
	# Guard: Don't start if already selecting or if club not selected yet
	if current_selection_ui != null:
		return
	if selected_club_card == null:
		# Optional: Shake deck or show warning?
		return

	# Draw hand for modifiers (e.g. 3 cards)
	var hand_size = 3
	_current_modifier_candidates = deck_manager.draw_candidates(hand_size)
	
	if _current_modifier_candidates.is_empty():
		# No cards? Skip to end
		_on_modifier_selected(null)
		return
		
	# Show UI
	_show_selection_ui(_current_modifier_candidates, _on_modifier_selected, deck_widget)


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
	
	# Signal completion
	turn_selection_complete.emit(selected_club_card, selected_modifier_card)


func _show_selection_ui(cards: Array[CardInstance], callback: Callable, source_widget: Control = null) -> void:
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
		if source_widget is DeckWidget:
			front_texture = source_widget.card_front_texture
	
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
	if node.get_class() == class_name_str or node.name == class_name_str:
		return node
	
	for child in node.get_children():
		var result = _recursive_find(child, class_name_str)
		if result:
			return result
	
	return null


func _setup_deck_ui() -> void:
	"""Find or create the DeckView3D component via overlay"""
	var widgets = []
	
	# Try to find MainUI first
	var main_ui = get_tree().current_scene.find_child("MainUI", true, false)
	if main_ui and main_ui.get("modifier_deck_widget"):
		if main_ui.modifier_deck_widget:
			widgets.append(main_ui.modifier_deck_widget)
		if main_ui.club_deck_widget:
			widgets.append(main_ui.club_deck_widget)
	
	# Fallback to searching Control
	if widgets.is_empty():
		var control = get_tree().current_scene.get_node_or_null("Control")
		if control:
			# Explicitly remove old HandUI/DeckUI if they exist
			var old_hand = control.get_node_or_null("HandUI")
			if old_hand: old_hand.queue_free()
			var old_deck = control.get_node_or_null("DeckUI")
			if old_deck: old_deck.queue_free()
			
			# Find all DeckWidgets in Control
			for child in control.get_children():
				if child is DeckWidget:
					widgets.append(child)
				elif child.name == "DeckOverlay" or child.name == "ClubDeckOverlay":
					# Fallback for old overlays or manually named nodes
					widgets.append(child)
	
	for widget in widgets:
		var is_club_deck = false
		
		# Determine type
		if widget is DeckWidget:
			if widget.deck_type == DeckWidget.DeckType.CLUBS:
				is_club_deck = true
		elif widget.name == "ClubDeckOverlay":
			is_club_deck = true
			
		# Setup
		if is_club_deck:
			# Club Deck
			club_deck_widget = widget
			
			# Ensure correct textures for Club Deck
			if widget is DeckWidget:
				if not widget.card_front_texture or widget.card_front_texture.resource_path.contains("card-front.png"):
					widget.card_front_texture = load("res://textures/card-front-clubs.png")
				if not widget.card_back_texture or widget.card_back_texture.resource_path.contains("card-back.png"):
					widget.card_back_texture = load("res://textures/card-back-clubs.png")
			
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
				
		else:
			# Modifier Deck (Default)
			deck_widget = widget
			
			# Ensure correct textures for Modifier Deck
			if widget is DeckWidget:
				if not widget.card_front_texture:
					widget.card_front_texture = load("res://textures/card-front.png")
				if not widget.card_back_texture:
					widget.card_back_texture = load("res://textures/card-back.png")
			
			if widget.has_method("get_deck_view"):
				deck_view = widget.get_deck_view()
				widget.setup(deck_manager)
			else:
				deck_view = widget.get_node_or_null("SubViewport/DeckView3D")
				if deck_view:
					deck_view.setup(deck_manager)
					# Use SELECT_FROM_UI mode to trigger custom logic instead of auto-draw
					deck_view.interaction_mode = DeckView3D.InteractionMode.SELECT_FROM_UI
			
			# Connect modifier deck click to modifier selection
			if deck_view:
				if deck_view.request_club_selection.is_connected(start_turn_selection):
					deck_view.request_club_selection.disconnect(start_turn_selection)
				
				if not deck_view.request_club_selection.is_connected(_start_modifier_selection):
					deck_view.request_club_selection.connect(_start_modifier_selection)


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
	"""Apply a card's effects to the modifier system"""
	if not card_instance or not modifier_manager:
		return
		
	# If it's a CLUB card, we don't create a modifier, we set the club
	if card_instance.data.card_type == CardData.CardType.CLUB:
		_apply_club_selection(card_instance)
		return
	
	# Create modifier wrapper for the card
	var card_modifier = CardModifier.new(card_instance)
	
	# Add to modifier manager
	modifier_manager.add_modifier(card_modifier)
	active_card_modifiers.append(card_modifier)


func get_deck_manager() -> DeckManager:
	return deck_manager


func get_card_library() -> CardLibrary:
	return card_library


# --- Shot Lifecycle Hooks ---

func _on_shot_started(context: ShotContext) -> void:
	"""Called when a new shot begins"""
	# Clear active card modifiers from previous shot
	_clear_active_modifiers()
	
	# Clear active cards in deck manager (move to discard)
	if deck_manager:
		deck_manager.clear_active_cards()
	if club_deck_manager:
		club_deck_manager.clear_active_cards()


func _on_shot_completed(context: ShotContext) -> void:
	"""Called when shot finishes"""
	# Clear active modifiers
	_clear_active_modifiers()
	
	# Unlock club selection for next shot
	club_selection_locked = false


func _clear_active_modifiers() -> void:
	"""Remove all active card modifiers from the system"""
	if modifier_manager:
		for card_mod in active_card_modifiers:
			modifier_manager.remove_modifier(card_mod)
	
	active_card_modifiers.clear()


# --- Event Handlers ---

func _on_card_activated(card: CardInstance) -> void:
	"""Handle card activated from deck manager"""
	activate_card_modifier(card)
