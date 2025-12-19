extends Node
class_name ItemManager

## ItemManager - Manages the player's item inventory
## Items can be used during the shot flow after modifier flip

signal item_added(item: ItemData)
signal item_removed(item: ItemData)
signal item_used(item: ItemData)
signal inventory_changed(items: Array[ItemData])

# Inventory configuration
const MAX_INVENTORY_SLOTS: int = 5

# Current inventory
var _inventory: Array[ItemData] = []

# Item queued for current shot (played after modifier, before resolution)
var _queued_item: ItemData = null


func _ready() -> void:
	pass


# --- Inventory Management ---

func add_item(item: ItemData) -> bool:
	"""Add an item to inventory. Returns false if inventory full."""
	if _inventory.size() >= MAX_INVENTORY_SLOTS:
		push_warning("[ItemManager] Inventory full, cannot add item: %s" % item.item_name)
		return false
	
	_inventory.append(item)
	item_added.emit(item)
	inventory_changed.emit(_inventory)
	print("[ItemManager] Added item: %s" % item.item_name)
	return true


func remove_item(item: ItemData) -> bool:
	"""Remove an item from inventory. Returns false if not found."""
	var index = _inventory.find(item)
	if index == -1:
		return false
	
	_inventory.remove_at(index)
	item_removed.emit(item)
	inventory_changed.emit(_inventory)
	print("[ItemManager] Removed item: %s" % item.item_name)
	return true


func has_item(item_type: ItemData.ItemType) -> bool:
	"""Check if player has an item of the specified type"""
	for item in _inventory:
		if item.item_type == item_type:
			return true
	return false


func get_item_by_type(item_type: ItemData.ItemType) -> ItemData:
	"""Get first item of the specified type, or null"""
	for item in _inventory:
		if item.item_type == item_type:
			return item
	return null


func get_inventory() -> Array[ItemData]:
	"""Get copy of current inventory"""
	return _inventory.duplicate()


func get_inventory_size() -> int:
	return _inventory.size()


func get_max_slots() -> int:
	return MAX_INVENTORY_SLOTS


func clear_inventory() -> void:
	"""Clear all items (for new run)"""
	_inventory.clear()
	inventory_changed.emit(_inventory)


# --- Item Usage ---

func queue_item_for_shot(item: ItemData) -> void:
	"""Queue an item to be used on the current shot"""
	_queued_item = item
	print("[ItemManager] Queued item for shot: %s" % item.item_name)


func get_queued_item() -> ItemData:
	return _queued_item


func clear_queued_item() -> void:
	_queued_item = null


func use_queued_item() -> ItemData:
	"""Use the queued item and remove from inventory if consumable"""
	if _queued_item == null:
		return null
	
	var item = _queued_item
	_queued_item = null
	
	if item.is_consumable:
		item.uses_remaining -= 1
		if item.uses_remaining <= 0:
			remove_item(item)
	
	item_used.emit(item)
	print("[ItemManager] Used item: %s" % item.item_name)
	return item


# --- Item Factory ---

static func create_mulligan() -> ItemData:
	var item = ItemData.new()
	item.item_id = "mulligan"
	item.item_name = "Mulligan Token"
	item.item_type = ItemData.ItemType.MULLIGAN
	item.description = "Redraw modifier card once per hole"
	item.shop_cost = 15
	return item


static func create_lucky_ball() -> ItemData:
	var item = ItemData.new()
	item.item_id = "lucky_ball"
	item.item_name = "Lucky Ball"
	item.item_type = ItemData.ItemType.LUCKY_BALL
	item.description = "Convert negative modifier to neutral"
	item.shop_cost = 20
	return item


static func create_power_tee() -> ItemData:
	var item = ItemData.new()
	item.item_id = "power_tee"
	item.item_name = "Power Tee"
	item.item_type = ItemData.ItemType.POWER_TEE
	item.description = "+2 distance on tee shot"
	item.effect_value = 2
	item.shop_cost = 10
	return item


static func create_ignore_water() -> ItemData:
	var item = ItemData.new()
	item.item_id = "ignore_water"
	item.item_name = "Floater Ball"
	item.item_type = ItemData.ItemType.IGNORE_WATER
	item.description = "No penalty in water"
	item.shop_cost = 25
	return item


static func create_ignore_sand() -> ItemData:
	var item = ItemData.new()
	item.item_id = "ignore_sand"
	item.item_name = "Sand Skipper"
	item.item_type = ItemData.ItemType.IGNORE_SAND
	item.description = "No penalty in sand"
	item.shop_cost = 15
	return item


static func create_ignore_wind() -> ItemData:
	var item = ItemData.new()
	item.item_id = "ignore_wind"
	item.item_name = "Heavy Ball"
	item.item_type = ItemData.ItemType.IGNORE_WIND
	item.description = "Wind has no effect"
	item.shop_cost = 20
	return item


static func create_coin_magnet() -> ItemData:
	var item = ItemData.new()
	item.item_id = "coin_magnet"
	item.item_name = "Coin Magnet"
	item.item_type = ItemData.ItemType.COIN_MAGNET
	item.description = "Collect coins within 3 tiles"
	item.magnet_radius = 3
	item.shop_cost = 30
	return item


static func create_worm_burner() -> ItemData:
	var item = ItemData.new()
	item.item_id = "worm_burner"
	item.item_name = "Worm Burner"
	item.item_type = ItemData.ItemType.WORM_BURNER
	item.description = "Low trajectory, less wind effect"
	item.shop_cost = 15
	return item


static func create_sky_ball() -> ItemData:
	var item = ItemData.new()
	item.item_id = "sky_ball"
	item.item_name = "Sky Ball"
	item.item_type = ItemData.ItemType.SKY_BALL
	item.description = "High trajectory, more distance"
	item.shop_cost = 15
	return item
