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
@export var card_size: Vector2 = Vector2(160, 240)  # Larger cards for readability
@export var hand_y_offset: float = 10.0  # From bottom of screen
@export var slot_spacing: float = 20.0  # Space between slots
@export var slot_y_offset: float = 260.0  # How far above hand the slots are

# Arc layout settings
@export var arc_height: float = 30.0  # How much the arc curves up in the center
@export var arc_rotation: float = 12.0  # Max rotation in degrees at edges (positive = fan out)
@export var card_overlap: float = 0.3  # 0 = no overlap, 1 = full overlap

# Inspection overlay
var inspection_overlay: ColorRect = null
var inspected_card: CardUI = null
var inspected_card_original_parent: Node = null
var inspected_card_return_position: Vector2 = Vector2.ZERO
var inspected_card_return_rotation: float = 0.0
var inspected_card_return_scale: Vector2 = Vector2.ONE

# Slot visual settings
@export var slot_color: Color = Color(0.15, 0.2, 0.15, 0.6)
@export var slot_hover_color: Color = Color(0.25, 0.4, 0.25, 0.8)
@export var slot_border_color: Color = Color(0.4, 0.6, 0.4, 0.8)
@export var slot_texture: Texture2D = null  # Optional texture for slots
@export var slot_hover_texture: Texture2D = null  # Optional texture for hovered slots

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
	
	# Create inspection overlay (hidden initially)
	_create_inspection_overlay()
	
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
	
	# Background - use TextureRect if texture provided, else ColorRect
	if slot_texture:
		var tex_bg = TextureRect.new()
		tex_bg.name = "Background"
		tex_bg.texture = slot_texture
		tex_bg.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tex_bg)
	else:
		var bg = ColorRect.new()
		bg.name = "Background"
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.color = slot_color
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(bg)
		
		# Border (using 4 thin rects) - only for ColorRect background
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
	card_ui.card_inspect_requested.connect(_on_card_inspect_requested)
	
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
	"""Position cards in an arc layout in the hand area"""
	# Filter out any invalid cards first
	var valid_cards: Array[CardUI] = []
	for card_ui in card_uis:
		if is_instance_valid(card_ui):
			valid_cards.append(card_ui)
	card_uis = valid_cards
	
	var display_count = card_uis.size()
	if skip_dragging and dragging_card and is_instance_valid(dragging_card):
		display_count -= 1
	
	var current_index = 0
	for i in card_uis.size():
		var card_ui = card_uis[i]
		if not is_instance_valid(card_ui):
			continue
		if skip_dragging and card_ui == dragging_card:
			continue
		
		_set_card_arc_position(card_ui, current_index, display_count)
		current_index += 1


func _set_card_arc_position(card_ui: CardUI, index: int, total: int) -> void:
	"""Position a card in an arc formation"""
	if total <= 0:
		return
	
	# Calculate normalized position (-1 to 1, center is 0)
	var t: float = 0.0
	if total > 1:
		t = (float(index) / float(total - 1)) * 2.0 - 1.0  # -1 to 1
	
	# Calculate card spacing - overlap more with more cards
	var base_spacing = card_size.x * (1.0 - card_overlap)
	var total_width = base_spacing * (total - 1) if total > 1 else 0
	total_width = min(total_width, hand_width - card_size.x)  # Cap at hand width
	
	# X position: spread cards evenly
	var center_x = hand_width / 2.0
	var x = center_x + (t * total_width / 2.0) - card_size.x / 2.0
	
	# Y position: arc curve (center cards are raised, edge cards are lower)
	# Use a parabola: at t=0 (center), y=0; at t=±1 (edges), y=arc_height
	var y = arc_height * (t * t)  # 0 at center, arc_height at edges
	
	# Rotation: fan OUT from center (left cards tilt left, right cards tilt right)
	var rotation_deg = t * arc_rotation  # Positive so cards fan outward
	
	# Set targets
	card_ui.target_position = Vector2(x, y)
	card_ui.target_rotation = deg_to_rad(rotation_deg)
	card_ui.return_position = card_ui.target_position
	card_ui.return_rotation = card_ui.target_rotation
	card_ui.hand_index = index
	
	# Z-index: center cards are on top
	var center_dist = abs(index - (total - 1) / 2.0)
	card_ui.z_index = int(total - center_dist)
	
	if not card_ui.is_dragging and not card_ui.is_selected:
		card_ui.target_scale = Vector2.ONE


