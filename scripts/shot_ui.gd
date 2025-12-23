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

var spin_meter: SpinMeter = null  # Spin meter to confirm shot and set spin (found in parent/main_ui)
var _spin_meter_retry_queued: bool = false
@onready var score_popup: PanelContainer = $ScorePopup

# Shot prerequisite tracking
var tile_selected: bool = false       # Player has locked a target tile
var swing_card_selected: bool = false # Player picked a card from swing deck
var modifier_drawn: bool = false      # Player drew from modifier deck (or skipped)

# Legacy swing meter (deprecated but kept for compatibility)
var swing_meter: SwingMeter = null

# Current shot difficulty (for display)
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

# NEW: References to new managers
var tempo_manager = null  # TempoManager
var scoring_manager = null  # ScoringManager
var modifier_deck_manager = null  # ModifierDeckManager
var game_flow_manager = null  # GameFlowManager

# NEW: Dynamic UI labels for new systems (created at runtime)
var tempo_label: Label = null
var multiplier_label: Label = null
var streak_label: Label = null
var deck_count_label: Label = null
var modifier_display_label: RichTextLabel = null

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
	
	# Find and wire the spin meter (it may live in the parent MainUI scene)
	_setup_spin_meter()
	
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


func _setup_spin_meter() -> void:
	"""Find an existing SpinMeter in the parent (MainUI) and connect its signals.
	We keep this scene-driven: the meter is placed in a .tscn, and ShotUI only wires it."""
	# Try to find a uniquely-named node inside this scene first (for compatibility)
	spin_meter = get_node_or_null("%SpinMeter") as SpinMeter
	
	# Prefer the meter instance the user placed in MainUI
	if not spin_meter:
		var parent := get_parent()
		if parent:
			# Unique-name lookup must be done from the owning scene (MainUI), not from inside ShotUI's instanced scene.
			spin_meter = parent.get_node_or_null("%SpinMeter") as SpinMeter
			if not spin_meter:
				spin_meter = parent.get_node_or_null("SpinMeter") as SpinMeter
			if not spin_meter:
				spin_meter = parent.get_node_or_null("SpinMeterPanel/SpinMeter") as SpinMeter
			if not spin_meter:
				spin_meter = parent.find_child("SpinMeter", true, false) as SpinMeter

	if not spin_meter:
		# One deferred retry helps if ShotUI _ready runs before MainUI finished instancing children.
		if not _spin_meter_retry_queued:
			_spin_meter_retry_queued = true
			call_deferred("_setup_spin_meter")
			return
		push_warning("[ShotUI] SpinMeter not found. Ensure MainUI has a SpinMeter node (unique name %SpinMeter or node name SpinMeter).")
		return
	
	spin_meter.visible = true
	spin_meter.set_disabled(true)
	if not spin_meter.spin_confirmed.is_connected(_on_spin_confirmed):
		spin_meter.spin_confirmed.connect(_on_spin_confirmed)
	if spin_meter.has_signal("cancelled") and not spin_meter.cancelled.is_connected(_on_swing_cancelled):
		# Treat cancel as backing out of the shot confirmation flow
		spin_meter.cancelled.connect(_on_swing_cancelled)


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


# --- Swing Button Prerequisites ---

# Set to true to bypass card selection requirements (for testing or simplified mode)
@export var bypass_card_selection: bool = true

func reset_shot_prerequisites() -> void:
	"""Reset all prerequisites for a new shot"""
	tile_selected = false
	# If bypassing cards, auto-set to true
	swing_card_selected = bypass_card_selection
	modifier_drawn = bypass_card_selection
	_update_swing_button_state()


func set_tile_selected(selected: bool) -> void:
	"""Called when player locks/unlocks a target tile"""
	print("[ShotUI] set_tile_selected(%s)" % selected)
	tile_selected = selected
	_update_swing_button_state()


