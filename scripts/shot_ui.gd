extends Control
class_name ShotUI

## ShotUI - Visual interface for the shot system
## Connect this to ShotManager signals and hex_grid for live updates

# Swing meter scene
const SwingMeterScene = preload("res://scenes/ui/SwingMeter.tscn")

# UI element references - set via unique names
@onready var hole_label: Label = %HoleLabel
@onready var par_label: Label = %ParLabel
@onready var yardage_label: Label = %YardageLabel
@onready var shot_label: Label = %ShotLabel
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

@onready var hole_complete_popup: PanelContainer = $HoleCompletePopup
@onready var hole_complete_title: Label = %HoleCompleteTitle
@onready var hole_score: Label = %HoleScore
@onready var total_score: Label = %TotalScore
@onready var next_button: Button = %NextButton

# Lie info panel (optional - may not exist in scene)
var lie_info_panel: PanelContainer = null
var lie_name_label: Label = null
var lie_description_label: RichTextLabel = null
var lie_modifiers_label: RichTextLabel = null

# References to game systems (set externally)
var shot_manager: ShotManager = null
var hole_controller: Node3D = null  # hex_grid reference

# Game state
var current_hole: int = 1
var current_par: int = 4
var current_yardage: int = 0
var total_points: int = 0
var shots_this_hole: int = 0

