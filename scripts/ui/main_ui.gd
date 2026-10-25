extends Control
class_name MainUI

# --- FEAT-003: live hand strip (club + modifier rows) -------------------
# The 2D HandStrip is the sole surface the player uses to play cards. The hole
# controller (hex_grid.gd) deals a club bag + modifier hand at hole start, binds
# it here via set_hand(), and listens for these selection signals to drive
# set_club_by_name() / activate_card_modifier().
signal club_card_selected(card_instance)
signal modifier_card_selected(card_instance)
signal lag_putt_pressed
signal caddie_peek_pressed

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
	# Wind and lie live in the tray (ConditionsStrip) under THIS SHOT
	"HoleViewer/HoleHUD/WindWidget", "HoleViewer/HoleHUD/LieView",
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

# Cards: tap one to read it (CardZoom); drag it onto the playmat to play it
var card_zoom: CardZoom
var playmat: Playmat
var chip_badge: ChipBadge
var _chips := 0
var _committed := 0
var club_tier_colors: Dictionary = {}  # ClubType name -> tier colour (set by hex_grid)
var club_uses: Dictionary = {}  # ClubType name -> [uses left, uses per hole, worn out] (set by hex_grid)
var conditions: ConditionsStrip  # wind + lie, under THIS SHOT
var putt_panel: PuttPanel  # in place of the hand while putting
var _hand_and_mat: Control
var _hand_head: Control  # HAND · N OF M and CHIPS: the shot hand's, hidden while putting

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
	card_zoom = CardZoom.new()
	card_zoom.name = "CardZoom"
	add_child(card_zoom)

	# Notifications over the hole view fade when the camera moves
	if hole_viewer and hole_viewer.has_signal("camera_moved") and shot_ui and shot_ui.has_method("fade_overlays"):
		hole_viewer.camera_moved.connect(shot_ui.fade_overlays)

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

	# Middle: HAND · N OF M and CHIPS over the hand, then the playmat beside it
	hand_strip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var rows := hand_modifier_row.get_parent() as BoxContainer
	var hand_head := HBoxContainer.new()
	_hand_head = hand_head
	rows.add_child(hand_head)
	rows.move_child(hand_head, 0)
	_hand_label = _tray_caption("HAND")
	_hand_label.size_flags_vertical = Control.SIZE_SHRINK_END
	hand_head.add_child(_hand_label)
	var head_fill := Control.new()
	head_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_head.add_child(head_fill)
	chip_badge = ChipBadge.new()
	hand_head.add_child(chip_badge)
	rows.add_theme_constant_override("separation", 4)
	var hand_and_mat := HBoxContainer.new()
	hand_and_mat.add_theme_constant_override("separation", 16)
	rows.add_child(hand_and_mat)
	hand_modifier_row.reparent(hand_and_mat, false)
	hand_modifier_row.add_theme_constant_override("separation", 12)
	hand_modifier_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	hand_modifier_row.set_drag_forwarding(Callable(), _can_drop_in_hand, _drop_in_hand)
	playmat = Playmat.new()
	playmat.name = "Playmat"
	playmat.card_dropped.connect(func(card):
		_drop_at = get_global_mouse_position() - CardFaceView.SIZE / 2.0
		emit_signal("modifier_card_selected", card)
		_drop_at = Vector2.INF)
	hand_and_mat.add_child(playmat)
	_hand_and_mat = hand_and_mat
	putt_panel = PuttPanel.new()
	putt_panel.visible = false
	putt_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	putt_panel.lag_pressed.connect(func(): lag_putt_pressed.emit())
	putt_panel.peek_pressed.connect(func(): caddie_peek_pressed.emit())
	rows.add_child(putt_panel)

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
	conditions = ConditionsStrip.new()
	conditions.name = "Conditions"
	card_col.add_child(conditions)
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
	# SHOOT is always square: as tall as the tray's content, or narrower if
	# the rest of the tray needs the width (then centred). Sized from the
	# anchored tray's height (the screen below TRAY_TOP, less the paper's top
	# rule and the margins), never the tray's current size: that grows with
	# its content, SHOOT included, and would feed back into itself.
	shoot_button.reparent(right, false)
	shoot_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var square := func():
		var others := content.get_combined_minimum_size().x - shoot_button.custom_minimum_size.x
		var room := get_viewport_rect().size.x - 36.0 - others  # the screen less the tray's side margins
		var tall := get_viewport_rect().size.y * (1.0 - TRAY_TOP) - paper.get_minimum_size().y - 22.0  # top + bottom margins
		var side := maxf(80.0, minf(tall, room))
		if not shoot_button.custom_minimum_size.is_equal_approx(Vector2(side, side)):
			shoot_button.custom_minimum_size = Vector2(side, side)
	tray.resized.connect(square)
	get_viewport().size_changed.connect(square)
	square.call()


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


