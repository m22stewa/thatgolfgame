extends Control

## Title screen: a white page, GOLF set big on the left, and the menu on the
## right: Play (the run), Driving Range (practice and testing), Options
## (display: window / fullscreen, resolution, V-Sync; see Settings), Quit.
## Starting either shows a quick loading screen while the course loads in the
## background; the game opens on the same cover and fades it off onto the
## hole's flyover.

const LOADING_MIN_TIME := 0.9  # seconds, so it reads as a screen, not a flash

var _loading: Control = null
var _bar: ProgressBar
var _range_mode := false
var _load_time := 0.0
var _shown := 0.0  # bar value shown (eases toward the real progress)
var _options: Control = null
var _opt_mode := "windowed"
var _opt_res := Vector2i(1920, 1080)
var _opt_vsync := true
var _mode_buttons: Dictionary = {}  # mode -> Button
var _res_label: Label
var _res_note: Label
var _vsync_button: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 140
	row.offset_right = -160
	add_child(row)

	var title := ScorecardStyle.label("GOLF", 300, ScorecardStyle.INK, ScorecardStyle.header_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	var menu := VBoxContainer.new()
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.add_theme_constant_override("separation", 20)
	row.add_child(menu)
	var play := _button("PLAY", func(): _start(false), true)
	menu.add_child(play)
	menu.add_child(_button("DRIVING RANGE", func(): _start(true)))
	menu.add_child(_button("OPTIONS", _open_options))
	menu.add_child(_button("QUIT", func(): get_tree().quit()))
	play.grab_focus.call_deferred()


func _start(range_mode: bool) -> void:
	"""Fade up the loading screen and load the game in the background."""
	if _loading:
		return
	_range_mode = range_mode
	_load_time = 0.0
	_loading = _build_loading_screen()
	add_child(_loading)
	_loading.modulate.a = 0.0
	create_tween().tween_property(_loading, "modulate:a", 1.0, 0.18)
	if ResourceLoader.load_threaded_request(GameMode.GAME_SCENE) != OK:
		GameMode.start(get_tree(), range_mode)


func _process(delta: float) -> void:
	if _loading == null:
		return
	_load_time += delta
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(GameMode.GAME_SCENE, progress)
	var real: float = progress[0] if not progress.is_empty() else 0.0
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		real = 1.0
	# Eased, and paced so it never finishes before the minimum time
	_shown = move_toward(_shown, minf(real, _load_time / LOADING_MIN_TIME), delta * 2.5)
	_bar.value = _shown
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		GameMode.start(get_tree(), _range_mode)
	elif status == ResourceLoader.THREAD_LOAD_LOADED and _shown >= 1.0:
		set_process(false)
		# The bar's done: the hole is built behind the same cover, then revealed
		await get_tree().process_frame
		GameMode.start_loaded(get_tree(), _range_mode, ResourceLoader.load_threaded_get(GameMode.GAME_SCENE))


func _build_loading_screen() -> Control:
	"""The game's cover colour, LOADING_TEXT where the game shows it, and a
	thin progress bar under it."""
	var screen := ColorRect.new()
	screen.color = GameMode.LOADING_BG
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var text := Label.new()
	text.text = GameMode.LOADING_TEXT
	text.add_theme_font_override("font", load("res://theme/Unbounded-VariableFont_wght.ttf"))
	text.add_theme_font_size_override("font_size", 66)
	text.add_theme_color_override("font_color", Color.WHITE)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(text)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ScorecardStyle.PAPER
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_bar.offset_left = -220
	_bar.offset_right = 220
	_bar.offset_top = 70
	_bar.offset_bottom = 78
	screen.add_child(_bar)
	return screen


# --- Options -------------------------------------------------------------------

func _open_options() -> void:
	"""A sheet of scorecard paper over the title: display mode, resolution,
	V-Sync; Apply saves them (Settings)."""
	_opt_mode = Settings.mode
	_opt_res = Settings.resolution
	_opt_vsync = Settings.vsync
	if _options == null:
		_options = _build_options()
		add_child(_options)
	_options.visible = true
	_refresh_options()


func _build_options() -> Control:
	var screen := ColorRect.new()
	screen.color = Color(1, 1, 1, 0.92)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var sheet := PanelContainer.new()
	var box := ScorecardStyle.paper_box(ScorecardStyle.INK, 2, ScorecardStyle.PAPER, 4)
	box.set_content_margin_all(40)
	sheet.add_theme_stylebox_override("panel", box)
	center.add_child(sheet)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	sheet.add_child(col)
	col.add_child(ScorecardStyle.label("OPTIONS", 64, ScorecardStyle.INK, ScorecardStyle.header_font()))

	col.add_child(_caption("DISPLAY"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 12)
	col.add_child(modes)
	for m in [["windowed", "WINDOWED"], ["fullscreen", "FULLSCREEN"], ["borderless", "BORDERLESS"]]:
		var b := _small_button(m[1], func(): _opt_mode = m[0]; _refresh_options())
		b.toggle_mode = true
		modes.add_child(b)
		_mode_buttons[m[0]] = b

	col.add_child(_caption("RESOLUTION"))
	var res := HBoxContainer.new()
	res.add_theme_constant_override("separation", 12)
	col.add_child(res)
	res.add_child(_small_button("<", func(): _step_resolution(-1), 64))
	_res_label = ScorecardStyle.label("", 34, ScorecardStyle.INK, ScorecardStyle.header_font())
	_res_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_res_label.custom_minimum_size = Vector2(300, 0)
	res.add_child(_res_label)
	res.add_child(_small_button(">", func(): _step_resolution(1), 64))
	_res_note = ScorecardStyle.label("", 18, ScorecardStyle.INK_SOFT, ScorecardStyle.header_font(false))
	col.add_child(_res_note)

	col.add_child(_caption("V-SYNC"))
	_vsync_button = _small_button("", func(): _opt_vsync = not _opt_vsync; _refresh_options())
	_vsync_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_vsync_button)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	col.add_child(actions)
	actions.add_child(_button("APPLY", func():
		Settings.set_options(_opt_mode, _opt_res, _opt_vsync)
		_refresh_options(), true))
	actions.add_child(_button("BACK", func(): _options.visible = false))
	return screen


func _resolution_choices() -> Array[Vector2i]:
	"""Windowed: sizes that fit the screen. Fullscreen: every size (it's the
	3D render resolution)."""
	var out: Array[Vector2i] = Settings.RESOLUTIONS.duplicate() if _opt_mode != "windowed" else Settings.fitting_resolutions()
	if out.is_empty():
		out = [Vector2i(1280, 720)]
	return out


func _step_resolution(step: int) -> void:
	var choices := _resolution_choices()
	var i := choices.find(_opt_res)
	i = clampi((i if i >= 0 else choices.size() - 1) + step, 0, choices.size() - 1)
	_opt_res = choices[i]
	_refresh_options()


func _refresh_options() -> void:
	for m in _mode_buttons:
		_mode_buttons[m].button_pressed = m == _opt_mode
	var choices := _resolution_choices()
	if not choices.has(_opt_res):
		_opt_res = choices.back()
	_res_label.text = "%d × %d" % [_opt_res.x, _opt_res.y]
	_res_note.text = "WINDOW SIZE" if _opt_mode == "windowed" else "3D DETAIL (THE MENUS STAY SHARP)"
	_vsync_button.text = "ON" if _opt_vsync else "OFF"


func _caption(text: String) -> Label:
	return ScorecardStyle.label(text, 18, ScorecardStyle.INK_SOFT, ScorecardStyle.header_font(false))


func _small_button(text: String, on_press: Callable, width: float = 200.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 56)
	ScorecardStyle.flat_button(b)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(on_press)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if _options and _options.visible and event.is_action_pressed("ui_cancel"):
		_options.visible = false
		get_viewport().set_input_as_handled()


func _button(text: String, on_press: Callable, main: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 84)
	if main:
		ScorecardStyle.flat_button(b, ScorecardStyle.RED, ScorecardStyle.RED)
	else:
		ScorecardStyle.flat_button(b)
	b.add_theme_font_size_override("font_size", 34)
	b.pressed.connect(on_press)
	return b
