extends Node
class_name PuttingSystem

## New Putting System
## - Circle around ball with arrow following mouse
## - Arrow indicates aim direction
## - Click to set power and putt

signal putting_mode_entered()
signal putting_mode_exited()
signal putt_started(direction: Vector3, power: float)
signal putt_completed(final_tile: Vector2i)

# References
var hex_grid: Node = null
var golf_ball: Node3D = null
var hole_viewer: Node = null
var camera: Camera3D = null

# State
var is_putting_mode: bool = false
var aim_direction: Vector3 = Vector3.FORWARD  # Direction arrow is pointing
var is_charging: bool = false
var charge_power: float = 0.0
var charge_start_time: float = 0.0
var putt_start_tile: Vector2i = Vector2i(-1, -1)  # Where ball was when putt started

# Ball rolling
var ball_velocity: Vector3 = Vector3.ZERO
var is_ball_rolling: bool = false

# Constants
const PUTT_BASE_DISTANCE: float = 20.0  # Base putter distance in yards
const PUTT_SPEED: float = 10.0  # Speed multiplier - at 100% power, ball travels ~10 tiles
const FRICTION: float = 2.0  # Friction on green
const FRICTION_OFF_GREEN: float = 12.0  # Much higher friction off green (rough, fringe)
const SLOPE_FORCE: float = 10.0  # Substantial slope effect on ball
const MIN_VELOCITY: float = 0.05
const CIRCLE_RADIUS: float = 0.5  # Radius of aim circle around ball
const ARROW_LENGTH: float = 1.0  # Length of aim arrow

# Visuals
var aim_circle: MeshInstance3D = null
var aim_arrow: MeshInstance3D = null
var ball_outline: MeshInstance3D = null  # Black outline tight around ball
var power_bar: MeshInstance3D = null


func _ready() -> void:
	set_process(false)
	set_process_input(false)


func setup(grid: Node, viewer: Node) -> void:
	hex_grid = grid
	hole_viewer = viewer
	# Find camera - hole_viewer has camera as property
	if hole_viewer and "camera" in hole_viewer and hole_viewer.camera:
		camera = hole_viewer.camera
	elif hex_grid:
		camera = hex_grid.get_viewport().get_camera_3d()


func _process(delta: float) -> void:
	if is_putting_mode and not is_ball_rolling:
		_update_arrow_direction()
	
	if is_charging:
		_update_charge()
	
	if is_ball_rolling:
		_update_rolling(delta)
	
	# Keep visuals positioned on ball
	_update_visuals_position()


func enter_putting_mode() -> void:
	if is_putting_mode:
		return
	
	is_putting_mode = true
	set_process(true)
	# Don't enable global input - input is handled via hole_viewer.handle_input()
	# set_process_input(true)
	is_charging = false
	charge_power = 0.0
	
	_create_visuals()
	
	# Hide the target highlight from regular shot mode
	if hex_grid:
		if hex_grid.target_highlight_mesh:
			hex_grid.target_highlight_mesh.visible = false
	
	# Find green center (use flag position)
	var green_center = Vector2i(0, 0)
	if hex_grid and hex_grid.flag_position.x >= 0:
		green_center = hex_grid.flag_position
	
	if hole_viewer and hole_viewer.has_method("enter_putting_mode"):
		hole_viewer.enter_putting_mode(green_center, Rect2i())
	
	# Update club display to show Putter
	if hex_grid and hex_grid.shot_ui and hex_grid.shot_ui.has_method("set_putting_club"):
		hex_grid.shot_ui.set_putting_club(int(PUTT_SPEED))
	
	putting_mode_entered.emit()


func exit_putting_mode() -> void:
	if not is_putting_mode:
		return
	
	is_putting_mode = false
	set_process(false)
	set_process_input(false)
	
	_clear_visuals()
	
	if hole_viewer and hole_viewer.has_method("exit_putting_mode"):
		hole_viewer.exit_putting_mode()
	
	putting_mode_exited.emit()