func _process(_delta: float) -> void:
	_update_wind()


func _update_wind() -> void:
	"""The tray's wind arrow points where the wind blows as seen on screen, so
	it turns with the camera."""
	if conditions == null or hole_viewer == null:
		return
	var hg = hole_viewer.get("hex_grid")
	var cam: Camera3D = hole_viewer.get("camera")
	if hg == null or cam == null or hg.get("wind_system") == null:
		return
	var ws: WindSystem = hg.wind_system
	var v := ws.get_direction_vector()  # world x, z: the way the ball is pushed
	var w := Vector3(v.x, 0.0, v.y)
	var right := cam.global_basis.x
	right.y = 0.0
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	var screen := Vector2(w.dot(right.normalized()), -w.dot(fwd.normalized()))
	conditions.set_wind(ws.enabled and ws.strength > 0, screen.normalized() if screen.length() > 0.001 else Vector2.UP,
		ws.strength, ws.get_strength_name(), int(ws.speed_kmh))


func set_lie(lie_name: String, effects: String) -> void:
	if conditions:
		conditions.set_lie(lie_name, effects)


func set_putting(state: Dictionary) -> void:
	"""On the green the hand gives way to the putting card; {} puts it back."""
	if putt_panel == null:
		return
	putt_panel.visible = not state.is_empty()
	for c in [_hand_and_mat, _hand_head]:
		if c:
			c.visible = state.is_empty()
	if not state.is_empty():
		putt_panel.set_state(state)


func set_this_shot(text: String) -> void:
	if _this_shot_label:
		_this_shot_label.text = text


func set_tray_info(hand_size: int, deck_left: int, deck_total: int, points: int, run_text: String, mult: float = 1.0) -> void:
	"""HAND · 4 OF 15, MOD DECK left/total, PTS (and the bag's points
	multiplier when it's above ×1), and the run's score line."""
	if _hand_label:
		_hand_label.text = "HAND  ·  %d OF %d" % [hand_size, deck_total]
	if _deck_label:
		_deck_label.text = "MOD DECK  %d/%d     %d PTS" % [deck_left, deck_total, points]
		if mult > 1.0:
			_deck_label.text += "  ·  LIGHT BAG ×%s" % (str(int(mult)) if is_equal_approx(mult, roundf(mult)) else "%.1f" % mult)
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
	if hole_viewer:
		hole_viewer.set("show_wind_widget", not on)
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
	"""Reflect whether a shot card is played this shot (without re-emitting):
	a played card sits on the playmat, the rest in the hand."""
	if hand_modifier_row == null:
		return
	var btn := _card_button(card_instance)
	if btn == null:
		return
	# The card springs over from where it was (or from where it was dropped)
	var face := btn.get_node_or_null("Face") as Control
	var from: Vector2 = _drop_at if _drop_at != Vector2.INF else (face.global_position if face else btn.global_position)
	_drop_at = Vector2.INF
	var moved := false
	if pressed and playmat and btn.get_parent() != playmat.slots:
		playmat.add_card(btn)
		moved = true
	elif not pressed and btn.get_parent() != hand_modifier_row:
		btn.reparent(hand_modifier_row, false)
		if playmat:
			playmat.refresh()
		moved = true
	var motion := CardMotion.of(btn)
	if moved and motion:
		motion.fly_from(from)
	_refresh_affordable()


func set_chip_stack(chips: int, committed: int) -> void:
	"""Chips this hole, and what the cards on the playmat will spend."""
	_chips = chips
	_committed = committed
	if chip_badge:
		chip_badge.set_chip_stack(chips, committed)
	_refresh_affordable()


func set_range_layout() -> void:
	"""The driving range deals every card: the hand scrolls sideways (mouse
	wheel) beside the playmat, and Chips are unlimited."""
	if chip_badge:
		chip_badge.unlimited = true
		chip_badge.queue_redraw()
	if hand_modifier_row == null or hand_modifier_row.get_parent() is ScrollContainer:
		return
	var parent := hand_modifier_row.get_parent()
	var at := hand_modifier_row.get_index()
	var scroll := ScrollContainer.new()
	scroll.name = "HandScroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(200, CardFaceView.SIZE.y)
	parent.add_child(scroll)
	parent.move_child(scroll, at)
	hand_modifier_row.reparent(scroll, false)
	scroll.set_drag_forwarding(Callable(), _can_drop_in_hand, _drop_in_hand)


