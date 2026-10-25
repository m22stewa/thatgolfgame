extends Button
class_name ClubTile

## ClubTile - A club in the Pro Shop, drawn as a landscape yardage card
## (design 4b in "Card Tray - Scorecard"): a different silhouette from the
## action cards so clubs never get confused with them. Inked grey while
## Common; an upgraded club takes its tier's colour (blue, purple, gold).
## Left: an ink column with the club code, its tier if better than Common, and
## the uses left this hole.
## Right: name and yards, a flight diagram drawn from carry / arc / roll on
## grid paper, and the accuracy rings, spread and loft along the bottom.
## As a toggle, a picked club gets a red border and a pencil tick; otherwise
## a red border on hover. The putter is always in (locked).

const DESIGN := Vector2(214, 150)  # the card as designed; drawn at SCALE
const SCALE := 1.1
const SIZE := DESIGN * SCALE
const MIN_FONT := 10  # small labels never shrink below this
const PAPER := Color("#f6f1e3")
const PAPER_OFF := Color("#e6dfcc")  # not in the bag
const PENCIL := Color("#4a4a48")
const ZONE := Color("#b8432f")
const INK_DARKEN := 0.25  # tier colours, a shade darker to read as ink on paper
const MAX_CARRY := 26.0  # hexes across the flight diagram
const MAX_ARC := 13.0

var item: ClubItem
var stats: Dictionary = {}  # the club's stats with its tier applied (ClubItem.apply)
var locked := false  # the putter: always in the bag
var uses := 0        # swings per hole (0: unlimited)
var spent := 0       # swings taken this hole

var _k := SCALE  # design px -> tile px


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = SIZE
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	toggled.connect(func(_on): queue_redraw())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


static func short_code(club_name: String) -> String:
	"""1W, 3W, 5i, PW, SW, PT."""
	match club_name:
		"Driver":
			return "1W"
		"Putter":
			return "PT"
	var words := club_name.split(" ")
	if club_name.ends_with("Wedge"):
		return words[0].left(1) + "W"
	return words[0] + ("W" if club_name.ends_with("Wood") else "i")


func _draw() -> void:
	_k = size.x / DESIGN.x
	var head := ScorecardStyle.header_font()
	var head_light := ScorecardStyle.header_font(false)
	var pencil := ScorecardStyle.pencil_font()
	var ink := item.color().darkened(INK_DARKEN)
	var on := toggle_mode and (button_pressed or locked)
	var dim := toggle_mode and not on
	var cmin := int(stats.get("band_min", 0))
	var cmax := int(stats.get("band_max", 0))

	# Shadow, paper, double ink border
	draw_rect(_r(0, 2, 214, 150), Color(0, 0, 0, 0.12))
	draw_rect(_r(2, 6, 210, 148), Color(0, 0, 0, 0.1))
	draw_rect(_r(0, 0, 214, 150), PAPER_OFF if dim else PAPER)
	draw_rect(_r(0.75, 0.75, 212.5, 148.5), ink, false, 1.5 * _k)
	draw_rect(_r(5.5, 5.5, 203, 139), ink, false, maxf(1.0, _k))

	# Left: ink column with code, tier and uses left
	draw_rect(_r(6, 6, 46, 138), ink)
	_text(head, short_code(item.club_name), 29, 30, 24, PAPER, HORIZONTAL_ALIGNMENT_CENTER, 46)
	if item.tier > ClubItem.Tier.COMMON:
		var tier := item.tier_name()
		var fs := _fs(9)
		while fs > 7 and head.get_string_size(tier, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 42 * _k:
			fs -= 1
		draw_rect(_r(8, 38, 42, 13), PAPER)
		draw_string(head, _p(29, 48) - Vector2(21 * _k, 0), tier, HORIZONTAL_ALIGNMENT_CENTER, 42 * _k, fs, ink)
	_text(head, "LEFT", 29, 95, 8, PAPER, HORIZONTAL_ALIGNMENT_CENTER, 46)
	draw_circle(_p(29, 112), 15 * _k, PAPER)
	var left := "∞" if uses == 0 else str(maxi(0, uses - spent))
	_text(pencil, left, 29, 121, 28, PENCIL, HORIZONTAL_ALIGNMENT_CENTER, 46)
	_text(head_light, "of %s" % ("∞" if uses == 0 else str(uses)), 29, 139, 10, PAPER, HORIZONTAL_ALIGNMENT_CENTER, 46)

	# Header: name (shrunk to fit) and yards
	var yds := "%d–%d yd" % [cmin * 10, cmax * 10]
	var yds_w := head_light.get_string_size(yds, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs(11)).x
	var name := item.club_name.to_upper()
	var name_fs := _fs(17)
	while name_fs > MIN_FONT and head.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).x > 143 * _k - yds_w:
		name_fs -= 1
	draw_string(head, _p(58, 24), name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs, ink)
	draw_string(head_light, _p(202, 23) - Vector2(yds_w, 0), yds, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs(11), ink)
	draw_line(_p(52, 30), _p(208, 30), ink, maxf(1.0, _k))

	# Flight diagram on grid paper
	var grid := Color(ink, 0.11)
	for gx in range(0, 156, 10):
		draw_line(_p(52 + gx, 30), _p(52 + gx, 113), grid, 1.0)
	for gy in range(0, 84, 10):
		draw_line(_p(52, 30 + gy), _p(208, 30 + gy), grid, 1.0)
	_draw_flight(Vector2(56, 55), 148.0, 58.0, cmin, cmax, ink)
	draw_line(_p(52, 113), _p(208, 113), ink, maxf(1.0, _k))

	# Bottom: rings | spread | loft
	var sep := Color(ink, 0.27)
	draw_line(_p(82, 113), _p(82, 144), sep, 1.0)
	draw_line(_p(145, 113), _p(145, 144), sep, 1.0)
	var rings := int(stats.get("accuracy", 1))
	for i in range(rings):
		draw_arc(_p(67, 128.5), (4 + i * 4.5) * 28.0 / 30.0 * _k, 0, TAU, 32, ink, 1.3 * _k, true)
	draw_circle(_p(67, 128.5), 1.6 * _k, ZONE)
	_text(head, "SPREAD", 113.5, 123, 8, ink, HORIZONTAL_ALIGNMENT_CENTER, 62)
	_text(pencil, str(int(stats.get("base_spread", 0))), 113.5, 141, 20, PENCIL, HORIZONTAL_ALIGNMENT_CENTER, 62)
	_text(head, "LOFT", 176.5, 123, 8, ink, HORIZONTAL_ALIGNMENT_CENTER, 62)
	var loft := int(stats.get("loft", 0))
	for i in range(5):
		var c := _p(166.5 + i * 7, 132.5)
		if i < loft:
			draw_circle(c, 2.5 * _k, ink)
		draw_arc(c, 2.5 * _k, 0, TAU, 12, ink, 1.0, true)

	# Picked: red border and a pencil tick
	var hover := is_hovered() and not locked
	if on or hover:
		draw_rect(Rect2(Vector2.ZERO, size), ScorecardStyle.RED, false, 4.0 if on else 2.0)
	if on:
		ScorecardStyle.check_mark(self, _p(184, 36), 18 * _k)


