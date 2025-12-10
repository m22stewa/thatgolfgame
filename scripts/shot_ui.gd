extends Control
class_name ShotUI

## ShotUI - Visual interface for the shot system
## Connect this to ShotManager signals and hex_grid for live updates

# Signals
signal next_hole_requested()

# Swing meter scene
const SwingMeterScene = preload("res://scenes/ui/SwingMeter.tscn")
const ShotNumberScene = preload("res://scenes/ui/shot_number.tscn")

# UI element references - set via unique names
@onready var hole_label: Label = %HoleLabel
@onready var hole_progress_label: Label = %HoleProgressLabel if has_node("%HoleProgressLabel") else null
@onready var par_label: Label = %ParLabel
@onready var yardage_label: Label = %YardageLabel
@onready var shot_numbers: HBoxContainer = %ShotNumbers
@onready var distance_label: Label = %DistanceLabel

@onready var club_name: Label = %ClubName
@onready var club_range: Label = %ClubRange
@onready var current_terrain: Label = %CurrentTerrain
@onready var terrain_effect: Label = %TerrainEffect
@onready var target_terrain: Label = %TargetTerrain
@onready var target_distance: Label = %TargetDistance

@onready var confirm_button: Button = %ConfirmButton
@onready var score_popup: PanelContainer = $ScorePopup

# Swing meter instance
var swing_meter: SwingMeter = null

# Current shot difficulty (for swing meter)
var current_club_difficulty: float = 0.5
var current_lie_difficulty: float = 0.0
var current_power_cap: float = 1.0
var current_lie_info: Dictionary = {}  # Store for recalculating when club changes

@onready var score_title: Label = %ScoreTitle
@onready var score_value: Label = %ScoreValue
@onready var score_details: Label = %ScoreDetails

# Persistent score display in TopBar - get by path since it may not have unique name
var persistent_score_label: Label = null
var chips_label: Label = null  # Display for currency
var score_tween: Tween = null
var displayed_score: int = 0  # For animated counting
var displayed_chips: int = 0  # For animated chip counting

# Currency reference
var currency_manager: CurrencyManager = null

@onready var hole_complete_popup: PanelContainer = $HoleCompletePopup
@onready var hole_complete_title: Label = %HoleCompleteTitle
@onready var hole_score: Label = %HoleScore
@onready var total_score: Label = %TotalScore
@onready var next_button: Button = %NextButton

# References to game systems (set externally)
var shot_manager: ShotManager = null
var hole_controller: Node3D = null  # hex_grid reference
var run_state: RunStateManager = null  # Run progression tracking

# Game state
var current_hole: int = 1
var current_par: int = 4
var current_yardage: int = 0
var total_points: int = 0
var shots_this_hole: int = 0
var total_holes: int = 9

# Club data (name, min_yards, max_yards)
var clubs = [
	["Driver", 190, 220],      # 22 tiles max = 220 yards
	["3 Wood", 170, 200],      # 20 tiles max = 200 yards
	["5 Wood", 150, 180],      # 18 tiles max = 180 yards
	["3 Iron", 140, 170],      # 17 tiles max = 170 yards
	["5 Iron", 130, 160],      # 16 tiles max = 160 yards
	["6 Iron", 120, 150],      # 15 tiles max = 150 yards
	["7 Iron", 110, 140],      # 14 tiles max = 140 yards
	["8 Iron", 100, 130],      # 13 tiles max = 130 yards
	["9 Iron", 90, 120],       # 12 tiles max = 120 yards
	["Pitching Wedge", 70, 110],  # 11 tiles max = 110 yards
	["Sand Wedge", 50, 90],    # 9 tiles max = 90 yards
	["Putter", 5, 20]
]
var selected_club: int = 0

# Terrain display names and effects
var terrain_names = {
	0: "Tee Box",
	1: "Fairway",
	2: "Rough",
	3: "Deep Rough",
	4: "Green",
	5: "Sand Trap",
	6: "Water",
	7: "Trees",
	8: "Flag"
}

