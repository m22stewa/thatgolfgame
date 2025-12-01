extends Node
class_name DeckManager

## DeckManager - Manages the card deck, hand, and discard pile.
## Handles drawing, playing, discarding, and shuffling cards.
## Emits signals for UI updates and game state changes.

# Signals
signal hand_changed(hand: Array[CardInstance])
signal card_drawn(card: CardInstance)
signal card_played(card: CardInstance)
signal card_discarded(card: CardInstance)
signal deck_shuffled()
signal deck_empty()

# Deck configuration
@export var hand_size: int = 5              # Max cards in hand
@export var draw_per_shot: int = 1          # Cards drawn at start of each shot
@export var auto_draw_to_hand: bool = true  # Automatically draw to hand size

# Card piles
var _draw_pile: Array[CardInstance] = []
var _hand: Array[CardInstance] = []
var _discard_pile: Array[CardInstance] = []

# Card registry - maps card IDs to CardData resources
var card_registry: Dictionary = {}  # String -> CardData

# Played cards this shot (reset after each shot)
var _played_this_shot: Array[CardInstance] = []

# Reference to modifier manager for registering card effects
var modifier_manager: ModifierManager = null


func _ready() -> void:
	_load_card_registry()


# --- Card Registry ---

func _load_card_registry() -> void:
	"""Load all card definitions into the registry.
	   Override this to load cards from files or create them programmatically."""
	# Cards will be registered by CardLibrary or loaded from resources
	pass


func register_card(card_data: CardData) -> void:
	"""Register a card definition in the registry"""
	if card_data and not card_data.card_id.is_empty():
		card_registry[card_data.card_id] = card_data


func get_card_data(card_id: String) -> CardData:
	"""Get card data by ID"""
	return card_registry.get(card_id, null)


# --- Deck Management ---

func initialize_deck(starting_cards: Array[CardData]) -> void:
	"""Set up the deck with starting cards"""
	_draw_pile.clear()
	_hand.clear()
	_discard_pile.clear()
	_played_this_shot.clear()
	
	for card_data in starting_cards:
		var instance = CardInstance.create_from_data(card_data)
		_draw_pile.append(instance)
	
	shuffle_deck()


func add_to_deck(card_instance: CardInstance) -> void:
	"""Add an existing card instance to the draw pile"""
	if card_instance:
		_draw_pile.append(card_instance)


func add_card_to_deck(card_data: CardData, upgraded_level: int = 0) -> CardInstance:
	"""Add a new card to the deck (goes to discard)"""
	var instance: CardInstance
	if upgraded_level > 0:
		instance = CardInstance.create_upgraded(card_data, upgraded_level)
	else:
		instance = CardInstance.create_from_data(card_data)
	
	_discard_pile.append(instance)
	return instance


func remove_card_from_deck(card: CardInstance) -> bool:
	"""Remove a card from wherever it is"""
	var removed = false
	
	if card in _draw_pile:
		_draw_pile.erase(card)
		removed = true
	elif card in _hand:
		_hand.erase(card)
		removed = true
		hand_changed.emit(_hand)
	elif card in _discard_pile:
		_discard_pile.erase(card)
		removed = true
	
	return removed


func shuffle_deck() -> void:
	"""Shuffle the draw pile"""
	_draw_pile.shuffle()
	deck_shuffled.emit()


func shuffle_discard_into_deck() -> void:
	"""Shuffle discard pile back into draw pile"""
	_draw_pile.append_array(_discard_pile)
	_discard_pile.clear()
	shuffle_deck()


# --- Drawing Cards ---

func draw_card() -> CardInstance:
	"""Draw a single card from the draw pile"""
	if _draw_pile.is_empty():
		if _discard_pile.is_empty():
			deck_empty.emit()
			return null
		shuffle_discard_into_deck()
	
	if _draw_pile.is_empty():
		return null
	
	var card = _draw_pile.pop_back()
	_hand.append(card)
	card_drawn.emit(card)
	hand_changed.emit(_hand)
	return card


func draw_cards(count: int) -> Array[CardInstance]:
	"""Draw multiple cards"""
	var drawn: Array[CardInstance] = []
	for i in range(count):
		var card = draw_card()
		if card:
			drawn.append(card)
		else:
			break
	return drawn


func draw_to_hand_size() -> Array[CardInstance]:
	"""Draw until hand is at max size"""
	var drawn: Array[CardInstance] = []
	while _hand.size() < hand_size:
		var card = draw_card()
		if card:
			drawn.append(card)
		else:
			break
	return drawn


# --- Playing Cards ---

