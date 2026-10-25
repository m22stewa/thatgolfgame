extends Node3D
class_name ChipModel

## ChipModel - A casino chip standing on its edge, built from primitives: a
## red body, a cream ring on both faces round a red centre, and cream spots
## around the rim. The chip collectable on the course (coin.tscn) and on
## puzzle greens (GreenOverlay); it spins about Y with whatever holds it.

const RED := Color(0.72, 0.1, 0.12)  # ScorecardStyle.CHIP
const CREAM := Color(0.96, 0.94, 0.87)
const RIM_SPOTS := 6

@export var radius := 0.25
@export var thickness := 0.06


func _ready() -> void:
	var red := _material(RED)
	var cream := _material(CREAM)
	var chip := Node3D.new()
	chip.rotation.x = PI / 2.0  # stand it on its edge, faces front and back
	add_child(chip)
	chip.add_child(_disc(radius, thickness, red))
	chip.add_child(_disc(radius * 0.72, thickness * 1.04, cream))
	chip.add_child(_disc(radius * 0.56, thickness * 1.08, red))
	for i in range(RIM_SPOTS):
		var a := TAU * i / RIM_SPOTS
		var box := BoxMesh.new()
		box.size = Vector3(radius * 0.3, thickness * 1.03, radius * 0.16)
		var spot := MeshInstance3D.new()
		spot.mesh = box
		spot.material_override = cream
		spot.position = Vector3(cos(a), 0.0, sin(a)) * radius * 0.92
		spot.rotation.y = -(a + PI / 2.0)  # long side along the rim
		chip.add_child(spot)


func _disc(r: float, h: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.45
	mat.emission_enabled = true
	mat.emission = color * 0.25  # reads from far up the hole
	return mat
