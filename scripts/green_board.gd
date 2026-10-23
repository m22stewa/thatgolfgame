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
## Puzzle pieces (seeded with the board), after hex movement puzzles:
##   lip     - a raised edge between two hexes along a ridge (Ricochet Robots'
##             walls): the ball can't cross it and stops against it
##   slick   - a fast patch (ice in Pokemon / TERASLIDE): a ball that runs onto
##             it keeps sliding the way it was going, hex by hex, until it
##             reaches grippy green, a lip, the cup (it drops) or the edge
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
## mounds and bowls, sometimes a tier) so every green has character. Every
## green also has 2-3 curving feeder valleys that run into the cup from
## different sides, and ridges that split the flow: there are several routes
## in, and a putt struck onto the head of a valley rides a long chain of
## arrows down it (more hexes touched, more points).

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
const STRENGTH_SHARE := [0.15, 0.4, 0.3, 0.15]

var tiles: Dictionary = {}   # Vector2i axial -> {height: float, dir: int, strength: int}
var features: Dictionary = {}  # Vector2i axial -> {kind: "coin" | "spike" | "putter", dir: int}
var walls: Dictionary = {}     # edge key (see edge_key) -> [a, b]: a lip between two neighbouring hexes
var _ridge_lines: Array = []   # the ridges' spines, for laying lips along them
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
	_place_walls()
	_place_slick(rng)
	_place_features(rng)


func _shape_surface(rng: RandomNumberGenerator) -> void:
	"""Height field: a gentle tilt, 4-6 small mounds or hollows, half the time
	a tier (a step between two levels), feeder valleys into the cup and ridges
	that split the flow, plus the green's style: rolling (as is), two-tier (a
	strong step), crowned (sheds to the edges) or punchbowl (runs to the
	middle)."""
	var center := Vector2.ZERO
	for a in tiles:
		center += to_world(a)
	center /= float(tiles.size())
	var radius := 0.0
	for a in tiles:
		radius = maxf(radius, (to_world(a) - center).length())
	radius = maxf(radius, 1.0)

	# A soft tilt only: a strong one points the whole green the same way
	var tilt := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.02, 0.05)
	var bumps: Array = []
	for i in range(rng.randi_range(4, 6)):
		bumps.append({
			"at": center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.1, 0.9) * radius,
			"amp": rng.randf_range(0.15, 0.35) * (1.0 if rng.randf() < 0.5 else -1.0),
			"sigma": rng.randf_range(0.18, 0.35) * radius,
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
	var valleys := _feeder_valleys(rng)
	var ridges := _ridges(rng, center, radius)
	_ridge_lines = ridges

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
		for v in valleys:
			# Deeper toward the cup, so the floor of the valley runs into it
			var near := _nearest_on(v.points, to_world(a))
			h -= v.depth * (0.25 + 0.75 * near.t) * exp(-near.d * near.d / (2.0 * v.width * v.width))
		for g in ridges:
			var near := _nearest_on(g.points, to_world(a))
			h += g.amp * exp(-near.d * near.d / (2.0 * g.width * g.width))
		tiles[a].height = h
		low = minf(low, h)
		high = maxf(high, h)


func _feeder_valleys(rng: RandomNumberGenerator) -> Array:
	"""1-2 curving troughs from the far side of the green into the cup, coming
	in from well-spread directions. Each is {points (polyline, start -> cup),
	depth, width}."""
	var cup_w := to_world(cup)
	var far := 0.0
	for a in tiles:
		far = maxf(far, (to_world(a) - cup_w).length())
	var out: Array = []
	if far < STEP * 3.0:
		return out  # a tiny green: no room for valleys
	var count := rng.randi_range(1, 2)
	var base := rng.randf() * TAU
	var keys := tiles.keys()
	keys.sort()  # the seed must give the same green every time
	for i in range(count):
		var ang := base + TAU * float(i) / float(count) + rng.randf_range(-0.4, 0.4)
		var dir := Vector2.from_angle(ang)
		# Head of the valley: the green hex furthest out along this direction
		var head := cup_w
		var best := -INF
		for a in keys:
			var off := to_world(a) - cup_w
			var along := off.dot(dir)
			var score := along - 1.5 * absf(off.cross(dir))
			if along > STEP * 2.0 and score > best:
				best = score
				head = to_world(a)
		if head == cup_w:
			continue
		# Bend it: a quadratic curve through a control point off to one side
		var mid := (head + cup_w) * 0.5
		var span := (cup_w - head).length()
		var side := (cup_w - head).normalized().orthogonal()
		var ctrl := mid + side * span * rng.randf_range(-0.45, 0.45)
		var pts := PackedVector2Array()
		for k in range(17):
			var t := float(k) / 16.0
			pts.append(head.lerp(ctrl, t).lerp(ctrl.lerp(cup_w, t), t))
		out.append({"points": pts, "depth": rng.randf_range(0.35, 0.6), "width": rng.randf_range(0.4, 0.55)})
	return out


func _ridges(rng: RandomNumberGenerator, center: Vector2, radius: float) -> Array:
	"""1-2 raised spines across the green that split the flow, kept clear of
	the cup. Each is {points (a straight segment), amp, width}."""
	var out: Array = []
	var cup_w := to_world(cup)
	for i in range(rng.randi_range(1, 2)):
		for _try in range(10):
			var at := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.7) * radius
			var along := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 0.6) * radius
			var pts := PackedVector2Array([at - along, at + along])
			if _nearest_on(pts, cup_w).d < 1.5:
				continue
			out.append({"points": pts, "amp": rng.randf_range(0.2, 0.35), "width": rng.randf_range(0.3, 0.45)})
			break
	return out


