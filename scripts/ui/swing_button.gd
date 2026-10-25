extends Button
class_name SwingButton

## SwingButton - Hold-to-swing SHOOT button: the whole button is the meter,
## and how far out you let go is how hard you hit. Its face is ringed, from
## the middle out: plain paper, then the power zone (shading darker toward the
## edge: the club's shortest carry up to its longest), with a green sweet spot
## sitting at the power the aimed shot needs (aim_power; thinner on harder
## shots), then a red band touching the button's edge. While the button is
## held a box grows from 0 x 0 in the centre out to the button's edges and
## back; letting go strikes the ball, graded by where the box was (grade()):
##   in the middle (paper)        - thin (well short of the club, and right)
##   in the power zone, short of  - short (carry from the club's band, by power)
##     the green / past it        - long
##   in the green                 - pure (the aimed carry, tighter landing)
##   in the outer red, at edge    - hook (overswung: past the club, and left)
## Putts and disabled states are a plain tap. A `pressed` with no hold (tests,
## the bot) is a neutral strike: take_swing() returns {}.

signal swung(result: Dictionary)

const RESULT_SHOW_TIME := 1.6
const POWER_LO := 0.22     # the power zone, as shares of the button (centre 0, edge 1):
const POWER_HI := 0.88     #   inside it is a thin strike, outside it an overswung hook
const GREEN_SHARE := 0.5   # sweet spot thickness per unit of difficulty "green"
const POWER_SHADES := 6    # steps of shading across the power zone
const SWEET_PAD := 0.08    # power zone kept either side of the sweet spot (short / long, not a miss)

var title := "SHOOT"
var subtitle := ""
var meter_enabled := true
var green_width := 0.34   # difficulty: bigger = a thicker green band (hex_grid._swing_difficulty)
var period := 2.0         # seconds for centre -> edge -> centre
var aim_power := 0.75     # share of the club's power the aimed shot needs (where the green sits)

var _holding := false
var _hold_time := 0.0
var _released_w := -1.0
var _released_frame := -1
var _last_result := ""
var _result_time := 0.0


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]:
		add_theme_color_override(c, Color(0, 0, 0, 0))  # the face is drawn
	button_down.connect(_on_down)
	button_up.connect(_on_up)


func set_face(p_title: String, p_subtitle: String, p_meter: bool) -> void:
	title = p_title
	subtitle = p_subtitle
	meter_enabled = p_meter
	queue_redraw()


func set_difficulty(p_green: float, p_period: float, p_aim_power: float = 0.75) -> void:
	green_width = clampf(p_green, 0.08, 0.5)
	period = p_period
	aim_power = clampf(p_aim_power, 0.0, 1.0)
	queue_redraw()


static func meter_width(t: float, p: float) -> float:
	"""Box size at hold time t, as a share of the button: 0 -> 1 -> 0 every period."""
	var ph := fmod(t, p) / p
	return 1.0 - absf(2.0 * ph - 1.0)


static func bands(green: float, aim: float) -> Dictionary:
	"""The sweet spot's edges (shares of the button, centre 0 to edge 1),
	centred on the aimed power, SWEET_PAD inside the power zone: {lo, hi}."""
	var half := clampf(green, 0.08, 0.5) * GREEN_SHARE / 2.0
	var centre := lerpf(POWER_LO, POWER_HI, clampf(aim, 0.0, 1.0))
	var lo := clampf(centre - half, POWER_LO + SWEET_PAD, POWER_HI - SWEET_PAD - 2.0 * half)
	return {"lo": lo, "hi": lo + 2.0 * half}


static func power_at(w: float) -> float:
	"""How hard a release at box size w hits: 0 the club's shortest carry, 1 its longest."""
	return clampf(inverse_lerp(POWER_LO, POWER_HI, w), 0.0, 1.0)


static func grade(w: float, green: float, aim: float) -> String:
	var b := bands(green, aim)
	if w < POWER_LO:
		return "thin"
	if w > POWER_HI:
		return "hook"
	if w < b.lo:
		return "short"
	if w <= b.hi:
		return "pure"
	return "long"


func take_swing() -> Dictionary:
	"""The swing being released right now ({} if nobody held the button)."""
	var w := -1.0
	if _holding:
		w = meter_width(_hold_time, period)
		_holding = false
	elif _released_frame == Engine.get_process_frames():
		w = _released_w
	if w < 0.0 or not meter_enabled:
		return {}
	var result := {"kind": grade(w, green_width, aim_power), "width": w, "power": power_at(w)}
	show_result(result.kind)
	swung.emit(result)
	return result


func show_result(kind: String) -> void:
	_last_result = kind
	_result_time = RESULT_SHOW_TIME
	queue_redraw()


func _on_down() -> void:
	if disabled or not meter_enabled:
		return
	_holding = true
	_hold_time = 0.0
	_last_result = ""


