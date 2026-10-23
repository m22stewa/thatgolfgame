extends Control
class_name MainUI

# --- FEAT-003: live hand strip (club + modifier rows) -------------------
# The 2D HandStrip is the sole surface the player uses to play cards. The hole
# controller (hex_grid.gd) deals a club bag + modifier hand at hole start, binds
# it here via set_hand(), and listens for these selection signals to drive
# set_club_by_name() / activate_card_modifier().
signal club_card_selected(card_instance)
signal modifier_card_selected(card_instance)

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
@onready var hand_club_row: BoxContainer = get_node_or_null("%ClubRow")
@onready var hand_modifier_row: BoxContainer = get_node_or_null("%ModifierRow")
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
const TRAY_TOP := 0.69  # the scorecard tray takes the bottom 31% of the screen
const PROTOTYPE_HIDDEN := [
	"ShotUI/mainbg green", "ShotUI/holeinfo white", "ShotUI/shotinfo grey",
	"ShotUI/scorebg darkgreen", "ShotUI/ScoreInfo", "ShotUI/TopBar",
	"ShotUI/ShotCounter", "ShotUI/ActionPanel", "ShotUI/BottomPanel",
	"HoleViewer/HoleHUD/GenerateButton", "HoleViewer/HoleHUD/GenerateUniqueButton",
	"HoleViewer/HoleHUD/LieInfoPanel", "HoleViewer/HoleHUD/HoleInfoLabel",
]
var _prototype_saved_visibility: Dictionary = {}  # NodePath -> visible before hiding

# Card inspection popup
var card_inspection_overlay: ColorRect = null
var card_inspection_panel: PanelContainer = null
var inspected_card: CardInstance = null

# Scorecard tray (built in code on top of the scene's ClubRow / ModifierRow /
# ShootButton): club table | hand | scorecard + THIS SHOT + SHOOT
var scorecard_table: ScorecardTable
var _hand_label: Label
var _this_shot_label: Label
var _deck_label: Label
var _run_label: Label

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

	_build_scorecard_tray()

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


func _build_scorecard_tray() -> void:
	"""Restyle the tray as a paper scorecard and lay it out: CLUB IN HAND table
	(ClubRow), the hand (ModifierRow), then the scorecard, THIS SHOT, deck and
	points, and the SHOOT box (ShootButton)."""
	if tray == null or hand_club_row == null or hand_modifier_row == null or shoot_button == null:
		return
	tray.material = null
	# A taller tray so the cards can be read: the hole view gives up the space
	tray.anchor_top = TRAY_TOP
	if hole_viewer:
		hole_viewer.anchor_bottom = TRAY_TOP
	var paper := ScorecardStyle.paper_box(ScorecardStyle.INK, 0, ScorecardStyle.PAPER, 0)
	paper.border_width_top = 3
	tray.add_theme_stylebox_override("panel", paper)
	var margin := tray.get_node("TrayMargin") as MarginContainer
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	var content := margin.get_node("TrayContent") as HBoxContainer
	content.add_theme_constant_override("separation", 22)
	content.alignment = BoxContainer.ALIGNMENT_BEGIN

	# Left: CLUB IN HAND | YARDS
	var clubs := VBoxContainer.new()
	clubs.name = "ClubTable"
	clubs.custom_minimum_size = Vector2(240, 0)
	clubs.add_theme_constant_override("separation", 2)
	content.add_child(clubs)
	content.move_child(clubs, 0)
	var club_head := HBoxContainer.new()
	clubs.add_child(club_head)
	club_head.add_child(_tray_caption("CLUB IN HAND"))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	club_head.add_child(fill)
	club_head.add_child(_tray_caption("YARDS"))
	clubs.add_child(_rule())
	hand_club_row.reparent(clubs, false)

	# Middle: HAND · N OF M
	hand_strip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var rows := hand_modifier_row.get_parent() as BoxContainer
	_hand_label = _tray_caption("HAND")
	rows.add_child(_hand_label)
	rows.move_child(_hand_label, 0)
	rows.add_theme_constant_override("separation", 4)
	hand_modifier_row.add_theme_constant_override("separation", 12)
	hand_modifier_row.alignment = BoxContainer.ALIGNMENT_BEGIN

	# Right: scorecard, THIS SHOT, deck / points / run, and SHOOT
	var right := HBoxContainer.new()
	right.name = "ScorePanel"
	right.add_theme_constant_override("separation", 16)
	content.add_child(right)
	var card_col := VBoxContainer.new()
	card_col.add_theme_constant_override("separation", 4)
	card_col.custom_minimum_size = Vector2(380, 0)
	right.add_child(card_col)
	scorecard_table = ScorecardTable.new()
	card_col.add_child(scorecard_table)
	card_col.add_child(_tray_caption("THIS SHOT"))
	_this_shot_label = ScorecardStyle.label("", 26, ScorecardStyle.PENCIL, ScorecardStyle.pencil_font())
	_this_shot_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_this_shot_label.clip_text = true
	_this_shot_label.custom_minimum_size = Vector2(380, 0)
	card_col.add_child(_this_shot_label)
	var foot := HBoxContainer.new()
	card_col.add_child(foot)
	_deck_label = _tray_caption("")
	foot.add_child(_deck_label)
	var foot_fill := Control.new()
	foot_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(foot_fill)
	_run_label = _tray_caption("")
	foot.add_child(_run_label)
	for b in [zoom_in_button, zoom_out_button, rotate_button, reset_view_button]:
		if b:
			ScorecardStyle.flat_button(b)
			b.add_theme_font_size_override("font_size", 16)
			b.custom_minimum_size = Vector2(120, 38)
	shoot_button.reparent(right, false)
	shoot_button.custom_minimum_size = Vector2(190, 0)
	shoot_button.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _tray_caption(text: String) -> Label:
	var l := ScorecardStyle.label(text, 13, ScorecardStyle.INK_SOFT, ScorecardStyle.header_font(false))
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = ScorecardStyle.RULE
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func update_scorecard(current_hole: int, pars: Dictionary, scores: Dictionary, live_strokes: int) -> void:
	if scorecard_table:
		scorecard_table.set_state(current_hole, pars, scores, live_strokes)


