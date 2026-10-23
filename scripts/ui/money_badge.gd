extends Control
class_name MoneyBadge

## MoneyBadge - How much Money there is to play cards with this hole: a gold
## coin with the amount, and what the cards on the playmat will spend.

var money := 0
var committed := 0  # cost of the cards on the playmat this shot
var _flash := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(300, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_money(p_money: int, p_committed: int) -> void:
	money = p_money
	committed = p_committed
	queue_redraw()


func flash() -> void:
	"""Not enough Money: blink the coin red."""
	var t := create_tween()
	t.tween_method(func(v: float):
		_flash = v
		queue_redraw(), 1.0, 0.0, 0.6)


func _draw() -> void:
	var head := ScorecardStyle.header_font()
	var at := Vector2(size.x - 22, size.y / 2.0)
	var coin := CardFaceView.COIN.lerp(ScorecardStyle.RED, _flash)
	draw_circle(at + Vector2(0, 2), 19, Color(0, 0, 0, 0.25))
	draw_circle(at, 19, coin)
	draw_arc(at, 19, 0, TAU, 32, CardFaceView.COIN_RIM, 2.5, true)
	var left := money - committed
	var txt := "%d" % left
	var tw := head.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	draw_string(head, at + Vector2(-tw.x / 2.0, 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ScorecardStyle.INK)
	# Caption to the left: MONEY, and the spend when cards are on the mat
	var caption := "MONEY" if committed == 0 else "MONEY  %d  −%d ON THE MAT  =" % [money, committed]
	draw_string(head, Vector2(0, size.y / 2.0 + 7), caption, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 50, 18,
		ScorecardStyle.RED if committed > 0 else ScorecardStyle.INK)
