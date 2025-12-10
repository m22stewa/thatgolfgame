extends Node
class_name ShotManager

## ShotManager - Owns the shot lifecycle and emits signals at each phase.
## Other systems hook into signals to stay decoupled.

# Signals for shot lifecycle phases
signal shot_started(context: ShotContext)
signal modifiers_applied_before_aim(context: ShotContext)
signal player_aiming(context: ShotContext)
signal aoe_computed(context: ShotContext)
signal modifiers_applied_on_aoe(context: ShotContext)
signal landing_resolved(context: ShotContext)
signal ball_path_simulated(context: ShotContext)
signal scoring_computed(context: ShotContext)
signal modifiers_applied_on_scoring(context: ShotContext)
signal shot_completed(context: ShotContext)

# References
var hole_controller: Node3D = null   # Reference to hex_grid.gd node
var aoe_system: Node = null          # Reference to AOESystem
var modifier_manager: Node = null    # Reference to ModifierManager

# Current shot context
var current_context: ShotContext = null

# Shot state
var is_shot_in_progress: bool = false
var is_animating: bool = false  # True while ball is in flight/bouncing

# Animation speed control
var animation_speed: float = 1.0  # Multiplier for animation speed (1.0 = normal, 2.0 = 2x speed)
const FAST_FORWARD_SPEED: float = 3.0  # Speed when fast-forwarding
const SKIP_SPEED: float = 10.0  # Speed when skipping (near instant)


func _ready() -> void:
	current_context = ShotContext.new()


# --- Public API ---

func set_hole_controller(controller: Node3D) -> void:
	hole_controller = controller
	if current_context:
		current_context.hole = controller


func set_aoe_system(system: Node) -> void:
	aoe_system = system


func set_modifier_manager(manager: Node) -> void:
	modifier_manager = manager


func start_shot(ball: Node3D, start_tile: Vector2i) -> void:
	"""Begin a new shot - Phase 1: prepare_shot"""
	if is_shot_in_progress:
		push_warning("ShotManager: Shot already in progress")
		return
	
	is_shot_in_progress = true
	
	# Reset and initialize context
	current_context.reset()
	current_context.hole = hole_controller
	current_context.ball = ball
	current_context.start_tile = start_tile
	current_context.shot_index += 1
	
	# Calculate base stats from ball/hole state
	_calculate_base_stats()
	
	shot_started.emit(current_context)
	
	# Phase 2: Apply modifiers before aiming
	_apply_modifiers_before_aim()


func set_aim_target(aim_tile: Vector2i) -> void:
	"""Player has aimed at a tile - Phase 3-4: player_aims + compute_aoe"""
	if not is_shot_in_progress:
		push_warning("ShotManager: No shot in progress")
		return
	
	current_context.aim_tile = aim_tile
	player_aiming.emit(current_context)
	
	# Phase 4: Compute AOE
	_compute_aoe()


func confirm_shot() -> void:
	"""Player confirms the shot - Phases 5-9: resolve through cleanup"""
	if not is_shot_in_progress:
		push_warning("ShotManager: No shot in progress")
		return
	
	if current_context.aim_tile.x < 0:
		push_warning("ShotManager: No aim target set")
		return
	
	# Phase 5: Apply modifiers on AOE
	_apply_modifiers_on_aoe()
	
	# Phase 6: Resolve landing tile
	_resolve_landing_tile()
	
	# Phase 7: Simulate ball path
	_simulate_ball_path()
	
	# Phase 8: Compute scoring
	_compute_scoring()
	
	# Phase 9: Apply modifiers on scoring
	_apply_modifiers_on_scoring()
	
	# Phase 10: Cleanup
	_cleanup_shot()


func cancel_shot() -> void:
	"""Cancel current shot without completing it"""
	if is_shot_in_progress:
		current_context.reset()
		is_shot_in_progress = false
		is_animating = false
		animation_speed = 1.0


func start_animation() -> void:
	"""Mark that ball animation has started"""
	is_animating = true
	animation_speed = 1.0


func end_animation() -> void:
	"""Mark that ball animation has finished"""
	is_animating = false
	animation_speed = 1.0


func fast_forward_animation() -> void:
	"""Speed up current animation to 3x"""
	if is_animating:
		animation_speed = FAST_FORWARD_SPEED


func skip_animation() -> void:
	"""Skip to end of animation (near instant)"""
	if is_animating:
		animation_speed = SKIP_SPEED


func get_animation_speed() -> float:
	"""Get current animation speed multiplier"""
	return animation_speed if is_animating else 1.0


func can_aim() -> bool:
	"""Check if player can aim (allowed during animation for pre-aiming)"""
	return is_shot_in_progress or is_animating


func can_confirm_shot() -> bool:
	"""Check if player can confirm a shot (not during animation)"""
	return is_shot_in_progress and not is_animating


func get_current_context() -> ShotContext:
	return current_context


# --- Private Phase Methods ---

func _calculate_base_stats() -> void:
	"""Calculate initial stats from ball position and hole state"""
	# Base AOE radius starts at 0 (perfect accuracy)
	# Will be increased by club accuracy and modifiers
	current_context.aoe_radius = 0
	current_context.aoe_shape = "circle"
	
	# Base scoring values
	current_context.base_chips = 10
	current_context.chips = current_context.base_chips


