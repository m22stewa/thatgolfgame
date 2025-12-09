extends Node
class_name CurrencyManager

## CurrencyManager - Tracks chips/coins earned from shot performance
## Integrates with RunStateManager to convert scores to spendable currency

# Signals
signal currency_changed(new_amount: int, delta: int)
signal purchase_made(item_type: String, item_id: String, cost: int)
signal purchase_failed(item_type: String, reason: String)

# Currency balance
var chips: int = 0

# Earnings configuration
@export_group("Earnings")
@export var base_hole_payout: int = 50           # Base chips per hole completed
@export var par_bonus_multiplier: float = 1.0    # Multiplier for par bonus conversion
@export var stroke_penalty: int = 10             # Chips lost per stroke over par

# Price configuration  
@export_group("Shop Prices")
@export var card_base_price: int = 100           # Base price for common cards
@export var rarity_price_multiplier: Dictionary = {
	"COMMON": 1.0,
	"UNCOMMON": 2.0,
	"RARE": 4.0,
	"LEGENDARY": 10.0
}
@export var upgrade_base_cost: int = 75          # Base cost to upgrade a card
@export var upgrade_level_multiplier: float = 1.5  # Cost multiplier per upgrade level
@export var card_removal_cost: int = 50          # Cost to remove a card from deck

# Run state reference
var run_state: RunStateManager = null


func _ready() -> void:
	# Try to find RunStateManager
	_find_run_state()


func _find_run_state() -> void:
	"""Find the RunStateManager in the scene tree"""
	run_state = get_node_or_null("/root/RunStateManager")
	if not run_state:
		# Search children
		for child in get_tree().root.get_children():
			if child is RunStateManager:
				run_state = child
				break
	
	# Connect to run state signals if found
	if run_state:
		if not run_state.hole_completed.is_connected(_on_hole_completed):
			run_state.hole_completed.connect(_on_hole_completed)
		if not run_state.score_changed.is_connected(_on_score_changed):
			run_state.score_changed.connect(_on_score_changed)


func set_run_state(state: RunStateManager) -> void:
	"""Set the RunStateManager reference"""
	run_state = state
	if run_state:
		if not run_state.hole_completed.is_connected(_on_hole_completed):
			run_state.hole_completed.connect(_on_hole_completed)
		if not run_state.score_changed.is_connected(_on_score_changed):
			run_state.score_changed.connect(_on_score_changed)


# --- Currency Operations ---

func add_chips(amount: int, reason: String = "") -> void:
	"""Add chips to the player's balance"""
	if amount <= 0:
		return
	
	var old_amount = chips
	chips += amount
	currency_changed.emit(chips, amount)
	
	if reason:
		print("[CurrencyManager] +%d chips: %s (Total: %d)" % [amount, reason, chips])


func remove_chips(amount: int, reason: String = "") -> bool:
	"""Remove chips from balance. Returns false if insufficient funds."""
	if amount <= 0:
		return true
	
	if chips < amount:
		return false
	
	chips -= amount
	currency_changed.emit(chips, -amount)
	
	if reason:
		print("[CurrencyManager] -%d chips: %s (Total: %d)" % [amount, reason, chips])
	
	return true


func can_afford(cost: int) -> bool:
	"""Check if player can afford a cost"""
	return chips >= cost


func reset_currency() -> void:
	"""Reset chips to zero (new run)"""
	chips = 0
	currency_changed.emit(0, 0)


# --- Hole Completion Rewards ---

func _on_hole_completed(hole_number: int, strokes: int, par: int, hole_score: int) -> void:
	"""Calculate and award chips based on hole performance"""
	var earnings = calculate_hole_earnings(strokes, par, hole_score)
	add_chips(earnings, "Hole %d completed" % hole_number)


func _on_score_changed(_new_score: int) -> void:
	"""Optional: React to score changes during play"""
	pass


