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
		if a == board.cup:
			_add_cup_marker(at)
		elif t.strength == 0:
			_add_dot(at)
		else:
			_add_arrow(at, t.dir, t.strength)


func clear() -> void:
	for c in get_children():
		c.queue_free()
	_arrows.clear()
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
