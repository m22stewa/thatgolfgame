extends Node

## test_autoplay.gd - Bot playtest: plays whole holes through the real GOLF.tscn
## using only the default plan (auto-aim at the flag + suggested club, no
## cards) and the Shoot button. Logs every time Shoot is unavailable or a turn
## stalls, plus strokes per hole. Exits 1 if any turn could not be shot.
##
## Run: Godot --headless --path . scenes/tests/test_autoplay.tscn

const GOLF_SCENE := "res://scenes/GOLF.tscn"
const HOLES_TO_PLAY := 6  # override with env AUTOPLAY_HOLES for balance runs
const MAX_STROKES_PER_HOLE := 15
const TURN_TIMEOUT_S := 20.0  # real seconds at the sped-up time scale

var hg: Node = null
var main_ui: Node = null
var shoot_button: Button = null
var _problems: Array = []
var _shots_fired := 0
var _results: Array = []  # {par, strokes, putts, blown}
var _putts_this_hole := 0
var _shots_this_hole := 0
var _green_turns := 0
var _shop_visits := 0
var _fire_hits := 0
var _ice_runs := 0
var _ice_touches := 0
var _bounces := 0
var _swings := {"pure": 0, "short": 0, "long": 0, "thin": 0, "hook": 0}
var _swing_rng := RandomNumberGenerator.new()
const SWING_TIMING_SD := 0.08  # seconds: how far off a decent player's release is
var _extinguished := 0
var _tunnel_rides := 0
var _fires_seen := 0
var _bought := 0
var _removed := 0


func _ready() -> void:
	_swing_rng.seed = 7
	Engine.time_scale = 8.0
	var golf: Node = load(GOLF_SCENE).instantiate()
	add_child(golf)
	for i in range(30):
		await get_tree().process_frame
	hg = golf.find_child("HexGrid", true, false)
	main_ui = golf.find_child("MainUI", true, false)
	shoot_button = main_ui.get_node_or_null("%ShootButton")
	var holes := int(OS.get_environment("AUTOPLAY_HOLES")) if OS.get_environment("AUTOPLAY_HOLES") != "" else HOLES_TO_PLAY
	print("=== autoplay: %d holes ===" % holes)

	# The opening hole's flyover ends in the Pro Shop too
	await _shop_for_hole(1)
	for hole in range(holes):
		_putts_this_hole = 0
		_shots_this_hole = 0
		var par: int = hg.current_par
		if hg.course_features and hg.course_features.count("fire") > 0:
			_fires_seen += 1
		if OS.get_environment("AUTOPLAY_SHOW_FEATURES") != "":
			print("  SEED %d ice %d gusts %d fire %d tc_has_features %s" % [hg.hole_context.seed, hg.course_features.count("ice"), hg.course_features.count("tunnel"), hg.course_features.count("fire"), hg.turn_controller.course_features != null])
		print("  LENGTH par %d: %d hexes tee->flag" % [par, hg.hex_distance(hg.world_to_grid(hg.golf_ball.position), hg.flag_position)])
		await _play_hole(hole + 1)
		if _shots_this_hole == 0:
			_problems.append("hole %d: finished without a shot (%s)" % [hole + 1, _state()])
			continue
		if hg.run_state.strokes_this_hole == 0:
			print("  (hole %d: stroke count reset mid-hole, excluded)" % (hole + 1))
			continue
		_results.append({"par": par, "strokes": hg.run_state.strokes_this_hole, "putts": _putts_this_hole, "blown": hg.run_state.is_blown_out})
		hg.shot_ui.hide_hole_complete()
		# Wait out the last shot, then for the regeneration (it bumps shot_serial)
		await _wait(func(): return not hg.shot_manager.is_animating, 10.0)
		var serial_before: int = hg.shot_serial
		if hg.run_state.is_final_hole() or hg.run_state.is_blown_out:
			hg._show_run_complete()  # what "Finish Round" / "New Run" does
		else:
			hg._proceed_to_next_hole()  # what "Next Hole" does
		# The next hole is generated behind a loading transition
		if not await _wait(func(): return hg.shot_serial != serial_before and not hg.hole_complete_triggered and _ready_to_shoot(), 15.0):
			_problems.append("hole %d: next hole never became playable (%s)" % [hole + 2, _state()])
		# Its flyover ends in the Pro Shop, where the bag is picked
		else:
			await _shop_for_hole(hole + 2)

	_print_balance()
	print("FEATURES fires seen %d, fire hits %d, ice hexes rolled over %d, ice runs %d, trampoline bounces %d, tunnel rides %d, extinguishers played %d" % [_fires_seen, _fire_hits, _ice_touches, _ice_runs, _bounces, _tunnel_rides, _extinguished])
	print("--- %d shots fired (%d from the green view), %d shop visits (%d bought, %d removed), %d problems ---" % [_shots_fired, _green_turns, _shop_visits, _bought, _removed, _problems.size()])
	for p in _problems:
		printerr("  [PROBLEM] %s" % p)
	print("=== autoplay complete: %d problems ===" % _problems.size())
	Engine.time_scale = 1.0
	get_tree().quit(1 if _problems.size() > 0 else 0)