func set_swing_card_selected(selected: bool) -> void:
	"""Called when player picks a card from the swing deck"""
	print("[ShotUI] set_swing_card_selected(%s)" % selected)
	swing_card_selected = selected
	_update_swing_button_state()


func set_modifier_drawn(drawn: bool) -> void:
	"""Called when player draws from modifier deck (or skips)"""
	print("[ShotUI] set_modifier_drawn(%s)" % drawn)
	modifier_drawn = drawn
	_update_swing_button_state()


func _update_swing_button_state() -> void:
	"""Enable spin meter.
	The game no longer requires tile/swing/modifier prerequisites to take a shot."""
	if spin_meter:
		spin_meter.set_disabled(false)
	else:
		# Spin meter may not be ready yet; _setup_spin_meter() does a deferred retry.
		return


func _on_spin_confirmed(spin_value: int) -> void:
	"""Called when player releases the spin meter"""
	print("[ShotUI] Spin confirmed with value: %d" % spin_value)
	
	# Pass spin value to swing completion - it will be applied after shot starts
	_on_swing_completed_with_spin(spin_value)


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
	# Display shows how many strokes have been taken (starts at 0 for tee shot)
	_update_shot_counter_visuals(strokes_taken)
	if distance_label:
		distance_label.text = "%d yds to flag" % distance_to_flag


func _update_shot_counter_visuals(strokes_taken: int) -> void:
	if not shot_numbers: return
	
	# Clear existing
	for child in shot_numbers.get_children():
		child.queue_free()
	
	# Determine range (e.g. up to Par + 2, or strokes taken if higher)
	var max_display = max(current_par + 2, strokes_taken + 2)
	if max_display < 5: max_display = 5 # Minimum 5
	
	for i in range(1, max_display + 1):
		var shot_node = ShotNumberScene.instantiate()
		shot_numbers.add_child(shot_node)
		shot_node.set_number(i)
		
		# strokes_taken = how many shots have been completed
		# Don't show "current" until tee shot is taken (strokes_taken > 0)
		if i <= strokes_taken:
			shot_node.set_state("past")  # Already taken
		elif strokes_taken > 0 and i == strokes_taken + 1:
			shot_node.set_state("current")  # Next shot to take (only after tee shot)
		else:
			shot_node.set_state("future")


func update_current_terrain(terrain_type: int) -> void:
	"""Update the terrain display for ball's current position"""
	current_terrain.text = terrain_names.get(terrain_type, "Unknown")
	var effect = terrain_effects.get(terrain_type, ["", Color.WHITE])
	terrain_effect.text = effect[0]
	terrain_effect.add_theme_color_override("font_color", effect[1])


func update_target_info(terrain_type: int, distance: int) -> void:
	"""Update target terrain and distance, and track tile selection"""
	target_terrain.text = terrain_names.get(terrain_type, "---")
	target_distance.text = "%d yds" % distance
	
	# Track tile selection state
	var valid_target = terrain_type >= 0
	set_tile_selected(valid_target)


func update_club_display() -> void:
	"""Update club name and range display"""
	var club = clubs[selected_club]
	club_name.text = club[0]
	club_range.text = "%d-%d yds" % [club[1], club[2]]


func set_putting_club(tile_distance: int) -> void:
	"""Set club display for putting mode"""
	club_name.text = "Putter"
	club_range.text = "%d tiles" % tile_distance


