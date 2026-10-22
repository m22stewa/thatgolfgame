extends Node
class_name TurnController

## TurnController - Builds the shot "footprint" (weighted landing disk) from the
## current plan (club + modifier cards + aim) and drives the board-resolution
## roll/tree/water walk after the ball lands.
##
## FEAT-002 creates and unit-proves this controller via the headless harness.
## FEAT-003 wires it into the live loop. The builder preserves the pinned
## resolutions:
##   R#1 - reward chips come from the AIMED CENTER (ctx.aim_tile = footprint
##         center) via ShotContext.get_shot_distance(); landing terrain is
##         scored on the board-resolved hex.
##   R#2 - apply_board_resolution reconstructs the roll line itself, stopping
##         before OOB / WATER, and (for non-Punch/non-Stinger) before TREE.
##   R#3 - build_footprint sets metadata["footprint_built"]=true so the
##         ShotManager fast-path selects over the builder's aoe_tiles/weights.
##   R#5 - perp(fwd) for dominant hex direction d uses hex direction (d+2)%6 for
##         +shift and (d+4)%6 for -shift.

# --- Collaborators (assigned by the loop / harness) ---
var shot_manager: ShotManager = null
var card_system = null                 # CardSystemManager (optional in harness)
var aoe_system: AOESystem = null
var wind_system: WindSystem = null
var lie_system: LieSystem = null
var hole_context: HoleContext = null
var hex_grid: Node3D = null            # Hole controller (get_cell/get_tile_surface_position/...)

# --- Tuning constants ---
const MIN_WEIGHT: float = 0.05
const ROLL_IN_CHANCE: float = 0.15  # a full shot rolling dead onto the cup drops this often
# Chance a putt at the cup drops, by length in hexes (1 hex = 10 yd); a miss
# finishes next to the cup.
const PUTT_MAKE_CHANCE := {1: 0.6, 2: 0.4, 3: 0.25, 4: 0.15}
const BAND_MAX_SLACK: int = 2          # along-axis may exceed band_max by this much

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

# Terrain landing-weight multipliers (footprint builder only; does NOT touch
# AOESystem.calculate_weights_by_terrain).
const TERRAIN_FACTOR := {
	SURF_TEE: 1.15,
	SURF_FAIRWAY: 1.15,
	SURF_GREEN: 1.25,
	SURF_ROUGH: 0.90,
	SURF_DEEP_ROUGH: 0.75,
	SURF_SAND: 0.60,
	SURF_TREE: 0.45,
	SURF_WATER: 0.50,
	SURF_FLAG: 1.0,  # no pull toward the cup: aces stay rare
}

# The club currently played this turn (ClubType int). Set by the loop/harness
# before rebuild().
var played_club: int = -1
# World reference to the ball tile for this turn (shot start tile).
var ball_tile: Vector2i = Vector2i(-1, -1)
# Hex the player aimed at. When set, the shot follows the true line to it and
# the club band caps the carry; (-1,-1) falls back to the 6-direction aim_dir.
var aim_target: Vector2i = Vector2i(-1, -1)
# Prototype: with a tapped target, build the card-shaped flight (ShotPlan)
# instead of the club-band projection.
var path_mode: bool = true


# --- Public API ---

func begin_turn() -> void:
	"""Start the ShotManager shot for this turn from the ball tile, then build."""
	if shot_manager == null or hex_grid == null:
		return
	var ball_node: Node3D = hex_grid.get("golf_ball")
	shot_manager.start_shot(ball_node, ball_tile)
	rebuild()


func set_aim_dir(dir: int) -> void:
	"""Set the dominant hex aim direction (0..5) and rebuild the footprint."""
	var ctx := _ctx()
	if ctx == null:
		return
	ctx.aim_dir = ((dir % 6) + 6) % 6
	rebuild()


