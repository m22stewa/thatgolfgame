extends Node

## test_green_board.gd - Headless harness for GreenBoard: small-hex geometry
## lines up with the course, every green gets a full range of arrows, and the
## putting rules (struck roll, arrow pushes, cup, off green, loops, reach).
## Exits 0 on success, 1 on any failure.

var _failures: int = 0
var _checks: int = 0


## Course stand-in with hex_grid's real geometry; a round green of radius 3.
class StubHole extends RefCounted:
	var grid_width := 16
	var grid_height := 20
	var flag_position := Vector2i(8, 10)
	var grid: Array = []

	func _init() -> void:
		for c in range(grid_width):
			var col: Array = []
			col.resize(grid_height)
			col.fill(1)
			grid.append(col)
		for x in range(grid_width):
			for y in range(grid_height):
				if _cube_dist(Vector2i(x, y), flag_position) <= 3:
					grid[x][y] = 4

	func get_cell(col: int, row: int) -> int:
		if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
			return grid[col][row]
		return -1

	func get_tile_world_position(cell: Vector2i) -> Vector3:
		var hh := sqrt(3.0)
		return Vector3(cell.x * 1.5, 0.0, cell.y * hh + (cell.x % 2) * (hh / 2.0))

	func world_to_grid(p: Vector3) -> Vector2i:
		var hh := sqrt(3.0)
		var col := roundi(p.x / 1.5)
		return Vector2i(col, roundi((p.z - (col % 2) * (hh / 2.0)) / hh))

	func _cube_dist(a: Vector2i, b: Vector2i) -> int:
		var az := a.y - (a.x - (a.x & 1)) / 2
		var bz := b.y - (b.x - (b.x & 1)) / 2
		return int((abs(a.x - b.x) + abs(az - bz) + abs((-a.x - az) - (-b.x - bz))) / 2)


func _ready() -> void:
	print("=== green board test ===")
	_test_geometry()
	_test_build()
	_test_putts()
	_test_features()
	print("=== green board test complete: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_geometry() -> void:
	print("-- geometry --")
	var hole := StubHole.new()
	var ok := true
	for cell in [Vector2i(0, 0), Vector2i(3, 5), Vector2i(8, 10), Vector2i(9, 10)]:
		var w: Vector3 = hole.get_tile_world_position(cell)
		var a := GreenBoard.from_course(cell)
		if GreenBoard.to_world(a).distance_to(Vector2(w.x, w.z)) > 0.001:
			ok = false
	_check(ok, "every course hex centre is a small hex centre")
	var a := Vector2i(5, -3)
	_check(GreenBoard.from_world(GreenBoard.to_world(a)) == a, "world <-> small hex round trip")
	_check(GreenBoard.to_world(a).distance_to(GreenBoard.to_world(a + GreenBoard.DIRS[0])) - GreenBoard.STEP < 0.001, "neighbours are STEP apart")
	var ln := GreenBoard.line(Vector2i(0, 0), Vector2i(4, -2))
	var contiguous := true
	for i in range(1, ln.size()):
		if GreenBoard.distance(ln[i - 1], ln[i]) != 1:
			contiguous = false
	_check(contiguous and ln.size() == 5, "lines are contiguous")


func _test_build() -> void:
	print("-- building a green --")
	var hole := StubHole.new()
	var board := GreenBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	board.build(hole, rng)
	var greens := 37  # course hexes within 3 of the flag
	_check(board.tiles.size() >= greens * 3 and board.tiles.size() <= greens * 5, "about four small hexes per green hex (%d for %d)" % [board.tiles.size(), greens])
	_check(board.tiles.has(board.cup) and board.tiles[board.cup].strength == 0, "the cup is on the board and flat")
	var counts := [0, 0, 0, 0]
	for t in board.tiles.values():
		counts[t.strength] += 1
	_check(counts[0] > 0 and counts[1] > 0 and counts[2] > 0 and counts[3] > 0, "every arrow strength appears %s" % str(counts))
	var again := GreenBoard.new()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	again.build(hole, rng2)
	var same := true
	for a in board.tiles:
		if not again.tiles.has(a) or again.tiles[a].dir != board.tiles[a].dir or again.tiles[a].strength != board.tiles[a].strength:
			same = false
	_check(same, "same seed, same green")
	var styles := {}
	for seed in range(40):
		var g := GreenBoard.new()
		var r := RandomNumberGenerator.new()
		r.seed = seed
		g.build(hole, r)
		styles[g.style] = true
	_check(styles.size() == 4, "greens come in all four styles %s" % str(styles.keys()))


func _flat_board(radius: int) -> GreenBoard:
	"""Hand-built round board, all flat, cup at the origin."""
	var b := GreenBoard.new()
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var a := Vector2i(q, r)
			if GreenBoard.distance(a, Vector2i.ZERO) <= radius:
				b.tiles[a] = {"height": 0.0, "dir": 0, "strength": 0}
	b.cup = Vector2i.ZERO
	return b


func _test_putts() -> void:
	print("-- putting --")
	var b := _flat_board(5)
	var start := Vector2i(-3, 0)

	var plain := b.roll(start, Vector2i(-1, 0))
	_check(not plain.holed and plain.end == Vector2i(-1, 0) and plain.touched == 2, "on a flat green the ball stops where it's struck")

	var straight := b.roll(start, Vector2i(0, 0))
	_check(not straight.holed and straight.end == Vector2i(-1, 0), "aiming at the cup from 3 stops just short (got %s)" % str(straight.end))
	var through := b.roll(start, Vector2i(2, 0))
	_check(not through.holed and through.end == Vector2i(2, 0), "a struck ball rolls over the cup")
	var tap := b.roll(Vector2i(-1, 0), Vector2i(0, 0))
	_check(tap.holed and tap.touched == 1, "a 1-hex tap-in drops")

	# Arrows: land on (-1,0), which pushes 2 east (DIRS[1] = (1,0)) -> (1,0); that pushes 1 west -> (0,0) = cup
	b.tiles[Vector2i(-1, 0)].dir = 1
	b.tiles[Vector2i(-1, 0)].strength = 2
	b.tiles[Vector2i(1, 0)].dir = 4
	b.tiles[Vector2i(1, 0)].strength = 1
	var chain := b.roll(start, Vector2i(-1, 0))
	_check(chain.holed, "arrows carry the ball on and it rolls into the cup")
	_check(chain.path == [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0)], "the push runs through the cup and drops (path %s)" % str(chain.path))

	# A longer trick route around the cup: north, east, then south into the cup
	var trick := _flat_board(5)
	trick.tiles[Vector2i(-2, 0)].dir = 5   # (0,-1)
	trick.tiles[Vector2i(-2, 0)].strength = 2
	trick.tiles[Vector2i(-2, -2)].dir = 1  # (1,0)
	trick.tiles[Vector2i(-2, -2)].strength = 2
	trick.tiles[Vector2i(0, -2)].dir = 2   # (0,1)
	trick.tiles[Vector2i(0, -2)].strength = 3
	var route := trick.roll(start, Vector2i(-2, 0))
	_check(route.holed and route.touched == 7, "a planned route around the green holes it touching 7 hexes (got %s, %d)" % [route.holed, route.touched])

	var edge := _flat_board(2)
	edge.cup = Vector2i(0, 2)  # out of the way of this putt
	edge.tiles[Vector2i(-1, 0)].dir = 4
	edge.tiles[Vector2i(-1, 0)].strength = 3
	var off := edge.roll(Vector2i(1, 0), Vector2i(-1, 0))
	_check(off.off_green and not edge.tiles.has(off.end), "an arrow can run the ball off the green")

	var loop := _flat_board(4)
	loop.tiles[Vector2i(-2, 0)].dir = 1
	loop.tiles[Vector2i(-2, 0)].strength = 1
	loop.tiles[Vector2i(-1, 0)].dir = 4
	loop.tiles[Vector2i(-1, 0)].strength = 1
	var settled := loop.roll(Vector2i(-3, 0), Vector2i(-2, 0))
	_check(not settled.holed and not settled.off_green and settled.path.size() < 12, "a loop settles instead of rolling forever (%d moves)" % settled.path.size())

	var far := _flat_board(8)
	var clamped := far.roll(Vector2i(-8, 0), Vector2i(8, 0))
	_check(GreenBoard.distance(Vector2i(-8, 0), clamped.end) == GreenBoard.PUTT_REACH, "a putt is struck at most %d hexes" % GreenBoard.PUTT_REACH)


