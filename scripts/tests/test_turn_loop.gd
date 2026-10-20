extends Node

## test_turn_loop.gd - Isolated headless harness for the FEAT-002 footprint
## engine + board resolution + determinism + the R#5 crosswind-sign assertion.
##
## This harness is test-only and is NOT part of the shipped loop. It builds a
## small fixed hole + a tiny stub hole-controller (faithful hex math), wires the
## real systems (ShotManager, AOESystem, WindSystem, LieSystem, ModifierManager)
## and a TurnController, and proves the acceptance criteria. It exits with code 0
## on success and 1 on any failed assertion (AC12).

const HEX_GRID_SCRIPT := "res://scripts/hex_grid.gd"

# Surface enum (matches hex_grid.gd SurfaceType)
const TEE := 0
const FAIRWAY := 1
const ROUGH := 2
const DEEP_ROUGH := 3
const GREEN := 4
const SAND := 5
const WATER := 6
const TREE := 7
const FLAG := 8

var _failures: int = 0
var _checks: int = 0

# Pulled from the real hex_grid.gd constants so assertions compare against the
# live game data (R#4 invariant proof uses the real CLUB_STATS/ClubType).
var CLUB_STATS: Dictionary = {}
var ClubType: Dictionary = {}


# ---------------------------------------------------------------------------
# Lightweight stub hole-controller: faithful hex geometry, no rendering.
# ---------------------------------------------------------------------------
class StubHole extends Node3D:
	const TILE_SIZE := 1.0
	const TILE_SURFACE_OFFSET := 0.75
	const BALL_RADIUS_OFFSET := 0.15

	var grid_width: int = 7
	var grid_height: int = 24
	var grid: Array = []
	var elevation: Array = []
	var flag_position: Vector2i = Vector2i(-1, -1)
	var golf_ball: Node3D = null
	var CLUB_STATS: Dictionary = {}

	func init_grid(w: int, h: int) -> void:
		grid_width = w
		grid_height = h
		grid.clear()
		elevation.clear()
		for col in range(w):
			var column: Array = []
			var elev_column: Array = []
			for row in range(h):
				column.append(FAIRWAY)
				elev_column.append(0.0)
			grid.append(column)
			elevation.append(elev_column)

	func get_cell(col: int, row: int) -> int:
		if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
			return grid[col][row]
		return -1

	func set_cell(col: int, row: int, value: int) -> void:
		if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
			grid[col][row] = value

	func get_grid_width() -> int:
		return grid_width

	func get_grid_height() -> int:
		return grid_height

	func get_elevation(col: int, row: int) -> float:
		if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
			return elevation[col][row]
		return 0.0

	func set_elevation(col: int, row: int, value: float) -> void:
		if col >= 0 and col < grid_width and row >= 0 and row < grid_height:
			elevation[col][row] = value

	func get_tile_world_position(cell: Vector2i) -> Vector3:
		var width: float = TILE_SIZE
		var hex_height: float = TILE_SIZE * sqrt(3.0)
		var x_pos: float = cell.x * width * 1.5
		var z_pos: float = cell.y * hex_height + (cell.x % 2) * (hex_height / 2.0)
		var y_pos: float = get_elevation(cell.x, cell.y)
		return Vector3(x_pos, y_pos, z_pos)

	func get_tile_surface_position(cell: Vector2i) -> Vector3:
		var pos: Vector3 = get_tile_world_position(cell)
		pos.y += TILE_SURFACE_OFFSET + BALL_RADIUS_OFFSET
		return pos

	func get_tile_distance(from: Vector2i, to: Vector2i) -> int:
		var dx: int = abs(to.x - from.x)
		var dy: int = abs(to.y - from.y)
		return maxi(dx, dy + int(dx / 2))

	func get_adjacent_cells(col: int, row: int) -> Array[Vector2i]:
		var neighbors: Array[Vector2i] = []
		if col % 2 == 0:
			neighbors.append(Vector2i(col - 1, row - 1))
			neighbors.append(Vector2i(col - 1, row))
			neighbors.append(Vector2i(col, row - 1))
			neighbors.append(Vector2i(col, row + 1))
			neighbors.append(Vector2i(col + 1, row - 1))
			neighbors.append(Vector2i(col + 1, row))
		else:
			neighbors.append(Vector2i(col - 1, row))
			neighbors.append(Vector2i(col - 1, row + 1))
			neighbors.append(Vector2i(col, row - 1))
			neighbors.append(Vector2i(col, row + 1))
			neighbors.append(Vector2i(col + 1, row))
			neighbors.append(Vector2i(col + 1, row + 1))
		return neighbors

	func get_outer_ring_cells(col: int, row: int) -> Array[Vector2i]:
		var outer: Array[Vector2i] = []
		var inner := get_adjacent_cells(col, row)
		var seen: Dictionary = {}
		seen[Vector2i(col, row)] = true
		for cell in inner:
			seen[cell] = true
		for inner_cell in inner:
			var inner_neighbors := get_adjacent_cells(inner_cell.x, inner_cell.y)
			for neighbor in inner_neighbors:
				if not seen.has(neighbor):
					seen[neighbor] = true
					outer.append(neighbor)
		return outer


