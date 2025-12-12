extends Node
class_name ModifierManager

## ModifierManager - Holds active modifiers and calls their methods at each shot phase.
## Modifiers can be nodes (children) or objects in the modifiers array.

# Array of active modifier instances
var modifiers: Array = []


func _ready() -> void:
	# Auto-register any modifier children
	for child in get_children():
		if _is_modifier(child):
			modifiers.append(child)


# --- Public API ---

func add_modifier(modifier: Variant) -> void:
	"""Add a modifier to the active list"""
	if modifier not in modifiers:
		var mod_name = modifier.get("modifier_name") if modifier.get("modifier_name") else str(modifier)
		print("[ModifierManager] Adding modifier: %s" % mod_name)
		modifiers.append(modifier)
		
		# If it's a node, add as child for lifecycle management
		if modifier is Node and modifier.get_parent() == null:
			add_child(modifier)


func remove_modifier(modifier: Variant) -> void:
	"""Remove a modifier from the active list"""
	var idx = modifiers.find(modifier)
	if idx >= 0:
		var mod_name = modifier.get("modifier_name") if modifier.get("modifier_name") else str(modifier)
		print("[ModifierManager] Removing modifier: %s" % mod_name)
		modifiers.remove_at(idx)
		
		# If it's a child node, remove it
		if modifier is Node and modifier.get_parent() == self:
			remove_child(modifier)


func clear_modifiers() -> void:
	"""Remove all modifiers"""
	for modifier in modifiers.duplicate():
		remove_modifier(modifier)
	modifiers.clear()


func get_modifiers() -> Array:
	"""Get list of all active modifiers"""
	return modifiers.duplicate()


func get_modifiers_by_type(type_name: String) -> Array:
	"""Get modifiers that have a specific type tag"""
	var result = []
	for mod in modifiers:
		if mod.has_method("get_modifier_type"):
			if mod.get_modifier_type() == type_name:
				result.append(mod)
		elif mod.get("modifier_type") == type_name:
			result.append(mod)
	return result


# --- Phase Application Methods ---

func apply_before_aim(context: ShotContext) -> void:
	"""Called before player aims - modifiers can change base stats"""
	print("[ModifierManager] apply_before_aim - Active modifiers: %d" % modifiers.size())
	for modifier in modifiers:
		var mod_name = modifier.get("modifier_name") if modifier.get("modifier_name") else str(modifier)
		print("[ModifierManager]   - Modifier: %s" % mod_name)
		if modifier.has_method("apply_before_aim"):
			print("[ModifierManager]     Applying before_aim for: %s" % mod_name)
			modifier.apply_before_aim(context)


func apply_on_aoe(context: ShotContext) -> void:
	"""Called after AOE computed - modifiers can change AOE shape/tiles"""
	print("[ModifierManager] apply_on_aoe - Active modifiers: %d" % modifiers.size())
	for modifier in modifiers:
		var mod_name = modifier.get("modifier_name") if modifier.get("modifier_name") else str(modifier)
		if modifier.has_method("apply_on_aoe"):
			print("[ModifierManager]   Applying on_aoe for: %s" % mod_name)
			modifier.apply_on_aoe(context)


func apply_on_landing(context: ShotContext) -> void:
	"""Called after landing tile resolved - modifiers can react to landing"""
	for modifier in modifiers:
		if modifier.has_method("apply_on_landing"):
			modifier.apply_on_landing(context)


func apply_on_scoring(context: ShotContext) -> void:
	"""Called during scoring - modifiers can adjust chips/mult"""
	print("[ModifierManager] apply_on_scoring - Active modifiers: %d" % modifiers.size())
	for modifier in modifiers:
		var mod_name = modifier.get("modifier_name") if modifier.get("modifier_name") else str(modifier)
		if modifier.has_method("apply_on_scoring"):
			print("[ModifierManager]   Applying on_scoring for: %s" % mod_name)
			modifier.apply_on_scoring(context)


func apply_after_shot(context: ShotContext) -> void:
	"""Called after shot complete - modifiers can update state/tiles"""
	for modifier in modifiers:
		if modifier.has_method("apply_after_shot"):
			modifier.apply_after_shot(context)


# --- Helper Methods ---

func _is_modifier(obj: Variant) -> bool:
	"""Check if an object implements any modifier interface methods"""
	if obj == null:
		return false
	
	var modifier_methods = [
		"apply_before_aim",
		"apply_on_aoe", 
		"apply_on_landing",
		"apply_on_scoring",
		"apply_after_shot"
	]
	
	for method in modifier_methods:
		if obj.has_method(method):
			return true
	
	return false
