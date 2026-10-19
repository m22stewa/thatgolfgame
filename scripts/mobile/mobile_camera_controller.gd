extends Camera3D
class_name MobileCameraController

@export var pan_speed: float = 0.08
@export var zoom_speed: float = 0.03
@export var min_distance: float = 15.0
@export var max_distance: float = 120.0
@export var min_pitch: float = 15.0  # Degrees - more horizontal
@export var max_pitch: float = 75.0  # Degrees - more top-down

# Camera orbit state
var _target: Vector3 = Vector3.ZERO
var _distance: float = 50.0
var _yaw: float = 0.0  # Rotation around Y axis
var _pitch: float = 45.0  # Angle from horizontal

# Mouse drag
var _is_mouse_panning: bool = false
var _mouse_last: Vector2 = Vector2.ZERO

# Touch
var _touch_points: Dictionary = {}
var _pinch_last_dist: float = -1.0

func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = 50.0


func set_target(pos: Vector3) -> void:
	_target = pos
	_update_camera()


func set_look_direction(from_pos: Vector3, to_pos: Vector3) -> void:
	# Focus on the CENTER of the hole, not the tee
	_target = (from_pos + to_pos) * 0.5
	var dir := to_pos - from_pos
	_yaw = rad_to_deg(atan2(dir.x, dir.z))
	# Set distance based on hole length to fit entire course in view
	var hole_length := dir.length()
	_distance = clampf(hole_length * 0.8, min_distance, max_distance)
	_update_camera()


func _update_camera() -> void:
	var pitch_rad := deg_to_rad(_pitch)
	var yaw_rad := deg_to_rad(_yaw)
	
	# Spherical coordinates
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad) * _distance,
		sin(pitch_rad) * _distance,
		cos(yaw_rad) * cos(pitch_rad) * _distance
	)
	
	global_position = _target + offset
	look_at(_target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse (desktop testing)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_mouse_panning = mb.pressed
			_mouse_last = mb.position
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(-3.0)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(3.0)
			get_viewport().set_input_as_handled()
			return
	
	if event is InputEventMouseMotion and _is_mouse_panning:
		var mm := event as InputEventMouseMotion
		_orbit(mm.relative)
		_mouse_last = mm.position
		get_viewport().set_input_as_handled()
		return

	# Touch
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_points[st.index] = st.position
		else:
			_touch_points.erase(st.index)
			_pinch_last_dist = -1.0
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touch_points[sd.index] = sd.position
		if _touch_points.size() == 1:
			_orbit(sd.relative)
		elif _touch_points.size() >= 2:
			_handle_pinch()
		get_viewport().set_input_as_handled()
		return


func _orbit(delta: Vector2) -> void:
	# Horizontal drag rotates yaw, vertical drag adjusts pitch
	_yaw -= delta.x * pan_speed
	_pitch += delta.y * pan_speed
	_pitch = clampf(_pitch, min_pitch, max_pitch)
	_update_camera()


func _handle_pinch() -> void:
	var keys := _touch_points.keys()
	if keys.size() < 2:
		_pinch_last_dist = -1.0
		return
	var p0: Vector2 = _touch_points[keys[0]]
	var p1: Vector2 = _touch_points[keys[1]]
	var dist := p0.distance_to(p1)
	if _pinch_last_dist < 0.0:
		_pinch_last_dist = dist
		return
	var delta := _pinch_last_dist - dist
	_pinch_last_dist = dist
	_zoom(delta * 0.15)


func _zoom(amount: float) -> void:
	_distance = clampf(_distance + amount * zoom_speed * _distance, min_distance, max_distance)
	_update_camera()
