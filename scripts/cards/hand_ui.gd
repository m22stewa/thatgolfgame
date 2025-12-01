extends Control
class_name HandUI

## Displays the player's current hand of cards.
## Manages card layout, drag & drop, and card slots for playing.

signal card_selected(card_instance: CardInstance)
signal card_played(card_instance: CardInstance)
signal card_deselected()

# References
var deck_manager: DeckManager = null
var card_ui_scene: PackedScene = null

# Child cards in hand
var card_uis: Array[CardUI] = []
var selected_card: CardUI = null
var dragging_card: CardUI = null

# Card slots (cards that have been played/staged)
var card_slots: Array[Control] = []
var slotted_cards: Array[CardUI] = []  # Cards currently in slots (null if empty)
const NUM_SLOTS: int = 3

# Layout settings
@export var hand_width: float = 600.0
@export var card_size: Vector2 = Vector2(100, 150)
@export var hand_y_offset: float = 5.0  # From bottom of screen
@export var slot_spacing: float = 20.0  # Space between slots
@export var slot_y_offset: float = 170.0  # How far above hand the slots are

# Slot visual settings
@export var slot_color: Color = Color(0.15, 0.2, 0.15, 0.6)
@export var slot_hover_color: Color = Color(0.25, 0.4, 0.25, 0.8)
@export var slot_border_color: Color = Color(0.4, 0.6, 0.4, 0.8)

# Currently hovered slot
var hovered_slot_index: int = -1

# Preload card UI scene
const CARD_UI_PATH = "res://scenes/ui/card_ui.tscn"


func _ready() -> void:
	# Try to load card UI scene
	if ResourceLoader.exists(CARD_UI_PATH):
		card_ui_scene = load(CARD_UI_PATH)
	
	# Initialize slotted cards array
	slotted_cards.resize(NUM_SLOTS)
	for i in NUM_SLOTS:
		slotted_cards[i] = null
	
	# Create card slots
	_create_card_slots()
	
	# Position at bottom of screen
	_update_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()


func _create_card_slots() -> void:
	"""Create the 3 drop slots for playing cards"""
	var slots_container = Control.new()
	slots_container.name = "SlotsContainer"
	slots_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slots_container)
	move_child(slots_container, 0)  # Behind cards
	
	for i in NUM_SLOTS:
		var slot = _create_single_slot(i)
		slots_container.add_child(slot)
		card_slots.append(slot)


