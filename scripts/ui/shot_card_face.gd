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


static func cost_for(data: CardData) -> int:
	for e in data.effects:
		if e is EffectShotShape:
			return e.power_cost
	return 0


func _draw() -> void:
	var c := size / 2.0
	var h := minf(size.x, size.y) * 0.42
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
		"strain":
			var pts := PackedVector2Array([c + Vector2(-h, -h * 0.3), c + Vector2(-h * 0.4, h * 0.3), c + Vector2(0, -h * 0.3), c + Vector2(h * 0.4, h * 0.3), c + Vector2(h, -h * 0.3)])
			draw_polyline(pts, Color(0.75, 0.25, 0.2), 3.0, true)


func _flag(at: Vector2) -> void:
	draw_line(at + Vector2(0, 2), at + Vector2(0, -14), INK, 2.0)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -14), at + Vector2(10, -10), at + Vector2(0, -6)]), ACCENT)
