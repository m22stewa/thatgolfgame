extends Control
class_name SwingCardUI

## A draggable swing card for the player's hand.
## Manually handles drag to move the actual card (not a preview).

signal card_clicked(card_instance: CardInstance)
signal card_hovered(card_instance: CardInstance)
signal card_unhovered(card_instance: CardInstance)
signal card_drag_started(card_ui: SwingCardUI)
signal card_drag_ended(card_ui: SwingCardUI, was_dropped: bool)

# Node references - found from scene
@onready var card_name_label: Label = $CardName
@onready var card_description: RichTextLabel = $CardDescription

# Card data
var card_instance: CardInstance = null

# State
var is_hovered: bool = false
var is_selected: bool = false
var is_playable: bool = true

# Drag state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_parent: Node = null
var original_position: Vector2 = Vector2.ZERO
var original_z_index: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Make sure child nodes don't intercept mouse events
	for child in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(instance: CardInstance) -> void:
	"""Initialize the card with data"""
	card_instance = instance
	_update_from_data()


func _update_from_data() -> void:
	if not card_instance or not card_instance.data:
		return
	
	var data = card_instance.data
	
	if card_name_label:
		card_name_label.text = data.card_name
	
	if card_description:
		card_description.text = data.description if data.description else ""


func set_playable(playable: bool) -> void:
	is_playable = playable
	# Don't change visuals - only affects drag behavior


func set_selected(selected: bool) -> void:
	is_selected = selected


# =============================================================================
# MANUAL DRAG - Move the actual card with the mouse
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if not is_playable:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(event.position)


func _start_drag(local_click_pos: Vector2) -> void:
	"""Begin dragging - store original state and start following mouse"""
	is_dragging = true
	drag_offset = local_click_pos
	
	# Store original state so we can return if drop fails
	original_parent = get_parent()
	original_position = position
	original_z_index = z_index
	
	# Move to top of UI tree so card renders above everything
	var root_ui = _get_root_ui()
	if root_ui and root_ui != original_parent:
		var global_pos = global_position
		original_parent.remove_child(self)
		root_ui.add_child(self)
		global_position = global_pos
	
	# Render on top
	z_index = 100
	
	card_drag_started.emit(self)


func _get_root_ui() -> Control:
	"""Find the root UI node (MainUI or similar)"""
	var node = self
	while node.get_parent() is Control:
		node = node.get_parent()
	return node as Control


func _input(event: InputEvent) -> void:
	if not is_dragging:
		return
	
	if event is InputEventMouseMotion:
		# Move card to follow mouse, offset by where we grabbed it
		global_position = event.global_position - drag_offset
		get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_drag()
			get_viewport().set_input_as_handled()


func _end_drag() -> void:
	"""End dragging - check if we're over a valid drop target"""
	if not is_dragging:
		return
	
	is_dragging = false
	z_index = original_z_index
	
	# Check if we're over a valid drop target
	var drop_target = _find_drop_target()
	
	if drop_target and drop_target.can_accept_card(self):
		# Successful drop
		drop_target.accept_card(self)
		card_drag_ended.emit(self, true)
	else:
		# Failed drop - return to original position
		_return_to_origin()
		card_drag_ended.emit(self, false)


func _find_drop_target() -> SwingCardSlot:
	"""Find a SwingCardSlot under the mouse"""
	var mouse_pos = get_global_mouse_position()
	var root = get_tree().root
	return _find_slot_recursive(root, mouse_pos)


func _find_slot_recursive(node: Node, mouse_pos: Vector2) -> SwingCardSlot:
	"""Recursively find a SwingCardSlot containing the mouse position"""
	if node is SwingCardSlot:
		var slot = node as SwingCardSlot
		var rect = slot.get_global_rect()
		if rect.has_point(mouse_pos):
			return slot
	
	for child in node.get_children():
		var found = _find_slot_recursive(child, mouse_pos)
		if found:
			return found
	
	return null


func _return_to_origin() -> void:
	"""Animate back to original position in original parent"""
	if original_parent and is_instance_valid(original_parent):
		# Reparent back
		if get_parent() != original_parent:
			get_parent().remove_child(self)
			original_parent.add_child(self)
		
		# Animate back to original position
		var tween = create_tween()
		tween.tween_property(self, "position", original_position, 0.15).set_ease(Tween.EASE_OUT)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			if not is_dragging:
				is_hovered = true
				card_hovered.emit(card_instance)
		NOTIFICATION_MOUSE_EXIT:
			if not is_dragging:
				is_hovered = false
				card_unhovered.emit(card_instance)
