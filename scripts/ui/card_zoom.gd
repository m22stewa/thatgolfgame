extends Control
class_name CardZoom

## CardZoom - Tap a card to read it. After Marvel Snap's card view, the card
## zooms up over a dark backdrop at ZOOM times its hand size, with its full
## rules beside it and the actions it allows where it was tapped (Play / Take
## back in the hand; Buy, Remove, Upgrade in the Pro Shop). Tap the backdrop,
## Close or Esc to put it back.

const ZOOM := 2.5  # card size vs the hand

var _row: HBoxContainer
var _holder: Control
var _face: CardFaceView = null
var _title: Label
var _cost: Label
var _body: Label
var _note: Label
var _actions: VBoxContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.06, 0.04, 0.85)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(backdrop)

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
	side.custom_minimum_size = Vector2(440, 0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 16)
	_row.add_child(side)
	_title = ScorecardStyle.label("", 52, ScorecardStyle.PAPER, ScorecardStyle.header_font())
	side.add_child(_title)
	_cost = ScorecardStyle.label("", 34, CardFaceView.COIN, ScorecardStyle.header_font())
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


func open(instance, actions: Array = [], note: String = "", affordable: bool = true) -> void:
	"""Show instance big. actions: [{label, on_press: Callable, disabled}],
	the first is the main one. note: why an action is off (red)."""
	if _face:
		_face.queue_free()
	_face = CardFaceView.for_instance(instance)
	_face.size = CardFaceView.SIZE * ZOOM
	_face.affordable = affordable
	_holder.add_child(_face)
	_title.text = instance.get_display_name().to_upper()
	var cost: int = _face.cost
	_cost.text = "" if _face.unplayable else ("FREE TO PLAY" if cost == 0 else "COSTS %d MONEY" % cost)
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
		b.pressed.connect(func():
			close()
			cb.call())
		_actions.add_child(b)
	_actions.add_child(_button("CLOSE", false, close))
	visible = true
	# Zoom up from small, like picking the card up
	_face.pivot_offset = _face.size / 2.0
	_face.scale = Vector2(0.4, 0.4)
	modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.12)
	t.tween_property(_face, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	visible = false


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
