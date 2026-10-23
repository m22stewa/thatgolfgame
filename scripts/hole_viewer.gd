extends Control
class_name HoleViewer

## Main hole viewing camera - 3/4 overhead perspective
## Handles panning, zooming, rotating, ball tracking, and tile selection

signal tile_clicked(tile_coords: Vector2i)
signal tile_hovered(tile_coords: Vector2i)
signal flyover_finished  # the new-hole flyover reached the tee (or was skipped)
signal camera_moved      # the camera moved this frame (any cause)

# Camera node references
var camera: Camera3D = null
var viewport: SubViewport = null
var viewport_container: SubViewportContainer = null

# Camera settings
@export var camera_height: float = 25.0
@export var camera_angle: float = 55.0  # Degrees from horizontal (90 = top-down, 45 = more angled)
@export var min_zoom: float = 15.0
@export var max_zoom: float = 80.0
@export var zoom_speed: float = 3.0
@export var pan_speed: float = 0.5
@export var rotation_speed: float = 0.005  # Radians per pixel of mouse movement
@export var follow_speed: float = 5.0  # How fast camera follows ball
@export var flight_follow_speed: float = 8.0  # Faster tracking during flight

# Camera state
var target_position: Vector3 = Vector3.ZERO  # Where camera is looking at (on ground plane)
var current_zoom: float = 40.0
var target_zoom: float = 40.0
var camera_yaw: float = 0.0  # Rotation around Y axis (0 = looking north/up the hole)
var target_yaw: float = 0.0
var target_pitch: float = 55.0  # Target camera angle (pitch)
var is_panning: bool = false
var is_rotating: bool = false
var is_pitching: bool = false  # True when adjusting pitch with middle mouse
var pan_start_mouse: Vector2 = Vector2.ZERO
var pan_start_position: Vector3 = Vector3.ZERO
var pan_grab_world_pos: Vector3 = Vector3.ZERO  # World position where pan grab started
var rotation_start_mouse: Vector2 = Vector2.ZERO
var rotation_start_yaw: float = 0.0
var pitch_start_mouse: Vector2 = Vector2.ZERO
var pitch_start_angle: float = 55.0

# Pitch limits
const MIN_PITCH: float = 25.0  # Minimum camera angle (more angled/3D view)
const MAX_PITCH: float = 65.0  # Maximum camera angle (near top-down)
const PITCH_SPEED: float = 0.3  # Degrees per pixel of mouse movement

# Default camera pitch (matches camera_angle / target_pitch initializers) - used by reset_view()
const DEFAULT_PITCH: float = 55.0

# Cross-platform input tuning
const TAP_MOVE_THRESHOLD: float = 10.0   # px of movement before a press becomes a drag (not a tap)
const TAP_TIME_THRESHOLD: int = 350      # ms a press may last and still count as a tap

# --- Tap-vs-drag discriminator state (shared by left-mouse and single-finger touch) ---
var pending_tap: bool = false
var press_pos: Vector2 = Vector2.ZERO
var press_time: int = 0

# --- Touch / gesture state ---
var touches: Dictionary = {}          # index -> position (Vector2) of active touch points
var last_input_was_touch: bool = false
var prev_dist: float = 0.0            # previous two-finger distance (pinch)
var prev_ang: float = 0.0             # previous two-finger angle (twist)

# Keyboard camera tuning
const KEY_PAN_SPEED: float = 20.0     # world units/sec for keyboard pan nudge

# Aspect-aware framing tuning (used by _center_on_hole)
const Z_FIT_FACTOR: float = 0.55  # Scales hole length (Z) to fit vertically
const X_FIT_FACTOR: float = 2.0   # Scales hole width (X) to fit horizontally

# Ball tracking
var ball_node: Node3D = null
var is_tracking_ball: bool = true  # Start with tracking enabled
var ball_in_flight: bool = false
var last_ball_position: Vector3 = Vector3.ZERO
var ball_velocity: Vector3 = Vector3.ZERO
var track_after_flight: bool = true

# Wind display
var wind_label: Label = null
var wind_indicator: Node3D = null  # The windflag scene instance

# Flight camera behavior
@export var flight_zoom_out: float = 10.0  # Extra zoom during flight
@export var flight_look_ahead: float = 0.3  # How much to look ahead of ball during flight

# Hole reference
var hex_grid: Node = null
var hole_bounds: Rect2 = Rect2()

# Mouse state
var hovered_tile: Vector2i = Vector2i(-999, -999)

# Putting mode state
var is_putting_mode: bool = false
# Green view: on the green the camera frames the whole green (ball at the
# bottom, cup ahead) and holds still; tap-to-aim works as normal.
var is_green_view: bool = false
const GREEN_VIEW_PITCH: float = 66.0
const GREEN_VIEW_MARGIN: float = 1.05
var _pre_green_view := {}
var _green_frame: Array = []  # [center, extent, yaw] for Reset View on the green
var putting_system: Node = null
var normal_camera_angle: float = 55.0  # Store normal angle to restore
var normal_zoom: float = 40.0  # Store normal zoom to restore

# Putting mode camera settings
const PUTTING_CAMERA_ANGLE: float = 85.0  # Near top-down
const PUTTING_ZOOM: float = 20.0  # Closer zoom on green


func _ready() -> void:
	# Create the SubViewport structure
	_setup_viewport()
	
	# Re-frame the hole when the viewer band resizes (e.g. window/aspect change),
	# but only when idle so we never yank a tracked or mid-gesture camera.
	if viewport_container:
		viewport_container.resized.connect(_on_viewport_resized)
	
	# Create wind UI elements
	_setup_wind_display()
	
	# Find references after scene is ready
	call_deferred("_find_references")


func _setup_viewport() -> void:
	# Create SubViewportContainer (this Control will contain it)
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "ViewportContainer"
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	# IMPORTANT: Use PASS so we can handle input on the parent Control
	viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(viewport_container)
	# The 3D viewport is created in code and would otherwise be the LAST child
	# of HoleViewer, drawing on top of the HoleHUD overlay (wind/lie readouts,
	# Generate buttons, and the on-screen HoleControls) authored in main_ui.tscn.
	# Move it to the bottom of the draw order so the HUD renders over the 3D band.
	move_child(viewport_container, 0)
	
	# Create SubViewport
	viewport = SubViewport.new()
	viewport.name = "HoleViewport"
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport_container.add_child(viewport)
	
	# IMPORTANT: Share the main scene's World3D so we see the same 3D content
	# This must be done after the viewport is in the tree
	call_deferred("_share_world")
	
	# Create Camera3D
	camera = Camera3D.new()
	camera.name = "HoleCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 200.0
	viewport.add_child(camera)
	
	# Initial camera setup
	_update_camera_transform()


