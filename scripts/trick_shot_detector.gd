extends RefCounted
class_name TrickShotDetector

## TrickShotDetector - Awards points (the run's currency) for skillful shots.
## Strokes vs par is the real score; points are earned from trick shots, coins
## and hole results, then spent in the shop between holes.
##
##   Shot tricks     -> score_shot(ctx), called from ShotManager's scoring phase.
##                      Writes ctx.chips / ctx.mult so cards can still boost them.
##   Hole-out tricks -> score_hole_out(start_tile, strokes), called when the ball drops.
##
## A fairway streak (consecutive shots finishing on fairway/green) raises the
## mult, so stringing good shots together makes tricks worth more.

# Surface enum (matches hex_grid.gd SurfaceType)
const SURF_TEE := 0
const SURF_FAIRWAY := 1
const SURF_ROUGH := 2
const SURF_DEEP_ROUGH := 3
const SURF_GREEN := 4
const SURF_SAND := 5
const SURF_WATER := 6
const SURF_TREE := 7
const SURF_FLAG := 8

const TRICKS := {
	"water_carry": {"name": "Over the Water", "points": 30},
	"bunker_blast": {"name": "Bunker Blast", "points": 40},
	"great_escape": {"name": "Great Escape", "points": 25},
	"stuck_green": {"name": "Stuck the Green", "points": 20},
	"pin_seeker": {"name": "Pin Seeker", "points": 40},
	"hole_in_one": {"name": "Hole in One!", "points": 300},
	"chip_in": {"name": "Chip-in", "points": 100},
	"long_putt": {"name": "Long Putt", "points": 50},
	"ice_run": {"name": "Ice Run", "points": 20},
	"boing": {"name": "Boing!", "points": 15},
	"tunnel_ride": {"name": "Tunnel Ride", "points": 15},
}

const COIN_POINTS := 25
const STUCK_GREEN_MIN_DIST := 8     # approach length (hexes) to count as "stuck"
const PIN_SEEKER_MIN_DIST := 6      # must start at least this far from the flag
const PIN_SEEKER_RADIUS := 1        # finish within this many hexes of the flag
const LONG_PUTT_MIN_DIST := 3
const STREAK_MULT_STEP := 0.5       # mult = 1 + step * (streak - 1)

# Hole controller (get_cell / flag_position). Set by the owner.
var hole = null
var fairway_streak: int = 0


func reset_hole() -> void:
	"""New hole: streak starts over."""
	fairway_streak = 0


# --- Shot tricks (scoring phase) ---

func score_shot(ctx: ShotContext) -> Array:
	"""Detect tricks for a resolved shot. Sets ctx.base_chips/chips/mult and
	   metadata["tricks"] (Array of {id, name, points}). Returns the tricks."""
	var tricks: Array = []
	var start := ctx.start_tile
	var landing := ctx.landing_tile
	var start_surf := _surface(start)
	var land_surf := _surface(landing)
	var lands_safe := land_surf != SURF_WATER and land_surf != -1
	var on_green := land_surf == SURF_GREEN or land_surf == SURF_FLAG
	var shot_len := hex_distance(start, landing)

	if lands_safe and _carries_water(start, landing):
		tricks.append(_trick("water_carry"))
	if start_surf == SURF_SAND and on_green:
		tricks.append(_trick("bunker_blast"))
	if (start_surf == SURF_TREE or start_surf == SURF_DEEP_ROUGH) and (land_surf == SURF_FAIRWAY or on_green):
		tricks.append(_trick("great_escape"))
	if on_green and start_surf != SURF_GREEN and shot_len >= STUCK_GREEN_MIN_DIST:
		tricks.append(_trick("stuck_green"))
	if ctx.has_metadata("ice_run"):
		tricks.append(_trick("ice_run"))
	if ctx.has_metadata("bounced") and lands_safe:
		tricks.append(_trick("boing"))
	if ctx.has_metadata("tunnel_ride") and lands_safe:
		tricks.append(_trick("tunnel_ride"))
	var flag := _flag()
	if flag.x >= 0 and hex_distance(landing, flag) <= PIN_SEEKER_RADIUS and hex_distance(start, flag) >= PIN_SEEKER_MIN_DIST:
		tricks.append(_trick("pin_seeker"))

	# Fairway streak feeds the mult
	if land_surf == SURF_FAIRWAY or on_green:
		fairway_streak += 1
	else:
		fairway_streak = 0

	var chips := 0
	for t in tricks:
		chips += t.points
	ctx.base_chips = chips
	ctx.chips = chips
	ctx.mult = 1.0 + STREAK_MULT_STEP * maxi(0, fairway_streak - 1)
	ctx.add_metadata("tricks", tricks)
	ctx.add_metadata("fairway_streak", fairway_streak)
	return tricks


# --- Hole-out tricks ---

func score_hole_out(start_tile: Vector2i, strokes: int) -> Array:
	"""Tricks for the stroke that holed out, played from start_tile."""
	if strokes == 1:
		return [_trick("hole_in_one")]
	var start_surf := _surface(start_tile)
	if start_surf == SURF_GREEN:
		if hex_distance(start_tile, _flag()) >= LONG_PUTT_MIN_DIST:
			return [_trick("long_putt")]
		return []
	return [_trick("chip_in")]


# --- Hex helpers (odd-q offset, matches hex_grid.offset_to_cube) ---

func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac := _to_cube(a)
	var bc := _to_cube(b)
	return int((abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2)


func hex_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	"""Hexes on the straight line from a to b (inclusive)."""
	var line: Array[Vector2i] = []
	var n := hex_distance(a, b)
	var ac := Vector3(_to_cube(a)) + Vector3(1e-6, 2e-6, -3e-6)  # nudge off ties
	var bc := Vector3(_to_cube(b)) + Vector3(1e-6, 2e-6, -3e-6)
	for i in range(n + 1):
		var t := 0.0 if n == 0 else float(i) / float(n)
		line.append(_from_cube(_cube_round(ac.lerp(bc, t))))
	return line


func _carries_water(start: Vector2i, landing: Vector2i) -> bool:
	var line := hex_line(start, landing)
	for i in range(1, line.size() - 1):
		if _surface(line[i]) == SURF_WATER:
			return true
	return false


func _to_cube(o: Vector2i) -> Vector3i:
	var x := o.x
	var z := o.y - (o.x - (o.x & 1)) / 2
	return Vector3i(x, -x - z, z)


func _from_cube(c: Vector3i) -> Vector2i:
	return Vector2i(c.x, c.z + (c.x - (c.x & 1)) / 2)


func _cube_round(c: Vector3) -> Vector3i:
	var rx := roundf(c.x)
	var ry := roundf(c.y)
	var rz := roundf(c.z)
	var dx := absf(rx - c.x)
	var dy := absf(ry - c.y)
	var dz := absf(rz - c.z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3i(int(rx), int(ry), int(rz))


func _surface(tile: Vector2i) -> int:
	if hole == null:
		return -1
	return hole.get_cell(tile.x, tile.y)


func _flag() -> Vector2i:
	if hole == null:
		return Vector2i(-1, -1)
	var f = hole.get("flag_position")
	return f if f is Vector2i else Vector2i(-1, -1)


func _trick(id: String) -> Dictionary:
	return {"id": id, "name": TRICKS[id].name, "points": TRICKS[id].points}
