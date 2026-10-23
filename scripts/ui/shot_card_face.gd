extends Control
class_name ShotCardFace

## Drawn icon for a shot card (no font glyphs): the shape a card gives the
## flight, in ink on the card face. kind comes from ShotCardFace.kind_for().

const INK := Color(0.13, 0.13, 0.11)
const ACCENT := Color(0.78, 0.5, 0.12)

var kind: String = ""
var strength: float = 1.0  # 1 = gentle, 2 = hard (Draw vs Hard Draw)


static func kind_for(data: CardData) -> Dictionary:
	"""{kind, tag, strength} for a card's face, read from its EffectShotShape."""
	if data.card_type == CardData.CardType.NEGATIVE:
		return {"kind": "strain", "tag": "CURSE", "strength": 1.0}
	for e in data.effects:
		if e is EffectPuttCard:
			if e.read_green:
				return {"kind": "read", "tag": "GREEN", "strength": 1.0}
			if e.reach_bonus > 0:
				return {"kind": "firm", "tag": "GREEN", "strength": 1.0}
			if e.dead_weight:
				return {"kind": "dead", "tag": "GREEN", "strength": 1.0}
		if e is EffectCourseUtility:
			return {"kind": e.action, "tag": "UTILITY", "strength": 1.0}
		if e is EffectShotShape:
			if e.bulge > 0.0:
				return {"kind": "draw", "tag": "SHAPE", "strength": 2.0 if e.bulge > 2.0 else 1.0}
			if e.bulge < 0.0:
				return {"kind": "fade", "tag": "SHAPE", "strength": 2.0 if e.bulge < -2.0 else 1.0}
			if e.loft:
				return {"kind": "loft", "tag": "FLIGHT", "strength": 1.0}
			if e.ignore_wind:
				return {"kind": "wind", "tag": "FLIGHT", "strength": 1.0}
			if e.roll_mod < 0:
				return {"kind": "stop", "tag": "LANDING", "strength": 1.0}
			if e.roll_mod > 0:
				return {"kind": "release", "tag": "LANDING", "strength": 1.0}
			if e.ring_mod < 0:
				return {"kind": "dart", "tag": "LANDING", "strength": 1.0}
	return {"kind": "", "tag": "SHOT", "strength": 1.0}


static func cost_for(data: CardData, upgrade_level: int = 0) -> int:
	for e in data.effects:
		if e is EffectShotShape:
			return maxi(0, e.power_cost - upgrade_level)
	return 0


const BASE_H := 70.0  # icon height on a card in the hand; bigger = zoomed in


