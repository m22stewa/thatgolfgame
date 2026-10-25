extends PanelContainer
class_name PuttPanel

## PuttPanel - The tray's putting card, shown in place of the hand while the
## ball is on the green (design/claude/design_handoff_putting). A pencilled
## scorecard box: the green and its par, PUTT x / 4, putting chips and the
## deck's draw / discard, then LAG PUTT and CADDIE PEEK (FLIP & PUTT is the
## SHOOT button), the cards flipped on the last putt with the sum pencilled in,
## the peeked card, and the green's result stamp. hex_grid fills it through
## MainUI.set_putting().

signal lag_pressed
signal peek_pressed

var _title: Label
var _counts: Label
var _flips: Label
var _peek: Label
var _stamp: Label
var _lag: Button
var _peek_button: Button


func _init() -> void:
	name = "PuttPanel"
	add_theme_stylebox_override("panel", ScorecardStyle.paper_box(ScorecardStyle.RULE, 2, ScorecardStyle.PAPER, 3))
	custom_minimum_size = Vector2(420, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_title = ScorecardStyle.label("", 26, ScorecardStyle.INK, ScorecardStyle.header_font())
	head.add_child(_title)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	_stamp = ScorecardStyle.label("", 26, ScorecardStyle.RED, ScorecardStyle.header_font())
	head.add_child(_stamp)

	_counts = ScorecardStyle.label("", 15, ScorecardStyle.INK_SOFT, ScorecardStyle.header_font(false))
	col.add_child(_counts)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)
	_lag = _button(buttons, func(): lag_pressed.emit())
	_peek_button = _button(buttons, func(): peek_pressed.emit())

	_flips = ScorecardStyle.label("", 26, ScorecardStyle.PENCIL, ScorecardStyle.pencil_font())
	col.add_child(_flips)
	_peek = ScorecardStyle.label("", 18, ScorecardStyle.NAVY, ScorecardStyle.pencil_font())
	col.add_child(_peek)


func _button(parent: Control, on_press: Callable) -> Button:
	var b := Button.new()
	ScorecardStyle.flat_button(b)
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(150, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func set_state(st: Dictionary) -> void:
	"""st: see hex_grid._refresh_putt_panel."""
	_title.text = "%s green  ·  Par %d" % [st.get("green", ""), int(st.get("par", 0))]
	_counts.text = "PUTT %d / %d     PUTTING CHIPS %d     DECK %d  ·  DISCARD %d" % [
		int(st.get("putt", 0)), int(st.get("max", 4)), int(st.get("chips", 0)),
		int(st.get("draw", 0)), int(st.get("discard", 0))]
	_lag.text = "LAG PUTT  ·  %d" % int(st.get("lag_chips", 1))
	_lag.disabled = not st.get("can_lag", false)
	_peek_button.text = "CADDIE PEEK  ·  %d" % int(st.get("peek_chips", 1))
	_peek_button.disabled = not st.get("can_peek", false)
	var labels: Array[String] = []
	for id in st.get("flips", []):
		labels.append(PuttModifierDeck.card(id).label)
	var math: String = st.get("math", "")
	_flips.text = ("[%s]   %s" % ["] [".join(labels), math]) if not labels.is_empty() else math
	_peek.text = "Next card: %s" % st.peek if st.get("peek", "") != "" else ""
	_stamp.text = String(st.get("result", "")).to_upper()