var _play_prompt: PanelContainer = null
var _play_prompt_tween: Tween = null


func set_flyover_mode(on: bool) -> void:
	"""Flyover: the hole takes the whole screen (no tray) with a CLICK TO PLAY
	prompt (any press skips it). Off: the tray and the shot view come back."""
	if tray:
		tray.visible = not on
	if hole_viewer:
		hole_viewer.anchor_bottom = 1.0 if on else TRAY_TOP
	if _play_prompt == null:
		_play_prompt = _build_play_prompt()
	if _play_prompt_tween:
		_play_prompt_tween.kill()
		_play_prompt_tween = null
	_play_prompt.visible = on
	if on:
		_play_prompt.modulate.a = 1.0
		_play_prompt_tween = create_tween().set_loops()
		_play_prompt_tween.tween_property(_play_prompt, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE)
		_play_prompt_tween.tween_property(_play_prompt, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)


func _build_play_prompt() -> PanelContainer:
	"""A scorecard-paper tag near the bottom of the screen."""
	var tag := PanelContainer.new()
	tag.name = "PlayPrompt"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := ScorecardStyle.paper_box(ScorecardStyle.INK, 2, ScorecardStyle.PAPER, 4)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	tag.add_theme_stylebox_override("panel", box)
	var text := ScorecardStyle.label("CLICK TO PLAY", 26, ScorecardStyle.INK, ScorecardStyle.header_font())
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(text)
	add_child(tag)
	tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	tag.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tag.offset_top -= 48
	tag.offset_bottom -= 48
	return tag


func flash_chips() -> void:
	if chip_badge:
		chip_badge.flash()


func _card_button(card_instance) -> Button:
	var rows: Array = [hand_modifier_row]
	if playmat:
		rows.append(playmat.slots)
	for row in rows:
		for c in row.get_children():
			if c is Button and c.has_meta("card_instance") and c.get_meta("card_instance") == card_instance:
				return c
	return null


func _on_mat(btn: Control) -> bool:
	return playmat != null and btn.get_parent() == playmat.slots


func _affordable(card_instance) -> bool:
	return ShotCardFace.cost_for(card_instance.data, card_instance.upgrade_level) <= _chips - _committed


func _refresh_affordable() -> void:
	"""Coins on hand cards go red when Chips left can't pay for them."""
	if hand_modifier_row == null:
		return
	for c in hand_modifier_row.get_children():
		var face := c.get_node_or_null("Face") as CardFaceView
		if face and c.has_meta("card_instance"):
			face.affordable = _affordable(c.get_meta("card_instance"))
	if playmat:
		for c in playmat.cards():
			var face := c.get_node_or_null("Face") as CardFaceView
			if face:
				face.affordable = true


func open_card_zoom(btn: Button) -> void:
	"""Tap a hand or mat card: read it big, with Play / Take back."""
	var card = btn.get_meta("card_instance")
	var face := btn.get_node_or_null("Face") as CardFaceView
	var unplayable: bool = face != null and face.unplayable
	var actions: Array = []
	var note := ""
	if _on_mat(btn):
		actions.append({"label": "TAKE BACK", "on_press": func(): emit_signal("modifier_card_selected", card)})
	else:
		var cost := ShotCardFace.cost_for(card.data, card.upgrade_level)
		var verb := "USE" if ShotCardFace.kind_for(card.data).tag == "UTILITY" else "PLAY"
		var label := "%s  ·  FREE" % verb if cost == 0 else "%s  ·  %d CHIP%s" % [verb, cost, "" if cost == 1 else "S"]
		var blocked: bool = unplayable or not _affordable(card) or (playmat != null and playmat.is_full())
		if unplayable:
			note = "Strain can't be played. Remove it in the Pro Shop."
		elif not _affordable(card):
			note = "Not enough Chips: %d left." % (_chips - _committed)
		elif playmat and playmat.is_full():
			note = "The playmat is full."
		actions.append({"label": label, "on_press": func(): emit_signal("modifier_card_selected", card), "disabled": blocked})
	# The zoom grows out of this card and shrinks back to wherever it ends up
	card_zoom.open(card, actions, note, unplayable or _on_mat(btn) or _affordable(card), btn, func(): return _card_button(card))


