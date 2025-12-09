extends Control
class_name ShopUI

## ShopUI - Visual interface for the between-hole shop
## Displays card offers, upgrade options, and card removal

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

# Card slot scene path (loaded at runtime if available)
const CARD_SLOT_SCENE_PATH = "res://scenes/ui/shop_card_slot.tscn"
var card_slot_scene: PackedScene = null

# Manager references
var shop_manager: ShopManager = null
var currency_manager: CurrencyManager = null
var deck_manager: DeckManager = null

# State
var current_tab: int = 0  # 0 = Buy, 1 = Upgrade, 2 = Remove


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
	
	if currency_manager:
		if not currency_manager.currency_changed.is_connected(_on_currency_changed):
			currency_manager.currency_changed.connect(_on_currency_changed)


# --- Shop Lifecycle ---

func open() -> void:
	"""Open and display the shop"""
	visible = true
	
	if shop_manager:
		shop_manager.open_shop()
	
	_update_chips_display()
	_update_reroll_button()


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
	
	if tab == 0:
		_update_offers_display()
	else:
		_update_deck_display()


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
