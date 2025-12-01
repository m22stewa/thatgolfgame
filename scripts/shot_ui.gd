extends Control
class_name ShotUI

## ShotUI - Visual interface for the shot system
## Connect this to ShotManager signals and hex_grid for live updates

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
@onready var score_title: Label = %ScoreTitle
@onready var score_value: Label = %ScoreValue
@onready var score_details: Label = %ScoreDetails

@onready var hole_complete_popup: PanelContainer = $HoleCompletePopup
@onready var hole_complete_title: Label = %HoleCompleteTitle
@onready var hole_score: Label = %HoleScore
@onready var total_score: Label = %TotalScore
@onready var next_button: Button = %NextButton

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
	
	# Connect button signals
	confirm_button.pressed.connect(_on_confirm_pressed)
	next_button.pressed.connect(_on_next_hole_pressed)
	
	# Initial UI state
	update_club_display()


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
	
	# Enable confirm button when target is valid
	confirm_button.disabled = (terrain_type < 0)


func update_club_display() -> void:
	"""Update club name and range display"""
	var club = clubs[selected_club]
	club_name.text = club[0]
	club_range.text = "%d-%d yds" % [club[1], club[2]]


func select_club(index: int) -> void:
	"""Change selected club"""
	selected_club = clamp(index, 0, clubs.size() - 1)
	update_club_display()


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
	
	confirm_button.disabled = true


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
		# Wait for score popup to finish
		await get_tree().create_timer(2.5).timeout
		show_hole_complete(shots_this_hole, current_par, total_points)


func _on_confirm_pressed() -> void:
	"""Confirm button clicked - trigger shot"""
	if shot_manager and shot_manager.is_shot_in_progress:
		shot_manager.confirm_shot()
		confirm_button.disabled = true


func _on_next_hole_pressed() -> void:
	"""Next hole button clicked"""
	hide_hole_complete()
	# Signal to hex_grid to generate new hole
	if hole_controller and hole_controller.has_method("_on_regenerate_button_pressed"):
		hole_controller._on_regenerate_button_pressed()
		current_hole += 1
		# Hole info will be updated when new hole generates
