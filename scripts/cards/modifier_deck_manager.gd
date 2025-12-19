extends Node
class_name ModifierDeckManager

## ModifierDeckManager - Manages the modifier deck with auto-reshuffle mechanics
## Base deck has 20 cards with specific distribution:
## - 6x Neutral (+0)
## - 4x +1 Distance
## - 4x -1 Distance
## - 2x +2 Distance
## - 1x -2 Distance
## - 1x Perfect Accuracy (shuffle trigger)
## - 1x Whiff (shuffle trigger)
## - 1x Bad Slice/Hook (shuffle trigger)

signal modifier_drawn(card: ModifierCardData)
signal deck_shuffled()
signal deck_size_changed(draw_size: int, discard_size: int)

# Card types
enum ModifierType {
	NEUTRAL,
	DISTANCE_PLUS_1,
	DISTANCE_PLUS_2,
	DISTANCE_MINUS_1,
	DISTANCE_MINUS_2,
	PERFECT_ACCURACY,
	WHIFF,
	BIG_SLICE,
	BIG_HOOK
}

# Cards that trigger a reshuffle after being drawn
const SHUFFLE_TRIGGER_TYPES = [
	ModifierType.PERFECT_ACCURACY,
	ModifierType.WHIFF,
	ModifierType.BIG_SLICE,
	ModifierType.BIG_HOOK
]

# Card piles
var _draw_pile: Array[ModifierCardData] = []
var _discard_pile: Array[ModifierCardData] = []
var _last_drawn: ModifierCardData = null

# Base deck composition (can be modified by shop)
var _base_deck_composition: Dictionary = {
	ModifierType.NEUTRAL: 6,
	ModifierType.DISTANCE_PLUS_1: 4,
	ModifierType.DISTANCE_MINUS_1: 4,
	ModifierType.DISTANCE_PLUS_2: 2,
	ModifierType.DISTANCE_MINUS_2: 1,
	ModifierType.PERFECT_ACCURACY: 1,
	ModifierType.WHIFF: 1,
	ModifierType.BIG_SLICE: 1,  # or BIG_HOOK - we use slice for now
}


func _ready() -> void:
	initialize_base_deck()


func initialize_base_deck() -> void:
	"""Create the base 20-card modifier deck"""
	_draw_pile.clear()
	_discard_pile.clear()
	
	for modifier_type in _base_deck_composition:
		var count = _base_deck_composition[modifier_type]
		for i in range(count):
			var card = _create_modifier_card(modifier_type)
			_draw_pile.append(card)
	
	shuffle_deck()
	_emit_deck_size_changed()


func _create_modifier_card(modifier_type: ModifierType) -> ModifierCardData:
	"""Create a modifier card of the specified type"""
	var card = ModifierCardData.new()
	card.modifier_type = modifier_type
	
	match modifier_type:
		ModifierType.NEUTRAL:
			card.card_name = "Neutral"
			card.description = "No effect"
			card.distance_modifier = 0
			card.triggers_shuffle = false
		ModifierType.DISTANCE_PLUS_1:
			card.card_name = "+1 Distance"
			card.description = "+1 tile to shot distance"
			card.distance_modifier = 1
			card.triggers_shuffle = false
		ModifierType.DISTANCE_PLUS_2:
			card.card_name = "+2 Distance"
			card.description = "+2 tiles to shot distance"
			card.distance_modifier = 2
			card.triggers_shuffle = false
		ModifierType.DISTANCE_MINUS_1:
			card.card_name = "-1 Distance"
			card.description = "-1 tile to shot distance"
			card.distance_modifier = -1
			card.triggers_shuffle = false
		ModifierType.DISTANCE_MINUS_2:
			card.card_name = "-2 Distance"
			card.description = "-2 tiles to shot distance"
			card.distance_modifier = -2
			card.triggers_shuffle = false
		ModifierType.PERFECT_ACCURACY:
			card.card_name = "Perfect Shot"
			card.description = "Ball lands exactly where aimed!"
			card.is_perfect_accuracy = true
			card.triggers_shuffle = true
		ModifierType.WHIFF:
			card.card_name = "Whiff!"
			card.description = "Complete miss! Shot goes nowhere."
			card.is_whiff = true
			card.triggers_shuffle = true
		ModifierType.BIG_SLICE:
			card.card_name = "Big Slice"
			card.description = "Ball curves +5 tiles right!"
			card.curve_modifier = 5
			card.triggers_shuffle = true
		ModifierType.BIG_HOOK:
			card.card_name = "Big Hook"
			card.description = "Ball curves +5 tiles left!"
			card.curve_modifier = -5
			card.triggers_shuffle = true
	
	return card