func calculate_hole_earnings(strokes: int, par: int, hole_score: int) -> int:
	"""Calculate chip earnings for a completed hole"""
	var earnings = base_hole_payout
	
	# Par performance bonus
	var par_diff = strokes - par
	
	match par_diff:
		-3:  # Albatross
			earnings += 300
		-2:  # Eagle  
			earnings += 150
		-1:  # Birdie
			earnings += 75
		0:   # Par
			earnings += 25
		1:   # Bogey
			earnings += 0
		_:
			if par_diff < -3:
				earnings += 500  # Incredible!
			elif par_diff > 1:
				# Penalty for going over
				earnings = maxi(0, earnings - (par_diff - 1) * stroke_penalty)
	
	# Convert hole score to additional chips
	if hole_score > 0:
		earnings += int(hole_score * par_bonus_multiplier)
	
	return earnings


# --- Shop Pricing ---

func get_card_price(card_data: CardData) -> int:
	"""Calculate the purchase price for a card"""
	if card_data == null:
		return card_base_price
	
	var rarity_name = card_data.get_rarity_name().to_upper()
	var multiplier = rarity_price_multiplier.get(rarity_name, 1.0)
	
	return int(card_base_price * multiplier)


func get_upgrade_cost(card_instance: CardInstance) -> int:
	"""Calculate cost to upgrade a card to next level"""
	if card_instance == null:
		return upgrade_base_cost
	
	var level = card_instance.upgrade_level
	return int(upgrade_base_cost * pow(upgrade_level_multiplier, level))


func get_removal_cost() -> int:
	"""Get the cost to remove a card from deck"""
	return card_removal_cost


# --- Purchase Operations ---

func purchase_card(card_data: CardData) -> bool:
	"""Attempt to purchase a card. Returns true if successful."""
	var price = get_card_price(card_data)
	
	if not can_afford(price):
		purchase_failed.emit("card", "Insufficient chips")
		return false
	
	if not remove_chips(price, "Purchased %s" % card_data.card_name):
		purchase_failed.emit("card", "Failed to deduct chips")
		return false
	
	purchase_made.emit("card", card_data.card_id, price)
	return true


func purchase_upgrade(card_instance: CardInstance) -> bool:
	"""Attempt to upgrade a card. Returns true if successful."""
	if card_instance == null:
		purchase_failed.emit("upgrade", "Invalid card")
		return false
	
	if not card_instance.data.can_upgrade:
		purchase_failed.emit("upgrade", "Card cannot be upgraded")
		return false
	
	if card_instance.upgrade_level >= card_instance.data.max_upgrade_level:
		purchase_failed.emit("upgrade", "Card at max level")
		return false
	
	var cost = get_upgrade_cost(card_instance)
	
	if not can_afford(cost):
		purchase_failed.emit("upgrade", "Insufficient chips")
		return false
	
	if not remove_chips(cost, "Upgraded %s to level %d" % [card_instance.data.card_name, card_instance.upgrade_level + 1]):
		purchase_failed.emit("upgrade", "Failed to deduct chips")
		return false
	
	# Actually upgrade the card
	card_instance.upgrade()
	
	purchase_made.emit("upgrade", card_instance.data.card_id, cost)
	return true


func purchase_card_removal(card_instance: CardInstance) -> bool:
	"""Attempt to remove a card from deck. Returns true if successful."""
	if card_instance == null:
		purchase_failed.emit("removal", "Invalid card")
		return false
	
	var cost = get_removal_cost()
	
	if not can_afford(cost):
		purchase_failed.emit("removal", "Insufficient chips")
		return false
	
	if not remove_chips(cost, "Removed %s" % card_instance.data.card_name):
		purchase_failed.emit("removal", "Failed to deduct chips")
		return false
	
	purchase_made.emit("removal", card_instance.data.card_id, cost)
	return true


# --- State Queries ---

func get_balance() -> int:
	"""Get current chip balance"""
	return chips


func get_state() -> Dictionary:
	"""Get snapshot of currency state"""
	return {
		"chips": chips
	}


func load_state(state: Dictionary) -> void:
	"""Restore currency state from a dictionary"""
	chips = state.get("chips", 0)
	currency_changed.emit(chips, 0)
