extends Control
class_name ShopUI

## ShopUI - Visual interface for the between-hole shop
## Displays card offers, upgrade options, card removal, modifier deck, and items

# Signals
signal shop_closed()
signal card_selected(card_data: CardData, index: int)

# UI References
@onready var shop_panel: PanelContainer = $ShopPanel
@onready var title_label: Label = %TitleLabel
@onready var chips_label: Label = %ChipsLabel
@onready var offers_container: HBoxContainer = %OffersContainer
@onready var deck_container: HBoxContainer = %DeckContainer
@onready var reroll_button: Button = %RerollButton
@onready var continue_button: Button = %ContinueButton
@onready var tab_container: TabContainer = %TabContainer

# NEW: Modifier deck and item containers (created dynamically if not in scene)
var modifier_container: VBoxContainer = null
var items_container: HBoxContainer = null
var actions_label: Label = null

# Card slot scene path (loaded at runtime if available)
const CARD_SLOT_SCENE_PATH = "res://scenes/ui/shop_card_slot.tscn"
var card_slot_scene: PackedScene = null

# Manager references
var shop_manager: ShopManager = null
var currency_manager: CurrencyManager = null
var deck_manager: DeckManager = null
var modifier_deck_manager = null  # ModifierDeckManager
var item_manager = null  # ItemManager

# State
var current_tab: int = 0  # 0 = Buy, 1 = Upgrade, 2 = Remove, 3 = Modifiers, 4 = Items


func _ready() -> void:
	_setup_connections()
	visible = false
	
	# Try to load card slot scene at runtime
	if ResourceLoader.exists(CARD_SLOT_SCENE_PATH):
		card_slot_scene = load(CARD_SLOT_SCENE_PATH)


func _setup_connections() -> void:
	if reroll_button:
		reroll_button.pressed.connect(_on_reroll_pressed)
	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)
	if tab_container:
		tab_container.tab_changed.connect(_on_tab_changed)


func set_managers(shop: ShopManager, currency: CurrencyManager, deck: DeckManager) -> void:
	"""Set manager references"""
	shop_manager = shop
	currency_manager = currency
	deck_manager = deck
	
	# Connect to signals
	if shop_manager:
		if not shop_manager.shop_refreshed.is_connected(_on_shop_refreshed):
			shop_manager.shop_refreshed.connect(_on_shop_refreshed)
		if not shop_manager.card_purchased.is_connected(_on_card_purchased):
			shop_manager.card_purchased.connect(_on_card_purchased)
		if shop_manager.has_signal("actions_remaining_changed") and not shop_manager.actions_remaining_changed.is_connected(_on_actions_changed):
			shop_manager.actions_remaining_changed.connect(_on_actions_changed)
	
	if currency_manager:
		if not currency_manager.currency_changed.is_connected(_on_currency_changed):
			currency_manager.currency_changed.connect(_on_currency_changed)


func set_new_managers(modifier_deck, items) -> void:
	"""Set new system manager references"""
	modifier_deck_manager = modifier_deck
	item_manager = items


# --- Shop Lifecycle ---

func open() -> void:
	"""Open and display the shop"""
	visible = true
	
	if shop_manager:
		shop_manager.open_shop()
	
	# Create new tabs if needed
	_create_modifier_tab()
	_create_items_tab()
	
	_update_chips_display()
	_update_reroll_button()
	
	# Update initial tab
	_on_tab_changed(current_tab)


func close() -> void:
	"""Close the shop"""
	visible = false
	
	if shop_manager:
		shop_manager.close_shop()
	
	shop_closed.emit()


# --- Display Updates ---

func _update_chips_display() -> void:
	"""Update the chips counter"""
	if chips_label and currency_manager:
		chips_label.text = "%d" % currency_manager.get_balance()


func _update_reroll_button() -> void:
	"""Update reroll button text and state"""
	if not reroll_button or not shop_manager:
		return
	
	var cost = shop_manager.get_reroll_cost()
	if cost == 0:
		reroll_button.text = "Reroll (FREE)"
		reroll_button.disabled = false
	else:
		reroll_button.text = "Reroll (%d)" % cost
		reroll_button.disabled = not (currency_manager and currency_manager.can_afford(cost))


func _update_offers_display() -> void:
	"""Update the card offers display"""
	if not offers_container or not shop_manager:
		return
	
	# Clear existing
	for child in offers_container.get_children():
		child.queue_free()
	
	# Add offer cards
	var offers = shop_manager.get_offers()
	for i in range(offers.size()):
		var card_data = offers[i]
		var slot = _create_offer_slot(card_data, i)
		offers_container.add_child(slot)