func _share_world() -> void:
	"""Share the main scene's World3D with our viewport"""
	# Get the main viewport's world
	var main_world = get_viewport().find_world_3d()
	if main_world and viewport:
		viewport.world_3d = main_world


func _find_references() -> void:
	# Find HexGrid - it's under HoleGenerator in the scene tree
	hex_grid = get_tree().current_scene.get_node_or_null("HoleGenerator/HexGrid")
	if hex_grid == null:
		hex_grid = get_tree().current_scene.get_node_or_null("HexGrid")
	if hex_grid == null:
		# Try finding it by searching all children
		hex_grid = _find_node_by_name(get_tree().current_scene, "HexGrid")
	
	if hex_grid:
		# Register our camera with hex_grid so it can be used for picking
		# Pass self so hex_grid can set up putting system connection
		if hex_grid.has_method("set_external_camera"):
			hex_grid.set_external_camera(camera, viewport, self)
		_calculate_hole_bounds()
		_center_on_hole()
	
	# Find ball
	_find_ball()


func _find_node_by_name(node: Node, search_name: String) -> Node:
	"""Recursively find a node by name"""
	if node.name == search_name:
		return node
	for child in node.get_children():
		var found = _find_node_by_name(child, search_name)
		if found:
			return found
	return null


func _find_ball() -> void:
	# Look for golf ball node
	ball_node = get_tree().current_scene.get_node_or_null("GolfBall")
	if ball_node == null:
		# Try finding by group (hex_grid uses "golfball")
		var balls = get_tree().get_nodes_in_group("golfball")
		if balls.size() > 0:
			ball_node = balls[0]
	
	if ball_node == null:
		# Try "golf_ball" group too
		var balls = get_tree().get_nodes_in_group("golf_ball")
		if balls.size() > 0:
			ball_node = balls[0]


func _calculate_hole_bounds() -> void:
	"""Calculate the bounding box of the hole for camera limits"""
	if not hex_grid:
		# Default bounds
		hole_bounds = Rect2(-5, -5, 20, 50)
		return
	
	# Get grid dimensions from hex_grid
	var tile_size = 1.0
	var grid_width = 10
	var grid_height = 40
	
	if "TILE_SIZE" in hex_grid:
		tile_size = hex_grid.TILE_SIZE
	if "grid_width" in hex_grid:
		grid_width = hex_grid.grid_width
	if "grid_height" in hex_grid:
		grid_height = hex_grid.grid_height
	
	# Calculate world bounds
	var hex_width = tile_size * 1.5
	var hex_height = tile_size * sqrt(3.0)
	
	hole_bounds = Rect2(
		-tile_size,  # Left edge with padding
		-tile_size,  # Top edge with padding
		grid_width * hex_width + tile_size * 2,  # Width
		grid_height * hex_height + tile_size * 2  # Height
	)


func _center_on_hole() -> void:
	"""Position camera to show hole - camera transform handles forward shift.
	Aspect-aware so the wider/shorter Snap-layout viewport still frames the hole."""
	if hole_bounds.size.length() > 0:
		# Guard-skip framing when the viewport isn't ready yet; retry on next resize.
		if viewport == null or viewport.size.y <= 1:
			return

		# Center on the hole's X, and start at the tee (low Z)
		target_position = Vector3(
			hole_bounds.position.x + hole_bounds.size.x / 2,
			0,
			hole_bounds.position.y  # Start at tee position
		)

		# Compute viewport aspect (16/9 fallback on divide-by-zero)
		var aspect := 16.0 / 9.0
		if viewport.size.y > 0:
			aspect = float(viewport.size.x) / float(viewport.size.y)

		# Fit the hole both along its length (Z) and width (X); wider viewport
		# (larger aspect) needs less zoom to fit the same width.
		var needed_for_z := hole_bounds.size.y * Z_FIT_FACTOR
		var needed_for_x := (hole_bounds.size.x * X_FIT_FACTOR) / aspect
		target_zoom = clamp(max(needed_for_z, needed_for_x), min_zoom, max_zoom)
		current_zoom = target_zoom


func _on_viewport_resized() -> void:
	"""Re-frame the hole on a band/window resize, but only when the camera is idle
	(not following the ball and not mid-gesture) so play isn't disrupted."""
	if is_green_view and _green_frame.size() == 3:
		enter_green_view(_green_frame[0], _green_frame[1], _green_frame[2])
		return
	if is_tracking_ball or is_flying:
		return
	if is_panning or is_rotating or is_pitching:
		return
	_center_on_hole()


func _process(delta: float) -> void:
	# Skip ball tracking in putting mode - camera stays fixed on green, and
	# while a scripted move (flyover / glide to the ball) has the camera
	var scripted := _cam_tween != null and _cam_tween.is_valid() and _cam_tween.is_running()
	if not is_putting_mode and not is_green_view and not scripted:
		_handle_ball_tracking(delta)
	if not scripted:
		_process_keyboard_camera(delta)
	_smooth_camera_movement(delta)
	_update_camera_transform()
	_check_camera_moved()
	_update_hovered_tile()
	_update_wind_display()


const CAMERA_MOVE_EPS := 0.02  # world units / radians per frame that count as moving
var _last_cam := Transform3D()


func _check_camera_moved() -> void:
	"""Emit camera_moved when the camera visibly moved since last frame (the
	smoothing's tiny settling steps don't count)."""
	if camera == null:
		return
	var t := camera.global_transform
	var moved := t.origin.distance_to(_last_cam.origin) > CAMERA_MOVE_EPS \
		or (t.basis.z - _last_cam.basis.z).length() > CAMERA_MOVE_EPS * 0.1
	_last_cam = t
	if moved:
		camera_moved.emit()


func _process_keyboard_camera(delta: float) -> void:
	"""Keyboard camera control via input actions. Gated to when the pointer is over
	the hole band (and a line-edit isn't focused elsewhere) so WASD/Q/E/+/- don't
	fight text entry or fire while the mouse is over the tray/UI."""
	# Don't steal keys from a focused text field.
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	# Only drive the camera when the pointer is over the hole band.
	if not _is_mouse_inside():
		return

	var moved := false

	# Rotate (yaw)
	var step := rotation_speed * 300.0 * delta
	if Input.is_action_pressed("cam_rotate_left"):
		target_yaw -= step
		moved = true
	if Input.is_action_pressed("cam_rotate_right"):
		target_yaw += step
		moved = true

	# Pan nudge (WASD / arrows map to left/right/up/down actions)
	var pan_vec := Vector2.ZERO
	if Input.is_action_pressed("left"):
		pan_vec.x -= 1.0
	if Input.is_action_pressed("right"):
		pan_vec.x += 1.0
	if Input.is_action_pressed("up"):
		pan_vec.y -= 1.0
	if Input.is_action_pressed("down"):
		pan_vec.y += 1.0
	if pan_vec != Vector2.ZERO:
		var yaw := camera_yaw
		var right := Vector3(cos(yaw), 0, sin(yaw))
		var fwd := Vector3(sin(yaw), 0, -cos(yaw))
		var scale := KEY_PAN_SPEED * (current_zoom / 40.0) * delta
		target_position += right * pan_vec.x * scale + fwd * pan_vec.y * scale
		moved = true

	# Zoom
	if Input.is_action_pressed("cam_zoom_in"):
		target_zoom = clamp(target_zoom - zoom_speed * delta * 10.0, min_zoom, max_zoom)
		moved = true
	if Input.is_action_pressed("cam_zoom_out"):
		target_zoom = clamp(target_zoom + zoom_speed * delta * 10.0, min_zoom, max_zoom)
		moved = true

	if moved:
		is_tracking_ball = false