var terrain_effects = {
	0: ["No penalty", Color(0.5, 0.8, 0.5)],
	1: ["+10% Mult", Color(0.5, 0.8, 0.5)],
	2: ["-2 Chips", Color(0.8, 0.6, 0.3)],
	3: ["-5 Chips", Color(0.8, 0.5, 0.2)],
	4: ["+50% Mult", Color(0.4, 0.9, 0.4)],
	5: ["-10 Chips", Color(0.8, 0.7, 0.3)],
	6: ["50% Chip Loss!", Color(0.8, 0.3, 0.3)],
	7: ["-8 Chips", Color(0.6, 0.4, 0.2)],
	8: ["2x Mult!", Color(1.0, 0.85, 0.0)]
}


func _ready() -> void:
	# Hide popups initially
	score_popup.visible = false
	hole_complete_popup.visible = false
	
	# Hide the confirm button - swing meter replaces it
	confirm_button.visible = false
	
	# Connect button signals
	next_button.pressed.connect(_on_next_hole_pressed)
	
	# Get the persistent score label from ScoreInfo (at root level)
	persistent_score_label = get_node_or_null("ScoreInfo/ScoreValue")
	if persistent_score_label:
		persistent_score_label.text = "0"
	
	# Find or create swing meter (may be added via scene in main_ui)
	_setup_swing_meter()
	
	# Initial UI state
	update_club_display()


func _setup_swing_meter() -> void:
	"""Find existing swing meter from parent (main_ui) or create one if not found"""
	# First, look for SwingMeter as a sibling (added via main_ui.tscn)
	var parent = get_parent()
	if parent:
		swing_meter = parent.get_node_or_null("SwingMeter") as SwingMeter
	
	# If not found as sibling, create one dynamically
	if not swing_meter:
		swing_meter = SwingMeterScene.instantiate()
		add_child(swing_meter)
	
	# Connect signals
	if swing_meter:
		if not swing_meter.swing_completed.is_connected(_on_swing_completed):
			swing_meter.swing_completed.connect(_on_swing_completed)
		if not swing_meter.swing_cancelled.is_connected(_on_swing_cancelled):
			swing_meter.swing_cancelled.connect(_on_swing_cancelled)


func setup(p_shot_manager: ShotManager, p_hole_controller: Node3D) -> void:
	"""Connect to shot manager and hole controller"""
	shot_manager = p_shot_manager
	hole_controller = p_hole_controller
	
	if shot_manager:
		shot_manager.shot_started.connect(_on_shot_started)
		shot_manager.aoe_computed.connect(_on_aoe_computed)
		shot_manager.shot_completed.connect(_on_shot_completed)


func set_currency_manager(p_currency: CurrencyManager) -> void:
	"""Connect to currency manager for chips display"""
	currency_manager = p_currency
	if currency_manager:
		if not currency_manager.currency_changed.is_connected(_on_currency_changed):
			currency_manager.currency_changed.connect(_on_currency_changed)
		# Initial update
		_update_chips_display(currency_manager.get_balance())


func _on_currency_changed(new_amount: int, _delta: int) -> void:
	"""Handle currency change - update chips display"""
	_update_chips_display(new_amount)


func _update_chips_display(amount: int) -> void:
	"""Update the chips label with animation"""
	if chips_label:
		chips_label.text = "💰 %d" % amount
	displayed_chips = amount


func set_hole_info(hole: int, par: int, yardage: int) -> void:
	"""Update hole information display"""
	current_hole = hole
	current_par = par
	current_yardage = yardage
	shots_this_hole = 0
	
	if hole_label:
		hole_label.text = "Hole %d" % hole
	if par_label:
		par_label.text = "Par %d" % par
	if yardage_label:
		yardage_label.text = "%d yds" % yardage


func update_shot_info(strokes_taken: int, distance_to_flag: int) -> void:
	"""Update shot counter and distance. strokes_taken is how many shots have been made."""
	shots_this_hole = strokes_taken
	# Display shows which shot number we're ON (next shot to take)
	# After 0 strokes, we're on shot 1. After 1 stroke, we're on shot 2.
	_update_shot_counter_visuals(strokes_taken + 1)
	distance_label.text = "%d yds to flag" % distance_to_flag


