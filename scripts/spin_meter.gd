extends Control
class_name SpinMeter

## SpinMeter - A golf ball button with vertical spin selector
## Press and hold to activate, release to set spin value (-3 to +3)
## Oscillation speed varies by club (slower for Driver, faster for Wedges)

signal spin_confirmed(spin_value: int)
signal cancelled()

# UI Elements
@onready var ball_button: TextureRect = %BallButton
@onready var meter_panel: Panel = %MeterPanel
@onready var meter_marker: ColorRect = %MeterMarker
@onready var meter_track: ColorRect = %MeterTrack
@onready var spin_label: Label = %SpinLabel
@onready var top_label: Label = %TopLabel
@onready var bottom_label: Label = %BottomLabel
@onready var center_line: ColorRect = %CenterLine

# State
var is_active: bool = false
var is_oscillating: bool = false
var oscillation_position: float = 0.0  # -1.0 to 1.0 (maps to -3 to +3)
var oscillation_direction: int = 1  # 1 = going up, -1 = going down
var base_speed: float = 3.0  # Base oscillation speed

# Club difficulty affects oscillation speed
# 0.0 = easy (wedges), 1.0 = hard (driver)
var club_difficulty: float = 0.5

# Calculated speed based on club
var current_speed: float = 3.0

# Disabled state
var is_disabled: bool = true


func _ready() -> void:
	# Keep meter panel always visible
	if meter_panel:
		meter_panel.visible = true
	
	# Connect ball button signals
	if ball_button:
		ball_button.gui_input.connect(_on_ball_button_input)
	
	update_meter_display()
	_update_visual_state()


func _process(delta: float) -> void:
	if is_oscillating and not is_disabled:
		# Oscillate the marker up and down
		oscillation_position += oscillation_direction * current_speed * delta
		
		# Bounce at limits
		if oscillation_position >= 1.0:
			oscillation_position = 1.0
			oscillation_direction = -1
		elif oscillation_position <= -1.0:
			oscillation_position = -1.0
			oscillation_direction = 1
		
		update_meter_display()


func _on_ball_button_input(event: InputEvent) -> void:
	if is_disabled:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start oscillating
				start_oscillation()
			else:
				# Stop and confirm
				stop_oscillation()


func start_oscillation() -> void:
	"""Start the spin meter oscillation"""
	if is_disabled:
		return
		
	is_oscillating = true
	is_active = true
	oscillation_position = 0.0
	oscillation_direction = 1
	
	# Calculate speed based on club difficulty
	# Driver (1.0) = slower (easier to hit spin), Wedges (0.0) = faster
	# Range: 2.0 (slowest for driver) to 5.0 (fastest for wedges)
	current_speed = lerp(4.5, 2.0, club_difficulty)
	
	# Meter panel stays visible; oscillation just animates the marker
	
	update_meter_display()


func stop_oscillation() -> void:
	"""Stop oscillation and confirm the spin value"""
	is_oscillating = false
	is_active = false
	
	# Calculate spin value from position (-1.0 to 1.0 → -3 to +3)
	var spin_value = int(round(oscillation_position * 3.0))
	
	# Meter panel stays visible
	
	# Emit the confirmed spin value
	spin_confirmed.emit(spin_value)


func cancel() -> void:
	"""Cancel the spin meter without confirming"""
	is_oscillating = false
	is_active = false
	oscillation_position = 0.0
	
	# Meter panel stays visible
	
	cancelled.emit()


func update_meter_display() -> void:
	"""Update the visual position of the meter marker"""
	if not meter_marker or not meter_track:
		return
	
	# Calculate marker position within the track
	# oscillation_position: -1.0 (bottom/backspin) to 1.0 (top/topspin)
	# Map to 0.0 (bottom) to 1.0 (top) of track
	var normalized = (oscillation_position + 1.0) / 2.0  # 0.0 to 1.0
	
	var track_height = meter_track.size.y
	var marker_height = meter_marker.size.y
	var usable_height = track_height - marker_height
	
	# Position marker within track bounds (inverted because Y grows down in UI)
	# Track is centered at anchor 0.5,0.5 so we need to position relative to that
	var track_top = meter_track.position.y
	meter_marker.position.y = track_top + (1.0 - normalized) * usable_height
	meter_marker.position.x = meter_track.position.x + (meter_track.size.x - meter_marker.size.x) / 2.0
	
	# Update spin label with current value
	var spin_value = int(round(oscillation_position * 3.0))
	if spin_label:
		if spin_value > 0:
			spin_label.text = "Top +%d" % spin_value
			spin_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))  # Green
		elif spin_value < 0:
			spin_label.text = "Back %d" % spin_value
			spin_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))  # Red
		else:
			spin_label.text = "Neutral"
			spin_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))  # White


func set_club_difficulty(difficulty: float) -> void:
	"""Set the club difficulty (0.0 = easy/wedges, 1.0 = hard/driver)
	This affects the oscillation speed."""
	club_difficulty = clamp(difficulty, 0.0, 1.0)


func set_disabled(disabled: bool) -> void:
	"""Enable or disable the spin meter"""
	is_disabled = disabled
	
	if is_disabled and is_oscillating:
		cancel()
	
	_update_visual_state()


func _update_visual_state() -> void:
	"""Update visual appearance based on enabled/disabled state"""
	if ball_button:
		if is_disabled:
			ball_button.modulate = Color(0.5, 0.5, 0.5, 0.7)
		else:
			ball_button.modulate = Color(1, 1, 1, 1)


func get_spin_value() -> int:
	"""Get the current spin value based on oscillation position"""
	return int(round(oscillation_position * 3.0))