func _play_hole(n: int) -> void:
	var par: int = hg.current_par
	for stroke in range(MAX_STROKES_PER_HOLE):
		var ready := await _wait(func(): return hg.hole_complete_triggered or hg.run_state.is_blown_out or _ready_to_shoot(), TURN_TIMEOUT_S)
		if hg.run_state.is_blown_out:
			print("  hole %d (par %d): BLOWOUT after %d strokes" % [n, par, hg.run_state.strokes_this_hole])
			return
		if hg.hole_complete_triggered:
			print("  hole %d (par %d): holed in %d" % [n, par, hg.run_state.strokes_this_hole])
			return
		if not ready:
			_problems.append("hole %d stroke %d: turn never became ready (%s)" % [n, stroke + 1, _state()])
			return
		if shoot_button.disabled:
			_problems.append("hole %d stroke %d: Shoot disabled (%s)" % [n, stroke + 1, _state()])
			return
		# Green view: on the green the camera frames it and the overlay shows; off it, neither
		var bt: Vector2i = hg.world_to_grid(hg.golf_ball.position)
		var on_green: bool = hg.get_cell(bt.x, bt.y) == 4
		var viewing: bool = hg.hole_viewer != null and hg.hole_viewer.is_green_view
		var overlay_on: bool = hg.green_overlay != null and hg.green_overlay.visible
		if on_green != viewing or on_green != overlay_on:
			_problems.append("hole %d stroke %d: green view %s / overlay %s while ball %s the green" % [n, stroke + 1, viewing, overlay_on, "on" if on_green else "off"])
		_play_extinguisher(n)
		if on_green and hg.putting_active:
			if hg.main_ui_ref.putt_panel == null or not hg.main_ui_ref.putt_panel.visible:
				_problems.append("hole %d stroke %d: no putting panel on the green" % [n, stroke + 1])
			if hg.putt_strokes >= GreenBoard.MAX_PUTTS:
				_problems.append("hole %d stroke %d: putt %d of %d" % [n, stroke + 1, hg.putt_strokes + 1, GreenBoard.MAX_PUTTS])
			# Caddie Peek on a green's first putt, when there are putting chips for it
			if hg.putt_strokes == 0 and hg.putt_chips >= hg.CADDIE_PEEK_CHIPS:
				var chips: int = hg.putt_chips
				hg.main_ui_ref.emit_signal("caddie_peek_pressed")
				if hg.putt_peek == "" or hg.putt_chips != chips - hg.CADDIE_PEEK_CHIPS:
					_problems.append("hole %d: Caddie Peek didn't show a card for a chip" % n)
				elif hg.putt_peek != hg.putt_modifiers.draw_pile.back():
					_problems.append("hole %d: Caddie Peek showed %s, not the top card" % [n, hg.putt_peek])
			_read_the_green()
		if on_green:
			_green_turns += 1
			if hg.green_board == null or not hg.green_board.tiles.has(hg.green_board.cup) or not hg.putting_active:
				_problems.append("hole %d stroke %d: on the green but no putting board/turn" % [n, stroke + 1])
		var fired := [false]
		var club_name: String = hg.CLUB_STATS.get(hg.current_club, {}).get("name", "?")
		if club_name == "Putter":
			_putts_this_hole += 1
			var b: Vector2i = hg.world_to_grid(hg.golf_ball.position)
			if hg.turn_aim_target != hg.flag_position and hg.hex_distance(b, hg.flag_position) <= 4:
				var fp := ShotPlan.build(hg, b, hg.flag_position, {"power": 4, "spread": 1, "exact_usage": 0.0})
				print("      PUTT NOT AT CUP ball %s flag %s (surface %d, dist %d) aim %s | flag plan end %s ring %s blocked %s tiles %s | flag score %.2f aim score %.2f" % [b, hg.flag_position, hg.get_cell(hg.flag_position.x, hg.flag_position.y), hg.hex_distance(b, hg.flag_position), hg.turn_aim_target, fp.end, fp.ring, fp.blocked, fp.tiles, hg._caddie_landing_score(fp.end, fp.ring), hg._caddie_landing_score(hg.turn_aim_target, 1)])
		var from: Vector2i = hg.world_to_grid(hg.golf_ball.position)
		var aim: Vector2i = hg.turn_aim_target
		var on_done := func(ctx):
			fired[0] = true
			if ctx.get_metadata("hit_fire", false):
				_fire_hits += 1
			if ctx.has_metadata("ice_run"):
				_ice_runs += 1
			if ctx.has_metadata("bounced"):
				_bounces += 1
			if ctx.has_metadata("tunnel_ride"):
				_tunnel_rides += 1
			for t in ctx.get_metadata("roll_tiles", []):
				if hg.course_features and hg.course_features.kind_at(t) == "ice":
					_ice_touches += 1
			print("    %s%s from %s(%d) aim %s -> landing %s(%d), %d from flag" % [club_name, " (%s)" % ctx.get_metadata("swing", "") if ctx.has_metadata("swing") else "", from, hg.get_cell(from.x, from.y), aim, ctx.landing_tile, hg.get_cell(ctx.landing_tile.x, ctx.landing_tile.y), hg.hex_distance(ctx.landing_tile, hg.flag_position)])
			if club_name == "Putter" and ctx.landing_tile != hg.flag_position and hg.hex_distance(from, hg.flag_position) <= 1:
				var pl: Dictionary = ctx.get_metadata("shot_plan", {})
				print("      MISSED SHORT PUTT flag %s surface %d | plan end %s ring %s carry %s blocked %s | make %s | aoe %s weights %s" % [hg.flag_position, hg.get_cell(hg.flag_position.x, hg.flag_position.y), pl.get("end"), pl.get("ring"), pl.get("carry"), pl.get("blocked"), ctx.get_metadata("putt_make_chance", "-"), ctx.aoe_tiles, ctx.aoe_weights])
		var on_putt := func(result):
			fired[0] = true
			print("    Putt from %s (%s) -> %s, %d hexes, %s" % [from, PuttModifierDeck.describe(result.flip), result.end, result.touched, result.reason])
		hg.shot_manager.shot_completed.connect(on_done)
		hg.putt_resolved.connect(on_putt)
		if club_name != "Putter" and OS.get_environment("AUTOPLAY_SWING") != "off":
			hg.pending_swing = _model_swing()
		shoot_button.emit_signal("pressed")
		hg.shot_manager.shot_completed.disconnect(on_done)
		hg.putt_resolved.disconnect(on_putt)
		if not fired[0]:
			_problems.append("hole %d stroke %d: Shoot pressed but no shot resolved (%s)" % [n, stroke + 1, _state()])
			return
		_shots_fired += 1
		_shots_this_hole += 1
		# Wait for the ball to land and the next turn (or hole-out) to begin
		var settled := await _wait(func(): return hg.hole_complete_triggered or hg.run_state.is_blown_out or (not hg.shot_manager.is_animating and hg.turn_aim_target.x >= 0), TURN_TIMEOUT_S)
		if not settled:
			_problems.append("hole %d stroke %d: stuck after the shot (%s)" % [n, stroke + 1, _state()])
			return
	print("  hole %d (par %d): not holed after %d strokes (%s)" % [n, par, MAX_STROKES_PER_HOLE, _state()])