func _handle_ball_tracking(delta: float) -> void:
	"""Handle camera following the ball - optimized to only move on landing"""
	if not ball_node or not is_instance_valid(ball_node):
		_find_ball()
		return
	
	var ball_pos = ball_node.global_position
	
	# Simple velocity check (avoid per-frame division)
	var pos_delta = ball_pos - last_ball_position
	var speed_sq = pos_delta.length_squared()  # Avoid sqrt for performance
	last_ball_position = ball_pos
	
	# Detect if ball is in flight (speed^2 > 1.0 means speed > 1.0)
	var was_in_flight = ball_in_flight
	ball_in_flight = speed_sq > 1.0
	
	# Only act on state changes - not every frame
	if ball_in_flight and not was_in_flight:
		_on_ball_flight_started()
	elif not ball_in_flight and was_in_flight:
		_on_ball_flight_ended()
	
	# Only do smooth tracking when ball is at rest and tracking is enabled
	# Skip tracking during flight to reduce per-frame calculations
	if is_tracking_ball and not ball_in_flight:
		var target = Vector3(ball_pos.x, 0, ball_pos.z)
		# Only lerp if we're not already close enough
		var dist_sq = (target_position - target).length_squared()
		if dist_sq > 0.1:  # Only move if more than ~0.3 units away
			target_position = target_position.lerp(target, delta * follow_speed)


func _on_ball_flight_started() -> void:
	"""Called when ball starts moving"""
	pass


func _on_ball_flight_ended() -> void:
	"""Called when ball stops - smoothly move camera to ball position"""
	# Re-enable tracking when shot completes (user can disable again by panning/rotating)
	# (the tracking lerp eases it over; the next shot's frame_shot settles it)
	is_tracking_ball = true
	track_after_flight = true


func _smooth_camera_movement(delta: float) -> void:
	"""Smooth interpolation for zoom and rotation - only when needed"""
	# Only lerp if values are different (avoid unnecessary calculations)
	if abs(current_zoom - target_zoom) > 0.01:
		current_zoom = lerp(current_zoom, target_zoom, delta * 8.0)
	else:
		current_zoom = target_zoom
	
	if abs(camera_yaw - target_yaw) > 0.001:
		camera_yaw = lerp_angle(camera_yaw, target_yaw, delta * 8.0)
	else:
		camera_yaw = target_yaw


# Cache for camera transform to avoid recalculating every frame
var _last_cam_pos: Vector3 = Vector3.ZERO
var _last_target_pos: Vector3 = Vector3.ZERO
var _last_zoom: float = 0.0
var _last_yaw: float = 0.0
var _last_angle: float = 0.0

func _update_camera_transform() -> void:
	"""Update camera position and rotation based on current state - cached"""
	if not camera:
		return
	
	# Skip update if nothing changed (big performance win)
	if target_position == _last_target_pos and current_zoom == _last_zoom and camera_yaw == _last_yaw and camera_angle == _last_angle:
		return
	
	# Cache current values
	_last_target_pos = target_position
	_last_zoom = current_zoom
	_last_yaw = camera_yaw
	_last_angle = camera_angle
	
	# Calculate camera position with rotation
	var angle_rad = deg_to_rad(camera_angle)
	var horizontal_dist = current_zoom * cos(angle_rad)
	var vertical_dist = current_zoom * sin(angle_rad)
	
	# Apply yaw rotation to camera offset
	var offset_x = sin(camera_yaw) * horizontal_dist
	var offset_z = -cos(camera_yaw) * horizontal_dist  # Negative to look from behind
	
	# Shift the view forward (the way the camera faces) so the ball / tee sits
	# low in the frame with the shot ahead of it. The green view frames its
	# own centre, so no shift there.
	var shift_len: float = 0.0 if is_green_view else horizontal_dist * 0.5
	var shift := Vector3(-sin(camera_yaw), 0, cos(camera_yaw)) * shift_len
	
	var cam_pos = Vector3(
		target_position.x + offset_x,
		vertical_dist,
		target_position.z + offset_z
	) + shift
	
	camera.global_position = cam_pos
	camera.look_at(Vector3(target_position.x, 0, target_position.z) + shift, Vector3.UP)


func _is_mouse_inside() -> bool:
	"""Check if mouse is inside the HoleViewer bounds"""
	var mouse_pos = get_global_mouse_position()
	var rect = get_global_rect()
	return rect.has_point(mouse_pos)


func _is_mouse_over_ui_control(mouse_pos_override: Vector2 = Vector2(INF, INF)) -> bool:
	"""Check if mouse is over a UI control that should consume clicks (buttons, etc).

	Pass mouse_pos_override to test the gate at a specific global point; defaults
	to the live OS mouse position (the normal runtime path)."""
	var mouse_pos = mouse_pos_override
	if mouse_pos.x == INF:
		mouse_pos = get_global_mouse_position()
	
	# Get all controls under mouse and check if any should consume input
	var parent_control = get_parent()
	if parent_control is Control:
		# Check all sibling controls
		for child in parent_control.get_children():
			if child == self:
				continue
			if child is Control and child.visible:
				if _control_wants_input(child, mouse_pos):
					# print("Input consumed by: ", child.name)
					return true

	# Also check our OWN descendant UI (the HoleHUD corner overlay and its
	# buttons now live under HoleViewer). Skip the SubViewportContainer: it is a
	# full-rect PASS control and treating it as "wants input" would make the
	# viewer yield everywhere and break hole aiming.
	for child in get_children():
		if child == viewport_container or child is SubViewportContainer:
			continue
		if child is Control and child.visible:
			if _control_wants_input(child, mouse_pos):
				# print("Input consumed by HUD descendant: ", child.name)
				return true
	return false


