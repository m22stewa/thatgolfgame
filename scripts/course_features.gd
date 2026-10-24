extends RefCounted
class_name CourseFeatures

## CourseFeatures - Good / bad things on the course hexes (the green has its
## own, see GreenBoard). Seeded per hole from the hole RNG.
##
## Each obstacle is a shape of at least SHAPE_MIN hexes (sometimes bigger): a
## line, a 2-wide band, a rhombus "square" or a grown blob.
##
##   ice        - frictionless: a ball landing on ice gets +ICE_LANDING_ROLL,
##                and a rolling ball doesn't slow down while crossing ice
##   fire       - a hazard that spreads, and gets worse the longer the hole
##                takes: each stroke every fire may catch neighbours (more of
##                them, and more likely, as strokes go by; from FIRE_FAIRWAY_TURN
##                the fairway burns too), new fires flare up in the rough, and
##                each hex burns out after FIRE_LIFETIME strokes (scorched
##                ground). With wind it only spreads downwind. A ball that
##                lands in or rolls through fire costs a Chips (hex_grid); a
##                ball flying over it rides the updraft (ShotPlan): it goes
##                higher and carries FIRE_UPDRAFT hexes further
##   scorched   - burnt-out ground; cosmetic
##   tunnel     - a wind gust: a band of adjacent hexes (2 wide, 3-4 long)
##                all blowing one way; a ball touching it is pushed that way
##                1 + wind strength hexes and stops
##   trampoline - a round pad of 7 hexes (a hex and its ring); a ball touching
##                it bounces high, TRAMPOLINE_HOP hexes on in its direction of
##                travel, and keeps rolling. One bounce per pad
##
## Coins are the existing course pickups (hex_grid), not part of this map.

const SURF_FAIRWAY := 1
const SURF_ROUGH := 2
const SURF_DEEP_ROUGH := 3
const SURF_TREE := 7

const ICE_LANDING_ROLL := 2
const TRAMPOLINE_HOP := 4
const FIRE_LIFETIME := 6        # strokes a hex burns before it scorches
const FIRE_SPREAD_CHANCE := 0.75 # per fire per stroke, +FIRE_SPREAD_GROWTH each stroke
const FIRE_SPREAD_GROWTH := 0.15
const FIRE_MAX_BURNING := 14     # cap on burning hexes, +FIRE_MAX_GROWTH each stroke
const FIRE_MAX_GROWTH := 8
const FIRE_FLARE_FROM := 2       # from this stroke on, a new fire may flare up in the rough
const FIRE_FLARE_CHANCE := 0.5
const FIRE_FAIRWAY_TURN := 2     # from this stroke on, fire spreads onto the fairway too
const FIRE_UPDRAFT := 3          # extra hexes of carry for a ball flying over fire
const FIRE_WIND_BOOST := 0.1     # spread chance per point of wind strength
const FIRE_DOWNWIND_MIN := 0.35  # a neighbour within ~70 degrees of the wind is downwind
const FLAMMABLE := [SURF_ROUGH, SURF_DEEP_ROUGH]  # not trees: the canopy would hide it
const SHAPE_MIN := 4             # every obstacle covers at least this many hexes
const SHAPE_BIGGER_CHANCE := 0.45  # ...and is sometimes bigger (up to about 9)

var tiles: Dictionary = {}  # Vector2i course cell -> {kind: String, dir: int, age: int}


