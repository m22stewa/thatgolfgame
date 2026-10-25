extends Node

## test_green_board.gd - Headless harness for GreenBoard: small-hex geometry
## lines up with the course, greens are mostly flat with a few slopes, the
## putting rules of design/claude/design_handoff_putting (pace, cup, slopes,
## slick, spikes, fringe, lip out / sweet spot, the preview) and the putting
## deck.
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
	_test_slopes()
	_test_features()
	_test_preview()
	_test_modifier_deck()
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
	var sparse := true
	var clean := true
	var with_slick := 0
	var dirs_total := 0
	for seed in range(40):
		var g := GreenBoard.new()
		var r := RandomNumberGenerator.new()
		r.seed = seed
		g.build(hole, r)
		styles[g.style] = true
		var n := g.slope_count()
		if n < GreenBoard.SLOPES_MIN or n > GreenBoard.SLOPES_MAX:
			sparse = false
		var dirs := {}
		var slick := false
		for a in g.tiles:
			var t: Dictionary = g.tiles[a]
			slick = slick or g.is_slick(a)
			if t.strength > 0:
				dirs[t.dir] = true
				if t.strength > 3 or a == g.cup or g.is_slick(a) or g.features.get(a, {}).get("kind", "") == "spike":
					clean = false
			if g.is_slick(a) and GreenBoard.distance(a, g.cup) < 2:
				clean = false
		dirs_total += dirs.size()
		if slick:
			with_slick += 1
	_check(styles.size() == 4, "greens come in all four styles %s" % str(styles.keys()))
	_check(sparse, "every green has %d-%d slopes" % [GreenBoard.SLOPES_MIN, GreenBoard.SLOPES_MAX])
	_check(clean, "slopes are strength 1-3 and never on the cup, a slick hex or spike marks")
	_check(with_slick >= 30, "greens have slick patches (%d of 40)" % with_slick)
	_check(float(dirs_total) / 40.0 >= 3.0, "slopes fall several ways (%.1f directions a green)" % (float(dirs_total) / 40.0))


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


func _slope(b: GreenBoard, a: Vector2i, dir: int, strength: int) -> void:
	b.tiles[a].dir = dir
	b.tiles[a].strength = strength


func _test_putts() -> void:
	print("-- pace and the cup --")
	var b := _flat_board(5)
	var start := Vector2i(-3, 0)  # 3 hexes west of the cup; DIRS[1] is east
	var still := b.simulate_putt(start, 1, 0)
	_check(still.end == start and still.reason == "short", "no pace: the ball doesn't move")
	var plain := b.simulate_putt(start, 1, 2)
	_check(not plain.holed and plain.end == Vector2i(-1, 0) and plain.touched == 2, "on a flat green a putt rolls its pace in hexes")
	_check(b.simulate_putt(start, 2, 2).end == start + GreenBoard.DIRS[2] * 2, "a putt leaves the hex in its direction")
	_check(b.simulate_putt(start, 1, 3).holed, "reaching the cup with 0 pace left: it drops")
	_check(b.simulate_putt(start, 1, 4).holed, "1 pace left at the cup: it still drops")
	var firm := b.simulate_putt(start, 1, 5)
	_check(not firm.holed and firm.end == Vector2i(2, 0) and firm.reason == "ran", "any firmer: it lips out and rolls on (%s)" % str(firm.end))
	var lip := b.simulate_putt(start, 1, 3, "lip")
	_check(not lip.holed and lip.end == Vector2i(-1, 0) and lip.reason == "lipout", "Lip out: it hangs on the edge, a hex short")
	_check(b.simulate_putt(start, 1, 6, "star").holed, "Sweet spot: drops at any pace")
	_check(b.simulate_putt(start, 1, 2, "star").holed, "Sweet spot: drops from a hex beside the cup")
	var edge := _flat_board(2)
	edge.cup = Vector2i(0, 2)
	var fringe := edge.simulate_putt(Vector2i(0, 0), 1, 5)
	_check(fringe.end == Vector2i(2, 0) and fringe.reason == "fringe", "off the green it stops on the last green hex (%s)" % str(fringe.end))
	_check(GreenBoard.par_for(Vector2i(-4, 0), Vector2i.ZERO) == 2 and GreenBoard.par_for(Vector2i(-5, 0), Vector2i.ZERO) == 3, "par 2 within 4 hexes, else 3")


