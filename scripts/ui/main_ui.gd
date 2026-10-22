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
const CLUB_BUTTON_MIN_SIZE := Vector2(104, 52)
const SHOT_CARD_SIZE := Vector2(136, 150)
const CARD_PAPER := Color(0.97, 0.95, 0.89)
const CARD_INK := Color(0.13, 0.13, 0.11)
const CARD_BRASS := Color(0.86, 0.62, 0.2)
var _selected_club_instance = null

@onready var shot_ui: Control = $ShotUI
@onready var combined_deck_widget: DeckWidget = $DeckWidget  # Combined view (modifier only now)
@onready var modifier_deck_widget: DeckWidget = get_node_or_null("ModifierDeckWidget")  # Standalone modifier deck (optional)
@onready var items_bar: ItemsBar = get_node_or_null("ItemsBar")  # Item slots (optional)
@onready var wind_widget: Control = %WindWidget
@onready var lie_view: Control = %LieView
@onready var hole_info_label: Label = %HoleInfoLabel
@onready var hole_viewer: Control = $HoleViewer
@onready var tray: PanelContainer = get_node_or_null("%Tray")  # Felt tray (FEAT-002 shader host)
@onready var generate_button: Button = %GenerateButton
@onready var generate_unique_button: Button = %GenerateUniqueButton
@onready var shoot_button: Button = get_node_or_null("%ShootButton")  # Turn-based "Shoot" confirm (FEAT-003)
@onready var hand_strip: Control = get_node_or_null("%HandStrip")  # 2D hand strip (club + modifier rows)
@onready var hand_club_row: HBoxContainer = get_node_or_null("%ClubRow")
@onready var hand_modifier_row: HBoxContainer = get_node_or_null("%ModifierRow")
@onready var lie_info_panel: PanelContainer = %LieInfoPanel
# FEAT-003: on-screen hole-view controls (zoom / rotate / reset) in the HUD.
@onready var zoom_in_button: Button = get_node_or_null("%ZoomInButton")
@onready var zoom_out_button: Button = get_node_or_null("%ZoomOutButton")
@onready var rotate_button: Button = get_node_or_null("%RotateButton")
@onready var reset_view_button: Button = get_node_or_null("%ResetViewButton")
@onready var lie_name_label: Label = %LieName
@onready var lie_desc_label: RichTextLabel = %LieDescription
@onready var lie_mods_label: RichTextLabel = %LieModifiers

# Prototype: hide everything not needed to plan and hit a shot (scoreboard,
# debug info, dev buttons). Nothing is deleted; F1 toggles it all back.
@export var prototype_ui: bool = true
const PROTOTYPE_HIDDEN := [
	"ShotUI/mainbg green", "ShotUI/holeinfo white", "ShotUI/shotinfo grey",
	"ShotUI/scorebg darkgreen", "ShotUI/ScoreInfo", "ShotUI/TopBar",
	"ShotUI/ShotCounter", "ShotUI/ActionPanel", "ShotUI/BottomPanel",
	"HoleViewer/HoleHUD/GenerateButton", "HoleViewer/HoleHUD/GenerateUniqueButton",
	"HoleViewer/HoleHUD/LieInfoPanel",
]
var _prototype_saved_visibility: Dictionary = {}  # NodePath -> visible before hiding

# Card inspection popup
var card_inspection_overlay: ColorRect = null
var card_inspection_panel: PanelContainer = null
var inspected_card: CardInstance = null

func _ready() -> void:
	set_prototype_ui.call_deferred(prototype_ui)
	# Connect card inspection signals from deck widgets
	if modifier_deck_widget and modifier_deck_widget.visible:
		modifier_deck_widget.card_inspection_requested.connect(_on_card_inspection_requested)
	
	# Connect combined deck widget if present
	if combined_deck_widget and combined_deck_widget.visible:
		combined_deck_widget.card_inspection_requested.connect(_on_card_inspection_requested)
	
	# Create card inspection overlay (hidden initially)
	_create_card_inspection_ui()

	# Keep the felt tray shader's stitch dashes square by feeding it the tray's
	# live width/height ratio (FEAT-002).
	if tray:
		tray.resized.connect(_on_tray_resized)
		_on_tray_resized()

	# Wire the on-screen hole-view controls to the HoleViewer camera (FEAT-003).
	if hole_viewer:
		if zoom_in_button:
			zoom_in_button.pressed.connect(hole_viewer.on_zoom_in_pressed)
		if zoom_out_button:
			zoom_out_button.pressed.connect(hole_viewer.on_zoom_out_pressed)
		if rotate_button:
			rotate_button.pressed.connect(hole_viewer.on_rotate_pressed)
		if reset_view_button:
			reset_view_button.pressed.connect(hole_viewer.on_reset_view_pressed)


func _on_tray_resized() -> void:
	"""Refresh the felt_tray shader's tray_aspect uniform from the tray size."""
	if not tray or not (tray.material is ShaderMaterial):
		return
	var size := tray.size
	if size.y <= 0.0:
		return
	(tray.material as ShaderMaterial).set_shader_parameter("tray_aspect", size.x / size.y)


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

func set_prototype_ui(on: bool) -> void:
	"""Hide (or restore) the non-prototype UI listed in PROTOTYPE_HIDDEN."""
	prototype_ui = on
	for path in PROTOTYPE_HIDDEN:
		var node := get_node_or_null(path) as CanvasItem
		if node == null:
			continue
		if on:
			if not _prototype_saved_visibility.has(path):
				_prototype_saved_visibility[path] = node.visible
			node.visible = false
		elif _prototype_saved_visibility.has(path):
			node.visible = _prototype_saved_visibility[path]
	if not on:
		_prototype_saved_visibility.clear()
	_style_status_label(on)