func can_play_card(card: CardInstance) -> bool:
	"""Check if a card can be played"""
	if card == null:
		return false
	if card not in _hand:
		return false
	if not card.can_play():
		return false
	return true


func play_card(card: CardInstance, context: ShotContext = null) -> bool:
	"""Play a card from hand"""
	if not can_play_card(card):
		return false
	
	# Remove from hand
	_hand.erase(card)
	_played_this_shot.append(card)
	
	# Use the card (for limited-use cards)
	card.use()
	
	# Apply card effects if we have a context
	if context:
		_apply_card_effects(card, context)
	
	card_played.emit(card)
	hand_changed.emit(_hand)
	return true


func _apply_card_effects(card: CardInstance, context: ShotContext) -> void:
	"""Apply all effects from a card based on current phase"""
	# Card effects are applied via the CardModifier wrapper
	# This allows cards to participate in the normal modifier system
	pass


# --- Discarding Cards ---

func discard_card(card: CardInstance) -> bool:
	"""Discard a card from hand"""
	if card not in _hand:
		return false
	
	_hand.erase(card)
	
	# Exhausted cards are removed from game, not discarded
	if card.is_exhausted:
		pass  # Card is gone
	else:
		_discard_pile.append(card)
	
	card_discarded.emit(card)
	hand_changed.emit(_hand)
	return true


func discard_hand() -> void:
	"""Discard entire hand"""
	for card in _hand.duplicate():
		discard_card(card)


func discard_played_cards() -> void:
	"""Move played cards to discard pile"""
	for card in _played_this_shot:
		if not card.is_exhausted:
			_discard_pile.append(card)
	_played_this_shot.clear()


# --- Shot Lifecycle Hooks ---

func on_shot_start(context: ShotContext = null) -> void:
	"""Called when a new shot begins"""
	_played_this_shot.clear()
	
	# Reset temp modifiers on hand cards
	for card in _hand:
		card.reset_temp_modifiers()
	
	# Draw cards for this shot
	if auto_draw_to_hand:
		draw_to_hand_size()
	else:
		draw_cards(draw_per_shot)


func on_shot_end(context: ShotContext = null) -> void:
	"""Called when a shot completes"""
	discard_played_cards()


# --- Query Methods ---

func get_hand() -> Array[CardInstance]:
	"""Get current hand"""
	return _hand.duplicate()


func get_hand_size() -> int:
	return _hand.size()


func get_draw_pile_size() -> int:
	return _draw_pile.size()


func get_discard_pile_size() -> int:
	return _discard_pile.size()


func get_total_deck_size() -> int:
	return _draw_pile.size() + _hand.size() + _discard_pile.size() + _played_this_shot.size()


func get_cards_by_type(card_type: int) -> Array[CardInstance]:
	"""Get all cards of a specific type from all piles"""
	var result: Array[CardInstance] = []
	
	for card in _draw_pile + _hand + _discard_pile:
		if card.data and card.data.card_type == card_type:
			result.append(card)
	
	return result


func get_cards_with_tag(tag: String) -> Array[CardInstance]:
	"""Get all cards with a specific tag"""
	var result: Array[CardInstance] = []
	
	for card in _draw_pile + _hand + _discard_pile:
		if card.data and card.data.has_tag(tag):
			result.append(card)
	
	return result


# --- Serialization ---

func save_state() -> Dictionary:
	"""Save deck state for game saves"""
	return {
		"draw_pile": _draw_pile.map(func(c): return c.to_dict()),
		"hand": _hand.map(func(c): return c.to_dict()),
		"discard_pile": _discard_pile.map(func(c): return c.to_dict()),
		"played_this_shot": _played_this_shot.map(func(c): return c.to_dict())
	}


func load_state(state: Dictionary) -> void:
	"""Load deck state from save"""
	_draw_pile.clear()
	_hand.clear()
	_discard_pile.clear()
	_played_this_shot.clear()
	
	for card_dict in state.get("draw_pile", []):
		var card = CardInstance.from_dict(card_dict, card_registry)
		if card:
			_draw_pile.append(card)
	
	for card_dict in state.get("hand", []):
		var card = CardInstance.from_dict(card_dict, card_registry)
		if card:
			_hand.append(card)
	
	for card_dict in state.get("discard_pile", []):
		var card = CardInstance.from_dict(card_dict, card_registry)
		if card:
			_discard_pile.append(card)
	
	for card_dict in state.get("played_this_shot", []):
		var card = CardInstance.from_dict(card_dict, card_registry)
		if card:
			_played_this_shot.append(card)
	
	hand_changed.emit(_hand)