func _ready() -> void:
	print("=== test_turn_loop harness ===")
	_ensure_card_library()
	_load_real_club_stats()

	_test_ac3_band_fields()
	_test_ac4_six_directions()
	_test_ac5_tighten_and_ignore_wind()
	_test_r5_crosswind_sign()
	_test_ac6_determinism()
	_test_ac7_progress_toward_flag()
	_test_ac8_scoring_formula()
	_test_board_resolution_tree_water()

	print("=== harness complete: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Assertion helpers ---

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)


func _ensure_card_library() -> void:
	# CardLibrary is not an autoload; instantiate it so CardLibrary.instance is
	# populated and the SHOT cards (incl. the new footprint cards) register.
	if CardLibrary.instance == null:
		var lib := CardLibrary.new()
		add_child(lib)  # _ready sets CardLibrary.instance and registers cards
	_check(CardLibrary.instance != null, "CardLibrary instance available")


func _load_real_club_stats() -> void:
	var script: GDScript = load(HEX_GRID_SCRIPT)
	var consts: Dictionary = script.get_script_constant_map()
	CLUB_STATS = consts.get("CLUB_STATS", {})
	# ClubType enum is exposed as a dictionary constant on the script.
	ClubType = consts.get("ClubType", {})
	_check(not CLUB_STATS.is_empty(), "loaded real CLUB_STATS from hex_grid.gd")
	_check(ClubType.has("DRIVER"), "loaded real ClubType enum")


# --- Rig construction ---

func _build_hole() -> StubHole:
	# Fixed small hole: straight fairway up the center (+Y toward flag),
	# a bunker, a water hex, a tree, and a green+flag near the top.
	var hole := StubHole.new()
	hole.CLUB_STATS = CLUB_STATS
	hole.init_grid(7, 24)
	add_child(hole)

	var tee := Vector2i(3, 1)
	var flag := Vector2i(3, 20)
	hole.set_cell(tee.x, tee.y, TEE)
	hole.flag_position = flag

	# Green cluster around the flag.
	hole.set_cell(flag.x, flag.y, FLAG)
	for n in hole.get_adjacent_cells(flag.x, flag.y):
		if n.x >= 0 and n.x < hole.grid_width and n.y >= 0 and n.y < hole.grid_height:
			hole.set_cell(n.x, n.y, GREEN)

	# Hazards off the straight line so the clear tee shot stays clear.
	hole.set_cell(5, 6, SAND)     # bunker
	hole.set_cell(1, 9, WATER)    # water
	hole.set_cell(1, 12, TREE)    # tree

	return hole


