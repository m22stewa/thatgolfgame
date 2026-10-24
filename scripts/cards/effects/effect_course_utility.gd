extends CardEffect
class_name EffectCourseUtility

## Utility card: acts on the course's obstacles the moment it's played, then
## goes to the discard (it isn't one of the shot's planned cards).
##   extinguish   - every fire goes out (scorched ground)
##   groundskeeper - the hole's obstacles are moved somewhere else
##   shutoff      - wind gusts switched off for the hole

@export var action: String = ""
@export var power_cost: int = 1  # Chips to play it (CardCost)


func _init() -> void:
	effect_id = "course_utility"
	effect_name = "Utility"
	apply_phase = 0
	trigger_condition = 0


func get_description(_upgrade_level: int = 0) -> String:
	return effect_name
