extends Resource
class_name ItemData

## ItemData - Data definition for an item that can be used during shots
## Items are optional and can be played after modifier flip, before shot resolution

# Item identification
@export var item_id: String = ""               # Unique identifier
@export var item_name: String = ""             # UI display name
@export var description: String = ""           # Effect description
@export var flavor_text: String = ""           # Optional lore text

# Visual
@export var icon: Texture2D = null

# Item type
enum ItemType {
	MULLIGAN,       # Redraw modifier card
	LUCKY_BALL,     # Convert negative modifier to neutral
	POWER_TEE,      # +2 distance on tee shot only
	IGNORE_WATER,   # Ball doesn't penalize in water
	IGNORE_SAND,    # Ball doesn't penalize in sand
	IGNORE_WIND,    # Wind has no effect
	COIN_MAGNET,    # Increase coin collection radius
	WORM_BURNER,    # Low trajectory, less affected by wind
	SKY_BALL,       # High trajectory, more distance
}

@export var item_type: ItemType = ItemType.MULLIGAN

# Cost
@export var shop_cost: int = 10                # Cost to buy in shop

# Usage
@export var is_consumable: bool = true         # Is used up when played?
@export var uses_remaining: int = 1            # For multi-use items

# Effect parameters (varies by item type)
@export var effect_value: int = 0              # Generic value (e.g., +2 for Power Tee)
@export var magnet_radius: int = 2             # For Coin Magnet: radius in tiles


func get_effect_description() -> String:
	"""Get detailed effect description based on item type"""
	match item_type:
		ItemType.MULLIGAN:
			return "Redraw your modifier card once this hole."
		ItemType.LUCKY_BALL:
			return "Convert any negative modifier to neutral."
		ItemType.POWER_TEE:
			return "+%d distance on tee shot only." % effect_value
		ItemType.IGNORE_WATER:
			return "No penalty if ball lands in water."
		ItemType.IGNORE_SAND:
			return "No penalty if ball lands in sand."
		ItemType.IGNORE_WIND:
			return "Wind has no effect on this shot."
		ItemType.COIN_MAGNET:
			return "Increase coin collection radius to %d tiles." % magnet_radius
		ItemType.WORM_BURNER:
			return "Low trajectory, less affected by wind but less distance."
		ItemType.SKY_BALL:
			return "High trajectory, more hang time and distance."
		_:
			return description


func duplicate_item() -> ItemData:
	"""Create a copy of this item"""
	var copy = ItemData.new()
	copy.item_id = item_id
	copy.item_name = item_name
	copy.description = description
	copy.flavor_text = flavor_text
	copy.icon = icon
	copy.item_type = item_type
	copy.shop_cost = shop_cost
	copy.is_consumable = is_consumable
	copy.uses_remaining = uses_remaining
	copy.effect_value = effect_value
	copy.magnet_radius = magnet_radius
	return copy
