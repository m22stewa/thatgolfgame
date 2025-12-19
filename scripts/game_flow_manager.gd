extends Node
class_name GameFlowManager

## GameFlowManager - Central controller for the new shot flow
## Shot Flow: Choose hex -> Play swing card -> Flip modifier -> Play optional item -> Swing
## 
## This manager coordinates between all the new systems:
## - TempoManager (swing card costs)
## - ModifierDeckManager (modifier card draws)
## - ItemManager (optional item usage)
## - ScoringManager (points, multipliers, bonuses)
## - ShopManager (between-hole purchases)

# Signals
signal flow_state_changed(state: FlowState)
signal swing_card_played(card: CardInstance, tempo_cost: int)
signal modifier_flipped(card: ModifierCardData)
signal item_activated(item: ItemData)
signal shot_ready()
signal shot_cancelled()

enum FlowState {
	IDLE,
	CHOOSING_HEX,
	CHOOSING_SWING_CARD,
	FLIPPING_MODIFIER,
	CHOOSING_ITEM,
	READY_TO_SWING,
	ANIMATING,
	HOLE_COMPLETE,
	IN_SHOP
}

# Current flow state
var current_state: FlowState = FlowState.IDLE

# Manager references (set externally or auto-found)
var tempo_manager: TempoManager = null
var modifier_deck_manager = null  # ModifierDeckManager
var item_manager: ItemManager = null
var scoring_manager: ScoringManager = null
var shop_manager: ShopManager = null
var run_state_manager: RunStateManager = null
var currency_manager: CurrencyManager = null
var shot_manager: ShotManager = null
var hex_grid = null  # Reference to the hex_grid node

# Current shot data
var selected_hex: Vector2i = Vector2i(-1, -1)
var selected_swing_card: CardInstance = null
var drawn_modifier: ModifierCardData = null
var selected_item: ItemData = null

# Mulligan tracking (one per hole)
var mulligan_used_this_hole: bool = false


func _ready() -> void:
	call_deferred("_auto_setup")


func _auto_setup() -> void:
	"""Auto-find manager references"""
	# These can be set externally or found in scene tree
	if not tempo_manager:
		tempo_manager = _find_or_create_manager("TempoManager", TempoManager)
	if not modifier_deck_manager:
		modifier_deck_manager = _find_or_create_manager("ModifierDeckManager", ModifierDeckManager)
	if not item_manager:
		item_manager = _find_or_create_manager("ItemManager", ItemManager)
	if not scoring_manager:
		scoring_manager = _find_or_create_manager("ScoringManager", ScoringManager)


func _find_or_create_manager(node_name: String, manager_class) -> Node:
	"""Find a manager in tree or create one"""
	var found = get_node_or_null("/root/%s" % node_name)
	if found:
		return found
	
	# Check children
	for child in get_children():
		if child.get_script() == manager_class:
			return child
	
	# Create new
	var new_manager = manager_class.new()
	new_manager.name = node_name
	add_child(new_manager)
	return new_manager


# --- Flow Control ---

func start_hole() -> void:
	"""Begin a new hole"""
	mulligan_used_this_hole = false
	
	if tempo_manager:
		tempo_manager.reset_for_hole()
	if scoring_manager:
		scoring_manager.reset_for_hole()
	if hex_grid:
		hex_grid.reset_coin_magnet_radius()
	
	_set_state(FlowState.CHOOSING_HEX)


func on_hex_selected(hex_pos: Vector2i) -> void:
	"""Called when player selects a target hex"""
	if current_state != FlowState.CHOOSING_HEX:
		return
	
	selected_hex = hex_pos
	_set_state(FlowState.CHOOSING_SWING_CARD)


func on_swing_card_selected(card: CardInstance) -> void:
	"""Called when player selects a swing card"""
	if current_state != FlowState.CHOOSING_SWING_CARD:
		return
	
	# Check tempo cost
	var tempo_cost = card.card_data.tempo_cost if card.card_data else 1
	
	if tempo_manager and not tempo_manager.can_afford(tempo_cost):
		print("[GameFlowManager] Cannot afford card (cost %d, have %d)" % [tempo_cost, tempo_manager.get_current_tempo()])
		return
	
	# Spend tempo
	if tempo_manager:
		tempo_manager.spend_tempo(tempo_cost)
	
	selected_swing_card = card
	swing_card_played.emit(card, tempo_cost)
	
	# Automatically flip modifier
	_flip_modifier()


