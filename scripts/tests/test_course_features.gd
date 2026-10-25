extends Node

## test_course_features.gd - Headless harness for course features: placement,
## fire spreading and burning out, and how TurnController's roll-out treats
## ice, fire, wind gusts and trampolines. Exits 0 on success, 1 on any failure.

const FAIRWAY := 1
const ROUGH := 2
const TREE := 7

var _failures: int = 0
var _checks: int = 0


## Course stand-in: all fairway, flag far away, real odd-q neighbours.
class StubHole extends Node3D:
	var grid_width := 12
	var grid_height := 30
	var flag_position := Vector2i(6, 28)
	var current_par := 4
	var grid: Array = []

	func _init() -> void:
		for c in range(grid_width):
			var col: Array = []
			col.resize(grid_height)
			col.fill(1)
			grid.append(col)

	func get_cell(col: int, row: int) -> int:
		if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
			return grid[col][row]
		return -1

	func get_grid_width() -> int:
		return grid_width

	func get_grid_height() -> int:
		return grid_height

	func get_elevation(_c: int, _r: int) -> float:
		return 0.0

	func get_tile_world_position(cell: Vector2i) -> Vector3:
		var hh := sqrt(3.0)
		return Vector3(cell.x * 1.5, 0.0, cell.y * hh + (cell.x % 2) * (hh / 2.0))

	func get_adjacent_cells(col: int, row: int) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		var odd := col % 2 == 1
		var offs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)] if odd \
			else [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
		for o in offs:
			var n: Vector2i = Vector2i(col, row) + o
			if get_cell(n.x, n.y) >= 0:
				out.append(n)
		return out


var hole: StubHole
var aoe: AOESystem
var tc: TurnController
var wind: WindSystem


func _ready() -> void:
	print("=== course features test ===")
	hole = StubHole.new()
	add_child(hole)
	aoe = AOESystem.new()
	add_child(aoe)
	tc = TurnController.new()
	add_child(tc)
	tc.aoe_system = aoe
	tc.hex_grid = hole
	tc.course_features = CourseFeatures.new()
	wind = WindSystem.new()
	add_child(wind)
	tc.wind_system = wind

	_test_ice()
	_test_fire_penalty()
	_test_fire_spread()
	_test_tunnel()
	_test_trampoline()
	_test_placement()
	_test_spin()
	_test_card_costs()
	print("=== course features test complete: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _roll(landing: Vector2i, base_roll: int, meta: Dictionary = {}, roll_mod: int = 0) -> ShotContext:
	"""Resolve a roll-out straight down column 4 (hex direction 3 = +row)."""
	var ctx := ShotContext.new()
	ctx.add_metadata("footprint_built", true)
	for k in meta:
		ctx.add_metadata(k, meta[k])
	ctx.landing_tile = landing
	ctx.base_roll = base_roll
	ctx.roll_mod = roll_mod
	ctx.aim_dir = 3
	tc.apply_board_resolution(ctx)
	return ctx


func _test_spin() -> void:
	print("-- spin --")
	tc.course_features.tiles.clear()
	_check(_roll(Vector2i(4, 10), 2, {"spin_back": 1}).landing_tile == Vector2i(4, 9), "backspin 1: spins back one hex toward the golfer, no roll on")
	_check(_roll(Vector2i(4, 10), 2, {"spin_back": 3}).landing_tile == Vector2i(4, 7), "Zip Back: spins back 3 hexes")
	hole.grid[4][10] = ROUGH
	_check(_roll(Vector2i(4, 10), 2, {"spin_back": 1}).landing_tile == Vector2i(4, 10), "rough grabs a 1-hex backspin: it stays put")
	_check(_roll(Vector2i(4, 10), 1, {}, 3).landing_tile == Vector2i(4, 13), "without topspin the rough takes a hex off (+3 roll from rough: 3 hexes)")
	_check(_roll(Vector2i(4, 10), 1, {"topspin": true}, 3).landing_tile == Vector2i(4, 14), "topspin: the rough doesn't slow it (4 hexes)")
	hole.grid[4][10] = FAIRWAY


func _test_card_costs() -> void:
	"""Every playable card costs 1-6 Chips; upgrades never take it below 1.
	(Green cards aren't played: they change the putting deck when bought.)"""
	print("-- card costs --")
	var lib := CardLibrary.new()
	add_child(lib)
	var bad: Array = []
	for id in RunShop.POOL:
		var data: CardData = lib.get_card(id)
		if data and RunShop.is_green_card(data):
			continue
		var cost := CardCost.of(data) if data else -1
		if cost < CardCost.MIN or cost > CardCost.MAX:
			bad.append("%s=%d" % [id, cost])
	_check(bad.is_empty(), "every shop card costs 1-6 Chips %s" % str(bad))
	var draw := CardInstance.create_from_data(lib.get_card("draw_shot"))
	_check(not RunShop.can_upgrade(draw), "a 1-Chip card can't be upgraded")
	var zip := CardInstance.create_from_data(lib.get_card("zip_back"))
	zip.upgrade_level = 10
	_check(CardCost.of(zip.data, zip.upgrade_level) == CardCost.MIN, "upgrades stop at 1 Chip")
	zip.upgrade_level = 1
	_check(RunShop.upgrade_price(zip) > RunShop.UPGRADE_PRICE, "each upgrade costs more than the last")


func _test_ice() -> void:
	print("-- ice --")
	var f: CourseFeatures = tc.course_features
	f.tiles.clear()
	_check(_roll(Vector2i(4, 5), 1).landing_tile == Vector2i(4, 6), "no ice: roll 1 moves one hex")
	f.tiles[Vector2i(4, 5)] = {"kind": "ice", "dir": 0, "age": 0}
	_check(_roll(Vector2i(4, 5), 1).landing_tile == Vector2i(4, 8), "landing on ice skids +2 (roll 1 -> 3 hexes)")
	f.tiles.clear()
	for r in [6, 7, 8]:
		f.tiles[Vector2i(4, r)] = {"kind": "ice", "dir": 0, "age": 0}
	var run := _roll(Vector2i(4, 5), 2)
	_check(run.landing_tile == Vector2i(4, 10), "crossing 3 ice hexes costs no roll (roll 2 -> 5 hexes, at %s)" % str(run.landing_tile))
	_check(run.has_metadata("ice_run"), "3+ ice hexes rolled over is an Ice Run")


func _test_fire_penalty() -> void:
	print("-- fire --")
	var f: CourseFeatures = tc.course_features
	f.tiles.clear()
	f.tiles[Vector2i(4, 6)] = {"kind": "fire", "dir": 0, "age": 0}
	_check(_roll(Vector2i(4, 5), 1).get_metadata("hit_fire", false), "a ball ending in fire is a fire penalty")
	_check(_roll(Vector2i(4, 5), 2).get_metadata("hit_fire", false), "rolling through fire costs too")
	f.tiles.clear()
	_check(not _roll(Vector2i(4, 5), 2).get_metadata("hit_fire", false), "no fire on the way, no cost")


func _test_fire_spread() -> void:
	print("-- fire spreading --")
	var f := CourseFeatures.new()
	for r in range(0, 30):
		hole.grid[3][r] = ROUGH
		hole.grid[4][r] = ROUGH
	f.tiles[Vector2i(4, 10)] = {"kind": "fire", "dir": 0, "age": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var max_fire := 1
	var only_rough := true
	for turn in range(12):
		f.spread_fire(hole, rng)
		max_fire = maxi(max_fire, f.count("fire"))
		for cell in f.tiles:
			if f.tiles[cell].kind == "fire" and hole.get_cell(cell.x, cell.y) != ROUGH:
				only_rough = false
	_check(max_fire > 1, "fire spreads (up to %d burning)" % max_fire)
	_check(only_rough, "fire only catches rough / deep rough / trees")
	_check(f.count("scorched") > 0, "burnt-out fire leaves scorched ground (%d)" % f.count("scorched"))
	_check(f.count("fire") <= CourseFeatures.FIRE_MAX_BURNING, "fire stays within its cap")

	# Wind: fire only spreads downwind (here toward +z, down the rows)
	var down := true
	var spread_any := false
	for seed in range(10):
		var g := CourseFeatures.new()
		var start := Vector2i(4, 10)
		g.tiles[start] = {"kind": "fire", "dir": 0, "age": 0}
		var r := RandomNumberGenerator.new()
		r.seed = seed
		for i in range(4):
			g.spread_fire(hole, r, 1, Vector2(0, 1), 2)
		for cell in g.tiles:
			if cell != start and g.tiles[cell].kind in ["fire", "scorched"]:
				spread_any = true
				if cell.y < start.y:
					down = false
	_check(spread_any, "wind still spreads fire")
	_check(down, "fire only spreads downwind")

	# Later strokes: the same fire spreads further when the hole drags on
	var calm := _burn(func(_t): return 1)
	var late := _burn(func(t): return t + 1)
	_check(late > calm, "fire spreads more the longer the hole goes (%d burning late vs %d)" % [late, calm])
	for r in range(0, 30):
		hole.grid[3][r] = FAIRWAY
		hole.grid[4][r] = FAIRWAY


func _burn(turn_of: Callable) -> int:
	"""Hexes that have burned after 6 strokes from one fire in a strip of rough,
	averaged over 10 seeds. turn_of(i) = the stroke number passed for step i."""
	var total := 0
	for seed in range(10):
		var f := CourseFeatures.new()
		f.tiles[Vector2i(4, 10)] = {"kind": "fire", "dir": 0, "age": 0}
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		for i in range(6):
			f.spread_fire(hole, rng, turn_of.call(i))
		total += f.count("fire") + f.count("scorched")
	return total / 10


func _test_tunnel() -> void:
	print("-- wind tunnel --")
	var f: CourseFeatures = tc.course_features
	f.tiles.clear()
	# A tunnel along column 4 pointing up (dir 0), rows 8-10
	for r in [8, 9, 10]:
		f.tiles[Vector2i(4, r)] = {"kind": "tunnel", "dir": 0, "age": 0, "group": Vector2i(4, 10)}
	wind.strength = 0
	_check(_roll(Vector2i(4, 9), 3).landing_tile == Vector2i(4, 8), "landing in a calm tunnel: pushed 1 along it, roll ends")
	wind.strength = 3
	_check(_roll(Vector2i(4, 9), 3).landing_tile == Vector2i(4, 5), "wind 3: pushed 4 hexes along it")
	wind.strength = 1
	var c := _roll(Vector2i(4, 6), 4)
	_check(c.landing_tile == Vector2i(4, 6), "rolling into the tunnel pushes it back up (at %s)" % str(c.landing_tile))
	hole.grid[4][6] = TREE
	_check(_roll(Vector2i(4, 9), 3).landing_tile == Vector2i(4, 7), "a tunnel push stops short of a tree")
	hole.grid[4][6] = FAIRWAY
	wind.strength = 0


func _test_trampoline() -> void:
	print("-- trampoline --")
	var f: CourseFeatures = tc.course_features
	f.tiles.clear()
	var hop := CourseFeatures.TRAMPOLINE_HOP
	f.tiles[Vector2i(4, 6)] = {"kind": "trampoline", "dir": 0, "age": 0}
	_check(_roll(Vector2i(4, 6), 0).landing_tile == Vector2i(4, 6 + hop), "landing on a trampoline bounces %d hexes on" % hop)
	_check(_roll(Vector2i(4, 5), 2).landing_tile == Vector2i(4, 7 + hop), "rolling onto it: bounce %d, keep the last hex of roll" % hop)
	f.tiles[Vector2i(4, 6 + hop)] = {"kind": "trampoline", "dir": 0, "age": 0}
	_check(_roll(Vector2i(4, 6), 0).landing_tile == Vector2i(4, 6 + 2 * hop), "trampoline onto trampoline chains")
	# A round 7-hex pad bounces once, however many of its hexes the ball touches
	f.tiles.clear()
	for c in CourseFeatures.trampoline_cells(Vector2i(4, 12)):
		f.tiles[c] = {"kind": "trampoline", "dir": 0, "age": 0, "group": Vector2i(4, 12)}
	_check(CourseFeatures.trampoline_cells(Vector2i(4, 12)).size() == 7, "a trampoline pad is 7 hexes")
	_check(_roll(Vector2i(4, 11), 0).landing_tile == Vector2i(4, 11 + hop), "a ball crossing the pad bounces once (lands %d on)" % hop)
	f.tiles.clear()


func _test_placement() -> void:
	print("-- placement --")
	var f := CourseFeatures.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	f.place(hole, rng)
	_check(f.count("ice") >= 3, "a hole gets ice patches (ice %d)" % f.count("ice"))
	_check(f.count("sprinkler") == 0, "no sprinklers any more")
	_check(not f.tiles.has(hole.flag_position), "nothing on the cup")
	var again := CourseFeatures.new()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 11
	again.place(hole, rng2)
	_check(again.tiles == f.tiles, "same seed, same features")
	var tunnels := 0
	var tramps := 0
	var straight := true
	var round_pads := true
	for sd in range(40):
		var g := CourseFeatures.new()
		var r := RandomNumberGenerator.new()
		r.seed = sd
		g.place(hole, r)
		var pads := g.count("trampoline")
		tramps += pads
		if pads % 7 != 0:
			round_pads = false
		var t := g.count("tunnel")
		if t > 0:
			tunnels += 1
			if t < 6 or t > 8:
				straight = false
	_check(tunnels > 5 and tunnels < 35, "wind gusts on about half the holes (%d / 40)" % tunnels)
	_check(straight, "a gust is a 2-wide band of 6-8 adjacent hexes")
	_check(tramps > 10 and round_pads, "trampolines get placed as 7-hex pads (%d hexes over 40 holes)" % tramps)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)
