extends Control
class_name ShopPanel

## ShopPanel - The Pro Shop overlay between holes.
##
## Shows the RunShop's offers as real card faces with Buy buttons, the Eraser
## item, a reroll, and the run's deck as chips you can pick to Remove or
## Upgrade. It only displays and forwards clicks: the host (hex_grid) owns the
## decks and the wallet and implements shop_* actions, then calls refresh().

const FELT := Color(0.09, 0.2, 0.13, 0.97)
const BRASS := Color(0.86, 0.62, 0.2)
const INK := Color(0.95, 0.93, 0.85)

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
	var box := StyleBoxFlat.new()
	box.bg_color = FELT
	box.border_color = BRASS
	box.set_border_width_all(4)
	box.set_corner_radius_all(14)
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
	header.add_child(_label("Pro Shop", 34, BRASS))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_balance = _label("", 26, INK)
	header.add_child(_balance)

	col.add_child(_label("For sale", 18, INK.darkened(0.2)))
	_offers_row = HBoxContainer.new()
	_offers_row.add_theme_constant_override("separation", 18)
	col.add_child(_offers_row)

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 12)
	col.add_child(mid)
	_reroll_button = _button("Reroll  %d" % RunShop.REROLL_PRICE, func(): host.shop_reroll())
	mid.add_child(_reroll_button)
	_note = _label("", 16, INK.darkened(0.25))
	mid.add_child(_note)

	col.add_child(_label("Your deck  (pick a card to remove or upgrade)", 18, INK.darkened(0.2)))
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
	_remove_button = _button("Remove  %d" % RunShop.REMOVE_PRICE, func(): host.shop_remove(_selected))
	actions.add_child(_remove_button)
	_upgrade_button = _button("Upgrade  %d  (-1 power)" % RunShop.UPGRADE_PRICE, func(): host.shop_upgrade(_selected))
	actions.add_child(_upgrade_button)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(fill)
	_continue_button = _button("Continue", func(): host.shop_continue())
	_continue_button.custom_minimum_size = Vector2(220, 56)
	actions.add_child(_continue_button)


func open(p_shop: RunShop, p_host, p_main_ui, next_hole: int) -> void:
	shop = p_shop
	host = p_host
	main_ui = p_main_ui
	_selected = null
	_continue_button.text = "Continue to hole %d" % next_hole
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
		var face := Button.new()
		face.disabled = true
		main_ui.build_shot_card(face, CardInstance.create_from_data(data))
		slot.add_child(face)
		var idx := i
		var buy := _button("Buy  %d" % price, func(): host.shop_buy(idx))
		buy.disabled = balance < price
		slot.add_child(buy)
		_offers_row.add_child(slot)
	# The item: Eraser
	var item := VBoxContainer.new()
	item.add_child(_item_face("Eraser", "-1 stroke off your run score. Used at once."))
	var buy_item := _button("Buy  %d" % RunShop.ERASER_PRICE, func(): host.shop_buy_eraser())
	buy_item.disabled = balance < RunShop.ERASER_PRICE or not shop.eraser_available
	if not shop.eraser_available:
		buy_item.text = "Sold"
	item.add_child(buy_item)
	_offers_row.add_child(item)
	_reroll_button.disabled = balance < RunShop.REROLL_PRICE

	for c in _deck_flow.get_children():
		c.queue_free()
	for card in host.shop_deck_cards():
		var chip := Button.new()
		chip.toggle_mode = true
		chip.button_pressed = card == _selected
		chip.text = card.get_display_name()
		chip.custom_minimum_size = Vector2(120, 40)
		chip.add_theme_stylebox_override("pressed", _box(BRASS, Color(1.0, 0.95, 0.8), 3))
		chip.add_theme_stylebox_override("hover_pressed", _box(BRASS, Color(1.0, 0.95, 0.8), 3))
		chip.add_theme_color_override("font_pressed_color", Color(0.12, 0.1, 0.05))
		chip.add_theme_color_override("font_hover_pressed_color", Color(0.12, 0.1, 0.05))
		if card.data.card_type == CardData.CardType.NEGATIVE:
			chip.add_theme_color_override("font_color", Color(0.62, 0.08, 0.05))
		var picked = card
		chip.pressed.connect(func():
			_selected = picked if _selected != picked else null
			refresh())
		_deck_flow.add_child(chip)
	_remove_button.disabled = _selected == null or balance < RunShop.REMOVE_PRICE
	_upgrade_button.disabled = _selected == null or balance < RunShop.UPGRADE_PRICE or not RunShop.can_upgrade(_selected)
	_note.text = "Strain cards come from overswinging; remove them here." if _has_strain() else ""


func clear_selection() -> void:
	_selected = null


func _has_strain() -> bool:
	for card in host.shop_deck_cards():
		if card.data.card_type == CardData.CardType.NEGATIVE:
			return true
	return false


func _item_face(title: String, text: String) -> Control:
	"""An item drawn like a card: paper face, ITEM tag, name, effect."""
	var face := PanelContainer.new()
	face.custom_minimum_size = Vector2(136, 150)
	var paper := _box(Color(0.97, 0.95, 0.89), Color(0.13, 0.13, 0.11), 2)
	paper.content_margin_left = 10
	paper.content_margin_right = 10
	paper.content_margin_top = 8
	face.add_theme_stylebox_override("panel", paper)
	var col := VBoxContainer.new()
	face.add_child(col)
	col.add_child(_label("ITEM", 11, Color(0.4, 0.38, 0.33)))
	col.add_child(_label(title, 16, Color(0.13, 0.13, 0.11)))
	var body := _label(text, 12, Color(0.3, 0.29, 0.26))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(body)
	return face


func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(8)
	return box


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(136, 44)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(on_press)
	return b
