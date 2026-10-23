extends Button
class_name ClubLine

## ClubLine - One row of the "CLUB IN HAND | YARDS" table: the club name in
## condensed caps, its carry range pencilled in, and a pencil ellipse round the
## name when it's the club in hand.

var club_name: String = ""
var yards: String = ""


func _init() -> void:
	toggle_mode = true
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, 26)
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	toggled.connect(func(_on): queue_redraw())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var head := ScorecardStyle.header_font()
	var pencil := ScorecardStyle.pencil_font()
	var h := size.y
	if is_hovered() and not button_pressed:
		draw_rect(Rect2(0, 1, size.x, h - 2), Color(ScorecardStyle.RED, 0.07))
	var name_w := head.get_string_size(club_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(head, Vector2(10, h - 7), club_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ScorecardStyle.INK)
	draw_string(pencil, Vector2(size.x - 92, h - 4), yards, HORIZONTAL_ALIGNMENT_RIGHT, 84, 21, ScorecardStyle.PENCIL)
	draw_line(Vector2(0, h - 0.5), Vector2(size.x, h - 0.5), Color(ScorecardStyle.RULE, 0.35), 1.0)
	if button_pressed:
		ScorecardStyle.wobble_ellipse(self, Rect2(3, 1, name_w + 16, h - 2), ScorecardStyle.PENCIL, 2.0, club_name.length())
