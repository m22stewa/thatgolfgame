extends Control
class_name DeckUI

## DeckUI - Visual interface for the deck and active card slot.
## Replaces the old HandUI.

# References
var deck_manager: DeckManager = null
var card_ui_scene: PackedScene = null

# UI Elements - Now connected via scene
@onready var deck_button: TextureButton = $DeckContainer/DeckWrapper/DeckButton
@onready var active_slot: TextureRect = $DeckContainer/SlotWrapper/ActiveSlot
@onready var active_card_container: Control = $DeckContainer/SlotWrapper/ActiveSlot/ActiveCardContainer
@onready var deck_count_label: Label = $DeckContainer/DeckWrapper/DeckButton/DeckCount

# Assets
const CARD_UI_PATH = "res://scenes/ui/card_ui.tscn"
const CARD_BACK_TEXTURE = preload("res://textures/cardback.png")

func _ready() -> void:
	# Load card scene
	if ResourceLoader.exists(CARD_UI_PATH):
		card_ui_scene = load(CARD_UI_PATH)
	
	# Connect button signal
	if deck_button:
		deck_button.pressed.connect(_on_deck_clicked)
		# Reset rotation (inherit from container)
		deck_button.rotation = 0
		deck_button.pivot_offset = deck_button.size / 2
		# Set texture
		deck_button.texture_normal = CARD_BACK_TEXTURE
	
	if active_slot:
		active_slot.rotation = 0
		active_slot.pivot_offset = active_slot.size / 2
		
	if deck_count_label:
		# Counter-rotate label so it's upright (Container is -90, so we need +90)
		deck_count_label.rotation_degrees = 90
		deck_count_label.pivot_offset = deck_count_label.size / 2


func setup(manager: DeckManager) -> void:
	deck_manager = manager
	
	# Connect signals
	if deck_manager:
		deck_manager.active_cards_changed.connect(_on_active_cards_changed)
		deck_manager.deck_shuffled.connect(_update_deck_visuals)
		deck_manager.card_drawn.connect(_on_card_drawn)
		
		# Initial update
		_update_deck_visuals()
		# Don't show active cards immediately on setup if we want to animate them later
		# But for reload/init, we should.
		if not deck_manager.get_active_cards().is_empty():
			_on_active_cards_changed(deck_manager.get_active_cards())


func _on_deck_clicked() -> void:
	if deck_manager:
		deck_manager.draw_and_activate()


func _update_deck_visuals() -> void:
	if deck_manager and deck_count_label:
		var count = deck_manager.get_draw_pile_size()
		deck_count_label.text = str(count)
		
		# Disable button if empty
		if deck_button:
			deck_button.disabled = count == 0
			deck_button.modulate = Color(0.5, 0.5, 0.5) if count == 0 else Color.WHITE


func _on_active_cards_changed(cards: Array[CardInstance]) -> void:
	# This is called when the active list changes.
	# If it was a draw, _on_card_drawn handles the animation.
	# This is mostly for cleanup or initial load.
	pass


func _on_card_drawn(card: CardInstance) -> void:
	_update_deck_visuals()
	_animate_card_draw(card)


func _animate_card_draw(card: CardInstance) -> void:
	if not deck_button or not active_slot:
		return
		
	# Create a temporary flying card
	var flying_card = TextureRect.new()
	flying_card.texture = CARD_BACK_TEXTURE
	flying_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flying_card.size = deck_button.size
	flying_card.pivot_offset = deck_button.size / 2
	
	# Match global rotation of deck button
	# Control nodes use 'rotation' which is relative to parent.
	# To get global rotation, we sum up rotations of parents or use transform.
	# But for simple UI, just using 'rotation' + parent's rotation is usually enough.
	# Or better, just set rotation to match the visual look we know (-90).
	flying_card.rotation = deck_button.get_global_transform().get_rotation()
	
	flying_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Add to the root of this control so it flies over everything
	add_child(flying_card)
	
	# Set initial position to match deck button exactly
	flying_card.global_position = deck_button.global_position
	
	# Tween it
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Move to slot
	tween.tween_property(flying_card, "global_position", active_slot.global_position, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	# Grow by 20% initially (Scale 1.0 -> 1.2)
	tween.tween_property(flying_card, "scale", Vector2(1.2, 1.2), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Flip animation sequence
	var flip_tween = create_tween()
	# Wait a bit before flipping
	flip_tween.tween_interval(0.25)
	
	# Parallel flip: 
	# Since we are rotated -90 (Landscape), Local Y is the "Width" visually.
	# Scale Y -> 0 to flip like a page.
	# Scale X -> 1.125 (Final size matching deck)
	flip_tween.set_parallel(true)
	flip_tween.tween_property(flying_card, "scale:y", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flip_tween.tween_property(flying_card, "scale:x", 1.125, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	flip_tween.chain().tween_callback(func(): 
		# Mid-flip: Change texture or just hide and show the real card
		flying_card.visible = false
		_show_active_card(card)
	)
	
	# Cleanup
	tween.chain().tween_callback(flying_card.queue_free)


func _show_active_card(card: CardInstance) -> void:
	if not active_card_container:
		return
		
	# Clear current visuals
	for child in active_card_container.get_children():
		child.queue_free()
	
	_create_card_visual(card)


func _create_card_visual(card: CardInstance) -> void:
	if not card_ui_scene:
		return
		
	var card_ui = card_ui_scene.instantiate()
	active_card_container.add_child(card_ui)
	
	# Setup card UI
	if card_ui.has_method("setup"):
		card_ui.setup(card)
	
	# Position it
	# Slot is 180x270 (Portrait), Card is 160x240 (Portrait)
	# ActiveSlot is rotated -90 deg.
	
	# Scale to match deck size (180x270)
	# 180 / 160 = 1.125
	var desired_scale = Vector2(1.125, 1.125)
	card_ui.scale = desired_scale
	
	# IMPORTANT: CardUI constantly lerps to 'target_scale' in its _process loop.
	# We must set target_scale to prevent it from shrinking back to 1.0.
	if "target_scale" in card_ui:
		card_ui.target_scale = desired_scale
	
	# Disable playability/hover effects
	if "is_playable" in card_ui:
		card_ui.is_playable = false
	
	# Disable mouse interaction entirely so it doesn't capture clicks/hovers
	card_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Center in local space of ActiveSlot (which is 180x270)
	# Card pivot is center (80, 120)
	# Slot center is (90, 135)
	card_ui.position = Vector2(90, 135) - (Vector2(80, 120) * desired_scale.x)