func update_lie_info(lie_info: Dictionary) -> void:
	"""Update UI with lie information"""
	
	# Store lie info for reference
	current_lie_info = lie_info
	
	# Get lie info
	var lie_name = lie_info.get("lie_name", "FAIRWAY")
	var accuracy_mod = lie_info.get("accuracy_mod", 0)
	var distance_mod = lie_info.get("distance_mod", 0)
	
	# Calculate lie difficulty for display (0.0 = easy, 1.0 = hard)
	# Based on accuracy_mod: 0 = easy, 2+ = hard
	current_lie_difficulty = clamp(accuracy_mod / 2.0, 0.0, 1.0)
	
	# Check if current club is appropriate for this lie
	var allowed_clubs = lie_info.get("allowed_clubs", [])
	var club_name = _get_current_club_name()
	var club_is_appropriate = allowed_clubs.is_empty() or club_name in allowed_clubs
	
	# If club is not appropriate for the lie, increase difficulty display
	if not club_is_appropriate:
		current_lie_difficulty = min(current_lie_difficulty + 0.5, 1.0)


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
		var distance_mod = current_lie_info.get("distance_mod", 0)
		var allowed_clubs = current_lie_info.get("allowed_clubs", [])
		var club_name = _get_current_club_name()
		var club_is_appropriate = allowed_clubs.is_empty() or club_name in allowed_clubs
		
		# Base lie difficulty
		current_lie_difficulty = clamp(accuracy_mod / 2.0, 0.0, 1.0)
		
		# If club is not appropriate for the lie, increase difficulty
		if not club_is_appropriate:
			current_lie_difficulty = min(current_lie_difficulty + 0.5, 1.0)
	
	# Update spin meter oscillation speed based on club difficulty
	if spin_meter:
		spin_meter.set_club_difficulty(current_club_difficulty)


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
	
	# Show score breakdown with new scoring info
	var score_text = "Hole Score: %d pts" % hole_points
	
	# Add scoring manager breakdown if available
	if scoring_manager:
		var fairways = scoring_manager.get_consecutive_fairways()
		if fairways > 0:
			score_text += "\nFairway Streak: %d" % fairways
		var multiplier = scoring_manager.get_current_multiplier()
		if multiplier > 1.0:
			score_text += "\nMultiplier: %.1fx" % multiplier
	
	if par_bonus > 0:
		score_text += "\n\n%s Bonus: +%d pts" % [score_name.split("!")[0].strip_edges(), par_bonus]
	
	# Add coins collected if run_state tracks it
	if run_state:
		var coins = run_state.get_coins_this_hole()
		if coins > 0:
			score_text += "\nCoins: +%d" % coins
	
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
	# Reset prerequisites for the new shot
	reset_shot_prerequisites()
	
	# Use run_state stroke count if available, otherwise fall back to context
	var stroke_count = run_state.strokes_this_hole if run_state else context.shot_index
	update_shot_info(stroke_count, 0)
	
	# Update current terrain from ball position
	if hole_controller and context.start_tile.x >= 0:
		var terrain = hole_controller.get_cell(context.start_tile.x, context.start_tile.y)
		update_current_terrain(terrain)


func _on_aoe_computed(context: ShotContext) -> void:
	"""Called when player has aimed"""
	if hole_controller and context.aim_tile.x >= 0:
		var terrain = hole_controller.get_cell(context.aim_tile.x, context.aim_tile.y)
		var distance = int(context.get_shot_distance_yards())
		update_target_info(terrain, distance)


func _on_shot_completed(context: ShotContext) -> void:
	"""Called when shot finishes"""
	# Reset prerequisites for the next shot
	reset_shot_prerequisites()


func _on_swing_completed_with_spin(spin_value: int) -> void:
	"""Called when player completes the swing with spin value from meter."""
	if not shot_manager:
		push_error("[ShotUI] No shot_manager reference! Cannot confirm shot.")
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
	
	# Apply spin value to roll_mod AFTER shot started (modifiers already applied)
	if shot_manager.current_context:
		shot_manager.current_context.roll_mod += spin_value
		print("[ShotUI] Applied spin to roll_mod, new value: %d" % shot_manager.current_context.roll_mod)
	
	# Now confirm the shot
	shot_manager.confirm_shot()


