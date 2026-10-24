extends Button
class_name ClubTile

## ClubTile - A club in the Pro Shop: a header bar in its tier colour (grey,
## blue, purple, gold) with the tier name, the club's name, its carry range
## and its features. Toggles in and out of the bag for the hole; a picked club
## gets a red border and a pencil tick. The putter is always in (locked).

const SIZE := Vector2(150, 168)

var item: ClubItem
var yards: String = ""
var locked := false  # the putter: always in the bag
var uses := 0        # swings per hole (0: unlimited)


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = SIZE
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	toggled.connect(func(_on): queue_redraw())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var head := ScorecardStyle.header_font()
	var head_light := ScorecardStyle.header_font(false)
	var pencil := ScorecardStyle.pencil_font()
	var w := size.x
	var h := size.y
	var on := button_pressed or locked
	draw_rect(Rect2(Vector2.ZERO, size), ScorecardStyle.PAPER if on else ScorecardStyle.PAPER_DARK)
	var bar := item.color()
	draw_rect(Rect2(0, 0, w, 26), bar)
	draw_string(head, Vector2(8, 19), item.tier_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ScorecardStyle.PAPER)
	# Name, shrunk to fit
	var name := item.club_name.to_upper()
	var fs := 26
	while fs > 14 and head.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 46:  # clear of the tick
		fs -= 1
	draw_string(head, Vector2(8, 54), name, HORIZONTAL_ALIGNMENT_LEFT, w - 16, fs, ScorecardStyle.INK)
	draw_string(pencil, Vector2(8, 82), yards, HORIZONTAL_ALIGNMENT_LEFT, w - 16, 24, ScorecardStyle.PENCIL)
	var y := 104.0
	var lines := item.feature_lines()
	if lines.is_empty():
		lines = ["NO EXTRAS"] as Array[String]
	for line in lines:
		draw_string(head_light, Vector2(8, y), line, HORIZONTAL_ALIGNMENT_LEFT, w - 16, 14, bar.darkened(0.25) if line != "NO EXTRAS" else ScorecardStyle.INK_SOFT)
		y += 18.0
	var border := ScorecardStyle.RED if on else ScorecardStyle.RULE
	if is_hovered() and not locked:
		border = ScorecardStyle.RED
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 4.0 if on else 2.0)
	if on:
		ScorecardStyle.check_mark(self, Vector2(w - 34, 32), 24)
	if locked:
		draw_string(head_light, Vector2(8, h - 10), "ALWAYS IN THE BAG", HORIZONTAL_ALIGNMENT_LEFT, w - 16, 12, ScorecardStyle.INK_SOFT)
	elif uses > 0:
		draw_string(head_light, Vector2(8, h - 10), "%d USE%s A HOLE" % [uses, "" if uses == 1 else "S"], HORIZONTAL_ALIGNMENT_LEFT, w - 16, 12, ScorecardStyle.INK)
