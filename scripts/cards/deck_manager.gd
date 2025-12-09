extends Node
class_name DeckManager

## DeckManager - Manages the card deck and active cards.
## Handles drawing from deck to active slot and discarding.

# Signals
signal active_cards_changed(cards: Array[CardInstance])
signal card_drawn(card: CardInstance)
signal card_activated(card: CardInstance)
signal deck_shuffled()
signal deck_empty()

# Deck configuration
@export var deck_size: int = 20             # Target deck size

# Card piles
var _draw_pile: Array[CardInstance] = []
var _active_cards: Array[CardInstance] = [] # Cards currently in the dropzone
var _discard_pile: Array[CardInstance] = []

# Card registry - maps card IDs to CardData resources
var card_registry: Dictionary = {}  # String -> CardData

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
	clear_deck()
	
	for card_data in starting_cards:
		var instance = CardInstance.create_from_data(card_data)
		_draw_pile.append(instance)
	
	# Don't shuffle club cards if that's what we're using
	# But for now, we assume generic deck behavior.
	# If using club deck, we might want them sorted?
	# For now, shuffle is fine as we will pick from list.
	shuffle_deck()
	active_cards_changed.emit(_active_cards)


func initialize_with_instances(cards: Array[CardInstance]) -> void:
	"""Initialize deck with existing instances (e.g. club deck)"""
	clear_deck()
	_draw_pile = cards.duplicate()
	# Don't shuffle club deck by default so they might be ordered?
	# Actually, for a picker UI, order doesn't matter much if we sort there.
	active_cards_changed.emit(_active_cards)


func clear_deck() -> void:
	"""Clear all piles"""
	_draw_pile.clear()
	_active_cards.clear()
	_discard_pile.clear()
	active_cards_changed.emit(_active_cards)


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
	elif card in _active_cards:
		_active_cards.erase(card)
		removed = true
		active_cards_changed.emit(_active_cards)
	elif card in _discard_pile:
		_discard_pile.erase(card)
		removed = true
		
	return removed


func get_draw_pile_count() -> int:
	return _draw_pile.size()


func get_discard_pile_count() -> int:
	return _discard_pile.size()


func shuffle_deck() -> void:
	"""Shuffle the draw pile"""
	_draw_pile.shuffle()
	deck_shuffled.emit()


func shuffle_discard_into_deck() -> void:
	"""Shuffle discard pile back into draw pile"""
	_draw_pile.append_array(_discard_pile)
	_discard_pile.clear()
	shuffle_deck()


# --- Drawing & Activating Cards ---

func draw_specific_card(card_instance: CardInstance) -> void:
	"""Move a specific card from draw pile to active"""
	if card_instance in _draw_pile:
		_draw_pile.erase(card_instance)
		_active_cards.append(card_instance)
		active_cards_changed.emit(_active_cards)
		card_drawn.emit(card_instance)
		card_activated.emit(card_instance)


func draw_candidates(count: int) -> Array[CardInstance]:
	"""Draw cards for selection but do not activate them yet"""
	var candidates: Array[CardInstance] = []
	for i in range(count):
		if _draw_pile.is_empty():
			if _discard_pile.is_empty():
				break
			shuffle_discard_into_deck()
		
		if not _draw_pile.is_empty():
			candidates.append(_draw_pile.pop_back())
	
	# Note: Candidates are now in limbo (not in draw, active, or discard)
	# The caller is responsible for playing or discarding them.
	return candidates


func play_candidate(card: CardInstance) -> void:
	"""Play a card that was previously drawn as a candidate"""
	_active_cards.append(card)
	
	# Use the card immediately (apply effects)
	card.use()
	
	card_drawn.emit(card)
	card_activated.emit(card)
	active_cards_changed.emit(_active_cards)


func discard_candidates(cards: Array[CardInstance]) -> void:
	"""Discard cards that were drawn as candidates but not chosen"""
	_discard_pile.append_array(cards)
	# No signal needed for discard pile change usually, unless UI tracks it



func draw_card() -> CardInstance:
	"""Draw the top card from the deck"""
	if _draw_pile.is_empty():
		if _discard_pile.is_empty():
			deck_empty.emit()
			return null
		shuffle_discard_into_deck()
	
	if _draw_pile.is_empty():
		return null
	
	var card = _draw_pile.pop_back()
	_active_cards.append(card)
	
	# Use the card immediately (apply effects)
	card.use()
	
	card_drawn.emit(card)
	card_activated.emit(card)
	active_cards_changed.emit(_active_cards)
	
	return card


func clear_active_cards() -> void:
	"""Move all active cards to discard pile"""
	_discard_pile.append_array(_active_cards)
	_active_cards.clear()
	active_cards_changed.emit(_active_cards)


func get_active_cards() -> Array[CardInstance]:
	return _active_cards


func get_all_deck_cards() -> Array[CardInstance]:
	"""Get all cards in the deck (draw + discard + active) for viewing/upgrading"""
	var all_cards: Array[CardInstance] = []
	all_cards.append_array(_draw_pile)
	all_cards.append_array(_active_cards)
	all_cards.append_array(_discard_pile)
	return all_cards


func get_draw_pile_size() -> int:
	return _draw_pile.size()


func get_discard_pile_size() -> int:
	return _discard_pile.size()
