extends Resource
class_name HoleDefinition

## HoleDefinition - Seedable, authored definition of a single hole.
## Drives procedural generation (or fixed overrides) and the hand dealt on it.

@export var hole_id: String = ""
@export var seed: int = 0
@export var par: int = 4
@export var use_procedural: bool = true
@export var grid_width: int = 10
@export var grid_height: int = 40
@export var tee: Vector2i = Vector2i.ZERO
@export var flag: Vector2i = Vector2i.ZERO
@export var surface_overrides: Dictionary = {}
@export var elevation_overrides: Dictionary = {}
@export var wind_fixed: bool = false
@export var wind_direction_index: int = 0
@export var wind_strength: int = 0
@export var hand_definition: HandDefinition = null