func _create_single_slot(index: int) -> Control:
	"""Create a single card slot"""
	var slot = Control.new()
	slot.name = "Slot_%d" % index
	slot.custom_minimum_size = card_size
	slot.size = card_size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = slot_color
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(bg)
	
	# Border (using 4 thin rects)
	var border_thickness = 2.0
	var borders = ["Top", "Bottom", "Left", "Right"]
	for border_name in borders:
		var border = ColorRect.new()
		border.name = "Border" + border_name
		border.color = slot_border_color
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(border)
	
	# Slot number label
	var label = Label.new()
	label.name = "SlotLabel"
	label.text = str(index + 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	
	return slot


func _update_slot_borders(slot: Control) -> void:
	"""Update border positions for a slot"""
	var border_thickness = 2.0
	var s = slot.size
	
	var top = slot.get_node_or_null("BorderTop")
	if top:
		top.position = Vector2.ZERO
		top.size = Vector2(s.x, border_thickness)
	
	var bottom = slot.get_node_or_null("BorderBottom")
	if bottom:
		bottom.position = Vector2(0, s.y - border_thickness)
		bottom.size = Vector2(s.x, border_thickness)
	
	var left = slot.get_node_or_null("BorderLeft")
	if left:
		left.position = Vector2.ZERO
		left.size = Vector2(border_thickness, s.y)
	
	var right = slot.get_node_or_null("BorderRight")
	if right:
		right.position = Vector2(s.x - border_thickness, 0)
		right.size = Vector2(border_thickness, s.y)


func setup(manager: DeckManager) -> void:
	"""Connect to a DeckManager to display its hand"""
	if deck_manager:
		# Disconnect old signals
		if deck_manager.hand_changed.is_connected(_on_hand_changed):
			deck_manager.hand_changed.disconnect(_on_hand_changed)
		if deck_manager.card_played.is_connected(_on_card_played):
			deck_manager.card_played.disconnect(_on_card_played)
	
	deck_manager = manager
	
	if deck_manager:
		deck_manager.hand_changed.connect(_on_hand_changed)
		deck_manager.card_played.connect(_on_card_played)
		refresh_hand()


func refresh_hand() -> void:
	"""Rebuild the hand display from DeckManager"""
	if not deck_manager:
		return
	
	# Clear existing hand cards (not slotted ones)
	_clear_hand_cards()
	
	# Create new card UIs
	var hand = deck_manager.get_hand()
	for card_instance in hand:
		# Don't recreate cards that are already slotted
		var already_slotted = false
		for slotted in slotted_cards:
			if slotted and is_instance_valid(slotted) and slotted.card_instance == card_instance:
				already_slotted = true
				break
		
		if not already_slotted:
			_create_card_ui(card_instance)
	
	# Update layout
	_arrange_cards()


func _create_card_ui(card_instance: CardInstance) -> CardUI:
	var card_ui: CardUI
	
	if card_ui_scene:
		card_ui = card_ui_scene.instantiate()
	else:
		# Create a basic card UI dynamically
		card_ui = _create_basic_card_ui()
	
	add_child(card_ui)
	card_ui.setup(card_instance)
	card_ui.custom_minimum_size = card_size
	
	# Connect signals
	card_ui.card_clicked.connect(_on_card_clicked)
	card_ui.card_hovered.connect(_on_card_hovered)
	card_ui.card_played.connect(_on_card_ui_played)
	card_ui.card_drag_started.connect(_on_card_drag_started)
	card_ui.card_drag_ended.connect(_on_card_drag_ended)
	card_ui.card_dropped.connect(_on_card_dropped)
	
	card_uis.append(card_ui)
	return card_ui


func _create_basic_card_ui() -> CardUI:
	"""Create a simple card UI without a scene file"""
	var card_ui = CardUI.new()
	card_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.2, 0.3, 0.2)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_ui.add_child(bg)
	
	# Rarity indicator (top bar)
	var rarity = ColorRect.new()
	rarity.name = "RarityIndicator"
	rarity.custom_minimum_size = Vector2(0, 6)
	rarity.set_anchors_preset(Control.PRESET_TOP_WIDE)
	rarity.size = Vector2(card_size.x, 6)
	rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_ui.add_child(rarity)
	
	# Card name
	var name_label = Label.new()
	name_label.name = "CardName"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(4, 10)
	name_label.size = Vector2(card_size.x - 8, 24)
	name_label.text = "Card"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_ui.add_child(name_label)
	
	# Description
	var desc = RichTextLabel.new()
	desc.name = "Description"
	desc.position = Vector2(6, 35)
	desc.size = Vector2(card_size.x - 12, card_size.y - 55)
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.scroll_active = false
	card_ui.add_child(desc)
	
	# Cost label (for consumables)
	var cost = Label.new()
	cost.name = "CostLabel"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.position = Vector2(card_size.x - 28, card_size.y - 20)
	cost.size = Vector2(24, 16)
	cost.visible = false
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_ui.add_child(cost)
	
	# Type icon placeholder
	var icon = TextureRect.new()
	icon.name = "TypeIcon"
	icon.position = Vector2(4, card_size.y - 20)
	icon.size = Vector2(16, 16)
	icon.visible = false
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_ui.add_child(icon)
	
	return card_ui


func _clear_hand_cards() -> void:
	"""Clear cards in hand (not slotted cards)"""
	for card_ui in card_uis:
		if is_instance_valid(card_ui):
			card_ui.queue_free()
	card_uis.clear()
	selected_card = null
	dragging_card = null


func _clear_all_slots() -> void:
	"""Clear all slotted cards"""
	for i in NUM_SLOTS:
		if slotted_cards[i] and is_instance_valid(slotted_cards[i]):
			slotted_cards[i].queue_free()
		slotted_cards[i] = null


