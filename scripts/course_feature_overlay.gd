extends Node3D
class_name CourseFeatureOverlay

## CourseFeatureOverlay - Draws CourseFeatures on the course hexes: glossy ice,
## flickering fire, scorched ground, wind gusts (a column of pale light over
## each hex, like the coins', with streaks flowing the way it blows and
## chevrons on the ground) and round trampolines (one big pad over its 7
## hexes). Rebuilt whenever the features change (fire spreading).

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
			"tunnel":
				_add_tunnel(at, cell, f.dir, hole)
			"trampoline":
				# One big pad, drawn from its centre hex
				if f.get("group", cell) == cell:
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


const GUST_HEIGHT := 5.0
const GUST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 gust_color : source_color;
uniform vec2 flow = vec2(0.0, 1.0);  // world x, z the gust blows toward
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// Streaks in world space, so neighbouring columns read as one gust,
	// racing along the flow; brightest low down, gone at the top
	float along = dot(world_pos.xz, flow);
	float across = dot(world_pos.xz, vec2(-flow.y, flow.x));
	float streak = fract(along * 0.45 - TIME * 1.6 + sin(across * 2.3 + world_pos.y * 0.9) * 0.35);
	float band = smoothstep(0.0, 0.08, streak) * (1.0 - smoothstep(0.08, 0.45, streak));
	float fade = pow(UV.y, 1.4);
	ALBEDO = gust_color.rgb;
	ALPHA = gust_color.a * fade * (0.25 + 0.75 * band);
}
"""


func _add_tunnel(at: Vector3, cell: Vector2i, dir: int, hole) -> void:
	"""A wind gust hex: a pale tint, a column of light streaming the way it
	blows, and chevrons on the ground pointing that way."""
	var tint := _flat(Color(0.75, 0.92, 1.0, 0.3), false)
	_add_hex(at, tint)
	var next: Vector2i = hole.aoe_system._get_neighbor_in_direction(cell, dir, cell.x % 2 == 1)
	var to: Vector3 = hole.get_tile_world_position(next) - hole.get_tile_world_position(cell)
	var flow := Vector2(to.x, to.z).normalized()
	var column := MeshInstance3D.new()
	var prism := CylinderMesh.new()
	prism.radial_segments = 6  # the flat-top hex tiles
	prism.rings = 1
	prism.top_radius = HEX_RADIUS * 0.95
	prism.bottom_radius = HEX_RADIUS * 0.95
	prism.height = GUST_HEIGHT
	prism.cap_top = false
	prism.cap_bottom = false
	column.mesh = prism
	var mat := ShaderMaterial.new()
	mat.shader = _gust_shader()
	mat.set_shader_parameter("gust_color", Color(0.75, 0.92, 1.0, 0.5))
	mat.set_shader_parameter("flow", flow)
	column.material_override = mat
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.position = at + Vector3(0, GUST_HEIGHT / 2.0, 0)
	column.rotation.y = PI / 6.0  # corners onto the tile's, like _add_hex
	add_child(column)
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = atan2(to.x, to.z)
	add_child(holder)
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


static var _gust_shader_res: Shader = null


static func _gust_shader() -> Shader:
	if _gust_shader_res == null:
		_gust_shader_res = Shader.new()
		_gust_shader_res.code = GUST_SHADER
	return _gust_shader_res


const PAD_RADIUS := 2.5  # covers the centre hex and its ring


func _add_trampoline(at: Vector3) -> void:
	"""A big round trampoline over the centre hex and the six around it."""
	var frame := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = PAD_RADIUS - 0.2
	torus.outer_radius = PAD_RADIUS
	torus.rings = 48
	frame.mesh = torus
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.16, 0.12)
	red.roughness = 0.4
	frame.material_override = red
	frame.position = at + Vector3(0, 0.22, 0)
	add_child(frame)
	var mat := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = PAD_RADIUS - 0.15
	disc.bottom_radius = PAD_RADIUS - 0.15
	disc.height = 0.02
	disc.radial_segments = 40
	mat.mesh = disc
	mat.material_override = _flat(Color(0.08, 0.08, 0.1, 0.95), false)
	mat.position = at + Vector3(0, 0.2, 0)
	add_child(mat)
	# A target ring on the mat
	var ring := MeshInstance3D.new()
	var inner := TorusMesh.new()
	inner.inner_radius = 0.75
	inner.outer_radius = 0.9
	inner.rings = 32
	ring.mesh = inner
	ring.material_override = _flat(Color(0.95, 0.85, 0.3, 0.9), false)
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.position = at + Vector3(0, 0.22, 0)
	add_child(ring)
	for i in range(10):
		var leg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = 0.22
		leg.mesh = cyl
		leg.material_override = red
		var a := float(i) * TAU / 10.0
		leg.position = at + Vector3(cos(a) * (PAD_RADIUS - 0.1), 0.11, sin(a) * (PAD_RADIUS - 0.1))
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