func rebuild() -> void:
	"""Re-run the reset -> lie -> club band -> modifiers -> project -> build
	contract. Invoked on every plan change (club / modifier / aim)."""
	var ctx := _ctx()
	if ctx == null:
		return

	var saved_aim_dir := ctx.aim_dir
	var saved_start := ctx.start_tile
	var saved_ball := ctx.ball
	var saved_hole := ctx.hole
	var saved_shot_index := ctx.shot_index

	ctx.reset()
	ctx.aim_dir = saved_aim_dir
	ctx.start_tile = saved_start
	# The ball node is replaced on penalties / new holes; never keep a freed one
	ctx.ball = saved_ball if is_instance_valid(saved_ball) else (hex_grid.get("golf_ball") if hex_grid else null)
	ctx.hole = saved_hole
	ctx.shot_index = saved_shot_index

	# 1. Lie (writes distance_mod/roll_mod/spread_mod/chips/mult + allowed_clubs)
	if lie_system != null and ctx.start_tile.x >= 0 and hex_grid != null:
		var lie_info := lie_system.calculate_lie(hex_grid, ctx.start_tile)
		lie_system.apply_lie_to_shot(ctx, lie_info)

	# 2. Club band -> base footprint fields (R#4: band_center == CLUB_STATS.distance)
	_write_band_from_club(ctx, played_club)

	# 3. Re-apply all currently-played shot-shape / modifier cards.
	var mod_mgr = _modifier_manager()
	if mod_mgr != null and mod_mgr.has_method("apply_before_aim"):
		mod_mgr.apply_before_aim(ctx)

	# 4. Project center + build the footprint disk.
	build_footprint(ctx)


func execute_shot() -> void:
	"""Confirm the shot through the ShotManager (fast-path consumes the built
	footprint)."""
	if shot_manager != null:
		shot_manager.confirm_shot()


func terrain_factor(surface: int) -> float:
	"""Const landing-weight multiplier per surface, clamped to a floor of 0.30."""
	var raw: float = TERRAIN_FACTOR.get(surface, 1.0)
	return maxf(raw, 0.30)


# --- Footprint builder ---

func build_footprint(ctx: ShotContext) -> void:
	"""Build the weighted landing disk from the current plan. Sets ctx.aim_tile
	to the footprint center (R#1) and metadata["footprint_built"] (R#3)."""
	if hex_grid == null or aoe_system == null:
		return
	if ball_tile.x < 0:
		return

	# Aim at a hex: carry toward it (clamped to the club band) along the true
	# line; aim_dir becomes the nearest hex direction (perp shift + roll-out).
	var aiming_at_target := aim_target.x >= 0 and aim_target != ball_tile
	if path_mode and aiming_at_target:
		_build_path_footprint(ctx)
		return
	var base_along := ctx.band_center + ctx.distance_mod
	if aiming_at_target:
		ctx.aim_dir = _dominant_dir(ball_tile, aim_target)
		base_along = clampi(_hex_distance(ball_tile, aim_target), ctx.band_min, ctx.band_max) + ctx.distance_mod

	# --- Provisional along-axis carry (no wind head/tail yet) ---
	var provisional_center := _project(ball_tile, aiming_at_target, ctx.aim_dir, maxi(0, base_along))
	var elevation_adjust := _elevation_adjust(ball_tile, provisional_center)
	base_along += elevation_adjust

	# --- Wind: head/tail distance and crosswind shift from the shot vector ---
	var shot_vec := _shot_vector(ball_tile, provisional_center)
	var wind_shift := 0
	var head_tail := 0
	if wind_system != null:
		wind_shift = wind_system.calculate_wind_curve(shot_vec)
		head_tail = clampi(int(round(wind_system.get_direction_vector().dot(shot_vec) * float(wind_system.strength) * 0.5)), -2, 2)
	# Ignore-wind shots zero both BEFORE applying.
	if ctx.get_metadata("ignore_wind", false):
		wind_shift = 0
		head_tail = 0
	ctx.wind_curve = wind_shift

	# --- Final along-axis carry ---
	var along := base_along + head_tail
	# Card overrides (flop / bump set to band_min; stinger adds; punch caps).
	if ctx.has_metadata("along_axis_override"):
		along = int(ctx.get_metadata("along_axis_override", along))
	along += int(ctx.get_metadata("along_axis_add", 0))
	if ctx.has_metadata("along_axis_cap"):
		along = mini(along, int(ctx.get_metadata("along_axis_cap", along)))
	along = clampi(along, ctx.band_min, ctx.band_max + BAND_MAX_SLACK)

	# --- Walk to the footprint center, then apply perp shift ---
	var center := _project(ball_tile, aiming_at_target, ctx.aim_dir, maxi(0, along))
	var perp_shift := wind_shift + int(round(ctx.curve_strength))
	if perp_shift != 0:
		center = _apply_perp_shift(center, ctx.aim_dir, perp_shift)

	# R#1: aimed center drives scoring chips via get_shot_distance().
	ctx.aim_tile = center

	# --- Spread radius + weighted disk ---
	_weigh_disk(ctx, center, maxi(0, ctx.base_spread + ctx.spread_mod))
	ctx.add_metadata("footprint_built", true)