func _arrange_cards(skip_dragging: bool = true) -> void:
	"""Position cards in a fan layout in the hand area"""
	# Filter out any invalid cards first
	var valid_cards: Array[CardUI] = []
	for card_ui in card_uis:
		if is_instance_valid(card_ui):
			valid_cards.append(card_ui)
	card_uis = valid_cards
	
	var total = card_uis.size()
	
	var current_index = 0
	for i in total:
		var card_ui = card_uis[i]
		if not is_instance_valid(card_ui):
			continue
		if card_ui == dragging_card:
			continue
		card_ui.set_hand_position(current_index, total - (1 if dragging_card and is_instance_valid(dragging_card) else 0), hand_width, -1)
		current_index += 1


func _update_layout() -> void:
	"""Update hand position based on screen size"""
	var screen_size = get_viewport_rect().size
	position = Vector2(
		(screen_size.x - hand_width) / 2,
		screen_size.y - card_size.y - hand_y_offset
	)
	
	# Update slot positions (centered above hand)
	var total_slots_width = (card_size.x * NUM_SLOTS) + (slot_spacing * (NUM_SLOTS - 1))
	var slots_start_x = (hand_width - total_slots_width) / 2
	
	for i in NUM_SLOTS:
		if i < card_slots.size():
			var slot = card_slots[i]
			slot.position = Vector2(
				slots_start_x + i * (card_size.x + slot_spacing),
				-slot_y_offset
			)
			slot.size = card_size
			_update_slot_borders(slot)
			
			# Update slotted card position too
			if slotted_cards[i] and is_instance_valid(slotted_cards[i]):
				slotted_cards[i].target_position = slot.position
	
	_arrange_cards()


func _get_slot_at_position(global_pos: Vector2) -> int:
	"""Return slot index at position, or -1 if none"""
	for i in NUM_SLOTS:
		if i >= card_slots.size():
			continue
		var slot = card_slots[i]
		var slot_global_pos = slot.global_position
		var slot_rect = Rect2(slot_global_pos, slot.size)
		if slot_rect.has_point(global_pos):
			return i
	return -1


func _is_slot_empty(index: int) -> bool:
	"""Check if a slot is available"""
	if index < 0 or index >= NUM_SLOTS:
		return false
	return slotted_cards[index] == null or not is_instance_valid(slotted_cards[index])


func _highlight_slot(index: int, highlight: bool) -> void:
	"""Highlight or unhighlight a slot"""
	if index < 0 or index >= card_slots.size():
		return
	
	var slot = card_slots[index]
	var bg = slot.get_node_or_null("Background")
	if bg:
		bg.color = slot_hover_color if highlight else slot_color


func _snap_card_to_slot(card_ui: CardUI, slot_index: int) -> void:
	"""Snap a card to a slot and mark it as played"""
	if slot_index < 0 or slot_index >= NUM_SLOTS:
		return
	
	if not is_instance_valid(card_ui):
		return
	
	# Remove from hand
	card_uis.erase(card_ui)
	
	# Clear any existing card in slot
	if slotted_cards[slot_index] and is_instance_valid(slotted_cards[slot_index]):
		# Return old card to hand
		var old_card = slotted_cards[slot_index]
		card_uis.append(old_card)
		old_card.return_to_hand()
	
	# Put card in slot
	slotted_cards[slot_index] = card_ui
	
	# Snap to slot position
	var slot = card_slots[slot_index]
	card_ui.target_position = slot.position
	card_ui.target_rotation = 0.0
	card_ui.target_scale = Vector2.ONE
	card_ui.z_index = 50
	card_ui.is_dragging = false
	
	# Emit played signal
	card_played.emit(card_ui.card_instance)
	
	# Rearrange remaining hand cards
	_arrange_cards(false)


