extends Node3D
class_name TargetMarker

@onready var label: Label3D = $Label3D
@onready var mesh: MeshInstance3D = $MeshInstance3D

func set_distance(yards: int) -> void:
	if label:
		label.text = "%d yds" % yards

func set_color(color: Color) -> void:
	if mesh:
		# Try to get the material override first
		var mat = mesh.material_override
		if not mat:
			# Or the surface override
			mat = mesh.get_surface_override_material(0)
		
		if mat and mat is StandardMaterial3D:
			mat.albedo_color = color
