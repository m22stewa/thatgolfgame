extends Node
class_name LieSystem

## LieSystem - Manages how different lies (terrain types) affect shots
## 
## Lie effects based on real golf:
## - TEE: Perfect lie, ball on tee peg. Best conditions.
## - FAIRWAY: Clean lie, short grass. Excellent contact.
## - ROUGH: Ball sitting in longer grass. Reduced distance, less spin control.
## - DEEP_ROUGH: Ball buried in thick grass. Major distance/accuracy loss.
## - SAND: Bunker lie. Requires different technique, distance unpredictable.
## - GREEN: Putting surface. Not typically hit from (chipping possible).

## Lie data structure - all values are additive modifiers (+/- from baseline)
## power_mod: Tiles added/subtracted from max distance
## accuracy_mod: AOE rings added (positive = less accurate, bigger AOE)
## spin_mod: Spin effectiveness change
## curve_mod: Curve/shape effectiveness change  
## roll_mod: Roll tiles added/subtracted
## chip_bonus: Additive bonus/penalty to chips scored
## mult_bonus: Additive bonus/penalty to scoring multiplier

const LIE_DATA = {
	"TEE": {
		"display_name": "Tee Box",
		"description": "Perfect lie on a tee. Full power and control.",
		"power_mod": 0,        # No change - baseline
		"accuracy_mod": 0,     # Normal AOE
		"spin_mod": 0.0,
		"curve_mod": 0.0,
		"roll_mod": 0,
		"chip_bonus": 5,
		"mult_bonus": 0.0,
		"allowed_clubs": ["DRIVER", "WOOD_3", "WOOD_5", "IRON_3", "IRON_5", "IRON_6", "IRON_7", "IRON_8", "IRON_9", "PITCHING_WEDGE"],
		"color": Color(0.4, 0.8, 0.4),
	},
	"FAIRWAY": {
		"display_name": "Fairway",
		"description": "Clean lie on short grass. Excellent contact.",
		"power_mod": 0,        # Standard distance
		"accuracy_mod": 0,
		"spin_mod": 0.0,
		"curve_mod": 0.0,
		"roll_mod": 0,
		"chip_bonus": 0,
		"mult_bonus": 0.1,
		"allowed_clubs": ["WOOD_3", "WOOD_5", "IRON_3", "IRON_5", "IRON_6", "IRON_7", "IRON_8", "IRON_9", "PITCHING_WEDGE", "SAND_WEDGE"],
		"color": Color(0.3, 0.7, 0.3),
	},
	"ROUGH": {
		"display_name": "Rough",
		"description": "Ball in longer grass. Reduced distance and spin.",
		"power_mod": -4,       # 4 tiles less distance
		"accuracy_mod": 1,     # +1 AOE ring (less accurate)
		"spin_mod": -0.5,
		"curve_mod": -0.3,
		"roll_mod": -1,
		"chip_bonus": -5,
		"mult_bonus": 0.0,
		"allowed_clubs": ["IRON_5", "IRON_6", "IRON_7", "IRON_8", "IRON_9", "PITCHING_WEDGE", "SAND_WEDGE"],
		"color": Color(0.2, 0.5, 0.2),
	},
	"DEEP_ROUGH": {
		"display_name": "Deep Rough",
		"description": "Ball buried in thick grass. Major power and control loss.",
		"power_mod": -8,       # 8 tiles less distance
		"accuracy_mod": 2,     # +2 AOE rings (very inaccurate)
		"spin_mod": -0.8,
		"curve_mod": -0.7,
		"roll_mod": -2,
		"chip_bonus": -15,
		"mult_bonus": -0.2,
		"allowed_clubs": ["IRON_7", "IRON_8", "IRON_9", "PITCHING_WEDGE", "SAND_WEDGE"],
		"color": Color(0.15, 0.35, 0.15),
	},
	"SAND": {
		"display_name": "Bunker",
		"description": "Sand trap. Use sand wedge for best results.",
		"power_mod": -6,       # 6 tiles less distance
		"accuracy_mod": 1,     # +1 AOE ring
		"spin_mod": 0.5,       # Can get more spin from sand
		"curve_mod": -0.6,
		"roll_mod": -2,
		"chip_bonus": -20,
		"mult_bonus": 0.0,
		"preferred_club": "SAND_WEDGE",
		"allowed_clubs": ["SAND_WEDGE", "PITCHING_WEDGE", "IRON_9"],
		"color": Color(0.9, 0.85, 0.6),
	},
	"GREEN": {
		"display_name": "Green",
		"description": "Putting surface. Putter only.",
		"power_mod": -15,      # Very short - chip only if not putting
		"accuracy_mod": -1,    # More accurate for chips
		"spin_mod": 0.0,
		"curve_mod": 0.0,
		"roll_mod": 2,         # Ball rolls more on green
		"chip_bonus": 0,
		"mult_bonus": 0.0,
		"preferred_club": "PUTTER",
		"allowed_clubs": ["PUTTER"],
		"color": Color(0.5, 0.9, 0.5),
	},
	"WATER": {
		"display_name": "Water",
		"description": "Penalty area. Drop required.",
		"power_mod": -100,     # Can't hit from water
		"accuracy_mod": 0,
		"spin_mod": 0.0,
		"curve_mod": 0.0,
		"roll_mod": 0,
		"chip_bonus": -50,
		"mult_bonus": -0.5,
		"allowed_clubs": [],
		"color": Color(0.2, 0.4, 0.8),
	},
	"TREE": {
		"display_name": "Trees",
		"description": "Obstructed lie. Limited swing options.",
		"power_mod": -10,
		"accuracy_mod": 2,     # Very inaccurate
		"spin_mod": -0.7,
		"curve_mod": -0.8,
		"roll_mod": -1,
		"chip_bonus": -25,
		"mult_bonus": -0.3,
		"allowed_clubs": ["IRON_7", "IRON_8", "IRON_9", "PITCHING_WEDGE", "SAND_WEDGE"],
		"color": Color(0.3, 0.25, 0.1),
	},
	"FLAG": {
		"display_name": "Hole",
		"description": "In the cup!",
		"power_mod": 0,
		"accuracy_mod": 0,
		"spin_mod": 0.0,
		"curve_mod": 0.0,
		"roll_mod": 0,
		"chip_bonus": 100,
		"mult_bonus": 1.0,
		"allowed_clubs": [],
		"color": Color(1.0, 0.8, 0.0),
	},
}

