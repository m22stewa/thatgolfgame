extends Node3D
class_name GreenOverlay

## GreenOverlay - Draws a GreenBoard (the small-hex putting surface).
##
## After how golf games show greens (height colour gradients, flowing slope
## markers), on small hexes:
##   - Height tint: blue (lowest on this green) to red (highest).
##   - Arrow chevrons: point the way the hex pushes the ball; the number of
##     chevrons IS how many hexes it pushes (1-3). They drift slowly that way,
##     faster when stronger. Flat hexes (the ball stops there) get a dot.
##   - The cup: a bright ring.
##   - Features: spinning gold coins, spike marks (a pair of shoe prints) and
##     a forgotten putter lying across two hexes.

const LIFT := 0.04            # above the course tile surface
const TINT_ALPHA := 0.5
const CHEVRON_SPACING := 0.15
const DRIFT_RANGE := 0.1      # how far chevrons drift before looping (world units)

const LOW_COLOR := Color(0.2, 0.45, 0.95)
const MID_COLOR := Color(0.95, 0.85, 0.3)
const HIGH_COLOR := Color(0.95, 0.3, 0.22)
const MARK_COLOR := Color(1.0, 1.0, 1.0, 0.95)

var board: GreenBoard = null

var _arrows: Array = []  # [{node, speed}] chevron stacks drifting along their local +Z
var _time := 0.0
var _mark_material: StandardMaterial3D
var _chevron_mesh: ArrayMesh
var _dot_mesh: CylinderMesh
var _tint_mesh: CylinderMesh
var _target: MeshInstance3D = null
var _coins: Dictionary = {}  # small hex -> coin node (spins; removed when collected)


func _init() -> void:
	_mark_material = StandardMaterial3D.new()
	_mark_material.albedo_color = MARK_COLOR
	_mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mark_material.render_priority = 2
	_chevron_mesh = _make_chevron_mesh()
	_dot_mesh = CylinderMesh.new()
	_dot_mesh.top_radius = 0.035
	_dot_mesh.bottom_radius = 0.035
	_dot_mesh.height = 0.01
	_dot_mesh.radial_segments = 8
	_tint_mesh = CylinderMesh.new()
	_tint_mesh.top_radius = GreenBoard.SIZE * 0.94
	_tint_mesh.bottom_radius = GreenBoard.SIZE * 0.94
	_tint_mesh.height = 0.01
	_tint_mesh.radial_segments = 6


func show_board(green: GreenBoard, hole) -> void:
	"""Lay out the board's tints, arrows and cup. hole gives the surface height
	of the course tile under each small hex."""
	clear()
	board = green
	var span := maxf(board.high - board.low, 0.001)
	for a in board.tiles:
		var t: Dictionary = board.tiles[a]
		var at := surface_point(a, hole)
		_add_tint(at, (float(t.height) - board.low) / span)
		var kind: String = board.features.get(a, {}).get("kind", "")
		if a == board.cup:
			_add_cup_marker(at)
		elif kind == "spike":
			_add_spike_marks(at, a)
		elif kind == "putter":
			pass  # drawn once per putter below
		elif t.strength == 0:
			_add_dot(at)
		else:
			_add_arrow(at, t.dir, t.strength)
		if kind == "coin":
			_add_coin(at, a)
	var drawn := {}
	for a in board.features:
		var f: Dictionary = board.features[a]
		var other: Vector2i = a + GreenBoard.DIRS[f.dir]
		if f.kind == "putter" and not drawn.has(a) and board.features.has(other):
			drawn[a] = true
			drawn[other] = true
			_add_putter(surface_point(a, hole), surface_point(other, hole))


func clear() -> void:
	for c in get_children():
		c.queue_free()
	_arrows.clear()
	_coins.clear()
	_target = null
	board = null


func surface_point(a: Vector2i, hole) -> Vector3:
	"""World position on top of the course tile under small hex a."""
	var w := GreenBoard.to_world(a)
	var cell: Vector2i = hole.world_to_grid(Vector3(w.x, 0.0, w.y))
	var y: float = hole.get_tile_world_position(cell).y + hole.TILE_SURFACE_OFFSET + LIFT
	return Vector3(w.x, y, w.y)


func _process(delta: float) -> void:
	if not visible or _arrows.is_empty():
		return
	_time += delta
	for c in _coins.values():
		if is_instance_valid(c):
			c.rotation.y = _time * 2.0
	for a in _arrows:
		var node: Node3D = a.node
		if is_instance_valid(node):
			node.position = Vector3(0, 0, fmod(_time * a.speed, DRIFT_RANGE))


func _add_tint(at: Vector3, height: float) -> void:
	var color := LOW_COLOR.lerp(MID_COLOR, height * 2.0) if height < 0.5 else MID_COLOR.lerp(HIGH_COLOR, (height - 0.5) * 2.0)
	color.a = TINT_ALPHA
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 1
	var mi := MeshInstance3D.new()
	mi.mesh = _tint_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.rotation.y = PI / 6.0
	add_child(mi)


func _add_dot(at: Vector3) -> void:
	var dot := MeshInstance3D.new()
	dot.mesh = _dot_mesh
	dot.material_override = _mark_material
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.position = at + Vector3(0, 0.01, 0)
	add_child(dot)


