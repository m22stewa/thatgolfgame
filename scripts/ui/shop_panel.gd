extends Control
class_name ShopPanel

## ShopPanel - The Pro Shop overlay between holes.
##
## Shows the RunShop's offers as real card faces with Buy buttons, the Eraser
## item, a reroll, and the run's deck as chips you can pick to Remove or
## Upgrade. It only displays and forwards clicks: the host (hex_grid) owns the
## decks and the wallet and implements shop_* actions, then calls refresh().

const INK := ScorecardStyle.INK
const SOFT := ScorecardStyle.INK_SOFT
const RED := ScorecardStyle.RED

var shop: RunShop
var host  # hex_grid: shop_balance(), shop_deck_cards(), shop_buy(i), shop_buy_eraser(), shop_reroll(), shop_remove(card), shop_upgrade(card), shop_continue()
var main_ui  # builds card faces (build_shot_card)

var _balance: Label
var _offers_row: HBoxContainer
var _deck_flow: HFlowContainer
var _remove_button: Button
var _upgrade_button: Button
var _reroll_button: Button
var _continue_button: Button
var _note: Label
var _selected = null  # deck card picked for Remove / Upgrade


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var panel := PanelContainer.new()
	var box := ScorecardStyle.paper_box(INK, 3)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 20
	box.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -590
	panel.offset_right = 590
	panel.offset_top = -380
	panel.offset_bottom = 380

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	header.add_child(_label("PRO SHOP", 40, INK, ScorecardStyle.header_font()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_balance = _label("", 40, ScorecardStyle.PENCIL, ScorecardStyle.pencil_font())
	header.add_child(_balance)
	col.add_child(_rule(RED, 3))

	col.add_child(_caption("FOR SALE"))
	_offers_row = HBoxContainer.new()
	_offers_row.add_theme_constant_override("separation", 18)
	col.add_child(_offers_row)

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 12)
	col.add_child(mid)
	_reroll_button = _button("REROLL  ·  %d" % RunShop.REROLL_PRICE, func(): host.shop_reroll())
	mid.add_child(_reroll_button)
	_note = _label("", 22, ScorecardStyle.PENCIL, ScorecardStyle.pencil_font())
	mid.add_child(_note)

	col.add_child(_rule(ScorecardStyle.RULE, 1))
	col.add_child(_caption("YOUR DECK  ·  PICK A CARD TO REMOVE OR UPGRADE"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_deck_flow = HFlowContainer.new()
	_deck_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_flow.add_theme_constant_override("h_separation", 8)
	_deck_flow.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_deck_flow)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	col.add_child(actions)
	_remove_button = _button("REMOVE  ·  %d" % RunShop.REMOVE_PRICE, func(): host.shop_remove(_selected))
	actions.add_child(_remove_button)
	_upgrade_button = _button("UPGRADE  ·  %d  (-1 POWER)" % RunShop.UPGRADE_PRICE, func(): host.shop_upgrade(_selected))
	actions.add_child(_upgrade_button)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(fill)
	_continue_button = _button("Continue", func(): host.shop_continue())
	_continue_button.custom_minimum_size = Vector2(240, 56)
	ScorecardStyle.flat_button(_continue_button, RED, RED)
	actions.add_child(_continue_button)


func open(p_shop: RunShop, p_host, p_main_ui, next_hole: int) -> void:
	shop = p_shop
	host = p_host
	main_ui = p_main_ui
	_selected = null
	_continue_button.text = "TEE OFF HOLE %d  →" % next_hole
	visible = true
	refresh()


func refresh() -> void:
	"""Rebuild the offers and the deck from the shop and the host."""
	var balance: int = host.shop_balance()
	_balance.text = "%d pts" % balance
	for c in _offers_row.get_children():
		c.queue_free()
	for i in range(shop.offers.size()):
		var data: CardData = shop.offers[i]
		var price := RunShop.price_of(data)
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 8)
		var face := Button.new()
		face.disabled = true
		main_ui.build_shot_card(face, CardInstance.create_from_data(data))
		slot.add_child(face)
		var idx := i
		var buy := _button("BUY  ·  %d" % price, func(): host.shop_buy(idx))
		buy.disabled = balance < price
		slot.add_child(buy)
		_offers_row.add_child(slot)
	# The item: Eraser
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 8)
	item.add_child(_item_face("Eraser", "-1 stroke off your run score. Used at once."))
	var buy_item := _button("BUY  ·  %d" % RunShop.ERASER_PRICE, func(): host.shop_buy_eraser())
	buy_item.disabled = balance < RunShop.ERASER_PRICE or not shop.eraser_available
	if not shop.eraser_available:
		buy_item.text = "SOLD"
	item.add_child(buy_item)
	_offers_row.add_child(item)
	_reroll_button.disabled = balance < RunShop.REROLL_PRICE

	for c in _deck_flow.get_children():
		c.queue_free()
	for card in host.shop_deck_cards():
		var chip := Button.new()
		chip.toggle_mode = true
		chip.button_pressed = card == _selected
		var tag: String = ShotCardFace.kind_for(card.data).tag
		chip.text = card.get_display_name().to_upper()
		chip.custom_minimum_size = Vector2(130, 38)
		ScorecardStyle.flat_button(chip)
		chip.add_theme_font_size_override("font_size", 15)
		# A coloured left edge for the card's category, red when picked
		var normal := ScorecardStyle.paper_box(ScorecardStyle.RULE, 1)
		normal.border_width_left = 6
		normal.border_color = ScorecardStyle.category_color(tag)
		chip.add_theme_stylebox_override("normal", normal)
		var picked_box := ScorecardStyle.paper_box(RED, 3, ScorecardStyle.PAPER_DARK)
		picked_box.border_width_left = 6
		chip.add_theme_stylebox_override("pressed", picked_box)
		chip.add_theme_stylebox_override("hover_pressed", picked_box)
		if card.data.card_type == CardData.CardType.NEGATIVE:
			chip.add_theme_color_override("font_color", RED)
		var picked = card
		chip.pressed.connect(func():
			_selected = picked if _selected != picked else null
			refresh())
		_deck_flow.add_child(chip)
	_remove_button.disabled = _selected == null or balance < RunShop.REMOVE_PRICE
	_upgrade_button.disabled = _selected == null or balance < RunShop.UPGRADE_PRICE or not RunShop.can_upgrade(_selected)
	_note.text = "Strain comes from overswinging - remove it here." if _has_strain() else ""


func clear_selection() -> void:
	_selected = null


func _has_strain() -> bool:
	for card in host.shop_deck_cards():
		if card.data.card_type == CardData.CardType.NEGATIVE:
			return true
	return false


func _item_face(title: String, text: String) -> Control:
	"""An item drawn as a card: red ITEM bar, name, effect."""
	var face := CardFaceView.new()
	face.tag = "ITEM"
	face.cost_text = "ONCE"
	face.title = title
	face.description = text
	face.stats = [["STROKES", "-1"], ["USE", "NOW"]]
	face.set_icon("eraser")
	return face


func _label(text: String, size: int, color: Color, font: Font = null) -> Label:
	return ScorecardStyle.label(text, size, color, font)


func _caption(text: String) -> Label:
	return ScorecardStyle.label(text, 15, SOFT, ScorecardStyle.header_font(false))


func _rule(color: Color, height: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, height)
	return r


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 44)
	ScorecardStyle.flat_button(b)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(on_press)
	return b
