extends Node
class_name PuttingSystem

## Simplified Putting System
## - Click a tile to aim
## - Click and hold to charge power
## - Release to putt
## - Ball rolls toward target with slope influence

signal putting_mode_entered()
signal putting_mode_exited()
signal putt_started(target_tile: Vector2i, power: float)
signal putt_completed(final_tile: Vector2i)

# References
var hex_grid: Node = null
var golf_ball: Node3D = null
var hole_viewer: Node = null

# State
var is_putting_mode: bool = false
var aim_tile: Vector2i = Vector2i(-1, -1)
var is_charging: bool = false
var charge_power: float = 0.0
var charge_start_time: float = 0.0

# Ball rolling
var ball_velocity: Vector3 = Vector3.ZERO
var is_ball_rolling: bool = false

# Constants
const PUTT_SPEED: float = 4.0  # Base speed multiplier
const FRICTION: float = 2.5
const SLOPE_FORCE: float = 2.0
const MIN_VELOCITY: float = 0.05

# Visuals
var aim_marker: MeshInstance3D = null
var power_bar: MeshInstance3D = null


func _ready() -> void:
	set_process(false)


func setup(grid: Node, viewer: Node) -> void:
	hex_grid = grid
	hole_viewer = viewer


func _process(delta: float) -> void:
	if is_charging:
		_update_charge()
	
	if is_ball_rolling:
		_update_rolling(delta)


func enter_putting_mode() -> void:
	if is_putting_mode:
		return
	
	is_putting_mode = true
	set_process(true)
	aim_tile = Vector2i(-1, -1)
	is_charging = false
	
	_create_visuals()
	
	# Find green center (use flag position)
	var green_center = Vector2i(0, 0)
	if hex_grid and hex_grid.flag_position.x >= 0:
		green_center = hex_grid.flag_position
	
	if hole_viewer and hole_viewer.has_method("enter_putting_mode"):
		hole_viewer.enter_putting_mode(green_center, Rect2i())
	
	print("PUTTING MODE ON - centered on: ", green_center)
	putting_mode_entered.emit()


func exit_putting_mode() -> void:
	if not is_putting_mode:
		return
	
	is_putting_mode = false
	set_process(false)
	
	_clear_visuals()
	
	if hole_viewer and hole_viewer.has_method("exit_putting_mode"):
		hole_viewer.exit_putting_mode()
	
	print("PUTTING MODE OFF")
	putting_mode_exited.emit()


func _create_visuals() -> void:
	_clear_visuals()
	
	# Safety check - need hex_grid to add children
	if hex_grid == null or not is_instance_valid(hex_grid):
		print("PuttingSystem: Cannot create visuals - no hex_grid")
		return
	
	# Aim marker - simple cylinder
	aim_marker = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 0.05
	aim_marker.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aim_marker.material_override = mat
	aim_marker.visible = false
	hex_grid.add_child(aim_marker)
	
	# Power bar
	power_bar = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.1, 0.1)
	power_bar.mesh = box
	var mat2 = StandardMaterial3D.new()
	mat2.albedo_color = Color(0, 1, 0, 0.9)
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	power_bar.material_override = mat2
	power_bar.visible = false
	hex_grid.add_child(power_bar)
	
	print("PuttingSystem: Visuals created")


func _clear_visuals() -> void:
	if aim_marker and is_instance_valid(aim_marker):
		aim_marker.queue_free()
		aim_marker = null
	if power_bar and is_instance_valid(power_bar):
		power_bar.queue_free()
		power_bar = null


# Handle input from hole_viewer
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Click down - get tile from hole_viewer's hover detection
			var tile = _get_hovered_tile()
			if tile.x >= 0:
				on_tile_clicked(tile)
		else:
			# Click released - execute putt
			on_click_released()


func _get_hovered_tile() -> Vector2i:
	"""Get the tile under the mouse using hole_viewer's detection"""
	if hole_viewer and "hovered_tile" in hole_viewer:
		var tile = hole_viewer.hovered_tile
		print("PuttingSystem: hovered_tile = ", tile)
		if tile.x != -999:
			return tile
	else:
		print("PuttingSystem: No hole_viewer or hovered_tile")
	return Vector2i(-1, -1)


