extends Control
class_name HoleViewer

## Main hole viewing camera - 3/4 overhead perspective
## Handles panning, zooming, rotating, ball tracking, and tile selection

signal tile_clicked(tile_coords: Vector2i)
signal tile_hovered(tile_coords: Vector2i)

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
var is_panning: bool = false
var is_rotating: bool = false
var pan_start_mouse: Vector2 = Vector2.ZERO
var pan_start_position: Vector3 = Vector3.ZERO
var pan_grab_world_pos: Vector3 = Vector3.ZERO  # World position where pan grab started
var rotation_start_mouse: Vector2 = Vector2.ZERO
var rotation_start_yaw: float = 0.0

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
var putting_system: Node = null
var normal_camera_angle: float = 55.0  # Store normal angle to restore
var normal_zoom: float = 40.0  # Store normal zoom to restore

# Putting mode camera settings
const PUTTING_CAMERA_ANGLE: float = 85.0  # Near top-down
const PUTTING_ZOOM: float = 20.0  # Closer zoom on green


func _ready() -> void:
	# Create the SubViewport structure
	_setup_viewport()
	
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
	"""Position camera to show hole - camera transform handles forward shift"""
	if hole_bounds.size.length() > 0:
		# Center on the hole's X, and start at the tee (low Z)
		target_position = Vector3(
			hole_bounds.position.x + hole_bounds.size.x / 2,
			0,
			hole_bounds.position.y  # Start at tee position
		)
		
		# Set zoom to show a good portion of the hole
		var max_dim = max(hole_bounds.size.x * 2, hole_bounds.size.y * 0.5)
		target_zoom = clamp(max_dim, min_zoom, max_zoom)
		current_zoom = target_zoom


func _process(delta: float) -> void:
	# Skip ball tracking in putting mode - camera stays fixed on green
	if not is_putting_mode:
		_handle_ball_tracking(delta)
	_smooth_camera_movement(delta)
	_update_camera_transform()
	_update_hovered_tile()
	_update_wind_display()


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
		# Move camera to ball position when it lands (not during flight)
		if is_tracking_ball:
			target_position = Vector3(ball_pos.x, 0, ball_pos.z)
	
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
	# Don't change zoom during flight - reduces calculations
	# Just mark that we're tracking
	is_tracking_ball = true


func _on_ball_flight_ended() -> void:
	"""Called when ball stops"""
	# Camera will snap to ball position in _handle_ball_tracking
	if track_after_flight:
		is_tracking_ball = true


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
	
	# Shift camera forward (positive Z) to put tee at bottom of view
	# This offset moves the camera's view forward toward the green
	var forward_shift = horizontal_dist * 0.5  # Shift forward by 50% of view distance
	
	var cam_pos = Vector3(
		target_position.x + offset_x,
		vertical_dist,
		target_position.z + offset_z + forward_shift
	)
	
	camera.global_position = cam_pos
	camera.look_at(Vector3(target_position.x, 0, target_position.z + forward_shift), Vector3.UP)


func _is_mouse_inside() -> bool:
	"""Check if mouse is inside the HoleViewer bounds"""
	var mouse_pos = get_global_mouse_position()
	var rect = get_global_rect()
	return rect.has_point(mouse_pos)


func _is_mouse_over_ui_control() -> bool:
	"""Check if mouse is over a UI control that should consume clicks (buttons, etc)"""
	var mouse_pos = get_global_mouse_position()
	
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
			
		# Check children recursively
		for child in control.get_children():
			if child is Control and child.visible:
				if _control_wants_input(child, mouse_pos):
					return true
	return false


func _input(event: InputEvent) -> void:
	# Always handle motion if we're already panning/rotating (even if mouse leaves bounds)
	if event is InputEventMouseMotion:
		if is_panning or is_rotating:
			_handle_mouse_motion(event)
			get_viewport().set_input_as_handled()
		return
	
	# For button events, check if mouse is inside our bounds
	if not _is_mouse_inside():
		return
	
	if event is InputEventMouseButton:
		# If we are currently dragging/rotating, we own the mouse interaction
		# and must handle the release event regardless of UI
		var is_interacting = is_panning or is_rotating
		
		if not is_interacting:
			# If not interacting, check if UI wants this event (Press OR Release)
			if _is_mouse_over_ui_control():
				return

		_handle_mouse_button(event)
		get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# In putting mode, handle differently
	if is_putting_mode:
		_handle_putting_mouse_button(event)
		return
	
	# Middle mouse = rotate
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			is_rotating = true
			rotation_start_mouse = event.position
			rotation_start_yaw = target_yaw
		else:
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
	
	# Left click = select tile
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_tile_click(event.position)


func _handle_putting_mouse_button(event: InputEventMouseButton) -> void:
	"""Handle mouse input during putting mode"""
	# Right click in putting mode = cancel aim
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and putting_system:
			putting_system.cancel_aim()
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
	if is_rotating:
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


func _handle_tile_click(screen_pos: Vector2) -> void:
	"""Handle clicking on the viewport to select a tile"""
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
	"""Reset camera to show the ball with default rotation"""
	target_yaw = 0.0
	is_tracking_ball = true
	if ball_node and is_instance_valid(ball_node):
		center_on_ball(true)
	else:
		_center_on_hole()


func look_at_flag() -> void:
	"""Rotate camera to look toward the flag/hole"""
	if hex_grid and "flag_position" in hex_grid:
		var flag_pos = hex_grid.flag_position
		var ball_pos = target_position
		if ball_node and is_instance_valid(ball_node):
			ball_pos = Vector3(ball_node.global_position.x, 0, ball_node.global_position.z)
		
		# Calculate angle from ball to flag
		var dir = flag_pos - ball_pos
		target_yaw = atan2(dir.x, dir.z)


func get_hole_viewport() -> SubViewport:
	"""Get the SubViewport for rendering"""
	return viewport


func add_to_viewport(node: Node3D) -> void:
	"""Add a 3D node to be rendered in this viewport"""
	if viewport:
		viewport.add_child(node)


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
		wind_label = wind_widget.get_node_or_null("Label")
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
	
	# ALWAYS show the widget, even if calm
	wind_widget.visible = true
	
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
