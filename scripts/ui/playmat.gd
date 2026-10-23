extends PanelContainer
class_name Playmat

## Playmat - The felt mat beside the hand where cards are played. Drag a card
## from the hand onto it (or tap the card and press Play) to play it this shot;
## drag it back to the hand (or tap it and Take back) to change your mind. The
## mat only shows what is played: hex_grid decides, main_ui moves the cards.

signal card_dropped(card_instance)  # a hand card was dropped here

const FELT := Color(0.133, 0.227, 0.149)
const FELT_EDGE := Color(0.08, 0.15, 0.09)

var capacity := 3
var slots: HBoxContainer
var _empty: Control


func _init() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = FELT
	box.border_color = FELT_EDGE
	box.set_border_width_all(3)
	box.set_corner_radius_all(12)
	box.set_content_margin_all(8)
	add_theme_stylebox_override("panel", box)
	slots = HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	slots.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(slots)
	_empty = Control.new()
	_empty.custom_minimum_size = CardFaceView.SIZE
	_empty.mouse_filter = Control.MOUSE_FILTER_PASS
	_empty.draw.connect(_draw_empty)
	slots.add_child(_empty)


func cards() -> Array:
	var out: Array = []
	for c in slots.get_children():
		if c != _empty:
			out.append(c)
	return out


func add_card(btn: Control) -> void:
	if btn.get_parent():
		btn.reparent(slots, false)
	else:
		slots.add_child(btn)
	slots.move_child(_empty, -1)
	refresh()


func refresh() -> void:
	"""The dashed slot shows while there is room for another card."""
	_empty.visible = cards().size() < capacity
	_empty.queue_redraw()


func is_full() -> bool:
	return cards().size() >= capacity


func clear() -> void:
	for c in cards():
		c.queue_free()
	_empty.visible = true


func _draw_empty() -> void:
	"""A dashed card outline with how to play."""
	var r := Rect2(Vector2(4, 4), _empty.size - Vector2(8, 8))
	var col := Color(0.85, 0.92, 0.82, 0.55)
	var dash := 10.0
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var n := int(a.distance_to(b) / dash)
		for j in range(0, n, 2):
			_empty.draw_line(a.lerp(b, float(j) / n), a.lerp(b, float(j + 1) / n), col, 2.0)
	var font := ScorecardStyle.header_font()
	var lines := ["DRAG A CARD", "HERE TO", "PLAY IT"] if cards().is_empty() else ["ADD", "ANOTHER"]
	var y := r.get_center().y - (lines.size() - 1) * 13.0
	for line in lines:
		_empty.draw_string(font, Vector2(r.position.x, y + 8), line, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, col)
		y += 26.0


func _can_drop_data(_pos: Vector2, data) -> bool:
	return data is Dictionary and data.has("card") and not data.get("from_mat", false) and not is_full()


func _drop_data(_pos: Vector2, data) -> void:
	card_dropped.emit(data.card)
