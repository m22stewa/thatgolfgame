extends CardEffect
class_name EffectTightenSpread

## Shot-shape effect: tighten the footprint.
## Reduces the spread radius and steepens the weight falloff so the landing
## concentrates toward the center.

func _init() -> void:
	effect_id = "tighten_spread"
	effect_name = "Tighten Spread"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, _upgrade_level: int = 0) -> void:
	context.spread_mod -= 1
	context.falloff_pow += 0.5


func get_description(_upgrade_level: int = 0) -> String:
	return "Tighter landing: spread -1, steeper falloff"