func _print_balance() -> void:
	"""Default-play balance: strokes vs par by par type, putts, aces, blowouts."""
	var by_par := {}
	var aces := 0
	var blown := 0
	var total_diff := 0
	var putts := 0
	for r in _results:
		if r.blown:
			blown += 1
			continue
		var d: Array = by_par.get(r.par, [])
		d.append(r.strokes - r.par)
		by_par[r.par] = d
		total_diff += r.strokes - r.par
		putts += r.putts
		if r.strokes == 1:
			aces += 1
	var finished := _results.size() - blown
	print("SWING pure %d, short %d, long %d, thin %d, hook %d" % [_swings.pure, _swings.short, _swings.long, _swings.thin, _swings.hook])
	print("BALANCE holes=%d finished=%d avg_vs_par=%+.2f putts/hole=%.2f aces=%d (%.0f%%) blowouts=%d" % [
		_results.size(), finished, float(total_diff) / maxf(1, finished), float(putts) / maxf(1, finished),
		aces, 100.0 * aces / maxf(1, finished), blown])
	for par in [3, 4, 5]:
		var d: Array = by_par.get(par, [])
		if d.is_empty():
			continue
		var sum := 0
		var dist := {}
		for x in d:
			sum += x
			dist[x] = dist.get(x, 0) + 1
		print("BALANCE  par %d: n=%d avg=%+.2f spread=%s" % [par, d.size(), float(sum) / d.size(), dist])


