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
var cup: Vector2i = Vector2i.ZERO
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


func _shape_surface(rng: RandomNumberGenerator) -> void:
	"""Height field: a tilt across the green, 2-3 mounds or bowls, and half the
	time a tier (a step between two levels)."""
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
	var tier := {}
	if rng.randf() < 0.5:
		tier = {
			"normal": Vector2.from_angle(rng.randf() * TAU),
			"offset": rng.randf_range(-0.3, 0.3) * radius,
			"amp": rng.randf_range(0.2, 0.35),
		}

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


# --- Putting ---

func clamp_target(ball: Vector2i, target: Vector2i) -> Vector2i:
	"""Pull a tapped hex back along the line to within PUTT_REACH. Aiming at
	the cup from further than a tap-in stops the ball just short of it."""
	var d := distance(ball, target)
	if d > PUTT_REACH:
		target = line(ball, target)[PUTT_REACH]
		d = PUTT_REACH
	if target == cup and d > 1:
		target = line(ball, target)[d - 1]
	return target


func roll(ball: Vector2i, target: Vector2i) -> Dictionary:
	"""Resolve a putt. Returns {path: Array[Vector2i] (hexes entered, in order),
	holed, off_green, end, touched (unique hexes entered)}."""
	var path: Array[Vector2i] = []
	var result := {"path": path, "holed": false, "off_green": false, "end": ball, "touched": 0}
	var cur := ball
	# The struck roll: straight to the target; arrows don't act mid-roll and
	# the ball rolls over the cup (only a 1-hex tap-in drops)
	var struck := line(ball, clamp_target(ball, target))
	for i in range(1, struck.size()):
		var tap_in := struck.size() == 2
		if struck[i] == cup and not tap_in:
			path.append(struck[i])
			cur = struck[i]
			continue
		if _enter(struck[i], path, result):
			return _finish(result)
		cur = struck[i]
	# Then the green takes over: each landing hex pushes the ball on
	var seen := {}
	for _push in range(MAX_PUSHES):
		var t: Dictionary = tiles[cur]
		if t.strength == 0:
			break
		if seen.get(cur, 0) >= 2:
			break  # caught in a loop: the ball settles
		seen[cur] = seen.get(cur, 0) + 1
		for _s in range(t.strength):
			var nxt: Vector2i = cur + DIRS[t.dir]
			if _enter(nxt, path, result):
				return _finish(result)
			cur = nxt
	result.end = cur
	return _finish(result)


func _enter(a: Vector2i, path: Array[Vector2i], result: Dictionary) -> bool:
	"""Move the ball onto a; true when the putt ends here (cup or off green)."""
	path.append(a)
	result.end = a
	if a == cup:
		result.holed = true
		return true
	if not tiles.has(a):
		result.off_green = true
		return true
	return false


func _finish(result: Dictionary) -> Dictionary:
	var unique := {}
	for a in result.path:
		unique[a] = true
	result.touched = unique.size()
	return result