func _build_path_footprint(ctx: ShotContext) -> void:
	"""Prototype: the flight is built from the tapped target + shape cards
	(ShotPlan). The landing ring sits on the path's end, roll follows the
	curve's final heading, and a tree-blocked flight drops dead."""
	var wind_vec := Vector2.ZERO
	var strength := 0
	if wind_system != null:
		wind_vec = wind_system.get_direction_vector()
		strength = wind_system.strength
	# A club can't be hit shorter than its band: a short tap is carried out to band_min.
	var target := aim_target
	if ctx.band_min > 0 and _hex_distance(ball_tile, target) < ctx.band_min:
		target = _point_along(ball_tile, aim_target, ctx.band_min)
	var plan := ShotPlan.build(hex_grid, ball_tile, target, {
		"power": ctx.band_max + ctx.distance_mod,
		"bulge": float(ctx.get_metadata("shape_bulge", 0.0)),
		"loft": ctx.get_metadata("loft", false),
		"ignore_wind": ctx.get_metadata("ignore_wind", false),
		"wind_vec": wind_vec,
		"wind_strength": strength,
		"extra_cost": int(ctx.get_metadata("power_cost", 0)),
		"spread": ctx.base_spread,
		"exact_usage": ShotPlan.PUTT_EXACT_USAGE if played_club == int(hex_grid.ClubType.PUTTER) else ShotPlan.EXACT_USAGE,
		"ring_mod": int(ctx.get_metadata("ring_mod", 0)) + ctx.spread_mod,
	})
	var center: Vector2i = plan.end
	ctx.aim_tile = center
	# Putts are all ground: the path IS the roll
	if played_club == int(hex_grid.ClubType.PUTTER):
		ctx.base_roll = 0
		ctx.add_metadata("all_ground", true)
	ctx.aim_dir = _dir_for_vector(center, plan.tangent)
	ctx.wind_curve = 0
	ctx.add_metadata("shot_plan", plan)
	if plan.blocked:
		ctx.add_metadata("path_blocked", true)
	_weigh_disk(ctx, center, plan.ring)
	if played_club == int(hex_grid.ClubType.PUTTER) and center == _cup() and plan.ring > 0:
		_weigh_putt(ctx, center, int(plan.carry))
	ctx.add_metadata("footprint_built", true)


func _weigh_putt(ctx: ShotContext, cup: Vector2i, length: int) -> void:
	"""Re-weight a putt's ring so the cup hex carries the make chance for its
	length; the rest of the ring is where a miss stops."""
	var make: float = PUTT_MAKE_CHANCE.get(clampi(length, 1, 4), 0.2)
	var others := 0.0
	for t in ctx.aoe_tiles:
		if t == cup:
			continue
		# A missed putt stays on the green
		if _surface_at(t) != SURF_GREEN:
			ctx.aoe_weights.erase(t)
			continue
		others += float(ctx.aoe_weights.get(t, 0.0))
	var kept: Array[Vector2i] = []
	for t in ctx.aoe_tiles:
		if ctx.aoe_weights.has(t):
			kept.append(t)
	ctx.aoe_tiles = kept
	if others > 0.0:
		ctx.aoe_weights[cup] = others * make / (1.0 - make)
	ctx.add_metadata("putt_make_chance", make)


