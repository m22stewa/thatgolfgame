extends Control
class_name ItemsBar

## Displays the player's item slots (5 hexagonal slots).
## Items can be dragged onto swing cards or used directly.

signal item_selected(slot_index: int)
signal item_used(slot_index: int)

const NUM_SLOTS = 5

# Item slot references (populated on ready)
var item_slots: Array[Panel] = []
var item_icons: Array[TextureRect] = []

# Item data for each slot
var items: Array = []  # Array of ItemData or null


func _ready() -> void:
	items.resize(NUM_SLOTS)
	
	# Find all item slot nodes
	var hbox = $VBoxContainer/HBoxContainer
	for i in NUM_SLOTS:
		var slot_name = "ItemSlot%d" % (i + 1)
		var slot = hbox.get_node_or_null(slot_name) as Panel
		if slot:
			item_slots.append(slot)
			var icon = slot.get_node_or_null("Icon") as TextureRect
			item_icons.append(icon)
			
			# Connect click handler
			slot.gui_input.connect(_on_slot_input.bind(i))
		else:
			item_slots.append(null)
			item_icons.append(null)


func _on_slot_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if items[slot_index] != null:
			item_selected.emit(slot_index)


func set_item(slot_index: int, item_data) -> void:
	"""Set an item in a specific slot"""
	if slot_index < 0 or slot_index >= NUM_SLOTS:
		return
	
	items[slot_index] = item_data
	_update_slot_visual(slot_index)


func clear_item(slot_index: int) -> void:
	"""Clear an item from a slot"""
	if slot_index < 0 or slot_index >= NUM_SLOTS:
		return
	
	items[slot_index] = null
	_update_slot_visual(slot_index)


func get_item(slot_index: int):
	"""Get the item in a slot"""
	if slot_index < 0 or slot_index >= NUM_SLOTS:
		return null
	return items[slot_index]


func use_item(slot_index: int) -> void:
	"""Use and consume an item"""
	if slot_index < 0 or slot_index >= NUM_SLOTS:
		return
	
	if items[slot_index] != null:
		item_used.emit(slot_index)
		clear_item(slot_index)


func _update_slot_visual(slot_index: int) -> void:
	"""Update the visual state of a slot"""
	if slot_index < 0 or slot_index >= item_icons.size():
		return
	
	var icon = item_icons[slot_index]
	if not icon:
		return
	
	var item = items[slot_index]
	if item and item.has("icon"):
		icon.texture = item.icon
	elif item and item is Resource and item.get("icon"):
		icon.texture = item.icon
	else:
		icon.texture = null


func clear_all() -> void:
	"""Clear all item slots"""
	for i in NUM_SLOTS:
		clear_item(i)


func get_filled_count() -> int:
	"""Get number of filled slots"""
	var count = 0
	for item in items:
		if item != null:
			count += 1
	return count


func get_empty_slot() -> int:
	"""Get first empty slot index, or -1 if full"""
	for i in NUM_SLOTS:
		if items[i] == null:
			return i
	return -1
