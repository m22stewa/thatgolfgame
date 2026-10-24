extends Control
class_name ChipBadge

## ChipBadge - The Chips there are to play cards with this hole: a casino chip
## with the count, and what the cards on the playmat will spend.

var chips := 0
var committed := 0  # cost of the cards on the playmat this shot
var unlimited := false  # the driving range: cards are free
var _flash := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(300, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_chip_stack(p_chips: int, p_committed: int) -> void:
	chips = p_chips
	committed = p_committed
	queue_redraw()


func flash() -> void:
	"""Not enough Chips: blink the chip grey."""
	var t := create_tween()
	t.tween_method(func(v: float):
		_flash = v
		queue_redraw(), 1.0, 0.0, 0.6)


func _draw() -> void:
	var head := ScorecardStyle.header_font()
	var at := Vector2(size.x - 22, size.y / 2.0)
	var txt := "∞" if unlimited else "%d" % (chips - committed)
	ScorecardStyle.draw_chip(self, at, 19.0, txt, 22, _flash < 0.5)
	# Caption to the left: CHIPS, and the spend when cards are on the mat
	var caption := "CHIPS" if committed == 0 or unlimited else "CHIPS  %d  −%d ON THE MAT  =" % [chips, committed]
	draw_string(head, Vector2(0, size.y / 2.0 + 7), caption, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 50, 18,
		ScorecardStyle.RED if committed > 0 and not unlimited else ScorecardStyle.INK)
