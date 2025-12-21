class_name ModifierCard3D
extends Card3D
## Custom 3D card for modifier cards
## Extends Card3D from the addon with ability to flip and show modifier data

var card_instance: CardInstance = null:
	set(value):
		card_instance = value
		_update_visuals()

@export var front_texture_path: String = "res://textures/cards/modifier-deck-neutral.png":
	set(path):
		front_texture_path = path
		if is_inside_tree():
			_apply_front_texture()

@export var back_texture_path: String = "res://textures/Modifier Card Back.png":
	set(path):
		back_texture_path = path
		if is_inside_tree():
			_apply_back_texture()


func _ready() -> void:
	# Start face down
	face_down = true
	call_deferred("_setup_visuals")
	call_deferred("_update_visuals")


func _setup_visuals() -> void:
	"""Set up the card textures and configure labels/icons for proper depth testing"""
	_apply_front_texture()
	_apply_back_texture()
	
	# Configure labels for proper depth testing (same as swing cards)
	if has_node("CardMesh/TopLabel"):
		$CardMesh/TopLabel.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	
	if has_node("CardMesh/BottomLabel"):
		$CardMesh/BottomLabel.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	
	# Configure icons for proper depth testing
	if has_node("CardMesh/Icon1"):
		$CardMesh/Icon1.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	
	if has_node("CardMesh/Icon2"):
		$CardMesh/Icon2.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	
	if has_node("CardMesh/Icon3"):
		$CardMesh/Icon3.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS


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
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		$CardMesh/CardFrontMesh.set_surface_override_material(0, mat)


func _apply_back_texture() -> void:
	"""Apply the back texture to the card mesh"""
	if not back_texture_path or not is_inside_tree():
		return
	if not has_node("CardMesh/CardBackMesh"):
		return
	
	var texture = load(back_texture_path)
	if texture:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = texture
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		$CardMesh/CardBackMesh.set_surface_override_material(0, mat)


func _update_visuals() -> void:
	"""Update card visuals from card_instance data"""
	if not card_instance or not is_inside_tree():
		return
	
	var card_data = card_instance.data
	
	# Update front texture based on card type
	match card_data.card_type:
		CardData.CardType.NEGATIVE:
			front_texture_path = "res://textures/cards/modifier-deck-negative.png"
		CardData.CardType.POSITIVE:
			front_texture_path = "res://textures/cards/modifier-deck-positive.png"
		CardData.CardType.NEUTRAL:
			front_texture_path = "res://textures/cards/modifier-deck-neutral.png"
		_:  # SHOT or any other
			front_texture_path = "res://textures/cards/modifier-deck-neutral.png"
	_apply_front_texture()
	
	# Update top label - Description
	if has_node("CardMesh/TopLabel"):
		$CardMesh/TopLabel.text = card_data.description if card_data.description else ""
	
	# Update bottom label - Flavor Text
	if has_node("CardMesh/BottomLabel"):
		$CardMesh/BottomLabel.text = card_data.flavor_text if card_data.flavor_text else ""
	
	# Update icons from card data
	if has_node("CardMesh/Icon1"):
		if card_data.modifier_icon_1:
			$CardMesh/Icon1.texture = card_data.modifier_icon_1
			$CardMesh/Icon1.visible = true
		else:
			$CardMesh/Icon1.visible = false
	
	if has_node("CardMesh/Icon2"):
		if card_data.modifier_icon_2:
			$CardMesh/Icon2.texture = card_data.modifier_icon_2
			$CardMesh/Icon2.visible = true
		else:
			$CardMesh/Icon2.visible = false
	
	if has_node("CardMesh/Icon3"):
		if card_data.modifier_icon_3:
			$CardMesh/Icon3.texture = card_data.modifier_icon_3
			$CardMesh/Icon3.visible = true
		else:
			$CardMesh/Icon3.visible = false


func set_card_data(instance: CardInstance) -> void:
	"""Set the card instance data"""
	card_instance = instance


func flip_face_up() -> void:
	"""Flip the card to show the front"""
	face_down = false


func flip_face_down() -> void:
	"""Flip the card to show the back"""
	face_down = true
