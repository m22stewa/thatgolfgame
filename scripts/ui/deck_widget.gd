extends SubViewportContainer
class_name DeckWidget

## DeckWidget - A self-contained UI widget that displays a 3D deck.
## Wraps the SubViewport and DeckView3D complexity.

enum DeckType { MODIFIERS, CLUBS }

@export_group("Deck Configuration")
@export var deck_type: DeckType = DeckType.MODIFIERS
@export var card_back_texture: Texture2D
@export var card_front_texture: Texture2D
@export var deck_size: Vector3 = Vector3(4.0, 2.02, 0.5)
@export var interaction_mode: DeckView3D.InteractionMode = DeckView3D.InteractionMode.DRAW_TOP

# Internal references
var deck_view: DeckView3D = null

func _ready() -> void:
	# Find the internal DeckView3D
	deck_view = get_node_or_null("SubViewport/DeckView3D")
	if deck_view:
		_apply_config()

func _apply_config() -> void:
	if not deck_view: return
	
	if card_back_texture:
		deck_view.card_back_texture = card_back_texture
	if card_front_texture:
		deck_view.card_front_texture = card_front_texture
	
	deck_view.deck_size = deck_size
	deck_view.interaction_mode = interaction_mode
	
	# Trigger mesh rebuild if needed
	if deck_view.is_inside_tree():
		deck_view._setup_deck_mesh()

func setup(manager: DeckManager) -> void:
	if deck_view:
		deck_view.setup(manager)

func get_deck_view() -> DeckView3D:
	return deck_view
