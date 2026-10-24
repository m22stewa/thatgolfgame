extends Button
class_name SwingButton

## SwingButton - Hold-to-swing SHOOT button: the whole button is the meter.
## Its face is ringed, outside in: a red band touching the button's edge, a
## green band near the edge (thinner on harder shots), a red band inside it,
## and plain paper in the middle. While the button is held a box grows from
## 0 x 0 in the centre out to the button's edges and back; letting go strikes
## the ball, graded by how far out the box was (bands()):
##   in the middle (paper)     - thin (comes up short)
##   in the inner red          - slice (misses right)
##   in the green              - pure (tighter landing)
##   in the outer red, at edge - hook (misses left, further)
## Putts and disabled states are a plain tap. A `pressed` with no hold (tests,
## the bot) is a neutral strike: take_swing() returns {}.

signal swung(result: Dictionary)

const RESULT_SHOW_TIME := 1.6
const GREEN_OUTER := 0.88   # the green band's outer edge (the outer red runs from here to the edge)
const GREEN_SHARE := 0.7    # green band thickness per unit of difficulty "green"
const INNER_RED := 0.2      # the inner red band's thickness

var title := "SHOOT"
var subtitle := ""
var meter_enabled := true
var green_width := 0.34   # difficulty: bigger = a thicker green band (hex_grid._swing_difficulty)
var period := 2.0         # seconds for centre -> edge -> centre

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


func set_difficulty(p_green: float, p_period: float) -> void:
	green_width = clampf(p_green, 0.08, 0.5)
	period = p_period
	queue_redraw()


static func meter_width(t: float, p: float) -> float:
	"""Box size at hold time t, as a share of the button: 0 -> 1 -> 0 every period."""
	var ph := fmod(t, p) / p
	return 1.0 - absf(2.0 * ph - 1.0)


static func bands(green: float) -> Dictionary:
	"""Where the rings sit (shares of the button, centre 0 to edge 1):
	{thin: inner red starts, lo: green starts, hi: green ends (outer red to 1)}."""
	var hi := GREEN_OUTER
	var lo := hi - clampf(green, 0.08, 0.5) * GREEN_SHARE
	return {"thin": maxf(0.05, lo - INNER_RED), "lo": lo, "hi": hi}


static func grade(w: float, green: float) -> String:
	var b := bands(green)
	if w < b.thin:
		return "thin"
	if w < b.lo:
		return "slice"
	if w <= b.hi:
		return "pure"
	return "hook"


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
	var result := {"kind": grade(w, green_width), "width": w}
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
		# The rings, painted outside in (solid, so they don't mix): outer red
		# (to the edge), green, inner red, paper
		var b := bands(green_width)
		var paper := ScorecardStyle.PAPER
		draw_rect(_ring(1.0), paper.lerp(red, 0.6))
		draw_rect(_ring(b.hi), paper.lerp(ScorecardStyle.GREEN, 0.65))
		draw_rect(_ring(b.lo), paper.lerp(red, 0.25))
		draw_rect(_ring(b.thin), paper)
		for k in [b.hi, b.lo]:
			draw_rect(_ring(k), Color(ScorecardStyle.INK, 0.35), false, 1.0)
	elif live:
		draw_rect(Rect2(Vector2(1.5, 1.5), size - Vector2(3, 3)), red, false, 3.0)
	if is_hovered() and live and not _holding:
		draw_rect(Rect2(Vector2.ZERO, size), Color(red, 0.06))
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1, 1)), ScorecardStyle.INK if live else Color(ScorecardStyle.INK, 0.35), false, 1.0)

	if live:
		# Fits in the paper middle when the meter is showing
		var room := _ring(bands(green_width).thin).size.x - 8.0 if meter else w - 16.0
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
		var word: String = {"pure": "PURE!", "thin": "THIN", "slice": "SLICE", "hook": "HOOK"}.get(_last_result, _last_result.to_upper())
		var col := ScorecardStyle.GREEN if _last_result == "pure" else red
		draw_set_transform(Vector2(w * 0.5, h * 0.22), -0.18, Vector2.ONE)
		draw_string(ScorecardStyle.pencil_font(), Vector2(-w * 0.5, 0), word, HORIZONTAL_ALIGNMENT_CENTER, w, 34, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ring(k: float) -> Rect2:
	"""The button's rect scaled by k about its centre (k = 1: the button)."""
	var s := size * clampf(k, 0.0, 1.0)
	return Rect2((size - s) / 2.0, s)
