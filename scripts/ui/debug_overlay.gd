extends CanvasLayer
class_name DebugOverlay

@export var refresh_hz: float = 10.0
@export var max_modifier_events: int = 100

@onready var root_panel: PanelContainer = $Panel
@onready var text_label: RichTextLabel = $Panel/Margin/VBox/Scroll/Text
@onready var title_label: Label = $Panel/Margin/VBox/Header/Title

var _accum: float = 0.0
var _hex_grid: Node = null
var _shot_manager: ShotManager = null
var _wind_system: WindSystem = null
var _modifier_manager: ModifierManager = null
var _card_system: CardSystemManager = null

var _modifier_events: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("debug_overlay")
	set_process_unhandled_input(true)
	visible = false
	_process_references()
	_render()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	# Toggle on Shift+6 ("^") or literal '^' unicode if present.
	var is_caret := (key.shift_pressed and key.keycode == KEY_6)
	if not is_caret and key.unicode != 0:
		is_caret = (char(key.unicode) == "^")

	if is_caret:
		visible = not visible
		if visible:
			_process_references(true)
			_render()
		# CanvasLayer isn't a Control, so we can't call accept_event().
		# Mark this input as handled to avoid other listeners also toggling.
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	var interval := 1.0 / maxf(1.0, refresh_hz)
	if _accum >= interval:
		_accum = 0.0
		_process_references()
		_render()


func record_modifier_delta(phase: String, modifier_name: String, delta: Dictionary) -> void:
	# Called by ModifierManager (best-effort). Store even when overlay is hidden.
	if delta.is_empty():
		return
	_modifier_events.append({
		"t": Time.get_ticks_msec(),
		"phase": phase,
		"name": modifier_name,
		"delta": delta,
	})
	if _modifier_events.size() > max_modifier_events:
		_modifier_events = _modifier_events.slice(_modifier_events.size() - max_modifier_events, _modifier_events.size())


func _process_references(force: bool = false) -> void:
	if force or _hex_grid == null or not is_instance_valid(_hex_grid):
		_hex_grid = _find_node_by_name("HexGrid")

	if _hex_grid == null:
		_shot_manager = null
		_wind_system = null
		_modifier_manager = null
		_card_system = null
		return

	if force or _shot_manager == null or not is_instance_valid(_shot_manager):
		_shot_manager = _hex_grid.get_node_or_null("ShotManager") as ShotManager
	if force or _wind_system == null or not is_instance_valid(_wind_system):
		_wind_system = _hex_grid.get_node_or_null("WindSystem") as WindSystem
	if force or _modifier_manager == null or not is_instance_valid(_modifier_manager):
		_modifier_manager = _hex_grid.get_node_or_null("ModifierManager") as ModifierManager
	# CardSystemManager is added later during shot system init.
	if force or _card_system == null or not is_instance_valid(_card_system):
		_card_system = _hex_grid.get_node_or_null("CardSystemManager") as CardSystemManager


func _find_node_by_name(node_name: String) -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child(node_name, true, false)


func _render() -> void:
	if title_label:
		title_label.text = "Debug Overlay (toggle: Shift+6 '^')"
	if text_label == null:
		return

	var lines: Array[String] = []
	lines.append("[b]Scene[/b]")
	lines.append("- fps: %d" % int(Engine.get_frames_per_second()))

	if _hex_grid == null:
		lines.append("\n[color=red]HexGrid not found.[/color]")
		text_label.bbcode_enabled = true
		text_label.text = "\n".join(lines)
		return

	var ctx: ShotContext = null
	if _shot_manager and _shot_manager.current_context:
		ctx = _shot_manager.current_context

	lines.append("\n[b]Shot Manager[/b]")
	if _shot_manager:
		lines.append("- in_progress: %s" % str(_shot_manager.is_shot_in_progress))
		lines.append("- animating: %s" % str(_shot_manager.is_animating))
		lines.append("- animation_speed: %.2f" % float(_shot_manager.get_animation_speed()))
	else:
		lines.append("- (missing ShotManager)")

	if ctx:
		lines.append("\n[b]Shot Context[/b]")
		lines.append("- start_tile: %s" % str(ctx.start_tile))
		lines.append("- aim_tile: %s" % str(ctx.aim_tile))
		lines.append("- landing_tile: %s" % str(ctx.landing_tile))
		lines.append("- dist_mod: %+d, acc_mod: %+d, roll_mod: %+d" % [ctx.distance_mod, ctx.accuracy_mod, ctx.roll_mod])
		var prof := ctx.curve_profile if ctx.curve_profile != "" else ("draw" if ctx.curve_strength < 0.0 else ("fade" if ctx.curve_strength > 0.0 else ""))
		lines.append("- curve_strength: %.2f (%s), wind_curve: %+d" % [ctx.curve_strength, prof, ctx.wind_curve])
		lines.append("- aoe_radius: %d, aoe_shape: %s, aoe_tiles: %d" % [ctx.aoe_radius, ctx.aoe_shape, ctx.aoe_tiles.size()])
		lines.append("- chips: %d (base %d), mult: %.2f, final: %d" % [ctx.chips, ctx.base_chips, ctx.mult, ctx.final_score])

		var dist_tiles := ctx.get_shot_distance()
		lines.append("- distance: %.2f tiles (%.0f yards)" % [dist_tiles, ctx.get_shot_distance_yards()])

		if not ctx.metadata.is_empty():
			lines.append("- metadata:")
			for k in ctx.metadata.keys():
				lines.append("    %s: %s" % [str(k), str(ctx.metadata[k])])

	lines.append("\n[b]Wind[/b]")
	if _wind_system:
		lines.append("- enabled: %s" % str(_wind_system.enabled))
		lines.append("- direction: %s (index %d)" % [_wind_system.get_direction_name(), int(_wind_system.direction_index)])
		lines.append("- speed_kmh: %.1f, strength: %d (%s)" % [float(_wind_system.speed_kmh), int(_wind_system.strength), _wind_system.get_strength_name()])
		lines.append("- dir_vec: %s" % str(_wind_system.get_direction_vector()))
	else:
		lines.append("- (missing WindSystem)")

	lines.append("\n[b]Club / Stats[/b]")
	lines.append_array(_render_club_stats(ctx))

	lines.append("\n[b]Active Modifiers[/b]")
	lines.append_array(_render_active_modifiers())

	lines.append("\n[b]Modifier Deltas (most recent first)[/b]")
	lines.append_array(_render_modifier_events())

	text_label.bbcode_enabled = true
	text_label.text = "\n".join(lines)


