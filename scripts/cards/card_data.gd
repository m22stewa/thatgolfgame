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
enum CardType { SHOT, PASSIVE, CONSUMABLE, JOKER }

@export var rarity: Rarity = Rarity.COMMON
@export var card_type: CardType = CardType.SHOT

# Visual
@export var icon: Texture2D = null             # Card art
@export var color_tint: Color = Color.WHITE    # Card frame color

# Cost/Requirements
@export var play_cost: int = 0                 # Energy cost to play (if using energy system)
@export var requires_target: bool = false      # Does this card need a target tile?
@export var requires_shot_in_progress: bool = true  # Must be played during shot phase?

# Card effects - uses composition pattern
# Each effect is a separate resource that can be mixed and matched
@export var effects: Array[Resource] = []      # Array of CardEffect resources

# Upgrade tracking (for Balatro-style enhancement)
@export var can_upgrade: bool = true
@export var max_upgrade_level: int = 3
@export var max_uses: int = -1                 # -1 = unlimited uses

# Tags for filtering and synergies
@export var tags: PackedStringArray = []       # e.g. ["power", "accuracy", "wind"]


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
		CardType.PASSIVE: return "Passive"
		CardType.CONSUMABLE: return "Consumable"
		CardType.JOKER: return "Joker"
		_: return "Unknown"


func has_tag(tag: String) -> bool:
	return tag in tags


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
	copy.requires_target = requires_target
	copy.requires_shot_in_progress = requires_shot_in_progress
	copy.effects = effects.duplicate()
	copy.can_upgrade = can_upgrade
	copy.max_upgrade_level = max_upgrade_level
	copy.max_uses = max_uses
	copy.tags = tags.duplicate()
	return copy
