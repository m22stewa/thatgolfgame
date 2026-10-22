extends RefCounted
class_name GreenBoard

## GreenBoard - The putting surface at half the hex size of the course.
##
## Putting is a reading puzzle: every green hex carries an arrow (one of 6
## directions, strength 0-3). A putt rolls the ball straight to the hex you
## pick (within PUTT_REACH), then the arrow on the hex it lands on pushes it
## that many hexes, and again on the next hex, until it reaches a flat hex.
## A struck ball is moving too fast to drop: it rolls over the cup, unless it
## is a 1-hex tap-in. Only the green (an arrow push) feeds a longer putt in.
## Rolling off the green ends the putt on the fringe. The more hexes a holed
## putt touches, the more it scores.
##
## Features on the green (seeded with the board):
##   coin    - collected when the ball rolls over it (the putt carries on)
##   spike   - spike marks: the ball stops dead on them
##   putter  - a forgotten putter lying across two hexes: the ball bounces off
##             it and rolls back the way it came for the hexes it had left
##             (a bank shot)
##
## Small hexes use axial coords (q, r), flat-top like the course grid:
##   x = SIZE * 1.5 * q,  z = SIZE * sqrt(3) * (r + q / 2)
## With SIZE = 0.5 every course hex centre is also a small hex centre, and each
## course hex covers about four small ones. Elevation is a seeded field (tilt,
## mounds and bowls, sometimes a tier) so every green has character.

const SIZE := 0.5                   # small hex radius (course hexes are 1.0)
const STEP := 0.8660254             # distance between neighbouring small hexes (SIZE * sqrt(3))
const PUTT_REACH := 6               # small hexes a putt can be struck
const MAX_PUSHES := 60              # safety cap on the arrow chain
const SURF_GREEN := 4
const SURF_FLAG := 8

# Axial neighbour steps, flat-top. Index = arrow direction.
const DIRS: Array[Vector2i] = [
	Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1),
	Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1),
]

# Share of green hexes at each arrow strength (0 = flat ... 3 = steep)
const STRENGTH_SHARE := [0.2, 0.4, 0.28, 0.12]

var tiles: Dictionary = {}   # Vector2i axial -> {height: float, dir: int, strength: int}
var features: Dictionary = {}  # Vector2i axial -> {kind: "coin" | "spike" | "putter", dir: int}
var cup: Vector2i = Vector2i.ZERO
var style: String = "rolling"  # rolling | two-tier | crowned | punchbowl
var low := 0.0               # height range, for tinting
var high := 1.0


# --- Coordinates ---

static func to_world(a: Vector2i) -> Vector2:
	"""Small hex centre in world (x, z)."""
	return Vector2(SIZE * 1.5 * a.x, SIZE * sqrt(3.0) * (a.y + a.x / 2.0))


static func from_world(p: Vector2) -> Vector2i:
	"""Small hex containing world (x, z)."""
	var q := p.x / (SIZE * 1.5)
	var r := p.y / (SIZE * sqrt(3.0)) - q / 2.0
	return _axial_round(q, r)


static func from_course(cell: Vector2i) -> Vector2i:
	"""The small hex at a course hex's centre."""
	return Vector2i(2 * cell.x, 2 * cell.y + (cell.x & 1) - cell.x)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((absi(dq) + absi(dr) + absi(dq + dr)) / 2)


static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	"""Small hexes on the straight line from a to b, inclusive."""
	var out: Array[Vector2i] = []
	var n := distance(a, b)
	for i in range(n + 1):
		var t := 0.0 if n == 0 else float(i) / float(n)
		var q := lerpf(a.x + 1e-6, b.x + 1e-6, t)
		var r := lerpf(a.y + 2e-6, b.y + 2e-6, t)
		out.append(_axial_round(q, r))
	return out


