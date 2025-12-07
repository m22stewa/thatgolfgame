extends CardEffect
class_name EffectTerrainBonus

## Grants bonus chips or mult when hitting specific terrain.
## Great for themed builds (sand specialist, rough rider, etc.)

@export var target_terrain: String = "Fairway"  # "Fairway", "Rough", "Sand", "Water", "Green", "Bunker"
@export var terrain_is_start: bool = false      # If true, checks starting tile instead of landing
@export var bonus_chips: int = 0
@export var bonus_mult: float = 0.0

func _init() -> void:
	effect_id = "terrain_bonus"
	effect_name = "Terrain Bonus"
	apply_phase = 3  # OnScoring


func apply_on_scoring(context: ShotContext, upgrade_level: int = 0) -> void:
	if not _terrain_in_path(context):
		return
	
	var scaled_chips = bonus_chips + int(upgrade_level * 5)
	var scaled_mult = bonus_mult + (upgrade_level * 0.2)
	
	if scaled_chips > 0:
		context.chips += scaled_chips
	
	if scaled_mult > 0:
		context.mult += scaled_mult


func _terrain_in_path(context: ShotContext) -> bool:
	"""Check if the bonus terrain type is in the shot path"""
	if context.hole == null or not context.hole.has_method("get_cell"):
		return false
	
	var target_type = _get_terrain_type()
	
	if terrain_is_start:
		# Check starting tile
		var start_terrain = context.hole.get_cell(context.start_tile.x, context.start_tile.y)
		return start_terrain == target_type
	else:
		# Check landing tile
		var landing_terrain = context.hole.get_cell(context.landing_tile.x, context.landing_tile.y)
		if landing_terrain == target_type:
			return true
		
		# Check path tiles
		for tile in context.path_tiles:
			if context.hole.get_cell(tile.x, tile.y) == target_type:
				return true
	
	return false


func _get_terrain_type() -> int:
	# Map target_terrain string to SurfaceType values
	match target_terrain:
		"Fairway": return 1
		"Rough": return 2
		"Sand", "Bunker": return 5
		"Water": return 6
		"Green": return 4
		_: return -1


func get_description(upgrade_level: int = 0) -> String:
	var parts = []
	var scaled_chips = bonus_chips + int(upgrade_level * 5)
	var scaled_mult = bonus_mult + (upgrade_level * 0.2)
	
	if scaled_chips > 0:
		parts.append("+%d Chips" % scaled_chips)
	if scaled_mult > 0:
		parts.append("+%.1f Mult" % scaled_mult)
	
	var location = "starting from" if terrain_is_start else "on"
	return "%s %s: %s" % [location.capitalize(), target_terrain, ", ".join(parts)]
