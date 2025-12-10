extends CardEffect
class_name EffectRollModifier

## Modifies how the ball rolls after landing.
## Uses simplified int-based roll_mod.

@export var roll_tiles: int = 1  # Tiles added/subtracted from roll
@export var bonus_chips_on_roll_stop: int = 0   # Chips when ball stops rolling

func _init() -> void:
	effect_id = "roll_modifier"
	effect_name = "Roll Modifier"
	apply_phase = 0  # BeforeAim (so it's included in stats calculation)
	trigger_condition = 0  # Always


func apply_before_aim(context: ShotContext, upgrade_level: int = 0) -> void:
	# Apply roll modifier to the shot context
	var scaled_roll = roll_tiles + upgrade_level
	context.roll_mod += scaled_roll


func apply_on_scoring(context: ShotContext, upgrade_level: int = 0) -> void:
	# Add bonus chips if configured
	if bonus_chips_on_roll_stop > 0:
		var scaled = bonus_chips_on_roll_stop + (upgrade_level * 3)
		context.chips += scaled


func get_description(upgrade_level: int = 0) -> String:
	var sr = roll_tiles + upgrade_level
	
	var parts: Array[String] = []
	if sr != 0:
		var op = "+" if sr > 0 else ""
		parts.append("Roll %s%d tiles" % [op, sr])
	if bonus_chips_on_roll_stop > 0:
		var sc = bonus_chips_on_roll_stop + (upgrade_level * 3)
		parts.append("+%d Chips on roll stop" % sc)
	
	return ", ".join(parts) if parts.size() > 0 else "Modifies ball roll"