# Called by hole_viewer when mouse clicks
func on_tile_clicked(tile: Vector2i) -> void:
	if not is_putting_mode or is_ball_rolling:
		return
	
	if aim_tile.x < 0:
		# First click - set aim
		aim_tile = tile
		_show_aim_marker(tile)
		print("AIM SET: ", tile)
	else:
		# Already aiming - start charge on this click
		is_charging = true
		charge_start_time = Time.get_ticks_msec() / 1000.0
		charge_power = 0.0
		if power_bar:
			power_bar.visible = true
		print("CHARGING...")


func on_click_released() -> void:
	if not is_putting_mode:
		return
	
	if is_charging:
		is_charging = false
		if power_bar:
			power_bar.visible = false
		_execute_putt()


func cancel_aim() -> void:
	aim_tile = Vector2i(-1, -1)
	is_charging = false
	if aim_marker:
		aim_marker.visible = false
	if power_bar:
		power_bar.visible = false


func _show_aim_marker(tile: Vector2i) -> void:
	if aim_marker == null or hex_grid == null:
		return
	var pos = hex_grid.get_tile_world_position(tile)
	aim_marker.position = Vector3(pos.x, pos.y + 0.55, pos.z)
	aim_marker.visible = true


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
	power_bar.position = Vector3(bp.x, bp.y + 1.2, bp.z)
	
	# Scale width by power
	power_bar.scale.x = 0.2 + charge_power * 1.5
	
	# Color: green -> yellow -> red
	var mat = power_bar.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(charge_power, 1.0 - charge_power * 0.5, 0.1, 0.9)


func _execute_putt() -> void:
	if golf_ball == null or hex_grid == null or aim_tile.x < 0:
		print("Cannot putt - missing data")
		return
	
	print("PUTT! Power: %.0f%%" % [charge_power * 100])
	
	# Emit signal before starting
	putt_started.emit(aim_tile, charge_power)
	
	# Get positions
	var ball_pos = golf_ball.global_position
	var target_pos = hex_grid.get_tile_world_position(aim_tile)
	
	# Direction from ball to target (XZ plane)
	var dir = Vector3(target_pos.x - ball_pos.x, 0, target_pos.z - ball_pos.z)
	var dist = dir.length()
	if dist > 0.01:
		dir = dir.normalized()
	else:
		dir = Vector3(0, 0, 1)
	
	# Speed based on power (higher power = faster = goes further)
	var speed = (0.5 + charge_power * 1.5) * PUTT_SPEED
	ball_velocity = dir * speed
	
	print("Dir: ", dir, " Speed: ", speed)
	
	# Start rolling
	is_ball_rolling = true
	
	# Hide aim marker
	if aim_marker:
		aim_marker.visible = false
	
	# Reset aim for next putt
	aim_tile = Vector2i(-1, -1)


func _update_rolling(delta: float) -> void:
	if golf_ball == null or hex_grid == null:
		is_ball_rolling = false
		return
	
	# Get current tile for slope
	var current_tile = hex_grid.world_to_grid(golf_ball.global_position)
	
	# Apply slope influence
	var slope = _get_slope(current_tile)
	ball_velocity.x += slope.x * SLOPE_FORCE * delta
	ball_velocity.z += slope.y * SLOPE_FORCE * delta
	
	# Apply friction
	var speed = ball_velocity.length()
	if speed > 0:
		var friction_amount = FRICTION * delta
		speed = max(0, speed - friction_amount)
		ball_velocity = ball_velocity.normalized() * speed if speed > 0 else Vector3.ZERO
	
	# Move ball
	var new_pos = golf_ball.global_position + ball_velocity * delta
	
	# Get ground height at new position
	var new_tile = hex_grid.world_to_grid(new_pos)
	if new_tile.x >= 0 and new_tile.x < hex_grid.grid_width and new_tile.y >= 0 and new_tile.y < hex_grid.grid_height:
		var ground_y = hex_grid.get_elevation(new_tile.x, new_tile.y) + 0.65
		new_pos.y = ground_y
		
		# Check for hole
		if new_tile == hex_grid.flag_position:
			print("IN THE HOLE!")
			is_ball_rolling = false
			ball_velocity = Vector3.ZERO
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
		print("Ball stopped")
		
		var final_tile = hex_grid.world_to_grid(golf_ball.global_position)
		putt_completed.emit(final_tile)


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