func set_this_shot(text: String) -> void:
	if _this_shot_label:
		_this_shot_label.text = text


func set_tray_info(hand_size: int, deck_left: int, deck_total: int, points: int, run_text: String) -> void:
	"""HAND · 4 OF 15, MOD DECK left/total, PTS, and the run's score line."""
	if _hand_label:
		_hand_label.text = "HAND  ·  %d OF %d" % [hand_size, deck_total]
	if _deck_label:
		_deck_label.text = "MOD DECK  %d/%d     %d PTS" % [deck_left, deck_total, points]
	if _run_label:
		_run_label.text = run_text


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
			var face := c.get_node_or_null("Face") as CardFaceView
			if face:
				face.played = pressed


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
		var row: BoxContainer = hand_club_row if is_club else hand_modifier_row
		var card_control := _make_hand_card(instance, is_club, club_subtitles.get(instance, ""))
		row.add_child(card_control)


func build_shot_card(btn: Button, instance) -> void:
	"""Scorecard card face (CardFaceView) on a see-through button. Played cards
	get a pencil tick; Strain can't be played."""
	var face := CardFaceView.for_instance(instance)
	face.name = "Face"
	btn.custom_minimum_size = CardFaceView.SIZE
	btn.tooltip_text = instance.get_full_description()
	btn.disabled = face.unplayable
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.played = btn.button_pressed
	btn.toggled.connect(func(on: bool): face.played = on)
	# Lift on hover, like picking a card up
	btn.mouse_entered.connect(func(): if not btn.disabled: face.position.y = -6.0)
	btn.mouse_exited.connect(func(): face.position.y = 0.0)


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
	var btn: Button
	if is_club:
		var line := ClubLine.new()
		line.club_name = instance.data.card_name
		line.yards = subtitle.replace(" yd", "").replace("-", "–")
		line.tooltip_text = "%s  %s" % [instance.data.card_name, subtitle]
		btn = line
	else:
		btn = Button.new()
		btn.toggle_mode = true
		build_shot_card(btn, instance)
	btn.set_meta("card_instance", instance)
	btn.pressed.connect(func() -> void:
		var bound = btn.get_meta("card_instance")
		if is_club:
			emit_signal("club_card_selected", bound)
		else:
			emit_signal("modifier_card_selected", bound)
	)
	return btn