func _draw_flight(origin: Vector2, w: float, ht: float, cmin: int, cmax: int, ink: Color) -> void:
	"""The carry band in red on a yardage ruler, the arc dashed in pencil up to
	the middle of the band, and the roll after it."""
	var X := func(v: float) -> float: return origin.x + 6 + v / MAX_CARRY * (w - 12)
	var base := origin.y + ht - 8
	var arc := float(stats.get("arc_height", 0.0))
	var top := base - arc / MAX_ARC * (ht - 16)
	var x0: float = X.call(0)
	var land: float = X.call((cmin + cmax) / 2.0)
	draw_line(_p(origin.x + 4, base), _p(origin.x + w - 4, base), ink, maxf(1.0, _k))
	for v in range(0, int(MAX_CARRY) + 1, 2):
		draw_line(_p(X.call(v), base), _p(X.call(v), base + (6 if v % 10 == 0 else 3)), ink, 1.0)
	var zone := Rect2(_p(X.call(cmin), base - 4), Vector2(X.call(cmax) - X.call(cmin), 4) * _k)
	draw_rect(zone, Color(ZONE, 0.7))
	var path := PackedVector2Array()
	if arc > 0:
		var ctrl := Vector2((x0 + X.call(cmax)) / 2.0, 2 * top - base)
		for i in range(25):
			var t := i / 24.0
			var p := Vector2(x0, base).lerp(ctrl, t).lerp(ctrl.lerp(Vector2(land, base), t), t)
			path.append(_p(p.x, p.y))
	else:  # the putter rolls along the ground
		path.append(_p(x0, base - 2))
		path.append(_p(X.call(cmax), base - 2))
	_dashed(path, 4 * _k, 3 * _k, PENCIL, 1.6 * _k)
	var roll := int(stats.get("roll", 0))
	if roll > 0:
		draw_line(_p(land, base - 1), _p(land + roll * (w - 12) / MAX_CARRY, base - 1), PENCIL, 2.4 * _k)
	draw_circle(_p(x0, base - 2.5), 2.5 * _k, ink)


func _dashed(path: PackedVector2Array, dash: float, gap: float, color: Color, width: float) -> void:
	"""A dashed polyline: dash on, gap off, carried across the path's corners."""
	var drawing := true
	var left := dash
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var seg := a.distance_to(b)
		var at := 0.0
		while at < seg:
			var step := minf(left, seg - at)
			if drawing:
				draw_line(a.lerp(b, at / seg), a.lerp(b, (at + step) / seg), color, width, true)
			at += step
			left -= step
			if left <= 0.0:
				drawing = not drawing
				left = dash if drawing else gap


func _p(x: float, y: float) -> Vector2:
	return Vector2(x, y) * _k


func _r(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(_p(x, y), Vector2(w, h) * _k)


func _fs(design_size: int) -> int:
	return maxi(MIN_FONT, roundi(design_size * _k))


func _text(font: Font, text: String, cx: float, baseline: float, design_size: int, color: Color, align: HorizontalAlignment, box_w: float) -> void:
	"""Text centred on cx (design px) in a box_w wide box."""
	draw_string(font, _p(cx - box_w / 2.0, baseline), text, align, box_w * _k, _fs(design_size), color)
