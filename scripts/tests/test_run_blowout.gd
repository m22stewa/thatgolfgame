extends Node

## test_run_blowout.gd - Headless harness for the run "blowout" rule:
## the run ends the moment the live score vs par reaches RunStateManager.blowout_limit.
## Exits 0 on success, 1 on any failed assertion.

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	print("=== run blowout test ===")
	_test_live_vs_par()
	_test_blowout_mid_hole()
	_test_blowout_on_hole_out()
	_test_adjust_score()
	_test_new_run_resets()
	print("=== run blowout test complete: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _new_run() -> RunStateManager:
	var rs := RunStateManager.new()
	add_child(rs)
	rs.start_new_run(9)
	return rs


func _play_hole(rs: RunStateManager, par: int, strokes: int) -> void:
	rs.start_hole(par, 400)
	for i in range(strokes):
		rs.record_stroke(0)
	rs.complete_hole()
	rs.advance_to_next_hole()


func _test_live_vs_par() -> void:
	print("-- live vs par --")
	var rs := _new_run()
	_check(rs.get_live_vs_par() == 0, "fresh run is E")
	_play_hole(rs, 4, 6)
	_check(rs.get_live_vs_par() == 2, "double bogey -> +2 (got %d)" % rs.get_live_vs_par())
	rs.start_hole(4, 400)
	for i in range(3):
		rs.record_stroke(0)
	_check(rs.get_live_vs_par() == 2, "3 strokes mid par-4 does not count as birdie yet (got %d)" % rs.get_live_vs_par())
	rs.record_stroke(0)
	rs.record_stroke(0)
	_check(rs.get_live_vs_par() == 3, "5th stroke on a par 4 counts immediately -> +3 (got %d)" % rs.get_live_vs_par())
	_check(rs.format_vs_par(0) == "E" and rs.format_vs_par(3) == "+3" and rs.format_vs_par(-2) == "-2", "golf-style formatting E/+3/-2")
	rs.queue_free()


func _test_blowout_mid_hole() -> void:
	print("-- blowout mid hole --")
	var rs := _new_run()
	var fired := [0]
	rs.run_blown_out.connect(func(_v): fired[0] += 1)
	_play_hole(rs, 4, 9)  # +5
	_check(not rs.is_blown_out, "+5 is still alive")
	rs.start_hole(3, 150)
	for i in range(5):
		rs.record_stroke(0)  # par 3: strokes 4,5 push to +7
	_check(not rs.is_blown_out and rs.get_live_vs_par() == 7, "+7 still alive (got %d)" % rs.get_live_vs_par())
	_check(rs.get_strokes_until_blowout() == 1, "one stroke of margin left")
	rs.record_stroke(0)  # +8
	_check(rs.is_blown_out, "reaching +8 blows out the run")
	_check(not rs.is_run_active, "run is no longer active")
	_check(fired[0] == 1, "run_blown_out emitted exactly once (got %d)" % fired[0])
	rs.record_stroke(0)
	_check(fired[0] == 1, "no repeat emit after blowout")
	rs.queue_free()


func _test_blowout_on_hole_out() -> void:
	print("-- blowout on the holing stroke --")
	var rs := _new_run()
	_play_hole(rs, 4, 11)  # +7
	_check(not rs.is_blown_out, "+7 after hole 1 still alive")
	rs.start_hole(4, 400)
	for i in range(5):
		rs.record_stroke(0)
	_check(rs.is_blown_out, "bogey on next hole reaches +8 even though it holes out")
	rs.queue_free()


func _test_adjust_score() -> void:
	print("-- item score adjustment seam --")
	var rs := _new_run()
	_play_hole(rs, 4, 10)  # +6
	rs.adjust_score(-1, "test item")
	_check(rs.get_live_vs_par() == 5, "adjust_score(-1) lowers run score to +5 (got %d)" % rs.get_live_vs_par())
	rs.adjust_score(3, "test curse")
	_check(rs.is_blown_out, "adjust_score(+3) to +8 blows out")
	rs.queue_free()


func _test_new_run_resets() -> void:
	print("-- new run resets --")
	var rs := _new_run()
	_play_hole(rs, 4, 12)
	_check(rs.is_blown_out, "setup: blown out")
	rs.start_new_run(9)
	_check(not rs.is_blown_out and rs.is_run_active and rs.get_live_vs_par() == 0, "start_new_run clears blowout and score")
	rs.queue_free()


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)
