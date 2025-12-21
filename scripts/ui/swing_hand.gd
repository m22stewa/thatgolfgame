extends Control
class_name SwingHand

## Wrapper for the 3D swing hand displayed in a SubViewport.
## This Control anchors the SubViewport to the UI layout.

@onready var swing_hand_3d = $SubViewportContainer/SubViewport/SwingHand3D
@onready var viewport = $SubViewportContainer/SubViewport
@onready var viewport_camera = $SubViewportContainer/SubViewport/Camera3D

var deck_manager: DeckManager = null


func _ready() -> void:
	# Ensure SubViewport has proper camera reference
	if swing_hand_3d and viewport_camera:
		swing_hand_3d.drag_controller._camera = viewport_camera


func setup(manager: DeckManager) -> void:
	"""Connect to a deck manager to display its hand"""
	deck_manager = manager
	
	if swing_hand_3d:
		swing_hand_3d.setup(manager)


func get_selected_card() -> CardInstance:
	"""Get the currently selected swing card"""
	if swing_hand_3d:
		return swing_hand_3d.get_selected_swing_card()
	return null
