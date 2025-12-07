extends Control
class_name SwingMeter

## SwingMeter - Classic 3-click golf swing interface
## 
## Layout:
## [NEGATIVE] [== ACCURACY ZONE ==] [========= 0% to 100% POWER =========]
##    hook      centered at "0"              power only (no curve)
##            affects curve + AOE
##
## Click 1: Start swing (marker at 0, moves right through power zone)
## Click 2: Set power (based on position in power zone, 0-100%)
## Click 3: Set accuracy (stop in accuracy zone = perfect, left = hook, right in power = slice)

signal swing_completed(power: float, accuracy: float, curve_mod: float)
signal swing_cancelled()

# Swing states
enum State { IDLE, POWER_PHASE, POWER_RETURN, ACCURACY_PHASE, COMPLETE }

# Configuration - can be modified by clubs/cards
@export var swing_speed: float = 300.0  # Pixels per second for power phase
@export var return_speed: float = 350.0  # Pixels per second for accuracy phase

# Layout configuration (as percentage of bar width)
# The "0" point (start of power / center of accuracy zone)
@export var zero_point: float = 0.15  # 15% from left edge is the "0" line

# Accuracy zone is centered around the zero point
@export var accuracy_zone_width: float = 0.10  # 10% of bar width

# Power cap (0.0-1.0) - clubs/lies can limit max power
var max_power: float = 1.0

# Derived positions (calculated from above)
var accuracy_zone_start: float = 0.10  # zero_point - accuracy_zone_width/2
var accuracy_zone_end: float = 0.20    # zero_point + accuracy_zone_width/2

# Node references
@onready var track: ColorRect = $Background/VBox/TrackContainer/Track
@onready var marker: ColorRect = $Background/VBox/TrackContainer/Track/Marker
@onready var power_fill: ColorRect = $Background/VBox/TrackContainer/Track/PowerFill
@onready var accuracy_fill: ColorRect = $Background/VBox/TrackContainer/Track/AccuracyFill
@onready var accuracy_zone: ColorRect = $Background/VBox/TrackContainer/Track/AccuracyZone
@onready var negative_zone: ColorRect = $Background/VBox/TrackContainer/Track/NegativeZone
@onready var power_marker: ColorRect = $Background/VBox/TrackContainer/Track/PowerMarker
@onready var state_label: Label = $Background/VBox/StateLabel
@onready var power_label: Label = $Background/VBox/HBox/PowerLabel
@onready var accuracy_label: Label = $Background/VBox/HBox/AccuracyLabel

# State
var current_state: State = State.IDLE
var marker_position: float = 0.0  # 0.0 = left edge, 1.0 = right edge
var power_value: float = 0.0  # 0.0 to 1.0 (actual power percentage)
var accuracy_value: float = 0.0  # How far from accuracy zone center
var dwell_timer: float = 0.0  # Brief pause at 100% power before returning

# Dwell time at 100% power (seconds) - gives player time to react
const POWER_DWELL_TIME: float = 0.15

# Track dimensions (set on ready)
var track_width: float = 400.0


func _ready() -> void:
	# Hide by default
	visible = false
	
	# Calculate accuracy zone boundaries from zero point
	accuracy_zone_start = zero_point - accuracy_zone_width / 2.0
	accuracy_zone_end = zero_point + accuracy_zone_width / 2.0
	
	# Get track dimensions after layout is ready
	await get_tree().process_frame
	if track:
		track_width = track.size.x
	
	# Connect gui_input on the Background panel to capture clicks
	var background = get_node_or_null("Background")
	if background:
		background.gui_input.connect(_on_background_gui_input)
	
	_reset_meter()


func _process(delta: float) -> void:
	if not visible:
		return
	
	match current_state:
		State.POWER_PHASE:
			_update_power_phase(delta)
		State.POWER_RETURN:
			_update_power_return_phase(delta)
		State.ACCURACY_PHASE:
			_update_accuracy_phase(delta)


func _gui_input(event: InputEvent) -> void:
	# This catches any clicks that make it to the root control
	_check_click_event(event)


func _on_background_gui_input(event: InputEvent) -> void:
	# This catches clicks on the Background panel
	_check_click_event(event)


