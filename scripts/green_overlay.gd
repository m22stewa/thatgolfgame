extends Node3D
class_name GreenOverlay

## GreenOverlay - Draws a GreenBoard (the small-hex putting surface).
##
## On small hexes (design/claude/design_handoff_putting):
##   - Shading: flat hexes one even turf green, slope hexes a little darker.
##   - Arrow chevrons on the slopes, pointing down the fall line; the number of
##     chevrons is the slope's strength (1-3). They drift slowly that way.
##   - The cup: a bright ring.
##   - Features: spinning chips and spike marks (a pair of shoe prints).
##   - Slick patches: glossy pale-blue hexes with streaks, no arrow.
##   - Aiming: six arrows on the hexes round the ball (the picked one bright),
##     a label on every hex the read can stop on with the paces that stop
##     there (red where they drop), and the flipped cards over the ball.

const LIFT := 0.04            # above the course tile surface
const TINT_DEPTH := 0.6       # tints are solid columns this deep, so steps in the course below never show
const TURF := Color(0.33, 0.6, 0.3)
const CHEVRON_SPACING := 0.15
const DRIFT_RANGE := 0.1      # how far chevrons drift before looping (world units)

const SLOPE_DARKEN := 0.25    # slope hexes: this much darker than flat ones
const STOP_COLOR := Color(1.0, 0.98, 0.92)   # read labels: the ball stops here
const DROP_COLOR := Color(1.0, 0.55, 0.45)   # ... and drops
const MARK_COLOR := Color(1.0, 1.0, 1.0, 0.95)

var board: GreenBoard = null

var _arrows: Array = []  # [{node, speed}] chevron stacks drifting along their local +Z
var _time := 0.0
var _mark_material: StandardMaterial3D
var _chevron_mesh: ArrayMesh
var _tint_mesh: CylinderMesh
var _endpoints: Node3D = null    # the read's stop labels
var _aim_arrows: Array[MeshInstance3D] = []  # the six directions out of the ball's hex
var _flip: Label3D = null       # the modifier cards flipped for this putt
var _coins: Dictionary = {}  # small hex -> coin node (spins; removed when collected)


func _init() -> void:
	_mark_material = StandardMaterial3D.new()
	_mark_material.albedo_color = MARK_COLOR
	_mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mark_material.render_priority = 2
	_chevron_mesh = _make_chevron_mesh()
	_tint_mesh = CylinderMesh.new()
	_tint_mesh.top_radius = GreenBoard.SIZE * 1.01
	_tint_mesh.bottom_radius = GreenBoard.SIZE * 1.01
	_tint_mesh.height = TINT_DEPTH
	_tint_mesh.radial_segments = 6


func show_board(green: GreenBoard, hole) -> void:
	"""Lay out the board's tints, arrows and cup. hole gives the surface height
	of the course tile under each small hex."""
	clear()
	board = green
	for a in board.tiles:
		var t: Dictionary = board.tiles[a]
		var at := surface_point(a, hole)
		_add_tint(at, t.strength > 0)
		var kind: String = board.features.get(a, {}).get("kind", "")
		if a == board.cup:
			_add_cup_marker(at)
		elif kind == "spike":
			_add_spike_marks(at, a)
		elif t.get("slick", false):
			_add_slick(at)
		elif t.strength > 0:
			_add_arrow(at, t.dir, t.strength)
		if kind == "coin":
			_add_coin(at, a)


func clear() -> void:
	for c in get_children():
		c.queue_free()
	_arrows.clear()
	_coins.clear()
	_endpoints = null
	_aim_arrows.clear()
	_flip = null
	board = null


func surface_point(a: Vector2i, hole) -> Vector3:
	"""World position on top of small hex a: the highest course tile under any
	part of it, so a hex straddling two tiles never sinks into the higher one."""
	var w := GreenBoard.to_world(a)
	var top := -INF
	for i in range(7):
		var p := w
		if i > 0:
			var ang := float(i) * TAU / 6.0
			p += Vector2(cos(ang), sin(ang)) * GreenBoard.SIZE * 0.9
		var cell: Vector2i = hole.world_to_grid(Vector3(p.x, 0.0, p.y))
		if hole.get_cell(cell.x, cell.y) >= 0:
			top = maxf(top, hole.get_tile_world_position(cell).y)
	if top == -INF:
		top = hole.get_tile_world_position(hole.world_to_grid(Vector3(w.x, 0.0, w.y))).y
	return Vector3(w.x, top + hole.TILE_SURFACE_OFFSET + LIFT, w.y)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	for mi in _aim_arrows:
		if mi.visible and mi.get_meta("picked", false):
			var s := 0.62 + 0.08 * sin(_time * 6.0)
			mi.scale = Vector3(s, 1.0, s)
	for c in _coins.values():
		if is_instance_valid(c):
			c.rotation.y = _time * 2.0
	for a in _arrows:
		var node: Node3D = a.node
		if is_instance_valid(node):
			node.position = Vector3(0, 0, fmod(_time * a.speed, DRIFT_RANGE))