static func _nearest_on(points: PackedVector2Array, p: Vector2) -> Dictionary:
	"""Closest point on a polyline: {d: distance, t: 0 at the first point ... 1
	at the last, by segment}."""
	var best := {"d": INF, "t": 0.0}
	var n := points.size() - 1
	for i in range(n):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var u := 0.0 if ab.length_squared() < 1e-9 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := (a + ab * u - p).length()
		if d < best.d:
			best = {"d": d, "t": (float(i) + u) / float(n)}
	return best


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


static func edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	"""Order-free key for the edge between two hexes."""
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


func _place_walls() -> void:
	"""Lips along each ridge spine: every edge between two green hexes that the
	spine crosses, with a gate left open at its middle so the lip is
	something to route round or through, never a fence across the green.
	Never on the cup's edges."""
	walls.clear()
	var keys := tiles.keys()
	keys.sort()
	for g in _ridge_lines:
		var p0: Vector2 = g.points[0]
		var p1: Vector2 = g.points[g.points.size() - 1]
		for a in keys:
			for i in range(3):  # each edge once: half the directions
				var b: Vector2i = a + DIRS[i]
				if not tiles.has(b) or a == cup or b == cup:
					continue
				var hit = Geometry2D.segment_intersects_segment(p0, p1, to_world(a), to_world(b))
				if hit == null:
					continue
				var t := ((hit as Vector2) - p0).dot(p1 - p0) / maxf((p1 - p0).length_squared(), 0.0001)
				if absf(t - 0.5) < 0.12:
					continue  # the gate
				walls[edge_key(a, b)] = [a, b]


func _place_slick(rng: RandomNumberGenerator) -> void:
	"""1-2 fast patches of 3-7 hexes, grown from a seed hex, clear of the cup.
	Slick hexes are flat (no arrow): the ball's own pace carries it across."""
	var open: Array[Vector2i] = []
	for a in tiles:
		if distance(a, cup) >= 2:
			open.append(a)
	open.sort()
	if open.size() < 12:
		return
	for _patch in range(rng.randi_range(1, 2)):
		var patch: Array[Vector2i] = [open[rng.randi_range(0, open.size() - 1)]]
		var size := rng.randi_range(3, 7)
		for _grow in range(size * 4):
			if patch.size() >= size:
				break
			var from: Vector2i = patch[rng.randi_range(0, patch.size() - 1)]
			var nxt: Vector2i = from + DIRS[rng.randi_range(0, 5)]
			if tiles.has(nxt) and distance(nxt, cup) >= 2 and not patch.has(nxt):
				patch.append(nxt)
		for a in patch:
			tiles[a].slick = true
			tiles[a].strength = 0


func is_slick(a: Vector2i) -> bool:
	return tiles.has(a) and tiles[a].get("slick", false)


func blocked(a: Vector2i, b: Vector2i) -> bool:
	"""A lip between a and b."""
	return walls.has(edge_key(a, b))


func _place_features(rng: RandomNumberGenerator) -> void:
	"""Seeded green clutter: usually a forgotten putter, 2-4 spike marks and
	1-2 coins, kept off the cup and its neighbours."""
	features.clear()
	var open: Array[Vector2i] = []
	for a in tiles:
		if distance(a, cup) >= 2 and not is_slick(a):
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
		if blocked(cur, nxt):
			break  # stops against the lip
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
	# Still carrying pace onto a slick patch: it slides on the way it was rolling
	var last := path[path.size() - 2] if path.size() >= 2 else ball
	var slide := _slide(cur, _dir_index(cur - last), path, result)
	if slide.ended:
		return _finish(result)
	cur = slide.cur
	# Then the green takes over: each landing hex pushes the ball on
	var seen := {}
	var stopped := false
	for _push in range(MAX_PUSHES):
		var t: Dictionary = tiles[cur]
		if t.strength == 0 or stopped:
			break
		if seen.get(cur, 0) >= 2:
			break  # caught in a loop: the ball settles
		seen[cur] = seen.get(cur, 0) + 1
		var dir: int = t.dir
		for _s in range(t.strength):
			var nxt: Vector2i = cur + DIRS[dir]
			if blocked(cur, nxt):
				stopped = true  # rests against the lip
				break
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
			if is_slick(cur):
				slide = _slide(cur, dir, path, result)
				if slide.ended:
					return _finish(result)
				cur = slide.cur
				break  # the slide used up this push
	result.end = cur
	return _finish(result)


func _slide(cur: Vector2i, dir: int, path: Array[Vector2i], result: Dictionary) -> Dictionary:
	"""On a slick hex the ball keeps going in dir until grippy green, a lip or
	a putter stops it (or the cup / the edge ends the putt). Returns {cur, ended}."""
	if dir < 0:
		return {"cur": cur, "ended": false}
	for _guard in range(MAX_PUSHES):
		if not is_slick(cur):
			break
		var nxt: Vector2i = cur + DIRS[dir]
		if blocked(cur, nxt) or _is_putter(nxt):
			break
		if _enter(nxt, path, result):
			return {"cur": nxt, "ended": true}
		cur = nxt
	result.end = cur
	return {"cur": cur, "ended": false}


static func _dir_index(step: Vector2i) -> int:
	return DIRS.find(step)


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
