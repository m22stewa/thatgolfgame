extends Control
class_name CardZoom

## CardZoom - Tap a card to read it. After Marvel Snap's card view, the card
## zooms up over a dark backdrop at ZOOM times its hand size, with its full
## rules beside it and the actions it allows where it was tapped (Play / Take
## back in the hand; Buy, Remove, Upgrade in the Pro Shop). Tap the backdrop,
## Close or Esc to put it back.
##
## The card flies: it grows out of the card that was tapped into the middle
## of the screen, turning a little on the way, sways gently while it is read,
## and shrinks back down to wherever the card is now (its hand slot, or the
## playmat if it was just played).

const ZOOM := 2.5  # card size vs the hand
const OPEN_TIME := 0.38
const CLOSE_TIME := 0.3
const FLY_TURN := 0.05  # radians of turn mid-flight

var _row: HBoxContainer
var _holder: Control
var _face: CardFaceView = null
var _title: Label
var _cost: Label
var _body: Label
var _note: Label
var _actions: VBoxContainer
var _backdrop: ColorRect
var _side: VBoxContainer
var _source: Control = null      # the card that was tapped
var _return_to := Callable()     # -> Control: where the card is when it closes
var _anchor: Control = null      # the flight's small end (source or return_to)
var _turn := 1.0                 # which way it turns in flight
var _tween: Tween = null
var _sway: Tween = null
var _closing := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.04, 0.06, 0.04, 0.85)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 48)
	center.add_child(_row)
	_holder = Control.new()
	_holder.custom_minimum_size = CardFaceView.SIZE * ZOOM
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_holder)

	var side := VBoxContainer.new()
	_side = side
	side.custom_minimum_size = Vector2(440, 0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 16)
	_row.add_child(side)
	_title = ScorecardStyle.label("", 52, ScorecardStyle.PAPER, ScorecardStyle.header_font())
	side.add_child(_title)
	_cost = ScorecardStyle.label("", 34, Color(1.0, 0.55, 0.5), ScorecardStyle.header_font())
	side.add_child(_cost)
	_body = ScorecardStyle.label("", 26, ScorecardStyle.PAPER, ScorecardStyle.header_font(false))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(440, 0)
	side.add_child(_body)
	_note = ScorecardStyle.label("", 24, Color(1.0, 0.55, 0.5), ScorecardStyle.header_font(false))
	side.add_child(_note)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 12)
	side.add_child(_actions)


