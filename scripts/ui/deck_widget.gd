@tool
extends SubViewportContainer
class_name DeckWidget

## DeckWidget - A self-contained UI widget that displays a 3D deck.
## Wraps the SubViewport and DeckView3D complexity.

enum DeckType { MODIFIERS, CLUBS }

@export_group("Deck Configuration")
@export var deck_type: DeckType = DeckType.MODIFIERS
@export var card_back_texture: Texture2D
@export var card_front_texture: Texture2D

@export var lock_aspect_ratio: bool = true:
	set(value):
		lock_aspect_ratio = value
		if lock_aspect_ratio and deck_size.y > 0:
			_aspect_ratio = deck_size.x / deck_size.y

var _aspect_ratio: float = 4.0 / 2.02

@export var deck_size: Vector3 = Vector3(4.0, 2.02, 0.5):
	set(value):
		if lock_aspect_ratio and deck_size != Vector3.ZERO:
			var x_diff = abs(value.x - deck_size.x)
			var y_diff = abs(value.y - deck_size.y)
			
			if x_diff > 0.001 and y_diff < 0.001:
				value.y = value.x / _aspect_ratio
			elif y_diff > 0.001 and x_diff < 0.001:
				value.x = value.y * _aspect_ratio
		
		deck_size = value
		_apply_config()

@export var interaction_mode: DeckView3D.InteractionMode = DeckView3D.InteractionMode.DRAW_TOP

# Internal references
var deck_view: DeckView3D = null
var sub_viewport: SubViewport = null

# Saved state for restoring after inspection
var _saved_anchors: Dictionary = {}
var _saved_offsets: Dictionary = {}
var _saved_viewport_size: Vector2i = Vector2i.ZERO
var _is_expanded: bool = false

# Signals forwarded from DeckView3D
signal card_inspection_requested(card_instance: CardInstance)

func _ready() -> void:
	# Find the internal DeckView3D and SubViewport
	sub_viewport = get_node_or_null("SubViewport")
	deck_view = get_node_or_null("SubViewport/DeckView3D")
	if deck_view:
		_apply_config()
		# Forward inspection signal (kept for compatibility)
		if not deck_view.card_inspection_requested.is_connected(_on_card_inspection_requested):
			deck_view.card_inspection_requested.connect(_on_card_inspection_requested)
		# Connect to expansion/contraction signals
		if deck_view.has_signal("inspection_started") and not deck_view.inspection_started.is_connected(_on_inspection_started):
			deck_view.inspection_started.connect(_on_inspection_started)
		if deck_view.has_signal("inspection_closed") and not deck_view.inspection_closed.is_connected(_on_inspection_closed):
			deck_view.inspection_closed.connect(_on_inspection_closed)


func _on_card_inspection_requested(card_instance: CardInstance) -> void:
	card_inspection_requested.emit(card_instance)


func _on_inspection_started() -> void:
	"""Expand the SubViewportContainer to full screen for card inspection"""
	if _is_expanded:
		return
	
	# Save current state
	_saved_anchors = {
		"left": anchor_left,
		"top": anchor_top,
		"right": anchor_right,
		"bottom": anchor_bottom
	}
	_saved_offsets = {
		"left": offset_left,
		"top": offset_top,
		"right": offset_right,
		"bottom": offset_bottom
	}
	if sub_viewport:
		_saved_viewport_size = sub_viewport.size
	
	# Expand to full screen
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	
	# Also expand the SubViewport to match screen size
	if sub_viewport:
		var screen_size = get_viewport_rect().size
		sub_viewport.size = Vector2i(int(screen_size.x), int(screen_size.y))
	
	# Bring to front
	z_index = 100
	
	_is_expanded = true


func _on_inspection_closed() -> void:
	"""Restore the SubViewportContainer to original size"""
	if not _is_expanded:
		return
	
	# Restore anchors
	anchor_left = _saved_anchors.get("left", 1.0)
	anchor_top = _saved_anchors.get("top", 1.0)
	anchor_right = _saved_anchors.get("right", 1.0)
	anchor_bottom = _saved_anchors.get("bottom", 1.0)
	
	# Restore offsets
	offset_left = _saved_offsets.get("left", -1169.0)
	offset_top = _saved_offsets.get("top", -600.0)
	offset_right = _saved_offsets.get("right", -369.0)
	offset_bottom = _saved_offsets.get("bottom", 0.0)
	
	# Restore SubViewport size
	if sub_viewport and _saved_viewport_size != Vector2i.ZERO:
		sub_viewport.size = _saved_viewport_size
	
	# Restore z-index
	z_index = 0
	
	_is_expanded = false


func _apply_config() -> void:
	if not deck_view: return
	
	if card_back_texture:
		deck_view.card_back_texture = card_back_texture
	if card_front_texture:
		deck_view.card_front_texture = card_front_texture
	
	deck_view.deck_size = deck_size
	deck_view.interaction_mode = interaction_mode
	
	# Trigger mesh rebuild if needed
	if deck_view.is_inside_tree():
		deck_view._setup_deck_mesh()

func setup(manager: DeckManager) -> void:
	if deck_view:
		deck_view.setup(manager)

func get_deck_view() -> DeckView3D:
	return deck_view
