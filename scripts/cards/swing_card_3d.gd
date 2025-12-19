class_name SwingCard3D
extends Card3D
## Custom 3D card for swing/shot cards
## Extends Card3D from the addon with textures and dynamic text

var card_instance: CardInstance = null:
	set(value):
		card_instance = value
		_update_visuals()

@export var tempo_value: int = 1:
	set(value):
		tempo_value = value
		_update_tempo_label()

# Path to card front texture
@export var front_texture_path: String:
	set(path):
		front_texture_path = path
		_apply_front_texture()


func _apply_front_texture() -> void:
	"""Apply the front texture to the card mesh"""
	if not front_texture_path or not is_inside_tree():
		return
	if not has_node("CardMesh/CardFrontMesh"):
		return
	
	var texture = load(front_texture_path)
	if texture:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = texture
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show both sides
		$CardMesh/CardFrontMesh.set_surface_override_material(0, mat)


func _ready() -> void:
	# Ensure we call _setup_visuals after the scene tree is ready
	call_deferred("_setup_visuals")
	call_deferred("_update_visuals")


func _setup_visuals() -> void:
	"""Set up the default textures and create the tempo label"""
	# Apply front texture
	front_texture_path = "res://textures/Swing Card.png"
	_apply_front_texture()
	
	# Set back texture (darker version)
	var back_mat = StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.2, 0.3, 0.5)
	if has_node("CardMesh/CardBackMesh"):
		$CardMesh/CardBackMesh.set_surface_override_material(0, back_mat)
	
	# The TempoLabel is already defined in the scene, just update it
	_update_tempo_label()


func _update_visuals() -> void:
	"""Update card visuals from card_instance data"""
	if not card_instance or not is_inside_tree():
		return
	
	# Update tempo from card data
	if card_instance.data:
		tempo_value = card_instance.data.tempo_cost


func _update_tempo_label() -> void:
	"""Update the tempo label text"""
	if has_node("CardMesh/TempoLabel"):
		$CardMesh/TempoLabel.text = str(tempo_value)


func set_card_data(instance: CardInstance) -> void:
	"""Set the card instance and update visuals"""
	card_instance = instance