func _test_slopes() -> void:
	print("-- slopes and slick --")
	var start := Vector2i(-3, 0)
	var down := _flat_board(5)
	_slope(down, Vector2i(-2, 0), 1, 3)  # falls east, the way the putt goes
	_check(down.simulate_putt(start, 1, 1).holed, "downhill adds strength - 1 pace (1 pace reaches the cup)")
	_check(not down.simulate_putt(start, 1, 1, "", {"steady": true}).holed, "Steady: the slopes don't act")
	var up := _flat_board(5)
	_slope(up, Vector2i(-2, 0), 4, 2)  # falls west, against the putt
	_check(up.simulate_putt(start, 1, 3).end == Vector2i(-1, 0), "uphill takes strength - 1 pace")
	var side := _flat_board(5)
	_slope(side, Vector2i(-2, 0), 2, 2)  # falls south-ish (DIRS[2]), across the line
	var bent := side.simulate_putt(start, 1, 3)
	_check(bent.end == Vector2i(-2, 2), "across a slope the ball turns 60 degrees toward the fall line (%s)" % str(bent.end))
	var gentle := _flat_board(5)
	_slope(gentle, Vector2i(-2, 0), 2, 1)
	_check(gentle.simulate_putt(start, 1, 5).end == Vector2i(2, 0), "a strength-1 slope doesn't bend a quick ball")
	_check(gentle.simulate_putt(start, 1, 3).end == Vector2i(-2, 2), "... but bends a slow one (pace 2 or less)")
	_check(gentle.simulate_putt(start, 1, 5, "", {"slow_break": false}).end != Vector2i(2, 0), "slow-ball break off: it always bends")
	var ice := _flat_board(5)
	ice.tiles[Vector2i(-2, 0)].slick = true
	_check(ice.simulate_putt(start, 1, 2).holed, "slick adds 1 pace")


func _test_features() -> void:
	print("-- green features --")
	var start := Vector2i(-4, 0)
	var b := _flat_board(5)
	b.features[Vector2i(-2, 0)] = {"kind": "coin"}
	var coin := b.simulate_putt(start, 1, 3)
	_check(coin.coins == [Vector2i(-2, 0)] and coin.end == Vector2i(-1, 0), "rolling over a coin collects it and carries on")
	var s := _flat_board(5)
	s.features[Vector2i(-2, 0)] = {"kind": "spike"}
	var spiked := s.simulate_putt(start, 1, 4)
	_check(spiked.reason == "spike" and spiked.end == Vector2i(-2, 0), "spike marks stop the ball dead")
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
	_check(kinds.has("spike") and kinds.has("coin") and not near_cup and not kinds.has("putter"), "a built green has spikes and coins, none next to the cup %s" % str(kinds.keys()))


func _test_preview() -> void:
	print("-- the read --")
	var b := _flat_board(5)
	var read := b.preview(Vector2i(-3, 0), 1)
	var holed_totals: Array = []
	var covered := 0
	for m in read.marks:
		covered += m.totals.size()
		if m.holed:
			holed_totals.append_array(m.totals)
	_check(covered == GreenBoard.PREVIEW_TOTALS + 1, "every pace 0-%d is labelled once" % GreenBoard.PREVIEW_TOTALS)
	holed_totals.sort()
	_check(holed_totals == [3, 4], "the cup's label holds the paces that drop (%s)" % str(holed_totals))
	_check(read.base.size() == GreenBoard.PUTT_BASE + 1 and read.long.size() > read.base.size(), "base and long lines are drawn")
	var odds := PuttModifierDeck.chain_odds(PuttModifierDeck.starter_ids())
	var p := b.one_putt_chance(Vector2i(-3, 0), odds)
	_check(p > 0.2 and p < 0.6, "one-putt chance from 3 hexes on a flat green is fair (%.2f)" % p)


func _test_modifier_deck() -> void:
	print("-- putting deck --")
	var deck := PuttModifierDeck.new(11)
	_check(deck.size() == 20 and deck.draw_pile.size() == 20, "the starter deck holds 20 cards")
	var odds := PuttModifierDeck.chain_odds(PuttModifierDeck.starter_ids())
	var sum := 0.0
	for o in odds:
		sum += o.p
	_check(absf(sum - 1.0) < 0.0001, "flip odds add up to 1 (%.4f)" % sum)
	var chained := false
	var shuffled := false
	var counts_ok := true
	for i in range(200):
		var top := deck.peek()
		var f := deck.flip()
		if f.cards[0] != top:
			counts_ok = false  # Caddie Peek shows the card the next putt flips
		if f.total != GreenBoard.PUTT_BASE + f.mod:
			counts_ok = false
		var last: Dictionary = PuttModifierDeck.card(f.cards[f.cards.size() - 1])
		if last.get("rolling", false):
			counts_ok = false  # a flip never ends on a rolling card
		if f.cards.size() > 1:
			chained = true
		if f.special != "" and deck.discard.is_empty() and deck.draw_pile.size() == 20:
			shuffled = true
		if deck.size() != 20:
			counts_ok = false
	_check(chained, "rolling cards chain into another flip")
	_check(shuffled, "Lip out / Sweet spot shuffle the discards back in")
	_check(counts_ok, "peek matches the next flip, pace is 2 + the cards, no card is lost")
	_check(PuttModifierDeck.describe({"cards": ["rolling_1", "minus_1"], "total": 2}) == "2 + 1 − 1 = 2", "the sum is pencilled in")
	var a := PuttModifierDeck.new(5)
	var b := PuttModifierDeck.new(5)
	_check(a.draw_pile == b.draw_pile, "same seed, same deck order")
	a.add("plus_3")
	_check(a.size() == 21 and a.remove("plus_3") and not a.remove("plus_3"), "the shop can add and remove cards")
	var cursed := PuttModifierDeck.new(3)
	cursed.draw_pile.append("yips")
	var y := cursed.flip()
	_check(y.mod == -3 and not cursed.discard.has("yips") and not cursed.draw_pile.has("yips"), "Yips is -3 and leaves the deck once drawn")


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)
