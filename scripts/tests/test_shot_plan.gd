extends Node

## test_shot_plan.gd - Headless harness for the prototype card-built flight
## (ShotPlan): power costs, landing ring, shape bulge, wind in the air, and
## trees blocking unlofted shots. Exits 0 on success, 1 on any failure.

const FAIRWAY := 1
const TREE := 7

var _failures: int = 0
var _checks: int = 0


## Minimal hole with hex_grid's real geometry (odd-q, x = col*1.5, z = row*sqrt3).
class StubHole extends RefCounted:
	var w := 21
	var h := 40
	var grid: Array = []

	func _init() -> void:
		for c in range(w):
			var col: Array = []
			col.resize(h)
			col.fill(1)
			grid.append(col)

	func get_cell(col: int, row: int) -> int:
		if col >= 0 and col < w and row >= 0 and row < h:
			return grid[col][row]
		return -1

	func set_cell(col: int, row: int, surface: int) -> void:
		grid[col][row] = surface

	func get_tile_surface_position(cell: Vector2i) -> Vector3:
		var hh := sqrt(3.0)
		return Vector3(cell.x * 1.5, 0.0, cell.y * hh + (cell.x % 2) * (hh / 2.0))

	func world_to_grid(p: Vector3) -> Vector2i:
		var hh := sqrt(3.0)
		var col := roundi(p.x / 1.5)
		var row := roundi((p.z - (col % 2) * (hh / 2.0)) / hh)
		return Vector2i(col, row)


func _ready() -> void:
	print("=== shot plan test ===")
	var hole := StubHole.new()
	var ball := Vector2i(10, 2)
	var target := Vector2i(10, 14)  # 12 hexes straight down the hole

	print("-- straight shot --")
	var plain := ShotPlan.build(hole, ball, target, {"power": 20})
	_check(plain.end == target, "no cards, no wind: lands on the tapped hex (%s)" % str(plain.end))
	_check(plain.carry == 12 and plain.cost == 12, "cost = carry = 12 hexes (got %d)" % plain.cost)
	_check(plain.ring == 0, "12/20 power (60%%) lands exactly: ring 0 (got %d)" % plain.ring)
	_check(plain.tiles[0] == ball and plain.tiles.size() >= 12, "path starts at the ball and walks the hexes")

	print("-- power and the landing ring --")
	_check(ShotPlan.build(hole, ball, target, {"power": 14}).ring == 1, "12/14 power (86%) -> ring 1")
	var over := ShotPlan.build(hole, ball, target, {"power": 10})
	_check(over.over == 2 and over.ring == 2, "12/10 power: 2 over -> ring 2 (over=%d ring=%d)" % [over.over, over.ring])
	var shaped_cost := ShotPlan.build(hole, ball, target, {"power": 20, "extra_cost": 3})
	_check(shaped_cost.cost == 15, "card costs add to the spend (12 + 3 = %d)" % shaped_cost.cost)
	_check(ShotPlan.build(hole, ball, target, {"power": 14, "ring_mod": -1}).ring == 0, "Dart (ring -1) tightens ring 1 -> 0")

	print("-- shape --")
	var draw := ShotPlan.build(hole, ball, target, {"power": 20, "bulge": 3.5})
	_check(draw.end == target, "a shaped shot still finishes on the target")
	var mid: Vector2 = draw.points[draw.points.size() / 2]
	var straight_mid := Vector2(15.0, (2 + 14) / 2.0 * sqrt(3.0))
	_check(absf(mid.x - straight_mid.x) > 4.0, "Hard Draw bows the flight sideways mid-flight (%.1f off line)" % absf(mid.x - straight_mid.x))
	var fade := ShotPlan.build(hole, ball, target, {"power": 20, "bulge": -3.5})
	var fmid: Vector2 = fade.points[fade.points.size() / 2]
	_check(signf(fmid.x - straight_mid.x) != signf(mid.x - straight_mid.x), "Fade bows the opposite way to Draw")

	print("-- wind in the air --")
	var windy := ShotPlan.build(hole, ball, target, {"power": 20, "wind_vec": Vector2(1, 0), "wind_strength": 3})
	_check(windy.end != target, "a full crosswind blows a 12-hex carry off the target (%s)" % str(windy.end))
	var short_windy := ShotPlan.build(hole, ball, Vector2i(10, 5), {"power": 20, "wind_vec": Vector2(1, 0), "wind_strength": 3})
	_check(absf(short_windy.points[-1].x - 15.0) < absf(windy.points[-1].x - 15.0), "longer carries drift further in the wind")
	var cheat := ShotPlan.build(hole, ball, target, {"power": 20, "wind_vec": Vector2(1, 0), "wind_strength": 3, "ignore_wind": true})
	_check(cheat.end == target, "Wind Cheater: the wind can't move the shot")

	print("-- trees --")
	hole.set_cell(10, 8, TREE)
	var into_trees := ShotPlan.build(hole, ball, target, {"power": 20})
	_check(into_trees.blocked and into_trees.end == Vector2i(10, 8), "a tree on the flight stops an unlofted shot there (%s)" % str(into_trees.end))
	_check(into_trees.ring == 0, "a blocked shot drops dead: ring 0")
	_check(not ShotPlan.build(hole, ball, target, {"power": 20, "loft": true}).blocked, "Loft clears the tree")
	var around := ShotPlan.build(hole, ball, target, {"power": 20, "bulge": 3.5})
	_check(not around.blocked and around.end == target, "a Hard Draw curves around the tree onto the target")

	print("=== shot plan test complete: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)
