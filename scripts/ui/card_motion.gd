extends Node
class_name CardMotion

## CardMotion - Makes a card face feel alive (after Marvel Snap). Added as a
## child of the face it moves; drives the face's position offset, scale and
## rotation with damped springs, so every change overshoots a little and
## settles:
##   hover  - lifts, grows and leans toward the cursor
##   drag   - a drag ghost swings with how fast it's moving sideways
##   move   - fly_from(): springs in from where the card was (hand <-> mat)
##   deal   - deal_in(): slides up into the hand, slightly turned
##   punch  - punch(): a little bump and wobble (a card landing)

const HOVER_LIFT := 12.0
const HOVER_SCALE := 1.08
const HOVER_LEAN := 0.02       # radians with the cursor at the card's edge
const DRAG_SCALE := 1.1
const DRAG_SWING := 0.00025    # radians per px/s of sideways speed
const DRAG_SWING_MAX := 0.15
const STIFFNESS := 240.0
const DAMPING := 28.0          # just under critical (31): barely overshoots
const DEAL_DROP := 140.0       # px below its slot a dealt card starts
const KICK := 0.6              # spin kick on a move / punch (rad/s)

var face: Control
var host: Control              # hovered via its mouse signals (null: never hovers)
var dragging := false          # a drag ghost

var _base := Vector2.ZERO      # the face's resting position in its parent
var _hover := false
var _offset := Vector2.ZERO
var _offset_v := Vector2.ZERO
var _scale := 1.0
var _scale_v := 0.0
var _rot := 0.0
var _rot_v := 0.0
var _last_global := Vector2.INF
var _drag_vel := Vector2.ZERO
var _fly_from := Vector2.INF   # pending: spring in from this global position
var _wait := 0.0               # deal-in delay (hidden until then)


static func attach(p_face: Control, p_host: Control = null) -> CardMotion:
	var m := CardMotion.new()
	m.face = p_face
	m.host = p_host
	m.name = "Motion"
	p_face.add_child(m)
	return m


static func of(btn: Node) -> CardMotion:
	"""The motion on a card button's face, if it has one."""
	var face := btn.get_node_or_null("Face") if btn else null
	return face.get_node_or_null("Motion") as CardMotion if face else null


func _ready() -> void:
	_base = face.position
	if host:
		host.mouse_entered.connect(func(): _hover = true)
		host.mouse_exited.connect(func(): _hover = false)


func fly_from(global_pos: Vector2) -> void:
	"""The card just moved: spring in from global_pos (its face's old top-left)
	once the container has laid it out in its new place."""
	_fly_from = global_pos
	face.modulate.a = 0.0
	_rot_v += (1.0 if randf() < 0.5 else -1.0) * KICK


func deal_in(delay: float) -> void:
	_wait = delay
	_offset = Vector2(0, DEAL_DROP)
	_rot = randf_range(-0.08, 0.08)
	_scale = 0.85
	face.modulate.a = 0.0


func punch(amount: float = 1.0) -> void:
	_scale_v += 1.2 * amount
	_rot_v += (1.0 if randf() < 0.5 else -1.0) * KICK * amount


func _process(delta: float) -> void:
	if face == null:
		return
	var dt := minf(delta, 1.0 / 30.0)
	if _wait > 0.0:
		_wait -= dt
		if _wait > 0.0:
			return
		face.modulate.a = 1.0
	if _fly_from != Vector2.INF and host and host.size.x > 0.0:
		_offset = _fly_from - (host.global_position + _base)
		_fly_from = Vector2.INF
		face.modulate.a = 1.0
	var hovered := _hover and host != null and not dragging and host.is_visible_in_tree()
	var offset_target := Vector2(0, -HOVER_LIFT) if hovered else Vector2.ZERO
	var scale_target := HOVER_SCALE if hovered else 1.0
	var rot_target := 0.0
	if hovered:
		var r := host.get_global_rect()
		var u := clampf((host.get_global_mouse_position().x - r.position.x) / maxf(r.size.x, 1.0) * 2.0 - 1.0, -1.0, 1.0)
		rot_target = u * HOVER_LEAN
	if dragging:
		# Lean into the motion, like a card held by its top edge
		var g := face.global_position
		if _last_global != Vector2.INF:
			_drag_vel = _drag_vel.lerp((g - _last_global) / dt, 0.25)
		_last_global = g
		scale_target = DRAG_SCALE
		rot_target = clampf(_drag_vel.x * DRAG_SWING, -DRAG_SWING_MAX, DRAG_SWING_MAX)
	_offset_v += (STIFFNESS * (offset_target - _offset) - DAMPING * _offset_v) * dt
	_offset += _offset_v * dt
	_scale_v += (STIFFNESS * (scale_target - _scale) - DAMPING * _scale_v) * dt
	_scale += _scale_v * dt
	_rot_v += (STIFFNESS * (rot_target - _rot) - DAMPING * _rot_v) * dt
	_rot += _rot_v * dt
	face.pivot_offset = face.size / 2.0
	face.position = _base + _offset
	face.scale = Vector2(_scale, _scale)
	face.rotation = _rot
	# A lifted card draws over its neighbours
	face.z_index = 1 if hovered or _offset.length() > 2.0 or absf(_scale - 1.0) > 0.02 else 0