func _on_up() -> void:
	if _holding:
		_released_w = meter_width(_hold_time, period)
		_released_frame = Engine.get_process_frames()
	_holding = false
	queue_redraw()


func _process(delta: float) -> void:
	if _holding:
		_hold_time += delta
		queue_redraw()
	if _result_time > 0.0:
		_result_time -= delta
		if _result_time <= 0.0:
			_last_result = ""
			queue_redraw()


func _draw() -> void:
	var head := ScorecardStyle.header_font()
	var head_light := ScorecardStyle.header_font(false)
	var red := ScorecardStyle.RED
	var w := size.x
	var h := size.y
	var live := not disabled
	var meter := meter_enabled and live
	draw_rect(Rect2(Vector2.ZERO, size), ScorecardStyle.PAPER if live else ScorecardStyle.PAPER_DARK)
	if meter:
		# The rings: outer red (overswing), the power zone shading darker
		# outward, the green sweet spot over it, and paper in the middle
		var b := bands(green_width, aim_power)
		var paper := ScorecardStyle.PAPER
		_band(POWER_HI, 1.0, paper.lerp(red, 0.6))
		for i in range(POWER_SHADES):
			var k0 := lerpf(POWER_LO, POWER_HI, float(i) / POWER_SHADES)
			var k1 := lerpf(POWER_LO, POWER_HI, float(i + 1) / POWER_SHADES)
			_band(k0, k1, paper.lerp(ScorecardStyle.INK, 0.04 + 0.16 * float(i) / (POWER_SHADES - 1)))
		_band(b.lo, b.hi, paper.lerp(ScorecardStyle.GREEN, 0.65))
		for k in [POWER_LO, POWER_HI, b.lo, b.hi]:
			draw_rect(_ring(k), Color(ScorecardStyle.INK, 0.35), false, 1.0)
	elif live:
		draw_rect(Rect2(Vector2(1.5, 1.5), size - Vector2(3, 3)), red, false, 3.0)
	if is_hovered() and live and not _holding:
		draw_rect(Rect2(Vector2.ZERO, size), Color(red, 0.06))
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1, 1)), ScorecardStyle.INK if live else Color(ScorecardStyle.INK, 0.35), false, 1.0)

	if live:
		# Fits in the paper middle when the meter is showing
		var room := w * 0.5 if meter else w - 16.0
		var fs := 44
		while fs > 16 and head.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 2
		var ty := h * 0.5 + fs * 0.32 - (8.0 if subtitle != "" else 0.0)
		draw_string(head, Vector2(0, ty), title, HORIZONTAL_ALIGNMENT_CENTER, w, fs, red)
		if subtitle != "":
			draw_string(head_light, Vector2(0, ty + 18), subtitle, HORIZONTAL_ALIGNMENT_CENTER, w, 12, ScorecardStyle.INK_SOFT)
	else:
		# The reason Shoot can't fire, small
		draw_multiline_string(head_light, Vector2(8, h * 0.4), title, HORIZONTAL_ALIGNMENT_CENTER, w - 16, 14, 3, ScorecardStyle.INK_SOFT)

	# The swing: a box growing out from the middle to the edges and back
	if _holding and meter:
		var r := _ring(meter_width(_hold_time, period))
		if r.size.x > 1.0:
			draw_rect(r, ScorecardStyle.INK, false, 3.0)

	if _last_result != "":
		var word: String = {"pure": "PURE!", "thin": "THIN", "short": "SHORT", "long": "LONG", "hook": "HOOK"}.get(_last_result, _last_result.to_upper())
		var col: Color = {"pure": ScorecardStyle.GREEN, "short": ScorecardStyle.PENCIL, "long": ScorecardStyle.PENCIL}.get(_last_result, red)
		draw_set_transform(Vector2(w * 0.5, h * 0.22), -0.18, Vector2.ONE)
		draw_string(ScorecardStyle.pencil_font(), Vector2(-w * 0.5, 0), word, HORIZONTAL_ALIGNMENT_CENTER, w, 34, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _band(k0: float, k1: float, color: Color) -> void:
	"""Fill between ring k0 (inside) and ring k1 (outside)."""
	var o := _ring(k1)
	var i := _ring(k0)
	draw_rect(Rect2(o.position, Vector2(o.size.x, i.position.y - o.position.y)), color)
	draw_rect(Rect2(Vector2(o.position.x, i.end.y), Vector2(o.size.x, o.end.y - i.end.y)), color)
	draw_rect(Rect2(Vector2(o.position.x, i.position.y), Vector2(i.position.x - o.position.x, i.size.y)), color)
	draw_rect(Rect2(Vector2(i.end.x, i.position.y), Vector2(o.end.x - i.end.x, i.size.y)), color)


func _ring(k: float) -> Rect2:
	"""The button's rect scaled by k about its centre (k = 1: the button)."""
	var s := size * clampf(k, 0.0, 1.0)
	return Rect2((size - s) / 2.0, s)
