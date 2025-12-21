extends Resource
class_name CardData

## CardData - Data definition for a card type.
## This is the "blueprint" for cards - instances are created at runtime.
## Cards can be created in the editor as .tres files or procedurally.

# Card identification
@export var card_id: String = ""               # Unique identifier (e.g. "power_drive")
@export var card_name: String = ""             # UI name (e.g. "Power Drive")
@export var description: String = ""           # Card effect description
@export var flavor_text: String = ""           # Optional lore/humor text

# Card classification
enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }
enum CardType { SHOT, NEGATIVE, POSITIVE, NEUTRAL, CLUB }

# Shot shape for swing cards
enum ShotShape { STRAIGHT, DRAW, FADE, BIG_DRAW, BIG_FADE }

# Accuracy/AOE shape for swing cards  
enum AccuracyShape { SINGLE, HORIZONTAL_LINE, VERTICAL_LINE, RING }

@export var rarity: Rarity = Rarity.COMMON
@export var card_type: CardType = CardType.SHOT
@export var target_club: String = ""           # If type is CLUB, which club does it represent?

# Visual
@export var icon: Texture2D = null             # Card art
@export var shot_shape_icon: Texture2D = null  # Icon for shot shape (straight, draw, fade, etc)
@export var accuracy_icon: Texture2D = null    # Icon for accuracy/AOE shape
@export var modifier_icon_1: Texture2D = null  # Modifier card icon 1
@export var modifier_icon_2: Texture2D = null  # Modifier card icon 2
@export var modifier_icon_3: Texture2D = null  # Modifier card icon 3
@export var color_tint: Color = Color.WHITE    # Card frame color

# Cost/Requirements
@export var play_cost: int = 0                 # Energy cost to play (if using energy system)
@export var tempo_cost: int = 1                # Tempo cost for swing cards (1-3 typically)
@export var requires_target: bool = false      # Does this card need a target tile?
@export var requires_shot_in_progress: bool = true  # Must be played during shot phase?

# Swing card properties
@export var shot_shape: ShotShape = ShotShape.STRAIGHT
@export var accuracy_shape: AccuracyShape = AccuracyShape.RING

# Card effects - uses composition pattern
# Each effect is a separate resource that can be mixed and matched
@export var effects: Array[Resource] = []      # Array of CardEffect resources

# Upgrade tracking (for Balatro-style enhancement)
@export var can_upgrade: bool = true
@export var max_upgrade_level: int = 3
@export var max_uses: int = -1                 # -1 = unlimited uses


# --- Factory Methods ---

static func create(id: String, name: String, rarity_level: Rarity = Rarity.COMMON) -> CardData:
	"""Factory method to create cards programmatically"""
	var card = CardData.new()
	card.card_id = id
	card.card_name = name
	card.rarity = rarity_level
	return card


# --- Helpers ---

func get_rarity_name() -> String:
	match rarity:
		Rarity.COMMON: return "Common"
		Rarity.UNCOMMON: return "Uncommon"
		Rarity.RARE: return "Rare"
		Rarity.LEGENDARY: return "Legendary"
		_: return "Unknown"


func get_type_name() -> String:
	match card_type:
		CardType.SHOT: return "Shot"
		CardType.NEGATIVE: return "Negative"
		CardType.POSITIVE: return "Positive"
		CardType.NEUTRAL: return "Neutral"
		CardType.CLUB: return "Club"
		_: return "Unknown"


func get_rarity_color() -> Color:
	match rarity:
		Rarity.COMMON: return Color(0.8, 0.8, 0.8)      # Common - Gray
		Rarity.UNCOMMON: return Color(0.3, 0.7, 0.3)   # Uncommon - Green
		Rarity.RARE: return Color(0.3, 0.5, 0.9)       # Rare - Blue
		Rarity.LEGENDARY: return Color(0.9, 0.7, 0.2)  # Legendary - Gold
		_: return Color.WHITE


func get_formatted_description(upgrade_level: int = 0) -> String:
	"""Get description with values scaled by upgrade level"""
	# TODO: Parse description for {value} placeholders and scale them
	return description


func duplicate_card() -> CardData:
	"""Create a deep copy of this card data"""
	var copy = CardData.new()
	copy.card_id = card_id
	copy.card_name = card_name
	copy.description = description
	copy.flavor_text = flavor_text
	copy.rarity = rarity
	copy.card_type = card_type
	copy.icon = icon
	copy.color_tint = color_tint
	copy.play_cost = play_cost
	copy.tempo_cost = tempo_cost
	copy.requires_target = requires_target
	copy.requires_shot_in_progress = requires_shot_in_progress
	copy.effects = effects.duplicate()
	copy.can_upgrade = can_upgrade
	copy.max_upgrade_level = max_upgrade_level
	copy.max_uses = max_uses
	copy.shot_shape = shot_shape
	copy.accuracy_shape = accuracy_shape
	
	return copy


func get_shot_shape_name() -> String:
	"""Get display name for shot shape"""
	match shot_shape:
		ShotShape.STRAIGHT: return "Straight"
		ShotShape.DRAW: return "Draw"
		ShotShape.FADE: return "Fade"
		ShotShape.BIG_DRAW: return "Big Draw"
		ShotShape.BIG_FADE: return "Big Fade"
		_: return "Unknown"


func get_accuracy_shape_name() -> String:
	"""Get display name for accuracy shape"""
	match accuracy_shape:
		AccuracyShape.SINGLE: return "Single"
		AccuracyShape.HORIZONTAL_LINE: return "H-Line"
		AccuracyShape.VERTICAL_LINE: return "V-Line"
		AccuracyShape.RING: return "Ring"
		_: return "Unknown"


func get_curve_amount() -> int:
	"""Get curve value based on shot shape (negative = left/draw, positive = right/fade)"""
	match shot_shape:
		ShotShape.STRAIGHT: return 0
		ShotShape.DRAW: return -2
		ShotShape.FADE: return 2
		ShotShape.BIG_DRAW: return -4
		ShotShape.BIG_FADE: return 4
		_: return 0
