extends Resource
class_name ModifierCardData

## ModifierCardData - Data for a single modifier card
## These are procedurally generated, not saved as .tres files

# Visual/display
@export var card_name: String = "Modifier"
@export var description: String = ""
@export var icon: Texture2D = null

# Modifier type (from ModifierDeckManager.ModifierType enum)
var modifier_type: int = 0

# Effects
@export var distance_modifier: int = 0      # +/- tiles to shot distance
@export var curve_modifier: int = 0         # +/- tiles left/right (negative = left/hook)
@export var is_perfect_accuracy: bool = false  # Ball lands exactly on aimed tile
@export var is_whiff: bool = false          # Complete miss - shot goes nowhere

# Shuffle trigger
@export var triggers_shuffle: bool = false  # Does drawing this card trigger a deck reshuffle?


func get_display_text() -> String:
	"""Get formatted text for UI display"""
	if is_perfect_accuracy:
		return "[color=gold]PERFECT![/color]"
	elif is_whiff:
		return "[color=red]WHIFF![/color]"
	elif curve_modifier != 0:
		var direction = "Right" if curve_modifier > 0 else "Left"
		return "[color=red]Big %s! (%+d)[/color]" % [direction, curve_modifier]
	elif distance_modifier > 0:
		return "[color=green]+%d Distance[/color]" % distance_modifier
	elif distance_modifier < 0:
		return "[color=red]%d Distance[/color]" % distance_modifier
	else:
		return "[color=gray]Neutral[/color]"


func get_color() -> Color:
	"""Get color for card border/highlight"""
	if is_perfect_accuracy:
		return Color.GOLD
	elif is_whiff or curve_modifier != 0:
		return Color.RED
	elif distance_modifier > 0:
		return Color.GREEN
	elif distance_modifier < 0:
		return Color.ORANGE_RED
	else:
		return Color.GRAY