func _weigh_disk(ctx: ShotContext, center: Vector2i, radius: int) -> void:
	"""Candidate landing hexes around center, weighted by falloff x terrain."""
	var tiles: Array[Vector2i] = aoe_system.compute_circle_aoe(center, radius, hex_grid)
	if tiles.is_empty():
		tiles = [center]
	ctx.aoe_tiles = tiles
	ctx.aoe_radius = radius

	var weights: Dictionary = {}
	for t in tiles:
		var d := _hex_distance(center, t)
		var falloff: float = pow(float(radius + 1 - d), ctx.falloff_pow)
		var surface := _surface_at(t)
		var w: float = falloff * terrain_factor(surface)
		weights[t] = maxf(w, MIN_WEIGHT)
	ctx.aoe_weights = weights


# --- Board resolution (R#2) ---

func apply_board_resolution(ctx: ShotContext) -> void:
	"""Connected to ShotManager.landing_resolved. Reconstructs the roll line from
	the drawn landing hex, applies the green slope nudge, handles water, and
	mutates ctx.landing_tile IN PLACE before _simulate_ball_path / _compute_scoring.
	Only runs for footprint-built shots (leaves the legacy path untouched)."""
	if not ctx.get_metadata("footprint_built", false):
		return
	if hex_grid == null:
		return

	var passes_tree: bool = ctx.get_metadata("punch", false) or ctx.get_metadata("stinger", false)

	# Roll distance: base_roll + roll_mod + terrain roll of the landing surface.
	var landing := ctx.landing_tile
	var landing_surface := _surface_at(landing)
	var cup := _cup()
	var roll := maxi(0, ctx.base_roll + ctx.roll_mod + _terrain_roll(landing_surface))
	if ctx.get_metadata("path_blocked", false):
		roll = 0  # dropped out of the trees
	# No roll out of the water or off the course
	if landing_surface == SURF_WATER or landing_surface < 0:
		roll = 0

	var tile := landing
	var rolled: Array[Vector2i] = []
	var on_cup := landing == cup or landing_surface == SURF_FLAG
	if on_cup and ctx.get_metadata("all_ground", false):
		roll = 0  # a putt that finishes on the cup drops
	elif on_cup:
		# Landing on the cup from the air: it hits the pin and kicks one hex
		# past (a great approach, not a hole-out). Only rolling balls drop.
		var kick: Vector2i = aoe_system._get_neighbor_in_direction(tile, ctx.aim_dir, tile.x % 2 == 1)
		if _in_bounds(kick) and _surface_at(kick) != SURF_WATER:
			tile = kick
			rolled.append(tile)
		roll = 0

	# R#2: step along aim_dir `roll` times, recomputing parity each step; stop
	# before OOB / WATER, and (unless Punch/Stinger) before TREE. A ball rolling
	# over the cup drops only if it is slow (1 hex of roll or less left).
	for i in range(roll):
		var is_odd := tile.x % 2 == 1
		var next: Vector2i = aoe_system._get_neighbor_in_direction(tile, ctx.aim_dir, is_odd)
		if not _in_bounds(next):
			break
		var next_surface := _surface_at(next)
		if next_surface == SURF_WATER:
			break
		if next_surface == SURF_TREE and not passes_tree:
			break
		tile = next
		rolled.append(tile)
		# Rolling over the cup: only a slow ball can drop, and it can lip out
		if (tile == cup or next_surface == SURF_FLAG) and roll - i - 1 <= 1:
			var rng: RandomNumberGenerator = hole_context.rng if hole_context else null
			if (rng.randf() if rng else randf()) < ROLL_IN_CHANCE:
				break

	# Deterministic green slope nudge (design §4.3).
	if _surface_at(tile) == SURF_GREEN and tile != cup:
		var nudged := _green_slope_nudge(tile, ctx.aim_dir)
		if nudged != tile:
			tile = nudged
			rolled.append(tile)

	# Water handling: if the final hex is water, flag it (drop logic lives in the
	# loop; here we only tag so scoring/loop can react).
	if _surface_at(tile) == SURF_WATER:
		ctx.add_metadata("hit_water", true)

	# The ball's actual journey, replayed exactly by the animation
	ctx.add_metadata("carry_tile", landing)
	ctx.add_metadata("roll_tiles", rolled)

	# Mutate in place before scoring (R#1: landing terrain scored on this hex).
	ctx.landing_tile = tile


