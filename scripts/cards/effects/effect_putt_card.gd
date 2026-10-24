extends CardEffect
class_name EffectPuttCard

## Green card: changes how a putt is read or struck on the GreenBoard. Read by
## hex_grid when the putt resolves (it doesn't touch the ShotContext).

@export var power_cost: int = 1        # Chips to play it (CardCost)
@export var read_green: bool = false   # preview shows the putt's whole route
@export var reach_bonus: int = 0       # extra small hexes the putt can be struck
@export var dead_weight: bool = false  # the green doesn't push the ball


func _init() -> void:
	effect_id = "putt_card"
	effect_name = "Putt Card"
	apply_phase = 0
	trigger_condition = 0


func get_description(_upgrade_level: int = 0) -> String:
	return effect_name
