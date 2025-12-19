extends CardEffect
class_name EffectAOERing

## Sets AOE to a filled circle pattern (ring).
## Distance determines the radius: +1 = 1 ring, +2 = 2 rings, etc.
## This is the traditional AOE pattern where ball could land anywhere within radius.

@export var ring_distance: int = 1  # Number of rings (1 = adjacent tiles, 2 = two rings out, etc.)


func _init() -> void:
	effect_id = "aoe_ring"
	effect_name = "Ring AOE"
	apply_phase = 0  # BeforeAim - sets up AOE parameters
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, upgrade_level: int = 0) -> void:
	# Set AOE shape to circle (filled ring pattern)
	context.aoe_shape = "circle"
	# Add ring distance to existing radius (allows stacking)
	var distance = ring_distance + int(upgrade_level * value_per_upgrade)
	context.aoe_radius += distance


func get_description(upgrade_level: int = 0) -> String:
	var distance = ring_distance + int(upgrade_level * value_per_upgrade)
	if distance == 1:
		return "Ring +%d (adjacent tiles)" % distance
	else:
		return "Ring +%d (%d rings of possible landing)" % [distance, distance]
