extends CardEffect
class_name EffectBounceBonus

## Grants bonuses when the ball bounces.
## Great for trick shots and strategic bank shots.

@export var chips_per_bounce: int = 5
@export var mult_per_bounce: float = 0.2
@export var max_bonus_bounces: int = 5  # Cap to prevent exploits

func _init() -> void:
	effect_id = "bounce_bonus"
	effect_name = "Bounce Bonus"
	apply_phase = 3  # OnScoring
	trigger_condition = 1  # OnBounce


func check_trigger(context: ShotContext) -> bool:
	# Triggers if the ball bounced at least once
	return context.bounce_count > 0


func apply_on_scoring(context: ShotContext, upgrade_level: int = 0) -> void:
	var bounces = mini(context.bounce_count, max_bonus_bounces)
	
	if bounces > 0:
		var scaled_chips_per = chips_per_bounce + (upgrade_level * 2)
		var scaled_mult_per = mult_per_bounce + (upgrade_level * 0.1)
		
		var total_chips = bounces * scaled_chips_per
		var total_mult = bounces * scaled_mult_per
		
		context.chips += total_chips
		context.mult += total_mult


func get_description(upgrade_level: int = 0) -> String:
	var sc = chips_per_bounce + (upgrade_level * 2)
	var sm = mult_per_bounce + (upgrade_level * 0.1)
	return "+%d Chips, +%.1f Mult per bounce (max %d)" % [sc, sm, max_bonus_bounces]