func _update_shot_counter_visuals(current_shot: int) -> void:
	if not shot_numbers: return
	
	# Clear existing
	for child in shot_numbers.get_children():
		child.queue_free()
	
	# Determine range (e.g. up to Par + 2, or current shot if higher)
	var max_display = max(current_par + 2, current_shot + 1)
	if max_display < 5: max_display = 5 # Minimum 5
	
	for i in range(1, max_display + 1):
		var shot_node = ShotNumberScene.instantiate()
		shot_numbers.add_child(shot_node)
		shot_node.set_number(i)
		
		if i == current_shot:
			shot_node.set_state("current")
		elif i < current_shot:
			shot_node.set_state("past")
		else:
			shot_node.set_state("future")


func update_current_terrain(terrain_type: int) -> void:
	"""Update the terrain display for ball's current position"""
	current_terrain.text = terrain_names.get(terrain_type, "Unknown")
	var effect = terrain_effects.get(terrain_type, ["", Color.WHITE])
	terrain_effect.text = effect[0]
	terrain_effect.add_theme_color_override("font_color", effect[1])


func update_target_info(terrain_type: int, distance: int) -> void:
	"""Update target terrain and distance"""
	target_terrain.text = terrain_names.get(terrain_type, "---")
	target_distance.text = "%d yds" % distance
	
	# Check if club is selected
	var club_selected = true
	if hole_controller and hole_controller.has_method("is_club_selected"):
		club_selected = hole_controller.is_club_selected()
	
	# Show swing meter when target is valid and club is selected
	if terrain_type >= 0 and swing_meter and club_selected:
		if not swing_meter.visible:
			# Configure swing meter for current club/lie
			swing_meter.configure_for_shot(current_club_difficulty, current_lie_difficulty, current_power_cap)
			swing_meter.show_meter(1.0)
			
			# Force layout update to ensure track width is correct
			swing_meter.reset_size()
			swing_meter.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			# Set fixed offset from bottom (don't accumulate)
			swing_meter.anchor_top = 1.0
			swing_meter.anchor_bottom = 1.0
			swing_meter.offset_top = -150
			swing_meter.offset_bottom = -50


func update_club_display() -> void:
	"""Update club name and range display"""
	var club = clubs[selected_club]
	club_name.text = club[0]
	club_range.text = "%d-%d yds" % [club[1], club[2]]
	_update_club_difficulty()


func update_lie_info(lie_info: Dictionary) -> void:
	"""Calculate difficulty for swing meter based on lie"""
	
	# Store lie info for recalculating when club changes
	current_lie_info = lie_info
	
	# Get lie info for difficulty calculations
	var lie_name = lie_info.get("lie_name", "FAIRWAY")
	var accuracy_mod = lie_info.get("accuracy_mod", 0)
	var power_mod = lie_info.get("power_mod", 0)
	
	# Calculate lie difficulty (0.0 = easy, 1.0 = hard)
	# Based on accuracy_mod: 0 = easy, 2+ = hard
	current_lie_difficulty = clamp(accuracy_mod / 2.0, 0.0, 1.0)
	
	# Check if current club is appropriate for this lie
	# Hitting driver off fairway is harder, off rough is very hard
	var allowed_clubs = lie_info.get("allowed_clubs", [])
	var club_name = _get_current_club_name()
	var club_is_appropriate = allowed_clubs.is_empty() or club_name in allowed_clubs
	
	# If club is not appropriate for the lie, increase difficulty significantly
	if not club_is_appropriate:
		current_lie_difficulty = min(current_lie_difficulty + 0.5, 1.0)
	
	# Calculate power cap from power_mod AND club appropriateness
	# power_mod of -15 or worse = can't hit at full power
	if power_mod <= -15:
		current_power_cap = 0.3  # Very limited power (chip only)
	elif power_mod <= -8:
		current_power_cap = 0.6  # Moderate power limit
	elif power_mod <= -4:
		current_power_cap = 0.8  # Slight power limit
	else:
		current_power_cap = 1.0  # Full power
	
	# Further limit power if club doesn't suit the lie
	# E.g., driver off rough = only 70% max power
	if not club_is_appropriate:
		current_power_cap = min(current_power_cap, 0.7)
	
	# Special case: Long clubs (Driver, Woods) off fairway (not tee) should be harder
	# BUT woods should still get full power, just slightly harder swing
	if club_name == "DRIVER" and lie_name == "FAIRWAY":
		current_lie_difficulty = max(current_lie_difficulty, 0.4)  # At least medium difficulty
		current_power_cap = min(current_power_cap, 0.9)  # Slight power limit
	elif (club_name == "WOOD_3" or club_name == "WOOD_5") and lie_name == "FAIRWAY":
		current_lie_difficulty = max(current_lie_difficulty, 0.3)  # Moderate difficulty
		# Woods get full power off fairway - they're designed for this