func _control_wants_input(control: Control, mouse_pos: Vector2) -> bool:
	"""Recursively check if a control or its children want mouse input"""
	# Check if this control is a clickable type and contains the mouse
	var rect = control.get_global_rect()
	if rect.has_point(mouse_pos):
		# Buttons always consume clicks
		if control is BaseButton:
			return true
			
		# Card System UI should always consume clicks
		# Check by class name string to avoid cyclic dependency issues or load order issues
		if "CardSelectionUI" in control.name:
			return true
		if control.get_script() and "card_selection_ui.gd" in control.get_script().resource_path:
			return true
			
		if "CardUI" in control.name:
			return true
		if control.get_script() and "card_ui.gd" in control.get_script().resource_path:
			return true
			
		# DeckWidget should always consume clicks
		if "DeckWidget" in control.name:
			return true
		if control.get_script() and "deck_widget.gd" in control.get_script().resource_path:
			return true
			
		# Check children recursively
		for child in control.get_children():
			if child is Control and child.visible:
				if _control_wants_input(child, mouse_pos):
					return true
	return false


func _input(event: InputEvent) -> void:
	# A flyover belongs to the camera: any press skips to its end
	if is_flying:
		var press: bool = (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.pressed
		if press and (not (event is InputEventMouseButton) or _is_mouse_inside()):
			skip_flyover()
			get_viewport().set_input_as_handled()
		return
	# --- Touch screen (phone) ---
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
		return
	if event is InputEventScreenDrag:
		_handle_screen_drag(event)
		return
	# --- Trackpad / touchpad gestures (laptop, touch) ---
	if event is InputEventMagnifyGesture:
		_handle_magnify_gesture(event)
		return
	if event is InputEventPanGesture:
		_handle_pan_gesture(event)
		return

	# Always handle motion if we're already panning/rotating (even if mouse leaves bounds)
	if event is InputEventMouseMotion:
		if is_panning or is_rotating:
			_handle_mouse_motion(event)
			get_viewport().set_input_as_handled()
		elif pending_tap:
			# A left-mouse press is in flight; promote it to a pan once it moves
			# far enough so a drag never fires an aim (tap) on release.
			if event.position.distance_to(press_pos) > TAP_MOVE_THRESHOLD:
				pending_tap = false
				_begin_single_pointer_pan(press_pos)
				_handle_mouse_motion(event)
				get_viewport().set_input_as_handled()
		return
	
	# For button events, check if mouse is inside our bounds
	if not _is_mouse_inside():
		return
	
	if event is InputEventMouseButton:
		# If we are currently dragging/rotating, we own the mouse interaction
		# and must handle the release event regardless of UI
		var is_interacting = is_panning or is_rotating or pending_tap
		
		if not is_interacting:
			# If not interacting, check if UI wants this event (Press OR Release)
			# This ensures we don't steal release events from UI
			if _is_mouse_over_ui_control():
				return

		_handle_mouse_button(event)
		get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# In putting mode, handle differently
	if is_putting_mode:
		_handle_putting_mouse_button(event)
		return
	
	# Middle mouse = adjust pitch (vertical) and yaw (horizontal)
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			is_pitching = true
			is_rotating = true
			pitch_start_mouse = event.position
			pitch_start_angle = camera_angle
			rotation_start_mouse = event.position
			rotation_start_yaw = target_yaw
		else:
			is_pitching = false
			is_rotating = false
	
	# Right mouse = pan
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			is_panning = true
			pan_start_mouse = event.position
			pan_start_position = target_position
			# Record the world position we're "grabbing"
			var grab_pos = _screen_to_world(event.position)
			if grab_pos != null:
				pan_grab_world_pos = grab_pos
			else:
				pan_grab_world_pos = target_position
		else:
			is_panning = false
	
	# Scroll wheel = zoom
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if event.pressed:
			target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
	
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.pressed:
			target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)
	
	# Left click = tap-vs-drag: a quick stationary press+release aims (tap);
	# dragging past the threshold pans instead, so a pan never steals aim.
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			last_input_was_touch = false
			_begin_pending_tap(event.position)
		else:
			_resolve_pending_tap(event.position)


func _handle_putting_mouse_button(event: InputEventMouseButton) -> void:
	"""Handle mouse input during putting mode"""
	# Right click in putting mode - handle pan directly (no pitch)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			is_panning = true
			pan_start_mouse = event.position
			pan_start_position = target_position
		else:
			is_panning = false
		return
	
	# Left click = aim/charge/release
	if event.button_index == MOUSE_BUTTON_LEFT:
		if putting_system:
			putting_system.handle_input(event)
		return
	
	# Scroll wheel still works for zoom
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if event.pressed:
			target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.pressed:
			target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	# Middle mouse controls both pitch and yaw simultaneously
	if is_pitching and is_rotating:
		# Vertical movement = pitch (camera angle)
		var delta_y = event.position.y - pitch_start_mouse.y
		camera_angle = clamp(pitch_start_angle + delta_y * PITCH_SPEED, MIN_PITCH, MAX_PITCH)
		target_pitch = camera_angle
		
		# Horizontal movement = yaw (rotation)
		var delta_x = event.position.x - rotation_start_mouse.x
		target_yaw = rotation_start_yaw + delta_x * rotation_speed
		camera_yaw = target_yaw
		
		_update_camera_transform()
		# Stop tracking ball when manually adjusting camera
		is_tracking_ball = false
	
	elif is_rotating:
		# Calculate rotation delta
		var delta_x = event.position.x - rotation_start_mouse.x
		target_yaw = rotation_start_yaw + delta_x * rotation_speed
		# Stop tracking ball when manually rotating
		is_tracking_ball = false
	
	elif is_panning:
		# Convert screen delta to world delta using ground plane projection
		# Get world positions at start and current mouse positions
		var start_world = _screen_to_world(pan_start_mouse)
		var current_world = _screen_to_world(event.position)
		
		if start_world != null and current_world != null:
			# Calculate world-space delta between the two screen positions
			var world_delta = Vector3(current_world) - Vector3(start_world)
			# Move camera in opposite direction to create grab effect
			target_position = pan_start_position - Vector3(world_delta.x, 0, world_delta.z)
		
		# Stop tracking ball when manually panning
		is_tracking_ball = false


# ============================================================================
# TAP-VS-DRAG DISCRIMINATOR (shared by left-mouse and single-finger touch)
# ============================================================================

func _begin_pending_tap(pos: Vector2) -> void:
	"""Record a press and arm the tap/drag discriminator. We do NOT aim yet -
	aim fires only on a quick, stationary release (a tap)."""
	pending_tap = true
	press_pos = pos
	press_time = Time.get_ticks_msec()