func _flip_modifier() -> void:
	"""Flip a modifier card from the deck"""
	_set_state(FlowState.FLIPPING_MODIFIER)
	
	if modifier_deck_manager and modifier_deck_manager.has_method("draw_card"):
		drawn_modifier = modifier_deck_manager.draw_card()
		modifier_flipped.emit(drawn_modifier)
	else:
		# No modifier deck - create neutral
		drawn_modifier = ModifierCardData.new()
		modifier_flipped.emit(drawn_modifier)
	
	# Move to item selection (or skip if no items)
	_set_state(FlowState.CHOOSING_ITEM)


func use_mulligan() -> bool:
	"""Use mulligan item to redraw modifier"""
	if mulligan_used_this_hole:
		print("[GameFlowManager] Mulligan already used this hole")
		return false
	
	if not item_manager or not item_manager.has_item(ItemData.ItemType.MULLIGAN):
		print("[GameFlowManager] No mulligan item available")
		return false
	
	# Use the mulligan item
	var mulligan_item = item_manager.get_item_by_type(ItemData.ItemType.MULLIGAN)
	if mulligan_item:
		item_manager.queue_item_for_shot(mulligan_item)
		item_manager.use_queued_item()
		mulligan_used_this_hole = true
		
		# Redraw modifier
		if modifier_deck_manager and modifier_deck_manager.has_method("draw_card"):
			drawn_modifier = modifier_deck_manager.draw_card()
			modifier_flipped.emit(drawn_modifier)
			print("[GameFlowManager] Mulligan used - new modifier: %s" % drawn_modifier.card_name)
			return true
	
	return false


func on_item_selected(item: ItemData) -> void:
	"""Called when player selects an item (optional)"""
	if current_state != FlowState.CHOOSING_ITEM:
		return
	
	selected_item = item
	
	if item and item_manager:
		item_manager.queue_item_for_shot(item)
		
		# Apply item effects (like coin magnet radius)
		_apply_item_pre_effects(item)
		
		if scoring_manager:
			scoring_manager.set_item_used()
		
		item_activated.emit(item)
	
	_set_state(FlowState.READY_TO_SWING)
	shot_ready.emit()


func skip_item_selection() -> void:
	"""Skip item selection and proceed to swing"""
	if current_state != FlowState.CHOOSING_ITEM:
		return
	
	selected_item = null
	_set_state(FlowState.READY_TO_SWING)
	shot_ready.emit()


func _apply_item_pre_effects(item: ItemData) -> void:
	"""Apply item effects before shot resolution"""
	match item.item_type:
		ItemData.ItemType.COIN_MAGNET:
			if hex_grid:
				hex_grid.set_coin_magnet_radius(item.magnet_radius)
		ItemData.ItemType.LUCKY_BALL:
			# Convert negative modifier to neutral
			if drawn_modifier and (drawn_modifier.distance_modifier < 0 or drawn_modifier.is_whiff):
				drawn_modifier.distance_modifier = 0
				drawn_modifier.is_whiff = false
				drawn_modifier.card_name = "Neutral (Lucky!)"
		# Other item effects handled during shot resolution


