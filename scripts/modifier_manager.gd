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
		var before := _capture_context_state(context)
		if modifier.has_method("apply_before_aim"):
			print("[ModifierManager]     Applying before_aim for: %s" % mod_name)
			modifier.apply_before_aim(context)
		var after := _capture_context_state(context)
		_try_record_debug_delta("before_aim", mod_name, before, after)


func apply_on_aoe(context: ShotContext) -> void:
	"""Called after AOE computed - modifiers can change AOE shape/tiles"""
	print("[ModifierManager] apply_on_aoe - Active modifiers: %d" % modifiers.size())
	for modifier in modifiers:
		var mod_name = modifier.get("modifier_name") if modifier.get("modifier_name") else str(modifier)
		var before := _capture_context_state(context)
		if modifier.has_method("apply_on_aoe"):
			print("[ModifierManager]   Applying on_aoe for: %s" % mod_name)
			modifier.apply_on_aoe(context)
		var after := _capture_context_state(context)
		_try_record_debug_delta("on_aoe", mod_name, before, after)


func apply_on_landing(context: ShotContext) -> void:
	"""Called after landing tile resolved - modifiers can react to landing"""
	for modifier in modifiers:
		var mod_name = modifier.get("modifier_name") if modifier.get("modifier_name") else str(modifier)
		var before := _capture_context_state(context)
		if modifier.has_method("apply_on_landing"):
			modifier.apply_on_landing(context)
		var after := _capture_context_state(context)
		_try_record_debug_delta("on_landing", mod_name, before, after)


func apply_on_scoring(context: ShotContext) -> void:
	"""Called during scoring - modifiers can adjust chips/mult"""
	print("[ModifierManager] apply_on_scoring - Active modifiers: %d" % modifiers.size())
	for modifier in modifiers:
		var mod_name = modifier.get("modifier_name") if modifier.get("modifier_name") else str(modifier)
		var before := _capture_context_state(context)
		if modifier.has_method("apply_on_scoring"):
			print("[ModifierManager]   Applying on_scoring for: %s" % mod_name)
			modifier.apply_on_scoring(context)
		var after := _capture_context_state(context)
		_try_record_debug_delta("on_scoring", mod_name, before, after)


func apply_after_shot(context: ShotContext) -> void:
	"""Called after shot complete - modifiers can update state/tiles"""
	for modifier in modifiers:
		var mod_name = modifier.get("modifier_name") if modifier.get("modifier_name") else str(modifier)
		var before := _capture_context_state(context)
		if modifier.has_method("apply_after_shot"):
			modifier.apply_after_shot(context)
		var after := _capture_context_state(context)
		_try_record_debug_delta("after_shot", mod_name, before, after)


func _capture_context_state(context: ShotContext) -> Dictionary:
	if context == null:
		return {}
	return {
		"distance_mod": context.distance_mod,
		"accuracy_mod": context.accuracy_mod,
		"roll_mod": context.roll_mod,
		"wind_curve": context.wind_curve,
		"aoe_radius": context.aoe_radius,
		"aoe_shape": context.aoe_shape,
		"curve_strength": context.curve_strength,
		"curve_profile": context.curve_profile,
		"max_bounces": context.max_bounces,
		"chips": context.chips,
		"base_chips": context.base_chips,
		"mult": context.mult,
		"final_score": context.final_score,
		"metadata": context.metadata.duplicate(true),
	}


func _try_record_debug_delta(phase: String, modifier_name: String, before: Dictionary, after: Dictionary) -> void:
	var dbg := get_tree().get_first_node_in_group("debug_overlay") if get_tree() else null
	if dbg == null:
		return
	if not dbg.has_method("record_modifier_delta"):
		return
	var delta := _diff_context_state(before, after)
	if delta.is_empty():
		return
	dbg.record_modifier_delta(phase, modifier_name, delta)


func _diff_context_state(before: Dictionary, after: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	for k in after.keys():
		if not before.has(k):
			delta[k] = {"from": null, "to": after[k]}
			continue
		if k == "metadata":
			var md_delta := _diff_metadata(before[k], after[k])
			if not md_delta.is_empty():
				delta[k] = md_delta
			continue
		if before[k] != after[k]:
			delta[k] = {"from": before[k], "to": after[k]}
	return delta


func _diff_metadata(before_md: Dictionary, after_md: Dictionary) -> Dictionary:
	var md_delta: Dictionary = {}
	for k in after_md.keys():
		if not before_md.has(k):
			md_delta[str(k)] = {"from": null, "to": after_md[k]}
		elif before_md[k] != after_md[k]:
			md_delta[str(k)] = {"from": before_md[k], "to": after_md[k]}
	for k in before_md.keys():
		if not after_md.has(k):
			md_delta[str(k)] = {"from": before_md[k], "to": null}
	return md_delta


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
