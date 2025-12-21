extends Control
class_name ShotPanel

## Container for the shot controls: Modifier Deck and Spin Meter.
## Swing cards are now handled by SwingHand3D.

signal modifier_card_drawn(card_instance: CardInstance)
signal spin_changed(top_spin: float, back_spin: float)

# Node references (editor-assigned via scene)
@onready var modifier_deck: DeckWidget = $HBoxContainer/ModifierDeck
@onready var top_spin_slider: VSlider = $HBoxContainer/SpinMeterContainer/TopSpinSlider
@onready var back_spin_slider: VSlider = $HBoxContainer/SpinMeterContainer/BackSpinSlider


func _ready() -> void:
	# Connect spin sliders only
	
	if top_spin_slider:
		top_spin_slider.value_changed.connect(_on_spin_changed)
	if back_spin_slider:
		back_spin_slider.value_changed.connect(_on_spin_changed)


func _on_spin_changed(_value: float) -> void:
	var top = top_spin_slider.value if top_spin_slider else 0.0
	var back = back_spin_slider.value if back_spin_slider else 0.0
	spin_changed.emit(top, back)


func get_spin() -> Vector2:
	"""Get current spin values as Vector2(top_spin, back_spin)"""
	var top = top_spin_slider.value if top_spin_slider else 0.0
	var back = back_spin_slider.value if back_spin_slider else 0.0
	return Vector2(top, back)


func reset() -> void:
	"""Reset the panel for a new shot"""
	if top_spin_slider:
		top_spin_slider.value = 0.0
	if back_spin_slider:
		back_spin_slider.value = 0.0


func setup_modifier_deck(deck_manager: DeckManager) -> void:
	"""Setup the modifier deck with a deck manager"""
	if modifier_deck:
		modifier_deck.setup(deck_manager)
