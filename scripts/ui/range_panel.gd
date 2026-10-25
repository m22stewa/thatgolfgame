extends PanelContainer
class_name RangePanel

## RangePanel - The driving range's toolbox, a scorecard-paper panel at the
## top-left of the hole view. Pick a tool, then tap hexes to paint them:
## surfaces (fairway also erases), course features, coins, or move the ball and
## the flag. AIM & SHOOT puts taps back to aiming. Wind can be set to any
## strength and direction. Every card is in the hand and Chips are unlimited,
## so any shot can be tried. hex_grid (host) does the work: range_* calls.

var host  # hex_grid

const TOOLS := [
	["", "AIM & SHOOT"],
	["SURFACES", ""],
	["fairway", "FAIRWAY / ERASE"], ["rough", "ROUGH"],
	["deep_rough", "DEEP ROUGH"], ["sand", "BUNKER"],
	["water", "WATER"], ["tree", "TREES"],
	["green", "GREEN"],
	["OBSTACLES", ""],
	["ice", "ICE"], ["fire", "FIRE"],
	["tunnel", "WIND GUST"], ["trampoline", "TRAMPOLINE"],
	["coin", "CHIP"],
	["PLACE", ""],
	["ball", "MOVE BALL"], ["flag", "MOVE FLAG"],
]

var _wind_button: Button
var _tool_group := ButtonGroup.new()


func _init() -> void:
	var box := ScorecardStyle.paper_box(ScorecardStyle.INK, 2)
	box.set_content_margin_all(14)
	add_theme_stylebox_override("panel", box)
	position = Vector2(16, 16)
	custom_minimum_size = Vector2(330, 0)
	z_index = 5

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(ScorecardStyle.label("DRIVING RANGE", 26, ScorecardStyle.INK, ScorecardStyle.header_font()))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	head.add_child(_button("MENU", func(): host.range_menu(), false, Vector2(80, 32)))
	col.add_child(_caption("PICK A TOOL, THEN TAP HEXES"))

	var grid: GridContainer = null
	for t in TOOLS:
		var id: String = t[0]
		var label: String = t[1]
		if label == "":
			col.add_child(_caption(id))  # a section heading
			grid = null
			continue
		if grid == null:
			grid = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 6)
			col.add_child(grid)
		var b := _button(label, func(): host.range_set_tool(id), true)
		b.button_group = _tool_group
		b.button_pressed = id == ""
		if id == "":
			b.custom_minimum_size = Vector2(302, 36)
			col.add_child(b)
			grid = null
		else:
			grid.add_child(b)
	col.add_child(_caption("TAP A WIND GUST AGAIN TO TURN IT"))

	col.add_child(_caption("WIND"))
	var wind := HBoxContainer.new()
	wind.add_theme_constant_override("separation", 6)
	col.add_child(wind)
	_wind_button = _button("", func():
		host.range_cycle_wind()
		_refresh(), false, Vector2(148, 36))
	wind.add_child(_wind_button)
	wind.add_child(_button("TURN 45°", func():
		host.range_turn_wind()
		_refresh(), false, Vector2(148, 36)))

	col.add_child(_rule())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	col.add_child(actions)
	actions.add_child(_button("BALL TO TEE", func(): host.range_reset_ball(), false, Vector2(148, 36)))
	actions.add_child(_button("CLEAR COURSE", func(): host.range_clear(), false, Vector2(148, 36)))
	col.add_child(_caption("EVERY CARD IS IN THE HAND  ·  SCROLL IT"))


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	_wind_button.text = "WIND: %s" % host.range_wind_text()


func _caption(text: String) -> Label:
	return ScorecardStyle.label(text, 13, ScorecardStyle.INK_SOFT, ScorecardStyle.header_font(false))


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = ScorecardStyle.RULE
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _button(text: String, on_press: Callable, toggle: bool, min_size: Vector2 = Vector2(148, 36)) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	ScorecardStyle.flat_button(b)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(on_press)
	return b