func _draw() -> void:
	# Draw at hand size and let the transform scale it: shapes stay crisp
	var k := maxf(size.y / BASE_H, 0.01)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var c := size / k / 2.0
	var h := minf(size.x, size.y) / k * 0.42
	var w := 2.5
	match kind:
		"draw", "fade":
			# Flight from the ball (bottom) to the target (top), bowing out and back
			var side := 1.0 if kind == "fade" else -1.0
			var bow := h * 0.45 * strength * side
			var pts := PackedVector2Array()
			for i in range(17):
				var t := i / 16.0
				pts.append(Vector2(c.x - bow * 4.0 * t * (1.0 - t), c.y + h - 2.0 * h * t))
			draw_polyline(pts, INK, w + strength - 1.0, true)
			draw_circle(pts[0], 4.0, INK)
			_flag(pts[pts.size() - 1])
		"loft":
			var pts := PackedVector2Array()
			for i in range(17):
				var t := i / 16.0
				pts.append(Vector2(c.x - h + 2.0 * h * t, c.y + h * 0.6 - sin(t * PI) * h * 1.4))
			draw_polyline(pts, INK, w, true)
			draw_circle(pts[0], 4.0, INK)
			# tree under the arc
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - 9, c.y + h * 0.6), Vector2(c.x + 9, c.y + h * 0.6), Vector2(c.x, c.y - h * 0.05)]), ACCENT)
		"wind":
			for i in range(3):
				var y := c.y - h * 0.5 + i * h * 0.5
				var pts := PackedVector2Array()
				for j in range(13):
					var t := j / 12.0
					pts.append(Vector2(c.x - h + 2.0 * h * t, y + sin(t * TAU) * 4.0))
				draw_polyline(pts, INK, 2.0, true)
			draw_line(c + Vector2(-h, h), c + Vector2(h, -h), ACCENT, 3.0, true)
		"stop":
			draw_circle(c + Vector2(-h * 0.5, 0), 6.0, INK)
			draw_rect(Rect2(c + Vector2(h * 0.15, -h * 0.4), Vector2(h * 0.8, h * 0.8)), ACCENT)
		"release":
			draw_circle(c + Vector2(-h * 0.8, 0), 6.0, INK)
			for i in range(3):
				var x := c.x - h * 0.4 + i * h * 0.45
				draw_line(Vector2(x, c.y), Vector2(x + h * 0.25, c.y), INK, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(h, 0), c + Vector2(h * 0.7, -7), c + Vector2(h * 0.7, 7)]), INK)
		"dart":
			draw_arc(c, h * 0.9, 0, TAU, 32, INK, 2.0, true)
			draw_arc(c, h * 0.55, 0, TAU, 32, INK, 2.0, true)
			draw_circle(c, h * 0.2, ACCENT)
		"read":
			# An eye
			var eye := PackedVector2Array()
			for i in range(17):
				var t := i / 16.0
				eye.append(Vector2(c.x - h + 2.0 * h * t, c.y - sin(t * PI) * h * 0.55))
			for i in range(17):
				var t := 1.0 - i / 16.0
				eye.append(Vector2(c.x - h + 2.0 * h * t, c.y + sin(t * PI) * h * 0.55))
			draw_polyline(eye, INK, 2.0, true)
			draw_circle(c, h * 0.28, ACCENT)
			draw_circle(c, h * 0.12, INK)
		"firm":
			draw_circle(c + Vector2(-h * 0.9, 0), 5.0, INK)
			draw_line(c + Vector2(-h * 0.6, 0), c + Vector2(h * 0.7, 0), INK, 4.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(h, 0), c + Vector2(h * 0.6, -9), c + Vector2(h * 0.6, 9)]), ACCENT)
		"dead":
			# A ball sitting on a weight
			draw_rect(Rect2(c + Vector2(-h * 0.6, h * 0.1), Vector2(h * 1.2, h * 0.55)), ACCENT)
			draw_circle(c + Vector2(0, -h * 0.25), 7.0, INK)
		"extinguish":
			# Red canister and a nozzle
			draw_rect(Rect2(c + Vector2(-h * 0.25, -h * 0.4), Vector2(h * 0.5, h * 1.3)), Color(0.75, 0.15, 0.1))
			draw_rect(Rect2(c + Vector2(-h * 0.12, -h * 0.6), Vector2(h * 0.24, h * 0.2)), INK)
			draw_line(c + Vector2(h * 0.12, -h * 0.55), c + Vector2(h * 0.75, -h * 0.75), INK, 3.0, true)
			for i in range(3):
				draw_circle(c + Vector2(h * 0.85 + i * 4.0, -h * 0.85 + i * 6.0), 3.0, Color(0.6, 0.6, 0.6))
		"groundskeeper":
			# Rake
			draw_line(c + Vector2(-h * 0.8, h * 0.9), c + Vector2(h * 0.3, -h * 0.4), INK, 3.0, true)
			var head := c + Vector2(h * 0.3, -h * 0.4)
			draw_line(head + Vector2(-h * 0.35, -h * 0.35), head + Vector2(h * 0.35, h * 0.35), INK, 3.0, true)
			for i in range(5):
				var p := head + Vector2(-h * 0.35, -h * 0.35).lerp(Vector2(h * 0.35, h * 0.35), i / 4.0)
				draw_line(p, p + Vector2(h * 0.2, -h * 0.2), ACCENT, 2.0, true)
		"shutoff":
			# Valve wheel
			draw_arc(c, h * 0.7, 0, TAU, 32, INK, 3.0, true)
			for i in range(4):
				var a := i * PI / 2.0 + PI / 4.0
				draw_line(c, c + Vector2(cos(a), sin(a)) * h * 0.7, INK, 2.5, true)
			draw_circle(c, h * 0.18, ACCENT)
		"eraser":
			# A pencil eraser rubbing out a stroke
			draw_line(c + Vector2(-h, h * 0.55), c + Vector2(h, h * 0.55), INK, 2.0, true)
			draw_line(c + Vector2(-h * 0.2, h * 0.75), c + Vector2(h * 0.2, h * 0.35), Color(0.75, 0.25, 0.2), 3.0, true)
			var body := PackedVector2Array([c + Vector2(-h * 0.5, h * 0.2), c + Vector2(h * 0.1, -h * 0.6), c + Vector2(h * 0.55, -h * 0.25), c + Vector2(-h * 0.05, h * 0.55)])
			draw_colored_polygon(body, Color(0.93, 0.55, 0.6))
			draw_polyline(body + PackedVector2Array([body[0]]), INK, 2.0, true)
		"strain":
			var pts := PackedVector2Array([c + Vector2(-h, -h * 0.3), c + Vector2(-h * 0.4, h * 0.3), c + Vector2(0, -h * 0.3), c + Vector2(h * 0.4, h * 0.3), c + Vector2(h, -h * 0.3)])
			draw_polyline(pts, Color(0.75, 0.25, 0.2), 3.0, true)


func _flag(at: Vector2) -> void:
	draw_line(at + Vector2(0, 2), at + Vector2(0, -14), INK, 2.0)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -14), at + Vector2(10, -10), at + Vector2(0, -6)]), ACCENT)