# Surface type enum to string mapping
const SURFACE_TO_LIE = {
	0: "TEE",
	1: "FAIRWAY", 
	2: "ROUGH",
	3: "DEEP_ROUGH",
	4: "GREEN",
	5: "SAND",
	6: "WATER",
	7: "TREE",
	8: "FLAG",
}

# Signals for UI and other systems
signal lie_calculated(lie_info: Dictionary)
signal lie_modifiers_applied(context: ShotContext, lie_info: Dictionary)


# Current lie info - stored for external access
var current_lie_info: Dictionary = {}


func _ready() -> void:
	pass


## Get lie name from surface type enum value
func get_lie_name(surface_type: int) -> String:
	return SURFACE_TO_LIE.get(surface_type, "FAIRWAY")


## Get full lie data for a surface type
func get_lie_data(surface_type: int) -> Dictionary:
	var lie_name = get_lie_name(surface_type)
	return LIE_DATA.get(lie_name, LIE_DATA["FAIRWAY"]).duplicate()


## Calculate lie info for a given tile position
## Returns a dictionary with all lie modifiers and display info
func calculate_lie(hex_grid: Node, tile: Vector2i) -> Dictionary:
	if hex_grid == null or tile.x < 0:
		return get_lie_data(1)  # Default to fairway
	
	var surface_type = hex_grid.get_cell(tile.x, tile.y)
	var lie_data = get_lie_data(surface_type)
	
	# Add tile info
	lie_data["tile"] = tile
	lie_data["surface_type"] = surface_type
	lie_data["lie_name"] = get_lie_name(surface_type)
	
	# Calculate elevation effect (uphill/downhill)
	var elevation = hex_grid.get_elevation(tile.x, tile.y)
	lie_data["elevation"] = elevation
	
	# Check for slope effects
	var slope_info = _calculate_slope_effect(hex_grid, tile)
	lie_data["slope_direction"] = slope_info.direction
	lie_data["slope_strength"] = slope_info.strength
	
	# Uphill lies reduce power slightly, downhill can add distance
	if slope_info.strength > 0.1:
		if slope_info.direction == "uphill":
			lie_data["power_mod"] -= int(slope_info.strength * 2)  # Lose distance uphill
			lie_data["description"] += " Uphill stance."
		elif slope_info.direction == "downhill":
			lie_data["power_mod"] += int(slope_info.strength)  # Gain distance downhill
			lie_data["description"] += " Downhill stance."
		elif slope_info.direction == "sidehill_left" or slope_info.direction == "sidehill_right":
			lie_data["accuracy_mod"] += 1  # Lose accuracy on sidehill
			lie_data["description"] += " Sidehill lie."
	
	current_lie_info = lie_data
	lie_calculated.emit(lie_data)
	
	return lie_data


