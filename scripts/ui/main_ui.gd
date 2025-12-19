extends Control
class_name MainUI

@onready var shot_ui: Control = $ShotUI
@onready var combined_deck_widget: DeckWidget = $DeckWidget  # Combined view (modifier only now)
@onready var modifier_deck_widget: DeckWidget = $ModifierDeckWidget  # Standalone modifier deck
@onready var items_bar: ItemsBar = $ItemsBar  # Item slots
@onready var wind_widget: Control = $WindWidget
@onready var lie_view: Control = $LieView
@onready var hole_info_label: Label = $HoleInfoLabel
@onready var hole_viewer: Control = $HoleViewer
@onready var generate_button: Button = $GenerateButton
@onready var generate_unique_button: Button = $GenerateUniqueButton
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
