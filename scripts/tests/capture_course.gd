# THROWAWAY art-pass capture harness (BEFORE baseline).
#
# Purpose: render reference screenshots of the CURRENT, unchanged course look so
# a later art pass can be judged against this baseline. This script does NOT
# change generation, hole layout, tile positions, materials, or the game camera
# framing used during play. It instances the real game scene (scenes/GOLF.tscn)
# unmodified, lets it generate + settle, then drives a SEPARATE capture camera
# that mimics the game's tilted top-down angle to frame three subjects.
#
# Run (windowed, so macOS produces real pixels):
#   /Applications/Godot.app/Contents/MacOS/Godot \
#     --path <worktree> scenes/tests/capture_course.tscn
#
# It quits itself when done. PNGs land in:
#   .agents/tasks/art-shots/before_*.png
extends Node3D

const GAME_SCENE: PackedScene = preload("res://scenes/GOLF.tscn")
const OUT_DIR := "res://.agents/tasks/art-shots"

# SurfaceType enum values mirrored from hex_grid.gd (do not change there).
const SURF_SAND := 5
const SURF_WATER := 6

var _game: Node3D = null
var _hex_grid: Node3D = null
var _cam: Camera3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run()


func _run() -> void:
	# 1. Instance the real game exactly as it ships and let it build the hole.
	_game = GAME_SCENE.instantiate()
	add_child(_game)

	# The main scene's own Camera3D is current=true; we render through our own
	# capture camera instead, but we add it into the game scene so it shares the
	# same World3D / WorldEnvironment (sky, fog, lighting).
	await _wait_frames(90)  # let _ready(), generation, transition + physics settle

	_hex_grid = _game.get_node_or_null("HoleGenerator/HexGrid")
	if _hex_grid == null:
		push_error("[capture] HexGrid not found; cannot frame shots")
		_quit_soon()
		return

	# Hide the 2D HUD / UI overlay and the opening screen-transition dissolve so
	# the baseline shots show the COURSE ART, not the gameplay HUD. This only
	# toggles visibility of UI Control nodes for the capture; it does NOT touch
	# any 3D art, materials, environment, generation, or layout.
	var ui_control := _game.get_node_or_null("Control")
	if ui_control is CanvasItem:
		(ui_control as CanvasItem).visible = false
	# A CanvasLayer draws independently of its parent Control's visibility, so
	# hide any CanvasLayer nodes (which host the screen-transition dissolve and
	# the "Generating new hole..." label) explicitly.
	if ui_control != null:
		for node in ui_control.find_children("*", "CanvasLayer", true, false):
			(node as CanvasLayer).visible = false

	# Our capture camera lives under the game scene root (shares the world).
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_game.add_child(_cam)
	_cam.make_current()
	await _wait_frames(2)

	# Holes are procedural: some generate with no trees. Re-roll the hole (using
	# the game's OWN regeneration path, exactly like the in-game "Generate New
	# Hole" button) until the board actually has trees, so all three baseline
	# shots come from one consistent, feature-rich hole. Generation logic itself
	# is untouched.
	await _ensure_tree_bearing_hole()

	# 2. Compute subject world positions from the generated board.
	var board := _board_bounds()
	var board_center: Vector3 = board["center"]
	var board_span: float = board["span"]

	var water_or_sand: Variant = _find_surface_world_pos([SURF_WATER, SURF_SAND])
	var tree_pos: Variant = _find_group_world_pos("trees")

	# 3a. Wide board shot: tee -> green along the long (z) axis, tilted top-down.
	_frame_wide(board_center, board_span)
	await _render_and_save("after_board_wide.png")

	# 3b. Bunker / water close-up.
	if water_or_sand != null:
		_frame_closeup(water_or_sand)
	else:
		push_warning("[capture] no sand/water tile found; using board center for bunker shot")
		_frame_closeup(board_center)
	await _render_and_save("after_bunker_water.png")

	# 3c. Trees shot.
	if tree_pos != null:
		_frame_trees(tree_pos)
	else:
		push_warning("[capture] no tree nodes found; using board center for trees shot")
		_frame_closeup(board_center)
	await _render_and_save("after_trees.png")

	_quit_soon()


# --- framing helpers ----------------------------------------------------

# Game camera uses a tilted (~48 deg) look-down-the-course angle. We reuse that
# pitch so the baseline reads like the in-game view, just repositioned/zoomed.
func _frame_wide(center: Vector3, span: float) -> void:
	var dist := maxf(span * 1.05, 18.0)
	# Pull back along -z (toward tee) and up, pitch down toward the board.
	var eye := center + Vector3(0.0, dist * 0.92, -dist * 0.95)
	_look_from(eye, center)