# Club data (name, min_yards, max_yards)
var clubs = [
	["Driver", 200, 280],
	["3 Wood", 180, 230],
	["5 Wood", 160, 210],
	["3 Iron", 150, 190],
	["5 Iron", 130, 170],
	["6 Iron", 120, 160],
	["7 Iron", 110, 150],
	["8 Iron", 100, 140],
	["9 Iron", 90, 130],
	["Pitching Wedge", 70, 110],
	["Sand Wedge", 50, 90],
	["Putter", 5, 30]
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
	
	# Create swing meter (positioned where confirm button was)
	_create_swing_meter()
	
	# Create lie info panel for debugging
	_create_lie_info_panel()
	
	# Initial UI state
	update_club_display()


func _create_swing_meter() -> void:
	"""Create and add the swing meter UI"""
	swing_meter = SwingMeterScene.instantiate()
	swing_meter.swing_completed.connect(_on_swing_completed)
	swing_meter.swing_cancelled.connect(_on_swing_cancelled)
	add_child(swing_meter)


func setup(p_shot_manager: ShotManager, p_hole_controller: Node3D) -> void:
	"""Connect to shot manager and hole controller"""
	shot_manager = p_shot_manager
	hole_controller = p_hole_controller
	
	if shot_manager:
		shot_manager.shot_started.connect(_on_shot_started)
		shot_manager.aoe_computed.connect(_on_aoe_computed)
		shot_manager.shot_completed.connect(_on_shot_completed)


func set_hole_info(hole: int, par: int, yardage: int) -> void:
	"""Update hole information display"""
	current_hole = hole
	current_par = par
	current_yardage = yardage
	shots_this_hole = 0
	
	hole_label.text = "Hole %d" % hole
	par_label.text = "Par %d" % par
	yardage_label.text = "%d yds" % yardage


func update_shot_info(shot_num: int, distance_to_flag: int) -> void:
	"""Update shot counter and distance"""
	shots_this_hole = shot_num
	shot_label.text = "Shot %d" % shot_num
	distance_label.text = "%d yds to flag" % distance_to_flag


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
	
	# Show swing meter when target is valid (replaces confirm button)
	if terrain_type >= 0 and swing_meter and not swing_meter.visible:
		# Configure swing meter for current club/lie
		swing_meter.configure_for_shot(current_club_difficulty, current_lie_difficulty, current_power_cap)
		swing_meter.show_meter(1.0)


func update_club_display() -> void:
	"""Update club name and range display"""
	var club = clubs[selected_club]
	club_name.text = club[0]
	club_range.text = "%d-%d yds" % [club[1], club[2]]
	_update_club_difficulty()


func _create_lie_info_panel() -> void:
	"""Create a debug panel to show lie information"""
	lie_info_panel = PanelContainer.new()
	lie_info_panel.name = "LieInfoPanel"
	
	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_color = Color(0.3, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	lie_info_panel.add_theme_stylebox_override("panel", style)
	
	# Position in top-left area
	lie_info_panel.position = Vector2(20, 350)
	lie_info_panel.size = Vector2(200, 180)
	
	# Create content container
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	lie_info_panel.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "LIE INFO"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	vbox.add_child(title)
	
	# Lie name
	lie_name_label = Label.new()
	lie_name_label.text = "---"
	lie_name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(lie_name_label)
	
	# Description
	lie_description_label = RichTextLabel.new()
	lie_description_label.bbcode_enabled = true
	lie_description_label.fit_content = true
	lie_description_label.custom_minimum_size = Vector2(180, 30)
	lie_description_label.add_theme_font_size_override("normal_font_size", 11)
	vbox.add_child(lie_description_label)
	
	# Modifiers
	lie_modifiers_label = RichTextLabel.new()
	lie_modifiers_label.bbcode_enabled = true
	lie_modifiers_label.fit_content = true
	lie_modifiers_label.custom_minimum_size = Vector2(180, 80)
	lie_modifiers_label.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(lie_modifiers_label)
	
	add_child(lie_info_panel)


func update_lie_info(lie_info: Dictionary) -> void:
	"""Update the lie info debug panel and calculate difficulty for swing meter"""
	
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
		print("Club %s not ideal for %s - increased difficulty" % [club_name, lie_name])
	
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
		print("Power capped at %.0f%% for inappropriate club/lie" % (current_power_cap * 100))
	
	# Special case: Driver off fairway (not tee) should be harder
	if club_name == "DRIVER" and lie_name == "FAIRWAY":
		current_lie_difficulty = max(current_lie_difficulty, 0.4)  # At least medium difficulty
		current_power_cap = min(current_power_cap, 0.9)  # Slight power limit
	
	if lie_info_panel == null:
		return
	
	# Update lie name with color
	var lie_color = lie_info.get("color", Color.WHITE)
	lie_name_label.text = lie_info.get("display_name", "Unknown")
	lie_name_label.add_theme_color_override("font_color", lie_color)
	
	# Update description
	lie_description_label.text = "[i]%s[/i]" % lie_info.get("description", "")
	
	# Build modifiers text
	var mods = []
	var spin_mod = lie_info.get("spin_mod", 0.0)
	var curve_mod = lie_info.get("curve_mod", 0.0)
	var roll_mod = lie_info.get("roll_mod", 0)
	
	# Color code based on good/bad
	mods.append(_format_modifier_additive("Distance", power_mod, true))
	mods.append(_format_modifier_additive("Accuracy", accuracy_mod, false))
	mods.append(_format_modifier_additive("Spin", spin_mod, true))
	mods.append(_format_modifier_additive("Curve", curve_mod, true))
	mods.append(_format_modifier_additive("Roll", roll_mod, true))
	
	# Add chip/mult bonuses
	var chip_bonus = lie_info.get("chip_bonus", 0)
	if chip_bonus != 0:
		var color = "green" if chip_bonus > 0 else "red"
		mods.append("[color=%s]Chips: %s%d[/color]" % [color, "+" if chip_bonus > 0 else "", chip_bonus])
	
	var mult_bonus = lie_info.get("mult_bonus", 0.0)
	if mult_bonus != 0.0:
		var color = "green" if mult_bonus > 0 else "red"
		mods.append("[color=%s]Mult: %s%.1f[/color]" % [color, "+" if mult_bonus > 0 else "", mult_bonus])
	
	lie_modifiers_label.text = "\n".join(mods)


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
		
		# Special case: Driver off fairway
		if club_name == "DRIVER" and lie_name == "FAIRWAY":
			current_lie_difficulty = max(current_lie_difficulty, 0.4)
			current_power_cap = min(current_power_cap, 0.9)


func next_club() -> void:
	"""Cycle to next club"""
	select_club((selected_club + 1) % clubs.size())


func prev_club() -> void:
	"""Cycle to previous club"""
	select_club((selected_club - 1 + clubs.size()) % clubs.size())


func show_score_popup(chips: int, mult: float, final_score: int, hit_water: bool = false, hit_sand: bool = false) -> void:
	"""Display score popup after a shot"""
	total_points += final_score
	
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
	
	# Auto-hide after 2 seconds
	await get_tree().create_timer(2.0).timeout
	score_popup.visible = false


func show_hole_complete(strokes: int, par: int, hole_points: int) -> void:
	"""Display hole completion popup"""
	var diff = strokes - par
	var score_name = ""
	
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
	
	hole_score.text = score_name
	total_score.text = "Total: %d pts" % total_points
	
	hole_complete_popup.visible = true


func hide_hole_complete() -> void:
	"""Hide the hole complete popup"""
	hole_complete_popup.visible = false


# --- Signal Handlers ---

func _on_shot_started(context: ShotContext) -> void:
	"""Called when a new shot begins"""
	update_shot_info(context.shot_index, 0)
	
	# Update current terrain from ball position
	if hole_controller and context.start_tile.x >= 0:
		var terrain = hole_controller.get_cell(context.start_tile.x, context.start_tile.y)
		update_current_terrain(terrain)
	
	# Hide swing meter until target is selected
	if swing_meter:
		swing_meter.hide_meter()


func _on_aoe_computed(context: ShotContext) -> void:
	"""Called when player has aimed"""
	if hole_controller and context.aim_tile.x >= 0:
		var terrain = hole_controller.get_cell(context.aim_tile.x, context.aim_tile.y)
		var distance = int(context.get_shot_distance_yards())
		update_target_info(terrain, distance)


func _on_shot_completed(context: ShotContext) -> void:
	"""Called when shot finishes"""
	var hit_water = context.has_metadata("hit_water")
	var hit_sand = context.has_metadata("hit_sand")
	
	show_score_popup(context.chips, context.mult, context.final_score, hit_water, hit_sand)
	
	# Check for hole complete
	if context.has_metadata("reached_flag"):
		# Wait for score popup to finish (reduced from 2.5s)
		await get_tree().create_timer(1.0).timeout
		show_hole_complete(shots_this_hole, current_par, total_points)


func _on_swing_completed(power: float, accuracy: float, curve_mod: float) -> void:
	"""Called when player completes the 3-click swing"""
	print("Swing completed: Power=%.0f%%, Accuracy=%.2f, Curve=%.1f" % [power * 100, accuracy, curve_mod])
	
	if not shot_manager:
		push_error("ShotUI: No shot_manager reference! Cannot confirm shot.")
		return
	
	if not shot_manager.is_shot_in_progress:
		push_warning("ShotUI: No shot in progress - cannot confirm")
		return
	
	# Store swing meter results directly in context
	var ctx = shot_manager.current_context
	ctx.swing_power = power
	ctx.swing_accuracy = 1.0 - abs(accuracy)  # accuracy is offset from zone, convert to 0-1
	ctx.swing_curve = curve_mod
	
	print("Swing values stored: power=%.0f%%, accuracy=%.0f%%, curve=%+.1f" % [
		ctx.swing_power * 100, ctx.swing_accuracy * 100, ctx.swing_curve
	])
	
	# Now confirm the shot
	shot_manager.confirm_shot()


func _on_swing_cancelled() -> void:
	"""Called when swing is cancelled - reset to aiming"""
	# Player can click a new target or click swing meter again
	pass


func _on_next_hole_pressed() -> void:
	"""Next hole button clicked"""
	hide_hole_complete()
	# Signal to hex_grid to generate new hole
	if hole_controller and hole_controller.has_method("_on_regenerate_button_pressed"):
		hole_controller._on_regenerate_button_pressed()
		current_hole += 1
		# Hole info will be updated when new hole generates
