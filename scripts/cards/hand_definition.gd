extends Resource
class_name HandDefinition

## HandDefinition - Seedable definition of the hand dealt for a hole.
## Supports a fully fixed (curated) hand or a seeded draw from the given decks.

@export var club_deck: DeckDefinition = null
@export var modifier_deck: DeckDefinition = null
@export var fixed_hand: bool = false
@export var dealt_card_ids: Array[String] = []
@export var hand_size: int = 5
@export var seed: int = 0
