extends Node

## Settings (autoload) - The player's display options, set from Options on
## the title screen, saved to user://settings.cfg and applied at launch.
##   mode       - windowed, fullscreen (exclusive) or borderless (fullscreen
##                window)
##   resolution - windowed: the window's size. Fullscreen: the 3D renders at
##                this resolution (the UI always stays sharp), so a lower one
##                runs faster
##   vsync      - on / off
## The UI is designed at 1920x1080 and scaled to the window (project stretch
## mode canvas_items, aspect keep: other shapes get bars, nothing moves).
## With no saved file nothing is touched, so the project's defaults (and
## command-line --resolution) stand.

signal changed

const PATH := "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const MODES := ["windowed", "fullscreen", "borderless"]
const DESIGN_HEIGHT := 1080.0

var mode := "windowed"
var resolution := Vector2i(1920, 1080)
var vsync := true


func _ready() -> void:
	if _load():
		apply.call_deferred()


func _load() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return false
	mode = str(cfg.get_value("display", "mode", mode))
	if not MODES.has(mode):
		mode = "windowed"
	resolution = cfg.get_value("display", "resolution", resolution)
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	return true


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "mode", mode)
	cfg.set_value("display", "resolution", resolution)
	cfg.set_value("display", "vsync", vsync)
	cfg.save(PATH)


func set_options(p_mode: String, p_resolution: Vector2i, p_vsync: bool) -> void:
	"""Options screen: change, apply and save."""
	mode = p_mode
	resolution = p_resolution
	vsync = p_vsync
	apply()
	save()


func apply() -> void:
	var window := get_window()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	match mode:
		"fullscreen":
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		"borderless":
			window.mode = Window.MODE_FULLSCREEN
		_:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			# Never bigger than the screen can show; centred on it
			var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
			var want := resolution
			if want.x > screen.size.x or want.y > screen.size.y:
				want = fitting_resolutions().back() if not fitting_resolutions().is_empty() else screen.size
			window.size = want
			window.position = screen.position + (screen.size - want) / 2
	changed.emit()


func fitting_resolutions() -> Array[Vector2i]:
	"""The windowed sizes that fit on this screen."""
	var screen := DisplayServer.screen_get_usable_rect(get_window().current_screen).size
	var out: Array[Vector2i] = []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			out.append(r)
	return out


func render_scale_cap() -> float:
	"""Fullscreen: the most real pixels per UI pixel the 3D may use (the
	chosen resolution against the 1080 design). Windowed: no cap."""
	if mode == "windowed":
		return INF
	return float(resolution.y) / DESIGN_HEIGHT