func _resolve_pending_tap(pos: Vector2) -> void:
	"""On release: if the press never moved past the threshold and was quick,
	treat it as a tap and aim; otherwise it was a drag/hold - do nothing."""
	var was_tap := pending_tap
	pending_tap = false
	# End any single-pointer pan that this press may have started.
	is_panning = false
	if not was_tap:
		return
	var elapsed := Time.get_ticks_msec() - press_time
	if elapsed > TAP_TIME_THRESHOLD:
		return
	if pos.distance_to(press_pos) > TAP_MOVE_THRESHOLD:
		return
	# In putting mode a classified tap is a putting candidate (synthesized mouse).
	if is_putting_mode:
		_forward_touch_putting_tap(pos)
	else:
		_handle_tile_click(pos)


func _begin_single_pointer_pan(start_pos: Vector2) -> void:
	"""Start a right-mouse-style pan driven by a single pointer (left-drag / one finger)."""
	is_panning = true
	pan_start_mouse = start_pos
	pan_start_position = target_position
	var grab_pos = _screen_to_world(start_pos)
	if grab_pos != null:
		pan_grab_world_pos = grab_pos
	else:
		pan_grab_world_pos = target_position


# ============================================================================
# TOUCH + TRACKPAD GESTURES (phone touch, laptop trackpad)
# These never fire on a desktop headless run; they must compile and not throw.
# ============================================================================

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	last_input_was_touch = true
	if event.pressed:
		touches[event.index] = event.position
		if touches.size() == 1:
			# First finger down: arm the tap/drag discriminator (single-finger
			# drag will become a pan, a quick stationary lift becomes a tap/aim).
			_begin_pending_tap(event.position)
		elif touches.size() == 2:
			# Second finger landed: cancel any pending single-finger pan/tap and
			# seed the pinch/twist reference frame from the two touch positions.
			pending_tap = false
			is_panning = false
			_seed_two_finger_gesture()
	else:
		# Finger lifted.
		if touches.size() == 1 and touches.has(event.index):
			# Lifting the last (single) finger: resolve tap vs drag.
			touches.erase(event.index)
			_resolve_pending_tap(event.position)
		else:
			touches.erase(event.index)
		if touches.is_empty():
			is_panning = false
			is_rotating = false
			pending_tap = false
			prev_dist = 0.0
			prev_ang = 0.0


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	last_input_was_touch = true
	if touches.has(event.index):
		touches[event.index] = event.position

	if touches.size() == 1:
		# One finger -> pan. Promote a still-pending tap into a pan once moved.
		if pending_tap:
			if event.position.distance_to(press_pos) > TAP_MOVE_THRESHOLD:
				pending_tap = false
				_begin_single_pointer_pan(press_pos)
		if is_panning:
			var motion := InputEventMouseMotion.new()
			motion.position = event.position
			_handle_mouse_motion(motion)
	elif touches.size() >= 2:
		# Two fingers -> pinch (zoom) + twist (yaw) as independent axes.
		_apply_two_finger_gesture()


func _seed_two_finger_gesture() -> void:
	"""Seed prev_dist / prev_ang on the frame the second finger lands."""
	var pts := touches.values()
	if pts.size() < 2:
		return
	var p0: Vector2 = pts[0]
	var p1: Vector2 = pts[1]
	prev_dist = p0.distance_to(p1)
	prev_ang = atan2(p1.y - p0.y, p1.x - p0.x)


func _apply_two_finger_gesture() -> void:
	"""Pinch + twist each two-finger frame from the two touch positions."""
	var pts := touches.values()
	if pts.size() < 2:
		return
	var p0: Vector2 = pts[0]
	var p1: Vector2 = pts[1]

	# Pinch -> zoom
	var dist: float = p0.distance_to(p1)
	if prev_dist > 0.001:
		var factor: float = dist / prev_dist
		if factor > 0.001:
			target_zoom = clamp(target_zoom / factor, min_zoom, max_zoom)
	prev_dist = dist

	# Twist -> yaw
	var ang: float = atan2(p1.y - p0.y, p1.x - p0.x)
	var d_ang: float = wrapf(ang - prev_ang, -PI, PI)
	target_yaw += d_ang
	prev_ang = ang

	is_tracking_ball = false