func _make_turn_controller(hole: StubHole, use_rng: bool, hole_seed: int) -> TurnController:
	var aoe := AOESystem.new()
	add_child(aoe)

	var wind := WindSystem.new()
	add_child(wind)

	var lie := LieSystem.new()
	add_child(lie)

	var mod_mgr := ModifierManager.new()
	add_child(mod_mgr)

	var sm := ShotManager.new()
	add_child(sm)
	sm.set_hole_controller(hole)
	sm.set_aoe_system(aoe)
	sm.set_modifier_manager(mod_mgr)

	var hc := HoleContext.new()
	hc.seed = hole_seed
	hc.rng = RandomNumberGenerator.new()
	hc.rng.seed = hole_seed
	if use_rng:
		sm.rng = hc.rng

	var tc := TurnController.new()
	add_child(tc)
	tc.shot_manager = sm
	tc.aoe_system = aoe
	tc.wind_system = wind
	tc.lie_system = lie
	tc.hole_context = hc
	tc.hex_grid = hole
	sm.landing_resolved.connect(tc.apply_board_resolution)
	return tc


func _add_modifier_card(tc: TurnController, card_id: String) -> void:
	var data: CardData = CardLibrary.instance.get_card(card_id) if CardLibrary.instance else null
	if data == null:
		_check(false, "card '%s' exists in CardLibrary" % card_id)
		return
	var inst := CardInstance.create_from_data(data)
	# CardModifier bridges a CardInstance into the ModifierManager lifecycle
	# (apply_before_aim -> card.apply_effects(ctx, phase)).
	var modifier := CardModifier.new(inst)
	tc.shot_manager.modifier_manager.add_modifier(modifier)


func _clear_modifiers(tc: TurnController) -> void:
	tc.shot_manager.modifier_manager.clear_modifiers()


func _driver() -> int:
	return int(ClubType.get("DRIVER", 0))


func _putter() -> int:
	return int(ClubType.get("PUTTER", 11))


# --- Tests ---

func _test_ac3_band_fields() -> void:
	print("-- AC3: driver band fields + R#4 invariant --")
	var hole := _build_hole()
	var tc := _make_turn_controller(hole, false, 1)
	tc.ball_tile = Vector2i(3, 1)
	tc.played_club = _driver()
	tc.shot_manager.start_shot(null, tc.ball_tile)
	tc.set_aim_dir(3)  # toward flag (+Y)

	var ctx := tc.shot_manager.current_context
	var driver_stats: Dictionary = CLUB_STATS[_driver()]
	# CLUB_STATS carries no explicit band_center key; R#4 makes it equal to the
	# legacy .distance value, which TurnController reads as the band center.
	var expected_center: int = int(driver_stats.get("band_center", driver_stats.distance))
	_check(ctx.band_min == int(driver_stats.band_min), "band_min from CLUB_STATS[DRIVER]")
	_check(ctx.band_max == int(driver_stats.band_max), "band_max from CLUB_STATS[DRIVER]")
	_check(ctx.band_center == expected_center, "band_center from CLUB_STATS[DRIVER]")
	_check(ctx.base_spread == int(driver_stats.base_spread), "base_spread from CLUB_STATS[DRIVER]")
	_check(ctx.base_roll == int(driver_stats.roll), "base_roll from CLUB_STATS[DRIVER].roll")
	# R#4 invariant.
	_check(ctx.band_center == int(driver_stats.distance), "R#4: band_center == CLUB_STATS[DRIVER].distance")
	_cleanup()


func _test_ac4_six_directions() -> void:
	print("-- AC4: every aim_dir yields a valid footprint --")
	# Use a center tile with plenty of room in every direction.
	var hole := _build_hole()
	var tc := _make_turn_controller(hole, false, 1)
	tc.ball_tile = Vector2i(3, 11)
	tc.played_club = int(ClubType.get("PITCHING_WEDGE", 9))
	tc.shot_manager.start_shot(null, tc.ball_tile)

	for dir in range(6):
		tc.set_aim_dir(dir)
		var ctx := tc.shot_manager.current_context
		var non_empty := ctx.aoe_tiles.size() > 0
		var total_w := 0.0
		for t in ctx.aoe_tiles:
			total_w += float(ctx.aoe_weights.get(t, 0.0))
		var dist := hole.get_tile_distance(tc.ball_tile, ctx.aim_tile)
		# Center distance should fall within the band (clamped to grid bounds).
		var in_band := dist >= 0 and dist <= ctx.band_max + tc.BAND_MAX_SLACK
		_check(non_empty, "dir %d: non-empty aoe_tiles" % dir)
		_check(total_w > 0.0, "dir %d: positive total weight" % dir)
		_check(in_band, "dir %d: center distance %d within band" % [dir, dist])
	_cleanup()