func _create_offer_slot(card_data: CardData, index: int) -> Control:
	"""Create a UI slot for a card offer"""
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(150, 200)
	
	var vbox = VBoxContainer.new()
	slot.add_child(vbox)
	
	# Card name
	var name_label = Label.new()
	name_label.text = card_data.card_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	# Rarity
	var rarity_label = Label.new()
	rarity_label.text = card_data.get_rarity_name()
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_color_override("font_color", card_data.get_rarity_color())
	vbox.add_child(rarity_label)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = card_data.description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.y = 60
	vbox.add_child(desc_label)
	
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Price and buy button
	var price = shop_manager.get_offer_price(index) if shop_manager else 100
	var can_buy = shop_manager.can_afford_offer(index) if shop_manager else false
	
	var buy_button = Button.new()
	buy_button.text = "Buy (%d)" % price
	buy_button.disabled = not can_buy
	buy_button.pressed.connect(_on_buy_pressed.bind(index))
	vbox.add_child(buy_button)
	
	return slot


func _update_deck_display() -> void:
	"""Update the deck cards display (for upgrade/remove tabs)"""
	if not deck_container or not deck_manager:
		return
	
	# Clear existing
	for child in deck_container.get_children():
		child.queue_free()
	
	# Get all cards in deck
	var all_cards = _get_all_deck_cards()
	
	for card in all_cards:
		var slot = _create_deck_card_slot(card)
		deck_container.add_child(slot)


func _get_all_deck_cards() -> Array[CardInstance]:
	"""Get all cards currently in the player's deck"""
	var cards: Array[CardInstance] = []
	
	if not deck_manager:
		return cards
	
	# Get all cards from deck manager
	return deck_manager.get_all_deck_cards()


func _create_deck_card_slot(card: CardInstance) -> Control:
	"""Create a UI slot for a deck card (upgrade/remove)"""
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(150, 200)
	
	var vbox = VBoxContainer.new()
	slot.add_child(vbox)
	
	# Card name with upgrade level
	var name_label = Label.new()
	var upgrade_text = ""
	if card.upgrade_level > 0:
		upgrade_text = " +%d" % card.upgrade_level
	name_label.text = card.data.card_name + upgrade_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = card.data.get_formatted_description(card.upgrade_level)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.y = 60
	vbox.add_child(desc_label)
	
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Action button based on current tab
	var action_button = Button.new()
	
	if current_tab == 1:  # Upgrade
		var cost = currency_manager.get_upgrade_cost(card) if currency_manager else 100
		var can_upgrade = card.data.can_upgrade and card.upgrade_level < card.data.max_upgrade_level
		can_upgrade = can_upgrade and (currency_manager.can_afford(cost) if currency_manager else false)
		
		action_button.text = "Upgrade (%d)" % cost
		action_button.disabled = not can_upgrade
		action_button.pressed.connect(_on_upgrade_pressed.bind(card))
	else:  # Remove
		var cost = currency_manager.get_removal_cost() if currency_manager else 50
		var can_remove = currency_manager.can_afford(cost) if currency_manager else false
		
		action_button.text = "Remove (%d)" % cost
		action_button.disabled = not can_remove
		action_button.pressed.connect(_on_remove_pressed.bind(card))
	
	vbox.add_child(action_button)
	
	return slot


# --- Signal Handlers ---

func _on_shop_refreshed(_offers: Array[CardData]) -> void:
	_update_offers_display()
	_update_reroll_button()


func _on_card_purchased(_card_data: CardData) -> void:
	_update_offers_display()
	_update_chips_display()


func _on_currency_changed(_amount: int, _delta: int) -> void:
	_update_chips_display()
	_update_reroll_button()
	
	# Refresh displays to update button states
	if current_tab == 0:
		_update_offers_display()
	else:
		_update_deck_display()


func _on_tab_changed(tab: int) -> void:
	current_tab = tab
	
	match tab:
		0:  # Buy cards
			_update_offers_display()
		1, 2:  # Upgrade or Remove
			_update_deck_display()
		3:  # Modifiers
			_update_modifier_display()
		4:  # Items
			_update_items_display()


func _on_reroll_pressed() -> void:
	if shop_manager:
		shop_manager.reroll_offers()


func _on_continue_pressed() -> void:
	close()


func _on_buy_pressed(index: int) -> void:
	if shop_manager:
		shop_manager.purchase_offer(index)


