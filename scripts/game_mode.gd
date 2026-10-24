extends RefCounted
class_name GameMode

## GameMode - Which game the title screen started. Static, so it survives the
## scene change into GOLF.tscn.
##   driving_range = false: the run (holes, Pro Shop, scoring)
##   driving_range = true:  one long practice hole with every card and club,
##                          where obstacles can be painted on to test shots

const TITLE_SCENE := "res://scenes/title_screen.tscn"
const GAME_SCENE := "res://scenes/GOLF.tscn"
const LOADING_TEXT := "Teeing up..."  # the loading screen, and the game's opening cover
const LOADING_BG := Color(0, 0.0667, 0.0627)  # the screen transition's cover colour

static var driving_range := false


static func start(tree: SceneTree, range_mode: bool) -> void:
	driving_range = range_mode
	tree.change_scene_to_file(GAME_SCENE)


static func start_loaded(tree: SceneTree, range_mode: bool, scene: PackedScene) -> void:
	"""start(), with the game scene already loaded (the title's loading screen)."""
	driving_range = range_mode
	tree.change_scene_to_packed(scene)


static func to_title(tree: SceneTree) -> void:
	driving_range = false
	tree.change_scene_to_file(TITLE_SCENE)
