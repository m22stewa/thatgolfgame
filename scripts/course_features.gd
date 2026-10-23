extends RefCounted
class_name CourseFeatures

## CourseFeatures - Good / bad things on the course hexes (the green has its
## own, see GreenBoard). Seeded per hole from the hole RNG.
##
##   ice        - frictionless: a ball landing on ice gets +ICE_LANDING_ROLL,
##                and a rolling ball doesn't slow down while crossing ice
##   fire       - a hazard that spreads: each turn it can catch a neighbouring
##                rough / deep rough hex, and burns out after
##                FIRE_LIFETIME turns (leaving scorched ground). A ball that
##                ends in fire is a penalty stroke, returned like water
##   scorched   - burnt-out ground; cosmetic
##   sprinkler  - a ball that stops on it is knocked one hex its facing way
##   tunnel     - a wind tunnel (a straight run of 3-5 hexes): a ball touching
##                it is pushed along it 1 + wind strength hexes and stops
##   trampoline - a ball touching it bounces TRAMPOLINE_HOP hexes on in its
##                direction of travel and keeps rolling
##
## Coins are the existing course pickups (hex_grid), not part of this map.

const SURF_FAIRWAY := 1
const SURF_ROUGH := 2
const SURF_DEEP_ROUGH := 3
const SURF_TREE := 7

const ICE_LANDING_ROLL := 2
const TRAMPOLINE_HOP := 3
const FIRE_LIFETIME := 4       # turns a hex burns before it scorches
const FIRE_SPREAD_CHANCE := 0.6
const FIRE_MAX_BURNING := 8
const FLAMMABLE := [SURF_ROUGH, SURF_DEEP_ROUGH]  # not trees: the canopy would hide it

var tiles: Dictionary = {}  # Vector2i course cell -> {kind: String, dir: int, age: int}


func place(hole, rng: RandomNumberGenerator) -> void:
	"""Seed the hole: 2-3 ice patches, a few sprinklers on the fairway and, on
	par 4s and 5s, sometimes a fire in the rough. Never on the tee, the green,
	the cup or water."""
	tiles.clear()
	var fairway: Array[Vector2i] = []
	var rough: Array[Vector2i] = []
	for x in range(hole.grid_width):
		for y in range(hole.grid_height):
			var cell := Vector2i(x, y)
			if cell == hole.flag_position:
				continue
			var s: int = hole.get_cell(x, y)
			if s == SURF_FAIRWAY:
				fairway.append(cell)
			elif s == SURF_ROUGH or s == SURF_DEEP_ROUGH:
				rough.append(cell)
	# Fire starts in open rough (no tree next to it) so it can be seen
	var open_rough := rough.filter(func(c):
		return hole.get_adjacent_cells(c.x, c.y).all(func(n): return hole.get_cell(n.x, n.y) != SURF_TREE))
	if fairway.is_empty():
		return

	# Ice: patches of 3-6 hexes, grown from a fairway seed
	for _p in range(rng.randi_range(2, 3)):
		var seed_cell: Vector2i = fairway[rng.randi_range(0, fairway.size() - 1)]
		var patch: Array[Vector2i] = [seed_cell]
		for _g in range(rng.randi_range(2, 5)):
			var from: Vector2i = patch[rng.randi_range(0, patch.size() - 1)]
			var options: Array = hole.get_adjacent_cells(from.x, from.y).filter(
				func(n): return (fairway.has(n) or rough.has(n)) and not patch.has(n))
			if not options.is_empty():
				patch.append(options[rng.randi_range(0, options.size() - 1)])
		for cell in patch:
			tiles[cell] = {"kind": "ice", "dir": 0, "age": 0}

	# Sprinklers: 2-3 on the fairway, each facing a random way
	for _s in range(rng.randi_range(2, 3)):
		var cell: Vector2i = fairway[rng.randi_range(0, fairway.size() - 1)]
		if not tiles.has(cell):
			tiles[cell] = {"kind": "sprinkler", "dir": rng.randi_range(0, 5), "age": 0}

	# Wind tunnel: half the holes, a straight run of 3-5 hexes
	if rng.randf() < 0.5:
		var playable := fairway + rough
		for _try in range(10):
			var start: Vector2i = playable[rng.randi_range(0, playable.size() - 1)]
			var d := rng.randi_range(0, 5)
			var run: Array[Vector2i] = [start]
			for _i in range(rng.randi_range(2, 4)):
				var n := neighbor(run[run.size() - 1], d)
				if not playable.has(n) or tiles.has(n):
					break
				run.append(n)
			if run.size() >= 3 and run.all(func(c): return not tiles.has(c)):
				for cell in run:
					tiles[cell] = {"kind": "tunnel", "dir": d, "age": 0, "group": start}
				break

	# Trampolines: 0-2 on the fairway or rough
	for _t in range(rng.randi_range(0, 2)):
		var playable := fairway + rough
		var cell: Vector2i = playable[rng.randi_range(0, playable.size() - 1)]
		if not tiles.has(cell):
			tiles[cell] = {"kind": "trampoline", "dir": 0, "age": 0}

	# Fire: par 4 / 5, half the time, somewhere in the rough
	if hole.current_par >= 4 and not open_rough.is_empty() and rng.randf() < 0.5:
		var cell: Vector2i = open_rough[rng.randi_range(0, open_rough.size() - 1)]
		if not tiles.has(cell):
			tiles[cell] = {"kind": "fire", "dir": 0, "age": 0}


func spread_fire(hole, rng: RandomNumberGenerator) -> bool:
	"""One turn passes: fires age (and scorch), and each may catch one
	flammable neighbour. Returns true if anything changed."""
	var changed := false
	var burning: Array[Vector2i] = []
	for cell in tiles:
		if tiles[cell].kind == "fire":
			burning.append(cell)
	burning.sort()  # stable order for the seed
	for cell in burning:
		tiles[cell].age += 1
		if tiles[cell].age >= FIRE_LIFETIME:
			tiles[cell] = {"kind": "scorched", "dir": 0, "age": 0}
			changed = true
			continue
		if count("fire") >= FIRE_MAX_BURNING or rng.randf() > FIRE_SPREAD_CHANCE:
			continue
		var options: Array = hole.get_adjacent_cells(cell.x, cell.y).filter(
			func(n): return FLAMMABLE.has(hole.get_cell(n.x, n.y)) and not tiles.has(n) and n != hole.flag_position)
		if not options.is_empty():
			options.sort()
			tiles[options[rng.randi_range(0, options.size() - 1)]] = {"kind": "fire", "dir": 0, "age": 0}
			changed = true
	return changed


static func neighbor(cell: Vector2i, dir: int) -> Vector2i:
	"""Course hex neighbour, same direction convention as AOESystem
	(0 = up, then clockwise; odd columns sit half a hex lower)."""
	var odd := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
	var even := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	return cell + (odd[dir] if cell.x % 2 == 1 else even[dir])


func kind_at(cell: Vector2i) -> String:
	return tiles.get(cell, {}).get("kind", "")


func count(kind: String) -> int:
	var n := 0
	for cell in tiles:
		if tiles[cell].kind == kind:
			n += 1
	return n