func draw_card() -> ModifierCardData:
	"""Draw a single modifier card. Returns null if deck is empty."""
	if _draw_pile.is_empty():
		if _discard_pile.is_empty():
			return null
		shuffle_discard_into_deck()
	
	if _draw_pile.is_empty():
		return null
	
	var card = _draw_pile.pop_back()
	_last_drawn = card
	
	# Discard the card
	_discard_pile.append(card)
	_emit_deck_size_changed()
	
	modifier_drawn.emit(card)
	
	# Check for shuffle trigger
	if card.triggers_shuffle:
		# Reshuffle after the card effect is applied
		call_deferred("shuffle_all_into_deck")
	
	return card


func shuffle_deck() -> void:
	"""Shuffle the draw pile"""
	_draw_pile.shuffle()
	deck_shuffled.emit()


func shuffle_discard_into_deck() -> void:
	"""Shuffle discard pile back into draw pile"""
	_draw_pile.append_array(_discard_pile)
	_discard_pile.clear()
	shuffle_deck()
	_emit_deck_size_changed()


func shuffle_all_into_deck() -> void:
	"""Shuffle both draw and discard piles together (for shuffle triggers)"""
	_draw_pile.append_array(_discard_pile)
	_discard_pile.clear()
	shuffle_deck()
	_emit_deck_size_changed()
	print("[ModifierDeckManager] Deck reshuffled due to shuffle trigger!")


func get_draw_pile_size() -> int:
	return _draw_pile.size()


func get_discard_pile_size() -> int:
	return _discard_pile.size()


func get_total_deck_size() -> int:
	return _draw_pile.size() + _discard_pile.size()


func get_last_drawn() -> ModifierCardData:
	return _last_drawn


func _emit_deck_size_changed() -> void:
	deck_size_changed.emit(_draw_pile.size(), _discard_pile.size())


# --- Shop Operations ---

func add_card(modifier_type: ModifierType) -> void:
	"""Add a new card to the deck (goes to discard pile)"""
	var card = _create_modifier_card(modifier_type)
	_discard_pile.append(card)
	
	# Update base composition for future resets
	if modifier_type in _base_deck_composition:
		_base_deck_composition[modifier_type] += 1
	else:
		_base_deck_composition[modifier_type] = 1
	
	_emit_deck_size_changed()


func remove_card(modifier_type: ModifierType) -> bool:
	"""Remove one card of the specified type from the deck. Returns true if successful."""
	# Try draw pile first
	for i in range(_draw_pile.size()):
		if _draw_pile[i].modifier_type == modifier_type:
			_draw_pile.remove_at(i)
			
			# Update base composition
			if modifier_type in _base_deck_composition:
				_base_deck_composition[modifier_type] = max(0, _base_deck_composition[modifier_type] - 1)
			
			_emit_deck_size_changed()
			return true
	
	# Try discard pile
	for i in range(_discard_pile.size()):
		if _discard_pile[i].modifier_type == modifier_type:
			_discard_pile.remove_at(i)
			
			if modifier_type in _base_deck_composition:
				_base_deck_composition[modifier_type] = max(0, _base_deck_composition[modifier_type] - 1)
			
			_emit_deck_size_changed()
			return true
	
	return false


func get_deck_composition() -> Dictionary:
	"""Get count of each card type in the full deck"""
	var composition: Dictionary = {}
	
	for card in _draw_pile:
		var type_name = ModifierType.keys()[card.modifier_type]
		composition[type_name] = composition.get(type_name, 0) + 1
	
	for card in _discard_pile:
		var type_name = ModifierType.keys()[card.modifier_type]
		composition[type_name] = composition.get(type_name, 0) + 1
	
	return composition


func reset_to_base_deck() -> void:
	"""Reset to the standard 20-card base deck (for new run)"""
	_base_deck_composition = {
		ModifierType.NEUTRAL: 6,
		ModifierType.DISTANCE_PLUS_1: 4,
		ModifierType.DISTANCE_MINUS_1: 4,
		ModifierType.DISTANCE_PLUS_2: 2,
		ModifierType.DISTANCE_MINUS_2: 1,
		ModifierType.PERFECT_ACCURACY: 1,
		ModifierType.WHIFF: 1,
		ModifierType.BIG_SLICE: 1,
	}
	initialize_base_deck()
