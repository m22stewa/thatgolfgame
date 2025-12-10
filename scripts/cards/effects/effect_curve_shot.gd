extends CardEffect
class_name EffectCurveShot

## Adds curve to the shot trajectory for shaped shots.
## Enables draw and fade shots for creative play.

@export_enum("Draw", "Fade", "Random") var curve_direction: int = 0
@export var curve_tiles: int = 2              # Tiles of horizontal movement
@export var bonus_on_curve_land: int = 0      # Chips if ball lands via curve

func _init() -> void:
	effect_id = "curve_shot"
	effect_name = "Curve Shot"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, upgrade_level: int = 0) -> void:
	var scaled_tiles = curve_tiles + upgrade_level
	
	var direction_mult: float
	match curve_direction:
		0:  # Draw (curves left for right-handed)
			direction_mult = -1.0
		1:  # Fade (curves right for right-handed)
			direction_mult = 1.0
		2:  # Random
			direction_mult = 1.0 if randf() > 0.5 else -1.0
	
	context.curve_strength = float(scaled_tiles) * direction_mult


func apply_on_scoring(context: ShotContext, upgrade_level: int = 0) -> void:
	# Check if the ball actually curved to its destination
	if bonus_on_curve_land > 0 and context.did_curve:
		var scaled = bonus_on_curve_land + (upgrade_level * 5)
		context.chips += scaled


func get_description(upgrade_level: int = 0) -> String:
	var st = curve_tiles + upgrade_level
	var dir_name: String
	match curve_direction:
		0: dir_name = "Draw"
		1: dir_name = "Fade"
		2: dir_name = "Random"
	
	var desc = "%s: %d tiles of curve" % [dir_name, st]
	if bonus_on_curve_land > 0:
		var sc = bonus_on_curve_land + (upgrade_level * 5)
		desc += ", +%d chips on land" % sc
	return desc
	if bonus_on_curve_land > 0:
		var sc = bonus_on_curve_land + (upgrade_level * 5)
		desc += ", +%d Chips on curve landing" % sc
	return desc