func _get_current_club_name() -> String:
	"""Get the internal name of the currently selected club"""
	var club_names = ["DRIVER", "WOOD_3", "WOOD_5", "IRON_3", "IRON_5", "IRON_6", 
					  "IRON_7", "IRON_8", "IRON_9", "PITCHING_WEDGE", "SAND_WEDGE", "PUTTER"]
	if selected_club >= 0 and selected_club < club_names.size():
		return club_names[selected_club]
	return "IRON_7"


func _format_modifier_additive(stat_name: String, value: float, positive_is_good: bool) -> String:
	"""Format an additive modifier with color coding"""
	if value == 0:
		return "[color=white]%s: 0[/color]" % stat_name
	
	var is_good = (value > 0) == positive_is_good
	var color = "lime" if is_good else ("orange" if abs(value) <= 2 else "red")
	var sign = "+" if value > 0 else ""
	
	if abs(value) == int(abs(value)):
		return "[color=%s]%s: %s%d[/color]" % [color, stat_name, sign, int(value)]
	else:
		return "[color=%s]%s: %s%.1f[/color]" % [color, stat_name, sign, value]


func _format_modifier(name: String, value: int) -> String:
	"""Format a modifier with color coding"""
	var color = "white"
	if value > 100:
		color = "green"
	elif value < 100:
		color = "orange" if value >= 70 else "red"
	return "[color=%s]%s: %d%%[/color]" % [color, name, value]


func select_club(index: int) -> void:
	"""Change selected club"""
	selected_club = clamp(index, 0, clubs.size() - 1)
	update_club_display()
	_update_club_difficulty()


func _update_club_difficulty() -> void:
	"""Calculate club difficulty based on selected club.
	Driver/woods = hard (1.0), irons = medium, wedges = easy (0.0)"""
	# Club order: Driver, 3W, 5W, 3I, 5I, 6I, 7I, 8I, 9I, PW, SW, Putter
	# Index:      0       1    2    3    4    5    6    7    8   9   10   11
	match selected_club:
		0:  # Driver - hardest
			current_club_difficulty = 1.0
		1:  # 3 Wood
			current_club_difficulty = 0.9
		2:  # 5 Wood
			current_club_difficulty = 0.8
		3:  # 3 Iron
			current_club_difficulty = 0.7
		4:  # 5 Iron
			current_club_difficulty = 0.5
		5, 6:  # 6-7 Iron
			current_club_difficulty = 0.4
		7, 8:  # 8-9 Iron
			current_club_difficulty = 0.3
		9:  # PW
			current_club_difficulty = 0.2
		10:  # SW
			current_club_difficulty = 0.15
		11:  # Putter
			current_club_difficulty = 0.0
		_:
			current_club_difficulty = 0.5
	
	# Recalculate lie-based difficulty with new club
	if not current_lie_info.is_empty():
		# Re-run lie calculations with current club
		var lie_name = current_lie_info.get("lie_name", "FAIRWAY")
		var accuracy_mod = current_lie_info.get("accuracy_mod", 0)
		var power_mod = current_lie_info.get("power_mod", 0)
		var allowed_clubs = current_lie_info.get("allowed_clubs", [])
		var club_name = _get_current_club_name()
		var club_is_appropriate = allowed_clubs.is_empty() or club_name in allowed_clubs
		
		# Base lie difficulty
		current_lie_difficulty = clamp(accuracy_mod / 2.0, 0.0, 1.0)
		
		# If club is not appropriate for the lie, increase difficulty
		if not club_is_appropriate:
			current_lie_difficulty = min(current_lie_difficulty + 0.5, 1.0)
		
		# Calculate power cap
		if power_mod <= -15:
			current_power_cap = 0.3
		elif power_mod <= -8:
			current_power_cap = 0.6
		elif power_mod <= -4:
			current_power_cap = 0.8
		else:
			current_power_cap = 1.0
		
		# Further limit power if club doesn't suit the lie
		if not club_is_appropriate:
			current_power_cap = min(current_power_cap, 0.7)
		
		# Special case: Long clubs (Driver, Woods) off fairway (not tee)
		if club_name == "DRIVER" and lie_name == "FAIRWAY":
			current_lie_difficulty = max(current_lie_difficulty, 0.4)
			current_power_cap = min(current_power_cap, 0.9)
		elif (club_name == "WOOD_3" or club_name == "WOOD_5") and lie_name == "FAIRWAY":
			current_lie_difficulty = max(current_lie_difficulty, 0.3)
			# Woods get full power off fairway - they're designed for this


