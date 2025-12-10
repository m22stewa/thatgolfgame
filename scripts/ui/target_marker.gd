extends Node3D
class_name TargetMarker

@onready var label: Label3D = $Label3D
@onready var mesh: MeshInstance3D = $MeshInstance3D

func set_distance(yards: int) -> void:
	if label:
		label.text = "%d yds" % yards


func set_distance_and_club(yards: int, club_name: String) -> void:
	"""Set both distance and club name on the marker"""
	if label:
		label.text = "%s\n%d yds" % [club_name, yards]


func set_club_name(club_name: String) -> void:
	"""Set just the club name (appends to existing text)"""
	if label:
		var current = label.text
		if "\n" in current:
			# Replace club name portion
			var parts = current.split("\n")
			label.text = "%s\n%s" % [club_name, parts[1]]
		else:
			label.text = "%s\n%s" % [club_name, current]

func set_color(color: Color) -> void:
	if mesh:
		# Try to get the material override first
		var mat = mesh.material_override
		if not mat:
			# Or the surface override
			mat = mesh.get_surface_override_material(0)
		
		if mat and mat is StandardMaterial3D:
			mat.albedo_color = color
