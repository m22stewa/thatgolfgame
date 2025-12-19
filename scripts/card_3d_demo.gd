extends Node3D

## Card3D Demo
## Demonstrates basic usage of the Card3D addon

const Card3DScene = preload("res://addons/card_3d/scenes/card_3d.tscn")

@onready var player_hand: CardCollection3D = $DragController/PlayerHand
@onready var play_area: CardCollection3D = $DragController/PlayArea
@onready var drag_controller = $DragController


func _ready() -> void:
	# Set up the player hand with a fan layout
	var fan_layout = FanCardLayout.new()
	fan_layout.arc_angle_deg = 60.0
	fan_layout.arc_radius = 10.0
	player_hand.card_layout_strategy = fan_layout
	fan_layout.arc_radius = 10.0
	player_hand.card_layout_strategy = fan_layout
	
	# Set up the play area with a line layout
	var line_layout = LineCardLayout.new()
	line_layout.max_width = 15.0
	line_layout.padding = 0.5
	play_area.card_layout_strategy = line_layout
	
	# Add some test cards to the player's hand
	_create_test_cards()
	
	# Connect signals
	player_hand.card_clicked.connect(_on_card_clicked)
	play_area.card_clicked.connect(_on_card_clicked)
	drag_controller.card_moved.connect(_on_card_moved)


func _create_test_cards() -> void:
	"""Create some test cards for demonstration"""
	for i in range(5):
		var card = Card3DScene.instantiate()
		card.name = "Card" + str(i + 1)
		
		# You can customize the card appearance here
		# For now, just add it to the hand
		player_hand.append_card(card)


func _on_card_clicked(card: Card3D) -> void:
	print("Card clicked: ", card.name)


func _on_card_moved(card: Card3D, from_collection: CardCollection3D, to_collection: CardCollection3D, from_index: int, to_index: int) -> void:
	print("Card moved: ", card.name, " from ", from_collection.name, "[", from_index, "] to ", to_collection.name, "[", to_index, "]")
