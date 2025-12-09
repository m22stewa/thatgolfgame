extends PanelContainer
class_name ShotNumber

@onready var label: Label = $Label

@export_group("Visual Settings")
@export var current_color: Color = Color(1, 0.8, 0.2)
@export var past_color: Color = Color(0.5, 0.5, 0.5)
@export var future_color: Color = Color.WHITE

@export var current_bg_color: Color = Color(0.2, 0.2, 0.2, 0.8)
@export var normal_bg_color: Color = Color(0.1, 0.1, 0.1, 0.4)

@export var current_font_size: int = 32
@export var normal_font_size: int = 24

func _ready() -> void:
	# Ensure we have a stylebox to modify for background color
	if not get_theme_stylebox("panel"):
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		add_theme_stylebox_override("panel", style)

func set_number(number: int) -> void:
	if label:
		label.text = str(number)
	elif has_node("Label"):
		$Label.text = str(number)

func set_state(state: String) -> void:
	# state: "past", "current", "future"
	var lbl = label if label else get_node_or_null("Label")
	if not lbl: return
	
	var style = get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		style = StyleBoxFlat.new()
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		add_theme_stylebox_override("panel", style)
	
	match state:
		"current":
			lbl.add_theme_color_override("font_color", current_color)
			lbl.add_theme_font_size_override("font_size", current_font_size)
			style.bg_color = current_bg_color
			style.border_width_bottom = 2
			style.border_color = current_color
			custom_minimum_size = Vector2(40, 40)
			
		"past":
			lbl.add_theme_color_override("font_color", past_color)
			lbl.add_theme_font_size_override("font_size", normal_font_size)
			style.bg_color = normal_bg_color
			style.border_width_bottom = 0
			custom_minimum_size = Vector2(30, 30)
			
		"future":
			lbl.add_theme_color_override("font_color", future_color)
			lbl.add_theme_font_size_override("font_size", normal_font_size)
			style.bg_color = normal_bg_color
			style.border_width_bottom = 0
			custom_minimum_size = Vector2(30, 30)