func _update_layout() -> void:
	"""Update hand position based on screen size - positioned to the right of HoleViewer (800px)"""
	var screen_size = get_viewport_rect().size
	
	# HoleViewer takes up 800px on the left, hand goes in remaining space
	const HOLE_VIEWER_WIDTH = 800.0
	var right_panel_width = screen_size.x - HOLE_VIEWER_WIDTH
	
	# Center the hand in the right panel area
	position = Vector2(
		HOLE_VIEWER_WIDTH + (right_panel_width - hand_width) / 2,
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
		# Check if using textures or colors
		if bg is TextureRect and slot_texture:
			if highlight and slot_hover_texture:
				bg.texture = slot_hover_texture
			else:
				bg.texture = slot_texture
		elif bg is ColorRect:
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
	
	# Snap to slot position - FAST snap (1-2 frames)
	var slot = card_slots[slot_index]
	var target_pos = slot.position
	
	# Stop dragging state immediately
	card_ui.is_dragging = false
	card_ui.z_index = 50
	
	# Quick snap tween (about 2 frames at 60fps = ~0.033 seconds)
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(true)
	tween.tween_property(card_ui, "position", target_pos, 0.05)
	tween.tween_property(card_ui, "rotation", 0.0, 0.05)
	tween.tween_property(card_ui, "scale", Vector2.ONE, 0.05)
	
	# Also set targets so idle processing doesn't fight the tween
	card_ui.target_position = target_pos
	card_ui.target_rotation = 0.0
	card_ui.target_scale = Vector2.ONE
	
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
	# Track if this card was already selected before we toggle
	var was_selected = (selected_card == card_ui)
	
	# If not selected, select it
	if not was_selected:
		select_card(card_ui)
	# If already selected, clicking again opens inspection (don't deselect)


func _on_card_hovered(_card_ui: CardUI, _hovering: bool) -> void:
	pass


func _on_card_inspect_requested(card_ui: CardUI) -> void:
	"""Show card in fullscreen inspection view - only if card was already selected"""
	# Only inspect if clicking on an already-selected card
	if selected_card != card_ui:
		return
	
	# If clicking the currently inspected card, close inspection
	if inspected_card == card_ui:
		_close_inspection()
		return
	
	# If already inspecting a different card, close first
	if inspected_card != null:
		_close_inspection()
		# Small delay then open new one
		await get_tree().create_timer(0.2).timeout
	
	_show_inspection(card_ui)


func _create_inspection_overlay() -> void:
	"""Create the semi-transparent overlay for card inspection"""
	inspection_overlay = ColorRect.new()
	inspection_overlay.name = "InspectionOverlay"
	inspection_overlay.color = Color(0, 0, 0, 0.7)
	inspection_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	inspection_overlay.visible = false
	inspection_overlay.z_index = 200
	
	# Make it cover the full screen (we'll update size in _process or resize)
	inspection_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Connect click to close inspection
	inspection_overlay.gui_input.connect(_on_overlay_input)
	
	# Add to scene tree at a high level
	add_child(inspection_overlay)


func _on_overlay_input(event: InputEvent) -> void:
	"""Handle clicks on the overlay to close inspection"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_close_inspection()


func _show_inspection(card_ui: CardUI) -> void:
	"""Animate card to center of screen for inspection"""
	if not is_instance_valid(card_ui):
		return
	
	inspected_card = card_ui
	
	# Store return state
	inspected_card_return_position = card_ui.target_position
	inspected_card_return_rotation = card_ui.target_rotation
	inspected_card_return_scale = card_ui.target_scale
	
	# Update overlay to cover full screen
	var screen_size = get_viewport_rect().size
	inspection_overlay.position = -global_position  # Offset to cover full screen from our position
	inspection_overlay.size = screen_size
	
	# Show overlay with fade
	inspection_overlay.modulate.a = 0.0
	inspection_overlay.visible = true
	var overlay_tween = create_tween()
	overlay_tween.tween_property(inspection_overlay, "modulate:a", 1.0, 0.2)
	
	# Scale up the card (3.0x = triple size)
	var inspect_scale = 3.0
	
	# Set pivot to center of card (unscaled)
	card_ui.pivot_offset = card_size / 2.0
	
	# Calculate where the card's top-left corner needs to be
	# so that its CENTER lands at screen center
	# Screen center in local coords:
	var screen_center_local = (screen_size / 2.0) - global_position
	
	# The card's center (after scaling) will be at: position + pivot_offset
	# We want: position + pivot_offset = screen_center_local
	# So: position = screen_center_local - pivot_offset
	# But pivot_offset is in unscaled coords, and position is also unscaled
	var target_pos = screen_center_local - card_ui.pivot_offset
	
	# Animate card to center
	card_ui.z_index = 250  # Above overlay
	card_ui.target_position = target_pos
	card_ui.target_rotation = 0.0
	card_ui.target_scale = Vector2(inspect_scale, inspect_scale)
	
	# Enable inspection mode for mouse reaction
	card_ui.is_inspecting = true
	card_ui.inspect_center = screen_center_local
	
	# Disable dragging while inspecting
	card_ui.is_dragging = false
	card_ui.is_mouse_down = false


func _close_inspection() -> void:
	"""Return inspected card to hand"""
	if inspected_card == null or not is_instance_valid(inspected_card):
		inspection_overlay.visible = false
		inspected_card = null
		return
	
	# Fade out overlay
	var overlay_tween = create_tween()
	overlay_tween.tween_property(inspection_overlay, "modulate:a", 0.0, 0.15)
	overlay_tween.tween_callback(func(): inspection_overlay.visible = false)
	
	# Disable inspection mode
	inspected_card.is_inspecting = false
	
	# Return card to hand position
	inspected_card.target_position = inspected_card_return_position
	inspected_card.target_rotation = inspected_card_return_rotation
	inspected_card.target_scale = inspected_card_return_scale
	inspected_card.z_index = 0
	
	inspected_card = null
	
	# Re-arrange to fix z-indices
	_arrange_cards(false)


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