func _create_visuals() -> void:
	_clear_visuals()
	
	# Safety check - need hex_grid to add children
	if hex_grid == null or not is_instance_valid(hex_grid):
		return
	
	# --- OUTER RING (white, LARGER - creates the outer ring) ---
	ball_outline = MeshInstance3D.new()
	var outline_cyl = CylinderMesh.new()
	outline_cyl.top_radius = CIRCLE_RADIUS + 0.15  # Larger outer ring
	outline_cyl.bottom_radius = CIRCLE_RADIUS + 0.15
	outline_cyl.height = 0.05
	ball_outline.mesh = outline_cyl
	var outline_mat = StandardMaterial3D.new()
	outline_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)  # White
	outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_outline.material_override = outline_mat
	hex_grid.add_child(ball_outline)
	
	# --- INNER CIRCLE (black, SMALLER - sits on top, creating ring effect) ---
	aim_circle = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = CIRCLE_RADIUS + 0.05  # Smaller inner disc
	cylinder.bottom_radius = CIRCLE_RADIUS + 0.05
	cylinder.height = 0.06  # Slightly thicker so it's on top
	aim_circle.mesh = cylinder
	var circle_mat = StandardMaterial3D.new()
	circle_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)  # Black
	circle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_circle.material_override = circle_mat
	hex_grid.add_child(aim_circle)
	
	# --- AIM ARROW (points toward mouse) ---
	aim_arrow = MeshInstance3D.new()
	var arrow_mesh = _create_arrow_mesh()
	aim_arrow.mesh = arrow_mesh
	var arrow_mat = StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)  # White arrow
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_arrow.material_override = arrow_mat
	hex_grid.add_child(aim_arrow)
	
	# --- POWER BAR BACKGROUND (shows 100% mark) ---
	power_bar = MeshInstance3D.new()
	var bg_box = BoxMesh.new()
	bg_box.size = Vector3(1.5, 0.3, 0.08)  # Background - thinner
	power_bar.mesh = bg_box
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15, 0.15, 0.15, 1.0)  # Dark gray background
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	power_bar.material_override = bg_mat
	power_bar.visible = true  # Always visible for now
	hex_grid.add_child(power_bar)
	
	# --- POWER BAR FILL (grows with charge) ---
	var power_fill = MeshInstance3D.new()
	var fill_box = BoxMesh.new()
	fill_box.size = Vector3(1.5, 0.25, 0.1)  # Fill - in front
	power_fill.mesh = fill_box
	var fill_mat = StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.2, 0.9, 0.2, 1.0)  # Green fill
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	power_fill.material_override = fill_mat
	power_fill.name = "PowerFill"
	power_bar.add_child(power_fill)
	power_fill.position = Vector3(0, 0, 0.1)  # More in front of background


func _clear_visuals() -> void:
	if aim_circle and is_instance_valid(aim_circle):
		aim_circle.queue_free()
		aim_circle = null
	if aim_arrow and is_instance_valid(aim_arrow):
		aim_arrow.queue_free()
		aim_arrow = null
	if ball_outline and is_instance_valid(ball_outline):
		ball_outline.queue_free()
		ball_outline = null
	if power_bar and is_instance_valid(power_bar):
		power_bar.queue_free()
		power_bar = null


func _create_arrow_mesh() -> ArrayMesh:
	"""Create an arrow mesh pointing in +Z direction"""
	var arrow = ArrayMesh.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Arrow shaft (box from 0 to arrow_length - 0.4)
	var shaft_length = ARROW_LENGTH - 0.5
	var shaft_width = 0.15
	var shaft_height = 0.08
	
	# Shaft vertices (box)
	# Bottom face
	st.add_vertex(Vector3(-shaft_width, 0, 0))
	st.add_vertex(Vector3(shaft_width, 0, 0))
	st.add_vertex(Vector3(shaft_width, 0, shaft_length))
	st.add_vertex(Vector3(-shaft_width, 0, 0))
	st.add_vertex(Vector3(shaft_width, 0, shaft_length))
	st.add_vertex(Vector3(-shaft_width, 0, shaft_length))
	
	# Top face
	st.add_vertex(Vector3(-shaft_width, shaft_height, 0))
	st.add_vertex(Vector3(shaft_width, shaft_height, shaft_length))
	st.add_vertex(Vector3(shaft_width, shaft_height, 0))
	st.add_vertex(Vector3(-shaft_width, shaft_height, 0))
	st.add_vertex(Vector3(-shaft_width, shaft_height, shaft_length))
	st.add_vertex(Vector3(shaft_width, shaft_height, shaft_length))
	
	# Arrow head (triangle pointing forward)
	var head_start = shaft_length
	var head_end = ARROW_LENGTH
	var head_width = 0.35
	
	# Top face of arrow head
	st.add_vertex(Vector3(-head_width, shaft_height, head_start))
	st.add_vertex(Vector3(0, shaft_height, head_end))
	st.add_vertex(Vector3(head_width, shaft_height, head_start))
	
	# Bottom face of arrow head
	st.add_vertex(Vector3(-head_width, 0, head_start))
	st.add_vertex(Vector3(head_width, 0, head_start))
	st.add_vertex(Vector3(0, 0, head_end))
	
	st.generate_normals()
	return st.commit()


