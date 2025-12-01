extends Resource
class_name CardEffect

## CardEffect - Base class for all card effects.
## Effects are modular - a single card can have multiple effects.
## Each effect hooks into specific shot lifecycle phases.
##
## Subclass this to create specific effects like:
## - ChipsBonus: Add flat chips
## - MultBonus: Multiply score
## - AOEExpand: Increase AOE radius
## - TileModify: Add/remove tile tags

# Effect identification
@export var effect_id: String = ""
@export var effect_name: String = ""

# Scaling - values can be multiplied by card upgrade level
@export var base_value: float = 0.0
@export var value_per_upgrade: float = 0.0

# Trigger conditions
@export_enum("Always", "OnFairway", "OnRough", "OnSand", "OnWater", "OnGreen", "OnBounce", "OnRoll") var trigger_condition: int = 0

# Which phase this effect applies to
@export_enum("BeforeAim", "OnAOE", "OnLanding", "OnScoring", "AfterShot") var apply_phase: int = 0


# --- Virtual Methods (Override in subclasses) ---

func get_scaled_value(upgrade_level: int = 0) -> float:
	"""Get effect value scaled by upgrade level"""
	return base_value + (value_per_upgrade * upgrade_level)


func can_trigger(context: ShotContext) -> bool:
	"""Check if this effect should trigger based on conditions"""
	match trigger_condition:
		0:  # Always
			return true
		1:  # OnFairway
			return _check_terrain_in_path(context, 1)  # FAIRWAY = 1
		2:  # OnRough
			return _check_terrain_in_path(context, 2) or _check_terrain_in_path(context, 3)
		3:  # OnSand
			return _check_terrain_in_path(context, 5)
		4:  # OnWater
			return _check_terrain_in_path(context, 6)
		5:  # OnGreen
			return _check_terrain_in_path(context, 4)
		6:  # OnBounce
			return context.max_bounces > 0
		7:  # OnRoll
			return context.roll_distance > 0
		_:
			return true


func _check_terrain_in_path(context: ShotContext, terrain_type: int) -> bool:
	"""Check if a terrain type appears in the shot path"""
	if context.hole == null or not context.hole.has_method("get_cell"):
		return false
	
	for tile in context.path_tiles:
		if context.hole.get_cell(tile.x, tile.y) == terrain_type:
			return true
	return false


# --- Phase Application Methods (Override in subclasses) ---

func apply_before_aim(context: ShotContext, upgrade_level: int = 0) -> void:
	"""Called before player aims - modify base stats"""
	pass


func apply_on_aoe(context: ShotContext, upgrade_level: int = 0) -> void:
	"""Called after AOE computed - modify AOE shape/tiles"""
	pass


func apply_on_landing(context: ShotContext, upgrade_level: int = 0) -> void:
	"""Called when ball lands - modify landing behavior"""
	pass


func apply_on_scoring(context: ShotContext, upgrade_level: int = 0) -> void:
	"""Called during scoring - modify chips/mult"""
	pass


func apply_after_shot(context: ShotContext, upgrade_level: int = 0) -> void:
	"""Called after shot complete - trigger end effects"""
	pass


# --- Utility ---

func get_description(upgrade_level: int = 0) -> String:
	"""Get human-readable description of this effect"""
	return "%s: %s" % [effect_name, str(get_scaled_value(upgrade_level))]
