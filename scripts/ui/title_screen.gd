extends Control

## Title screen: a white page, GOLF set big on the left, and the menu on the
## right: Play (the run), Driving Range (practice and testing), Quit.
## Starting either shows a quick loading screen while the course loads in the
## background; the game opens on the same cover and fades it off onto the
## hole's flyover.

const LOADING_MIN_TIME := 0.9  # seconds, so it reads as a screen, not a flash

var _loading: Control = null
var _bar: ProgressBar
var _range_mode := false
var _load_time := 0.0
var _shown := 0.0  # bar value shown (eases toward the real progress)


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
