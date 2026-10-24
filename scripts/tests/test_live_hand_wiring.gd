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

	# --- (a2) a fresh 4-card shot hand of playable SHOT cards ---
	var mod_hand: Array = hex_grid.shot_hand
	_check(mod_hand.size() == hex_grid.SHOT_HAND_SIZE, "(a2) shot hand dealt with %d cards (got %d)" % [hex_grid.SHOT_HAND_SIZE, mod_hand.size()])
	var mod_names: Array = []
	var all_shot := mod_hand.size() > 0
	for c in mod_hand:
		mod_names.append(c.data.card_name)
		if c.data.card_type != CardData.CardType.SHOT:
			all_shot = false
	_check(all_shot, "(a2) modifier hand is all SHOT cards %s" % str(mod_names))

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

	# --- (c) each shot starts aimed at the flag with a suggested legal club ---
	var shoot_button: Node = main_ui.get_node_or_null("%ShootButton")
	_check(shoot_button != null, "ShootButton node present")
	if shoot_button == null:
		_finish()
		return
	var flag_tile: Vector2i = hex_grid.get("flag_position")
	var open_plan: Dictionary = shot_manager.current_context.get_metadata("shot_plan", {})
	var open_stats: Dictionary = hex_grid.CLUB_STATS.get(hex_grid.current_club, {})
	var open_carry := int(open_plan.get("carry", -1))
	_check(open_carry >= int(open_stats.get("band_min", 99)) and open_carry <= int(open_stats.get("band_max", -1)), "(c) the caddie's opening target is inside the suggested club's carry (%d in %d-%d)" % [open_carry, int(open_stats.get("band_min", 0)), int(open_stats.get("band_max", 0))])
	_check(int(open_plan.get("over", 1)) == 0, "(c) the default aim never overspends (%d/%d)" % [int(open_plan.get("cost", 0)), int(open_plan.get("power", 0))])
	_check(int(hex_grid.get("current_club")) >= 0 and shoot_button.disabled == false, "(c) a legal club is suggested and Shoot is ready (club=%d)" % int(hex_grid.get("current_club")))

	# --- (h) tapping a hex re-aims: the landing spread follows the new line ---
	var ball_now: Vector2i = hex_grid.world_to_grid(golf_ball.position)
	var flag_center: Vector2i = shot_manager.current_context.aim_tile
	var side_target := Vector2i(clampi(ball_now.x + 4, 0, hex_grid.grid_width - 1), ball_now.y + 6)
	if side_target.x == ball_now.x + 4 or hex_grid.grid_width <= ball_now.x + 4:
		side_target.x = clampi(ball_now.x - 4, 0, hex_grid.grid_width - 1) if ball_now.x + 4 >= hex_grid.grid_width else side_target.x
	_check(hex_grid.set_aim_cell(side_target), "(h) set_aim_cell accepts an off-line hex %s" % str(side_target))
	var side_center: Vector2i = shot_manager.current_context.aim_tile
	var tc = hex_grid.get("turn_controller")
	_check(side_center != flag_center, "(h) re-aiming moves the footprint center (%s -> %s)" % [str(flag_center), str(side_center)])
	_check(tc._hex_distance(side_center, side_target) < tc._hex_distance(flag_center, side_target), "(h) new center is nearer the tapped hex than the old one")
	_check(shot_manager.current_context.aoe_tiles.has(side_center), "(h) footprint spread contains its center")
	# Aim is capped at reach: the flag is accepted only when a club gets there
	var reach: int = hex_grid.aim_reach()
	var flag_dist: int = hex_grid.hex_distance(ball_now, flag_tile)
	_check(hex_grid.set_aim_cell(flag_tile) == (flag_dist <= reach), "(h) re-aim at the flag only if in reach (%d hexes, reach %d)" % [flag_dist, reach])
	var far_tile: Vector2i = tc._point_along(ball_now, flag_tile, reach + 1)
	if hex_grid.hex_distance(ball_now, far_tile) > reach:
		_check(not hex_grid.set_aim_cell(far_tile), "(h) a hex past the longest club's reach can't be picked")
	var near_tile: Vector2i = tc._point_along(ball_now, flag_tile, 2)
	hex_grid.set_aim_cell(near_tile)
	var club_min: int = int(hex_grid.CLUB_STATS.get(hex_grid.current_club, {}).get("band_min", 0))
	var near_carry: int = int(shot_manager.current_context.get_metadata("shot_plan", {}).get("carry", 0))
	_check(club_min <= 2 or near_carry >= club_min, "(h) a club can't be hit shorter than its band (carry %d, min %d)" % [near_carry, club_min])
	hex_grid._auto_aim_new_shot()

	# --- (i) shot cards toggle on/off, spend power, max 3; overspend adds Strain ---
	var plan_cost := func() -> int: return int(shot_manager.current_context.get_metadata("shot_plan", {}).get("cost", -1))
	var base_cost: int = plan_cost.call()
	var costly = null
	for c in hex_grid.shot_hand:
		if c.data.effects.size() > 0 and c.data.effects[0] is EffectShotShape and c.data.effects[0].power_cost > 0:
			costly = c
			break
	_check(base_cost > 0, "(i) the flag-aimed plan has a power cost (%d)" % base_cost)
	if costly:
		var card_cost := int(costly.data.effects[0].power_cost)
		main_ui.emit_signal("modifier_card_selected", costly)
		_check(hex_grid.planned_cards.has(costly), "(i) playing %s marks it played" % costly.data.card_name)
		_check(plan_cost.call() == base_cost, "(i) %s costs no power: cards are paid in Chips (%d -> %d)" % [costly.data.card_name, base_cost, plan_cost.call()])
		_check(hex_grid._planned_cost() == card_cost, "(i) %s puts %d Chips on the mat" % [costly.data.card_name, card_cost])
		main_ui.emit_signal("modifier_card_selected", costly)
		_check(not hex_grid.planned_cards.has(costly) and plan_cost.call() == base_cost, "(i) tapping it again takes it back")
	# Shot cards only: utility cards (Fire Extinguisher...) play at once and leave the hand
	var shape_cards: Array = hex_grid.shot_hand.filter(func(c): return c.data.effects.size() > 0 and c.data.effects[0] is EffectShotShape)
	for c in shape_cards:
		main_ui.emit_signal("modifier_card_selected", c)
	var expect: int = mini(hex_grid.MAX_PLANNED_CARDS, shape_cards.size())
	_check(hex_grid.planned_cards.size() == expect, "(i) at most %d cards per shot (played %d of %d shot cards)" % [hex_grid.MAX_PLANNED_CARDS, hex_grid.planned_cards.size(), shape_cards.size()])
	hex_grid._clear_planned_cards()
	hex_grid.rebuild_turn_plan()
	var discard_before: int = hex_grid.shot_discard.size()
	hex_grid._add_strain_cards(2)
	var strain_added: int = hex_grid.shot_discard.size() - discard_before
	_check(strain_added == 2 and hex_grid.shot_discard[-1].data.card_id == "strain", "(i) overspending adds Strain cards to the deck")

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
	# Picking a club re-aims inside its carry band, so the preview shows its distance
	var ball_tile: Vector2i = hex_grid.world_to_grid(hex_grid.golf_ball.position)
	var in_band := true
	var carries: Array = []
	for inst in ordered:
		var club: int = int(club_type_enum.get(inst.data.target_club, -1))
		# A short hole may have no hex in a long club's band: nothing to aim at
		if club < 0 or not hex_grid._is_club_legal_at(club, ball_tile) or hex_grid._caddie_pick(club).is_empty():
			continue
		main_ui.emit_signal("club_card_selected", inst)
		await get_tree().process_frame
		var stats: Dictionary = hex_grid.get_club_stats(club, {})
		var carry: int = hex_grid.hex_distance(ball_tile, hex_grid.turn_aim_target)
		carries.append("%s %d" % [inst.data.target_club, carry])
		if carry < int(stats.get("band_min", 0)) or carry > int(stats.get("band_max", 0)):
			in_band = false
	_check(in_band and carries.size() > 0, "(d) each picked club aims inside its own carry band (%s)" % ", ".join(carries))
	# Back to the shortest legal club, so (e)'s shot stays short and predictable
	for inst in ordered:
		main_ui.emit_signal("club_card_selected", inst)
		await get_tree().process_frame
		if not shoot_button.disabled:
			break

	# --- (g) points: trick detector wired, coins pay out, wallet matches the log ---
	var currency = hex_grid.get("currency_manager")
	_check(shot_manager.trick_detector != null, "(g) ShotManager scores through the trick detector")
	var coin: Node3D = null
	for _pass in range(2):
		for child in hex_grid.get_children():
			if child.is_in_group("coins") and not child.is_queued_for_deletion():
				coin = child
				break
		if coin:
			break
		# (e)'s shot can fly through the hole's coins and take them: lay one
		hex_grid._range_spawn_coin(Vector2i(6, 6))
	_check(coin != null and currency != null, "(g) a coin spawned on the hole and a wallet exists")
	if coin and currency:
		var before: int = currency.get_balance()
		var ball_home: Vector3 = golf_ball.position
		golf_ball.position = hex_grid.get_tile_surface_position(coin.get_meta("cell"))
		hex_grid._collect_coins_at_ball()
		golf_ball.position = ball_home
		var gained: int = currency.get_balance() - before
		_check(gained > 0 and gained % TrickShotDetector.COIN_POINTS == 0, "(g) landing on a coin pays %d pts per coin (gained %d)" % [TrickShotDetector.COIN_POINTS, gained])
		var logged := 0
		for entry in hex_grid.hole_points_log:
			logged += entry.points
		_check(logged == currency.get_balance(), "(g) wallet (%d) equals points logged this hole (%d)" % [currency.get_balance(), logged])
	# Flying through the hex next to a coin's column picks it up (+Chips)
	var spot := Vector2i(2, 2)
	hex_grid._range_spawn_coin(spot)
	var beam_ok := false
	for child in hex_grid.get_children():
		if child.is_in_group("coins") and child.get_meta("cell", Vector2i(-9, -9)) == spot:
			beam_ok = child.get_node_or_null("Beam") != null
	_check(beam_ok, "(g) a coin stands in a column of light")
	var chips_before: int = hex_grid.chip_stack
	hex_grid._collect_coins_in_flight(Vector2i(3, 2))  # an adjacent hex
	var still_there := false
	for child in hex_grid.get_children():
		if child.is_in_group("coins") and child.get_meta("cell", Vector2i(-9, -9)) == spot:
			still_there = true
	_check(not still_there and hex_grid.chip_stack == chips_before + hex_grid.CHIPS_PER_COIN, "(g) flying past a coin collects it (+%d Chips)" % hex_grid.CHIPS_PER_COIN)

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

	# --- (f) blowout ends the run: no new shot starts, run-over popup shows ---
	var run_state = hex_grid.get("run_state")
	var shot_ui = main_ui.get_node_or_null("ShotUI")
	_check(run_state != null and shot_ui != null, "(f) RunStateManager and ShotUI available")
	if run_state and shot_ui:
		# Let the last shot's ball land first: no turn starts mid-flight
		var waited := 0
		while shot_manager.is_animating and waited < 600:
			await get_tree().process_frame
			waited += 1
		run_state.adjust_score(run_state.blowout_limit - run_state.get_live_vs_par(), "test: force blowout")
		_check(run_state.is_blown_out, "(f) run is blown out at the limit")
		hex_grid._start_new_shot()
		_check(shot_ui.hole_complete_popup.visible, "(f) run-over popup shown instead of a new shot")
		_check(shot_ui.next_button.text == "New Run", "(f) popup offers a New Run")

	_finish()


func _on_shot_completed_probe(ctx) -> void:
	_shot_fired = true
	_landing_tile = ctx.landing_tile


func _finish() -> void:
	print("=== live hand wiring test complete: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
