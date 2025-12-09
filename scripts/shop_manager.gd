extends Node
class_name ShopManager

## ShopManager - Handles shop inventory and card offerings
## Generates random card selections for between-hole shopping

# Signals
signal shop_opened()
signal shop_closed()
signal shop_refreshed(offers: Array[CardData])
signal card_purchased(card_data: CardData)
signal card_upgraded(card_instance: CardInstance)
signal card_removed(card_instance: CardInstance)

# Shop configuration
@export_group("Offer Settings")
@export var cards_offered: int = 3                  # Cards to show in shop
@export var reroll_cost: int = 25                   # Cost to refresh shop
@export var free_rerolls_per_hole: int = 1          # Free rerolls each hole

# Rarity weights (higher = more common)
@export var rarity_weights: Dictionary = {
	CardData.Rarity.COMMON: 60,
	CardData.Rarity.UNCOMMON: 25,
	CardData.Rarity.RARE: 12,
	CardData.Rarity.LEGENDARY: 3
}

# Current shop state
var current_offers: Array[CardData] = []
var rerolls_remaining: int = 0
var is_shop_open: bool = false

# References
var currency_manager: CurrencyManager = null
var deck_manager: DeckManager = null
var card_library: CardLibrary = null


func _ready() -> void:
	_find_references()


func _find_references() -> void:
	"""Find required manager references"""
	# Currency manager
	currency_manager = get_node_or_null("/root/CurrencyManager")
	
	# Deck manager - might be in scene tree
	deck_manager = get_node_or_null("/root/DeckManager")
	
	# Card library is a singleton
	card_library = CardLibrary.instance


func set_managers(currency: CurrencyManager, deck: DeckManager) -> void:
	"""Set manager references directly"""
	currency_manager = currency
	deck_manager = deck


# --- Shop Lifecycle ---

func open_shop() -> void:
	"""Open the shop and generate offers"""
	is_shop_open = true
	rerolls_remaining = free_rerolls_per_hole
	
	generate_offers()
	shop_opened.emit()


func close_shop() -> void:
	"""Close the shop"""
	is_shop_open = false
	current_offers.clear()
	shop_closed.emit()


func generate_offers() -> void:
	"""Generate a new set of card offers"""
	current_offers.clear()
	
	if not card_library:
		card_library = CardLibrary.instance
	
	if not card_library:
		push_warning("[ShopManager] CardLibrary not available")
		return
	
	# Get all available cards
	var available_cards = _get_purchasable_cards()
	
	if available_cards.is_empty():
		push_warning("[ShopManager] No cards available for shop")
		return
	
	# Generate weighted random selection
	for i in range(cards_offered):
		var selected = _select_weighted_card(available_cards)
		if selected:
			current_offers.append(selected)
	
	shop_refreshed.emit(current_offers)


func _get_purchasable_cards() -> Array[CardData]:
	"""Get all cards that can appear in the shop"""
	var cards: Array[CardData] = []
	
	if not card_library:
		return cards
	
	# Get all non-club cards from library
	var all_cards = card_library.get_all_cards()
	
	for card in all_cards:
		# Skip club cards - those are managed separately
		if card.card_type == CardData.CardType.CLUB:
			continue
		
		# Skip cards already in deck (optional - remove for duplicates)
		# if _is_card_in_deck(card):
		#     continue
		
		cards.append(card)
	
	return cards


func _select_weighted_card(available: Array[CardData]) -> CardData:
	"""Select a card using rarity weights"""
	if available.is_empty():
		return null
	
	# Calculate total weight
	var total_weight = 0
	var weighted_cards: Array[Dictionary] = []
	
	for card in available:
		var weight = rarity_weights.get(card.rarity, 10)
		total_weight += weight
		weighted_cards.append({
			"card": card,
			"weight": weight
		})
	
	# Random selection
	var roll = randi() % total_weight
	var cumulative = 0
	
	for entry in weighted_cards:
		cumulative += entry.weight
		if roll < cumulative:
			return entry.card
	
	# Fallback
	return available[0]


# --- Shop Actions ---

func purchase_offer(index: int) -> bool:
	"""Purchase a card from the current offers"""
	if index < 0 or index >= current_offers.size():
		return false
	
	var card_data = current_offers[index]
	
	if not currency_manager:
		push_warning("[ShopManager] CurrencyManager not available")
		return false
	
	# Attempt purchase
	if not currency_manager.purchase_card(card_data):
		return false
	
	# Add card to deck
	if deck_manager:
		var instance = deck_manager.add_card_to_deck(card_data)
		if instance:
			card_purchased.emit(card_data)
	
	# Remove from offers
	current_offers.remove_at(index)
	shop_refreshed.emit(current_offers)
	
	return true


func reroll_offers() -> bool:
	"""Refresh the shop offers (costs chips after free rerolls)"""
	if rerolls_remaining > 0:
		rerolls_remaining -= 1
		generate_offers()
		return true
	
	# Paid reroll
	if currency_manager and currency_manager.can_afford(reroll_cost):
		if currency_manager.remove_chips(reroll_cost, "Shop reroll"):
			generate_offers()
			return true
	
	return false


func get_reroll_cost() -> int:
	"""Get current reroll cost (0 if free rerolls available)"""
	if rerolls_remaining > 0:
		return 0
	return reroll_cost


# --- Card Upgrade ---

func upgrade_card(card_instance: CardInstance) -> bool:
	"""Upgrade a card in the player's deck"""
	if not currency_manager:
		return false
	
	if not currency_manager.purchase_upgrade(card_instance):
		return false
	
	card_upgraded.emit(card_instance)
	return true


# --- Card Removal ---

func remove_card(card_instance: CardInstance) -> bool:
	"""Remove a card from the player's deck"""
	if not currency_manager:
		return false
	
	if not currency_manager.purchase_card_removal(card_instance):
		return false
	
	# Remove from deck
	if deck_manager:
		deck_manager.remove_card_from_deck(card_instance)
	
	card_removed.emit(card_instance)
	return true


# --- State Queries ---

func get_offers() -> Array[CardData]:
	"""Get current shop offers"""
	return current_offers


func get_offer_price(index: int) -> int:
	"""Get price for a specific offer"""
	if index < 0 or index >= current_offers.size():
		return 0
	
	if not currency_manager:
		return 100  # Default
	
	return currency_manager.get_card_price(current_offers[index])


func can_afford_offer(index: int) -> bool:
	"""Check if player can afford an offer"""
	if not currency_manager:
		return false
	
	var price = get_offer_price(index)
	return currency_manager.can_afford(price)