func _render_club_stats(ctx: ShotContext) -> Array[String]:
	var out: Array[String] = []
	if _hex_grid == null:
		out.append("- (missing HexGrid)")
		return out

	# Compute the same stats structure as hex_grid.get_current_shot_stats(), but without its debug prints.
	var club_type: int = int(_hex_grid.get("current_club"))
	if ctx and _hex_grid.get("golf_ball"):
		var ball: Node3D = _hex_grid.get("golf_ball")
		var ball_tile: Vector2i = _hex_grid.call("world_to_grid", ball.position)
		var aim_tile: Vector2i = ctx.aim_tile
		if aim_tile.x >= 0:
			var tile_dist: int = int(_hex_grid.call("get_tile_distance", ball_tile, aim_tile))
			var club_info: Dictionary = _hex_grid.call("get_club_for_tile_distance", tile_dist)
			if club_info and club_info.has("type"):
				club_type = int(club_info.type)

	var club_stats: Dictionary = _hex_grid.CLUB_STATS.get(club_type, _hex_grid.CLUB_STATS[_hex_grid.ClubType.IRON_7])
	out.append("- club: %s" % str(club_stats.get("name", "Unknown")))

	var base_distance := int(club_stats.get("distance", 0))
	var base_accuracy := int(club_stats.get("accuracy", 0))
	var base_roll := int(club_stats.get("roll", 0))
	var loft := int(club_stats.get("loft", 0))
	var arc_height := float(club_stats.get("arc_height", 0.0))
	var swing_difficulty := int(club_stats.get("swing_difficulty", 0))
	var base_curve := float(club_stats.get("curve", 0))

	var dist_mod := ctx.distance_mod if ctx else 0
	var acc_mod := ctx.accuracy_mod if ctx else 0
	var roll_mod := ctx.roll_mod if ctx else 0
	var curve_mod := ctx.curve_strength if ctx else 0.0

	out.append("- base_distance: %d tiles (%d yds)" % [base_distance, base_distance * 10])
	out.append("- distance_mod: %+d => %d tiles" % [dist_mod, maxi(1, base_distance + dist_mod)])
	out.append("- accuracy: %d %+d => %d rings" % [base_accuracy, acc_mod, maxi(0, base_accuracy + acc_mod)])
	out.append("- roll: %d %+d => %d tiles" % [base_roll, roll_mod, maxi(0, base_roll + roll_mod)])
	out.append("- loft: %d, arc_height: %.1f, swing_difficulty: %d" % [loft, arc_height, swing_difficulty])
	out.append("- curve: %.2f %+0.2f => %.2f" % [base_curve, curve_mod, base_curve + curve_mod])

	# Spin
	var spin := int(_hex_grid.get("current_spin"))
	var spin_name := "None"
	match spin:
		_hex_grid.SpinType.NONE: spin_name = "None"
		_hex_grid.SpinType.TOPSPIN: spin_name = "Topspin"
		_hex_grid.SpinType.BACKSPIN: spin_name = "Backspin"
	out.append("- spin: %s" % spin_name)
	return out


func _render_active_modifiers() -> Array[String]:
	var out: Array[String] = []
	if _modifier_manager == null:
		out.append("- (missing ModifierManager)")
		return out

	var mods: Array = _modifier_manager.get_modifiers()
	if mods.is_empty():
		out.append("- (none)")
		return out

	for m in mods:
		var name := "(unknown)"
		if m != null and m is Object:
			var maybe: Variant = m.get("modifier_name")
			name = str(maybe) if maybe != null and str(maybe) != "" else str(m)
			# CardModifier: show card name if possible
			var card_obj: Variant = m.get("card")
			if m.has_method("get_modifier_type") and m.get_modifier_type() == "card" and card_obj:
				var card: CardInstance = m.get("card") as CardInstance
				if card:
					name = "%s (%s)" % [name, card.get_display_name()]
		out.append("- %s" % name)

	# CardSystemManager also tracks active card modifiers; show count for sanity
	if _card_system:
		out.append("- card_system.active_card_modifiers: %d" % int(_card_system.active_card_modifiers.size()))
	return out


func _render_modifier_events() -> Array[String]:
	var out: Array[String] = []
	if _modifier_events.is_empty():
		out.append("- (no recorded deltas yet)")
		return out

	var count := mini(15, _modifier_events.size())
	for i in range(count):
		var e: Dictionary = _modifier_events[_modifier_events.size() - 1 - i]
		var phase := str(e.get("phase", ""))
		var name := str(e.get("name", ""))
		var delta: Dictionary = e.get("delta", {})
		out.append("- [%s] %s" % [phase, name])
		for k in delta.keys():
			out.append("    %s: %s" % [str(k), str(delta[k])])
	return out