func open(instance, actions: Array = [], note: String = "", affordable: bool = true, source: Control = null, return_to: Callable = Callable()) -> void:
	"""Show instance big. actions: [{label, on_press: Callable, disabled}],
	the first is the main one. note: why an action is off (red). source: the
	card tapped (the zoom grows out of it); return_to: returns the card's
	control when it closes (default: source)."""
	_stop_tweens()
	_restore_anchor()
	_closing = false
	if _face:
		_face.queue_free()
	_face = CardFaceView.for_instance(instance)
	_face.size = CardFaceView.SIZE * ZOOM
	_face.affordable = affordable
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)  # flies free of the layout; _holder keeps its spot
	_source = source
	_return_to = return_to
	_title.text = instance.get_display_name().to_upper()
	var cost: int = _face.cost
	_cost.text = "" if _face.unplayable else ("FREE TO PLAY" if cost == 0 else "COSTS %d CHIP%s" % [cost, "" if cost == 1 else "S"])
	# The rules in words (the cost has its own line above)
	var rules: String = instance.data.description.split(" (costs")[0]
	if instance.upgrade_level > 0:
		rules += "\nUpgraded: costs %d less." % instance.upgrade_level
	_body.text = rules
	_note.text = note
	_note.visible = note != ""
	for c in _actions.get_children():
		c.queue_free()
	for i in range(actions.size()):
		var a: Dictionary = actions[i]
		var b := _button(a.label, i == 0)
		b.disabled = a.get("disabled", false)
		var cb: Callable = a.on_press
		# Act first, so the card flies back to where it ends up
		b.pressed.connect(func():
			cb.call()
			close())
		_actions.add_child(b)
	_actions.add_child(_button("CLOSE", false, close))
	visible = true
	# Grow out of the tapped card into the middle
	_anchor = _source if _source and is_instance_valid(_source) and _source.is_visible_in_tree() else null
	_set_card_hidden(_anchor, true)
	_turn = -1.0 if randf() < 0.5 else 1.0
	_backdrop.modulate.a = 0.0
	_side.modulate.a = 0.0
	_place(0.0)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.18)
	_tween.tween_property(_side, "modulate:a", 1.0, 0.25).set_delay(0.12)
	_tween.tween_method(_place, 0.0, 1.0, OPEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(_start_sway)


func close() -> void:
	"""Shrink back down to the card's place (it may have moved), or just
	shrink away if it's gone (bought, removed)."""
	if not visible or _closing:
		return
	_closing = true
	_stop_tweens()
	_restore_anchor()
	var target: Control = null
	if _return_to.is_valid():
		target = _return_to.call()
	if target == null and _source and is_instance_valid(_source):
		target = _source
	_anchor = target if target and is_instance_valid(target) and target.is_visible_in_tree() else null
	_set_card_hidden(_anchor, true)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_backdrop, "modulate:a", 0.0, CLOSE_TIME)
	_tween.tween_property(_side, "modulate:a", 0.0, 0.12)
	_tween.tween_method(_place, 1.0, 0.0, CLOSE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if _anchor == null:
		_tween.tween_property(_face, "modulate:a", 0.0, CLOSE_TIME)
	_tween.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	visible = false
	_closing = false
	var landed := _anchor
	_restore_anchor()
	var motion := CardMotion.of(landed)
	if motion:
		motion.punch(0.6)
	if _face:
		_face.queue_free()
		_face = null


func _place(t: float) -> void:
	"""The card's flight: t 0 = over its small card (or shrunk in place when
	there is none), 1 = big in the middle."""
	if _face == null:
		return
	var big := _holder.get_global_rect()
	if big.size.x < 1.0:
		# Not laid out yet (first open): where the centred row will put it
		var w := CardFaceView.SIZE * ZOOM
		var mid := get_global_rect().get_center()
		big = Rect2(Vector2(mid.x - (w.x + 48.0 + 440.0) / 2.0, mid.y - w.y / 2.0), w)
	var small := Rect2(big.get_center() - big.size * 0.2, big.size * 0.4)
	if _anchor and is_instance_valid(_anchor):
		small = _anchor.get_global_rect()
	var k := lerpf(small.size.x / big.size.x, 1.0, t)
	# Scaled about its centre, so shift by what the scale takes off the corner
	_face.pivot_offset = _face.size / 2.0
	_face.scale = Vector2(k, k)
	_face.position = small.position.lerp(big.position, t) - global_position + (_face.size * k - _face.size) / 2.0
	# Turn a little on the way, and settle straight
	_face.rotation = sin(clampf(t, 0.0, 1.0) * PI) * FLY_TURN * _turn


func _start_sway() -> void:
	"""Held up to read, the card drifts gently."""
	if _face == null or _closing:
		return
	_sway = create_tween().set_loops()
	_sway.tween_property(_face, "rotation", 0.006 * _turn, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway.tween_property(_face, "rotation", -0.006 * _turn, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_tweens() -> void:
	for t in [_tween, _sway]:
		if t and t.is_valid():
			t.kill()
	_tween = null
	_sway = null


func _set_card_hidden(card: Control, hidden: bool) -> void:
	"""Hide a hand / shop card's face while its big copy is out."""
	if card == null or not is_instance_valid(card):
		return
	var face := card.get_node_or_null("Face") as Control
	if face:
		face.visible = not hidden


func _restore_anchor() -> void:
	_set_card_hidden(_anchor, false)
	_anchor = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _button(text: String, main: bool, on_press: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(440, 64)
	if main:
		ScorecardStyle.flat_button(b, ScorecardStyle.RED, ScorecardStyle.RED)
	else:
		ScorecardStyle.flat_button(b)
	b.add_theme_font_size_override("font_size", 26)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b