func _on_upgrade_pressed(card: CardInstance) -> void:
	if shop_manager:
		shop_manager.upgrade_card(card)
		_update_deck_display()
		_update_chips_display()


func _on_remove_pressed(card: CardInstance) -> void:
	if shop_manager:
		shop_manager.remove_card(card)
		_update_deck_display()
		_update_chips_display()


# --- NEW: Modifier Deck Tab ---

func _create_modifier_tab() -> void:
	"""Create the modifier deck manipulation tab"""
	if not tab_container:
		return
	
	# Check if tab already exists
	for i in range(tab_container.get_tab_count()):
		if tab_container.get_tab_title(i) == "Modifiers":
			return
	
	modifier_container = VBoxContainer.new()
	modifier_container.name = "Modifiers"
	tab_container.add_child(modifier_container)
	
	# Actions remaining label
	actions_label = Label.new()
	actions_label.text = "Actions: 3/3"
	actions_label.add_theme_font_size_override("font_size", 18)
	modifier_container.add_child(actions_label)
	
	# Deck composition display
	var composition_label = Label.new()
	composition_label.name = "CompositionLabel"
	composition_label.text = "Deck Composition:"
	modifier_container.add_child(composition_label)
	
	var composition_text = RichTextLabel.new()
	composition_text.name = "CompositionText"
	composition_text.bbcode_enabled = true
	composition_text.fit_content = true
	composition_text.custom_minimum_size = Vector2(300, 100)
	modifier_container.add_child(composition_text)
	
	# Separator
	modifier_container.add_child(HSeparator.new())
	
	# Actions HBox
	var actions_hbox = HBoxContainer.new()
	actions_hbox.add_theme_constant_override("separation", 10)
	modifier_container.add_child(actions_hbox)
	
	# Add Neutral button
	var add_neutral_btn = Button.new()
	add_neutral_btn.text = "Add Neutral (5)"
	add_neutral_btn.pressed.connect(_on_add_neutral_pressed)
	actions_hbox.add_child(add_neutral_btn)
	
	# Add +1 button
	var add_plus_btn = Button.new()
	add_plus_btn.text = "Add +1 Distance (15)"
	add_plus_btn.pressed.connect(_on_add_plus_one_pressed)
	actions_hbox.add_child(add_plus_btn)
	
	# Remove negative section
	modifier_container.add_child(HSeparator.new())
	
	var remove_label = Label.new()
	remove_label.text = "Remove Negative Cards (10 each):"
	modifier_container.add_child(remove_label)
	
	var remove_hbox = HBoxContainer.new()
	remove_hbox.name = "RemoveButtons"
	remove_hbox.add_theme_constant_override("separation", 10)
	modifier_container.add_child(remove_hbox)


func _update_modifier_display() -> void:
	"""Update modifier deck tab display"""
	if not modifier_container:
		_create_modifier_tab()
		return
	
	# Update actions label
	if actions_label and shop_manager:
		actions_label.text = "Actions: %d/3" % shop_manager.get_actions_remaining()
	
	# Update composition
	var composition_text = modifier_container.get_node_or_null("CompositionText")
	if composition_text and shop_manager:
		var comp = shop_manager.get_modifier_deck_composition()
		var text = ""
		for type_name in comp:
			var count = comp[type_name]
			var color = "white"
			if "PLUS" in type_name:
				color = "green"
			elif "MINUS" in type_name or "WHIFF" in type_name or "SLICE" in type_name or "HOOK" in type_name:
				color = "red"
			elif "PERFECT" in type_name:
				color = "gold"
			text += "[color=%s]%s: %d[/color]\n" % [color, type_name.replace("_", " ").capitalize(), count]
		composition_text.text = text
	
	# Update remove buttons
	var remove_hbox = modifier_container.get_node_or_null("RemoveButtons")
	if remove_hbox:
		for child in remove_hbox.get_children():
			child.queue_free()
		
		# Add buttons for removable negative types
		var negative_types = [
			{"name": "-1 Distance", "type": 3},  # DISTANCE_MINUS_1
			{"name": "-2 Distance", "type": 4},  # DISTANCE_MINUS_2
			{"name": "Whiff", "type": 6},
			{"name": "Big Slice", "type": 7},
		]
		
		for neg in negative_types:
			var btn = Button.new()
			btn.text = "Remove %s" % neg["name"]
			btn.pressed.connect(_on_remove_modifier_pressed.bind(neg["type"]))
			
			# Disable if can't afford or no actions
			if shop_manager:
				btn.disabled = not shop_manager.can_purchase() or not _has_modifier_of_type(neg["type"])
			
			remove_hbox.add_child(btn)