func _check_click_event(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click()
		accept_event()


func _handle_click() -> void:
	match current_state:
		State.IDLE:
			_start_swing()
		State.POWER_PHASE:
			_set_power()
		State.POWER_RETURN:
			# User can still set power on the way back
			_set_power()
		State.ACCURACY_PHASE:
			_set_accuracy()


func _start_swing() -> void:
	"""Click 1: Start the swing at 0% power (at the zero point)"""
	current_state = State.POWER_PHASE
	# Start at the zero point (center of accuracy zone = 0% power)
	marker_position = zero_point
	_update_state_label("Set Power!")


func _set_power() -> void:
	"""Click 2: Lock in power based on position in power zone (zero_point to 1.0)"""
	# Calculate power as percentage of the power zone (zero_point to 1.0)
	var power_zone_size = 1.0 - zero_point
	power_value = (marker_position - zero_point) / power_zone_size
	power_value = clamp(power_value, 0.0, max_power)  # Apply power cap
	
	current_state = State.ACCURACY_PHASE
	
	# Show power marker where power was set
	if power_marker:
		power_marker.visible = true
		power_marker.position.x = marker_position * track_width - power_marker.size.x / 2.0
	
	# Keep power fill showing the locked power (from zero point to marker)
	if power_fill:
		power_fill.position.x = zero_point * track_width
		power_fill.size.x = (marker_position - zero_point) * track_width
	
	# Start accuracy fill (will shrink as marker moves left)
	if accuracy_fill:
		accuracy_fill.visible = true
		accuracy_fill.position.x = 0
		accuracy_fill.size.x = marker_position * track_width
	
	_update_power_label()
	_update_state_label("Set Accuracy!")


func _set_accuracy() -> void:
	"""Click 3: Lock in accuracy, complete swing"""
	# Calculate accuracy based on distance from the accuracy zone
	accuracy_value = _calculate_accuracy_offset()
	
	# Calculate curve modifier based on accuracy
	var curve_mod = _calculate_curve_mod(accuracy_value)
	
	current_state = State.COMPLETE
	_update_accuracy_label()
	_update_state_label("Shot Complete!")
	
	# Emit result after brief delay so player can see result
	await get_tree().create_timer(0.3).timeout
	swing_completed.emit(power_value, accuracy_value, curve_mod)
	
	# Hide after completion
	await get_tree().create_timer(0.2).timeout
	hide_meter()


func _calculate_accuracy_offset() -> float:
	"""Calculate how far the marker is from the accuracy zone (centered at zero_point).
	Returns: 0 = in zone, negative = left of zone (hook), positive = right of zone (slice)"""
	
	# If marker is in the accuracy zone, return 0
	if marker_position >= accuracy_zone_start and marker_position <= accuracy_zone_end:
		return 0.0
	
	# If marker is left of zone (past it into negative zone), return negative
	if marker_position < accuracy_zone_start:
		return marker_position - accuracy_zone_start  # Negative value
	
	# If marker is right of zone (still in power zone), return positive
	return marker_position - accuracy_zone_end  # Positive value


func _calculate_curve_mod(accuracy_offset: float) -> float:
	"""Convert accuracy offset to curve modifier for the shot.
	accuracy_offset: negative = hook/draw, positive = fade/slice, 0 = straight
	Returns: curve_mod in tiles (-6 to +6)"""
	
	# No curve if in the zone
	if accuracy_offset == 0.0:
		return 0.0
	
	# Scale offset to curve tiles
	# Max curve at extremes = +/- 6 tiles (very drastic hook/slice)
	var max_curve = 6.0
	
	var curve = 0.0
	if accuracy_offset < 0:
		# Hook/Draw - missed left (past the zone into negative zone)
		# Marker is between 0 and accuracy_zone_start
		# Max hook when marker is at 0
		curve = (accuracy_offset / accuracy_zone_start) * max_curve
	else:
		# Fade/Slice - stopped too early (still in power zone)
		# This is less common since marker moves left during accuracy phase
		var range_right = 1.0 - accuracy_zone_end
		curve = (accuracy_offset / range_right) * max_curve
	
	return clamp(curve, -max_curve, max_curve)


func _update_power_phase(delta: float) -> void:
	"""Move marker from zero point to right through power zone (0% to 100%)"""
	marker_position += (swing_speed / track_width) * delta
	
	# Clamp to track bounds
	if marker_position > 1.0:
		marker_position = 1.0
	
	# Update power fill to follow marker (from zero point to marker)
	if power_fill:
		var fill_start = zero_point * track_width
		power_fill.position.x = fill_start
		power_fill.size.x = max(0, marker_position * track_width - fill_start)
	
	# Calculate and display current power percentage
	# Power zone goes from zero_point to 1.0
	var power_zone_size = 1.0 - zero_point
	var current_power = (marker_position - zero_point) / power_zone_size
	current_power = clamp(current_power, 0.0, 1.0)
	
	# If marker reaches 100% (right edge), pause briefly then start returning
	if marker_position >= 1.0:
		dwell_timer += delta
		if dwell_timer >= POWER_DWELL_TIME:
			current_state = State.POWER_RETURN
			dwell_timer = 0.0
			_update_state_label("Set Power!")
	
	_update_marker_visual()
	if power_label:
		power_label.text = "Power: %d%%" % int(current_power * 100)


func _update_power_return_phase(delta: float) -> void:
	"""Marker returns - user can still click to set power. Only resets if they miss entirely."""
	marker_position -= (return_speed / track_width) * delta
	
	# Update power fill to follow marker back
	if power_fill:
		var fill_start = zero_point * track_width
		power_fill.position.x = fill_start
		power_fill.size.x = max(0, marker_position * track_width - fill_start)
	
	# Calculate current power for display
	var power_zone_size = 1.0 - zero_point
	var current_power = (marker_position - zero_point) / power_zone_size
	current_power = clamp(current_power, 0.0, 1.0)
	
	# If marker reaches the zero point without clicking, THAT'S a miss - reset the meter
	if marker_position <= zero_point:
		marker_position = zero_point
		_reset_meter()
	
	_update_marker_visual()
	if power_label:
		power_label.text = "Power: %d%%" % int(current_power * 100)


func _update_accuracy_phase(delta: float) -> void:
	"""Move marker from right back to left through power zone and into negative zone"""
	marker_position -= (return_speed / track_width) * delta
	
	# Update accuracy fill to show current position (shrinks as marker moves left)
	if accuracy_fill:
		accuracy_fill.size.x = max(0, marker_position * track_width)
	
	# Marker can go all the way to 0 (deep into negative/hook zone)
	if marker_position <= 0.0:
		marker_position = 0.0
		# Auto-set accuracy if they don't click (max hook)
		_set_accuracy()
	
	_update_marker_visual()
	_update_accuracy_label()


func _update_marker_visual() -> void:
	"""Update marker position on track"""
	if marker:
		var x_pos = marker_position * track_width - marker.size.x / 2.0
		marker.position.x = clamp(x_pos, 0, track_width - marker.size.x)


func _update_accuracy_zone_visual() -> void:
	"""Update accuracy zone and negative zone positions based on current settings"""
	# Negative zone: from 0 to accuracy_zone_start
	if negative_zone:
		negative_zone.position.x = 0
		negative_zone.size.x = accuracy_zone_start * track_width
	
	# Accuracy zone: from accuracy_zone_start to accuracy_zone_end
	if accuracy_zone:
		accuracy_zone.position.x = accuracy_zone_start * track_width
		accuracy_zone.size.x = (accuracy_zone_end - accuracy_zone_start) * track_width


func _update_state_label(text: String) -> void:
	if state_label:
		state_label.text = text


func _update_power_label() -> void:
	if power_label:
		# Calculate power as percentage of power zone (zero_point to 1.0)
		var power_zone_size = 1.0 - zero_point
		var current_power = (marker_position - zero_point) / power_zone_size
		current_power = clamp(current_power, 0.0, 1.0)
		power_label.text = "Power: %d%%" % int(current_power * 100)


func _update_accuracy_label() -> void:
	if accuracy_label:
		# Accuracy zone is between accuracy_zone_start and accuracy_zone_end
		# In zone = perfect, left of zone = hook/draw, right of zone = fade/slice
		if marker_position >= accuracy_zone_start and marker_position <= accuracy_zone_end:
			accuracy_label.text = "PERFECT!"
			accuracy_label.add_theme_color_override("font_color", Color.GREEN)
		elif marker_position < accuracy_zone_start:
			# Left of zone (negative zone) = hook/draw
			var depth = accuracy_zone_start - marker_position
			if depth > 0.10:
				accuracy_label.text = "HOOK ◄◄"
			else:
				accuracy_label.text = "Draw ◄"
			accuracy_label.add_theme_color_override("font_color", Color.ORANGE)
		else:
			# Right of zone (still in power area) = fade/slice
			var depth = marker_position - accuracy_zone_end
			if depth > 0.20:
				accuracy_label.text = "SLICE ►►"
			else:
				accuracy_label.text = "Fade ►"
			accuracy_label.add_theme_color_override("font_color", Color.ORANGE)


func _reset_meter() -> void:
	"""Reset meter to initial state"""
	current_state = State.IDLE
	marker_position = zero_point  # Start at the zero point (0% power)
	power_value = 0.0
	accuracy_value = 0.0
	dwell_timer = 0.0
	
	if marker:
		marker.position.x = zero_point * track_width - marker.size.x / 2.0
	if power_fill:
		power_fill.position.x = zero_point * track_width
		power_fill.size.x = 0
	if accuracy_fill:
		accuracy_fill.visible = false
		accuracy_fill.size.x = 0
	if power_marker:
		power_marker.visible = false
	
	# Update accuracy zone visual
	_update_accuracy_zone_visual()
	
	_update_state_label("Click to Swing!")
	if power_label:
		power_label.text = "Power: 0%"
	if accuracy_label:
		accuracy_label.text = ""
		accuracy_label.remove_theme_color_override("font_color")


func configure_for_shot(club_difficulty: float, lie_difficulty: float, power_cap: float = 1.0) -> void:
	"""Configure the swing meter for a specific club/lie combination.
	club_difficulty: 0.0 = easy (wedges), 1.0 = hard (driver)
	lie_difficulty: 0.0 = easy (tee/fairway), 1.0 = hard (deep rough/sand)
	power_cap: Maximum power allowed (0.0-1.0)"""
	
	# Combine difficulties (club matters more on tee, lie matters more in rough)
	var combined = club_difficulty * 0.6 + lie_difficulty * 0.4
	
	# Accuracy zone width: 15% (easy) down to 5% (hard)
	accuracy_zone_width = lerp(0.15, 0.05, combined)
	
	# Recalculate zone boundaries
	accuracy_zone_start = zero_point - accuracy_zone_width / 2.0
	accuracy_zone_end = zero_point + accuracy_zone_width / 2.0
	
	# Speed: harder shots have faster meters
	# Base: 280-380 pixels/sec depending on difficulty
	swing_speed = lerp(280.0, 380.0, combined)
	return_speed = swing_speed * 1.05  # Return slightly faster
	
	# Power cap from lie
	max_power = clamp(power_cap, 0.1, 1.0)


func show_meter(speed_multiplier: float = 1.0) -> void:
	"""Show the swing meter and prepare for input.
	speed_multiplier: Adjust speed (1.0 = normal, higher = harder)"""
	# Note: configure_for_shot should be called before show_meter to set base speeds
	# speed_multiplier is an additional multiplier on top of configured speeds
	var base_swing = swing_speed if swing_speed > 0 else 300.0
	var base_return = return_speed if return_speed > 0 else 350.0
	swing_speed = base_swing * speed_multiplier
	return_speed = base_return * speed_multiplier
	
	# Refresh track width in case layout changed
	if track:
		track_width = track.size.x
	
	_reset_meter()
	visible = true
	
	# Grab focus for input
	grab_focus()


func hide_meter() -> void:
	"""Hide the swing meter"""
	visible = false
	current_state = State.IDLE


func cancel_swing() -> void:
	"""Cancel the current swing"""
	swing_cancelled.emit()
	hide_meter()


# --- Public methods to modify accuracy zone ---

func set_accuracy_zone(start: float, end: float) -> void:
	"""Set the accuracy zone position (0.0-1.0 from left edge)"""
	accuracy_zone_start = clamp(start, 0.0, 0.9)
	accuracy_zone_end = clamp(end, accuracy_zone_start + 0.05, 1.0)
	_update_accuracy_zone_visual()


func set_accuracy_zone_width(width: float) -> void:
	"""Set accuracy zone width while keeping it centered at current position"""
	var center = (accuracy_zone_start + accuracy_zone_end) / 2.0
	var half_width = width / 2.0
	accuracy_zone_start = clamp(center - half_width, 0.0, 0.9)
	accuracy_zone_end = clamp(center + half_width, accuracy_zone_start + 0.02, 1.0)
	_update_accuracy_zone_visual()


func shift_accuracy_zone(offset: float) -> void:
	"""Shift the accuracy zone left (negative) or right (positive)"""
	var width = accuracy_zone_end - accuracy_zone_start
	accuracy_zone_start = clamp(accuracy_zone_start + offset, 0.0, 1.0 - width)
	accuracy_zone_end = accuracy_zone_start + width
	_update_accuracy_zone_visual()


# Public getters for results
func get_power() -> float:
	return power_value


func get_accuracy() -> float:
	return accuracy_value


func is_active() -> bool:
	return visible and current_state != State.IDLE and current_state != State.COMPLETE
