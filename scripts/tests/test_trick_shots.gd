extends Node

## test_trick_shots.gd - Headless harness for TrickShotDetector: each trick
## fires on a hand-built board, the fairway streak feeds the mult, and plain
## shots score nothing. Exits 0 on success, 1 on any failed assertion.

const FAIRWAY := 1
const ROUGH := 2
const DEEP_ROUGH := 3
const GREEN := 4
const SAND := 5
const WATER := 6
const TREE := 7
const FLAG := 8

var _failures: int = 0
var _checks: int = 0


## Minimal hole: a column-major surface grid + flag_position.
class StubHole extends RefCounted:
	var w := 9
	var h := 30
	var grid: Array = []
	var flag_position := Vector2i(4, 28)

	func _init() -> void:
		for c in range(w):
			var col: Array = []
			col.resize(h)
			col.fill(1)  # FAIRWAY
			grid.append(col)

	func get_cell(col: int, row: int) -> int:
		if col >= 0 and col < w and row >= 0 and row < h:
			return grid[col][row]
		return -1

	func set_cell(col: int, row: int, surface: int) -> void:
		grid[col][row] = surface


func _ready() -> void:
	print("=== trick shot test ===")
	_test_plain_shot()
	_test_water_carry()
	_test_bunker_blast_and_stuck_green()
	_test_great_escape()
	_test_pin_seeker()
	_test_streak_mult()
	_test_hole_out()
	_test_hex_line()
	print("=== trick shot test complete: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _detector() -> Array:
	var hole := StubHole.new()
	var det := TrickShotDetector.new()
	det.hole = hole
	return [det, hole]


func _shot(det: TrickShotDetector, start: Vector2i, landing: Vector2i) -> ShotContext:
	var ctx := ShotContext.new()
	ctx.start_tile = start
	ctx.landing_tile = landing
	det.score_shot(ctx)
	ctx.calculate_final_score()
	return ctx


func _ids(ctx: ShotContext) -> Array:
	var ids: Array = []
	for t in ctx.get_metadata("tricks", []):
		ids.append(t.id)
	return ids


func _test_plain_shot() -> void:
	print("-- plain shot --")
	var p := _detector()
	var ctx := _shot(p[0], Vector2i(4, 2), Vector2i(4, 8))
	_check(_ids(ctx).is_empty() and ctx.final_score == 0, "fairway-to-fairway shot earns 0 pts (got %d)" % ctx.final_score)


func _test_water_carry() -> void:
	print("-- over the water --")
	var p := _detector()
	var hole: StubHole = p[1]
	hole.set_cell(4, 5, WATER)
	var ctx := _shot(p[0], Vector2i(4, 2), Vector2i(4, 8))
	_check(_ids(ctx).has("water_carry"), "carrying a water hex scores Over the Water %s" % str(_ids(ctx)))
	var wet := _shot(p[0], Vector2i(4, 2), Vector2i(4, 5))
	_check(not _ids(wet).has("water_carry"), "landing IN the water is not a carry")
	var side := _shot(p[0], Vector2i(2, 2), Vector2i(2, 8))
	_check(not _ids(side).has("water_carry"), "a line that misses the water is not a carry")


func _test_bunker_blast_and_stuck_green() -> void:
	print("-- bunker blast / stuck the green --")
	var p := _detector()
	var hole: StubHole = p[1]
	hole.set_cell(4, 10, SAND)
	hole.set_cell(4, 14, GREEN)
	var short := _shot(p[0], Vector2i(4, 10), Vector2i(4, 14))
	_check(_ids(short).has("bunker_blast"), "sand -> green scores Bunker Blast")
	_check(not _ids(short).has("stuck_green"), "a 4-hex bunker shot is too short for Stuck the Green")
	hole.set_cell(4, 2, ROUGH)
	var approach := _shot(p[0], Vector2i(4, 2), Vector2i(4, 14))
	_check(_ids(approach).has("stuck_green"), "12-hex approach onto the green scores Stuck the Green")


func _test_great_escape() -> void:
	print("-- great escape --")
	var p := _detector()
	var hole: StubHole = p[1]
	hole.set_cell(3, 6, TREE)
	hole.set_cell(5, 6, DEEP_ROUGH)
	_check(_ids(_shot(p[0], Vector2i(3, 6), Vector2i(3, 10))).has("great_escape"), "trees -> fairway scores Great Escape")
	_check(_ids(_shot(p[0], Vector2i(5, 6), Vector2i(5, 10))).has("great_escape"), "deep rough -> fairway scores Great Escape")
	hole.set_cell(3, 10, ROUGH)
	_check(not _ids(_shot(p[0], Vector2i(3, 6), Vector2i(3, 10))).has("great_escape"), "trees -> rough is no escape")


func _test_pin_seeker() -> void:
	print("-- pin seeker --")
	var p := _detector()
	var near := _shot(p[0], Vector2i(4, 18), Vector2i(4, 27))
	_check(_ids(near).has("pin_seeker"), "finishing 1 hex from the flag from 10 away scores Pin Seeker")
	var tap := _shot(p[0], Vector2i(4, 25), Vector2i(4, 27))
	_check(not _ids(tap).has("pin_seeker"), "a short tap-up from 3 hexes is not Pin Seeker")


func _test_streak_mult() -> void:
	print("-- fairway streak mult --")
	var p := _detector()
	var det: TrickShotDetector = p[0]
	var hole: StubHole = p[1]
	hole.set_cell(4, 5, WATER)
	_shot(det, Vector2i(4, 0), Vector2i(4, 3))          # streak 1
	_shot(det, Vector2i(4, 3), Vector2i(4, 4))          # streak 2
	var ctx := _shot(det, Vector2i(4, 4), Vector2i(4, 8))  # streak 3, water carry
	_check(is_equal_approx(ctx.mult, 2.0), "3rd fairway in a row -> mult 2.0 (got %.2f)" % ctx.mult)
	_check(ctx.final_score == 60, "Over the Water 30 x 2.0 = 60 (got %d)" % ctx.final_score)
	hole.set_cell(4, 12, ROUGH)
	_shot(det, Vector2i(4, 8), Vector2i(4, 12))         # rough breaks the streak
	_check(det.fairway_streak == 0, "landing in rough resets the streak")
	det.reset_hole()
	_check(det.fairway_streak == 0, "reset_hole clears the streak")


func _test_hole_out() -> void:
	print("-- hole-out tricks --")
	var p := _detector()
	var det: TrickShotDetector = p[0]
	var hole: StubHole = p[1]
	hole.set_cell(4, 25, GREEN)
	hole.set_cell(4, 27, GREEN)
	hole.set_cell(4, 20, ROUGH)
	_check(det.score_hole_out(Vector2i(4, 0), 1)[0].id == "hole_in_one", "holing the first stroke is a Hole in One")
	_check(det.score_hole_out(Vector2i(4, 20), 3)[0].id == "chip_in", "holing from off the green is a Chip-in")
	_check(det.score_hole_out(Vector2i(4, 25), 3)[0].id == "long_putt", "holing a 3-hex putt is a Long Putt")
	_check(det.score_hole_out(Vector2i(4, 27), 3).is_empty(), "a tap-in earns nothing")


func _test_hex_line() -> void:
	print("-- hex line --")
	var det := TrickShotDetector.new()
	var a := Vector2i(1, 3)
	var b := Vector2i(6, 11)
	var line := det.hex_line(a, b)
	_check(line[0] == a and line[line.size() - 1] == b, "line runs from start to end")
	var contiguous := true
	for i in range(1, line.size()):
		if det.hex_distance(line[i - 1], line[i]) != 1:
			contiguous = false
	_check(contiguous and line.size() == det.hex_distance(a, b) + 1, "line is contiguous with distance+1 hexes")


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)
