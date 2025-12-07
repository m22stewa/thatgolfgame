extends Node
class_name CardSystemManager

## Central controller that integrates the card system with the shot lifecycle.
## This node bridges DeckManager with ModifierManager and shot system.

# References to external systems (set via setup or found automatically)
var deck_manager: DeckManager = null
var modifier_manager: ModifierManager = null
var shot_manager: ShotManager = null
var card_library: CardLibrary = null

# UI reference
var hand_ui: HandUI = null

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
	
	# Connect deck signals (only if not already connected)
	if not deck_manager.card_played.is_connected(_on_card_played):
		deck_manager.card_played.connect(_on_card_played)
	if not deck_manager.card_discarded.is_connected(_on_card_discarded):
		deck_manager.card_discarded.connect(_on_card_discarded)
	if not deck_manager.hand_changed.is_connected(_on_hand_changed):
		deck_manager.hand_changed.connect(_on_hand_changed)
	
	# Create CardLibrary if not present
	if card_library == null:
		card_library = CardLibrary.new()
		card_library.name = "CardLibrary"
		add_child(card_library)
	
	card_system_ready.emit()


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


func _setup_hand_ui() -> void:
	"""Find or create the HandUI component"""
	# Try to find existing HandUI
	var control = get_tree().current_scene.get_node_or_null("Control")
	if control:
		hand_ui = control.get_node_or_null("HandUI")
	
	if hand_ui == null:
		# Try loading the scene
		var hand_ui_scene = load("res://scenes/ui/hand_ui.tscn")
		if hand_ui_scene and control:
			hand_ui = hand_ui_scene.instantiate()
			control.add_child(hand_ui)
	
	if hand_ui:
		hand_ui.setup(deck_manager)
		hand_ui.card_played.connect(_on_ui_card_played)
		hand_ui.card_selected.connect(_on_ui_card_selected)


# --- Public API ---

func initialize_starter_deck() -> void:
	"""Initialize the deck with starter cards for a new run"""
	if not card_library or not deck_manager:
		push_warning("CardSystemManager: Cannot init deck - systems not ready")
		return
	
	var starter_cards = card_library.get_starter_deck()
	
	for card in starter_cards:
		deck_manager.add_to_deck(card)
	
	deck_manager.shuffle_deck()


func draw_starting_hand(count: int = 5) -> void:
	"""Draw the initial hand for a hole"""
	if deck_manager:
		for i in count:
			deck_manager.draw_card()


func play_card(card_instance: CardInstance) -> bool:
	"""Play a card, adding its effects to the modifier system"""
	if not card_instance or not modifier_manager:
		return false
	
	# Create modifier wrapper for the card
	var card_modifier = CardModifier.new(card_instance)
	
	# Add to modifier manager
	modifier_manager.add_modifier(card_modifier)
	active_card_modifiers.append(card_modifier)
	
	# Move card from hand to discard (DeckManager handles this)
	deck_manager.play_card(card_instance)
	
	return true


func add_card_to_deck(card_data: CardData) -> void:
	"""Add a new card to the deck (rewards, shop, etc.)"""
	if deck_manager and card_data:
		var instance = CardInstance.new(card_data)
		deck_manager.add_to_deck(instance)
		deck_changed.emit()


func remove_card_from_deck(card_instance: CardInstance) -> void:
	"""Remove a card permanently (selling, destroying)"""
	if deck_manager:
		# Remove from all piles
		deck_manager._draw_pile.erase(card_instance)
		deck_manager._hand.erase(card_instance)
		deck_manager._discard_pile.erase(card_instance)
		deck_changed.emit()


func get_deck_manager() -> DeckManager:
	return deck_manager


func get_card_library() -> CardLibrary:
	return card_library


# --- Shot Lifecycle Hooks ---

func _on_shot_started(context: ShotContext) -> void:
	"""Called when a new shot begins"""
	# Clear active card modifiers from previous shot
	_clear_active_modifiers()
	
	# Apply Joker cards (always active passives)
	_apply_joker_cards(context)
	
	# Deck manager handles shot start (e.g., draw phase)
	if deck_manager:
		deck_manager.on_shot_start(context)


func _on_shot_completed(context: ShotContext) -> void:
	"""Called when shot finishes"""
	# Clear active modifiers
	_clear_active_modifiers()
	
	# Deck manager handles shot end (e.g., discard exhausted cards)
	if deck_manager:
		deck_manager.on_shot_end(context)


func _clear_active_modifiers() -> void:
	"""Remove all active card modifiers from the system"""
	if modifier_manager:
		for card_mod in active_card_modifiers:
			modifier_manager.remove_modifier(card_mod)
	
	active_card_modifiers.clear()


func _apply_joker_cards(context: ShotContext) -> void:
	"""Apply Joker-type cards (always active passives)"""
	# Jokers in hand are always active
	if deck_manager:
		for card in deck_manager.get_hand():
			if card.data.card_type == CardData.CardType.JOKER:
				var card_mod = CardModifier.new(card)
				modifier_manager.add_modifier(card_mod)
				active_card_modifiers.append(card_mod)


# --- UI Event Handlers ---

func _on_card_played(card: CardInstance) -> void:
	"""Handle card played from deck manager"""
	# Card is already processed by DeckManager
	pass


func _on_card_discarded(card: CardInstance) -> void:
	"""Handle card discarded"""
	pass


func _on_hand_changed() -> void:
	"""Handle hand composition change"""
	deck_changed.emit()


func _on_ui_card_played(card: CardInstance) -> void:
	"""Handle card played from UI"""
	play_card(card)


func _on_ui_card_selected(card: CardInstance) -> void:
	"""Handle card selected in UI (for preview/info)"""
	# Could show detailed card info popup
	pass