func _update_visuals_position() -> void:
	"""Keep circle and arrow centered on ball"""
	if golf_ball == null:
		return
	
	var ball_pos = golf_ball.global_position
	var y_offset = 0.15  # Slightly above ground
	
	# Ball outline stays tight around ball - slightly higher than circle for visibility
	if ball_outline and is_instance_valid(ball_outline):
		# Black outline at base level
		ball_outline.global_position = Vector3(ball_pos.x, ball_pos.y + y_offset, ball_pos.z)
	
	if aim_circle and is_instance_valid(aim_circle):
		# White circle slightly higher so it sits on top of black outline
		aim_circle.global_position = Vector3(ball_pos.x, ball_pos.y + y_offset + 0.02, ball_pos.z)
	
	if aim_arrow and is_instance_valid(aim_arrow):
		# Position arrow at edge of circle, pointing outward
		var arrow_start = ball_pos + aim_direction * CIRCLE_RADIUS
		aim_arrow.global_position = Vector3(arrow_start.x, ball_pos.y + y_offset, arrow_start.z)
		
		# Rotate arrow to point in aim direction using atan2
		if aim_direction.length() > 0.01:
			# Calculate Y rotation to face aim direction
			var angle = atan2(aim_direction.x, aim_direction.z)
			aim_arrow.rotation = Vector3(0, angle, 0)


func _update_arrow_direction() -> void:
	"""Update arrow to point toward mouse position on ground plane"""
	if golf_ball == null:
		return
	if camera == null:
		# Try to get camera again
		if hole_viewer and "camera" in hole_viewer:
			camera = hole_viewer.camera
		if camera == null:
			camera = golf_ball.get_viewport().get_camera_3d()
		if camera == null:
			return
	
	var mouse_pos = golf_ball.get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	# Intersect with ground plane at ball's Y height
	var ball_y = golf_ball.global_position.y
	if abs(ray_dir.y) > 0.001:
		var t = (ball_y - ray_origin.y) / ray_dir.y
		if t > 0:
			var hit_point = ray_origin + ray_dir * t
			var dir = hit_point - golf_ball.global_position
			dir.y = 0
			if dir.length() > 0.1:
				aim_direction = dir.normalized()


func _input(event: InputEvent) -> void:
	if not is_putting_mode or is_ball_rolling:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start charging
			is_charging = true
			charge_start_time = Time.get_ticks_msec() / 1000.0
			charge_power = 0.01  # Start with small value so bar is visible
		else:
			# Release - execute putt
			if is_charging:
				is_charging = false
				_execute_putt()


# Handle input from hole_viewer (legacy support)
func handle_input(event: InputEvent) -> void:
	_input(event)


func _update_charge() -> void:
	var elapsed = Time.get_ticks_msec() / 1000.0 - charge_start_time
	# Oscillate: 0 -> 1 -> 0 over ~1.5 seconds
	var t = fmod(elapsed, 1.5) / 0.75
	if t <= 1.0:
		charge_power = t
	else:
		charge_power = 2.0 - t
	
	_update_power_bar()


func _update_power_bar() -> void:
	if power_bar == null or golf_ball == null:
		return
	
	# Position above ball
	var bp = golf_ball.global_position
	power_bar.global_position = Vector3(bp.x, bp.y + 1.5, bp.z)
	
	# Get the fill child
	var power_fill = power_bar.get_node_or_null("PowerFill")
	if power_fill == null:
		return
	
	# Scale fill width by power (0.01 to 1.0 = 0% to 100%)
	var min_scale = 0.02
	power_fill.scale.x = max(min_scale, charge_power)
	
	# Offset fill so it grows from left edge
	# At scale 1.0, position.x = 0 (centered)
	# At scale 0.5, position.x = -0.375 (shifted left)
	var bar_width = 1.5  # Full width of bar
	power_fill.position.x = -(bar_width / 2.0) * (1.0 - power_fill.scale.x)
	
	# Color: green at low power -> yellow at mid -> red at high
	var mat = power_fill.material_override as StandardMaterial3D
	if mat:
		if charge_power < 0.5:
			# Green to yellow (0-50%)
			var t = charge_power * 2.0
			mat.albedo_color = Color(t, 0.9, 0.2, 1.0)
		else:
			# Yellow to red (50-100%)
			var t = (charge_power - 0.5) * 2.0
			mat.albedo_color = Color(1.0, 0.9 - t * 0.7, 0.2 - t * 0.2, 1.0)


