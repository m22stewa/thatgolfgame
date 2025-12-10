extends SubViewportContainer
class_name LieView

## LieView - Displays the current ball lie with a 3D preview
## Shows the ball model sitting on the current terrain tile type
##
## SCENE STRUCTURE (edit in editor):
## - LieView (this script)
##   - LieLabel (Label) - displays lie name
##   - SubViewport
##     - WorldEnvironment - edit lighting/environment here
##     - Camera3D - adjust camera position/angle/FOV here
##     - DirectionalLight3D - adjust lighting here
##     - TileRoot (Node3D) - rotates, contains all 3D content
##       - TileGround (MeshInstance3D) - the brown ground base
##       - TileSurface (MeshInstance3D) - the colored surface (fairway, rough, etc.)
##         * Add materials/shaders here via material_override
##       - BallModel - the golf ball instance
##       - Decorations (Node3D) - container for lie-specific decorations
##         - DeepRoughGrass - add grass models here, script toggles visibility
##         - RoughGrass - add grass models here
##         - SandDetail - add sand ripples/rocks here
##         - WaterEffect - add water effects here
##         - GreenDetail - add putting green details here
##
## HOW TO ADD SHADERS/MATERIALS:
## 1. Select TileSurface in the scene tree
## 2. In Inspector, expand "Geometry" or find "Material Override"
## 3. Create a new ShaderMaterial or StandardMaterial3D
## 4. The script will preserve your material when swapping meshes
##
## HOW TO ADD DECORATIONS:
## 1. Find the appropriate decoration node (e.g., DeepRoughGrass)
## 2. Add child nodes (MeshInstance3D, imported GLB models, etc.)
## 3. Position them around where the ball will be (center of tile)
## 4. The script will show/hide the correct decoration group per lie

# Surface mesh paths - the script loads these and swaps the mesh
const SURFACE_MESHES = {
	"TEE": "res://scenes/tiles/teebox-mesh.tres",
	"TEEBOX": "res://scenes/tiles/teebox-mesh.tres",
	"FAIRWAY": "res://scenes/tiles/fairway-mesh.tres",
	"ROUGH": "res://scenes/tiles/rough-mesh.tres",
	"DEEP_ROUGH": "res://scenes/tiles/deeprough-mesh.tres",
	"SAND": "res://scenes/tiles/sand-mesh.tres",
	"GREEN": "res://scenes/tiles/green-mesh.tres",
	"WATER": "res://scenes/tiles/water-mesh.tres",
}

# Map lie types to decoration node names
const LIE_DECORATIONS = {
	"DEEP_ROUGH": "DeepRoughGrass",
	"ROUGH": "RoughGrass",
	"SAND": "SandDetail",
	"WATER": "WaterEffect",
	"GREEN": "GreenDetail",
}

# Current state
var current_lie: String = "TEEBOX"

# Node references - use %NodeName for unique names set in scene
@onready var viewport: SubViewport = %SubViewport
@onready var camera: Camera3D = %Camera3D
@onready var light: DirectionalLight3D = %DirectionalLight3D
@onready var tile_root: Node3D = %TileRoot
@onready var tile_surface: MeshInstance3D = %TileSurface
@onready var tile_ground: MeshInstance3D = %TileGround
@onready var ball_model: Node3D = %BallModel
@onready var decorations: Node3D = %Decorations
@onready var lie_label: Label = %LieLabel

# Cached meshes
var _mesh_cache: Dictionary = {}

# Stored material from scene (preserved when swapping meshes)
var _surface_material: Material = null

# Animation settings - exposed for editor tweaking
@export_group("Animation")
@export var auto_rotate: bool = true
@export var rotation_speed: float = 0.4

@export_group("Ball Position Per Lie")
@export var ball_height_tee: float = 0.6
@export var ball_height_fairway: float = 0.5
@export var ball_height_green: float = 0.48
@export var ball_height_rough: float = 0.45
@export var ball_height_deep_rough: float = 0.4
@export var ball_height_sand: float = 0.42
@export var ball_height_water: float = 0.35


func _ready() -> void:
	# Store the material set in the editor so we can reapply it after mesh swaps
	if tile_surface and tile_surface.material_override:
		_surface_material = tile_surface.material_override
	
	# Set initial lie
	set_lie("TEEBOX")


func _process(delta: float) -> void:
	if auto_rotate and tile_root:
		tile_root.rotate_y(rotation_speed * delta)


