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


func _on_request_club_selection() -> void:
	"""Open club selection UI"""
	# Get available cards
	var cards = club_deck_manager._draw_pile
	
	# Instantiate the new UI
	var selection_ui_scene = load("res://scenes/ui/card_selection_ui.tscn")
	if not selection_ui_scene:
		push_error("CardSelectionUI scene not found!")
		return
		
	var selection_ui = selection_ui_scene.instantiate()
	
	# Calculate deck position for animation origin
	var deck_pos = Vector2.ZERO
	var front_texture = null
	
	if club_deck_widget:
		# If it's a Control (DeckWidget or SubViewportContainer)
		deck_pos = club_deck_widget.global_position + (club_deck_widget.size / 2.0)
		if club_deck_widget is DeckWidget:
			front_texture = club_deck_widget.card_front_texture
	
	# Add to UI layer
	var control = get_tree().current_scene.get_node_or_null("Control")
	if control:
		control.add_child(selection_ui)
		selection_ui.setup(cards, deck_pos, front_texture)
		selection_ui.card_selected.connect(_select_club_card)


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
	var control = get_tree().current_scene.get_node_or_null("Control")
	if not control: return
	
	# Explicitly remove old HandUI/DeckUI if they exist
	var old_hand = control.get_node_or_null("HandUI")
	if old_hand: old_hand.queue_free()
	var old_deck = control.get_node_or_null("DeckUI")
	if old_deck: old_deck.queue_free()
	
	# Find all DeckWidgets in Control
	var widgets = []
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
			if widget.has_method("get_deck_view"):
				club_deck_view = widget.get_deck_view()
				widget.setup(club_deck_manager)
			else:
				club_deck_view = widget.get_node_or_null("SubViewport/DeckView3D")
				if club_deck_view:
					club_deck_view.setup(club_deck_manager)
					club_deck_view.interaction_mode = DeckView3D.InteractionMode.SELECT_FROM_UI
			
			if club_deck_view and not club_deck_view.request_club_selection.is_connected(_on_request_club_selection):
				club_deck_view.request_club_selection.connect(_on_request_club_selection)
				
		else:
			# Modifier Deck (Default)
			deck_widget = widget
			if widget.has_method("get_deck_view"):
				deck_view = widget.get_deck_view()
				widget.setup(deck_manager)
			else:
				deck_view = widget.get_node_or_null("SubViewport/DeckView3D")
				if deck_view:
					deck_view.setup(deck_manager)
					deck_view.interaction_mode = DeckView3D.InteractionMode.DRAW_TOP
			
			# Ensure signal is disconnected (reverting previous change)
			if deck_view and deck_view.request_club_selection.is_connected(_on_request_club_selection):
				deck_view.request_club_selection.disconnect(_on_request_club_selection)


# --- Public API ---

func initialize_starter_deck() -> void:
	"""Initialize the deck with starter cards for a new run"""
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