func _execute_putt() -> void:
	if golf_ball == null or hex_grid == null:
		return
	
	# Record where putt started (for water hazard return)
	putt_start_tile = hex_grid.world_to_grid(golf_ball.global_position)
	
	# Emit signal before starting
	putt_started.emit(aim_direction, charge_power)
	
	# Speed based on power (higher power = faster = goes further)
	# Power ranges 0-1, max distance at 100% power
	var speed = charge_power * PUTT_SPEED
	# Ball goes in the direction the arrow is pointing
	ball_velocity = aim_direction * speed
	
	# Start rolling
	is_ball_rolling = true
	
	# Hide aim visuals while rolling
	if aim_circle:
		aim_circle.visible = false
	if aim_arrow:
		aim_arrow.visible = false
	if ball_outline:
		ball_outline.visible = false


func _update_rolling(delta: float) -> void:
	if golf_ball == null or hex_grid == null:
		is_ball_rolling = false
		return
	
	# Get current tile for slope
	var current_tile = hex_grid.world_to_grid(golf_ball.global_position)
	
	# Check if ball is on green or off green for friction
	var current_surface = hex_grid.get_cell(current_tile.x, current_tile.y)
	var is_on_green = (current_surface == hex_grid.SurfaceType.GREEN or current_surface == hex_grid.SurfaceType.FLAG)
	
	# Apply slope influence
	var slope = _get_slope(current_tile)
	ball_velocity.x += slope.x * SLOPE_FORCE * delta
	ball_velocity.z += slope.y * SLOPE_FORCE * delta
	
	# Apply friction - much higher when off the green
	var current_friction = FRICTION if is_on_green else FRICTION_OFF_GREEN
	var speed = ball_velocity.length()
	if speed > 0:
		var friction_amount = current_friction * delta
		speed = max(0, speed - friction_amount)
		ball_velocity = ball_velocity.normalized() * speed if speed > 0 else Vector3.ZERO
	
	# Move ball
	var new_pos = golf_ball.global_position + ball_velocity * delta
	
	# Get ground height at new position
	var new_tile = hex_grid.world_to_grid(new_pos)
	
	# Check if ball rolled into water - handle immediately
	var tile_surface = hex_grid.get_cell(new_tile.x, new_tile.y)
	if tile_surface == hex_grid.SurfaceType.WATER:
		is_ball_rolling = false
		ball_velocity = Vector3.ZERO
		_handle_putt_water_hazard()
		return
	
	if new_tile.x >= 0 and new_tile.x < hex_grid.grid_width and new_tile.y >= 0 and new_tile.y < hex_grid.grid_height:
		var ground_y = hex_grid.get_elevation(new_tile.x, new_tile.y) + 0.65
		new_pos.y = ground_y
		
		# Check for hole - ball must be close to hole center and slow enough
		if new_tile == hex_grid.flag_position:
			var hole_world_pos = hex_grid.get_tile_surface_position(hex_grid.flag_position)
			var dist_to_hole_center = Vector2(new_pos.x - hole_world_pos.x, new_pos.z - hole_world_pos.z).length()
			var hole_radius = 0.5  # Radius of the hole (slightly larger for easier drop)
			
			# Ball must be over hole (within ~90% of radius) and slow enough to fall in
			if dist_to_hole_center < hole_radius * 0.9 and ball_velocity.length() < 4.0:
				is_ball_rolling = false
				ball_velocity = Vector3.ZERO
				# Animate ball falling into hole
				await _animate_ball_into_hole(hole_world_pos)
				hex_grid._trigger_hole_complete()
				return
	
	golf_ball.global_position = new_pos
	
	# Spin the ball
	if speed > 0.1:
		var spin_axis = ball_velocity.cross(Vector3.UP).normalized()
		if spin_axis.length() > 0.1:
			golf_ball.rotate(spin_axis, speed * delta * 3.0)
	
	# Check if stopped
	if ball_velocity.length() < MIN_VELOCITY:
		is_ball_rolling = false
		ball_velocity = Vector3.ZERO
		
		var final_tile = hex_grid.world_to_grid(golf_ball.global_position)
		var final_surface = hex_grid.get_cell(final_tile.x, final_tile.y)
		
		# Check if ball rolled into water
		if final_surface == hex_grid.SurfaceType.WATER:
			_handle_putt_water_hazard()
			return
		
		# Check if ball is still on green
		var still_on_green = (final_surface == hex_grid.SurfaceType.GREEN or final_surface == hex_grid.SurfaceType.FLAG)
		
		if still_on_green:
			# Show aim visuals again for next putt
			if aim_circle:
				aim_circle.visible = true
			if aim_arrow:
				aim_arrow.visible = true
			if ball_outline:
				ball_outline.visible = true
		else:
			# Ball went off green - exit putting mode and return to normal shot mode
			exit_putting_mode()
			# Trigger camera reset and normal shot mode via hex_grid
			if hex_grid and hex_grid.has_method("_start_new_shot"):
				hex_grid._start_new_shot()
		
		putt_completed.emit(final_tile)