# --- Helpers ---

func _ctx() -> ShotContext:
	if shot_manager == null:
		return null
	return shot_manager.current_context


func _modifier_manager():
	if shot_manager == null:
		return null
	return shot_manager.modifier_manager


func _cup() -> Vector2i:
	if hex_grid == null:
		return Vector2i(-1, -1)
	var f = hex_grid.get("flag_position")
	return f if f is Vector2i else Vector2i(-1, -1)


func _write_band_from_club(ctx: ShotContext, club: int) -> void:
	if hex_grid == null or club < 0:
		return
	var stats: Dictionary = hex_grid.CLUB_STATS.get(club, {})
	if stats.is_empty():
		return
	ctx.band_min = int(stats.get("band_min", 0))
	ctx.band_max = int(stats.get("band_max", 0))
	ctx.band_center = int(stats.get("band_center", int(stats.get("distance", 0))))
	# R#4 fallback: keep band_center aligned with the legacy distance value.
	if not stats.has("band_center"):
		ctx.band_center = int(stats.get("distance", ctx.band_center))
	ctx.base_spread = int(stats.get("base_spread", 0))
	ctx.base_roll = int(stats.get("roll", 0))


func _walk(start: Vector2i, dir: int, steps: int) -> Vector2i:
	"""Step `steps` times in hex direction dir, recomputing parity each step and
	stopping before out-of-bounds."""
	var tile := start
	for _i in range(steps):
		var is_odd := tile.x % 2 == 1
		var next: Vector2i = aoe_system._get_neighbor_in_direction(tile, dir, is_odd)
		if not _in_bounds(next):
			break
		tile = next
	return tile


func _project(start: Vector2i, aiming_at_target: bool, dir: int, steps: int) -> Vector2i:
	"""Hex `steps` from start along the line to aim_target (or hex dir)."""
	if aiming_at_target:
		return _point_along(start, aim_target, steps)
	return _walk(start, dir, steps)


func _point_along(start: Vector2i, toward: Vector2i, steps: int) -> Vector2i:
	"""Hex `steps` away from start on the straight line through `toward` (may
	pass beyond it). Pulled back toward start until in bounds."""
	var dist := _hex_distance(start, toward)
	if dist == 0 or steps <= 0:
		return start
	var a := Vector3(_offset_to_cube(start)) + Vector3(1e-6, 2e-6, -3e-6)
	var b := Vector3(_offset_to_cube(toward)) + Vector3(1e-6, 2e-6, -3e-6)
	for s in range(steps, 0, -1):
		var tile := _cube_to_offset(_cube_round(a.lerp(b, float(s) / float(dist))))
		if _in_bounds(tile):
			return tile
	return start


func _dir_for_vector(tile: Vector2i, vec: Vector2) -> int:
	"""The hex direction (0..5) from tile that best matches a world (x,z) vector."""
	var is_odd := tile.x % 2 == 1
	var best_dir := 3
	var best_dot := -INF
	for d in range(6):
		var n: Vector2i = aoe_system._get_neighbor_in_direction(tile, d, is_odd)
		var dot := _shot_vector(tile, n).dot(vec)
		if dot > best_dot:
			best_dot = dot
			best_dir = d
	return best_dir


func _dominant_dir(from_tile: Vector2i, to_tile: Vector2i) -> int:
	"""The hex direction (0..5) whose neighbor step best matches from->to."""
	var target_vec := _shot_vector(from_tile, to_tile)
	var is_odd := from_tile.x % 2 == 1
	var best_dir := 3
	var best_dot := -INF
	for d in range(6):
		var n: Vector2i = aoe_system._get_neighbor_in_direction(from_tile, d, is_odd)
		var dot := _shot_vector(from_tile, n).dot(target_vec)
		if dot > best_dot:
			best_dot = dot
			best_dir = d
	return best_dir