func _test_ac5_tighten_and_ignore_wind() -> void:
	print("-- AC5: Tighten Spread concentrates; Ignore Wind is wind-independent --")

	# Tighten Spread: fewer hexes OR more concentrated weight than baseline.
	var hole := _build_hole()
	var tc := _make_turn_controller(hole, false, 1)
	tc.ball_tile = Vector2i(3, 1)
	tc.played_club = _driver()
	tc.shot_manager.start_shot(null, tc.ball_tile)
	tc.set_aim_dir(3)
	var base_ctx := tc.shot_manager.current_context
	var base_count := base_ctx.aoe_tiles.size()
	var base_peak_frac := _peak_weight_fraction(base_ctx)

	_add_modifier_card(tc, "tighten_spread")
	tc.rebuild()
	var tight_ctx := tc.shot_manager.current_context
	var tight_count := tight_ctx.aoe_tiles.size()
	var tight_peak_frac := _peak_weight_fraction(tight_ctx)
	_check(tight_count < base_count or tight_peak_frac > base_peak_frac,
		"Tighten Spread shrinks count (%d->%d) or concentrates weight (%.3f->%.3f)" % [base_count, tight_count, base_peak_frac, tight_peak_frac])
	_cleanup()

	# Ignore Wind: resolved center identical with and without a crosswind.
	var hole2 := _build_hole()
	var tc2 := _make_turn_controller(hole2, false, 1)
	tc2.ball_tile = Vector2i(3, 1)
	tc2.played_club = _driver()
	tc2.shot_manager.start_shot(null, tc2.ball_tile)

	# No wind.
	tc2.wind_system.enabled = false
	tc2.wind_system.strength = 0
	_add_modifier_card(tc2, "ignore_wind")
	tc2.set_aim_dir(3)
	var center_no_wind: Vector2i = tc2.shot_manager.current_context.aim_tile

	# Strong crosswind, still ignored.
	_configure_crosswind(tc2.wind_system)
	tc2.rebuild()
	var center_wind: Vector2i = tc2.shot_manager.current_context.aim_tile
	_check(center_no_wind == center_wind, "Ignore Wind: center unchanged by crosswind (%s == %s)" % [str(center_no_wind), str(center_wind)])
	_cleanup()


