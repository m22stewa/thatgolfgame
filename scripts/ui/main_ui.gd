extends Control
class_name MainUI

@onready var shot_ui: Control = $ShotUI
@onready var modifier_deck_widget: DeckWidget = $ModifierDeckWidget
@onready var club_deck_widget: DeckWidget = $ClubDeckWidget
@onready var wind_widget: Control = $WindWidget
@onready var hole_info_label: Label = $HoleInfoLabel
@onready var hole_viewer: Control = $HoleViewer
@onready var generate_button: Button = $GenerateButton
@onready var lie_info_panel: PanelContainer = %LieInfoPanel
@onready var lie_name_label: Label = %LieName
@onready var lie_desc_label: RichTextLabel = %LieDescription
@onready var lie_mods_label: RichTextLabel = %LieModifiers

func _ready() -> void:
	# Ensure full screen layout
	set_anchors_preset(Control.PRESET_FULL_RECT)
