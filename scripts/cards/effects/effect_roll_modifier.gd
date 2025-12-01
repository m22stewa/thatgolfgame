extends CardEffect
class_name EffectRollModifier

## Modifies how the ball rolls after landing.
## Affects roll distance and friction.

@export var roll_distance_modifier: float = 1.5  # Multiplier for roll distance
@export var friction_modifier: float = 1.0       # Lower = more roll, higher = less roll
@export var bonus_chips_on_roll_stop: int = 0   # Chips when ball stops rolling

func _init() -> void:
	effect_id = "roll_modifier"
	effect_name = "Roll Modifier"
	apply_phase = 2  # OnLanding
	trigger_condition = 0  # Always


func apply_on_landing(context: ShotContext, upgrade_level: int = 0) -> void:
	# Apply roll modifiers to the shot context
	var scaled_distance = roll_distance_modifier + (upgrade_level * 0.25)
	var scaled_friction = friction_modifier - (upgrade_level * 0.1)
	scaled_friction = maxf(0.1, scaled_friction)  # Don't go below 0.1
	
	context.roll_distance_mult = scaled_distance
	context.friction_mult = scaled_friction
	
	print("Card Effect: Roll modified! Distance ×%.2f, Friction ×%.2f" % [scaled_distance, scaled_friction])


func apply_on_scoring(context: ShotContext, upgrade_level: int = 0) -> void:
	# Add bonus chips if configured
	if bonus_chips_on_roll_stop > 0:
		var scaled = bonus_chips_on_roll_stop + (upgrade_level * 3)
		context.chips += scaled
		print("Card Effect: Roll stop bonus +%d chips" % scaled)


func get_description(upgrade_level: int = 0) -> String:
	var sd = roll_distance_modifier + (upgrade_level * 0.25)
	var sf = friction_modifier - (upgrade_level * 0.1)
	sf = maxf(0.1, sf)
	
	var parts: Array[String] = []
	if sd != 1.0:
		parts.append("Roll ×%.2f" % sd)
	if sf != 1.0:
		parts.append("Friction ×%.2f" % sf)
	if bonus_chips_on_roll_stop > 0:
		var sc = bonus_chips_on_roll_stop + (upgrade_level * 3)
		parts.append("+%d Chips on roll stop" % sc)
	
	return ", ".join(parts) if parts.size() > 0 else "Modifies ball roll"
