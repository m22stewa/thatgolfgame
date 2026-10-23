extends Control
class_name ConditionsStrip

## ConditionsStrip - Wind and lie for the shot, in the tray under THIS SHOT,
## drawn like the scorecard: two ruled boxes with small-caps captions and
## pencilled values. WIND: an arrow showing where the wind blows as seen from
## the camera (it turns as the view turns), its strength in ticks, and speed.
## LIE: where the ball sits and what that does to the shot.

const SIZE := Vector2(380, 74)

var wind_on := false
var wind_screen := Vector2.UP  # where the wind blows to, on screen (unit)
var wind_strength := 0         # 0-3
var wind_name := "CALM"
var wind_kmh := 0
var lie_name := ""
var lie_effects := ""


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_wind(on: bool, screen_dir: Vector2, strength: int, name: String, kmh: int) -> void:
	if on == wind_on and screen_dir.is_equal_approx(wind_screen) and strength == wind_strength and kmh == wind_kmh:
		return
	wind_on = on
	wind_screen = screen_dir
	wind_strength = strength
	wind_name = name.to_upper()
	wind_kmh = kmh
	queue_redraw()


func set_lie(name: String, effects: String) -> void:
	lie_name = name.to_upper()
	lie_effects = effects.to_upper()
	queue_redraw()


func _draw() -> void:
	var head := ScorecardStyle.header_font()
	var head_light := ScorecardStyle.header_font(false)
	var pencil := ScorecardStyle.pencil_font()
	var h := size.y
	var half := size.x / 2.0 - 6.0

	# WIND
	var wind := Rect2(0, 0, half, h)
	_box(wind, "WIND")
	var c := Vector2(wind.position.x + 30, h / 2.0 + 8)
	draw_arc(c, 20, 0, TAU, 32, Color(ScorecardStyle.RULE, 0.5), 1.0, true)
	if wind_on and wind_strength > 0:
		var d := wind_screen.normalized()
		var tip := c + d * 17.0
		var tail := c - d * 17.0
		draw_line(tail, tip, ScorecardStyle.RED, 3.0, true)
		var side := d.orthogonal() * 6.0
		draw_colored_polygon(PackedVector2Array([tip + d * 2.0, tip - d * 9.0 + side, tip - d * 9.0 - side]), ScorecardStyle.RED)
		draw_string(pencil, Vector2(c.x + 32, h / 2.0 + 6), wind_name.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, half - 70, 26, ScorecardStyle.PENCIL)
		# Strength ticks and speed
		for i in range(3):
			var r := Rect2(c.x + 32 + i * 12, h - 16, 8, 8)
			draw_rect(r, ScorecardStyle.RED if i < wind_strength else Color(ScorecardStyle.RULE, 0.25))
		draw_string(head_light, Vector2(c.x + 72, h - 8), "%d KM/H" % wind_kmh, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ScorecardStyle.INK_SOFT)
	else:
		draw_circle(c, 4, ScorecardStyle.PENCIL)
		draw_string(pencil, Vector2(c.x + 32, h / 2.0 + 14), "Calm", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ScorecardStyle.PENCIL)

	# LIE
	var lie := Rect2(half + 12, 0, half, h)
	_box(lie, "LIE")
	draw_string(pencil, Vector2(lie.position.x + 10, h / 2.0 + 8), lie_name.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, half - 20, 26, ScorecardStyle.PENCIL)
	draw_string(head_light, Vector2(lie.position.x + 10, h - 8), lie_effects, HORIZONTAL_ALIGNMENT_LEFT, half - 20, 13, ScorecardStyle.INK_SOFT)


func _box(r: Rect2, caption: String) -> void:
	"""A ruled scorecard cell with its caption in the top-left."""
	draw_rect(r, Color(ScorecardStyle.RULE, 0.85), false, 1.5)
	draw_string(ScorecardStyle.header_font(false), r.position + Vector2(8, 15), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ScorecardStyle.INK_SOFT)