func next_club() -> void:
	"""Cycle to next club"""
	select_club((selected_club + 1) % clubs.size())


func prev_club() -> void:
	"""Cycle to previous club"""
	select_club((selected_club - 1 + clubs.size()) % clubs.size())


func show_score_popup(chips: int, mult: float, final_score: int, hit_water: bool = false, hit_sand: bool = false) -> void:
	"""Display score popup after a shot"""
	total_points += final_score
	
	# Animate the persistent score display
	_animate_score_addition(final_score)
	
	if hit_water:
		score_title.text = "In the Water!"
		score_title.add_theme_color_override("font_color", Color(0.3, 0.5, 0.8))
	elif hit_sand:
		score_title.text = "In the Sand!"
		score_title.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	else:
		score_title.text = "Nice Shot!"
		score_title.add_theme_color_override("font_color", Color.WHITE)
	
	score_value.text = "+%d" % final_score
	score_details.text = "%d chips × %.1f mult" % [chips, mult]
	
	score_popup.visible = true
	
	# Auto-hide after 4 seconds (allow time for slower score animation)
	await get_tree().create_timer(4.0).timeout
	score_popup.visible = false


func _animate_score_addition(points_to_add: int) -> void:
	"""Animate the score counting up rapidly in the persistent display"""
	if not persistent_score_label:
		return
	
	# Kill any existing tween
	if score_tween and score_tween.is_valid():
		score_tween.kill()
	
	var start_score = displayed_score
	var target_score = total_points
	
	# Calculate duration based on points (slower animation)
	var duration = clamp(points_to_add / 100.0, 1.0, 3.0)
	
	score_tween = create_tween()
	score_tween.tween_method(_update_score_display, start_score, target_score, duration)


func _update_score_display(value: int) -> void:
	"""Called by tween to update the displayed score"""
	displayed_score = value
	if persistent_score_label:
		persistent_score_label.text = str(value)


func show_hole_complete(strokes: int, par: int, hole_points: int) -> void:
	"""Display hole completion popup"""
	var diff = strokes - par
	var score_name = ""
	
	# Get par bonus from run state if available
	var par_bonus = 0
	if run_state:
		par_bonus = run_state._calculate_par_bonus(diff)
		score_name = run_state.get_par_name(diff)
	else:
		match diff:
			-3: score_name = "Albatross! (-3)"
			-2: score_name = "Eagle! (-2)"
			-1: score_name = "Birdie! (-1)"
			0: score_name = "Par (E)"
			1: score_name = "Bogey (+1)"
			2: score_name = "Double Bogey (+2)"
			_:
				if diff < -3:
					score_name = "Incredible! (%d)" % diff
				else:
					score_name = "+%d" % diff
	
	# Update hole complete title with hole number
	if hole_complete_title:
		hole_complete_title.text = "Hole %d Complete!" % current_hole
	
	hole_score.text = "%s\n%d strokes" % [score_name, strokes]
	
	# Show score breakdown
	var score_text = "Hole Score: %d pts" % hole_points
	if par_bonus > 0:
		score_text += "\nPar Bonus: +%d pts" % par_bonus
	score_text += "\n\nTotal: %d pts" % total_points
	total_score.text = score_text
	
	# Update button text based on whether this is the final hole
	if run_state and run_state.is_final_hole():
		next_button.text = "Finish Round"
	else:
		next_button.text = "Next Hole"
	
	hole_complete_popup.visible = true


