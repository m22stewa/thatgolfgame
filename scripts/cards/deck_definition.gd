extends Resource
class_name DeckDefinition

## A resource that defines the contents of a deck.
## Can be used to define starter decks, enemy decks, or unlockable decks.

@export_group("Identity")
@export var deck_id: String = "deck_default"
@export var display_name: String = "New Deck"
@export_multiline var description: String = ""

@export_group("Content")
## List of CardData resources. Use this if your cards exist as .tres files.
@export var cards: Array[CardData] = []

## List of card IDs (strings). Use this for cards defined in code (CardLibrary).
## The system will look these up in the CardLibrary.
@export var card_ids: Array[String] = []

## Optional: Define counts for each card ID.
## Format: { "card_id": count }
## If a card is in 'card_ids' AND here, this count overrides simple inclusion.
@export var card_counts: Dictionary = {}

func get_all_cards() -> Array[CardData]:
	"""Resolves all cards from resources and IDs into a single list"""
	var final_deck: Array[CardData] = []
	
	# 1. Add direct resources
	final_deck.append_array(cards)
	
	# 2. Resolve IDs from CardLibrary
	if CardLibrary.instance:
		for id in card_ids:
			var card = CardLibrary.instance.get_card(id)
			if card:
				final_deck.append(card)
			else:
				push_warning("DeckDefinition: Could not find card with ID '%s'" % id)
				
		# 3. Handle counts dictionary
		for id in card_counts:
			var count = card_counts[id]
			var card = CardLibrary.instance.get_card(id)
			if card:
				for i in range(count):
					final_deck.append(card)
			else:
				push_warning("DeckDefinition: Could not find card with ID '%s' for count" % id)
	
	return final_deck