func _shop_for_hole(n: int) -> void:
	"""Wait for the Pro Shop the hole being played opens (after its flyover),
	then visit it. n is the hole's number in the whole autoplay."""
	var opened := func(): return hg.shop_panel != null and hg.shop_panel.visible and not hg._shop_wiping \
		and hg.shop_panel._hole == hg.run_state.current_hole
	if await _wait(opened, 25.0):
		await _visit_shop(n)
	else:
		_problems.append("hole %d: the Pro Shop didn't open after the flyover" % n)


func _visit_shop(n: int) -> void:
	"""The Pro Shop after a hole's flyover: pick the bag (buying a better club
	if we can), buy a card we can afford, strip a Strain card, then tee off."""
	if hg.run_shop.offers.size() != RunShop.OFFER_COUNT:
		_problems.append("hole %d: Pro Shop didn't open with %d offers" % [n, RunShop.OFFER_COUNT])
	_shop_visits += 1
	if not hg.run_shop.club_offers.is_empty() and hg.shop_balance() >= hg.run_shop.club_offers[0].price():
		var item: ClubItem = hg.run_shop.club_offers[0]
		hg.shop_buy_club(0)
		if hg.owned_clubs[item.club] != item:
			_problems.append("hole %d: buying a club didn't replace ours" % n)
	for item in hg.shop_clubs():
		if hg.hole_bag.size() < hg.BAG_SIZE and not hg.shop_bag_has(item.club):
			hg.shop_toggle_bag(item.club)
	if hg.hole_bag.size() != hg.BAG_SIZE:
		_problems.append("hole %d: picked %d clubs, not %d" % [n, hg.hole_bag.size(), hg.BAG_SIZE])
	# A lighter bag multiplies the hole's points (checked on the real wallet, then undone)
	var full: Array[int] = hg.hole_bag.duplicate()
	hg.hole_bag = full.slice(0, 2)
	var wallet: int = hg.shop_balance()
	var paid: int = hg._award_points(10, "Bag test")
	if paid != 20 or hg.shop_balance() != wallet + 20:
		_problems.append("hole %d: a 2-club bag paid %d for 10 points, not 20" % [n, paid])
	hg.currency_manager.remove_chips(paid, "Bag test undo")
	hg.hole_points_log.pop_back()
	hg.hole_bag = full
	if hg.points_multiplier() != 1.0:
		_problems.append("hole %d: a full bag should pay x1" % n)
	if OS.get_environment("AUTOPLAY_SHOW_DECK") != "":
		print("  DECK ", hg.shop_deck_cards().map(func(c): return "%s(%d)" % [c.data.card_id, c.data.card_type]))
	var balance: int = hg.shop_balance()
	var deck_size: int = hg.shop_deck_cards().size()
	var price := RunShop.price_of(hg.run_shop.offers[0])
	if balance >= price:
		hg.shop_buy(0)
		if hg.shop_balance() != balance - price or hg.shop_deck_cards().size() != deck_size + 1:
			_problems.append("hole %d: buying a card didn't charge %d / add it to the deck" % [n, price])
		_bought += 1
	for card in hg.shop_deck_cards():
		if card.data.card_type == CardData.CardType.NEGATIVE and hg.shop_balance() >= RunShop.REMOVE_PRICE:
			var before: int = hg.shop_deck_cards().size()
			hg.shop_remove(card)
			if hg.shop_deck_cards().size() != before - 1:
				_problems.append("hole %d: removing Strain didn't shrink the deck" % n)
			_removed += 1
			break
	hg.shop_continue()
	# Tee off wipes back to the hole
	if not await _wait(func(): return not hg.shop_panel.visible, 5.0):
		_problems.append("hole %d: Tee off didn't close the Pro Shop" % n)
	for card in hg._legal_club_cards():
		var club: int = hg.ClubType.get(card.data.target_club)
		if club != hg.ClubType.PUTTER and not hg.hole_bag.has(club):
			_problems.append("hole %d: %s offered but not in the bag" % [n, card.data.card_name])