func place(hole, rng: RandomNumberGenerator) -> void:
	"""Seed the hole: 2-3 ice patches, sometimes a wind gust and trampoline
	pads and, on par 4s and 5s (half the par 3s), a fire in the rough. Each
	is a shape of SHAPE_MIN+ hexes. Never on the tee, the green, the cup or
	water."""
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
	var playable := fairway + rough
	var on_playable := func(c): return playable.has(c)

	# Ice: patches on the fairway / rough
	for _p in range(rng.randi_range(2, 3)):
		for cell in _shape_cells(rng, fairway, on_playable):
			tiles[cell] = {"kind": "ice", "dir": 0, "age": 0}

	# Wind gust: half the holes, a 2-wide band of 3-4 hexes all blowing one way
	if rng.randf() < 0.5:
		for _try in range(12):
			var start: Vector2i = playable[rng.randi_range(0, playable.size() - 1)]
			var d := rng.randi_range(0, 5)
			var band := gust_cells(start, d, rng.randi_range(3, 4))
			if band.all(func(c): return playable.has(c) and not tiles.has(c)):
				for cell in band:
					tiles[cell] = {"kind": "tunnel", "dir": d, "age": 0, "group": start}
				break

	# Trampolines: 0-2 round pads of 7 hexes on the fairway or rough
	for _t in range(rng.randi_range(0, 2)):
		for _try in range(12):
			var centre: Vector2i = playable[rng.randi_range(0, playable.size() - 1)]
			var pad := trampoline_cells(centre)
			if pad.all(func(c): return playable.has(c) and not tiles.has(c)):
				for cell in pad:
					tiles[cell] = {"kind": "trampoline", "dir": 0, "age": 0, "group": centre}
				break

	# Fire: every par 4 / 5 and half the par 3s start with a blaze in the rough
	if not open_rough.is_empty() and (hole.current_par >= 4 or rng.randf() < 0.5):
		for cell in _shape_cells(rng, open_rough, func(c): return rough.has(c)):
			tiles[cell] = {"kind": "fire", "dir": 0, "age": 0}


func _shape_cells(rng: RandomNumberGenerator, seeds: Array, ok: Callable) -> Array[Vector2i]:
	"""An obstacle shape grown from a random seed hex: SHAPE_MIN hexes, or
	bigger now and then. Every hex must pass ok and be free; a few seeds are
	tried before giving up (empty)."""
	if seeds.is_empty():
		return []
	for _try in range(12):
		var start: Vector2i = seeds[rng.randi_range(0, seeds.size() - 1)]
		var big := rng.randf() < SHAPE_BIGGER_CHANCE
		var d := rng.randi_range(0, 5)
		var cells: Array[Vector2i] = []
		match rng.randi_range(0, 3):
			0:  # line
				cells = _line(start, d, rng.randi_range(SHAPE_MIN + 1, SHAPE_MIN + 3) if big else SHAPE_MIN)
			1:  # band: two rows side by side
				cells = _rhombus(start, d, rng.randi_range(3, 4) if big else 2, 2)
			2:  # "square": a rhombus of hexes
				cells = _rhombus(start, d, 3, rng.randi_range(2, 3)) if big else _rhombus(start, d, 2, 2)
			_:  # blob
				cells = _blob(rng, start, rng.randi_range(SHAPE_MIN + 1, SHAPE_MIN + 4) if big else SHAPE_MIN, ok)
		if cells.size() >= SHAPE_MIN and cells.all(func(c): return ok.call(c) and not tiles.has(c)):
			return cells
	return []


static func trampoline_cells(centre: Vector2i) -> Array[Vector2i]:
	"""A round trampoline pad: the centre hex and the six around it."""
	var out: Array[Vector2i] = [centre]
	for d in range(6):
		out.append(neighbor(centre, d))
	return out


static func gust_cells(start: Vector2i, dir: int, length: int) -> Array[Vector2i]:
	"""A wind gust: two side-by-side rows of length hexes along dir."""
	return _rhombus(start, dir, length, 2)


static func _line(start: Vector2i, dir: int, length: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [start]
	for _i in range(length - 1):
		out.append(neighbor(out[out.size() - 1], dir))
	return out


static func _rhombus(start: Vector2i, dir: int, length: int, rows: int) -> Array[Vector2i]:
	"""rows lines of length hexes along dir, each row stepped off the last
	toward dir + 1 (60 degrees round): 2 x 2 is a little diamond."""
	var out: Array[Vector2i] = []
	var row_start := start
	for _r in range(rows):
		out.append_array(_line(row_start, dir, length))
		row_start = neighbor(row_start, (dir + 1) % 6)
	return out


func _blob(rng: RandomNumberGenerator, start: Vector2i, size: int, ok: Callable) -> Array[Vector2i]:
	"""A clump grown hex by hex from start."""
	var out: Array[Vector2i] = [start]
	for _g in range(size * 3):
		if out.size() >= size:
			break
		var from: Vector2i = out[rng.randi_range(0, out.size() - 1)]
		var n := neighbor(from, rng.randi_range(0, 5))
		if not out.has(n) and ok.call(n) and not tiles.has(n):
			out.append(n)
	return out


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
	var catches := 2 + turn / 2  # neighbours one fire can light in a stroke
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