func _has_modifier_of_type(type: int) -> bool:
	"""Check if deck has a modifier of the given type"""
	if not shop_manager:
		return false
	var comp = shop_manager.get_modifier_deck_composition()
	var type_name = _get_modifier_type_name(type)
	return comp.get(type_name, 0) > 0


func _get_modifier_type_name(type: int) -> String:
	"""Get string name for modifier type enum value"""
	match type:
		0: return "NEUTRAL"
		1: return "DISTANCE_PLUS_1"
		2: return "DISTANCE_PLUS_2"
		3: return "DISTANCE_MINUS_1"
		4: return "DISTANCE_MINUS_2"
		5: return "PERFECT_ACCURACY"
		6: return "WHIFF"
		7: return "BIG_SLICE"
		8: return "BIG_HOOK"
		_: return "UNKNOWN"


func _on_add_neutral_pressed() -> void:
	if shop_manager and shop_manager.add_neutral_modifier():
		_update_modifier_display()
		_update_chips_display()


func _on_add_plus_one_pressed() -> void:
	if shop_manager and shop_manager.add_plus_one_modifier():
		_update_modifier_display()
		_update_chips_display()


func _on_remove_modifier_pressed(modifier_type: int) -> void:
	if shop_manager and shop_manager.remove_negative_modifier(modifier_type):
		_update_modifier_display()
		_update_chips_display()


func _on_actions_changed(remaining: int) -> void:
	if actions_label:
		actions_label.text = "Actions: %d/3" % remaining
	_update_modifier_display()


# --- NEW: Items Tab ---

func _create_items_tab() -> void:
	"""Create the items purchase tab"""
	if not tab_container:
		return
	
	# Check if tab already exists
	for i in range(tab_container.get_tab_count()):
		if tab_container.get_tab_title(i) == "Items":
			return
	
	var items_vbox = VBoxContainer.new()
	items_vbox.name = "Items"
	tab_container.add_child(items_vbox)
	
	var items_label = Label.new()
	items_label.text = "Buy Items (use during shots):"
	items_label.add_theme_font_size_override("font_size", 18)
	items_vbox.add_child(items_label)
	
	# Inventory display
	var inventory_label = Label.new()
	inventory_label.name = "InventoryLabel"
	inventory_label.text = "Inventory: 0/5"
	items_vbox.add_child(inventory_label)
	
	items_vbox.add_child(HSeparator.new())
	
	items_container = HBoxContainer.new()
	items_container.name = "ItemsContainer"
	items_container.add_theme_constant_override("separation", 10)
	items_vbox.add_child(items_container)


func _update_items_display() -> void:
	"""Update items tab display"""
	if not items_container:
		_create_items_tab()
		return
	
	# Clear existing
	for child in items_container.get_children():
		child.queue_free()
	
	# Get available items from shop
	if not shop_manager:
		return
	
	var items = shop_manager.get_available_items()
	
	for item_info in items:
		var slot = _create_item_slot(item_info)
		items_container.add_child(slot)
	
	# Update inventory label
	var items_tab = tab_container.get_node_or_null("Items")
	if items_tab and item_manager:
		var inv_label = items_tab.get_node_or_null("InventoryLabel")
		if inv_label:
			inv_label.text = "Inventory: %d/%d" % [item_manager.get_inventory_size(), item_manager.get_max_slots()]


func _create_item_slot(item_info: Dictionary) -> Control:
	"""Create a UI slot for an item"""
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(140, 180)
	
	var vbox = VBoxContainer.new()
	slot.add_child(vbox)
	
	# Item name
	var name_label = Label.new()
	name_label.text = item_info.get("name", "Item")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = item_info.get("description", "")
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.y = 60
	desc_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(desc_label)
	
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Buy button
	var cost = item_info.get("cost", 10)
	var buy_button = Button.new()
	buy_button.text = "Buy (%d)" % cost
	
	var can_buy = shop_manager.can_purchase() if shop_manager else false
	can_buy = can_buy and (currency_manager.can_afford(cost) if currency_manager else false)
	if item_manager:
		can_buy = can_buy and item_manager.get_inventory_size() < item_manager.get_max_slots()
	
	buy_button.disabled = not can_buy
	buy_button.pressed.connect(_on_buy_item_pressed.bind(item_info.get("id", "")))
	vbox.add_child(buy_button)
	
	return slot


func _on_buy_item_pressed(item_id: String) -> void:
	if shop_manager and shop_manager.buy_item(item_id):
		_update_items_display()
		_update_chips_display()
