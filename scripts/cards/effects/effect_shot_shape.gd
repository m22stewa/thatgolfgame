extends CardEffect
class_name EffectShotShape

## Prototype path card: shapes the card-built flight (ShotPlan) and spends power.
## All fields add up across played cards through ShotContext metadata, which
## TurnController reads when it builds the path.

@export var power_cost: int = 0      # added to the shot's power spend
@export var bulge: float = 0.0       # hexes; + bows the flight right (curves left into the target)
@export var loft: bool = false       # flight clears trees
@export var ignore_wind: bool = false
@export var roll_mod: int = 0        # roll-out after landing (-99 = stop dead)
@export var ring_mod: int = 0        # landing ring radius (-1 = tighter)


func _init() -> void:
	effect_id = "shot_shape"
	effect_name = "Shot Shape"
	apply_phase = 0  # BeforeAim
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, _upgrade_level: int = 0) -> void:
	context.add_metadata("power_cost", int(context.get_metadata("power_cost", 0)) + power_cost)
	context.add_metadata("shape_bulge", float(context.get_metadata("shape_bulge", 0.0)) + bulge)
	context.add_metadata("ring_mod", int(context.get_metadata("ring_mod", 0)) + ring_mod)
	context.roll_mod += roll_mod
	if loft:
		context.add_metadata("loft", true)
	if ignore_wind:
		context.add_metadata("ignore_wind", true)


func get_description(_upgrade_level: int = 0) -> String:
	return effect_name
