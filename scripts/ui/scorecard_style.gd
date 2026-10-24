extends RefCounted
class_name ScorecardStyle

## ScorecardStyle - The golf scorecard look shared by the tray, the cards, the
## Pro Shop and popups: cream paper, thin ink rules, condensed headers
## (Oswald) and pencil numbers (Caveat). Fonts are OFL, in assets/fonts.

const PAPER := Color(0.96, 0.94, 0.87)
const PAPER_DARK := Color(0.9, 0.87, 0.78)
const INK := Color(0.12, 0.12, 0.11)
const INK_SOFT := Color(0.36, 0.35, 0.31)
const RULE := Color(0.12, 0.12, 0.11, 0.85)
const GRID := Color(0.45, 0.6, 0.72, 0.22)
const PENCIL := Color(0.22, 0.22, 0.24)
const RED := Color(0.78, 0.13, 0.11)
const GREEN := Color(0.12, 0.36, 0.2)
const NAVY := Color(0.13, 0.2, 0.38)
const GREY := Color(0.3, 0.3, 0.3)
const TEAL := Color(0.08, 0.4, 0.4)

# Card category -> header bar colour
const CATEGORY_COLORS := {
	"SHAPE": GREEN,
	"FLIGHT": GREEN,
	"LANDING": NAVY,
	"GREEN": TEAL,
	"CURSE": RED,
	"PENALTY": RED,
	"CLUB": GREEN,
	"UTILITY": GREY,
	"MODIFIER": GREY,
	"ITEM": RED,
}

static var _header: Font = null
static var _header_bold: Font = null
static var _pencil: Font = null


static func header_font(bold: bool = true) -> Font:
	"""Oswald, condensed caps for titles and headers."""
	if _header == null:
		var base = load("res://assets/fonts/Oswald.ttf")
		_header = _weighted(base, 500)
		_header_bold = _weighted(base, 700)
	return _header_bold if bold else _header


static func pencil_font() -> Font:
	"""Caveat, the handwritten pencil numbers."""
	if _pencil == null:
		_pencil = _weighted(load("res://assets/fonts/Caveat.ttf"), 600)
	return _pencil


static func _weighted(base, weight: int) -> Font:
	if base == null:
		return ThemeDB.fallback_font
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return v


static func category_color(tag: String) -> Color:
	return CATEGORY_COLORS.get(tag, GREY)


static func paper_box(border: Color = RULE, width: int = 2, bg: Color = PAPER, radius: int = 3) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box


static func label(text: String, size: int, color: Color = INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func flat_button(b: Button, text_color: Color = INK, border: Color = RULE) -> void:
	"""A ruled paper button (shop actions, popups)."""
	b.add_theme_stylebox_override("normal", paper_box(border, 2))
	b.add_theme_stylebox_override("hover", paper_box(RED, 2))
	b.add_theme_stylebox_override("pressed", paper_box(RED, 3, PAPER_DARK))
	b.add_theme_stylebox_override("hover_pressed", paper_box(RED, 3, PAPER_DARK))
	b.add_theme_stylebox_override("disabled", paper_box(Color(INK, 0.3), 2, PAPER_DARK))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", header_font())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, text_color)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.35))


const CHIP := Color(0.72, 0.1, 0.12)  # casino chip red (a ball marker)


static func draw_chip(ci: CanvasItem, at: Vector2, r: float, text: String, font_size: int, ok: bool = true) -> void:
	"""A casino chip, the play currency: red with white edge spots, a cream
	inlay and the amount. ok = false (can't afford) greys it, number in red."""
	var base := CHIP if ok else Color(0.55, 0.53, 0.5)
	ci.draw_circle(at + Vector2(0, r * 0.1), r, Color(0, 0, 0, 0.25))
	ci.draw_circle(at, r, base)
	for i in range(6):
		var a := i * TAU / 6.0
		ci.draw_arc(at, r * 0.84, a - 0.2, a + 0.2, 6, PAPER, r * 0.26)
	ci.draw_circle(at, r * 0.6, PAPER)
	ci.draw_arc(at, r * 0.6, 0, TAU, 32, base.darkened(0.15), maxf(1.0, r * 0.07), true)
	var font := header_font()
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	ci.draw_string(font, at + Vector2(-tw.x / 2.0, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK if ok else RED)


static func wobble_ellipse(ci: CanvasItem, rect: Rect2, color: Color = PENCIL, width: float = 2.0, seed_value: int = 0) -> void:
	"""A hand-drawn pencil ellipse round rect: slightly off-round, overshooting
	where the pencil comes back to the start."""
	var c := rect.get_center()
	var rx := rect.size.x / 2.0
	var ry := rect.size.y / 2.0
	var pts := PackedVector2Array()
	var phase := float(seed_value % 7) * 0.4
	for i in range(41):
		var t := float(i) / 40.0 * TAU * 1.08 - 0.3
		var wob := 1.0 + 0.04 * sin(t * 3.0 + phase)
		pts.append(c + Vector2(cos(t) * rx * wob, sin(t) * ry * (wob + 0.05 * float(i) / 40.0)))
	ci.draw_polyline(pts, color, width, true)


static func check_mark(ci: CanvasItem, at: Vector2, size: float, color: Color = PENCIL) -> void:
	"""A pencil tick, at = top-left of its box."""
	var pts := PackedVector2Array([
		at + Vector2(0.0, size * 0.55),
		at + Vector2(size * 0.35, size * 0.9),
		at + Vector2(size, 0.0),
	])
	ci.draw_polyline(pts, color, 3.0, true)
