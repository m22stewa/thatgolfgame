extends Control
class_name GreenIndicator

## GreenIndicator - When the green is off screen, a pencil-and-paper tag at
## the edge of the course view points the way to the flag, with the yards
## left from the ball. It fades out once the flag is in view (and stays away
## during the flyover and after the hole is done). Lives in the HoleViewer,
## over its 3D band, and draws nothing that takes input.

const EDGE := 56.0         # tip of the arrow, in from the view's edge
const VIEW_MARGIN := 24.0  # the flag counts as in view this far inside the edge
const FADE_SPEED := 4.0    # alpha per second
const ARROW := 14.0
const TAG_OFFSET := 46.0   # tag centre, back from the arrow tip

var viewer: HoleViewer
var _alpha := 0.0
var _tip := Vector2.ZERO
var _dir := Vector2.UP
var _yards := 0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var show := _update_target()
	_alpha = move_toward(_alpha, 1.0 if show else 0.0, FADE_SPEED * delta)
	queue_redraw()


func _update_target() -> bool:
	"""Aim at the flag; true while it is off screen and worth pointing at."""
	var grid = viewer.hex_grid if viewer else null
	if grid == null or grid.golf_ball == null or grid.flag_position.x < 0:
		return false
	if grid.hole_complete_triggered or viewer.is_flying:
		return false
	var flag: Vector3 = grid.get_tile_world_position(grid.flag_position)
	var at: Vector2 = viewer.world_to_screen(flag)
	var behind: bool = viewer.camera.is_position_behind(flag)
	if not behind and Rect2(Vector2.ZERO, size).grow(-VIEW_MARGIN).has_point(at):
		return false
	var centre := size / 2.0
	_dir = (at - centre) * (-1.0 if behind else 1.0)
	if _dir.length_squared() < 1.0:
		_dir = Vector2.UP
	_dir = _dir.normalized()
	# Where the line from the centre meets the inset edge
	var half := centre - Vector2(EDGE, EDGE)
	var t := minf(half.x / absf(_dir.x) if _dir.x != 0.0 else INF, half.y / absf(_dir.y) if _dir.y != 0.0 else INF)
	_tip = centre + _dir * t
	var ball_cell: Vector2i = grid.world_to_grid(grid.golf_ball.position)
	_yards = int(grid.hex_distance(ball_cell, grid.flag_position) * grid.YARDS_PER_CELL)
	return true


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var a := _alpha
	# Arrow at the edge, pointing at the flag
	var side := _dir.orthogonal() * ARROW * 0.6
	var base := _tip - _dir * ARROW
	draw_colored_polygon(PackedVector2Array([_tip, base + side, base - side]), Color(ScorecardStyle.RED, a))

	# Tag: a flag and the yards in pencil, on scorecard paper
	var pencil := ScorecardStyle.pencil_font()
	var text := "%d yd" % _yards
	var fs := 30
	var text_w := pencil.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tag_size := Vector2(text_w + 46, 40)
	var c := _tip - _dir * TAG_OFFSET
	var rect := Rect2(c - tag_size / 2.0, tag_size)
	draw_style_box(ScorecardStyle.paper_box(Color(ScorecardStyle.RULE, a), 2, Color(ScorecardStyle.PAPER, a), 4), rect)
	var pole := rect.position + Vector2(14, 8)
	draw_line(pole, pole + Vector2(0, 24), Color(ScorecardStyle.INK, a), 2.0)
	draw_colored_polygon(PackedVector2Array([pole, pole + Vector2(12, 5), pole + Vector2(0, 10)]), Color(ScorecardStyle.RED, a))
	draw_string(pencil, rect.position + Vector2(32, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ScorecardStyle.PENCIL, a))
