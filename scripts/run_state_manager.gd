extends Node
class_name RunStateManager

## RunStateManager - Tracks the state of a roguelike run across multiple holes
## Manages hole progression, scoring, and deck state between holes

# Signals
signal hole_started(hole_number: int, par: int, yardage: int)
signal hole_completed(hole_number: int, strokes: int, par: int, hole_score: int)
signal run_completed(total_holes: int, total_strokes: int, total_score: int)
signal score_changed(new_score: int)
signal coins_changed(new_total: int)

# Run configuration
@export var total_holes: int = 9  # 9 or 18 hole round
@export var starting_score: int = 0

# Current run state
var current_hole: int = 1
var total_strokes: int = 0
var total_score: int = 0
var holes_completed: int = 0

# Per-hole tracking
var strokes_this_hole: int = 0
var score_this_hole: int = 0
var current_par: int = 4
var current_yardage: int = 0

# Hole history for scorecard
var hole_history: Array[Dictionary] = []

# Run status
var is_run_active: bool = false

# NEW: Progression tracking
var total_coins_earned: int = 0
var coins_this_hole: int = 0
var best_scores: Dictionary = {}  # hole_number -> best_score

# NEW: Modifier deck state (saved between holes)
var modifier_deck_state: Dictionary = {}


func _ready() -> void:
	pass


# --- Run Lifecycle ---

func start_new_run(holes: int = 9) -> void:
	"""Begin a fresh run"""
	total_holes = holes
	current_hole = 1
	total_strokes = 0
	total_score = starting_score
	holes_completed = 0
	strokes_this_hole = 0
	score_this_hole = 0
	hole_history.clear()
	is_run_active = true
	
	# Reset progression tracking
	total_coins_earned = 0
	coins_this_hole = 0
	best_scores.clear()
	modifier_deck_state.clear()


func end_run() -> void:
	"""End the current run"""
	is_run_active = false
	run_completed.emit(holes_completed, total_strokes, total_score)


# --- Hole Lifecycle ---

func start_hole(par: int, yardage: int) -> void:
	"""Begin a new hole - strokes start at 0 and increment on each actual stroke"""
	current_par = par
	current_yardage = yardage
	strokes_this_hole = 0  # Strokes counter starts at 0, increments on each record_stroke()
	score_this_hole = 0
	coins_this_hole = 0
	
	hole_started.emit(current_hole, par, yardage)


func record_stroke(shot_score: int = 0) -> void:
	"""Record a stroke taken on current hole"""
	strokes_this_hole += 1
	total_strokes += 1
	
	# Add shot score to hole total
	score_this_hole += shot_score
	total_score += shot_score
	score_changed.emit(total_score)


func complete_hole() -> Dictionary:
	"""Complete the current hole and return results"""
	var par_diff = strokes_this_hole - current_par
	
	# Calculate par bonus/penalty
	var par_bonus = _calculate_par_bonus(par_diff)
	score_this_hole += par_bonus
	total_score += par_bonus
	
	# Record history
	var hole_result = {
		"hole": current_hole,
		"par": current_par,
		"yardage": current_yardage,
		"strokes": strokes_this_hole,
		"par_diff": par_diff,
		"score": score_this_hole,
		"par_bonus": par_bonus
	}
	hole_history.append(hole_result)
	
	holes_completed += 1
	
	hole_completed.emit(current_hole, strokes_this_hole, current_par, score_this_hole)
	score_changed.emit(total_score)
	
	return hole_result


func advance_to_next_hole() -> bool:
	"""Move to next hole. Returns false if run is complete."""
	if current_hole >= total_holes:
		end_run()
		return false
	
	current_hole += 1
	strokes_this_hole = 0
	score_this_hole = 0
	return true


# --- Scoring ---

func _calculate_par_bonus(par_diff: int) -> int:
	"""Calculate bonus points based on par performance"""
	match par_diff:
		-3:  # Albatross
			return 500
		-2:  # Eagle
			return 200
		-1:  # Birdie
			return 100
		0:   # Par
			return 50
		1:   # Bogey
			return 10
		_:
			if par_diff < -3:
				return 1000  # Incredible!
			else:
				return 0  # Double bogey or worse


func get_par_name(par_diff: int) -> String:
	"""Get the name for a par differential"""
	match par_diff:
		-3: return "Albatross!"
		-2: return "Eagle!"
		-1: return "Birdie!"
		0: return "Par"
		1: return "Bogey"
		2: return "Double Bogey"
		_:
			if par_diff < -3:
				return "Incredible!"
			else:
				return "+%d" % par_diff


func get_total_par() -> int:
	"""Get total par for all completed holes"""
	var total = 0
	for hole in hole_history:
		total += hole.par
	return total


func get_vs_par() -> int:
	"""Get strokes vs par for completed holes"""
	return total_strokes - get_total_par()


# --- State Queries ---

func get_current_state() -> Dictionary:
	"""Get a snapshot of current run state"""
	return {
		"current_hole": current_hole,
		"total_holes": total_holes,
		"total_strokes": total_strokes,
		"total_score": total_score,
		"holes_completed": holes_completed,
		"strokes_this_hole": strokes_this_hole,
		"current_par": current_par,
		"vs_par": get_vs_par(),
		"is_run_active": is_run_active
	}


func is_final_hole() -> bool:
	"""Check if on the last hole"""
	return current_hole >= total_holes


func get_hole_display() -> String:
	"""Get formatted hole display string"""
	return "Hole %d of %d" % [current_hole, total_holes]


# --- Coin Tracking ---

func add_coins(amount: int) -> void:
	"""Add coins collected during play"""
	coins_this_hole += amount
	total_coins_earned += amount
	coins_changed.emit(total_coins_earned)


func get_coins_this_hole() -> int:
	return coins_this_hole


func get_total_coins() -> int:
	return total_coins_earned


# --- Best Score Tracking ---

func update_best_score(hole_number: int, score: int) -> bool:
	"""Update best score for a hole. Returns true if it's a new best."""
	if hole_number not in best_scores or score > best_scores[hole_number]:
		best_scores[hole_number] = score
		return true
	return false


func get_best_score(hole_number: int) -> int:
	"""Get best score for a hole, or 0 if not played"""
	return best_scores.get(hole_number, 0)


# --- Modifier Deck State ---

func save_modifier_deck_state(composition: Dictionary) -> void:
	"""Save modifier deck state between holes"""
	modifier_deck_state = composition.duplicate()


func get_modifier_deck_state() -> Dictionary:
	"""Get saved modifier deck state"""
	return modifier_deck_state


func has_saved_deck_state() -> bool:
	"""Check if there's a saved deck state"""
	return not modifier_deck_state.is_empty()


# --- Run Statistics ---

func get_run_statistics() -> Dictionary:
	"""Get comprehensive run statistics for UI display"""
	return {
		"current_hole": current_hole,
		"total_holes": total_holes,
		"holes_completed": holes_completed,
		"total_strokes": total_strokes,
		"total_score": total_score,
		"total_coins": total_coins_earned,
		"vs_par": get_vs_par(),
		"best_scores": best_scores.duplicate(),
		"is_run_active": is_run_active
	}