func _test_features() -> void:
	print("-- green features --")
	var b := _flat_board(5)
	var start := Vector2i(-4, 0)

	b.features[Vector2i(-2, 0)] = {"kind": "coin", "dir": 0}
	var coin := b.roll(start, Vector2i(-1, 0))
	_check(coin.coins == [Vector2i(-2, 0)] and coin.end == Vector2i(-1, 0), "rolling over a coin collects it and carries on")

	var s := _flat_board(5)
	s.features[Vector2i(-2, 0)] = {"kind": "spike", "dir": 0}
	var spiked := s.roll(start, Vector2i(0, 0))
	_check(spiked.spiked and spiked.end == Vector2i(-2, 0), "spike marks stop the ball dead")

	var p := _flat_board(5)
	p.features[Vector2i(-1, 0)] = {"kind": "putter", "dir": 2}
	p.features[Vector2i(-1, 1)] = {"kind": "putter", "dir": 2}
	var bounce := p.roll(start, Vector2i(0, 0))  # stops short of the cup at (-1,0)... blocked by the putter
	_check(bounce.banked and bounce.end.x < -2, "a struck ball bounces off the putter and rolls back (%s)" % str(bounce.end))

	var bank := _flat_board(5)
	bank.features[Vector2i(1, 0)] = {"kind": "putter", "dir": 2}
	bank.features[Vector2i(1, 1)] = {"kind": "putter", "dir": 2}
	bank.tiles[Vector2i(-1, 0)].dir = 1      # push east x3: (0,0) is the cup on the first step
	bank.tiles[Vector2i(-1, 0)].strength = 3
	bank.cup = Vector2i(-2, 0)               # cup behind: only a bank can reach it
	var banked := bank.roll(Vector2i(-1, -1), Vector2i(-1, 0))
	_check(banked.banked and banked.holed, "an arrow push banks off the putter back into the cup (%s)" % str(banked.path))

	var dead := _flat_board(5)
	dead.tiles[Vector2i(-2, 0)].dir = 1
	dead.tiles[Vector2i(-2, 0)].strength = 2
	_check(dead.roll(start, Vector2i(-2, 0), {"dead_weight": true}).end == Vector2i(-2, 0), "Dead Weight: the green doesn't push the ball")
	var far := _flat_board(9)
	_check(GreenBoard.distance(Vector2i(-9, 0), far.roll(Vector2i(-9, 0), Vector2i(9, 0), {"reach": 8}).end) == 8, "Firm Putt: reach 8")

	var hole := StubHole.new()
	var built := GreenBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	built.build(hole, rng)
	var kinds := {}
	var near_cup := false
	for a in built.features:
		kinds[built.features[a].kind] = true
		if GreenBoard.distance(a, built.cup) < 2:
			near_cup = true
	_check(kinds.has("spike") and kinds.has("coin") and not near_cup, "a built green has spikes and coins, none next to the cup %s" % str(kinds.keys()))


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)
