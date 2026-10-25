extends CardEffect
class_name EffectPuttCard

## Green card: bought in the Pro Shop, it changes the run's putting deck
## (PuttModifierDeck) instead of being dealt into a hand. hex_grid applies it
## when it's bought.

@export var deck_add: String = ""     # PuttModifierDeck card id put into the deck
@export var deck_remove: String = ""  # PuttModifierDeck card id taken out of the deck


func _init() -> void:
	effect_id = "putt_card"
	effect_name = "Putt Card"
	apply_phase = 0
	trigger_condition = 0


func get_description(_upgrade_level: int = 0) -> String:
	return effect_name