func _frame_closeup(target: Vector3) -> void:
	var dist := 7.5
	# Eye sits up and slightly back along -z; look straight at the subject so it
	# stays centered in frame.
	var eye := target + Vector3(0.0, dist * 0.80, -dist * 0.68)
	_look_from(eye, target + Vector3(0.0, 0.4, 0.0))


func _frame_trees(target: Vector3) -> void:
	# Trees are ~3-5 units tall; sit back + lower pitch and aim at mid-canopy so
	# foliage fills the frame rather than looking straight down onto treetops.
	var dist := 9.0
	var eye := target + Vector3(0.0, dist * 0.55, -dist * 0.85)
	_look_from(eye, target + Vector3(0.0, 1.8, 0.0))


func _look_from(eye: Vector3, target: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(target, Vector3.UP)


# --- board / subject discovery (read-only; no generation changes) -------

func _ensure_tree_bearing_hole() -> void:
	var attempts := 0
	while get_tree().get_nodes_in_group("trees").is_empty() and attempts < 12:
		attempts += 1
		if _hex_grid.has_method("_regenerate_hole"):
			_hex_grid.call("_regenerate_hole")
		else:
			break
		await _wait_frames(4)
	if get_tree().get_nodes_in_group("trees").is_empty():
		push_warning("[capture] could not generate a tree-bearing hole after %d tries" % attempts)
	else:
		print("[capture] using tree-bearing hole (regens: %d)" % attempts)
	await _wait_frames(6)


func _board_bounds() -> Dictionary:
	var min_p := Vector3(INF, INF, INF)
	var max_p := Vector3(-INF, -INF, -INF)
	var found := false
	for child in _hex_grid.get_children():
		if child is Node3D and (child as Node3D).visible:
			var p: Vector3 = (child as Node3D).global_position
			# Only count things near ground to avoid UI/offscreen helpers.
			min_p = min_p.min(p)
			max_p = max_p.max(p)
			found = true
	if not found:
		return {"center": Vector3.ZERO, "span": 24.0}
	var center := (min_p + max_p) * 0.5
	center.y = 0.0
	var span := maxf(max_p.x - min_p.x, max_p.z - min_p.z)
	return {"center": center, "span": maxf(span, 12.0)}


func _find_surface_world_pos(surface_types: Array) -> Variant:
	# Ask the HexGrid for its grid and translate a matching cell to world space
	# using the game's own get_tile_world_position (no layout change).
	var gw: int = int(_hex_grid.get("grid_width"))
	var gh: int = int(_hex_grid.get("grid_height"))
	if gw <= 0 or gh <= 0:
		return null
	for col in range(gw):
		for row in range(gh):
			var surf: int = int(_hex_grid.call("get_cell", col, row))
			if surface_types.has(surf):
				var local: Vector3 = _hex_grid.call("get_tile_world_position", Vector2i(col, row))
				return _hex_grid.to_global(local)
	return null


func _find_group_world_pos(group_name: String) -> Variant:
	var nodes := get_tree().get_nodes_in_group(group_name)
	var points: Array[Vector3] = []
	for n in nodes:
		if n is Node3D and (n as Node3D).visible:
			points.append((n as Node3D).global_position)
	if points.is_empty():
		return null
	# Pick the tree with the most neighbours within ~4 units so the close-up
	# frames a dense clump of trees rather than a lone edge straggler.
	var best := points[0]
	var best_neighbours := -1
	for p in points:
		var count := 0
		for q in points:
			if p.distance_to(q) < 4.0:
				count += 1
		if count > best_neighbours:
			best_neighbours = count
			best = p
	return best


# --- render + save ------------------------------------------------------

func _render_and_save(file_name: String) -> void:
	var vp := get_viewport()
	# Force several full frames so the chosen camera + post effects are drawn
	# before we grab the pixels (avoids blank/black captures).
	await _wait_frames(6)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := OUT_DIR + "/" + file_name
	var err := img.save_png(path)
	if err != OK:
		push_error("[capture] save_png failed (%d) for %s" % [err, path])
	else:
		print("[capture] saved %s  size=%s" % [ProjectSettings.globalize_path(path), str(img.get_size())])


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _quit_soon() -> void:
	await _wait_frames(2)
	get_tree().quit()