func _test_r5_crosswind_sign() -> void:
	print("-- R#5: crosswind pushes center to the expected side --")
	var d := 3  # aim toward flag (+Y)

	# Baseline center with no wind.
	var hole := _build_hole()
	var tc := _make_turn_controller(hole, false, 1)
	tc.ball_tile = Vector2i(3, 1)
	tc.played_club = _driver()
	tc.shot_manager.start_shot(null, tc.ball_tile)
	tc.wind_system.enabled = false
	tc.wind_system.strength = 0
	tc.set_aim_dir(d)
	var center_calm: Vector2i = tc.shot_manager.current_context.aim_tile
	_cleanup()

	# With a fixed crosswind.
	var hole2 := _build_hole()
	var tc2 := _make_turn_controller(hole2, false, 1)
	tc2.ball_tile = Vector2i(3, 1)
	tc2.played_club = _driver()
	tc2.shot_manager.start_shot(null, tc2.ball_tile)
	_configure_crosswind(tc2.wind_system)
	tc2.set_aim_dir(d)
	var ctx2 := tc2.shot_manager.current_context
	var center_wind: Vector2i = ctx2.aim_tile
	var wind_shift: int = ctx2.wind_curve

	_check(wind_shift != 0, "crosswind produced a non-zero wind_shift (%d)" % wind_shift)

	# Expected perp direction per R#5: +shift -> (d+2)%6, -shift -> (d+4)%6.
	var expected_dir := (d + 2) % 6 if wind_shift > 0 else (d + 4) % 6
	var opposite_dir := (d + 4) % 6 if wind_shift > 0 else (d + 2) % 6

	# Reconstruct where each perp direction would land the calm center, and
	# assert the windy center matches the EXPECTED side, not the opposite.
	var expected_center := _walk_dir(tc2.hex_grid, tc2.aoe_system, center_calm, expected_dir, abs(wind_shift))
	var opposite_center := _walk_dir(tc2.hex_grid, tc2.aoe_system, center_calm, opposite_dir, abs(wind_shift))

	_check(center_wind == expected_center,
		"center moved to expected side dir %d (%s == %s)" % [expected_dir, str(center_wind), str(expected_center)])
	_check(center_wind != opposite_center or expected_center == opposite_center,
		"center did NOT move to the opposite side dir %d" % opposite_dir)
	_cleanup()

	# Mirror crosswind: flip the wind to the opposite side and prove the sign
	# convention holds for the other sign too (the primary R#5 rule: +shift uses
	# (d+2)%6).
	var hole3 := _build_hole()
	var tc3 := _make_turn_controller(hole3, false, 1)
	tc3.ball_tile = Vector2i(3, 1)
	tc3.played_club = _driver()
	tc3.shot_manager.start_shot(null, tc3.ball_tile)
	_configure_crosswind_mirror(tc3.wind_system)
	tc3.set_aim_dir(d)
	var ctx3 := tc3.shot_manager.current_context
	var center_wind3: Vector2i = ctx3.aim_tile
	var wind_shift3: int = ctx3.wind_curve
	_check(sign(wind_shift3) == -sign(wind_shift), "mirror crosswind flips wind_shift sign (%d vs %d)" % [wind_shift3, wind_shift])
	var expected_dir3 := (d + 2) % 6 if wind_shift3 > 0 else (d + 4) % 6
	var expected_center3 := _walk_dir(tc3.hex_grid, tc3.aoe_system, center_calm, expected_dir3, abs(wind_shift3))
	_check(center_wind3 == expected_center3,
		"mirror center moved to expected side dir %d (%s == %s)" % [expected_dir3, str(center_wind3), str(expected_center3)])
	_cleanup()


func _test_ac6_determinism() -> void:
	print("-- AC6: fixed seed + fixed plan -> identical landing --")
	var landing_a := _run_seeded_shot(2024)
	var landing_b := _run_seeded_shot(2024)
	_check(landing_a == landing_b, "two seeded runs land identically (%s == %s)" % [str(landing_a), str(landing_b)])


func _run_seeded_shot(hole_seed: int) -> Vector2i:
	var hole := _build_hole()
	var tc := _make_turn_controller(hole, true, hole_seed)
	tc.ball_tile = Vector2i(3, 1)
	tc.played_club = _driver()
	tc.shot_manager.start_shot(null, tc.ball_tile)
	tc.set_aim_dir(3)
	tc.execute_shot()
	var landing: Vector2i = tc.shot_manager.current_context.landing_tile
	_cleanup()
	return landing


func _test_ac7_progress_toward_flag() -> void:
	print("-- AC7: a straight clear tee shot gets closer to the flag --")
	var hole := _build_hole()
	var tc := _make_turn_controller(hole, true, 7)
	tc.ball_tile = Vector2i(3, 1)
	tc.played_club = _driver()
	tc.shot_manager.start_shot(null, tc.ball_tile)
	tc.set_aim_dir(3)
	tc.execute_shot()
	var ctx := tc.shot_manager.current_context
	var start_dist := hole.get_tile_distance(tc.ball_tile, hole.flag_position)
	var land_dist := hole.get_tile_distance(ctx.landing_tile, hole.flag_position)
	_check(land_dist <= start_dist, "landing closer to flag (start %d -> landing %d)" % [start_dist, land_dist])
	_cleanup()


func _test_ac8_scoring_formula() -> void:
	print("-- AC8: final score == round(chips * mult); no gating --")
	var hole := _build_hole()
	var tc := _make_turn_controller(hole, true, 8)
	tc.ball_tile = Vector2i(3, 1)
	tc.played_club = _driver()
	tc.shot_manager.start_shot(null, tc.ball_tile)
	tc.set_aim_dir(3)
	tc.execute_shot()
	var ctx := tc.shot_manager.current_context
	var expected := int(round(ctx.chips * ctx.mult))
	_check(ctx.calculate_final_score() == expected, "calculate_final_score() == round(chips*mult) == %d" % expected)
	_cleanup()