func _apply_modifiers_before_aim() -> void:
	"""Phase 2: Let modifiers adjust context before player aims"""
	# Apply club accuracy to base AOE radius
	if hole_controller and hole_controller.has_method("get_current_shot_stats"):
		var stats = hole_controller.get_current_shot_stats()
		if stats.has("final") and stats.final.has("accuracy"):
			# Accuracy from club + all modifiers determines AOE radius
			current_context.aoe_radius = maxi(0, stats.final.accuracy)
	
	if modifier_manager and modifier_manager.has_method("apply_before_aim"):
		modifier_manager.apply_before_aim(current_context)
	
	modifiers_applied_before_aim.emit(current_context)


func _compute_aoe() -> void:
	"""Phase 4: Compute AOE tiles from aim position"""
	current_context.aoe_tiles.clear()
	
	if aoe_system and aoe_system.has_method("compute_aoe"):
		current_context.aoe_tiles = aoe_system.compute_aoe(
			current_context.aim_tile,
			current_context.aoe_radius,
			current_context.aoe_shape,
			hole_controller
		)
	else:
		# Fallback: use hole_controller's existing AOE methods
		if hole_controller and hole_controller.has_method("get_adjacent_cells"):
			# Add center tile
			current_context.aoe_tiles.append(current_context.aim_tile)
			# Add ring 1
			var adjacent = hole_controller.get_adjacent_cells(
				current_context.aim_tile.x, 
				current_context.aim_tile.y
			)
			current_context.aoe_tiles.append_array(adjacent)
			# Add ring 2 if radius >= 2
			if current_context.aoe_radius >= 2 and hole_controller.has_method("get_outer_ring_cells"):
				var outer = hole_controller.get_outer_ring_cells(
					current_context.aim_tile.x,
					current_context.aim_tile.y
				)
				current_context.aoe_tiles.append_array(outer)
	
	aoe_computed.emit(current_context)


func _apply_modifiers_on_aoe() -> void:
	"""Phase 5: Let modifiers adjust AOE shape/tiles"""
	if modifier_manager and modifier_manager.has_method("apply_on_aoe"):
		modifier_manager.apply_on_aoe(current_context)
	
	modifiers_applied_on_aoe.emit(current_context)


func _resolve_landing_tile() -> void:
	"""Phase 6: Determine landing tile from aim tile with accuracy-based spread"""
	
	# Calculate the target with curve applied (from cards + wind)
	var target_tile = _calculate_curved_target()
	
	# Apply accuracy spread - determines which tile in AOE the ball lands on
	# Higher accuracy_mod = more AOE rings = more random landing
	current_context.landing_tile = _calculate_accuracy_landing(target_tile)
	
	landing_resolved.emit(current_context)


func _calculate_curved_target() -> Vector2i:
	"""Calculate target tile with curve applied from cards and wind.
	Ball goes to aim_tile, but curve offsets it perpendicular to shot direction."""
	var start = current_context.start_tile
	var aim = current_context.aim_tile
	
	# Total curve: card curve + wind curve
	var total_curve = current_context.curve_strength + float(current_context.wind_curve)
	
	# If no curve, just return aim tile
	if abs(total_curve) < 0.1:
		return aim
	
	# Calculate shot direction
	var dir_x = aim.x - start.x
	var dir_y = aim.y - start.y
	var length = sqrt(dir_x * dir_x + dir_y * dir_y)
	
	if length < 0.1:
		return aim
	
	# Perpendicular vector (rotated 90 degrees)
	var perp_x = -dir_y / length
	var perp_y = dir_x / length
	
	# Apply curve (positive = right, negative = left)
	var curve_tiles = int(round(total_curve))
	var target_x = aim.x + int(round(perp_x * curve_tiles))
	var target_y = aim.y + int(round(perp_y * curve_tiles))
	
	# Mark that ball curved
	if abs(curve_tiles) > 0:
		current_context.did_curve = true
	
	# Clamp to valid grid bounds if hole_controller available
	if hole_controller and hole_controller.has_method("get_grid_width"):
		target_x = clampi(target_x, 0, hole_controller.get_grid_width() - 1)
		target_y = clampi(target_y, 0, hole_controller.get_grid_height() - 1)
	
	return Vector2i(target_x, target_y)


