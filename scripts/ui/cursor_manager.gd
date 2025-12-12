extends Node

## CursorManager - Manages custom cursor states throughout the game.
## Add as an autoload singleton for global cursor control.

# Cursor types
enum CursorType {
	DEFAULT,      # pointer_c_shaded - standard cursor
	HAND_OPEN,    # hand_small_open - hovering over deck
	HAND_POINT,   # hand_point_n - hovering over card in UI overlay
	ZOOM          # zoom - hovering over drawn card to inspect
}

# Cursor textures
var cursors: Dictionary = {}

# Current state
var _current_type: CursorType = CursorType.DEFAULT

# Cursor paths
const CURSOR_PATHS = {
	CursorType.DEFAULT: "res://textures/cursors/pointer_c_shaded.png",
	CursorType.HAND_OPEN: "res://textures/cursors/hand_small_open.png",
	CursorType.HAND_POINT: "res://textures/cursors/hand_point_n.png",
	CursorType.ZOOM: "res://textures/cursors/zoom.png"
}

# Hotspot offsets (where the click point is on the cursor image)
const CURSOR_HOTSPOTS = {
	CursorType.DEFAULT: Vector2(14, 6),      # Top-left area of pointer
	CursorType.HAND_OPEN: Vector2(32, 16),   # Center of palm
	CursorType.HAND_POINT: Vector2(24, 4),   # Fingertip
	CursorType.ZOOM: Vector2(24, 24)         # Center of magnifying glass
}


func _ready() -> void:
	_load_cursors()
	set_cursor(CursorType.DEFAULT)


func _load_cursors() -> void:
	"""Load all cursor textures"""
	for type in CURSOR_PATHS:
		var path = CURSOR_PATHS[type]
		var texture = load(path)
		if texture:
			cursors[type] = texture
		else:
			push_warning("[CursorManager] Failed to load cursor: %s" % path)


func set_cursor(type: CursorType) -> void:
	"""Set the current cursor type"""
	if type == _current_type:
		return
	
	_current_type = type
	
	if type in cursors:
		var hotspot = CURSOR_HOTSPOTS.get(type, Vector2.ZERO)
		Input.set_custom_mouse_cursor(cursors[type], Input.CURSOR_ARROW, hotspot)
	else:
		# Fallback to system cursor
		Input.set_custom_mouse_cursor(null)


func reset_cursor() -> void:
	"""Reset to default cursor"""
	set_cursor(CursorType.DEFAULT)


func get_current_type() -> CursorType:
	"""Get the current cursor type"""
	return _current_type


# Convenience methods for common cursor changes
func set_hand_open() -> void:
	set_cursor(CursorType.HAND_OPEN)

func set_hand_point() -> void:
	set_cursor(CursorType.HAND_POINT)

func set_zoom() -> void:
	set_cursor(CursorType.ZOOM)

func set_default() -> void:
	set_cursor(CursorType.DEFAULT)