func hide_hole_complete() -> void:
	"""Hide the hole complete popup"""
	hole_complete_popup.visible = false


# --- Signal Handlers ---

func _on_shot_started(context: ShotContext) -> void:
	"""Called when a new shot begins"""
	# Use run_state stroke count if available, otherwise fall back to context
	var stroke_count = run_state.strokes_this_hole if run_state else context.shot_index
	update_shot_info(stroke_count, 0)
	
	# Update current terrain from ball position
	if hole_controller and context.start_tile.x >= 0:
		var terrain = hole_controller.get_cell(context.start_tile.x, context.start_tile.y)
		update_current_terrain(terrain)
	
	# Don't hide swing meter here - if user pre-aimed, we want it visible!
	# if swing_meter:
	# 	swing_meter.hide_meter()


func _on_aoe_computed(context: ShotContext) -> void:
	"""Called when player has aimed"""
	if hole_controller and context.aim_tile.x >= 0:
		var terrain = hole_controller.get_cell(context.aim_tile.x, context.aim_tile.y)
		var distance = int(context.get_shot_distance_yards())
		update_target_info(terrain, distance)


func _on_shot_completed(context: ShotContext) -> void:
	"""Called when shot finishes"""
	# Logic moved to hex_grid.gd to coordinate with ball animation
	pass


func _on_swing_completed(power: float, accuracy: float, curve_mod: float) -> void:
	"""Called when player completes the 3-click swing"""
	
	if not shot_manager:
		push_error("ShotUI: No shot_manager reference! Cannot confirm shot.")
		return
	
	# If shot not started yet, auto-start it now (player did pre-aiming)
	if not shot_manager.is_shot_in_progress:
		# We need to start the shot lifecycle first
		if hole_controller and hole_controller.has_method("force_start_shot"):
			hole_controller.force_start_shot()
		else:
			# Fallback: try to start shot directly
			var ball = hole_controller.golf_ball if hole_controller else null
			if ball:
				var ball_tile = hole_controller.world_to_grid(ball.position)
				shot_manager.start_shot(ball, ball_tile)
				
				# Also set the aim target if we have a locked cell
				if hole_controller.target_locked and hole_controller.locked_cell.x >= 0:
					var adjusted = hole_controller.get_shape_adjusted_landing(hole_controller.locked_cell)
					shot_manager.set_aim_target(adjusted)
	
	# Store swing meter results directly in context
	var ctx = shot_manager.current_context
	ctx.swing_power = power
	ctx.swing_accuracy = 1.0 - abs(accuracy)  # accuracy is offset from zone, convert to 0-1
	ctx.swing_curve = curve_mod
	
	# Now confirm the shot
	shot_manager.confirm_shot()


func _on_swing_cancelled() -> void:
	"""Called when swing is cancelled - reset to aiming"""
	# Player can click a new target or click swing meter again
	pass


func _on_next_hole_pressed() -> void:
	"""Next hole button clicked"""
	hide_hole_complete()
	# Emit signal for hex_grid to handle hole transition
	next_hole_requested.emit()


func set_hole_display(display_text: String) -> void:
	"""Set the hole progress display (e.g., 'Hole 1 of 9')"""
	if hole_progress_label:
		hole_progress_label.text = display_text
	# Also update the main hole label if no progress label
	elif hole_label:
		# Parse hole number from display text if possible
		pass  # hole_label is set by set_hole_info