func _handle_magnify_gesture(event: InputEventMagnifyGesture) -> void:
	"""Trackpad / touch pinch -> zoom via factor. Preferred over the ScreenDrag
	pinch path when both arrive the same frame (seed prev_dist so the drag path
	treats this frame as its reference and does not double-apply)."""
	last_input_was_touch = true
	if event.factor > 0.001:
		target_zoom = clamp(target_zoom / event.factor, min_zoom, max_zoom)
		is_tracking_ball = false
	# Keep the two-finger drag pinch in sync so it won't re-apply this frame.
	var pts := touches.values()
	if pts.size() >= 2:
		prev_dist = (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	"""Trackpad two-finger scroll -> pan via delta (no modifier branch)."""
	last_input_was_touch = true
	# Pan the look target in the camera's ground plane using the gesture delta.
	var yaw := camera_yaw
	var right := Vector3(cos(yaw), 0, sin(yaw))
	var fwd := Vector3(sin(yaw), 0, -cos(yaw))
	var scale := pan_speed * (current_zoom / 40.0)
	target_position += right * event.delta.x * scale + fwd * event.delta.y * scale
	is_tracking_ball = false


func _forward_touch_putting_tap(tap_pos: Vector2) -> void:
	"""Touch putting: synthesize a left-mouse press+release at the tap position and
	forward to putting_system.handle_input(). putting_system is null today (retired),
	so this is a safe no-op that preserves the mouse contract if it is un-retired."""
	if putting_system == null:
		return
	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.position = tap_pos
	putting_system.handle_input(press_event)

	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = tap_pos
	putting_system.handle_input(release_event)


func _handle_tile_click(screen_pos: Vector2) -> void:
	"""Handle clicking on the viewport to select a tile.

	TOUCH CONTRACT: on touch there is no hover, so a tap collapses 'hover' and
	'select' into a single action. hex_grid.set_aim_cell() shows the footprint /
	AOE / trajectory preview on a valid tile even when ShotUI is absent (it fires
	_update_aoe_for_cell + _update_trajectory before the shot_ui guard). An invalid
	tap returns false, locks nothing, and leaves the preview on the last valid aim."""
	# Green view: putts aim at small hexes on the green's surface
	if is_green_view and hex_grid and hex_grid.has_method("putt_aim_ray") and camera and viewport:
		var vp_pos := screen_pos * (Vector2(viewport.size) / viewport_container.size)
		if hex_grid.putt_aim_ray(camera.project_ray_origin(vp_pos), camera.project_ray_normal(vp_pos)):
			return
	var world_pos = _screen_to_world(screen_pos)
	if world_pos == null:
		return
	
	# Convert world position to tile coordinates
	var tile_coords = _world_to_tile(world_pos)
	if tile_coords.x != -999:
		# Emit signal for external listeners
		tile_clicked.emit(tile_coords)
		
		# Directly set aim on hex_grid if available
		if hex_grid and hex_grid.has_method("set_aim_cell"):
			hex_grid.set_aim_cell(tile_coords)


func _update_hovered_tile() -> void:
	"""Update which tile the mouse is hovering over"""
	# No hover on touch: a tap collapses hover+select, so skip hover updates
	# while the last input came from a touch screen.
	if last_input_was_touch:
		return
	var mouse_pos = get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(mouse_pos):
		return
	
	var world_pos = _screen_to_world(mouse_pos)
	if world_pos == null:
		return
	
	var tile_coords = _world_to_tile(world_pos)
	if tile_coords != hovered_tile:
		hovered_tile = tile_coords
		if tile_coords.x != -999:
			tile_hovered.emit(tile_coords)
			
			# In putting mode, aim is handled by putting_system's own raycasting
			if not is_putting_mode:
				# Update hex_grid hover for highlighting (shows AOE)
				if hex_grid and hex_grid.has_method("set_hover_cell"):
					hex_grid.set_hover_cell(tile_coords)


func _screen_to_world(screen_pos: Vector2) -> Variant:
	"""Convert screen position in viewport to world position on ground plane"""
	if not camera or not viewport:
		return null
	
	# Adjust screen_pos to viewport coordinates
	var viewport_size = viewport.size
	var container_size = viewport_container.size
	
	# Scale screen position to viewport
	var viewport_pos = screen_pos * (Vector2(viewport_size) / container_size)
	
	# Create ray from camera
	var from = camera.project_ray_origin(viewport_pos)
	var dir = camera.project_ray_normal(viewport_pos)
	
	# Intersect with ground plane (y = 0)
	if abs(dir.y) < 0.001:
		return null
	
	var t = -from.y / dir.y
	if t < 0:
		return null
	
	return from + dir * t


func _world_to_tile(world_pos: Vector3) -> Vector2i:
	"""Convert world position to hex tile coordinates"""
	if not hex_grid:
		return Vector2i(-999, -999)
	
	# Use hex_grid's conversion if available
	if hex_grid.has_method("world_to_grid"):
		return hex_grid.world_to_grid(world_pos)
	
	# Fallback: rough hex conversion
	var hex_size = 1.0
	if "TILE_SIZE" in hex_grid:
		hex_size = hex_grid.TILE_SIZE
	elif "hex_size" in hex_grid:
		hex_size = hex_grid.hex_size
	
	var width = hex_size
	var height = hex_size * sqrt(3.0)
	
	# Approximate column from x position
	var col = int(round(world_pos.x / (width * 1.5)))
	
	# Adjust z for row offset based on column
	var z_offset = (col % 2) * (height / 2.0)
	var row = int(round((world_pos.z - z_offset) / height))
	
	return Vector2i(col, row)


# Public API

func center_on_position(world_pos: Vector3, smooth: bool = true) -> void:
	"""Center the camera on a world position"""
	target_position = Vector3(world_pos.x, 0, world_pos.z)
	if not smooth:
		_update_camera_transform()


func center_on_ball(smooth: bool = true) -> void:
	"""Center camera on the ball"""
	if ball_node and is_instance_valid(ball_node):
		center_on_position(ball_node.global_position, smooth)


func set_zoom(zoom_level: float, smooth: bool = true) -> void:
	"""Set the zoom level"""
	target_zoom = clamp(zoom_level, min_zoom, max_zoom)
	if not smooth:
		current_zoom = target_zoom
		_update_camera_transform()


func set_camera_rotation(yaw_degrees: float, smooth: bool = true) -> void:
	"""Set the camera rotation (yaw) in degrees"""
	target_yaw = deg_to_rad(yaw_degrees)
	if not smooth:
		camera_yaw = target_yaw
		_update_camera_transform()


func start_tracking_ball() -> void:
	"""Start following the ball"""
	is_tracking_ball = true


func stop_tracking_ball() -> void:
	"""Stop following the ball"""
	is_tracking_ball = false


func reset_view() -> void:
	"""Reset camera to show the ball with default rotation and pitch"""
	if is_green_view and _green_frame.size() == 3:
		enter_green_view(_green_frame[0], _green_frame[1], _green_frame[2])
		return
	if not _shot_pose.is_empty():
		_glide_to(_shot_pose, SHOT_GLIDE_TIME)
		return
	target_yaw = 0.0
	camera_angle = DEFAULT_PITCH
	target_pitch = DEFAULT_PITCH
	is_tracking_ball = true
	if ball_node and is_instance_valid(ball_node):
		center_on_ball(true)
	else:
		_center_on_hole()


# --- On-screen HoleControls handlers (zoom/rotate/reset buttons in the HUD) ---

func on_zoom_in_pressed() -> void:
	set_zoom(target_zoom - zoom_speed)


func on_zoom_out_pressed() -> void:
	set_zoom(target_zoom + zoom_speed)


func on_rotate_pressed() -> void:
	# Guaranteed trackpad/touch rotate path (45 degree steps).
	target_yaw += deg_to_rad(45)
	is_tracking_ball = false


func on_reset_view_pressed() -> void:
	reset_view()


func look_at_flag() -> void:
	"""Rotate camera to look toward the flag/hole"""
	if hex_grid and "flag_position" in hex_grid:
		var flag_grid_pos = hex_grid.flag_position  # Vector2i grid coords
		var ball_pos = target_position
		if ball_node and is_instance_valid(ball_node):
			ball_pos = Vector3(ball_node.global_position.x, 0, ball_node.global_position.z)
		
		# Convert flag grid position to world position
		var flag_world_pos: Vector3
		if hex_grid.has_method("get_tile_world_position"):
			flag_world_pos = hex_grid.get_tile_world_position(flag_grid_pos)
		else:
			# Fallback: manual hex grid to world conversion
			var tile_size = 1.0
			if "TILE_SIZE" in hex_grid:
				tile_size = hex_grid.TILE_SIZE
			var hex_height = tile_size * sqrt(3.0)
			flag_world_pos = Vector3(
				flag_grid_pos.x * tile_size * 1.5,
				0,
				flag_grid_pos.y * hex_height + (flag_grid_pos.x % 2) * hex_height / 2.0
			)
		
		# Calculate angle from ball to flag
		var dir = flag_world_pos - ball_pos
		target_yaw = atan2(dir.x, dir.z)


func get_hole_viewport() -> SubViewport:
	"""Get the SubViewport for rendering"""
	return viewport


func add_to_viewport(node: Node3D) -> void:
	"""Add a 3D node to be rendered in this viewport"""
	if viewport:
		viewport.add_child(node)


# --- Camera direction: hole flyover and framing each shot ---
#
# A pose is {pos (ground point looked at), zoom, yaw, pitch}. Scripted moves
# tween between poses and own the camera while they run (no ball tracking,
# no keyboard camera); a flyover can be skipped with any press.

const SHOT_GLIDE_TIME := 1.1
const FLY_LOW_ZOOM := 26.0
const FLY_LOW_PITCH := 46.0

var is_flying := false
var _cam_tween: Tween = null
var _shot_pose: Dictionary = {}  # where the camera settles for the next shot


static func yaw_toward(from: Vector3, to: Vector3) -> float:
	"""Camera yaw that faces from -> to (matches _update_camera_transform)."""
	var d := to - from
	return atan2(-d.x, d.z)


func shot_pose(ball: Vector3, aim: Vector3) -> Dictionary:
	"""Behind the ball, facing the aim, zoomed so the shot fits ahead of it."""
	var dist := Vector2(aim.x - ball.x, aim.z - ball.z).length()
	return {
		"pos": Vector3(ball.x, 0, ball.z),
		"zoom": clampf(dist * 0.55 + 12.0, 20.0, max_zoom),
		"yaw": yaw_toward(ball, aim) if dist > 0.5 else target_yaw,
		"pitch": DEFAULT_PITCH,
	}


func frame_shot(ball: Vector3, aim: Vector3) -> void:
	"""Next shot: glide to the ball, turned to face where it's aimed."""
	if is_green_view:
		return
	_shot_pose = shot_pose(ball, aim)
	if is_flying:
		_flyover_end_pose = _shot_pose  # the flyover lands on the new framing
		return
	_glide_to(_shot_pose, SHOT_GLIDE_TIME)


func play_flyover(tee: Vector3, green: Vector3, end_pose: Dictionary, start_delay: float = 0.0) -> void:
	"""New hole: whole-hole overview, down to the tee, along the hole to the
	green, a slow circle round it, then back to the tee framed for the shot."""
	_stop_camera_tween()
	_shot_pose = end_pose
	_flyover_end_pose = end_pose
	is_flying = true
	is_tracking_ball = false
	var yaw := yaw_toward(tee, green)
	var length := Vector2(green.x - tee.x, green.z - tee.z).length()
	var mid := (tee + green) / 2.0
	var overview := {"pos": Vector3(mid.x, 0, mid.z) - Vector3(-sin(yaw), 0, cos(yaw)) * length * 0.25,
		"zoom": clampf(length * 0.75, 30.0, max_zoom), "yaw": yaw, "pitch": 60.0}
	var at_tee := {"pos": Vector3(tee.x, 0, tee.z), "zoom": FLY_LOW_ZOOM, "yaw": yaw, "pitch": FLY_LOW_PITCH}
	var at_green := {"pos": Vector3(green.x, 0, green.z), "zoom": FLY_LOW_ZOOM + 2.0, "yaw": yaw, "pitch": FLY_LOW_PITCH + 6.0}
	var round_green := {"pos": Vector3(green.x, 0, green.z), "zoom": FLY_LOW_ZOOM + 6.0, "yaw": yaw + deg_to_rad(80), "pitch": 52.0}
	_apply_pose(overview)
	_cam_tween = create_tween()
	if start_delay > 0.0:
		_cam_tween.tween_interval(start_delay)
	_cam_tween.tween_interval(0.8)
	_tween_pose(overview, at_tee, 1.4, Tween.TRANS_SINE)
	_tween_pose(at_tee, at_green, clampf(length / 14.0, 2.2, 4.5), Tween.TRANS_SINE)
	_tween_pose(at_green, round_green, 1.6, Tween.TRANS_SINE)
	# The end pose may change while flying (the first shot gets re-aimed), so
	# the last leg reads it when it starts
	_cam_tween.tween_callback(func(): _last_leg_from = _pose_now())
	_cam_tween.tween_method(func(t: float): _apply_pose(_lerp_pose(_last_leg_from, _flyover_end_pose, t)), 0.0, 1.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_callback(_finish_flyover)


var _flyover_end_pose: Dictionary = {}
var _last_leg_from: Dictionary = {}


func skip_flyover() -> void:
	if not is_flying:
		return
	_stop_camera_tween()
	_glide_to(_flyover_end_pose, 0.6)
	_finish_flyover()


func _finish_flyover() -> void:
	is_flying = false
	is_tracking_ball = true
	flyover_finished.emit()


func _glide_to(pose: Dictionary, duration: float) -> void:
	_stop_camera_tween()
	is_tracking_ball = true
	_cam_tween = create_tween()
	_tween_pose(_pose_now(), pose, duration, Tween.TRANS_SINE)


func _tween_pose(from: Dictionary, to: Dictionary, duration: float, trans: Tween.TransitionType) -> void:
	_cam_tween.tween_method(func(t: float): _apply_pose(_lerp_pose(from, to, t)), 0.0, 1.0, duration).set_trans(trans).set_ease(Tween.EASE_IN_OUT)


func _stop_camera_tween() -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = null
	is_flying = false


func _pose_now() -> Dictionary:
	return {"pos": target_position, "zoom": current_zoom, "yaw": camera_yaw, "pitch": camera_angle}


func _lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"pos": (a.pos as Vector3).lerp(b.pos, t),
		"zoom": lerpf(a.zoom, b.zoom, t),
		"yaw": lerp_angle(a.yaw, b.yaw, t),
		"pitch": lerpf(a.pitch, b.pitch, t),
	}


func _apply_pose(p: Dictionary) -> void:
	"""Set the camera exactly (current and target) so smoothing doesn't lag it."""
	target_position = p.pos
	current_zoom = p.zoom
	target_zoom = p.zoom
	camera_yaw = p.yaw
	target_yaw = p.yaw
	camera_angle = p.pitch
	target_pitch = p.pitch


# --- Green View ---

func enter_green_view(center: Vector3, extent: float, yaw: float) -> void:
	"""Frame the whole green: look at its centre from yaw (radians, ball side),
	pitched down, zoomed so a circle of diameter extent fits the band."""
	_stop_camera_tween()
	if not is_green_view:
		_pre_green_view = {"angle": camera_angle, "pitch": target_pitch, "zoom": target_zoom, "yaw": target_yaw}
	_green_frame = [center, extent, yaw]
	is_green_view = true
	is_tracking_ball = false
	camera_angle = GREEN_VIEW_PITCH
	target_pitch = GREEN_VIEW_PITCH
	target_yaw = yaw
	target_position = Vector3(center.x, 0, center.z)
	# The band is wider than tall: fit the green's extent to the vertical FOV
	var half_fov := deg_to_rad((camera.fov if camera else 50.0) * 0.5)
	var fit := extent * GREEN_VIEW_MARGIN / (2.0 * tan(half_fov))
	target_zoom = clamp(fit / sin(deg_to_rad(GREEN_VIEW_PITCH)), 6.0, max_zoom)


func exit_green_view() -> void:
	"""Back to the shot view: restore the previous camera and follow the ball."""
	if not is_green_view:
		return
	is_green_view = false
	camera_angle = _pre_green_view.get("angle", DEFAULT_PITCH)
	target_pitch = _pre_green_view.get("pitch", DEFAULT_PITCH)
	target_zoom = _pre_green_view.get("zoom", target_zoom)
	target_yaw = _pre_green_view.get("yaw", 0.0)
	is_tracking_ball = true
	center_on_ball(true)


# --- Putting Mode ---

func enter_putting_mode(green_center: Vector2i, green_bounds: Rect2i) -> void:
	"""Switch to putting mode camera - top-down view centered on green"""
	if is_putting_mode:
		return
	
	is_putting_mode = true
	
	# Store current camera settings
	normal_camera_angle = camera_angle
	normal_zoom = current_zoom
	
	# Switch to near top-down view
	camera_angle = PUTTING_CAMERA_ANGLE
	target_zoom = PUTTING_ZOOM
	
	# Center on green
	if hex_grid and green_center.x >= 0:
		var green_world_pos = hex_grid.get_tile_world_position(green_center)
		target_position = Vector3(green_world_pos.x, 0, green_world_pos.z)
	
	# Look straight at the green (no yaw rotation for putting)
	target_yaw = 0.0
	
	# Disable ball tracking in putting mode - we stay centered on green
	is_tracking_ball = false


func exit_putting_mode() -> void:
	"""Exit putting mode and restore normal camera"""
	if not is_putting_mode:
		return
	
	is_putting_mode = false
	
	# Restore normal camera settings
	camera_angle = normal_camera_angle
	target_zoom = normal_zoom
	
	# Re-enable ball tracking
	is_tracking_ball = true
	
	# Center on ball
	center_on_ball(true)


func set_putting_system(system: Node) -> void:
	"""Set reference to the putting system"""
	putting_system = system


# ============================================================================
# WIND DISPLAY
# ============================================================================

var wind_widget: Control = null
var show_wind_widget := true  # off in the prototype UI: the tray shows the wind

func _setup_wind_display() -> void:
	"""Find UI elements for wind display (must be added in editor)"""
	# 1. Try direct child
	wind_widget = get_node_or_null("WindWidget")
	
	# 2. Try searching recursively in this node
	if not wind_widget:
		wind_widget = _find_node_by_name(self, "WindWidget")
	
	# 3. Try searching the entire scene (most robust)
	if not wind_widget and get_tree() and get_tree().current_scene:
		wind_widget = get_tree().current_scene.find_child("WindWidget", true, false)
		
	if wind_widget:
		# Found existing widget (placed in editor)
		# Try to find Label as direct child first
		wind_label = wind_widget.get_node_or_null("Label")
		
		# Try to find SubViewport in SubViewportContainer child
		var svc = wind_widget.get_node_or_null("SubViewportContainer")
		if svc:
			var viewport = svc.get_node_or_null("SubViewport")
			if viewport:
				wind_indicator = viewport.get_node_or_null("WindIndicator")
		else:
			# Fall back to Panel hierarchy
			var panel = wind_widget.get_node_or_null("Panel")
			if panel:
				if not wind_label:
					wind_label = panel.get_node_or_null("Label")
				var viewport = panel.get_node_or_null("SubViewport")
				if viewport:
					wind_indicator = viewport.get_node_or_null("WindIndicator")
			else:
				# Try direct SubViewport child (old structure)
				var viewport = wind_widget.get_node_or_null("SubViewport")
				if viewport:
					wind_indicator = viewport.get_node_or_null("WindIndicator")


func _update_wind_display() -> void:
	"""Update wind indicator based on hex_grid wind system"""
	# Re-acquire hex_grid if lost (e.g. scene reload or new hole)
	if not hex_grid or not is_instance_valid(hex_grid):
		_find_references()
		if not hex_grid:
			return
		
	if not wind_widget:
		_setup_wind_display()
		if not wind_widget:
			return
	
	# Get wind system from hex_grid
	var wind_system = hex_grid.get("wind_system")
	
	if not wind_system:
		wind_widget.visible = false
		return
	
	# Update wind label
	var enabled = wind_system.get("enabled")
	
	# ALWAYS show the widget, even if calm (unless the tray has it)
	wind_widget.visible = show_wind_widget
	
	if enabled:
		if wind_label:
			wind_label.text = wind_system.call("get_display_text")
		
		# Update wind indicator (3D flag)
		if wind_indicator:
			wind_indicator.visible = true
			
			# Rotate indicator to show wind direction RELATIVE to camera view
			# Wind rotation (0=N) is where wind comes FROM.
			# Flag should point where wind goes TO (opposite direction, +PI).
			# Note: wind_system indices are clockwise (N->NE), but 3D rotation is CCW.
			# So we negate wind_rotation to map N->NE to negative rotation.
			var wind_rotation = wind_system.call("get_arrow_rotation")
			
			# Camera rotation moves opposite to orbit yaw (Yaw increases CCW, Cam Rot decreases CW)
			# So we ADD camera_yaw to compensate.
			var relative_rotation = (-wind_rotation + PI) + camera_yaw
			
			wind_indicator.rotation.y = relative_rotation
			
			# Adjust shader parameters based on wind speed
			var mesh_instance = wind_indicator.get_node_or_null("MeshInstance3D")
			if mesh_instance:
				# Try material_override first, then the mesh's surface material
				var material = mesh_instance.material_override
				if not material:
					material = mesh_instance.get_active_material(0)
				
				if material and material is ShaderMaterial:
					var speed = wind_system.get("speed_kmh")
					if speed == null: speed = 0.0
					
					# Wave Size: 0.0 to 1.5 based on speed (0-40 km/h)
					var wave_size = lerp(0.0, 1.5, clamp(speed / 40.0, 0.0, 1.0))
					material.set_shader_parameter("wave_size", wave_size)
					
					# Time Scale: Faster animation with higher speed
					var speed_factor = speed / 20.0
					material.set_shader_parameter("time_scale", Vector2(0.3 + (0.3 * speed_factor), 0.0))
	else:
		# Calm conditions
		if wind_label:
			wind_label.text = "Calm"
		
		# Show flag but make it still
		if wind_indicator:
			wind_indicator.visible = true
			var mesh_instance = wind_indicator.get_node_or_null("MeshInstance3D")
			if mesh_instance:
				var material = mesh_instance.material_override
				if not material:
					material = mesh_instance.get_active_material(0)
				if material and material is ShaderMaterial:
					material.set_shader_parameter("wave_size", 0.0)
					material.set_shader_parameter("time_scale", Vector2(0.1, 0.0))
