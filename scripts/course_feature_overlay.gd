extends Node3D
class_name CourseFeatureOverlay

## CourseFeatureOverlay - Draws CourseFeatures on the course hexes: glossy ice,
## flickering fire, scorched ground, sprinkler heads with a chevron showing
## which way they knock the ball, wind tunnels (hoops over a tinted run with
## chevrons along it) and trampolines. Rebuilt whenever the features change
## (fire spreading).

const LIFT := 0.035
const HEX_RADIUS := 0.92

var _flames: Array = []  # [{node, phase}] flame cones, flickered in _process
var _time := 0.0


func show_features(features: CourseFeatures, hole) -> void:
	for c in get_children():
		c.queue_free()
	_flames.clear()
	if features == null:
		return
	for cell in features.tiles:
		var f: Dictionary = features.tiles[cell]
		var at: Vector3 = hole.get_tile_world_position(cell)
		at.y += hole.TILE_SURFACE_OFFSET + LIFT
		match f.kind:
			"ice":
				_add_hex(at, _ice_material())
				_add_frost(at, cell)
			"fire":
				_add_hex(at, _flat(Color(1.0, 0.42, 0.08, 0.75), true))
				_add_flames(at, cell)
			"scorched":
				_add_hex(at, _flat(Color(0.12, 0.1, 0.09, 0.8), false))
			"sprinkler":
				_add_sprinkler(at, cell, f.dir, hole)
			"tunnel":
				_add_tunnel(at, cell, f.dir, hole)
			"trampoline":
				_add_trampoline(at)


func _process(delta: float) -> void:
	if _flames.is_empty():
		return
	_time += delta
	for fl in _flames:
		var node: Node3D = fl.node
		if is_instance_valid(node):
			var s := 1.0 + 0.25 * sin(_time * 9.0 + fl.phase) + 0.1 * sin(_time * 23.0 + fl.phase * 2.0)
			node.scale = Vector3(1.0, s, 1.0)


func _add_hex(at: Vector3, mat: Material) -> void:
	var hex := CylinderMesh.new()
	hex.top_radius = HEX_RADIUS
	hex.bottom_radius = HEX_RADIUS
	hex.height = 0.02
	hex.radial_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = hex
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.rotation.y = PI / 6.0
	add_child(mi)


func _ice_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.93, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.3
	mat.roughness = 0.05
	mat.render_priority = 1
	return mat


func _flat(color: Color, glow: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 1
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.35, 0.05)
	return mat


func _add_frost(at: Vector3, cell: Vector2i) -> void:
	"""A few white streaks so ice reads as ice, not water."""
	var mat := _flat(Color(1, 1, 1, 0.8), false)
	mat.render_priority = 2
	for i in range(3):
		var streak := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5 - i * 0.1, 0.01, 0.04)
		streak.mesh = box
		streak.material_override = mat
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		streak.position = at + Vector3(-0.2 + i * 0.2, 0.015, -0.25 + i * 0.25)
		streak.rotation.y = 0.6 + float((cell.x * 3 + cell.y) % 5) * 0.2
		add_child(streak)


func _add_flames(at: Vector3, cell: Vector2i) -> void:
	var colors := [Color(1.0, 0.55, 0.1), Color(1.0, 0.82, 0.25), Color(0.95, 0.3, 0.05)]
	for i in range(3):
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.26 - i * 0.05
		cone.height = 0.95 - i * 0.15
		cone.radial_segments = 8
		var mat := _flat(colors[i], true)
		mat.albedo_color.a = 0.9
		var pivot := Node3D.new()  # scales from the base so flames flicker upward
		var angle := float(i) * TAU / 3.0 + float(cell.x + cell.y)
		pivot.position = at + Vector3(cos(angle) * 0.28, 0.0, sin(angle) * 0.28)
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, cone.height / 2.0, 0)
		pivot.add_child(mi)
		add_child(pivot)
		_flames.append({"node": pivot, "phase": angle * 3.0})