func _add_tint(at: Vector3, slope: bool) -> void:
	# Solid (not see-through): the course hexes under the green must not show
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TURF.darkened(SLOPE_DARKEN) if slope else TURF
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = _tint_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at - Vector3(0, TINT_DEPTH / 2.0, 0)  # top face at the surface
	mi.rotation.y = PI / 6.0
	add_child(mi)


func _add_slick(at: Vector3) -> void:
	"""A glossy pale-blue hex with two streaks: the ball slides straight across."""
	var hex := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = GreenBoard.SIZE * 0.92
	m.bottom_radius = GreenBoard.SIZE * 0.92
	m.height = 0.01
	m.radial_segments = 6
	hex.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.92, 1.0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic_specular = 1.0
	mat.render_priority = 1
	hex.material_override = mat
	hex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hex.position = at + Vector3(0, 0.01, 0)
	add_child(hex)
	for k in [-1.0, 1.0]:
		var streak := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.36, 0.005, 0.03)
		streak.mesh = box
		streak.material_override = _mark_material
		streak.position = at + Vector3(k * 0.06, 0.02, k * 0.1)
		streak.rotation.y = 0.5
		add_child(streak)


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
	"""A chip collectable standing on the hex."""
	var spin := Node3D.new()
	spin.position = at + Vector3(0, 0.28, 0)
	var chip := ChipModel.new()
	chip.radius = 0.2
	chip.thickness = 0.05
	spin.add_child(chip)
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


func show_endpoints(marks: Array, hole) -> void:
	"""The read: over every hex a previewed pace stops on, the paces that stop
	there ("2", "3 4"), red where they drop. marks: GreenBoard.preview().marks."""
	if _endpoints:
		_endpoints.queue_free()
	_endpoints = Node3D.new()
	add_child(_endpoints)
	for m in marks:
		var totals: Array[String] = []
		for t in m.totals:
			totals.append(str(t))
		var l := _make_label(30)
		l.reparent(_endpoints, false)
		l.text = " ".join(totals)
		l.modulate = DROP_COLOR if m.holed else STOP_COLOR
		l.position = surface_point(m.end, hole) + Vector3(0, 0.3, 0)


func show_aim(ball: Vector2i, picked: int, hole, arrow_mesh: Mesh) -> void:
	"""Six arrows on the hexes round the ball, one per direction a putt can
	leave it: the picked one bright and pulsing, the rest faint."""
	if _aim_arrows.is_empty():
		for d in range(6):
			var mi := MeshInstance3D.new()
			mi.mesh = arrow_mesh
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.no_depth_test = true
			mat.render_priority = 3
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_aim_arrows.append(mi)
	var ball_y := surface_point(ball, hole).y
	for d in range(6):
		var mi := _aim_arrows[d]
		var a: Vector2i = ball + GreenBoard.DIRS[d]
		var v := GreenBoard.to_world(GreenBoard.DIRS[d])
		var at := GreenBoard.to_world(a)
		var y := surface_point(a, hole).y if board.tiles.has(a) else ball_y
		mi.position = Vector3(at.x, y + 0.06, at.y)
		mi.rotation = Vector3(0, atan2(v.x, v.y), 0)
		var on := d == picked
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.86, 0.3, 0.95) if on else Color(1, 1, 1, 0.45)
		mi.scale = Vector3.ONE * 0.62 if on else Vector3(0.5, 1.0, 0.5)
		mi.set_meta("picked", on)
		mi.visible = true


func show_flip(text: String, color: Color, at: Vector3) -> void:
	"""The flipped modifier cards, big over the ball."""
	if _flip == null:
		_flip = _make_label(54)
	_flip.text = text
	_flip.modulate = color
	_flip.position = at + Vector3(0, 0.8, 0)
	_flip.visible = true


func hide_flip() -> void:
	if _flip:
		_flip.visible = false


func _make_label(size: int) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font = ScorecardStyle.header_font()
	l.font_size = size
	l.outline_size = 10
	l.outline_modulate = Color(0.12, 0.12, 0.11, 0.9)
	l.render_priority = 4
	l.outline_render_priority = 3
	add_child(l)
	return l


func hide_target() -> void:
	if _endpoints:
		_endpoints.visible = false
	for mi in _aim_arrows:
		mi.visible = false


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