## Calculate slope at a tile position
func _calculate_slope_effect(hex_grid: Node, tile: Vector2i) -> Dictionary:
	var result = {"direction": "flat", "strength": 0.0}
	
	if not hex_grid.has_method("get_elevation"):
		return result
	
	var center_elev = hex_grid.get_elevation(tile.x, tile.y)
	
	# Check neighbors for slope
	var north_elev = hex_grid.get_elevation(tile.x, tile.y + 1)
	var south_elev = hex_grid.get_elevation(tile.x, tile.y - 1)
	var east_elev = hex_grid.get_elevation(tile.x + 1, tile.y)
	var west_elev = hex_grid.get_elevation(tile.x - 1, tile.y)
	
	# North-South slope (assuming hitting toward positive Y/north)
	var ns_slope = north_elev - south_elev
	# East-West slope
	var ew_slope = east_elev - west_elev
	
	if abs(ns_slope) > abs(ew_slope):
		result.strength = abs(ns_slope)
		if ns_slope > 0.1:
			result.direction = "uphill"
		elif ns_slope < -0.1:
			result.direction = "downhill"
	else:
		result.strength = abs(ew_slope)
		if ew_slope > 0.1:
			result.direction = "sidehill_right"
		elif ew_slope < -0.1:
			result.direction = "sidehill_left"
	
	return result


## Apply lie effects to a ShotContext
## Call this during the shot lifecycle (before aim or on shot start)
func apply_lie_to_shot(context: ShotContext, lie_info: Dictionary) -> void:
	if context == null or lie_info.is_empty():
		return
	
	# Set the additive modifier fields on the context
	context.power_mod += lie_info.get("power_mod", 0)
	context.accuracy_mod += lie_info.get("accuracy_mod", 0)
	context.spin_mod += lie_info.get("spin_mod", 0.0)
	context.curve_mod += lie_info.get("curve_mod", 0.0)
	context.roll_mod += lie_info.get("roll_mod", 0)
	
	# Store lie info in context metadata (for UI and debugging)
	context.add_metadata("lie_info", lie_info)
	context.add_metadata("lie_name", lie_info.get("lie_name", "FAIRWAY"))
	context.add_metadata("power_mod", lie_info.get("power_mod", 0))
	context.add_metadata("accuracy_mod", lie_info.get("accuracy_mod", 0))
	context.add_metadata("allowed_clubs", lie_info.get("allowed_clubs", []))
	context.add_metadata("preferred_club", lie_info.get("preferred_club", ""))
	
	# AOE radius affected by accuracy mod
	var accuracy_mod = lie_info.get("accuracy_mod", 0)
	if accuracy_mod > 0:
		context.aoe_radius += accuracy_mod
	
	# Apply scoring effects
	context.chips += lie_info.get("chip_bonus", 0)
	context.mult += lie_info.get("mult_bonus", 0.0)
	
	# Store terrain info
	context.set_start_terrain(lie_info.get("display_name", "Unknown"))
	
	lie_modifiers_applied.emit(context, lie_info)


## Get a formatted string for debug display
func get_lie_debug_string(lie_info: Dictionary) -> String:
	if lie_info.is_empty():
		return "No lie info"
	
	var lines = []
	lines.append("[b]%s[/b]" % lie_info.get("display_name", "Unknown"))
	lines.append(lie_info.get("description", ""))
	lines.append("")
	lines.append("[u]Modifiers:[/u]")
	
	var power_mod = lie_info.get("power_mod", 0)
	if power_mod != 0:
		lines.append("Distance: %s%d tiles" % ["+" if power_mod > 0 else "", power_mod])
	
	var accuracy_mod = lie_info.get("accuracy_mod", 0)
	if accuracy_mod != 0:
		lines.append("Accuracy: %s%d AOE" % ["+" if accuracy_mod > 0 else "", accuracy_mod])
	
	var spin_mod = lie_info.get("spin_mod", 0.0)
	if spin_mod != 0.0:
		lines.append("Spin: %s%.1f" % ["+" if spin_mod > 0 else "", spin_mod])
	
	var curve_mod = lie_info.get("curve_mod", 0.0)
	if curve_mod != 0.0:
		lines.append("Curve: %s%.1f" % ["+" if curve_mod > 0 else "", curve_mod])
	
	var roll_mod = lie_info.get("roll_mod", 0)
	if roll_mod != 0:
		lines.append("Roll: %s%d tiles" % ["+" if roll_mod > 0 else "", roll_mod])
	
	if lie_info.get("chip_bonus", 0) != 0:
		var bonus = lie_info.get("chip_bonus", 0)
		lines.append("Chips: %s%d" % ["+" if bonus > 0 else "", bonus])
	
	if lie_info.get("mult_bonus", 0.0) != 0.0:
		var bonus = lie_info.get("mult_bonus", 0.0)
		lines.append("Mult: %s%.1f" % ["+" if bonus > 0 else "", bonus])
	
	if lie_info.get("slope_strength", 0.0) > 0.1:
		lines.append("")
		lines.append("Slope: %s (%.0f%%)" % [
			lie_info.get("slope_direction", "flat").capitalize().replace("_", " "),
			lie_info.get("slope_strength", 0.0) * 100
		])
	
	return "\n".join(lines)


## Get max club distance modified by lie (additive)
func get_modified_distance(base_distance: int, lie_info: Dictionary) -> int:
	var power_mod = lie_info.get("power_mod", 0)
	return maxi(1, base_distance + power_mod)
