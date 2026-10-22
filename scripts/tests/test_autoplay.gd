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


func _ready() -> void:
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

	for hole in range(holes):
		_putts_this_hole = 0
		_shots_this_hole = 0
		var par: int = hg.current_par
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
			hg._proceed_to_next_hole()
		# The next hole is generated behind a loading transition
		if not await _wait(func(): return hg.shot_serial != serial_before and not hg.hole_complete_triggered and _ready_to_shoot(), 15.0):
			_problems.append("hole %d: next hole never became playable (%s)" % [hole + 2, _state()])

	_print_balance()
	print("--- %d shots fired (%d from the green view), %d problems ---" % [_shots_fired, _green_turns, _problems.size()])
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
		if on_green and hg.putting_active:
			if hg.putt_hand.size() != hg.PUTT_HAND_SIZE:
				_problems.append("hole %d stroke %d: green hand has %d cards" % [n, stroke + 1, hg.putt_hand.size()])
			for card in hg.putt_hand:
				if card.data.card_id == "firm_putt":
					hg.main_ui_ref.emit_signal("modifier_card_selected", card)
					if hg._putt_opts().reach != GreenBoard.PUTT_REACH + 2:
						_problems.append("hole %d: Firm Putt didn't add reach" % n)
					hg.main_ui_ref.emit_signal("modifier_card_selected", card)
					if hg._putt_opts().reach != GreenBoard.PUTT_REACH:
						_problems.append("hole %d: Firm Putt didn't toggle off" % n)
					break
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
			print("    %s from %s(%d) aim %s -> landing %s(%d), %d from flag" % [club_name, from, hg.get_cell(from.x, from.y), aim, ctx.landing_tile, hg.get_cell(ctx.landing_tile.x, ctx.landing_tile.y), hg.hex_distance(ctx.landing_tile, hg.flag_position)])
			if club_name == "Putter" and ctx.landing_tile != hg.flag_position and hg.hex_distance(from, hg.flag_position) <= 1:
				var pl: Dictionary = ctx.get_metadata("shot_plan", {})
				print("      MISSED SHORT PUTT flag %s surface %d | plan end %s ring %s carry %s blocked %s | make %s | aoe %s weights %s" % [hg.flag_position, hg.get_cell(hg.flag_position.x, hg.flag_position.y), pl.get("end"), pl.get("ring"), pl.get("carry"), pl.get("blocked"), ctx.get_metadata("putt_make_chance", "-"), ctx.aoe_tiles, ctx.aoe_weights])
		var on_putt := func(result):
			fired[0] = true
			print("    Putt from %s -> %s, %d hexes, holed %s, off green %s" % [from, result.end, result.touched, result.holed, result.off_green])
		hg.shot_manager.shot_completed.connect(on_done)
		hg.putt_resolved.connect(on_putt)
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


func _read_the_green() -> void:
	"""A sensible putter: simulate every hex in reach; hole it if any route
	does (the longest route, for points), else leave it closest to the cup."""
	var board: GreenBoard = hg.green_board
	var ball: Vector2i = hg._ball_small()
	var best := Vector2i.ZERO
	var best_score := INF
	for a in board.tiles:
		var d := GreenBoard.distance(ball, a)
		if d == 0 or d > GreenBoard.PUTT_REACH:
			continue
		var r: Dictionary = board.roll(ball, a)
		var score: float
		if r.holed:
			score = -100.0 - r.touched
		elif r.off_green:
			score = 50.0
		else:
			score = GreenBoard.distance(r.end, board.cup)
		if score < best_score:
			best_score = score
			best = a
	if best_score < INF:
		hg.set_putt_target(best)


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