func _test_board_resolution_tree_water() -> void:
	print("-- Board resolution: tree/water stops; punch passes tree --")
	# A hex row with a tree directly in the roll line.
	var hole := _build_hole()
	# Clear everything, put the ball low and a tree two hexes up the +Y line.
	var tc := _make_turn_controller(hole, false, 1)
	var ball := Vector2i(3, 2)
	tc.ball_tile = ball

	# Tree directly in the +Y roll path from the drawn landing hex.
	# Drive a short wedge so the landing is near the ball, then force landing.
	tc.played_club = int(ClubType.get("PITCHING_WEDGE", 9))
	tc.shot_manager.start_shot(null, ball)
	tc.set_aim_dir(3)
	var ctx := tc.shot_manager.current_context

	# Force a known landing hex and a known downstream tree, then resolve roll.
	var landing := Vector2i(3, 8)
	# Place a tree one hex past the landing in +Y, within roll reach.
	var tree_tile := tc.aoe_system._get_neighbor_in_direction(landing, 3, landing.x % 2 == 1)
	hole.set_cell(tree_tile.x, tree_tile.y, TREE)
	# Ensure a positive roll so the walk actually steps.
	ctx.base_roll = 3
	ctx.roll_mod = 0
	ctx.landing_tile = landing
	ctx.add_metadata("footprint_built", true)
	ctx.aim_dir = 3
	tc.apply_board_resolution(ctx)
	_check(ctx.landing_tile == landing, "non-punch roll stops before TREE (stayed at %s)" % str(ctx.landing_tile))

	# Punch passes through the tree.
	ctx.landing_tile = landing
	ctx.add_metadata("punch", true)
	tc.apply_board_resolution(ctx)
	_check(ctx.landing_tile != landing, "punch rolls THROUGH the tree (moved to %s)" % str(ctx.landing_tile))

	# Water stops the roll regardless.
	ctx.metadata.erase("punch")
	ctx.landing_tile = landing
	var water_tile := tc.aoe_system._get_neighbor_in_direction(landing, 3, landing.x % 2 == 1)
	hole.set_cell(water_tile.x, water_tile.y, WATER)
	tc.apply_board_resolution(ctx)
	_check(ctx.landing_tile == landing, "roll stops before WATER (stayed at %s)" % str(ctx.landing_tile))
	_cleanup()


# --- small utilities ---

func _peak_weight_fraction(ctx: ShotContext) -> float:
	var total := 0.0
	var peak := 0.0
	for t in ctx.aoe_tiles:
		var w := float(ctx.aoe_weights.get(t, 0.0))
		total += w
		peak = maxf(peak, w)
	if total <= 0.0:
		return 0.0
	return peak / total


func _configure_crosswind(wind: WindSystem) -> void:
	# Fixed, strong wind blowing across the +Y shot line. Direction index 0 is
	# W=(-1,0): perpendicular to the +Z (world) shot vector, giving a clear
	# non-zero crosswind component.
	wind.enabled = true
	wind.direction_index = 0
	wind.speed_kmh = 35.0
	wind.strength = 3


func _configure_crosswind_mirror(wind: WindSystem) -> void:
	# Opposite crosswind: direction index 4 is E=(1,0), mirroring index 0 (W).
	wind.enabled = true
	wind.direction_index = 4
	wind.speed_kmh = 35.0
	wind.strength = 3


func _walk_dir(hole, aoe: AOESystem, start: Vector2i, dir: int, steps: int) -> Vector2i:
	var tile := start
	for _i in range(steps):
		var is_odd := tile.x % 2 == 1
		var next: Vector2i = aoe._get_neighbor_in_direction(tile, dir, is_odd)
		if next.x < 0 or next.x >= hole.grid_width or next.y < 0 or next.y >= hole.grid_height:
			break
		tile = next
	return tile


func _cleanup() -> void:
	for child in get_children():
		child.queue_free()
	# Drain the just-queued frees synchronously enough for the next test; the
	# harness creates fresh nodes each test so stale ones never interfere.