func _add_arrow(at: Vector3, dir: int, strength: int) -> void:
	"""strength chevrons pointing along GreenBoard.DIRS[dir]."""
	var d := GreenBoard.to_world(GreenBoard.DIRS[dir])
	var holder := Node3D.new()
	holder.position = at + Vector3(0, 0.01, 0)
	holder.rotation.y = atan2(d.x, d.y)  # chevron mesh points along +Z
	add_child(holder)
	var stack := Node3D.new()
	var start := -CHEVRON_SPACING * (strength - 1) / 2.0 - DRIFT_RANGE / 2.0
	for i in range(strength):
		var chev := MeshInstance3D.new()
		chev.mesh = _chevron_mesh
		chev.material_override = _mark_material
		chev.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chev.position = Vector3(0, 0, start + i * CHEVRON_SPACING)
		stack.add_child(chev)
	holder.add_child(stack)
	_arrows.append({"node": stack, "speed": 0.05 + 0.04 * strength})


func _add_cup_marker(at: Vector3) -> void:
	"""A bright ring on the cup hex so it reads through the tint."""
	var ring := TorusMesh.new()
	ring.inner_radius = 0.24
	ring.outer_radius = 0.34
	ring.rings = 24
	ring.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = ring
	mi.material_override = _mark_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1.0, 0.15, 1.0)
	mi.position = at + Vector3(0, 0.02, 0)
	add_child(mi)


func remove_coin(a: Vector2i) -> void:
	"""A collected coin leaves the green."""
	if _coins.has(a):
		_coins[a].queue_free()
		_coins.erase(a)


func _add_coin(at: Vector3, a: Vector2i) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.2
	disc.bottom_radius = 0.2
	disc.height = 0.05
	disc.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.78, 0.2)
	mat.metallic = 0.8
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.28, 0.0)
	var spin := Node3D.new()
	spin.position = at + Vector3(0, 0.28, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.material_override = mat
	mi.rotation.x = PI / 2.0  # stand the disc up
	spin.add_child(mi)
	add_child(spin)
	_coins[a] = spin


func _add_spike_marks(at: Vector3, a: Vector2i) -> void:
	"""A pair of shoe prints, turned by the hex so they don't all line up."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.18, 0.12, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 2
	var sole := CylinderMesh.new()
	sole.top_radius = 0.085
	sole.bottom_radius = 0.085
	sole.height = 0.01
	sole.radial_segments = 12
	var pair := Node3D.new()
	pair.position = at + Vector3(0, 0.012, 0)
	pair.rotation.y = float(abs(a.x * 7 + a.y * 13) % 6) * PI / 3.0
	for side in [-1.0, 1.0]:
		var print_mi := MeshInstance3D.new()
		print_mi.mesh = sole
		print_mi.material_override = mat
		print_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		print_mi.scale = Vector3(1.0, 1.0, 2.1)
		print_mi.position = Vector3(side * 0.09, 0, side * 0.05)
		pair.add_child(print_mi)
	add_child(pair)


func _add_putter(a: Vector3, b: Vector3) -> void:
	"""A putter lying on the green from hex a (head) to hex b (grip)."""
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.8, 0.84)
	steel.metallic = 0.9
	steel.roughness = 0.25
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = Color(0.08, 0.08, 0.09)
	var putter := Node3D.new()
	var dir := (b - a)
	putter.position = (a + b) / 2.0 + Vector3(0, 0.05, 0)
	putter.rotation.y = atan2(dir.x, dir.z)
	add_child(putter)
	var length := Vector2(dir.x, dir.z).length() + 0.5
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.035
	shaft_mesh.bottom_radius = 0.035
	shaft_mesh.height = length
	shaft.mesh = shaft_mesh
	shaft.material_override = steel
	shaft.rotation.x = PI / 2.0  # lie along +Z
	putter.add_child(shaft)
	var grip := MeshInstance3D.new()
	var grip_mesh := CylinderMesh.new()
	grip_mesh.top_radius = 0.055
	grip_mesh.bottom_radius = 0.055
	grip_mesh.height = length * 0.3
	grip.mesh = grip_mesh
	grip.material_override = grip_mat
	grip.rotation.x = PI / 2.0
	grip.position = Vector3(0, 0, length * 0.35)
	putter.add_child(grip)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.42, 0.12, 0.16)
	head.mesh = head_mesh
	head.material_override = steel
	head.position = Vector3(0.1, 0, -length * 0.5)
	putter.add_child(head)


func show_target(a: Vector2i, hole) -> void:
	"""Brass ring on the hex the putt is struck to."""
	if _target == null:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.3
		ring.outer_radius = 0.4
		ring.rings = 24
		ring.ring_segments = 6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.68, 0.2)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.render_priority = 3
		_target = MeshInstance3D.new()
		_target.mesh = ring
		_target.material_override = mat
		_target.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_target.scale = Vector3(1.0, 0.15, 1.0)
		add_child(_target)
	_target.position = surface_point(a, hole) + Vector3(0, 0.03, 0)
	_target.visible = true


func hide_target() -> void:
	if _target:
		_target.visible = false


func _make_chevron_mesh() -> ArrayMesh:
	"""A flat 'V' pointing along +Z, sized for a small hex."""
	var w := 0.2
	var depth := 0.11
	var t := 0.065  # stroke thickness
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