func _card_drag_data(btn: Button):
	"""Start dragging a card (to the playmat, or back to the hand)."""
	var face := btn.get_node_or_null("Face") as CardFaceView
	if face == null or face.unplayable:
		return null
	var card = btn.get_meta("card_instance")
	var preview := Control.new()
	var ghost := CardFaceView.for_instance(card)
	ghost.size = CardFaceView.SIZE
	ghost.position = -CardFaceView.SIZE / 2.0
	ghost.modulate.a = 0.95
	preview.add_child(ghost)
	# It swings with the drag
	CardMotion.attach(ghost).dragging = true
	btn.set_drag_preview(preview)
	# A faint gap where it was, until the drag ends
	face.modulate.a = 0.25
	return {"card": card, "from_mat": _on_mat(btn)}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_show_dragged_faces()


func _show_dragged_faces() -> void:
	"""Drag over: bring back the faded card it came from."""
	var rows: Array = [hand_modifier_row]
	if playmat:
		rows.append(playmat.slots)
	for row in rows:
		if row == null:
			continue
		for c in row.get_children():
			var face := c.get_node_or_null("Face") as Control
			if face and face.modulate.a < 1.0 and (CardMotion.of(c) == null or CardMotion.of(c)._wait <= 0.0):
				face.modulate.a = 1.0


func _can_drop_on_card(pos: Vector2, data, btn: Button) -> bool:
	return playmat._can_drop_data(pos, data) if _on_mat(btn) else _can_drop_in_hand(pos, data)


func _drop_on_card(pos: Vector2, data, btn: Button) -> void:
	if _on_mat(btn):
		playmat._drop_data(pos, data)
	else:
		_drop_in_hand(pos, data)


func _can_drop_in_hand(_pos: Vector2, data) -> bool:
	return data is Dictionary and data.get("from_mat", false)


func _drop_in_hand(_pos: Vector2, data) -> void:
	_drop_at = get_global_mouse_position() - CardFaceView.SIZE / 2.0
	emit_signal("modifier_card_selected", data.card)
	_drop_at = Vector2.INF  # used by set_card_pressed, if the card moved


var _drop_at := Vector2.INF  # where a dropped card's ghost was: it springs in from there
var _dealt: Dictionary = {}  # CardInstance -> true: cards already shown in the hand


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
	# Cards new to the hand are dealt in one after another
	var dealt: Dictionary = {}
	var deal_delay := 0.0
	for instance in all:
		if instance == null or instance.data == null:
			continue
		var is_club: bool = instance.data.card_type == CardData.CardType.CLUB
		var row: BoxContainer = hand_club_row if is_club else hand_modifier_row
		var card_control := _make_hand_card(instance, is_club, club_subtitles.get(instance, ""))
		row.add_child(card_control)
		if not is_club:
			dealt[instance] = true
			var motion := CardMotion.of(card_control)
			if motion and not _dealt.has(instance):
				motion.deal_in(deal_delay)
				deal_delay += 0.07
	_dealt = dealt


func build_shot_card(btn: Button, instance) -> void:
	"""Scorecard card face (CardFaceView) on a see-through button. Played cards
	get a pencil tick; Strain can't be played."""
	var face := CardFaceView.for_instance(instance)
	face.name = "Face"
	btn.custom_minimum_size = CardFaceView.SIZE
	btn.disabled = face.unplayable
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.played = btn.button_pressed
	btn.toggled.connect(func(on: bool): face.played = on)
	# Alive: lifts and leans on hover, springs about when it moves
	CardMotion.attach(face, btn)


func clear_hand() -> void:
	"""Remove every card control from both rows and the playmat."""
	if hand_club_row:
		for c in hand_club_row.get_children():
			c.queue_free()
	if hand_modifier_row:
		for c in hand_modifier_row.get_children():
			c.queue_free()
	if playmat:
		playmat.clear()


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
		line.tier_color = club_tier_colors.get(instance.data.target_club, Color(0, 0, 0, 0))
		var uses: Array = club_uses.get(instance.data.target_club, [])
		if not uses.is_empty():
			line.uses_left = int(uses[0])
			line.uses_max = int(uses[1])
			line.worn = bool(uses[2])
		btn = line
	else:
		btn = Button.new()
		build_shot_card(btn, instance)
		btn.disabled = false  # Strain can still be tapped and read
		# Drop on a card = drop on whatever it sits in (the mat or the hand)
		btn.set_drag_forwarding(_card_drag_data.bind(btn).unbind(1), _can_drop_on_card.bind(btn), _drop_on_card.bind(btn))
	btn.set_meta("card_instance", instance)
	btn.pressed.connect(func() -> void:
		var bound = btn.get_meta("card_instance")
		if is_club:
			emit_signal("club_card_selected", bound)
		else:
			open_card_zoom(btn)
	)
	if not is_club:
		var face := btn.get_node_or_null("Face") as CardFaceView
		if face:
			face.affordable = _affordable(instance)
	return btn