func _style_status_label(prototype: bool) -> void:
	"""Prototype: the hole label becomes a dark, centred status line across the
	top of the hole view (default: top-right hole info)."""
	if hole_info_label == null:
		return
	if prototype:
		hole_info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		hole_info_label.offset_top = 14
		hole_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hole_info_label.add_theme_color_override("font_color", Color(0.1, 0.16, 0.12))
		hole_info_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
		hole_info_label.add_theme_constant_override("outline_size", 8)
	else:
		hole_info_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		hole_info_label.offset_left = -300
		hole_info_label.offset_right = -20
		hole_info_label.offset_top = 16
		hole_info_label.offset_bottom = 96
		hole_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hole_info_label.remove_theme_color_override("font_color")
		hole_info_label.remove_theme_color_override("font_outline_color")
		hole_info_label.remove_theme_constant_override("outline_size")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		set_prototype_ui(not prototype_ui)
		get_viewport().set_input_as_handled()


func set_card_pressed(card_instance, pressed: bool) -> void:
	"""Reflect whether a shot card is played this shot (without re-emitting)."""
	if hand_modifier_row == null:
		return
	for c in hand_modifier_row.get_children():
		if c is Button and c.has_meta("card_instance") and c.get_meta("card_instance") == card_instance:
			c.set_pressed_no_signal(pressed)


func set_hand(club_cards: Array, modifier_cards: Array, club_subtitles: Dictionary = {}) -> void:
	"""Build the 2D club + modifier rows from dealt CardInstances.
	   Clears any existing controls first. A caller may pass a mixed list in
	   either argument; cards are routed to the club row vs modifier row by
	   card_type so the strip stays correct regardless of source.
	   club_subtitles: CardInstance -> second line on a club (its carry range)."""
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
		var card_control := _make_hand_card(instance, is_club, club_subtitles.get(instance, ""))
		row.add_child(card_control)


func _build_shot_card(btn: Button, instance) -> void:
	"""Card face: tag + cost row, name, drawn icon, one-line effect."""
	var info := ShotCardFace.kind_for(instance.data)
	var is_curse: bool = info.kind == "strain"
	btn.custom_minimum_size = SHOT_CARD_SIZE
	btn.tooltip_text = instance.get_full_description()
	btn.disabled = is_curse  # Strain: dead weight in the hand
	var paper := Color(0.78, 0.76, 0.72) if is_curse else CARD_PAPER
	btn.add_theme_stylebox_override("normal", _card_box(paper, CARD_INK, 2))
	btn.add_theme_stylebox_override("hover", _card_box(paper, CARD_BRASS, 3))
	btn.add_theme_stylebox_override("disabled", _card_box(paper, Color(0.4, 0.38, 0.35), 2))
	btn.add_theme_stylebox_override("pressed", _card_box(Color(1.0, 0.88, 0.6), CARD_BRASS, 5))
	btn.add_theme_stylebox_override("hover_pressed", _card_box(Color(1.0, 0.88, 0.6), CARD_BRASS, 5))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = 8
	col.offset_bottom = -8
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	top.add_child(_card_label(info.tag, 11, Color(0.4, 0.38, 0.33)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var cost := ShotCardFace.cost_for(instance.data)
	if not is_curse:
		top.add_child(_card_label("%d" % cost if cost > 0 else "free", 13, CARD_BRASS.darkened(0.3)))

	var title := _card_label(instance.data.card_name, 16, CARD_INK)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	col.add_child(title)

	var face := ShotCardFace.new()
	face.kind = info.kind
	face.strength = info.strength
	face.size_flags_vertical = Control.SIZE_EXPAND_FILL
	face.custom_minimum_size = Vector2(0, 40)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(face)

	var blurb := _card_label(instance.data.description.split(" (")[0], 11, Color(0.3, 0.29, 0.26))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(blurb)


func _card_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _card_box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(8)
	return box


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


func _make_hand_card(instance, is_club: bool, subtitle: String = "") -> Button:
	"""Build a lightweight, clickable card control bound to a CardInstance.
	   Clubs are compact two-line buttons (name + carry range); shot cards are
	   card faces (tag, cost, drawn icon, effect). Both toggle: a club stays
	   selected, a shot card is played/unplayed for this shot."""
	var btn := Button.new()
	btn.toggle_mode = true
	btn.set_meta("card_instance", instance)
	if is_club:
		btn.custom_minimum_size = CLUB_BUTTON_MIN_SIZE
		btn.text = instance.data.card_name if subtitle == "" else "%s\n%s" % [instance.data.card_name, subtitle]
		btn.add_theme_font_size_override("font_size", 15)
		# Selected reads as "active" (brass), not the theme's greyed pressed look
		btn.add_theme_stylebox_override("pressed", _card_box(Color(0.86, 0.66, 0.28), Color(1.0, 0.95, 0.8), 3))
		btn.add_theme_stylebox_override("hover_pressed", _card_box(Color(0.86, 0.66, 0.28), Color(1.0, 0.95, 0.8), 3))
		btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.1, 0.05))
		btn.add_theme_color_override("font_hover_pressed_color", Color(0.12, 0.1, 0.05))
	else:
		_build_shot_card(btn, instance)
	btn.pressed.connect(func() -> void:
		var bound = btn.get_meta("card_instance")
		if is_club:
			emit_signal("club_card_selected", bound)
		else:
			emit_signal("modifier_card_selected", bound)
	)
	return btn
