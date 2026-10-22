extends RefCounted
class_name ShotPlan

## ShotPlan - The card-built flight path for one shot (prototype).
##
## Tap-first: the tapped hex is where the shot is aimed to land. Shape cards
## bow the flight to the side while still finishing on the target (a draw
## starts right and curves back left), wind bends the ball while it is in the
## air, and trees on the flight path stop it unless the shot is lofted.
##
## Everything is priced in power: each hex of carry costs 1 and shape cards
## add their own cost. The club's power is the budget; going over is allowed
## (the caller adds Strain cards) but widens the landing ring.
##
## build() is pure (reads the hole, writes nothing) so the preview and the
## resolved shot are always the same path.

const SURF_TREE := 7

const HEX_STEP := 1.7320508          # world distance between neighbouring hex centers
const SAMPLES_PER_HEX := 4
const WIND_LATERAL_PER_HEX := 0.05   # sideways push (hexes) per air hex per wind strength
const WIND_ALONG_PER_HEX := 0.025    # head/tail push (hexes) per air hex per wind strength
const EXACT_USAGE := 0.5             # at or under this share of power the shot lands exactly
const PUTT_EXACT_USAGE := 0.0        # putts always carry a ring (make odds live in TurnController)


static func build(hole, ball: Vector2i, target: Vector2i, opts: Dictionary = {}) -> Dictionary:
	"""opts: power:int, bulge:float (hexes, + bows right / curves left),
	   loft:bool, ignore_wind:bool, wind_vec:Vector2 (world x,z), wind_strength:int,
	   extra_cost:int (shape cards), spread:int (club scatter, default 1), ring_mod:int,
	   exact_usage:float (share of power at or under which the ring shrinks).
	   Returns {tiles, points, end, blocked, carry, cost, power, over, ring, tangent}."""
	var power: int = maxi(1, int(opts.get("power", 1)))
	var bulge: float = float(opts.get("bulge", 0.0))
	var loft: bool = opts.get("loft", false)
	var carry := hex_distance(ball, target)

	var p0 := _flat(hole.get_tile_surface_position(ball))
	var p1 := _flat(hole.get_tile_surface_position(target))
	var span := p1 - p0
	var length := span.length()
	var fwd := span / length if length > 0.0001 else Vector2(0, 1)
	var right := Vector2(-fwd.y, fwd.x)

	# Wind acts over the time in the air: it grows with carry.
	var lat_end := 0.0
	var along_end := 0.0
	if not opts.get("ignore_wind", false):
		var wind: Vector2 = opts.get("wind_vec", Vector2.ZERO)
		var strength := float(opts.get("wind_strength", 0))
		lat_end = wind.dot(right) * strength * WIND_LATERAL_PER_HEX * carry
		along_end = wind.dot(fwd) * strength * WIND_ALONG_PER_HEX * carry

	# Sample the curve: shape bows out and returns; wind drifts progressively.
	var samples := maxi(8, carry * SAMPLES_PER_HEX)
	var points: Array[Vector2] = []
	var tiles: Array[Vector2i] = []
	for i in range(samples + 1):
		var t := float(i) / float(samples)
		var p := p0 + fwd * (length * t + along_end * HEX_STEP * t) \
			+ right * (bulge * HEX_STEP * 4.0 * t * (1.0 - t) + lat_end * HEX_STEP * t * t)
		points.append(p)
		var tile: Vector2i = hole.world_to_grid(Vector3(p.x, 0.0, p.y))
		if tiles.is_empty() or tiles[tiles.size() - 1] != tile:
			tiles.append(tile)

	# Trees on the flight stop a shot that isn't lofted (the ball drops there).
	# The hex next to the ball is exempt: the ball can always chip out.
	var blocked := false
	if not loft:
		for i in range(2, tiles.size() - 1):
			if hole.get_cell(tiles[i].x, tiles[i].y) == SURF_TREE:
				tiles = tiles.slice(0, i + 1)
				blocked = true
				break
	var end: Vector2i = tiles[tiles.size() - 1]
	if blocked:
		# Trim the drawn curve at the tree
		var cut := points.size() - 1
		for i in range(points.size()):
			if hole.world_to_grid(Vector3(points[i].x, 0.0, points[i].y)) == end:
				cut = i
				break
		points = points.slice(0, cut + 1)

	var cost := carry + int(opts.get("extra_cost", 0))
	var over := maxi(0, cost - power)
	# Landing ring: the club's spread, one tighter for an easy swing, one wider
	# when overswinging; cards and the lie add or remove rings.
	var spread := int(opts.get("spread", 1))
	var usage := float(cost) / float(power)
	var ring := spread - 1 if usage <= float(opts.get("exact_usage", EXACT_USAGE)) else (spread if over == 0 else spread + 1)
	ring = maxi(0, ring + int(opts.get("ring_mod", 0)))
	if blocked:
		ring = 0

	# Direction of travel at the end of the curve (roll-out follows it)
	var tangent := fwd * (length + along_end * HEX_STEP) \
		+ right * (-4.0 * bulge * HEX_STEP + 2.0 * lat_end * HEX_STEP)

	return {
		"tiles": tiles,
		"points": points,
		"end": end,
		"blocked": blocked,
		"carry": carry,
		"cost": cost,
		"power": power,
		"over": over,
		"ring": ring,
		"tangent": tangent,
	}


static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac := _to_cube(a)
	var bc := _to_cube(b)
	return int((abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2)


static func _to_cube(o: Vector2i) -> Vector3i:
	var x := o.x
	var z := o.y - (o.x - (o.x & 1)) / 2
	return Vector3i(x, -x - z, z)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
