extends Node

## test_generate_button_clickable.gd - LIVE-SCENE headless regression test for the
## left-side Generate / hole-navigation buttons being swallowed by HoleViewer.
##
## Bug context: after the Marvel-Snap layout restructure (commit be947d2), the
## Generate buttons, HoleInfoLabel, Lie widgets and on-screen HoleControls were
## moved INTO HoleViewer/HoleHUD. HoleViewer.gd handles mouse input in _input()
## (the global phase, before GUI picking) and, for any click inside its rect that
## no UI control "wants", calls get_viewport().set_input_as_handled() - swallowing
## the click. Its gate, _is_mouse_over_ui_control(), only walked HoleViewer's
## SIBLINGS, so it never saw the buttons that now live as its own descendants, and
## every click over the hole band on those buttons was consumed. The fix extends
## that gate to also walk HoleViewer's own descendant UI (skipping the
## SubViewportContainer), so clicks on the HUD buttons yield to the buttons.
##
## This test loads the REAL scenes/GOLF.tscn, forces a real 1280x720 window so the
## geometry is valid headless, and asserts the Generate button is reachable and NOT
## blocked: visible, enabled, STOP mouse_filter, HoleHUD present with IGNORE filter,
## the button's rect center lies inside HoleViewer's rect (the condition that
## triggers the bug), and - the key regression assertion - the UI-wants-input walk
## the fix touches now returns true for the button's center.
##
## WHAT THIS CANNOT EXERCISE HEADLESSLY: a real OS mouse click and the full
## Viewport GUI routing / set_input_as_handled ordering are not simulated here
## (_input reads the live OS pointer, which is not meaningful under --headless, and
## synthesizing a routed InputEventMouseButton through the viewport is unreliable
## headless). Instead the test drives the EXACT production gate the fix changes,
## HoleViewer._is_mouse_over_ui_control(), with a mouse-position override, and
## asserts:
##   - it returns TRUE over the Generate button center (the click yields to the
##     button instead of being swallowed) - FALSE on the buggy sibling-only tree,
##     TRUE after the fix adds the own-descendants walk; and
##   - it still returns FALSE over bare hole area (tile aiming preserved).
##
## Exits 0 on success, 1 on any failed assertion.

const GOLF_SCENE := "res://scenes/GOLF.tscn"

var _failures: int = 0
var _checks: int = 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)


func _ready() -> void:
	_run()


func _run() -> void:
	print("=== generate-button clickable test: loading GOLF.tscn ===")

	# Force a real window so Control geometry is valid under --headless.
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var win := get_window()
	if win:
		win.size = Vector2i(1280, 720)

	var golf_scene: PackedScene = load(GOLF_SCENE)
	if golf_scene == null:
		printerr("  [FAIL] could not load %s" % GOLF_SCENE)
		get_tree().quit(1)
		return
	var golf: Node = golf_scene.instantiate()
	add_child(golf)

	# Let _ready + hole generation + HUD layout settle.
	for i in range(10):
		await get_tree().process_frame

	# --- Locate the live nodes ---
	var main_ui: Node = golf.find_child("MainUI", true, false)
	_check(main_ui != null, "MainUI node found in GOLF.tscn")
	var hole_viewer: Node = golf.find_child("HoleViewer", true, false)
	_check(hole_viewer != null, "HoleViewer node found in GOLF.tscn")
	if main_ui == null or hole_viewer == null:
		_finish()
		return

	# Prototype mode hides the dev buttons; this test checks them when shown (F1).
	_check(not main_ui.get_node("%GenerateButton").visible, "prototype UI hides GenerateButton")
	main_ui.set_prototype_ui(false)

	var gen_button: Control = main_ui.get_node_or_null("%GenerateButton")
	var gen_unique: Control = main_ui.get_node_or_null("%GenerateUniqueButton")
	var hole_hud: Control = hole_viewer.get_node_or_null("HoleHUD")
	_check(gen_button != null, "GenerateButton reachable via unique name")
	_check(gen_unique != null, "GenerateUniqueButton reachable via unique name")
	_check(hole_hud != null, "HoleHUD overlay exists under HoleViewer")
	if gen_button == null or hole_hud == null:
		_finish()
		return

	# --- Static reachability: the button is visible, enabled, and accepts input ---
	_check(gen_button.visible == true, "GenerateButton is visible")
	_check(gen_button.is_visible_in_tree() == true, "GenerateButton is visible in tree")
	_check(gen_button.get("disabled") == false, "GenerateButton is not disabled")
	_check(gen_button.mouse_filter == Control.MOUSE_FILTER_STOP,
		"GenerateButton mouse_filter is STOP (accepts/consumes input) (=%d)" % gen_button.mouse_filter)
	# HoleHUD must pass input through to its children (IGNORE == 2).
	_check(hole_hud.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"HoleHUD mouse_filter is IGNORE (passes input to children) (=%d)" % hole_hud.mouse_filter)

	# --- The button sits over the hole band (the condition that triggers the bug) ---
	var gen_rect: Rect2 = gen_button.get_global_rect()
	var gen_center: Vector2 = gen_rect.get_center()
	var viewer_rect: Rect2 = (hole_viewer as Control).get_global_rect()
	_check(viewer_rect.has_point(gen_center),
		"GenerateButton center %s lies inside HoleViewer rect %s" % [str(gen_center), str(viewer_rect)])

	# --- KEY regression assertion: the REAL production gate the fix touches ---
	# _is_mouse_over_ui_control() is the exact function that decides whether
	# HoleViewer._input() yields the click to a UI control or swallows it via
	# set_input_as_handled(). It is called with a mouse_pos override so we can
	# drive it at the button's center under --headless (it normally reads the OS
	# mouse). Pre-fix it walked only HoleViewer's SIBLINGS and returned FALSE for
	# a point over the HUD Generate button (the click was swallowed). Post-fix it
	# also walks HoleViewer's OWN descendants and returns TRUE, yielding the click
	# to the button. This assertion FAILS on the buggy tree and PASSES after the fix.
	_check(hole_viewer._is_mouse_over_ui_control(gen_center) == true,
		"_is_mouse_over_ui_control(gen_center) returns true (click yields to Generate button, not swallowed)")

	# Sanity: the same gate must still return FALSE over genuinely empty hole area
	# (bare viewport surface) so tile aiming is preserved. Pick a point inside the
	# HoleViewer rect that is NOT over any HUD control: the lower-center band, well
	# clear of the top-corner HUD widgets and the bottom-left Lie column.
	var empty_pt := Vector2(viewer_rect.position.x + viewer_rect.size.x * 0.5,
		viewer_rect.position.y + viewer_rect.size.y * 0.85)
	_check(hole_viewer._is_mouse_over_ui_control(empty_pt) == false,
		"_is_mouse_over_ui_control(empty_hole_point %s) returns false (aiming preserved over bare hole)" % str(empty_pt))

	# Document that the detected control is a real button, not the viewport surface.
	_check(gen_button is BaseButton, "Generate control is a BaseButton (real UI, not viewport surface)")

	_finish()


func _finish() -> void:
	print("=== generate-button clickable test complete: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