func _on_swing_completed(power: float, accuracy: float, curve_mod: float) -> void:
	"""Called when player completes the swing.
	With new system, swing button just confirms shot - accuracy is determined by stats.
	Power/accuracy/curve_mod params kept for backwards compatibility but not used."""
	# Delegate to the new function with no spin
	_on_swing_completed_with_spin(0)


func _on_swing_cancelled() -> void:
	"""Called when swing is cancelled - reset to aiming"""
	# Player can click a new target or click swing meter again
	pass


func _on_next_hole_pressed() -> void:
	"""Next hole button clicked"""
	hide_hole_complete()
	next_hole_requested.emit()


# --- NEW: Tempo/Scoring/Modifier System UI ---

func setup_new_managers(tempo: Node, scoring: Node, modifier_deck: Node, game_flow: Node) -> void:
	"""Connect to new game systems"""
	tempo_manager = tempo
	scoring_manager = scoring
	modifier_deck_manager = modifier_deck
	game_flow_manager = game_flow
	
	# Connect signals
	if tempo_manager and tempo_manager.has_signal("tempo_changed"):
		tempo_manager.tempo_changed.connect(_on_tempo_changed)
	
	if scoring_manager:
		if scoring_manager.has_signal("multiplier_changed"):
			scoring_manager.multiplier_changed.connect(_on_multiplier_changed)
		if scoring_manager.has_signal("streak_changed"):
			scoring_manager.streak_changed.connect(_on_streak_changed)
		if scoring_manager.has_signal("points_awarded"):
			scoring_manager.points_awarded.connect(_on_points_awarded)
		if scoring_manager.has_signal("golf_bonus_awarded"):
			scoring_manager.golf_bonus_awarded.connect(_on_golf_bonus_awarded)
	
	if modifier_deck_manager and modifier_deck_manager.has_signal("deck_size_changed"):
		modifier_deck_manager.deck_size_changed.connect(_on_deck_size_changed)
	
	if game_flow_manager and game_flow_manager.has_signal("modifier_flipped"):
		game_flow_manager.modifier_flipped.connect(_on_modifier_flipped)
	
	# Create UI elements
	_create_new_system_ui()


func _create_new_system_ui() -> void:
	"""Create UI elements for tempo, multiplier, streak, and deck counts"""
	# Find or create a container for these elements
	var info_container = get_node_or_null("TopBar/InfoContainer")
	if not info_container:
		# Try to find TopBar
		var top_bar = get_node_or_null("TopBar")
		if top_bar:
			info_container = HBoxContainer.new()
			info_container.name = "InfoContainer"
			info_container.add_theme_constant_override("separation", 20)
			top_bar.add_child(info_container)
	
	if not info_container:
		# Create at root level
		info_container = HBoxContainer.new()
		info_container.name = "InfoContainer"
		info_container.add_theme_constant_override("separation", 20)
		info_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		info_container.position = Vector2(800, 10)
		add_child(info_container)
	
	# Tempo display
	tempo_label = Label.new()
	tempo_label.name = "TempoLabel"
	tempo_label.text = "⚡ 2/2"
	tempo_label.add_theme_font_size_override("font_size", 18)
	tempo_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	info_container.add_child(tempo_label)
	
	# Multiplier display
	multiplier_label = Label.new()
	multiplier_label.name = "MultiplierLabel"
	multiplier_label.text = "🎯 1.0x"
	multiplier_label.add_theme_font_size_override("font_size", 18)
	multiplier_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	info_container.add_child(multiplier_label)
	
	# Streak display
	streak_label = Label.new()
	streak_label.name = "StreakLabel"
	streak_label.text = "🔥 0"
	streak_label.add_theme_font_size_override("font_size", 18)
	streak_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	streak_label.visible = false  # Hidden until streak starts
	info_container.add_child(streak_label)
	
	# Deck count display
	deck_count_label = Label.new()
	deck_count_label.name = "DeckCountLabel"
	deck_count_label.text = "🃏 20/0"
	deck_count_label.add_theme_font_size_override("font_size", 16)
	deck_count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	info_container.add_child(deck_count_label)
	
	# Modifier display (shows last drawn modifier)
	modifier_display_label = RichTextLabel.new()
	modifier_display_label.name = "ModifierDisplay"
	modifier_display_label.bbcode_enabled = true
	modifier_display_label.fit_content = true
	modifier_display_label.custom_minimum_size = Vector2(150, 30)
	modifier_display_label.text = ""
	info_container.add_child(modifier_display_label)