func set_lie(lie_type: String, _lie_info: Dictionary = {}) -> void:
	"""Set the current lie type and update visuals"""
	# Normalize lie name
	var normalized = lie_type.to_upper().replace(" ", "_")
	if normalized == "TEE":
		normalized = "TEEBOX"
	
	current_lie = normalized
	
	_update_surface_mesh()
	_update_decorations()
	_update_ball_position()
	_update_label()


func _update_surface_mesh() -> void:
	"""Load and apply the surface mesh for current lie"""
	if not tile_surface:
		return
	
	var mesh_path = SURFACE_MESHES.get(current_lie, SURFACE_MESHES["FAIRWAY"])
	
	# Load mesh if not cached
	if not _mesh_cache.has(mesh_path):
		if ResourceLoader.exists(mesh_path):
			_mesh_cache[mesh_path] = load(mesh_path)
	
	# Apply mesh
	if _mesh_cache.has(mesh_path):
		tile_surface.mesh = _mesh_cache[mesh_path]
	
	# Reapply the material from the editor (mesh swap clears it)
	if _surface_material:
		tile_surface.material_override = _surface_material


func _update_decorations() -> void:
	"""Show/hide decoration groups based on current lie"""
	if not decorations:
		return
	
	# Hide all decoration groups first
	for child in decorations.get_children():
		child.visible = false
	
	# Show the decoration group for current lie (if it exists)
	var deco_name = LIE_DECORATIONS.get(current_lie, "")
	if deco_name != "":
		var deco_node = decorations.get_node_or_null(deco_name)
		if deco_node:
			deco_node.visible = true


func _update_ball_position() -> void:
	"""Position ball appropriately for the lie type"""
	if not ball_model:
		return
	
	# Get height based on lie type (uses exported values for easy tweaking)
	var height = ball_height_fairway
	match current_lie:
		"TEEBOX", "TEE":
			height = ball_height_tee
		"FAIRWAY":
			height = ball_height_fairway
		"GREEN":
			height = ball_height_green
		"ROUGH":
			height = ball_height_rough
		"DEEP_ROUGH":
			height = ball_height_deep_rough
		"SAND":
			height = ball_height_sand
		"WATER":
			height = ball_height_water
	
	ball_model.position.y = height


func _update_label() -> void:
	"""Update the lie label text and color"""
	if not lie_label:
		return
	
	lie_label.text = _get_display_name(current_lie)
	lie_label.add_theme_color_override("font_color", _get_lie_color(current_lie))


func _get_display_name(lie: String) -> String:
	"""Convert lie type to display name"""
	match lie:
		"TEEBOX", "TEE": return "Tee Box"
		"FAIRWAY": return "Fairway"
		"ROUGH": return "Rough"
		"DEEP_ROUGH": return "Deep Rough"
		"SAND": return "Bunker"
		"GREEN": return "Green"
		"WATER": return "Water"
		"FRINGE": return "Fringe"
		_: return lie.capitalize().replace("_", " ")


func _get_lie_color(lie: String) -> Color:
	"""Get color for lie quality indication"""
	match lie:
		"TEEBOX", "TEE": return Color(1.0, 1.0, 1.0)
		"FAIRWAY": return Color(0.5, 1.0, 0.5)
		"GREEN": return Color(0.3, 0.95, 0.3)
		"FRINGE": return Color(0.6, 0.9, 0.5)
		"ROUGH": return Color(1.0, 0.9, 0.4)
		"DEEP_ROUGH": return Color(1.0, 0.6, 0.3)
		"SAND": return Color(1.0, 0.85, 0.55)
		"WATER": return Color(0.4, 0.65, 1.0)
		_: return Color(0.85, 0.85, 0.85)


# --- Public API ---

func set_tile_rotation(angle: float) -> void:
	"""Set the tile rotation manually"""
	if tile_root:
		tile_root.rotation.y = angle


func get_tile_rotation() -> float:
	"""Get current tile rotation"""
	if tile_root:
		return tile_root.rotation.y
	return 0.0


func reset_rotation() -> void:
	"""Reset rotation to default"""
	if tile_root:
		tile_root.rotation.y = 0.0


func set_surface_material(mat: Material) -> void:
	"""Set a custom material on the tile surface (also updates stored material)"""
	_surface_material = mat
	if tile_surface:
		tile_surface.material_override = mat


func get_surface_material() -> Material:
	"""Get the current surface material"""
	return _surface_material