func _add_sprinkler(at: Vector3, cell: Vector2i, dir: int, hole) -> void:
	var head := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.22
	disc.bottom_radius = 0.26
	disc.height = 0.18
	disc.radial_segments = 12
	head.mesh = disc
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.57, 0.6)
	steel.metallic = 0.6
	steel.roughness = 0.35
	head.material_override = steel
	head.position = at + Vector3(0, 0.09, 0)
	add_child(head)
	# Chevron toward the hex it knocks the ball onto
	var next: Vector2i = hole.aoe_system._get_neighbor_in_direction(cell, dir, cell.x % 2 == 1)
	var to: Vector3 = hole.get_tile_world_position(next) - hole.get_tile_world_position(cell)
	var holder := Node3D.new()
	holder.position = at + Vector3(0, 0.02, 0)
	holder.rotation.y = atan2(to.x, to.z)
	add_child(holder)
	var water := _flat(Color(0.3, 0.8, 1.0, 1.0), true)
	water.emission = Color(0.1, 0.45, 0.8)
	water.render_priority = 2
	for i in range(2):
		var chev := MeshInstance3D.new()
		chev.mesh = _chevron_mesh()
		chev.material_override = water
		chev.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chev.position = Vector3(0, 0.02, 0.35 + i * 0.22)
		chev.scale = Vector3(1.4, 1.0, 1.4)
		holder.add_child(chev)


func _add_tunnel(at: Vector3, cell: Vector2i, dir: int, hole) -> void:
	var tint := _flat(Color(0.75, 0.92, 1.0, 0.35), false)
	_add_hex(at, tint)
	var next: Vector2i = hole.aoe_system._get_neighbor_in_direction(cell, dir, cell.x % 2 == 1)
	var to: Vector3 = hole.get_tile_world_position(next) - hole.get_tile_world_position(cell)
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = atan2(to.x, to.z)
	add_child(holder)
	# A hoop across the run: the tunnel's ribs
	var hoop := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.56
	torus.outer_radius = 0.72
	torus.rings = 24
	torus.ring_segments = 8
	hoop.mesh = torus
	var rib := StandardMaterial3D.new()
	rib.albedo_color = Color(0.55, 0.78, 0.95, 0.92)
	rib.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rib.roughness = 0.25
	rib.metallic = 0.2
	hoop.material_override = rib
	hoop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hoop.rotation.x = PI / 2.0  # stand it up across the direction of travel
	hoop.position = Vector3(0, 0.0, 0)
	holder.add_child(hoop)
	var air := _flat(Color(0.85, 0.97, 1.0, 1.0), true)
	air.emission = Color(0.5, 0.8, 1.0)
	air.render_priority = 2
	for i in range(2):
		var chev := MeshInstance3D.new()
		chev.mesh = _chevron_mesh()
		chev.material_override = air
		chev.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chev.position = Vector3(0, 0.03, -0.2 + i * 0.35)
		chev.scale = Vector3(1.6, 1.0, 1.6)
		holder.add_child(chev)


func _add_trampoline(at: Vector3) -> void:
	var frame := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.64
	torus.rings = 24
	frame.mesh = torus
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.16, 0.12)
	red.roughness = 0.4
	frame.material_override = red
	frame.position = at + Vector3(0, 0.12, 0)
	add_child(frame)
	var mat := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.52
	disc.bottom_radius = 0.52
	disc.height = 0.02
	disc.radial_segments = 20
	mat.mesh = disc
	mat.material_override = _flat(Color(0.08, 0.08, 0.1, 0.95), false)
	mat.position = at + Vector3(0, 0.1, 0)
	add_child(mat)
	for i in range(6):
		var leg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.03
		cyl.height = 0.12
		leg.mesh = cyl
		leg.material_override = red
		var a := float(i) * TAU / 6.0
		leg.position = at + Vector3(cos(a) * 0.57, 0.06, sin(a) * 0.57)
		add_child(leg)


func _chevron_mesh() -> ArrayMesh:
	var w := 0.22
	var depth := 0.12
	var t := 0.07
	var pts := PackedVector3Array([
		Vector3(-w, 0, -depth), Vector3(0, 0, depth - t), Vector3(0, 0, depth),
		Vector3(-w, 0, -depth), Vector3(0, 0, depth), Vector3(-w, 0, -depth + t),
		Vector3(w, 0, -depth), Vector3(0, 0, depth), Vector3(0, 0, depth - t),
		Vector3(w, 0, -depth), Vector3(w, 0, -depth + t), Vector3(0, 0, depth),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
