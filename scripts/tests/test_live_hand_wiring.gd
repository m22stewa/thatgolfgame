extends Node

## test_live_hand_wiring.gd - LIVE-SCENE headless regression test (FEAT-003).
##
## Closes the blind spot the original turn-loop harness missed: it proves the
## ENGINE but never loaded GOLF.tscn, never dealt a hand, and poked the club
## directly. This test instantiates the ACTUAL scenes/GOLF.tscn, drives the
## wired hand flow, and asserts the on-screen loop works end to end:
##   (a) a non-empty club hand is dealt at hole start;
##   (b) the dealt hand is bound to the on-screen hand UI (%ClubRow children,
##       each bound to a dealt club CardInstance);
##   (c) the Shoot button starts disabled before any club is picked;
##   (d) selecting a legal club via the hand-strip signal enables Shoot;
##   (e) pressing Shoot resolves a shot that moves the ball toward the flag.
##
## Exits 0 on success, 1 on any failed assertion. This MUST FAIL on the buggy
## tree (no hand dealt, Shoot never enables) and PASS after the wiring fix.

const GOLF_SCENE := "res://scenes/GOLF.tscn"

var _failures: int = 0
var _checks: int = 0
var _landing_tile: Vector2i = Vector2i(-999, -999)
var _shot_fired: bool = false


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)


func _ready() -> void:
	# Run the async driver and quit with the right code when done.
	_run()


func _run() -> void:
	print("=== live hand wiring test: loading GOLF.tscn ===")
	var golf_scene: PackedScene = load(GOLF_SCENE)
	if golf_scene == null:
		printerr("  [FAIL] could not load %s" % GOLF_SCENE)
		get_tree().quit(1)
		return
	var golf: Node = golf_scene.instantiate()
	add_child(golf)

	# Let _ready + hole generation + _deal_hand_for_current_hole settle.
	for i in range(10):
		await get_tree().process_frame

	# --- Locate the live nodes ---
	var hex_grid: Node = golf.find_child("HexGrid", true, false)
	_check(hex_grid != null, "HexGrid node found in GOLF.tscn")
	var main_ui: Node = golf.find_child("MainUI", true, false)
	_check(main_ui != null, "MainUI node found in GOLF.tscn")
	if hex_grid == null or main_ui == null:
		_finish()
		return

	var card_system = hex_grid.get("card_system")
	var shot_manager = hex_grid.get("shot_manager")
	var golf_ball = hex_grid.get("golf_ball")
	_check(card_system != null, "CardSystemManager available on HexGrid")
	_check(shot_manager != null, "ShotManager available on HexGrid")
	_check(golf_ball != null, "golf_ball placed on hole start")
	if card_system == null or shot_manager == null or golf_ball == null:
		_finish()
		return

	# --- (a) a non-empty club hand is dealt at hole start ---
	var club_hand: Array = []
	if card_system.club_deck_manager:
		club_hand = card_system.club_deck_manager.get_hand()
	_check(club_hand.size() > 0, "(a) non-empty club hand dealt at hole start (size=%d)" % club_hand.size())

	# --- (b) the hand is bound to the on-screen hand UI ---
	var club_row: Node = main_ui.get_node_or_null("%ClubRow")
	_check(club_row != null, "ClubRow node present in hand UI")
	var club_controls: Array = []
	if club_row:
		club_controls = club_row.get_children()
	_check(club_controls.size() > 0, "(b) ClubRow has card controls bound (count=%d)" % club_controls.size())

	# Each control must be bound to one of the dealt club CardInstances.
	var all_bound := club_controls.size() > 0
	for c in club_controls:
		var bound = c.get_meta("card_instance") if c.has_meta("card_instance") else null
		if bound == null or not (bound in club_hand):
			all_bound = false
	_check(all_bound, "(b) every ClubRow control is bound to a dealt club card")

	# --- (c) Shoot starts disabled before any club pick ---
	var shoot_button: Node = main_ui.get_node_or_null("%ShootButton")
	_check(shoot_button != null, "ShootButton node present")
	if shoot_button == null:
		_finish()
		return
	_check(shoot_button.disabled == true, "(c) Shoot button disabled before any club is picked")

	# --- (d) selecting a legal club enables Shoot ---
	# Try dealt clubs via the wired hand-strip signal until Shoot enables. Prefer
	# the SHORTEST legal club (smallest band center) so the resulting carry stays
	# in bounds and moves the ball forward regardless of the random hole seed,
	# keeping the (e) assertion deterministic. This still exercises the real
	# selection path (club_card_selected -> set_club_by_name -> Shoot enable).
	var club_stats: Dictionary = hex_grid.get("CLUB_STATS")
	var club_type_enum: Dictionary = hex_grid.get("ClubType")
	var ordered: Array = club_hand.duplicate()
	ordered.sort_custom(func(a, b) -> bool:
		var ca: int = int(club_type_enum.get(a.data.target_club, 0))
		var cb: int = int(club_type_enum.get(b.data.target_club, 0))
		var da: int = int(club_stats.get(ca, {}).get("distance", 999))
		var db: int = int(club_stats.get(cb, {}).get("distance", 999))
		return da < db
	)
	var enabled_after_pick := false
	for inst in ordered:
		main_ui.emit_signal("club_card_selected", inst)
		await get_tree().process_frame
		if not shoot_button.disabled:
			enabled_after_pick = true
			break
	_check(enabled_after_pick, "(d) selecting a legal club enables the Shoot button")
	_check(int(hex_grid.get("current_club")) >= 0, "(d) hex_grid.current_club set by selection (=%d)" % int(hex_grid.get("current_club")))

	# --- (e) pressing Shoot resolves a shot that moves the ball ---
	var start_tile: Vector2i = hex_grid.world_to_grid(golf_ball.position)
	var flag_pos: Vector2i = hex_grid.get("flag_position")
	var start_dist: int = hex_grid.get_tile_distance(start_tile, flag_pos)

	# shot_completed fires synchronously inside confirm_shot with the resolved
	# context; capture the landing tile from it.
	# Instance vars capture the result (GDScript lambdas capture locals by value,
	# so we can't mutate a local from inside the signal handler).
	_landing_tile = Vector2i(-999, -999)
	_shot_fired = false
	var on_completed := Callable(self, "_on_shot_completed_probe")
	shot_manager.shot_completed.connect(on_completed)

	# Press Shoot through the wired button signal (the real player path).
	shoot_button.emit_signal("pressed")

	# confirm_shot resolves synchronously, but the ball-flight animation that
	# repositions golf_ball runs over several frames; let it settle.
	for i in range(20):
		await get_tree().process_frame

	if shot_manager.shot_completed.is_connected(on_completed):
		shot_manager.shot_completed.disconnect(on_completed)

	_check(_shot_fired, "(e) Shoot resolved a shot (shot_completed fired)")
	# Ball-moved: compare the ball's actual grid tile after the shot settles.
	var end_tile: Vector2i = hex_grid.world_to_grid(golf_ball.position)
	_check(end_tile != start_tile, "(e) ball moved to a new tile (%s -> %s)" % [str(start_tile), str(end_tile)])
	var end_dist: int = hex_grid.get_tile_distance(end_tile, flag_pos)
	_check(end_dist <= start_dist, "(e) ball no farther from flag (%d -> %d)" % [start_dist, end_dist])

	_finish()


func _on_shot_completed_probe(ctx) -> void:
	_shot_fired = true
	_landing_tile = ctx.landing_tile


func _finish() -> void:
	print("=== live hand wiring test complete: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