func _read_the_green() -> void:
	"""A sensible putter: for each of the six lines, the chance the flip holes
	it and, failing that, how close the base pace leaves it; take the best."""
	var board: GreenBoard = hg.green_board
	var ball: Vector2i = hg._ball_small()
	var odds := PuttModifierDeck.chain_odds(hg.putt_modifiers.draw_pile if not hg.putt_modifiers.draw_pile.is_empty() else hg.putt_modifiers.discard)
	var best := 0
	var best_score := INF
	for d in range(6):
		var p := 0.0
		for o in odds:
			if board.simulate_putt(ball, d, GreenBoard.PUTT_BASE + int(o.mod), o.special, {"steady": o.steady}).holed:
				p += float(o.p)
		var r: Dictionary = board.simulate_putt(ball, d, GreenBoard.PUTT_BASE)
		var score: float = -10.0 * p + GreenBoard.distance(r.end, board.cup) * 0.5
		if score < best_score:
			best_score = score
			best = d
	hg.set_putt_dir(best)


func _ready_to_shoot() -> bool:
	return hg.turn_aim_target.x >= 0 and not hg.shot_manager.is_animating and not hg.shot_manager.is_shot_in_progress


func _state() -> String:
	var ball: Vector2i = hg.world_to_grid(hg.golf_ball.position)
	var surface: int = hg.get_cell(ball.x, ball.y)
	var plan: Dictionary = hg.shot_manager.current_context.get_metadata("shot_plan", {})
	return "strokes %d, run %d, blown %s, holed %s, animating %s, in_progress %s, ball %s surface %d, flag %s, club %d, legal %s, aim %s, plan %s/%s, reason '%s'" % [
		hg.run_state.strokes_this_hole, hg.run_state.get_live_vs_par(), hg.run_state.is_blown_out,
		hg.hole_complete_triggered, hg.shot_manager.is_animating, hg.shot_manager.is_shot_in_progress,
		ball, surface, hg.flag_position, hg.current_club, hg._allowed_clubs_for_tile(ball),
		hg.turn_aim_target, plan.get("cost", "-"), plan.get("power", "-"),
		hg._shoot_block_reason() if hg.has_method("_shoot_block_reason") else "?"]


func _wait(cond: Callable, timeout_s: float) -> bool:
	var start := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - start > timeout_s * 1000.0:
			return false
		await get_tree().process_frame
	return true


func _affordable(card) -> bool:
	"""Enough Chips left to play it (the game refuses it otherwise)."""
	return hg._card_cost(card) <= hg.chip_stack - hg._planned_cost()


func _play_extinguisher(n: int) -> void:
	"""A Fire Extinguisher in hand with fire on the hole: play it, check it worked."""
	if hg.course_features == null or hg.course_features.count("fire") == 0:
		return
	for card in hg.shot_hand:
		if card.data.card_id == "extinguisher" and _affordable(card):
			hg.main_ui_ref.emit_signal("modifier_card_selected", card)
			_extinguished += 1
			if hg.course_features.count("fire") > 0:
				_problems.append("hole %d: Fire Extinguisher left fire burning" % n)
			if hg.shot_hand.has(card) or not hg.shot_discard.has(card):
				_problems.append("hole %d: Fire Extinguisher didn't go to the discard" % n)
			return


func _model_swing() -> Dictionary:
	"""A decent player on the SHOOT meter: aims to let go with the box in the
	middle of the green band (on its way out), give or take SWING_TIMING_SD.
	Harder shots have a thinner band and a faster box."""
	var plan: Dictionary = hg.shot_manager.current_context.get_metadata("shot_plan", {}) if hg.shot_manager.current_context else {}
	var d: Vector2 = hg._swing_difficulty(plan)
	var aim: float = hg._swing_aim_power(plan)
	var b := SwingButton.bands(d.x, aim)
	var target_t: float = (b.lo + b.hi) / 2.0 * d.y / 2.0
	var t := maxf(0.0, target_t + _swing_rng.randfn(0.0, SWING_TIMING_SD))
	var w := SwingButton.meter_width(t, d.y)
	var kind := SwingButton.grade(w, d.x, aim)
	_swings[kind] += 1
	return {"kind": kind, "width": w, "power": SwingButton.power_at(w)}
