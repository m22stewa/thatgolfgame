extends RefCounted
class_name GreenBoard

## GreenBoard - The putting surface at half the hex size of the course.
##
## Putting is a planned puzzle (design/claude/design_handoff_putting). A putt
## leaves the ball's hex in one of the six directions with a pace: PUTT_BASE
## plus the PuttModifierDeck flip (a lag putt is exactly PUTT_BASE). The ball
## rolls hex by hex, spending 1 pace per hex, and each hex it enters acts on it
## (simulate_putt). The same function draws the preview, so the read is never
## hidden. Hole out in MAX_PUTTS or pick up.
##
## Hexes on the green:
##   slope   - a hand-placed-looking slope zone, 4-10 per green (most of the
##             green is flat). Strength 1-3. Rolling down it adds strength - 1
##             pace, up it takes that away; across it bends the ball 60
##             degrees toward the fall line (a strength-1 slope only bends a
##             slow ball, pace 2 or less).
##   slick   - a fast patch: +1 pace on every slick hex
##   spike   - spike marks: the ball stops dead on them
##   coin    - collected when the ball rolls over it (the putt carries on)
##   cup     - drops a ball arriving with 0 or 1 pace left; a firmer one lips
##             out and keeps rolling. Never a slope.
## Rolling off the green ends the putt on the last green hex (the fringe).
##
## Small hexes use axial coords (q, r), flat-top like the course grid:
##   x = SIZE * 1.5 * q,  z = SIZE * sqrt(3) * (r + q / 2)
## With SIZE = 0.5 every course hex centre is also a small hex centre, and each
## course hex covers about four small ones. Elevation is a seeded field (tilt,
## mounds and bowls, sometimes a tier, feeder valleys into the cup, ridges);
## the steepest few hexes of it become the green's slopes.

const SIZE := 0.5                   # small hex radius (course hexes are 1.0)
const STEP := 0.8660254             # distance between neighbouring small hexes (SIZE * sqrt(3))
const PUTT_BASE := 2                # pace before the flip; a lag putt is exactly this
const MAX_PUTTS := 4                # miss the 4th and pick up (scores MAX_PUTTS + 1)
const MAX_STEPS := 30               # safety cap on a putt's roll
const SLOPES_MIN := 4               # slope hexes per green: about 1 in 10, within these
const SLOPES_MAX := 10
const PREVIEW_TOTALS := 6           # the preview labels where paces 0..6 stop
const SURF_GREEN := 4
const SURF_FLAG := 8

# Axial neighbour steps, flat-top. Index = arrow direction.
const DIRS: Array[Vector2i] = [
	Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1),
	Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1),
]

var tiles: Dictionary = {}   # Vector2i axial -> {height: float, dir: int, strength: int, slick?: bool}
var features: Dictionary = {}  # Vector2i axial -> {kind: "coin" | "spike"}
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
	_place_slick(rng)
	_place_features(rng)
	_set_slopes()


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


func _set_slopes() -> void:
	"""Each hex's fall line (the downhill neighbour) from the height field, but
	only the steepest few hexes keep it as a slope: about one hex in ten, 4-10
	per green, never the cup, a slick hex or spike marks. The rest of the green
	is flat. Strength by rank among the slopes: the steeper 60% are 2, the
	rest 1, and a hex much steeper than the others is 3."""
	var drops := {}
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
			if h - hn > best_drop:
				best_drop = h - hn
				best_dir = i
		tiles[a].dir = best_dir
		tiles[a].strength = 0
		drops[a] = maxf(best_drop, 0.0)
	var open: Array = []
	for a in tiles:
		if a != cup and not is_slick(a) and features.get(a, {}).get("kind", "") != "spike" and drops[a] > 0.0:
			open.append(a)
	# Steepest first; ties by hex so the seed gives the same green every time
	open.sort_custom(func(x, y): return drops[x] > drops[y] if drops[x] != drops[y] else x < y)
	var count := mini(clampi(tiles.size() / 10, SLOPES_MIN, SLOPES_MAX), open.size())
	var picked: Array = open.slice(0, count)
	if picked.is_empty():
		return
	var median: float = drops[picked[picked.size() / 2]]
	for i in range(picked.size()):
		var a: Vector2i = picked[i]
		var s := 2 if i < ceili(picked.size() * 0.6) else 1
		if i == 0 and drops[a] > median * 1.6:
			s = 3
		tiles[a].strength = s


func slope_count() -> int:
	var n := 0
	for a in tiles:
		if tiles[a].strength > 0:
			n += 1
	return n


func _place_slick(rng: RandomNumberGenerator) -> void:
	"""One fast patch of 3-6 hexes, grown from a seed hex, clear of the cup.
	Slick hexes are never slopes (_set_slopes skips them)."""
	var open: Array[Vector2i] = []
	for a in tiles:
		if distance(a, cup) >= 2:
			open.append(a)
	open.sort()
	if open.size() < 12:
		return
	var patch: Array[Vector2i] = [open[rng.randi_range(0, open.size() - 1)]]
	var size := rng.randi_range(3, 6)
	for _grow in range(size * 4):
		if patch.size() >= size:
			break
		var from: Vector2i = patch[rng.randi_range(0, patch.size() - 1)]
		var nxt: Vector2i = from + DIRS[rng.randi_range(0, 5)]
		if tiles.has(nxt) and distance(nxt, cup) >= 2 and not patch.has(nxt):
			patch.append(nxt)
	for a in patch:
		tiles[a].slick = true


