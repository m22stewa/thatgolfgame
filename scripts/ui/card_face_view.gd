extends Control
class_name CardFaceView

## CardFaceView - A shot card drawn as a scorecard slip: coloured category bar,
## a gold coin with the card's Money cost, a condensed title, the drawn icon on
## grid paper, a one-line effect, and a stat row with pencilled values. A played
## card gets a pencil tick; a Strain card is stamped UNPLAYABLE.
##
## Drawn at any size: everything scales with size.x / SIZE.x, so the zoomed-in
## card (CardZoom) is as sharp as the one in the hand.

const SIZE := Vector2(186, 254)
const BAR_H := 28.0
const ART_TOP := 74.0
const ART_H := 74.0
const STAT_H := 52.0
const COIN := Color(0.95, 0.76, 0.26)
const COIN_RIM := Color(0.6, 0.42, 0.08)

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
var cost: int = 0
var affordable: bool = true:  # false: the coin turns red (not enough Money)
	set(v):
		affordable = v
		queue_redraw()
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
	cost = ShotCardFace.cost_for(data, instance.upgrade_level)
	cost_text = "–" if unplayable else "%d" % cost
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
	var k := size.x / SIZE.x  # 1 in the hand, ~2.6 zoomed in
	var icon_rect := Rect2(10 * k, (ART_TOP + 2) * k, size.x - 20 * k, (ART_H - 4) * k)
	if _icon.position != icon_rect.position or _icon.size != icon_rect.size:
		_icon.position = icon_rect.position
		_icon.size = icon_rect.size
		_icon.queue_redraw()
	var w := size.x
	var h := size.y
	var bar_h := BAR_H * k
	var head := ScorecardStyle.header_font()
	var head_light := ScorecardStyle.header_font(false)
	var pencil := ScorecardStyle.pencil_font()
	var ink := ScorecardStyle.INK
	draw_rect(Rect2(Vector2.ZERO, size), ScorecardStyle.PAPER_DARK if unplayable else ScorecardStyle.PAPER)

	# Category bar
	var bar := ScorecardStyle.category_color(tag)
	draw_rect(Rect2(0, 0, w, bar_h), bar)
	draw_string(head, Vector2(10 * k, bar_h - 8 * k), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k), ScorecardStyle.PAPER)

	# Title, shrunk to fit
	var title_size := 30
	while title_size > 16 and head.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(title_size * k)).x > w - 16 * k:
		title_size -= 1
	draw_string(head, Vector2(10 * k, bar_h + 37 * k), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 16 * k, int(title_size * k), ink)

	# Grid paper under the icon
	var art := Rect2(8 * k, ART_TOP * k, w - 16 * k, ART_H * k)
	draw_rect(art, Color(1, 1, 1, 0.35))
	var step := 8.0 * k
	var x := art.position.x + step
	while x < art.end.x:
		draw_line(Vector2(x, art.position.y), Vector2(x, art.end.y), ScorecardStyle.GRID, k)
		x += step
	var y := art.position.y + step
	while y < art.end.y:
		draw_line(Vector2(art.position.x, y), Vector2(art.end.x, y), ScorecardStyle.GRID, k)
		y += step
	draw_rect(art, Color(ink, 0.35), false, k)

	# Effect line
	draw_multiline_string(head_light, Vector2(8 * k, (ART_TOP + ART_H + 18) * k), description, HORIZONTAL_ALIGNMENT_LEFT, w - 16 * k, int(14 * k), 2, ScorecardStyle.INK_SOFT)

	# Stat row: small caps labels, pencilled values
	var top := h - STAT_H * k
	draw_line(Vector2(0, top), Vector2(w, top), ScorecardStyle.RULE, k)
	if not stats.is_empty():
		var cw := w / float(stats.size())
		for i in range(stats.size()):
			var cx := cw * i
			if i > 0:
				draw_line(Vector2(cx, top), Vector2(cx, h), ScorecardStyle.RULE, k)
			draw_string(head_light, Vector2(cx, top + 15 * k), stats[i][0], HORIZONTAL_ALIGNMENT_CENTER, cw, int(12 * k), ScorecardStyle.INK_SOFT)
			draw_string(pencil, Vector2(cx, top + 45 * k), stats[i][1], HORIZONTAL_ALIGNMENT_CENTER, cw, int(30 * k), ScorecardStyle.PENCIL)

	draw_rect(Rect2(Vector2.ZERO, size), ink, false, 2.0 * k)

	# Cost: a gold coin on the top-right corner, the card's price in Money
	if not unplayable and cost_text != "":
		var at := Vector2(w - 24 * k, 22 * k)
		var r := 19.0 * k
		draw_circle(at + Vector2(0, 2 * k), r, Color(0, 0, 0, 0.25))
		draw_circle(at, r, COIN if affordable else ScorecardStyle.PAPER_DARK)
		draw_arc(at, r, 0, TAU, 32, COIN_RIM if affordable else ScorecardStyle.RED, 2.5 * k, true)
		draw_arc(at, r - 4 * k, 0, TAU, 32, Color(COIN_RIM, 0.45), k, true)
		var fs := int(26 * k)
		var tw := head.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(head, at + Vector2(-tw.x / 2.0, fs * 0.36), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink if affordable else ScorecardStyle.RED)

	if played:
		ScorecardStyle.check_mark(self, Vector2(w - 40 * k, bar_h + 26 * k), 30 * k)
	if unplayable:
		_stamp("UNPLAYABLE")


func _stamp(text: String) -> void:
	var k := size.x / SIZE.x
	var font := ScorecardStyle.header_font()
	var c := size / 2.0 + Vector2(0, -6 * k)
	draw_set_transform(c, -0.32, Vector2.ONE)
	var fs := int(22 * k)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(-tw / 2.0 - 8 * k, -18 * k, tw + 16 * k, 30 * k)
	draw_rect(box, Color(ScorecardStyle.PAPER, 0.7))
	draw_rect(box, ScorecardStyle.RED, false, 3.0 * k)
	draw_string(font, Vector2(-tw / 2.0, 6 * k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ScorecardStyle.RED)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