static func _axial_round(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


# --- Building ---

func build(hole, rng: RandomNumberGenerator) -> void:
	"""Cover the course's green hexes with small hexes, shape the surface and
	set every arrow. hole: get_cell / world_to_grid / flag_position /
	get_tile_world_position. rng: the hole's seeded RNG."""
	tiles.clear()
	var course_cells: Array[Vector2i] = []
	for x in range(hole.grid_width):
		for y in range(hole.grid_height):
			var s: int = hole.get_cell(x, y)
			if s == SURF_GREEN or s == SURF_FLAG or Vector2i(x, y) == hole.flag_position:
				course_cells.append(Vector2i(x, y))
	if course_cells.is_empty():
		return
	var cup_world: Vector3 = hole.get_tile_world_position(hole.flag_position)
	cup = from_world(Vector2(cup_world.x, cup_world.z))

	# Small hexes whose centre falls on a green course hex
	var candidates := {}
	for cell in course_cells:
		var c := from_course(cell)
		candidates[c] = true
		for d in DIRS:
			candidates[c + d] = true
	for a in candidates:
		var w := to_world(a)
		var cell: Vector2i = hole.world_to_grid(Vector3(w.x, 0.0, w.y))
		var s: int = hole.get_cell(cell.x, cell.y)
		if s == SURF_GREEN or s == SURF_FLAG or cell == hole.flag_position:
			tiles[a] = {"height": 0.0, "dir": 0, "strength": 0}
	tiles[cup] = {"height": 0.0, "dir": 0, "strength": 0}

	_shape_surface(rng)
	_set_arrows()
	_place_features(rng)


func _shape_surface(rng: RandomNumberGenerator) -> void:
	"""Height field: a tilt across the green, 2-3 mounds or bowls, and half the
	time a tier (a step between two levels), plus the green's style: rolling
	(as is), two-tier (a strong step), crowned (sheds to the edges) or
	punchbowl (runs to the middle)."""
	var center := Vector2.ZERO
	for a in tiles:
		center += to_world(a)
	center /= float(tiles.size())
	var radius := 0.0
	for a in tiles:
		radius = maxf(radius, (to_world(a) - center).length())
	radius = maxf(radius, 1.0)

	var tilt := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.05, 0.1)
	var bumps: Array = []
	for i in range(rng.randi_range(2, 3)):
		bumps.append({
			"at": center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.8) * radius,
			"amp": rng.randf_range(0.18, 0.4) * (1.0 if rng.randf() < 0.5 else -1.0),
			"sigma": rng.randf_range(0.35, 0.6) * radius,
		})
	style = ["rolling", "two-tier", "crowned", "punchbowl"][rng.randi_range(0, 3)]
	var tier := {}
	if rng.randf() < 0.5 or style == "two-tier":
		tier = {
			"normal": Vector2.from_angle(rng.randf() * TAU),
			"offset": rng.randf_range(-0.3, 0.3) * radius,
			"amp": rng.randf_range(0.35, 0.5) if style == "two-tier" else rng.randf_range(0.2, 0.35),
		}
	if style == "crowned":
		bumps.append({"at": center, "amp": rng.randf_range(0.35, 0.5), "sigma": 0.55 * radius})
	elif style == "punchbowl":
		bumps.append({"at": center, "amp": -rng.randf_range(0.35, 0.5), "sigma": 0.6 * radius})

	# The cup sits in a slight dip, so the green tends to feed it
	bumps.append({"at": to_world(cup), "amp": -0.12, "sigma": 0.9})

	low = INF
	high = -INF
	for a in tiles:
		var p := to_world(a) - center
		var h := tilt.dot(p)
		for b in bumps:
			var d: float = (to_world(a) - b.at).length()
			h += b.amp * exp(-d * d / (2.0 * b.sigma * b.sigma))
		if not tier.is_empty():
			h += tier.amp * smoothstep(-0.4, 0.4, p.dot(tier.normal) - tier.offset)
		tiles[a].height = h
		low = minf(low, h)
		high = maxf(high, h)


func _set_arrows() -> void:
	"""Arrow = downhill neighbour direction; strength by how steep this hex is
	relative to the rest of the green (STRENGTH_SHARE), so every green has a
	full range of reads. The cup is a flat sink."""
	var drops: Array = []
	for a in tiles:
		var best_dir := 0
		var best_drop := -INF
		var h: float = tiles[a].height
		for i in range(6):
			var n: Vector2i = a + DIRS[i]
			# Off the green, extrapolate the slope from the opposite neighbour
			var hn: float
			if tiles.has(n):
				hn = tiles[n].height
			elif tiles.has(a - DIRS[i]):
				hn = 2.0 * h - float(tiles[a - DIRS[i]].height)
			else:
				hn = h
			var drop := h - hn
			if drop > best_drop:
				best_drop = drop
				best_dir = i
		tiles[a].dir = best_dir
		tiles[a]["_drop"] = maxf(best_drop, 0.0)
		drops.append(maxf(best_drop, 0.0))
	drops.sort()
	var cuts: Array = []
	var acc := 0.0
	for i in range(3):
		acc += STRENGTH_SHARE[i]
		cuts.append(drops[mini(int(acc * drops.size()), drops.size() - 1)])
	for a in tiles:
		var d: float = tiles[a]._drop
		var s := 0
		for c in cuts:
			if d > c:
				s += 1
		tiles[a].strength = s
		tiles[a].erase("_drop")
	tiles[cup].strength = 0


func _place_features(rng: RandomNumberGenerator) -> void:
	"""Seeded green clutter: usually a forgotten putter, 2-4 spike marks and
	1-2 coins, kept off the cup and its neighbours."""
	features.clear()
	var open: Array[Vector2i] = []
	for a in tiles:
		if distance(a, cup) >= 2:
			open.append(a)
	open.sort()  # the seed must give the same green every time
	if open.is_empty():
		return
	if rng.randf() < 0.7:
		for _try in range(20):
			var a: Vector2i = open[rng.randi_range(0, open.size() - 1)]
			var d := rng.randi_range(0, 5)
			var b: Vector2i = a + DIRS[d]
			if tiles.has(b) and distance(b, cup) >= 2 and not features.has(a) and not features.has(b):
				features[a] = {"kind": "putter", "dir": d}
				features[b] = {"kind": "putter", "dir": d}
				break
	for kind in ["spike", "coin"]:
		var count := rng.randi_range(2, 4) if kind == "spike" else rng.randi_range(1, 2)
		for _i in range(count):
			for _try in range(20):
				var a: Vector2i = open[rng.randi_range(0, open.size() - 1)]
				if not features.has(a):
					features[a] = {"kind": kind, "dir": 0}
					break


