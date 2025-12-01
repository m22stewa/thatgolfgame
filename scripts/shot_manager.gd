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


func get_current_context() -> ShotContext:
	return current_context


# --- Private Phase Methods ---

func _calculate_base_stats() -> void:
	"""Calculate initial stats from ball position and hole state"""
	# Base AOE radius (can be modified by clubs/cards later)
	current_context.aoe_radius = 1
	current_context.aoe_shape = "circle"
	
	# Base scoring values
	current_context.base_chips = 10
	current_context.chips = current_context.base_chips


func _apply_modifiers_before_aim() -> void:
	"""Phase 2: Let modifiers adjust context before player aims"""
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
	"""Phase 6: Choose landing tile from AOE (uniform or weighted)"""
	if current_context.aoe_tiles.is_empty():
		current_context.landing_tile = current_context.aim_tile
	elif current_context.aoe_weights.is_empty():
		# Uniform random selection
		var idx = randi() % current_context.aoe_tiles.size()
		current_context.landing_tile = current_context.aoe_tiles[idx]
	else:
		# Weighted selection
		current_context.landing_tile = _weighted_tile_selection()
	
	landing_resolved.emit(current_context)


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