func is_slick(a: Vector2i) -> bool:
	return tiles.has(a) and tiles[a].get("slick", false)


func _place_features(rng: RandomNumberGenerator) -> void:
	"""Seeded green clutter: 1-2 spike marks and 1-2 coins, kept off the cup,
	its neighbours and the slick patch."""
	features.clear()
	var open: Array[Vector2i] = []
	for a in tiles:
		if distance(a, cup) >= 2 and not is_slick(a):
			open.append(a)
	open.sort()  # the seed must give the same green every time
	if open.is_empty():
		return
	for kind in ["spike", "coin"]:
		var count := rng.randi_range(1, 2)
		for _i in range(count):
			for _try in range(20):
				var a: Vector2i = open[rng.randi_range(0, open.size() - 1)]
				if not features.has(a):
					features[a] = {"kind": kind}
					break


# --- Putting ---

static func par_for(ball: Vector2i, cup_hex: Vector2i) -> int:
	"""The green's par from where the ball first lies: 2 within 4 hexes of the
	cup, otherwise 3."""
	return 2 if distance(ball, cup_hex) <= 4 else 3


func simulate_putt(start: Vector2i, dir: int, total: int, special: String = "", opts: Dictionary = {}) -> Dictionary:
	"""Roll a putt out of start in direction dir (0-5) with pace total. special:
	"lip" (the cup won't take it: it hangs on the edge, a hex short), "star"
	(drops at any pace, or from a hex beside the cup) or "". opts: steady (the
	slopes don't act), slow_break (default true: a strength-1 slope only bends
	a ball with 2 pace or less). Returns {path: Array[Vector2i] (ball first),
	end, holed, reason (short | rolled | ran | lipout | holed | fringe | spike),
	coins (rolled over), touched (unique hexes entered)}."""
	var path: Array[Vector2i] = [start]
	var result := {"path": path, "end": start, "holed": false, "reason": "rolled", "coins": [], "touched": 0}
	if total <= 0:
		result.reason = "short"
		return _finish(result)
	var steady: bool = opts.get("steady", false)
	var slow_break: bool = opts.get("slow_break", true)
	var pos := start
	var heading := posmod(dir, 6)
	var pace := total
	for _step in range(MAX_STEPS):
		if pace <= 0:
			break
		var nxt: Vector2i = pos + DIRS[heading]
		if not tiles.has(nxt):
			result.reason = "fringe"  # stops on the last green hex
			break
		pos = nxt
		pace -= 1
		path.append(pos)
		if pos == cup:
			if special == "lip":
				path.pop_back()
				result.end = path[path.size() - 1]
				result.reason = "lipout"
				return _finish(result)
			if special == "star" or pace <= 1:
				result.holed = true
				result.end = cup
				result.reason = "holed"
				return _finish(result)
			result.reason = "ran"  # too firm: over the cup and on
			continue
		var kind: String = features.get(pos, {}).get("kind", "")
		if kind == "coin" and not result.coins.has(pos):
			result.coins.append(pos)
		if kind == "spike":
			result.reason = "spike"
			break
		var t: Dictionary = tiles[pos]
		if t.strength > 0 and not steady:
			var off := posmod(int(t.dir) - heading, 6)
			if off == 0:
				pace += t.strength - 1  # downhill
			elif off == 3:
				pace -= t.strength - 1  # uphill
			elif t.strength >= 2 or not slow_break or pace <= 2:
				heading = posmod(heading + (1 if off < 3 else -1), 6)  # breaks toward the fall line
		if is_slick(pos):
			pace += 1
	if special == "star" and distance(pos, cup) == 1:
		path.append(cup)
		pos = cup
		result.holed = true
		result.reason = "holed"
	result.end = pos
	return _finish(result)


func preview(start: Vector2i, dir: int, opts: Dictionary = {}) -> Dictionary:
	"""The read for a line: where each pace 0..PREVIEW_TOTALS stops (no
	special card). Returns {marks: [{end, totals: Array[int], holed}], base
	(path at PUTT_BASE), long (path at PREVIEW_TOTALS)}."""
	var marks: Array = []
	var by_end := {}
	var base: Array[Vector2i] = []
	var long: Array[Vector2i] = []
	for t in range(PREVIEW_TOTALS + 1):
		var r := simulate_putt(start, dir, t, "", opts)
		if t == PUTT_BASE:
			base = r.path
		if t == PREVIEW_TOTALS:
			long = r.path
		if not by_end.has(r.end):
			by_end[r.end] = {"end": r.end, "totals": [] as Array[int], "holed": r.holed}
			marks.append(by_end[r.end])
		by_end[r.end].totals.append(t)
	return {"marks": marks, "base": base, "long": long}


func one_putt_chance(start: Vector2i, odds: Array, opts: Dictionary = {}) -> float:
	"""Best chance of holing from start over the six lines. odds: the flip's
	outcomes, [{mod, special, steady, p}] (PuttModifierDeck.chain_odds)."""
	var best := 0.0
	for d in range(6):
		var p := 0.0
		for o in odds:
			var o_opts := opts.duplicate()
			o_opts.steady = o.steady
			if simulate_putt(start, d, PUTT_BASE + int(o.mod), o.special, o_opts).holed:
				p += float(o.p)
		best = maxf(best, p)
	return best


func _finish(result: Dictionary) -> Dictionary:
	var unique := {}
	for a in result.path.slice(1):
		unique[a] = true
	result.touched = unique.size()
	return result
