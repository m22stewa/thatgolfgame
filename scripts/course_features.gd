extends RefCounted
class_name CourseFeatures

## CourseFeatures - Good / bad things on the course hexes (the green has its
## own, see GreenBoard). Seeded per hole from the hole RNG.
##
##   ice        - frictionless: a ball landing on ice gets +ICE_LANDING_ROLL,
##                and a rolling ball doesn't slow down while crossing ice
##   fire       - a hazard that spreads, and gets worse the longer the hole
##                takes: each stroke every fire may catch neighbours (more of
##                them, and more likely, as strokes go by; from FIRE_FAIRWAY_TURN
##                the fairway burns too), new fires flare up in the rough, and
##                each hex burns out after FIRE_LIFETIME strokes (scorched
##                ground). With wind it only spreads downwind. A ball that
##                lands in or rolls through fire costs a Money (hex_grid)
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
const FIRE_LIFETIME := 5        # strokes a hex burns before it scorches
const FIRE_SPREAD_CHANCE := 0.5  # per fire per stroke, +FIRE_SPREAD_GROWTH each stroke
const FIRE_SPREAD_GROWTH := 0.1
const FIRE_MAX_BURNING := 6      # cap on burning hexes, +FIRE_MAX_GROWTH each stroke
const FIRE_MAX_GROWTH := 4
const FIRE_FLARE_FROM := 2       # from this stroke on, a new fire may flare up in the rough
const FIRE_FLARE_CHANCE := 0.35
const FIRE_FAIRWAY_TURN := 3     # from this stroke on, fire spreads onto the fairway too
const FIRE_WIND_BOOST := 0.1     # spread chance per point of wind strength
const FIRE_DOWNWIND_MIN := 0.35  # a neighbour within ~70 degrees of the wind is downwind
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

	# Fire: every par 4 / 5 and half the par 3s start with one in the rough
	if not open_rough.is_empty() and (hole.current_par >= 4 or rng.randf() < 0.5):
		var cell: Vector2i = open_rough[rng.randi_range(0, open_rough.size() - 1)]
		if not tiles.has(cell):
			tiles[cell] = {"kind": "fire", "dir": 0, "age": 0}


func spread_fire(hole, rng: RandomNumberGenerator, turn: int = 1, wind := Vector2.ZERO, wind_strength: int = 0) -> bool:
	"""Stroke number turn has been taken: fires age (and scorch), and each may
	catch flammable neighbours - more of them, and more likely, the later it
	is. Later still, fires flare up on their own and the fairway catches.
	With wind (wind = world x, z the way it blows), fire only spreads to the
	neighbours downwind, most downwind first, and a stronger wind spreads it
	more often. Returns true if anything changed."""
	var changed := false
	var burning: Array[Vector2i] = []
	for cell in tiles:
		if tiles[cell].kind == "fire":
			burning.append(cell)
	burning.sort()  # stable order for the seed
	var windy := wind_strength > 0 and wind.length() > 0.001
	var chance := minf(FIRE_SPREAD_CHANCE + FIRE_SPREAD_GROWTH * (turn - 1) + (FIRE_WIND_BOOST * wind_strength if windy else 0.0), 0.95)
	var cap := FIRE_MAX_BURNING + FIRE_MAX_GROWTH * (turn - 1)
	var catches := 1 + turn / 3  # neighbours one fire can light in a stroke
	var flammable := FLAMMABLE + ([SURF_FAIRWAY] if turn >= FIRE_FAIRWAY_TURN else [])
	for cell in burning:
		tiles[cell].age += 1
		if tiles[cell].age >= FIRE_LIFETIME:
			tiles[cell] = {"kind": "scorched", "dir": 0, "age": 0}
			changed = true
			continue
		if rng.randf() > chance:
			continue
		var options: Array = hole.get_adjacent_cells(cell.x, cell.y).filter(
			func(n): return flammable.has(hole.get_cell(n.x, n.y)) and not tiles.has(n) and n != hole.flag_position)
		options.sort()
		if windy:
			options = _downwind(hole, cell, options, wind.normalized())
		for _c in range(catches):
			if options.is_empty() or count("fire") >= cap:
				break
			# Downwind: the most downwind neighbour catches first
			var lit: Vector2i = options.pop_at(0 if windy else rng.randi_range(0, options.size() - 1))
			tiles[lit] = {"kind": "fire", "dir": 0, "age": 0}
			changed = true
	# A fresh fire flares up somewhere in the open rough
	if turn >= FIRE_FLARE_FROM and rng.randf() < FIRE_FLARE_CHANCE and count("fire") < cap:
		var rough: Array[Vector2i] = []
		for x in range(hole.grid_width):
			for y in range(hole.grid_height):
				var c := Vector2i(x, y)
				if FLAMMABLE.has(hole.get_cell(x, y)) and not tiles.has(c) and c != hole.flag_position:
					rough.append(c)
		if not rough.is_empty():
			tiles[rough[rng.randi_range(0, rough.size() - 1)]] = {"kind": "fire", "dir": 0, "age": 0}
			changed = true
	return changed


static func _downwind(hole, from: Vector2i, options: Array, wind: Vector2) -> Array:
	"""The neighbours the wind blows toward (within ~70 degrees of it), most
	downwind first."""
	var p: Vector3 = hole.get_tile_world_position(from)
	var scored: Array = []
	for n in options:
		var q: Vector3 = hole.get_tile_world_position(n)
		var along := Vector2(q.x - p.x, q.z - p.z).normalized().dot(wind)
		if along > FIRE_DOWNWIND_MIN:
			scored.append([along, n])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored.map(func(e): return e[1])


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