func remove_card_from_slot(slot_index: int) -> CardUI:
	"""Remove a card from a slot and return it"""
	if slot_index < 0 or slot_index >= NUM_SLOTS:
		return null
	
	var card_ui = slotted_cards[slot_index]
	slotted_cards[slot_index] = null
	
	if card_ui and is_instance_valid(card_ui):
		# Return to hand
		card_uis.append(card_ui)
		card_ui.return_to_hand()
		_arrange_cards(false)
	
	return card_ui


func get_slotted_cards() -> Array[CardInstance]:
	"""Get all cards currently in slots"""
	var result: Array[CardInstance] = []
	for card_ui in slotted_cards:
		if card_ui and is_instance_valid(card_ui) and card_ui.card_instance:
			result.append(card_ui.card_instance)
	return result


func clear_slots_after_shot() -> void:
	"""Clear all slots after a shot is taken (cards are consumed)"""
	for i in NUM_SLOTS:
		if slotted_cards[i] and is_instance_valid(slotted_cards[i]):
			var card_ui = slotted_cards[i]
			# Play animation and free
			card_ui.play_animation()
			# Tell deck manager to move to discard
			if deck_manager and card_ui.card_instance:
				deck_manager.play_card(card_ui.card_instance)
		slotted_cards[i] = null


func select_card(card_ui: CardUI) -> void:
	"""Select a card (deselects previous)"""
	if selected_card == card_ui:
		deselect_card()
		return
	
	if selected_card:
		selected_card.set_selected(false)
	
	selected_card = card_ui
	selected_card.set_selected(true)
	card_selected.emit(selected_card.card_instance)


func deselect_card() -> void:
	"""Deselect the current card"""
	if selected_card:
		selected_card.set_selected(false)
		selected_card = null
		card_deselected.emit()


func get_selected_card() -> CardInstance:
	"""Get the currently selected card instance"""
	if selected_card:
		return selected_card.card_instance
	return null


# Signal handlers

func _on_hand_changed() -> void:
	refresh_hand()


func _on_card_played(_card: CardInstance) -> void:
	pass


func _on_card_clicked(card_ui: CardUI) -> void:
	select_card(card_ui)


func _on_card_hovered(card_ui: CardUI, hovering: bool) -> void:
	pass


func _on_card_ui_played(card_ui: CardUI) -> void:
	# Find first empty slot
	for i in NUM_SLOTS:
		if _is_slot_empty(i):
			_snap_card_to_slot(card_ui, i)
			return


func _on_card_drag_started(card_ui: CardUI) -> void:
	"""Handle card drag start"""
	dragging_card = card_ui
	deselect_card()
	_arrange_cards(true)


func _on_card_drag_ended(card_ui: CardUI) -> void:
	"""Handle card drag end"""
	# Unhighlight any slot
	if hovered_slot_index >= 0:
		_highlight_slot(hovered_slot_index, false)
		hovered_slot_index = -1


func _on_card_dropped(card_ui: CardUI, global_pos: Vector2) -> void:
	"""Handle card being dropped"""
	if not is_instance_valid(card_ui):
		dragging_card = null
		return
	
	# Check if dropped on a slot
	var slot_index = _get_slot_at_position(global_pos)
	if slot_index >= 0:
		_snap_card_to_slot(card_ui, slot_index)
		dragging_card = null
		if hovered_slot_index >= 0:
			_highlight_slot(hovered_slot_index, false)
			hovered_slot_index = -1
		return
	
	# Return to hand
	card_ui.return_to_hand()
	dragging_card = null
	_arrange_cards(false)


func _process(_delta: float) -> void:
	# Update slot highlighting while dragging
	if dragging_card and is_instance_valid(dragging_card):
		var mouse_global = get_global_mouse_position()
		var new_hovered = _get_slot_at_position(mouse_global)
		
		# Update highlight if changed
		if new_hovered != hovered_slot_index:
			if hovered_slot_index >= 0:
				_highlight_slot(hovered_slot_index, false)
			if new_hovered >= 0:
				_highlight_slot(new_hovered, true)
			hovered_slot_index = new_hovered
	else:
		if hovered_slot_index >= 0:
			_highlight_slot(hovered_slot_index, false)
			hovered_slot_index = -1
		dragging_card = null
