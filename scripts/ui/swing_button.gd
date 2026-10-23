extends Button
class_name SwingButton

## SwingButton - Hold-to-swing SHOOT box. A green target sits in the middle of
## the meter with red lines either side (narrower on harder shots). While the
## button is held a box grows from the centre to the edges and back; letting
## go strikes the ball, graded by how wide the box was:
##   under THIN_SHARE of the green - thin (comes up short)
##   inside the green               - pure (tighter landing)
##   between the green and red line - slice (misses right)
##   past the red line              - hook (misses left, further)
## Putts and disabled states are a plain tap. A `pressed` with no hold (tests,
## the bot) is a neutral strike: take_swing() returns {}.

signal swung(result: Dictionary)

const THIN_SHARE := 0.4
const RESULT_SHOW_TIME := 1.6

var title := "SHOOT"
var subtitle := ""
var meter_enabled := true
var green_width := 0.34   # half-width of the green target, 0..1 of the meter
var red_width := 0.56     # the red lines
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
	red_width = minf(green_width + 0.22, 0.92)
	period = p_period
	queue_redraw()


static func meter_width(t: float, p: float) -> float:
	"""Box half-width at hold time t: 0 -> 1 -> 0 every period."""
	var ph := fmod(t, p) / p
	return 1.0 - absf(2.0 * ph - 1.0)


static func grade(w: float, green: float, red: float) -> String:
	if w < green * THIN_SHARE:
		return "thin"
	if w <= green:
		return "pure"
	if w <= red:
		return "slice"
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
	var result := {"kind": grade(w, green_width, red_width), "width": w}
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
	var edge := red if live else Color(ScorecardStyle.INK, 0.35)
	draw_rect(Rect2(Vector2.ZERO, size), ScorecardStyle.PAPER if live else ScorecardStyle.PAPER_DARK)
	if is_hovered() and live and not _holding:
		draw_rect(Rect2(Vector2.ZERO, size), Color(red, 0.06))
	draw_rect(Rect2(Vector2(1.5, 1.5), size - Vector2(3, 3)), edge, false, 3.0)

	var meter_h := 34.0 if (meter_enabled and live) else 0.0
	var text_h := h - meter_h - 10.0
	if live:
		var fs := 44
		while fs > 20 and head.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 16:
			fs -= 2
		var ty := text_h * 0.5 + fs * 0.32 - (6.0 if subtitle != "" else 0.0)
		draw_string(head, Vector2(0, ty), title, HORIZONTAL_ALIGNMENT_CENTER, w, fs, red)
		if subtitle != "":
			draw_string(head_light, Vector2(0, ty + 18), subtitle, HORIZONTAL_ALIGNMENT_CENTER, w, 12, ScorecardStyle.INK_SOFT)
	else:
		# The reason Shoot can't fire, small
		draw_multiline_string(head_light, Vector2(8, h * 0.4), title, HORIZONTAL_ALIGNMENT_CENTER, w - 16, 14, 3, ScorecardStyle.INK_SOFT)

	if meter_h > 0.0:
		var m := Rect2(12, h - meter_h - 12, w - 24, meter_h)
		var cx := m.get_center().x
		var half := m.size.x / 2.0
		draw_rect(m, Color(red, 0.18))  # outer red
		draw_rect(Rect2(cx - half * red_width, m.position.y, half * red_width * 2.0, m.size.y), Color(red, 0.08))  # inner red
		draw_rect(Rect2(cx - half * green_width, m.position.y, half * green_width * 2.0, m.size.y), Color(ScorecardStyle.GREEN, 0.75))
		var thin := green_width * THIN_SHARE
		draw_rect(Rect2(cx - half * thin, m.position.y, half * thin * 2.0, m.size.y), Color(ScorecardStyle.GREEN, 0.35))
		for s in [-1.0, 1.0]:
			var lx: float = cx + s * half * red_width
			draw_line(Vector2(lx, m.position.y - 2), Vector2(lx, m.end.y + 2), red, 2.5)
		draw_rect(m, ScorecardStyle.INK, false, 1.0)
		if _holding:
			var bw := meter_width(_hold_time, period)
			draw_rect(Rect2(cx - half * bw, m.position.y - 3, half * bw * 2.0, m.size.y + 6), ScorecardStyle.INK, false, 2.5)

	if _last_result != "":
		var word: String = {"pure": "PURE!", "thin": "THIN", "slice": "SLICE", "hook": "HOOK"}.get(_last_result, _last_result.to_upper())
		var col := ScorecardStyle.GREEN if _last_result == "pure" else red
		draw_set_transform(Vector2(w * 0.5, h * 0.35), -0.18, Vector2.ONE)
		draw_string(ScorecardStyle.pencil_font(), Vector2(-w * 0.5, 0), word, HORIZONTAL_ALIGNMENT_CENTER, w, 34, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
