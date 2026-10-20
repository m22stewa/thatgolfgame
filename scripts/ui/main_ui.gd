extends Control
class_name MainUI

# --- FEAT-003: live hand strip (club + modifier rows) -------------------
# The 2D HandStrip is the sole surface the player uses to play cards. The hole
# controller (hex_grid.gd) deals a club bag + modifier hand at hole start, binds
# it here via set_hand(), and listens for these selection signals to drive
# set_club_by_name() / activate_card_modifier().
signal club_card_selected(card_instance)
signal modifier_card_selected(card_instance)

# Lightweight card control size inside the strip (Button + card name).
const HAND_CARD_MIN_SIZE := Vector2(104, 72)
var _selected_club_instance = null

@onready var shot_ui: Control = $ShotUI
@onready var combined_deck_widget: DeckWidget = $DeckWidget  # Combined view (modifier only now)
@onready var modifier_deck_widget: DeckWidget = get_node_or_null("ModifierDeckWidget")  # Standalone modifier deck (optional)
@onready var items_bar: ItemsBar = get_node_or_null("ItemsBar")  # Item slots (optional)
@onready var wind_widget: Control = %WindWidget
@onready var lie_view: Control = %LieView
@onready var hole_info_label: Label = %HoleInfoLabel
@onready var hole_viewer: Control = $HoleViewer
@onready var generate_button: Button = %GenerateButton
@onready var generate_unique_button: Button = %GenerateUniqueButton
@onready var shoot_button: Button = get_node_or_null("%ShootButton")  # Turn-based "Shoot" confirm (FEAT-003)
@onready var hand_strip: Control = get_node_or_null("%HandStrip")  # 2D hand strip (club + modifier rows)
@onready var hand_club_row: HBoxContainer = get_node_or_null("%ClubRow")
@onready var hand_modifier_row: HBoxContainer = get_node_or_null("%ModifierRow")
@onready var lie_info_panel: PanelContainer = %LieInfoPanel
@onready var lie_name_label: Label = %LieName
@onready var lie_desc_label: RichTextLabel = %LieDescription
@onready var lie_mods_label: RichTextLabel = %LieModifiers

# Card inspection popup
var card_inspection_overlay: ColorRect = null
var card_inspection_panel: PanelContainer = null
var inspected_card: CardInstance = null

func _ready() -> void:
	# Connect card inspection signals from deck widgets
	if modifier_deck_widget and modifier_deck_widget.visible:
		modifier_deck_widget.card_inspection_requested.connect(_on_card_inspection_requested)
	
	# Connect combined deck widget if present
	if combined_deck_widget and combined_deck_widget.visible:
		combined_deck_widget.card_inspection_requested.connect(_on_card_inspection_requested)
	
	# Create card inspection overlay (hidden initially)
	_create_card_inspection_ui()


func _create_card_inspection_ui() -> void:
	"""Create the fullscreen card inspection popup"""
	# Dark overlay
	card_inspection_overlay = ColorRect.new()
	card_inspection_overlay.name = "CardInspectionOverlay"
	card_inspection_overlay.color = Color(0, 0, 0, 0.7)
	card_inspection_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_inspection_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	card_inspection_overlay.visible = false
	card_inspection_overlay.z_index = 100
	card_inspection_overlay.gui_input.connect(_on_inspection_overlay_input)
	add_child(card_inspection_overlay)
	
	# Card panel (centered)
	card_inspection_panel = PanelContainer.new()
	card_inspection_panel.name = "CardInspectionPanel"
	card_inspection_panel.custom_minimum_size = Vector2(400, 500)
	card_inspection_panel.set_anchors_preset(Control.PRESET_CENTER)
	card_inspection_panel.z_index = 101
	card_inspection_panel.visible = false
	add_child(card_inspection_panel)
	
	# Card content VBox
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 16)
	card_inspection_panel.add_child(vbox)
	
	# Title label
	var title = Label.new()
	title.name = "CardTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)
	
	# Description label
	var desc = RichTextLabel.new()
	desc.name = "CardDescription"
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.custom_minimum_size.y = 150
	vbox.add_child(desc)
	
	# Flavor text
	var flavor = Label.new()
	flavor.name = "CardFlavor"
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(flavor)
	
	# Close hint
	var hint = Label.new()
	hint.text = "Click anywhere to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)


