extends Control
class_name ShotPanel

## Container for the shot controls: Swing Card Slot, Modifier Deck, and Spin Meter.
## This panel is designed to be edited visually in the Godot editor.

signal swing_card_played(card_instance: CardInstance)
signal modifier_card_drawn(card_instance: CardInstance)
signal spin_changed(top_spin: float, back_spin: float)

# Node references (editor-assigned via scene)
@onready var swing_card_slot: SwingCardSlot = $HBoxContainer/SwingCardSlot
@onready var modifier_deck: DeckWidget = $HBoxContainer/ModifierDeck
@onready var top_spin_slider: VSlider = $HBoxContainer/SpinMeterContainer/TopSpinSlider
@onready var back_spin_slider: VSlider = $HBoxContainer/SpinMeterContainer/BackSpinSlider


func _ready() -> void:
	# Connect swing card slot
	if swing_card_slot:
		swing_card_slot.card_dropped.connect(_on_swing_card_dropped)
		swing_card_slot.card_removed.connect(_on_swing_card_removed)
	
	# Connect spin sliders
	if top_spin_slider:
		top_spin_slider.value_changed.connect(_on_spin_changed)
	if back_spin_slider:
		back_spin_slider.value_changed.connect(_on_spin_changed)


func _on_swing_card_dropped(card_instance: CardInstance) -> void:
	swing_card_played.emit(card_instance)


func _on_swing_card_removed() -> void:
	# Handle card being removed from slot
	pass


func _on_spin_changed(_value: float) -> void:
	var top = top_spin_slider.value if top_spin_slider else 0.0
	var back = back_spin_slider.value if back_spin_slider else 0.0
	spin_changed.emit(top, back)


func get_swing_card() -> CardInstance:
	"""Get the currently played swing card"""
	if swing_card_slot:
		return swing_card_slot.get_card_instance()
	return null


func has_swing_card() -> bool:
	"""Check if a swing card has been played"""
	if swing_card_slot:
		return swing_card_slot.has_card()
	return false


func get_spin() -> Vector2:
	"""Get current spin values as Vector2(top_spin, back_spin)"""
	var top = top_spin_slider.value if top_spin_slider else 0.0
	var back = back_spin_slider.value if back_spin_slider else 0.0
	return Vector2(top, back)


func reset() -> void:
	"""Reset the panel for a new shot"""
	if swing_card_slot:
		swing_card_slot.remove_card()
	if top_spin_slider:
		top_spin_slider.value = 0.0
	if back_spin_slider:
		back_spin_slider.value = 0.0


func setup_modifier_deck(deck_manager: DeckManager) -> void:
	"""Setup the modifier deck with a deck manager"""
	if modifier_deck:
		modifier_deck.setup(deck_manager)
