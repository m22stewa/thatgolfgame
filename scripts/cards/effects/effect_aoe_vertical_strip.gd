extends CardEffect
class_name EffectAOEVerticalStrip

## Sets AOE to exact vertical strip pattern (3 tiles: center, +1 forward, +1 back).
## This overrides radius and sets specific shape.

@export var strip_length: int = 3  # Total tiles in strip

func _init() -> void:
	effect_id = "aoe_vertical_strip"
	effect_name = "Vertical Strip"
	apply_phase = 1  # OnAOE
	trigger_condition = 0  # Always


func apply_on_aoe(context: ShotContext, upgrade_level: int = 0) -> void:
	# Override to use strip shape
	context.aoe_shape = "strip"
	# Strip goes in direction 0 (vertical/forward)
	# Radius determines length: 1 = 2 tiles (center + 1 forward), 2 = 3 tiles, etc.
	var length = strip_length + int(upgrade_level * value_per_upgrade)
	context.aoe_radius = maxi(0, length - 1)  # Radius 1 = 2 tiles total


func get_description(upgrade_level: int = 0) -> String:
	var length = strip_length + int(upgrade_level * value_per_upgrade)
	return "%d-tile vertical strip" % length