func _calculate_accuracy_landing(target_tile: Vector2i) -> Vector2i:
	"""Calculate final landing based on accuracy_mod.
	accuracy_mod is an int representing AOE rings (0 = perfect, higher = worse).
	Ball lands randomly within the AOE rings around the target tile."""
	var accuracy_rings = current_context.accuracy_mod
	
	# Perfect accuracy (0 rings) = land exactly on target
	if accuracy_rings <= 0:
		return target_tile
	
	# Build AOE tiles around the target tile
	var possible_tiles: Array[Vector2i] = [target_tile]
	var ring_start_indices: Array[int] = [0]  # Track where each ring starts
	
	if hole_controller and hole_controller.has_method("get_adjacent_cells"):
		# Add ring 1 neighbors if accuracy_mod >= 1
		if accuracy_rings >= 1:
			ring_start_indices.append(possible_tiles.size())
			var ring1 = hole_controller.get_adjacent_cells(target_tile.x, target_tile.y)
			possible_tiles.append_array(ring1)
		
		# Add ring 2 if accuracy_mod >= 2
		if accuracy_rings >= 2 and hole_controller.has_method("get_outer_ring_cells"):
			ring_start_indices.append(possible_tiles.size())
			var ring2 = hole_controller.get_outer_ring_cells(target_tile.x, target_tile.y)
			possible_tiles.append_array(ring2)
	
	# Weight tiles - center is most likely, outer rings less likely
	var weights: Dictionary = {}
	
	# Center tile gets weight based on how many rings there are
	# More rings = less likely to hit center
	var center_weight = 10.0 / float(accuracy_rings + 1)
	weights[target_tile] = center_weight
	
	# Ring 1 tiles get moderate weight
	if ring_start_indices.size() > 1:
		var ring1_weight = 3.0 / float(accuracy_rings)
		var ring1_start = ring_start_indices[1]
		var ring1_end = ring_start_indices[2] if ring_start_indices.size() > 2 else possible_tiles.size()
		for i in range(ring1_start, ring1_end):
			weights[possible_tiles[i]] = ring1_weight
	
	# Ring 2 tiles get lower weight
	if ring_start_indices.size() > 2:
		var ring2_weight = 1.0
		for i in range(ring_start_indices[2], possible_tiles.size()):
			weights[possible_tiles[i]] = ring2_weight
	
	# Weighted random selection
	var total_weight = 0.0
	for tile in possible_tiles:
		total_weight += weights.get(tile, 0.1)
	
	var roll = randf() * total_weight
	var cumulative = 0.0
	
	for tile in possible_tiles:
		cumulative += weights.get(tile, 0.1)
		if roll <= cumulative:
			return tile
	
	# Fallback
	return target_tile


func _weighted_tile_selection() -> Vector2i:
	"""Select a tile based on weights in aoe_weights"""
	var total_weight = 0.0
	for tile in current_context.aoe_tiles:
		total_weight += current_context.aoe_weights.get(tile, 1.0)
	
	var roll = randf() * total_weight
	var cumulative = 0.0
	
	for tile in current_context.aoe_tiles:
		cumulative += current_context.aoe_weights.get(tile, 1.0)
		if roll <= cumulative:
			return tile
	
	# Fallback to last tile
	return current_context.aoe_tiles[-1]


func _simulate_ball_path() -> void:
	"""Phase 7: Compute the path the ball takes from start to landing"""
	current_context.path_tiles.clear()
	
	# Simple straight-line path for now
	# TODO: Implement proper line-drawing algorithm with bounces
	current_context.path_tiles.append(current_context.start_tile)
	current_context.path_tiles.append(current_context.landing_tile)
	
	ball_path_simulated.emit(current_context)


func _compute_scoring() -> void:
	"""Phase 8: Calculate chips and mult based on shot"""
	# Base chips from distance
	var distance = current_context.get_shot_distance()
	current_context.base_chips = int(distance * 5)  # 5 chips per cell distance
	current_context.chips = current_context.base_chips
	
	# Check terrain effects on path
	if hole_controller:
		for tile in current_context.path_tiles:
			var surface = hole_controller.get_cell(tile.x, tile.y)
			_apply_terrain_scoring(surface)
	
	current_context.calculate_final_score()
	scoring_computed.emit(current_context)


func _apply_terrain_scoring(surface_type: int) -> void:
	"""Apply scoring effects based on terrain type"""
	# Surface type enum values from hex_grid.gd:
	# TEE=0, FAIRWAY=1, ROUGH=2, DEEP_ROUGH=3, GREEN=4, SAND=5, WATER=6, TREE=7, FLAG=8
	match surface_type:
		1:  # FAIRWAY
			current_context.mult += 0.1
		2:  # ROUGH
			current_context.chips -= 2
		3:  # DEEP_ROUGH
			current_context.chips -= 5
		4:  # GREEN
			current_context.mult += 0.5
		5:  # SAND
			current_context.chips -= 10
			current_context.add_metadata("hit_sand", true)
		6:  # WATER
			current_context.chips = int(current_context.chips * 0.5)
			current_context.add_metadata("hit_water", true)
		7:  # TREE
			current_context.chips -= 8
			current_context.add_metadata("hit_tree", true)
		8:  # FLAG (hole)
			current_context.mult *= 2.0
			current_context.add_metadata("reached_flag", true)


func _apply_modifiers_on_scoring() -> void:
	"""Phase 9: Let modifiers adjust final scoring"""
	if modifier_manager and modifier_manager.has_method("apply_on_scoring"):
		modifier_manager.apply_on_scoring(current_context)
	
	# Recalculate final score after modifiers
	current_context.calculate_final_score()
	modifiers_applied_on_scoring.emit(current_context)


func _cleanup_shot() -> void:
	"""Phase 10: Finalize shot and update state"""
	is_shot_in_progress = false
	shot_completed.emit(current_context)
