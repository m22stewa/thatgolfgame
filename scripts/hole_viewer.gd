extends Control
class_name HoleViewer

## Main hole viewing camera - 3/4 overhead perspective
## Handles panning, zooming, ball tracking, and tile selection

signal tile_clicked(tile_coords: Vector2i)
signal tile_hovered(tile_coords: Vector2i)

# Camera node references
var camera: Camera3D = null
var viewport: SubViewport = null
var viewport_container: SubViewportContainer = null

# Camera settings
@export var camera_height: float = 25.0
@export var camera_angle: float = 60.0  # Degrees from horizontal (90 = top-down, 45 = more angled)
@export var min_zoom: float = 10.0
@export var max_zoom: float = 50.0
@export var zoom_speed: float = 2.0
@export var pan_speed: float = 0.5
@export var follow_speed: float = 3.0  # How fast camera follows ball

# Camera state
var target_position: Vector3 = Vector3.ZERO  # Where camera is looking at (on ground plane)
var current_zoom: float = 25.0
var target_zoom: float = 25.0
var is_panning: bool = false
var pan_start_mouse: Vector2 = Vector2.ZERO
var pan_start_position: Vector3 = Vector3.ZERO

# Ball tracking
var ball_node: Node3D = null
var is_tracking_ball: bool = false
var ball_flight_complete: bool = true
var track_after_flight: bool = true

# Hole reference
var hex_grid: Node = null
var hole_bounds: Rect2 = Rect2()

# Mouse state
var hovered_tile: Vector2i = Vector2i(-999, -999)


func _ready() -> void:
	# Create the SubViewport structure
	_setup_viewport()
	
	# Find references after scene is ready
	call_deferred("_find_references")


func _setup_viewport() -> void:
	# Create SubViewportContainer (this Control will contain it)
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "ViewportContainer"
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
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
		print("HoleViewer: Sharing World3D with main scene")


func _find_references() -> void:
	# Find HexGrid - it's under HoleGenerator in the scene tree
	hex_grid = get_tree().current_scene.get_node_or_null("HoleGenerator/HexGrid")
	if hex_grid == null:
		hex_grid = get_tree().current_scene.get_node_or_null("HexGrid")
	if hex_grid == null:
		# Try finding it by searching all children
		hex_grid = _find_node_by_name(get_tree().current_scene, "HexGrid")
	
	if hex_grid:
		print("HoleViewer: Found HexGrid at ", hex_grid.get_path())
		_calculate_hole_bounds()
		_center_on_hole()
	else:
		print("HoleViewer: WARNING - Could not find HexGrid")
	
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
	
	if ball_node:
		print("HoleViewer: Found ball at ", ball_node.global_position)


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
	
	print("HoleViewer: Calculated hole bounds: ", hole_bounds)


func _center_on_hole() -> void:
	"""Center camera on the hole"""
	if hole_bounds.size.length() > 0:
		# Center on the hole (center x, but closer to the tee which is near the top/start of z)
		target_position = Vector3(
			hole_bounds.position.x + hole_bounds.size.x / 2,
			0,
			hole_bounds.position.y + hole_bounds.size.y * 0.4  # Slightly toward the tee
		)
		
		# Set zoom to fit hole width
		var max_dim = max(hole_bounds.size.x, hole_bounds.size.y * 0.6)
		target_zoom = clamp(max_dim * 0.8, min_zoom, max_zoom)
		current_zoom = target_zoom
		print("HoleViewer: Centered on hole, zoom = ", current_zoom)


func _process(delta: float) -> void:
	_handle_ball_tracking(delta)
	_smooth_camera_movement(delta)
	_update_camera_transform()
	_update_hovered_tile()


func _handle_ball_tracking(delta: float) -> void:
	"""Handle camera following the ball"""
	if not ball_node or not is_instance_valid(ball_node):
		_find_ball()
		return
	
	if is_tracking_ball and ball_flight_complete:
		# Smoothly move toward ball position
		var ball_pos = ball_node.global_position
		var target = Vector3(ball_pos.x, 0, ball_pos.z)
		target_position = target_position.lerp(target, delta * follow_speed)


func _smooth_camera_movement(delta: float) -> void:
	"""Smooth interpolation for zoom"""
	current_zoom = lerp(current_zoom, target_zoom, delta * 8.0)


func _update_camera_transform() -> void:
	"""Update camera position and rotation based on current state"""
	if not camera:
		return
	
	# Calculate camera position
	# Camera looks at target_position from an angle
	var angle_rad = deg_to_rad(camera_angle)
	var horizontal_dist = current_zoom * cos(angle_rad)
	var vertical_dist = current_zoom * sin(angle_rad)
	
	# Position camera behind and above the target (looking from south)
	var cam_pos = Vector3(
		target_position.x,
		vertical_dist,
		target_position.z + horizontal_dist
	)
	
	camera.global_position = cam_pos
	camera.look_at(target_position, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	# Handle mouse input for panning and zooming
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			is_panning = true
			pan_start_mouse = event.position
			pan_start_position = target_position
		else:
			is_panning = false
	
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if event.pressed:
			target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
	
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.pressed:
			target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)
	
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_tile_click(event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_panning:
		# Calculate pan delta in world space
		var delta = event.position - pan_start_mouse
		
		# Scale by zoom level (pan more when zoomed out)
		var scale = current_zoom * pan_speed * 0.01
		
		# Apply pan (inverted for natural feel)
		target_position = pan_start_position + Vector3(
			-delta.x * scale,
			0,
			-delta.y * scale
		)
		
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
		else:
			print("HoleViewer: Clicked tile ", tile_coords)


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
			# Update hex_grid hover for highlighting
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
	if smooth:
		target_position = Vector3(world_pos.x, 0, world_pos.z)
	else:
		target_position = Vector3(world_pos.x, 0, world_pos.z)
		# Immediate update
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


func start_tracking_ball() -> void:
	"""Start following the ball"""
	is_tracking_ball = true
	ball_flight_complete = true


func stop_tracking_ball() -> void:
	"""Stop following the ball"""
	is_tracking_ball = false


func on_ball_flight_started() -> void:
	"""Called when ball starts flying - camera watches but doesn't follow yet"""
	ball_flight_complete = false
	# Could add camera behavior here like zooming out to see trajectory


func on_ball_flight_ended() -> void:
	"""Called when ball stops - camera can now smoothly move to ball"""
	ball_flight_complete = true
	if track_after_flight:
		is_tracking_ball = true


func reset_view() -> void:
	"""Reset camera to show entire hole"""
	_center_on_hole()
	is_tracking_ball = false


func get_viewport() -> SubViewport:
	"""Get the SubViewport for rendering"""
	return viewport


func add_to_viewport(node: Node3D) -> void:
	"""Add a 3D node to be rendered in this viewport"""
	if viewport:
		viewport.add_child(node)
