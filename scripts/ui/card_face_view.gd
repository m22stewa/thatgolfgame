extends Control
class_name CardFaceView

## CardFaceView - A shot card drawn as a scorecard slip: coloured category bar
## with the cost, a condensed title, the drawn icon on grid paper, a one-line
## effect, and a stat row with pencilled values. A played card gets a pencil
## tick; a Strain card is stamped UNPLAYABLE.

const SIZE := Vector2(150, 204)
const BAR_H := 22.0
const ART_TOP := 58.0
const ART_H := 62.0
const STAT_H := 40.0

var tag: String = "SHOT"
var cost_text: String = ""
var title: String = ""
var description: String = ""
var stats: Array = []  # [[label, value], ...]
var played: bool = false:
	set(v):
		played = v
		queue_redraw()
var unplayable: bool = false
var _icon: ShotCardFace


static func for_instance(instance) -> CardFaceView:
	var face := CardFaceView.new()
	face.set_card(instance)
	return face


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = ShotCardFace.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)


func set_card(instance) -> void:
	var data: CardData = instance.data
	var info := ShotCardFace.kind_for(data)
	tag = info.tag
	unplayable = info.kind == "strain"
	var cost := ShotCardFace.cost_for(data, instance.upgrade_level)
	cost_text = "–" if unplayable else ("%d" % cost if cost > 0 else "FREE")
	title = instance.get_display_name()
	description = data.description.split(" (")[0]
	stats = stats_for(data)
	_icon.kind = info.kind
	_icon.strength = info.strength
	_icon.queue_redraw()
	queue_redraw()


func set_icon(kind: String) -> void:
	_icon.kind = kind
	_icon.queue_redraw()


static func stats_for(data: CardData) -> Array:
	"""Three [label, value] pairs for the card's stat row."""
	for e in data.effects:
		if e is EffectShotShape:
			var curve := "–"
			if e.bulge != 0.0:
				curve = "%s%d" % ["L" if e.bulge > 0.0 else "R", 2 if absf(e.bulge) > 2.0 else 1]
			var mid := ["FLIGHT", "HIGH" if e.loft else ("LOW" if e.ignore_wind else "–")]
			if e.ring_mod != 0:
				mid = ["RING", "%d" % e.ring_mod]
			var roll := "–"
			if e.roll_mod <= -10:
				roll = "0"
			elif e.roll_mod != 0:
				roll = "%+d" % e.roll_mod
			return [["CURVE", curve], mid, ["ROLL", roll]]
		if e is EffectPuttCard:
			return [["READ", "YES" if e.read_green else "–"], ["REACH", "+%d" % e.reach_bonus if e.reach_bonus > 0 else "–"], ["ROLL", "DEAD" if e.dead_weight else "–"]]
		if e is EffectCourseUtility:
			var target: String = {"extinguish": "FIRE", "groundskeeper": "ALL", "shutoff": "WIND+H2O"}.get(e.action, "–")
			return [["USE", "NOW"], ["HITS", target]]
	if data.card_type == CardData.CardType.NEGATIVE:
		return [["CURVE", "–"], ["CARRY", "–"], ["ROLL", "–"]]
	return []


func _draw() -> void:
	var icon_rect := Rect2(10, ART_TOP + 2, size.x - 20, ART_H - 4)
	if _icon.position != icon_rect.position or _icon.size != icon_rect.size:
		_icon.position = icon_rect.position
		_icon.size = icon_rect.size
		_icon.queue_redraw()
	var w := size.x
	var h := size.y
	var head := ScorecardStyle.header_font()
	var head_light := ScorecardStyle.header_font(false)
	var pencil := ScorecardStyle.pencil_font()
	var ink := ScorecardStyle.INK
	draw_rect(Rect2(Vector2.ZERO, size), ScorecardStyle.PAPER_DARK if unplayable else ScorecardStyle.PAPER)

	# Category bar + cost
	var bar := ScorecardStyle.category_color(tag)
	draw_rect(Rect2(0, 0, w, BAR_H), bar)
	draw_string(head, Vector2(8, BAR_H - 6), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ScorecardStyle.PAPER)
	draw_string(head, Vector2(w - 60, BAR_H - 6), cost_text, HORIZONTAL_ALIGNMENT_RIGHT, 52, 12, ScorecardStyle.PAPER)

	# Title, shrunk to fit
	var title_size := 24
	while title_size > 14 and head.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > w - 16:
		title_size -= 1
	draw_string(head, Vector2(8, BAR_H + 30), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 16, title_size, ink)

	# Grid paper under the icon
	var art := Rect2(8, ART_TOP, w - 16, ART_H)
	draw_rect(art, Color(1, 1, 1, 0.35))
	var step := 8.0
	var x := art.position.x + step
	while x < art.end.x:
		draw_line(Vector2(x, art.position.y), Vector2(x, art.end.y), ScorecardStyle.GRID, 1.0)
		x += step
	var y := art.position.y + step
	while y < art.end.y:
		draw_line(Vector2(art.position.x, y), Vector2(art.end.x, y), ScorecardStyle.GRID, 1.0)
		y += step
	draw_rect(art, Color(ink, 0.35), false, 1.0)

	# Effect line
	draw_multiline_string(head_light, Vector2(8, ART_TOP + ART_H + 14), description, HORIZONTAL_ALIGNMENT_LEFT, w - 16, 11, 2, ScorecardStyle.INK_SOFT)

	# Stat row: small caps labels, pencilled values
	var top := h - STAT_H
	draw_line(Vector2(0, top), Vector2(w, top), ScorecardStyle.RULE, 1.0)
	if not stats.is_empty():
		var cw := w / float(stats.size())
		for i in range(stats.size()):
			var cx := cw * i
			if i > 0:
				draw_line(Vector2(cx, top), Vector2(cx, h), ScorecardStyle.RULE, 1.0)
			draw_string(head_light, Vector2(cx, top + 12), stats[i][0], HORIZONTAL_ALIGNMENT_CENTER, cw, 9, ScorecardStyle.INK_SOFT)
			draw_string(pencil, Vector2(cx, top + 34), stats[i][1], HORIZONTAL_ALIGNMENT_CENTER, cw, 22, ScorecardStyle.PENCIL)

	draw_rect(Rect2(Vector2.ZERO, size), ink, false, 2.0)

	if played:
		ScorecardStyle.check_mark(self, Vector2(w - 34, BAR_H + 6), 24)
	if unplayable:
		_stamp("UNPLAYABLE")


func _stamp(text: String) -> void:
	var font := ScorecardStyle.header_font()
	var c := size / 2.0 + Vector2(0, -6)
	draw_set_transform(c, -0.32, Vector2.ONE)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var box := Rect2(-tw / 2.0 - 8, -18, tw + 16, 30)
	draw_rect(box, Color(ScorecardStyle.PAPER, 0.7))
	draw_rect(box, ScorecardStyle.RED, false, 3.0)
	draw_string(font, Vector2(-tw / 2.0, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ScorecardStyle.RED)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
