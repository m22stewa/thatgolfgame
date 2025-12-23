extends Node
class_name AOESystem

## AOESystem - Computes Area of Effect tiles from a center position.
## Supports different shapes: circle, cone, strip, line_vertical, line_horizontal.
##
## AOE Patterns (driven by cards):
## - "circle"/"ring": Filled circle of tiles within radius (traditional AOE)
## - "line_vertical": Line along shot direction (+N short, center, +N long)
## - "line_horizontal": Line perpendicular to shot (+N left, center, +N right - draw/fade)
## - "single": Just the center tile (default when no AOE card)


# --- Public API ---

func compute_aoe(center: Vector2i, radius: int, shape: String, hole_controller: Node3D, shot_direction: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	"""Compute all tiles in the AOE based on shape and radius.
	   shot_direction is needed for line_vertical/line_horizontal patterns."""
	match shape:
		"circle":
			return compute_circle_aoe(center, radius, hole_controller)
		"cone":
			return compute_cone_aoe(center, radius, hole_controller)
		"strip":
			return compute_strip_aoe(center, radius, hole_controller)
		"ring":
			return compute_ring_aoe(center, radius, hole_controller)
		"line_vertical":
			return compute_line_vertical_aoe(center, radius, hole_controller, shot_direction)
		"line_horizontal":
			return compute_line_horizontal_aoe(center, radius, hole_controller, shot_direction)
		"single":
			# Single tile only
			var tiles: Array[Vector2i] = []
			if _is_valid_tile(center, hole_controller):
				tiles.append(center)
			return tiles
		_:
			# Default to single tile (no spread)
			var tiles: Array[Vector2i] = []
			if _is_valid_tile(center, hole_controller):
				tiles.append(center)
			return tiles


func compute_circle_aoe(center: Vector2i, radius: int, hole_controller: Node3D) -> Array[Vector2i]:
	"""Standard circular AOE - all tiles within radius rings"""
	var tiles: Array[Vector2i] = []
	
	if not hole_controller:
		tiles.append(center)
		return tiles
	
	# Add center tile
	if _is_valid_tile(center, hole_controller):
		tiles.append(center)
	
	# Add tiles for each ring up to radius
	for ring in range(1, radius + 1):
		var ring_tiles = _get_ring_tiles(center, ring, hole_controller)
		tiles.append_array(ring_tiles)
	
	return tiles


func compute_cone_aoe(center: Vector2i, radius: int, hole_controller: Node3D, direction: int = 0) -> Array[Vector2i]:
	"""Cone-shaped AOE spreading in a direction (0-5 for hex directions)"""
	var tiles: Array[Vector2i] = []
	
	if not hole_controller:
		tiles.append(center)
		return tiles
	
	# Add center
	if _is_valid_tile(center, hole_controller):
		tiles.append(center)
	
	# Get direction offsets for the cone
	# Direction 0 = up, 1 = up-right, etc.
	var dir_offsets = _get_direction_offsets(center.x % 2 == 1)
	
	# Add tiles in cone pattern
	var current_tiles: Array[Vector2i] = [center]
	
	for ring in range(1, radius + 1):
		var next_tiles: Array[Vector2i] = []
		
		for tile in current_tiles:
			# Get the 3 neighbors in the cone direction
			var cone_neighbors = _get_cone_neighbors(tile, direction, hole_controller)
			for neighbor in cone_neighbors:
				if neighbor not in tiles and neighbor not in next_tiles:
					if _is_valid_tile(neighbor, hole_controller):
						next_tiles.append(neighbor)
		
		tiles.append_array(next_tiles)
		current_tiles = next_tiles
	
	return tiles


func compute_strip_aoe(center: Vector2i, radius: int, hole_controller: Node3D, direction: int = 0) -> Array[Vector2i]:
	"""Strip/line AOE extending in a direction"""
	var tiles: Array[Vector2i] = []
	
	if not hole_controller:
		tiles.append(center)
		return tiles
	
	# Add center
	if _is_valid_tile(center, hole_controller):
		tiles.append(center)
	
	var current = center
	var is_odd = current.x % 2 == 1
	
	for i in range(1, radius + 1):
		var next = _get_neighbor_in_direction(current, direction, is_odd)
		if _is_valid_tile(next, hole_controller):
			tiles.append(next)
			current = next
			is_odd = current.x % 2 == 1
		else:
			break
	
	return tiles


func compute_ring_aoe(center: Vector2i, radius: int, hole_controller: Node3D) -> Array[Vector2i]:
	"""Ring AOE - only tiles at exactly the specified radius (donut shape)"""
	if radius == 0:
		var tiles: Array[Vector2i] = []
		if _is_valid_tile(center, hole_controller):
			tiles.append(center)
		return tiles
	
	return _get_ring_tiles(center, radius, hole_controller)


# --- Utility Methods ---

func get_tiles_by_terrain(tiles: Array[Vector2i], terrain_type: int, hole_controller: Node3D) -> Array[Vector2i]:
	"""Filter tiles to only those matching a terrain type"""
	var result: Array[Vector2i] = []
	
	if not hole_controller or not hole_controller.has_method("get_cell"):
		return result
	
	for tile in tiles:
		if hole_controller.get_cell(tile.x, tile.y) == terrain_type:
			result.append(tile)
	
	return result


func get_tiles_excluding_terrain(tiles: Array[Vector2i], terrain_type: int, hole_controller: Node3D) -> Array[Vector2i]:
	"""Filter tiles to exclude a terrain type"""
	var result: Array[Vector2i] = []
	
	if not hole_controller or not hole_controller.has_method("get_cell"):
		return tiles
	
	for tile in tiles:
		if hole_controller.get_cell(tile.x, tile.y) != terrain_type:
			result.append(tile)
	
	return result


func calculate_weights_by_terrain(tiles: Array[Vector2i], hole_controller: Node3D) -> Dictionary:
	"""Calculate landing weights based on terrain (fairway preferred, hazards avoided)"""
	var weights = {}
	
	if not hole_controller or not hole_controller.has_method("get_cell"):
		return weights
	
	for tile in tiles:
		var terrain = hole_controller.get_cell(tile.x, tile.y)
		# Terrain weights (higher = more likely to land)
		match terrain:
			1:  # FAIRWAY
				weights[tile] = 2.0
			2:  # ROUGH
				weights[tile] = 1.0
			3:  # DEEP_ROUGH
				weights[tile] = 0.8
			4:  # GREEN
				weights[tile] = 2.5
			5:  # SAND
				weights[tile] = 0.5
			6:  # WATER
				weights[tile] = 0.2
			7:  # TREE
				weights[tile] = 0.3
			_:
				weights[tile] = 1.0
	
	return weights


# --- Private Helper Methods ---

func _is_valid_tile(tile: Vector2i, hole_controller: Node3D) -> bool:
	"""Check if a tile is within the grid bounds"""
	if not hole_controller:
		return false
	
	var grid_width = hole_controller.get("grid_width")
	var grid_height = hole_controller.get("grid_height")
	
	if grid_width == null or grid_height == null:
		return true  # Can't validate, assume valid
	
	return tile.x >= 0 and tile.x < grid_width and tile.y >= 0 and tile.y < grid_height


func _get_ring_tiles(center: Vector2i, ring: int, hole_controller: Node3D) -> Array[Vector2i]:
	"""Get all tiles at exactly 'ring' distance from center"""
	var tiles: Array[Vector2i] = []
	
	if ring == 1:
		# Use hole_controller's method if available
		if hole_controller and hole_controller.has_method("get_adjacent_cells"):
			var adjacent = hole_controller.get_adjacent_cells(center.x, center.y)
			for tile in adjacent:
				if _is_valid_tile(tile, hole_controller):
					tiles.append(tile)
		else:
			tiles = _calculate_adjacent_cells(center)
	elif ring == 2:
		# Use hole_controller's method if available
		if hole_controller and hole_controller.has_method("get_outer_ring_cells"):
			var outer = hole_controller.get_outer_ring_cells(center.x, center.y)
			for tile in outer:
				if _is_valid_tile(tile, hole_controller):
					tiles.append(tile)
		else:
			tiles = _calculate_outer_ring_cells(center)
	else:
		# For ring > 2, calculate manually
		tiles = _calculate_ring_at_distance(center, ring, hole_controller)
	
	return tiles


func _calculate_adjacent_cells(center: Vector2i) -> Array[Vector2i]:
	"""Calculate the 6 adjacent hex cells"""
	var cells: Array[Vector2i] = []
	var col = center.x
	var row = center.y
	var is_odd = col % 2 == 1
	
	# Hex neighbor offsets depend on column parity
	if is_odd:
		cells.append(Vector2i(col - 1, row))      # Left-up
		cells.append(Vector2i(col - 1, row + 1))  # Left-down
		cells.append(Vector2i(col + 1, row))      # Right-up
		cells.append(Vector2i(col + 1, row + 1))  # Right-down
		cells.append(Vector2i(col, row - 1))      # Up
		cells.append(Vector2i(col, row + 1))      # Down
	else:
		cells.append(Vector2i(col - 1, row - 1))  # Left-up
		cells.append(Vector2i(col - 1, row))      # Left-down
		cells.append(Vector2i(col + 1, row - 1))  # Right-up
		cells.append(Vector2i(col + 1, row))      # Right-down
		cells.append(Vector2i(col, row - 1))      # Up
		cells.append(Vector2i(col, row + 1))      # Down
	
	return cells


func _calculate_outer_ring_cells(center: Vector2i) -> Array[Vector2i]:
	"""Calculate tiles at distance 2 from center"""
	var cells: Array[Vector2i] = []
	var seen: Dictionary = {}
	
	# Get all neighbors of neighbors, excluding ring 0 and ring 1
	seen[center] = true
	var ring1 = _calculate_adjacent_cells(center)
	for cell in ring1:
		seen[cell] = true
	
	for ring1_cell in ring1:
		var neighbors = _calculate_adjacent_cells(ring1_cell)
		for neighbor in neighbors:
			if not seen.has(neighbor):
				seen[neighbor] = true
				cells.append(neighbor)
	
	return cells


func _calculate_ring_at_distance(center: Vector2i, distance: int, hole_controller: Node3D) -> Array[Vector2i]:
	"""Calculate tiles at exactly 'distance' from center using BFS"""
	var cells: Array[Vector2i] = []
	var visited: Dictionary = {}
	var current_ring: Array[Vector2i] = [center]
	visited[center] = true
	
	for d in range(distance):
		var next_ring: Array[Vector2i] = []
		for cell in current_ring:
			var neighbors = _calculate_adjacent_cells(cell)
			for neighbor in neighbors:
				if not visited.has(neighbor):
					visited[neighbor] = true
					next_ring.append(neighbor)
		current_ring = next_ring
	
	# Filter to valid tiles
	for cell in current_ring:
		if _is_valid_tile(cell, hole_controller):
			cells.append(cell)
	
	return cells


func _get_direction_offsets(is_odd: bool) -> Array:
	"""Get the 6 direction offsets for hex neighbors"""
	if is_odd:
		return [
			Vector2i(0, -1),   # 0: Up
			Vector2i(1, 0),    # 1: Up-Right
			Vector2i(1, 1),    # 2: Down-Right
			Vector2i(0, 1),    # 3: Down
			Vector2i(-1, 1),   # 4: Down-Left
			Vector2i(-1, 0)    # 5: Up-Left
		]
	else:
		return [
			Vector2i(0, -1),   # 0: Up
			Vector2i(1, -1),   # 1: Up-Right
			Vector2i(1, 0),    # 2: Down-Right
			Vector2i(0, 1),    # 3: Down
			Vector2i(-1, 0),   # 4: Down-Left
			Vector2i(-1, -1)   # 5: Up-Left
		]


func _get_neighbor_in_direction(tile: Vector2i, direction: int, is_odd: bool) -> Vector2i:
	"""Get the neighbor tile in a specific direction (0-5)"""
	var offsets = _get_direction_offsets(is_odd)
	var dir_idx = direction % 6
	return tile + offsets[dir_idx]


func _get_cone_neighbors(tile: Vector2i, direction: int, hole_controller: Node3D) -> Array[Vector2i]:
	"""Get the 3 neighbors that form a cone in the given direction"""
	var neighbors: Array[Vector2i] = []
	var is_odd = tile.x % 2 == 1
	
	# Get the main direction and the two adjacent directions
	var dirs = [(direction - 1 + 6) % 6, direction, (direction + 1) % 6]
	
	for dir in dirs:
		var neighbor = _get_neighbor_in_direction(tile, dir, is_odd)
		if _is_valid_tile(neighbor, hole_controller):
			neighbors.append(neighbor)
	
	return neighbors


# --- Line-based AOE patterns (card-driven) ---

func compute_line_vertical_aoe(center: Vector2i, distance: int, hole_controller: Node3D, shot_direction: Vector2i) -> Array[Vector2i]:
	"""Compute a vertical line AOE (grid-aligned).
	   This intentionally does NOT orient to shot direction; it always uses Up/Down.
	   +distance tiles up, center, +distance tiles down."""
	var tiles: Array[Vector2i] = []
	
	# Always include center
	if _is_valid_tile(center, hole_controller):
		tiles.append(center)
	
	if distance <= 0:
		return tiles
	
	# Fixed grid directions: 0=Up, 3=Down
	var forward_dir := 0
	var backward_dir := 3
	
	# Add tiles forward (toward hole)
	var current = center
	for i in range(distance):
		var is_odd = current.x % 2 == 1
		current = _get_neighbor_in_direction(current, forward_dir, is_odd)
		if _is_valid_tile(current, hole_controller):
			tiles.append(current)
		else:
			break
	
	# Add tiles backward (toward tee)
	current = center
	for i in range(distance):
		var is_odd = current.x % 2 == 1
		current = _get_neighbor_in_direction(current, backward_dir, is_odd)
		if _is_valid_tile(current, hole_controller):
			tiles.append(current)
		else:
			break
	
	return tiles


func compute_line_horizontal_aoe(center: Vector2i, distance: int, hole_controller: Node3D, shot_direction: Vector2i) -> Array[Vector2i]:
	"""Compute a horizontal line AOE (grid-aligned).
	   This intentionally does NOT orient to shot direction; it always uses the same
	   left/right directions on the hex grid.
	   +distance tiles left, center, +distance tiles right."""
	var tiles: Array[Vector2i] = []
	
	# Always include center
	if _is_valid_tile(center, hole_controller):
		tiles.append(center)
	
	if distance <= 0:
		return tiles
	
	# Fixed grid directions for "horizontal": 5=Up-Left, 1=Up-Right
	# (This yields a consistent left/right visual line in this project's offset grid.)
	var left_dir := 5
	var right_dir := 1
	
	# Add tiles to the left (draw side)
	var current = center
	for i in range(distance):
		var is_odd = current.x % 2 == 1
		current = _get_neighbor_in_direction(current, left_dir, is_odd)
		if _is_valid_tile(current, hole_controller):
			tiles.append(current)
		else:
			break
	
	# Add tiles to the right (fade side)
	current = center
	for i in range(distance):
		var is_odd = current.x % 2 == 1
		current = _get_neighbor_in_direction(current, right_dir, is_odd)
		if _is_valid_tile(current, hole_controller):
			tiles.append(current)
		else:
			break
	
	return tiles


func _vector_to_hex_direction(direction: Vector2i) -> int:
	"""Convert a grid direction vector to a hex direction index (0-5).
	   0=Up (toward hole), 3=Down (toward tee), etc."""
	# Normalize direction to get primary axis
	var dx = sign(direction.x)
	var dy = sign(direction.y)
	
	# Map to hex directions based on dominant axis
	# In hex grid: negative Y = toward top of grid (usually toward hole)
	if dy < 0:
		if dx > 0:
			return 1  # Up-Right
		elif dx < 0:
			return 5  # Up-Left
		else:
			return 0  # Up
	elif dy > 0:
		if dx > 0:
			return 2  # Down-Right
		elif dx < 0:
			return 4  # Down-Left
		else:
			return 3  # Down
	else:
		# dy == 0, horizontal movement
		if dx > 0:
			return 1  # Default to Up-Right
		elif dx < 0:
			return 5  # Default to Up-Left
		else:
			return 0  # No direction, default to Up