func _apply_perp_shift(center: Vector2i, aim_dir: int, perp_shift: int) -> Vector2i:
	"""R#5: +shift uses hex direction (d+2)%6, -shift uses (d+4)%6."""
	var d := ((aim_dir % 6) + 6) % 6
	var perp_dir := (d + 2) % 6 if perp_shift > 0 else (d + 4) % 6
	return _walk(center, perp_dir, abs(perp_shift))


func _green_slope_nudge(tile: Vector2i, aim_dir: int) -> Vector2i:
	"""If the hex is GREEN and a neighbor is meaningfully downhill, push one hex
	downhill (deterministic: pick the steepest drop, break ties by direction)."""
	var here_elev := _elevation_at(tile)
	var best_dir := -1
	var best_drop := 0.25  # threshold
	for dir in range(6):
		var is_odd := tile.x % 2 == 1
		var n: Vector2i = aoe_system._get_neighbor_in_direction(tile, dir, is_odd)
		if not _in_bounds(n):
			continue
		# The slope only moves the ball along the green (or into the cup)
		if _surface_at(n) != SURF_GREEN and _surface_at(n) != SURF_FLAG and n != _cup():
			continue
		var drop := here_elev - _elevation_at(n)
		if drop > best_drop:
			best_drop = drop
			best_dir = dir
	if best_dir >= 0:
		var is_odd2 := tile.x % 2 == 1
		return aoe_system._get_neighbor_in_direction(tile, best_dir, is_odd2)
	return tile


func _shot_vector(from_tile: Vector2i, to_tile: Vector2i) -> Vector2:
	"""World-space delta projected to Vector2(x, z), normalized."""
	if hex_grid == null:
		return Vector2.ZERO
	var a: Vector3 = hex_grid.get_tile_surface_position(to_tile)
	var b: Vector3 = hex_grid.get_tile_surface_position(from_tile)
	var v := Vector2(a.x - b.x, a.z - b.z)
	if v.length() < 0.0001:
		return Vector2.ZERO
	return v.normalized()


func _elevation_adjust(from_tile: Vector2i, to_tile: Vector2i) -> int:
	"""Downhill target (lower than the ball) adds carry; uphill subtracts."""
	var delta := _elevation_at(from_tile) - _elevation_at(to_tile)
	return int(round(clampf(delta * 0.5, -3.0, 3.0)))


func _elevation_at(tile: Vector2i) -> float:
	if hex_grid != null and hex_grid.has_method("get_elevation"):
		return hex_grid.get_elevation(tile.x, tile.y)
	return 0.0


func _surface_at(tile: Vector2i) -> int:
	if hex_grid != null and hex_grid.has_method("get_cell"):
		return hex_grid.get_cell(tile.x, tile.y)
	return SURF_FAIRWAY


func _terrain_roll(surface: int) -> int:
	"""Additive roll contribution from the landing surface."""
	match surface:
		SURF_FAIRWAY, SURF_TEE:
			return 0
		SURF_GREEN:
			return 0
		SURF_ROUGH:
			return -1
		SURF_DEEP_ROUGH:
			return -2
		SURF_SAND:
			return -2
		SURF_TREE:
			return -1
		_:
			return 0


func _in_bounds(tile: Vector2i) -> bool:
	if hex_grid == null:
		return false
	var w: int = hex_grid.get_grid_width() if hex_grid.has_method("get_grid_width") else int(hex_grid.get("grid_width"))
	var h: int = hex_grid.get_grid_height() if hex_grid.has_method("get_grid_height") else int(hex_grid.get("grid_height"))
	return tile.x >= 0 and tile.x < w and tile.y >= 0 and tile.y < h


func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	"""Offset-coordinate hex distance (odd-q vertical layout)."""
	var ac := _offset_to_cube(a)
	var bc := _offset_to_cube(b)
	return int((abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2)


func _cube_to_offset(c: Vector3i) -> Vector2i:
	return Vector2i(c.x, c.z + int((c.x - (c.x & 1)) / 2))


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


func _offset_to_cube(hex: Vector2i) -> Vector3i:
	# odd-q offset -> cube (columns are x; odd columns pushed down)
	var x := hex.x
	var z := hex.y - int((hex.x - (hex.x & 1)) / 2)
	var y := -x - z
	return Vector3i(x, y, z)
