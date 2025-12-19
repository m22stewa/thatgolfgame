extends Node
class_name ScoringManager

## ScoringManager - Handles point calculations for landing, multipliers, and golf bonuses
## Base Points per hex:
## - Fairway: +10
## - Green: +20
## - Rough: +5
## - Sand: -5
## - Water: -10
## 
## Multipliers:
## - Consecutive fairways: 1.5x (2nd), 2x (3rd), 2.5x (4th+)
## - Coin on same shot: 2x
## - Item used: +50 bonus
##
## Golf Bonuses (at hole completion):
## - Birdie (-1): +100
## - Eagle (-2): +250
## - Albatross (-3): +500
## - Par or better: +50

signal points_awarded(points: int, reason: String, multiplier: float)
signal multiplier_changed(new_multiplier: float)
signal streak_changed(streak_count: int)
signal golf_bonus_awarded(bonus_name: String, bonus_points: int)
signal hole_score_calculated(total: int, breakdown: Dictionary)

# Base points per surface type (uses SurfaceType enum from hex_grid)
const BASE_POINTS = {
	0: 10,   # TEE (treat as fairway)
	1: 10,   # FAIRWAY
	2: 5,    # ROUGH
	3: 0,    # DEEP_ROUGH
	4: 20,   # GREEN
	5: -5,   # SAND
	6: -10,  # WATER
	7: 0,    # TREE
	8: 20,   # FLAG (same as green)
}

# Surface type names for display
const SURFACE_NAMES = {
	0: "Tee Box",
	1: "Fairway",
	2: "Rough",
	3: "Deep Rough",
	4: "Green",
	5: "Sand",
	6: "Water",
	7: "Tree",
	8: "Flag",
}

# Hazard surfaces that reset streak
const HAZARD_SURFACES = [2, 3, 5, 6]  # Rough, Deep Rough, Sand, Water

# Consecutive fairway multipliers
const FAIRWAY_MULTIPLIERS = {
	0: 1.0,
	1: 1.0,
	2: 1.5,
	3: 2.0,
	4: 2.5,  # 4+ stays at 2.5x
}

# Golf bonus points
const GOLF_BONUSES = {
	-4: {"name": "Condor!", "points": 1000},
	-3: {"name": "Albatross!", "points": 500},
	-2: {"name": "Eagle!", "points": 250},
	-1: {"name": "Birdie!", "points": 100},
	0: {"name": "Par", "points": 50},
}

# Item usage bonus
const ITEM_BONUS: int = 50

# State
var consecutive_fairways: int = 0
var current_multiplier: float = 1.0
var hole_points: int = 0
var shot_used_item: bool = false
var shot_collected_coin: bool = false


func _ready() -> void:
	reset_for_hole()


func reset_for_hole() -> void:
	"""Reset scoring state for a new hole"""
	consecutive_fairways = 0
	current_multiplier = 1.0
	hole_points = 0
	shot_used_item = false
	shot_collected_coin = false
	streak_changed.emit(consecutive_fairways)
	multiplier_changed.emit(current_multiplier)


func reset_for_shot() -> void:
	"""Reset per-shot state"""
	shot_used_item = false
	shot_collected_coin = false


func set_item_used() -> void:
	"""Mark that an item was used this shot"""
	shot_used_item = true


func set_coin_collected() -> void:
	"""Mark that a coin was collected this shot"""
	shot_collected_coin = true


func calculate_landing_points(surface_type: int) -> Dictionary:
	"""Calculate points for landing on a surface. Returns breakdown dict."""
	var breakdown = {
		"base_points": 0,
		"multiplier": current_multiplier,
		"item_bonus": 0,
		"coin_multiplier": 1.0,
		"final_points": 0,
		"surface_name": SURFACE_NAMES.get(surface_type, "Unknown"),
	}
	
	# Get base points
	var base = BASE_POINTS.get(surface_type, 0)
	breakdown["base_points"] = base
	
	# Update streak
	_update_streak(surface_type)
	breakdown["multiplier"] = current_multiplier
	
	# Apply coin multiplier
	if shot_collected_coin:
		breakdown["coin_multiplier"] = 2.0
	
	# Apply item bonus
	if shot_used_item:
		breakdown["item_bonus"] = ITEM_BONUS
	
	# Calculate final
	var final_points = base
	final_points = int(final_points * current_multiplier)
	final_points = int(final_points * breakdown["coin_multiplier"])
	final_points += breakdown["item_bonus"]
	
	breakdown["final_points"] = final_points
	hole_points += final_points
	
	# Emit signals
	var reason = "Landed on %s" % breakdown["surface_name"]
	if breakdown["multiplier"] > 1.0:
		reason += " (%.1fx streak)" % breakdown["multiplier"]
	if breakdown["coin_multiplier"] > 1.0:
		reason += " (2x coin)"
	
	points_awarded.emit(final_points, reason, current_multiplier)
	
	return breakdown


func _update_streak(surface_type: int) -> void:
	"""Update consecutive fairway streak based on landing surface"""
	# Fairway and Tee count as fairway for streak
	if surface_type == 0 or surface_type == 1:  # TEE or FAIRWAY
		consecutive_fairways += 1
		# Cap at 4 for multiplier purposes
		var multiplier_key = min(consecutive_fairways, 4)
		current_multiplier = FAIRWAY_MULTIPLIERS.get(multiplier_key, 1.0)
	elif surface_type in HAZARD_SURFACES:
		# Reset streak on hazard
		consecutive_fairways = 0
		current_multiplier = 1.0
	# Green doesn't affect streak (keeps current)
	
	streak_changed.emit(consecutive_fairways)
	multiplier_changed.emit(current_multiplier)


func calculate_hole_bonus(strokes: int, par: int) -> Dictionary:
	"""Calculate bonus points at hole completion. Returns breakdown dict."""
	var par_diff = strokes - par
	var breakdown = {
		"strokes": strokes,
		"par": par,
		"par_diff": par_diff,
		"bonus_name": "",
		"bonus_points": 0,
		"hole_points": hole_points,
		"total_points": hole_points,
	}
	
	# Look up golf bonus
	if par_diff in GOLF_BONUSES:
		var bonus = GOLF_BONUSES[par_diff]
		breakdown["bonus_name"] = bonus["name"]
		breakdown["bonus_points"] = bonus["points"]
		breakdown["total_points"] += bonus["points"]
		
		golf_bonus_awarded.emit(bonus["name"], bonus["points"])
	elif par_diff < -4:
		# Even better than condor!
		breakdown["bonus_name"] = "Incredible!"
		breakdown["bonus_points"] = 2000
		breakdown["total_points"] += 2000
		golf_bonus_awarded.emit("Incredible!", 2000)
	
	hole_score_calculated.emit(breakdown["total_points"], breakdown)
	
	return breakdown


func get_par_diff_name(par_diff: int) -> String:
	"""Get the golf term for a par differential"""
	match par_diff:
		-4: return "Condor"
		-3: return "Albatross"
		-2: return "Eagle"
		-1: return "Birdie"
		0: return "Par"
		1: return "Bogey"
		2: return "Double Bogey"
		3: return "Triple Bogey"
		_:
			if par_diff < -4:
				return "Incredible!"
			else:
				return "+%d" % par_diff


func get_current_multiplier() -> float:
	return current_multiplier


func get_consecutive_fairways() -> int:
	return consecutive_fairways


func get_hole_points() -> int:
	return hole_points