func _handle_putt_water_hazard() -> void:
	"""Handle ball rolling into water during putting - show rain, add penalty, return ball"""
	if hex_grid == null or golf_ball == null:
		return
	
	# Show rain/water effect overlay if hex_grid has one
	if hex_grid.water_effect:
		hex_grid.water_effect.color = Color(1, 1, 1, 0)  # Start transparent
		hex_grid.water_effect.visible = true
		var fade_in = create_tween()
		fade_in.tween_property(hex_grid.water_effect, "color:a", 1.0, 0.3)
	
	# Wait a moment for effect
	await get_tree().create_timer(0.5).timeout
	
	# Return ball to where putt started (on the green)
	if putt_start_tile.x >= 0:
		var return_pos = hex_grid.get_tile_surface_position(putt_start_tile)
		golf_ball.global_position = return_pos
	
	# Add penalty stroke (+1)
	if hex_grid.run_state:
		hex_grid.run_state.record_stroke(0)  # Penalty stroke with 0 score bonus
		# Update UI with new stroke count
		if hex_grid.shot_ui:
			var dist_to_flag = 0
			if hex_grid.flag_position.x >= 0:
				var ball_tile = hex_grid.world_to_grid(golf_ball.global_position)
				dist_to_flag = hex_grid._calculate_distance_yards(ball_tile, hex_grid.flag_position)
			hex_grid.shot_ui.update_shot_info(hex_grid.run_state.strokes_this_hole, dist_to_flag)
	
	# Wait before fading out
	await get_tree().create_timer(0.3).timeout
	
	# Fade out water effect
	if hex_grid.water_effect:
		var fade_out = create_tween()
		fade_out.tween_property(hex_grid.water_effect, "color:a", 0.0, 0.7)
		await fade_out.finished
		hex_grid.water_effect.visible = false
	
	# Show aim visuals again - ball is back on green for another putt
	if aim_circle:
		aim_circle.visible = true
	if aim_arrow:
		aim_arrow.visible = true
	if ball_outline:
		ball_outline.visible = true
	
	putt_completed.emit(putt_start_tile)


func _get_slope(tile: Vector2i) -> Vector2:
	"""Get slope direction (points downhill)"""
	if hex_grid == null:
		return Vector2.ZERO
	
	var center_elev = hex_grid.get_elevation(tile.x, tile.y)
	var slope = Vector2.ZERO
	
	# Check neighbors
	var offsets = [
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(0, -1), Vector2i(0, 1)
	]
	
	for off in offsets:
		var nx = tile.x + off.x
		var ny = tile.y + off.y
		if nx >= 0 and nx < hex_grid.grid_width and ny >= 0 and ny < hex_grid.grid_height:
			var n_elev = hex_grid.get_elevation(nx, ny)
			var diff = center_elev - n_elev  # Positive = downhill toward neighbor
			slope.x += off.x * diff
			slope.y += off.y * diff
	
	return slope


func _animate_ball_into_hole(hole_pos: Vector3) -> void:
	"""Animate ball shrinking and turning dark as it falls into the hole"""
	if golf_ball == null:
		return
	
	# Get original scale and material
	var original_scale = golf_ball.scale
	
	# Create tween for the animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Move ball to hole center
	tween.tween_property(golf_ball, "global_position", Vector3(hole_pos.x, hole_pos.y - 0.3, hole_pos.z), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Shrink ball
	tween.tween_property(golf_ball, "scale", original_scale * 0.1, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Darken ball (if it has a mesh with material)
	var mesh = golf_ball.get_node_or_null("MeshInstance3D")
	if mesh == null:
		mesh = golf_ball.get_node_or_null("BallMesh")
	if mesh and mesh is MeshInstance3D:
		var mat = mesh.get_surface_override_material(0)
		if mat == null and mesh.mesh:
			mat = mesh.mesh.surface_get_material(0)
		if mat:
			mat = mat.duplicate()
			mesh.set_surface_override_material(0, mat)
			tween.tween_property(mat, "albedo_color", Color(0.1, 0.1, 0.1, 1.0), 0.4)
	
	await tween.finished
	
	# Restore ball scale for next hole (it will be repositioned)
	golf_ball.scale = original_scale