func _on_tempo_changed(current: int, max_tempo: int) -> void:
	"""Update tempo display"""
	if tempo_label:
		tempo_label.text = "⚡ %d/%d" % [current, max_tempo]
		# Color based on remaining tempo
		if current == 0:
			tempo_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		elif current <= max_tempo / 2:
			tempo_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		else:
			tempo_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))


func _on_multiplier_changed(new_multiplier: float) -> void:
	"""Update multiplier display"""
	if multiplier_label:
		multiplier_label.text = "🎯 %.1fx" % new_multiplier
		# Color based on multiplier value
		if new_multiplier >= 2.0:
			multiplier_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
		elif new_multiplier >= 1.5:
			multiplier_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.3))
		else:
			multiplier_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))


func _on_streak_changed(streak_count: int) -> void:
	"""Update streak display"""
	if streak_label:
		streak_label.text = "🔥 %d" % streak_count
		streak_label.visible = streak_count > 0
		# Animate on streak increase
		if streak_count >= 3:
			streak_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.1))
		elif streak_count >= 2:
			streak_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		else:
			streak_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))


func _on_deck_size_changed(draw_size: int, discard_size: int) -> void:
	"""Update modifier deck count display"""
	if deck_count_label:
		deck_count_label.text = "🃏 %d/%d" % [draw_size, discard_size]


func _on_modifier_flipped(card) -> void:
	"""Display the flipped modifier card"""
	if modifier_display_label and card:
		modifier_display_label.text = card.get_display_text() if card.has_method("get_display_text") else "[Modifier]"


func _on_points_awarded(points: int, reason: String, multiplier: float) -> void:
	"""Show points popup when points are awarded"""
	_show_points_popup(points, reason)


func _on_golf_bonus_awarded(bonus_name: String, bonus_points: int) -> void:
	"""Show golf bonus achievement"""
	_show_golf_bonus_popup(bonus_name, bonus_points)


func _show_points_popup(points: int, reason: String) -> void:
	"""Show a floating points indicator"""
	var popup = Label.new()
	popup.text = "+%d" % points if points >= 0 else "%d" % points
	popup.add_theme_font_size_override("font_size", 24)
	
	if points > 0:
		popup.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		popup.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	
	popup.position = Vector2(get_viewport().size.x / 2 - 50, get_viewport().size.y / 2)
	add_child(popup)
	
	# Animate and remove
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 50, 1.0)
	tween.tween_property(popup, "modulate:a", 0.0, 1.0)
	tween.set_parallel(false)
	tween.tween_callback(popup.queue_free)


func _show_golf_bonus_popup(bonus_name: String, bonus_points: int) -> void:
	"""Show a prominent golf bonus achievement"""
	var popup = Label.new()
	popup.text = "%s +%d" % [bonus_name, bonus_points]
	popup.add_theme_font_size_override("font_size", 36)
	popup.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.position = Vector2(get_viewport().size.x / 2 - 100, get_viewport().size.y / 2 - 50)
	add_child(popup)
	
	# Animate with scale and fade
	popup.scale = Vector2(0.5, 0.5)
	var tween = create_tween()
	tween.tween_property(popup, "scale", Vector2(1.2, 1.2), 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.2)
	tween.tween_interval(1.0)
	tween.tween_property(popup, "modulate:a", 0.0, 0.5)
	tween.tween_callback(popup.queue_free)
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
