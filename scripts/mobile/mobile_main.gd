extends Node3D
class_name MobileMain

@onready var hole: MobileHoleGenerator = $MobileHoleGenerator
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	if hole and hole.has_signal("hole_generated") and not hole.hole_generated.is_connected(_on_hole_generated):
		hole.hole_generated.connect(_on_hole_generated)
	# If already generated (regenerate_on_ready), frame on next idle.
	call_deferred("_frame_existing")

func _frame_existing() -> void:
	if hole and hole.get_hole_data().size() > 0:
		_on_hole_generated(hole.get_hole_data())

func _on_hole_generated(hole_data: Dictionary) -> void:
	if camera == null or hole == null:
		return

	var tee: Vector2i = hole_data.get("tee_tile", Vector2i(0, 0))
	var green: Vector2i = hole_data.get("green_center_tile", Vector2i(0, 0))
	
	# Get world positions
	var tee_world := hole.grid_to_world(tee)
	var green_world := hole.grid_to_world(green)
	
	# Use the orbit camera controller if available
	if camera.has_method("set_look_direction"):
		camera.set_look_direction(tee_world, green_world)
	else:
		# Fallback: position camera to view center of hole
		var center := (tee_world + green_world) * 0.5
		var tee_to_green := green_world - tee_world
		var hole_dir := tee_to_green.normalized()
		var hole_length := tee_to_green.length()
		var cam_height := hole_length * 0.6
		
		var cam_pos := center + Vector3(0, cam_height, -hole_length * 0.3)
		
		camera.global_position = cam_pos
		camera.look_at(center, Vector3.UP)
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 45.0


func _on_regenerate_pressed() -> void:
	if hole:
		hole.seed_value = -1  # Random new seed
		hole.regenerate()