func confirm_shot() -> Dictionary:
	"""Get the combined shot modifiers from swing card + modifier + item"""
	var modifiers = {
		"curve": 0,
		"distance_mod": 0,
		"is_perfect": false,
		"is_whiff": false,
		"ignore_water": false,
		"ignore_sand": false,
		"ignore_wind": false,
		"accuracy_shape": "ring",  # Default
	}
	
	# Apply swing card modifiers
	if selected_swing_card and selected_swing_card.card_data:
		var card = selected_swing_card.card_data
		modifiers["curve"] = card.get_curve_amount()
		modifiers["accuracy_shape"] = _get_accuracy_shape_string(card.accuracy_shape)
	
	# Apply modifier card
	if drawn_modifier:
		modifiers["distance_mod"] += drawn_modifier.distance_modifier
		modifiers["curve"] += drawn_modifier.curve_modifier
		modifiers["is_perfect"] = drawn_modifier.is_perfect_accuracy
		modifiers["is_whiff"] = drawn_modifier.is_whiff
	
	# Apply item modifiers
	if selected_item:
		match selected_item.item_type:
			ItemData.ItemType.IGNORE_WATER:
				modifiers["ignore_water"] = true
			ItemData.ItemType.IGNORE_SAND:
				modifiers["ignore_sand"] = true
			ItemData.ItemType.IGNORE_WIND:
				modifiers["ignore_wind"] = true
			ItemData.ItemType.POWER_TEE:
				modifiers["distance_mod"] += selected_item.effect_value
	
	_set_state(FlowState.ANIMATING)
	return modifiers


func _get_accuracy_shape_string(shape: CardData.AccuracyShape) -> String:
	match shape:
		CardData.AccuracyShape.SINGLE: return "single"
		CardData.AccuracyShape.HORIZONTAL_LINE: return "horizontal_line"
		CardData.AccuracyShape.VERTICAL_LINE: return "vertical_line"
		CardData.AccuracyShape.RING: return "ring"
		_: return "ring"


func on_shot_complete(landing_surface: int, collected_coins: int) -> void:
	"""Called when shot animation completes"""
	# Award coins
	if collected_coins > 0 and currency_manager:
		currency_manager.add_chips(collected_coins, "Coins collected")
		if scoring_manager:
			scoring_manager.set_coin_collected()
	
	# Calculate landing points
	if scoring_manager:
		var points_breakdown = scoring_manager.calculate_landing_points(landing_surface)
		print("[GameFlowManager] Landing points: %d" % points_breakdown["final_points"])
	
	# Consume queued item
	if item_manager:
		item_manager.use_queued_item()
	
	# Advance tempo for next shot
	if tempo_manager:
		tempo_manager.advance_shot()
	
	# Reset per-shot state
	if scoring_manager:
		scoring_manager.reset_for_shot()
	
	# Reset for next shot
	_reset_shot_state()
	_set_state(FlowState.CHOOSING_HEX)


func on_hole_complete(strokes: int, par: int) -> Dictionary:
	"""Called when hole is finished"""
	_set_state(FlowState.HOLE_COMPLETE)
	
	var result = {}
	if scoring_manager:
		result = scoring_manager.calculate_hole_bonus(strokes, par)
	
	return result


func enter_shop() -> void:
	"""Enter the shop phase between holes"""
	_set_state(FlowState.IN_SHOP)
	if shop_manager:
		shop_manager.open_shop()


func exit_shop() -> void:
	"""Exit shop and proceed to next hole"""
	if shop_manager:
		shop_manager.close_shop()
	
	_set_state(FlowState.IDLE)


func cancel_shot() -> void:
	"""Cancel current shot and reset"""
	if current_state == FlowState.ANIMATING:
		return  # Can't cancel during animation
	
	# Refund tempo if swing card was selected
	if selected_swing_card and tempo_manager:
		var cost = selected_swing_card.card_data.tempo_cost if selected_swing_card.card_data else 1
		tempo_manager.refund_tempo(cost)
	
	_reset_shot_state()
	_set_state(FlowState.CHOOSING_HEX)
	shot_cancelled.emit()


func _reset_shot_state() -> void:
	"""Reset per-shot state"""
	selected_hex = Vector2i(-1, -1)
	selected_swing_card = null
	drawn_modifier = null
	selected_item = null
	
	if item_manager:
		item_manager.clear_queued_item()
	
	if hex_grid:
		hex_grid.reset_coin_magnet_radius()


func _set_state(new_state: FlowState) -> void:
	"""Change flow state and emit signal"""
	if current_state != new_state:
		current_state = new_state
		flow_state_changed.emit(current_state)
		print("[GameFlowManager] State changed to: %s" % FlowState.keys()[current_state])


func get_current_state() -> FlowState:
	return current_state


func get_state_name() -> String:
	return FlowState.keys()[current_state]
