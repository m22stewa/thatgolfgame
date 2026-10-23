extends Control
class_name ScorecardTable

## ScorecardTable - The nine-hole card: HOLE numbers, PAR in red, YOU in
## pencil, and an OUT (or IN) total. The hole being played is a red cell; pars
## and scores fill in as the run gets to them.

const LABEL_W := 46.0
const ROW_H := 24.0

var first_hole := 1          # 1 (front nine) or 10 (back nine)
var current_hole := 1
var pars: Dictionary = {}    # hole number -> par
var scores: Dictionary = {}  # hole number -> strokes (finished holes)
var live_strokes := 0        # strokes so far on the current hole


func _init() -> void:
	custom_minimum_size = Vector2(LABEL_W + 10 * 30.0, ROW_H * 3)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(p_current: int, p_pars: Dictionary, p_scores: Dictionary, p_live: int) -> void:
	current_hole = p_current
	first_hole = 1 if p_current <= 9 else 10
	pars = p_pars
	scores = p_scores
	live_strokes = p_live
	queue_redraw()


func _draw() -> void:
	var head := ScorecardStyle.header_font()
	var head_light := ScorecardStyle.header_font(false)
	var pencil := ScorecardStyle.pencil_font()
	var cols := 10
	var cw := (size.x - LABEL_W) / float(cols)
	var rows := ["HOLE", "PAR", "YOU"]
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, ROW_H * 3)), ScorecardStyle.PAPER)
	for r in range(3):
		var y := ROW_H * r
		draw_string(head_light, Vector2(6, y + ROW_H - 7), rows[r], HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, 11, ScorecardStyle.INK_SOFT)
	var par_total := 0
	var you_total := 0
	for i in range(cols):
		var x := LABEL_W + cw * i
		var hole := first_hole + i
		var is_total := i == cols - 1
		if not is_total and hole == current_hole:
			draw_rect(Rect2(x, 0, cw, ROW_H), ScorecardStyle.RED)
		var hole_text := ("OUT" if first_hole == 1 else "IN") if is_total else str(hole)
		var hole_color := ScorecardStyle.PAPER if (not is_total and hole == current_hole) else ScorecardStyle.INK
		draw_string(head, Vector2(x, ROW_H - 6), hole_text, HORIZONTAL_ALIGNMENT_CENTER, cw, 13, hole_color)
		var par_text := ""
		var you_text := ""
		if is_total:
			par_text = str(par_total) if par_total > 0 else ""
			you_text = str(you_total) if you_total > 0 else ""
		else:
			if pars.has(hole):
				par_text = str(pars[hole])
				par_total += int(pars[hole])
			if scores.has(hole):
				you_text = str(scores[hole])
				you_total += int(scores[hole])
			elif hole == current_hole and live_strokes > 0:
				you_text = str(live_strokes)
		draw_string(head, Vector2(x, ROW_H * 2 - 6), par_text, HORIZONTAL_ALIGNMENT_CENTER, cw, 14, ScorecardStyle.RED)
		var you_color := ScorecardStyle.PENCIL if scores.has(hole) or is_total else Color(ScorecardStyle.PENCIL, 0.55)
		draw_string(pencil, Vector2(x, ROW_H * 3 - 3), you_text, HORIZONTAL_ALIGNMENT_CENTER, cw, 24, you_color)
		draw_line(Vector2(x, 0), Vector2(x, ROW_H * 3), ScorecardStyle.RULE, 2.0 if is_total else 1.0)
	for r in range(1, 3):
		draw_line(Vector2(0, ROW_H * r), Vector2(size.x, ROW_H * r), ScorecardStyle.RULE, 1.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, ROW_H * 3)), ScorecardStyle.INK, false, 2.0)
