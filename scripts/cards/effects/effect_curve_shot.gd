extends CardEffect
class_name EffectCurveShot

## Adds curve/spin to the shot trajectory.
## Enables hook and slice shots for creative play.

@export_enum("Left", "Right", "Random") var curve_direction: int = 0
@export var curve_strength: float = 0.3       # How much the ball curves
@export var curve_delay_cells: float = 2.0    # Distance before curve kicks in
@export var bonus_on_curve_land: int = 0      # Chips if ball lands via curve

func _init() -> void:
	effect_id = "curve_shot"
	effect_name = "Curve Shot"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, upgrade_level: int = 0) -> void:
	var scaled_strength = curve_strength + (upgrade_level * 0.1)
	
	var direction_mult: float
	match curve_direction:
		0:  # Left
			direction_mult = -1.0
		1:  # Right
			direction_mult = 1.0
		2:  # Random
			direction_mult = 1.0 if randf() > 0.5 else -1.0
	
	context.curve_strength = scaled_strength * direction_mult
	context.curve_delay = curve_delay_cells
	
	var dir_name = "left" if direction_mult < 0 else "right"
	print("Card Effect: Curve shot! Strength %.2f %s" % [scaled_strength, dir_name])


func apply_on_landing(context: ShotContext, upgrade_level: int = 0) -> void:
	# Check if the ball actually curved to its destination
	if bonus_on_curve_land > 0 and context.did_curve:
		var scaled = bonus_on_curve_land + (upgrade_level * 5)
		context.chips += scaled
		print("Card Effect: Curved landing! +%d chips" % scaled)


func get_description(upgrade_level: int = 0) -> String:
	var ss = curve_strength + (upgrade_level * 0.1)
	var dir_name: String
	match curve_direction:
		0: dir_name = "left"
		1: dir_name = "right"
		2: dir_name = "randomly"
	
	var desc = "Ball curves %s (strength %.2f)" % [dir_name, ss]
	if bonus_on_curve_land > 0:
		var sc = bonus_on_curve_land + (upgrade_level * 5)
		desc += ", +%d Chips on curve landing" % sc
	return desc