func _on_card_inspection_requested(card_instance: CardInstance) -> void:
	"""Show fullscreen card inspection popup"""
	if not card_instance or not card_instance.data:
		return
	
	inspected_card = card_instance
	
	# Update panel content
	var title = card_inspection_panel.get_node("VBoxContainer/CardTitle") as Label
	var desc = card_inspection_panel.get_node("VBoxContainer/CardDescription") as RichTextLabel
	var flavor = card_inspection_panel.get_node("VBoxContainer/CardFlavor") as Label
	
	if title:
		title.text = card_instance.data.card_name
	if desc:
		desc.text = card_instance.get_full_description()
	if flavor:
		flavor.text = card_instance.data.flavor_text
		flavor.visible = not card_instance.data.flavor_text.is_empty()
	
	# Show popup
	card_inspection_overlay.visible = true
	card_inspection_panel.visible = true
	
	# Animate in
	card_inspection_panel.modulate.a = 0.0
	card_inspection_panel.scale = Vector2(0.8, 0.8)
	card_inspection_panel.pivot_offset = card_inspection_panel.size / 2
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card_inspection_panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(card_inspection_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_inspection_overlay_input(event: InputEvent) -> void:
	"""Close inspection on click"""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close_card_inspection()


func _close_card_inspection() -> void:
	"""Hide the card inspection popup"""
	inspected_card = null
	
	var tween = create_tween()
	tween.tween_property(card_inspection_panel, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func():
		card_inspection_overlay.visible = false
		card_inspection_panel.visible = false
	)


# --- FEAT-003: hand strip population -------------------------------------

func set_hand(club_cards: Array, modifier_cards: Array) -> void:
	"""Build the 2D club + modifier rows from dealt CardInstances.
	   Clears any existing controls first. A caller may pass a mixed list in
	   either argument; cards are routed to the club row vs modifier row by
	   card_type so the strip stays correct regardless of source."""
	_selected_club_instance = null
	clear_hand()
	if hand_club_row == null or hand_modifier_row == null:
		return
	# Route by card_type so a mixed list still lands in the right row.
	var all: Array = []
	all.append_array(club_cards)
	all.append_array(modifier_cards)
	for instance in all:
		if instance == null or instance.data == null:
			continue
		var is_club: bool = instance.data.card_type == CardData.CardType.CLUB
		var row: HBoxContainer = hand_club_row if is_club else hand_modifier_row
		var card_control := _make_hand_card(instance, is_club)
		row.add_child(card_control)


func clear_hand() -> void:
	"""Remove every card control from both rows."""
	if hand_club_row:
		for c in hand_club_row.get_children():
			c.queue_free()
	if hand_modifier_row:
		for c in hand_modifier_row.get_children():
			c.queue_free()


func set_selected_club(card_instance) -> void:
	"""Highlight the control bound to card_instance in the club row."""
	_selected_club_instance = card_instance
	if hand_club_row == null:
		return
	for c in hand_club_row.get_children():
		if not (c is Button):
			continue
		var bound = c.get_meta("card_instance") if c.has_meta("card_instance") else null
		c.button_pressed = (bound == card_instance)


func _make_hand_card(instance, is_club: bool) -> Button:
	"""Build a lightweight, clickable card control bound to a CardInstance.
	   Kept deliberately cheap (Button, no per-card 3D SubViewport) so a full
	   club bag + modifier hand costs little. Emits the appropriate selection
	   signal on press."""
	var btn := Button.new()
	btn.custom_minimum_size = HAND_CARD_MIN_SIZE
	btn.clip_text = true
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.text = instance.data.card_name
	btn.toggle_mode = is_club  # clubs stay visibly selected; modifiers are one-shot plays
	btn.set_meta("card_instance", instance)
	if instance.data.card_type != CardData.CardType.CLUB:
		btn.tooltip_text = instance.get_full_description()
	btn.pressed.connect(func() -> void:
		var bound = btn.get_meta("card_instance")
		if is_club:
			emit_signal("club_card_selected", bound)
		else:
			emit_signal("modifier_card_selected", bound)
	)
	return btn