# --- Putting ---

func clamp_target(ball: Vector2i, target: Vector2i, reach: int = PUTT_REACH) -> Vector2i:
	"""Pull a tapped hex back along the line to within reach. Aiming at the cup
	from further than a tap-in stops the ball just short of it."""
	var d := distance(ball, target)
	if d > reach:
		target = line(ball, target)[reach]
		d = reach
	if target == cup and d > 1:
		target = line(ball, target)[d - 1]
	return target


func roll(ball: Vector2i, target: Vector2i, opts: Dictionary = {}) -> Dictionary:
	"""Resolve a putt. opts: reach (int, default PUTT_REACH), dead_weight (the
	green doesn't push it: the ball stays where it's struck).
	Returns {path: Array[Vector2i] (hexes entered, in order), holed, off_green,
	end, touched (unique hexes entered), coins (collected), banked, spiked}."""
	var path: Array[Vector2i] = []
	var result := {"path": path, "holed": false, "off_green": false, "end": ball, "touched": 0,
		"coins": [], "banked": false, "spiked": false}
	var reach := int(opts.get("reach", PUTT_REACH))
	# The struck roll: straight to the target; arrows don't act mid-roll and
	# the ball rolls over the cup (only a 1-hex tap-in drops). Off a putter it
	# rolls back along its line for the hexes it had left.
	var struck := line(ball, clamp_target(ball, target, reach))
	var steps: Array[Vector2i] = struck.slice(1)
	var tap_in := steps.size() == 1
	var cur := ball
	var i := 0
	while i < steps.size():
		var nxt: Vector2i = steps[i]
		if _is_putter(nxt):
			if result.banked:
				break  # a second bounce kills it
			result.banked = true
			steps = _rebound(struck, struck.find(cur), steps.size() - i)
			i = 0
			continue
		if nxt == cup and not tap_in:
			path.append(nxt)  # too quick to drop: over the cup
			cur = nxt
			i += 1
			continue
		if _enter(nxt, path, result):
			return _finish(result)
		cur = nxt
		i += 1
	if opts.get("dead_weight", false):
		result.end = cur
		return _finish(result)
	# Then the green takes over: each landing hex pushes the ball on
	var seen := {}
	for _push in range(MAX_PUSHES):
		var t: Dictionary = tiles[cur]
		if t.strength == 0:
			break
		if seen.get(cur, 0) >= 2:
			break  # caught in a loop: the ball settles
		seen[cur] = seen.get(cur, 0) + 1
		var dir: int = t.dir
		for _s in range(t.strength):
			var nxt: Vector2i = cur + DIRS[dir]
			if _is_putter(nxt):
				# Bank off the putter: reverse for the rest of this push
				result.banked = true
				dir = (dir + 3) % 6
				nxt = cur + DIRS[dir]
				if _is_putter(nxt):
					break
			if _enter(nxt, path, result):
				return _finish(result)
			cur = nxt
	result.end = cur
	return _finish(result)


func _rebound(struck: Array[Vector2i], at: int, remaining: int) -> Array[Vector2i]:
	"""Bounced off a putter while at struck[at]: retrace the struck line back
	toward (and past) the ball for the remaining hexes."""
	var out: Array[Vector2i] = []
	var pos: Vector2i = struck[at]
	var back := struck[0] - struck[1] if struck.size() > 1 else Vector2i.ZERO
	for j in range(remaining):
		var idx := at - 1 - j
		pos = struck[idx] if idx >= 0 else pos + back
		out.append(pos)
	return out


func _is_putter(a: Vector2i) -> bool:
	return features.has(a) and features[a].kind == "putter"


func _enter(a: Vector2i, path: Array[Vector2i], result: Dictionary) -> bool:
	"""Move the ball onto a; true when the putt ends here (cup, off the green,
	spike marks)."""
	path.append(a)
	result.end = a
	if a == cup:
		result.holed = true
		return true
	if not tiles.has(a):
		result.off_green = true
		return true
	var f: Dictionary = features.get(a, {})
	if f.get("kind", "") == "coin" and not result.coins.has(a):
		result.coins.append(a)
	if f.get("kind", "") == "spike":
		result.spiked = true
		return true
	return false


func _finish(result: Dictionary) -> Dictionary:
	var unique := {}
	for a in result.path:
		unique[a] = true
	result.touched = unique.size()
	return result
