extends Control
class_name ShopPanel

## ShopPanel - The Pro Shop, full screen at the start of each hole (after the
## flyover).
##
## Top: your bag for the hole - tap BAG_SIZE of your clubs (tiles in their
## tier colour; the putter is always in), and better clubs for sale.
## Left: the RunShop's offers as real card faces with Buy buttons, the Eraser
## item, and a reroll. Right: your deck as card faces, the shot deck in rows of
## DECK_COLUMNS and the green deck below it. Tap any card to read it big
## (CardZoom) with what you can do to it here: Buy an offer; Remove or Upgrade
## a deck card. It only displays and forwards clicks: the host (hex_grid) owns
## the decks and the wallet and implements shop_* actions, then calls refresh().

const INK := ScorecardStyle.INK
const SOFT := ScorecardStyle.INK_SOFT
const RED := ScorecardStyle.RED
const DECK_COLUMNS := 6
const DECK_SCALE := 0.7   # deck cards a little smaller than the offers
const OFFER_SCALE := 0.74

var shop: RunShop
var host  # hex_grid: shop_balance(), shop_deck_cards(), shop_buy(i), shop_buy_eraser(), shop_reroll(), shop_remove(card), shop_upgrade(card), shop_continue()
var main_ui  # builds card faces (build_shot_card)

var _balance: Label
var _bag_caption: Label
var _bag_row: HBoxContainer
var _club_offers: HBoxContainer
var _hole := 1  # the hole this visit is for
var _hole_title: Label
var _hole_details: Label
var _offers: GridContainer
var _deck_caption: Label
var _deck_grid: GridContainer
var _green_caption: Label
var _green_grid: GridContainer
var _reroll_button: Button
var _continue_button: Button
var _note: Label
var _zoom: CardZoom
var _tapped: Control = null  # the card last tapped


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Full screen: one sheet of scorecard paper covers the whole view
	var panel := PanelContainer.new()
	var box := ScorecardStyle.paper_box(INK, 0, ScorecardStyle.PAPER, 0)
	box.content_margin_left = 48
	box.content_margin_right = 48
	box.content_margin_top = 28
	box.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	header.add_theme_constant_override("separation", 36)
	header.add_child(_label("PRO SHOP", 44, INK, ScorecardStyle.header_font()))
	var hole_info := VBoxContainer.new()
	hole_info.add_theme_constant_override("separation", 0)
	hole_info.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(hole_info)
	_hole_title = _label("", 30, RED, ScorecardStyle.header_font())
	hole_info.add_child(_hole_title)
	_hole_details = _caption("")
	hole_info.add_child(_hole_details)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_balance = _label("", 44, ScorecardStyle.PENCIL, ScorecardStyle.pencil_font())
	header.add_child(_balance)
	col.add_child(_rule(RED, 3))

	# The bag for this hole, and clubs for sale
	var bag := HBoxContainer.new()
	bag.add_theme_constant_override("separation", 40)
	col.add_child(bag)
	var bag_col := VBoxContainer.new()
	bag_col.add_theme_constant_override("separation", 8)
	bag.add_child(bag_col)
	_bag_caption = _caption("")
	bag_col.add_child(_bag_caption)
	_bag_row = HBoxContainer.new()
	_bag_row.add_theme_constant_override("separation", 10)
	bag_col.add_child(_bag_row)
	var shop_col := VBoxContainer.new()
	shop_col.add_theme_constant_override("separation", 8)
	bag.add_child(shop_col)
	shop_col.add_child(_caption("CLUBS FOR SALE  ·  REPLACES YOURS"))
	_club_offers = HBoxContainer.new()
	_club_offers.add_theme_constant_override("separation", 12)
	shop_col.add_child(_club_offers)
	col.add_child(_rule(ScorecardStyle.RULE, 1))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 40)
	col.add_child(body)

	# Left: for sale
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	left.add_child(_caption("FOR SALE  ·  TAP A CARD TO READ IT"))
	_offers = GridContainer.new()
	_offers.columns = 2
	_offers.add_theme_constant_override("h_separation", 20)
	_offers.add_theme_constant_override("v_separation", 16)
	left.add_child(_offers)
	_reroll_button = _button("REROLL  ·  %d" % RunShop.REROLL_PRICE, func(): host.shop_reroll())
	left.add_child(_reroll_button)

	var divider := ColorRect.new()
	divider.color = ScorecardStyle.RULE
	divider.custom_minimum_size = Vector2(2, 0)
	body.add_child(divider)

	# Right: your deck
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	_deck_caption = _caption("")
	right.add_child(_deck_caption)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var decks := VBoxContainer.new()
	decks.add_theme_constant_override("separation", 10)
	scroll.add_child(decks)
	_deck_grid = _grid()
	decks.add_child(_deck_grid)
	_green_caption = _caption("")
	decks.add_child(_green_caption)
	_green_grid = _grid()
	decks.add_child(_green_grid)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	col.add_child(actions)
	_note = _label("", 24, ScorecardStyle.PENCIL, ScorecardStyle.pencil_font())
	actions.add_child(_note)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(fill)
	_continue_button = _button("Continue", func(): host.shop_continue())
	_continue_button.custom_minimum_size = Vector2(260, 56)
	ScorecardStyle.flat_button(_continue_button, RED, RED)
	_continue_button.add_theme_font_size_override("font_size", 22)
	actions.add_child(_continue_button)

	_zoom = CardZoom.new()
	add_child(_zoom)


func open(p_shop: RunShop, p_host, p_main_ui, next_hole: int) -> void:
	shop = p_shop
	host = p_host
	main_ui = p_main_ui
	_hole = next_hole
	var info: Dictionary = host.shop_hole_info()
	_hole_title.text = info.title
	_hole_details.text = info.details
	visible = true
	refresh()


func refresh() -> void:
	"""Rebuild the offers and the deck from the shop and the host."""
	var balance: int = host.shop_balance()
	_balance.text = "%d pts" % balance
	_refresh_bag(balance)
	for c in _offers.get_children():
		c.queue_free()
	for i in range(shop.offers.size()):
		var data: CardData = shop.offers[i]
		var price := RunShop.price_of(data)
		var instance := CardInstance.create_from_data(data)
		var idx := i
		var buy := func(): host.shop_buy(idx)
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 8)
		slot.add_child(_card(instance, OFFER_SCALE, func():
			_zoom.open(instance, [{"label": "BUY  ·  %d PTS" % price, "on_press": buy, "disabled": balance < price}],
				"" if balance >= price else "Not enough points: %d." % balance, true, _tapped)))
		var buy_button := _button("BUY  ·  %d" % price, buy)
		buy_button.disabled = balance < price
		slot.add_child(buy_button)
		_offers.add_child(slot)
	# The item: Eraser
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 8)
	var eraser := _item_face("Eraser", "-1 stroke off your run score.")
	eraser.custom_minimum_size = CardFaceView.SIZE * OFFER_SCALE
	item.add_child(eraser)
	var buy_item := _button("BUY  ·  %d" % RunShop.ERASER_PRICE, func(): host.shop_buy_eraser())
	buy_item.disabled = balance < RunShop.ERASER_PRICE or not shop.eraser_available
	if not shop.eraser_available:
		buy_item.text = "SOLD"
	item.add_child(buy_item)
	_offers.add_child(item)
	_reroll_button.disabled = balance < RunShop.REROLL_PRICE

	# The deck: shot cards in rows of DECK_COLUMNS, green cards below
	for grid in [_deck_grid, _green_grid]:
		for c in grid.get_children():
			c.queue_free()
	var shots := 0
	var greens := 0
	for card in host.shop_deck_cards():
		var green := RunShop.is_green_card(card.data)
		var picked = card
		var face := _card(card, DECK_SCALE, func(): _open_deck_card(picked))
		(_green_grid if green else _deck_grid).add_child(face)
		if green:
			greens += 1
		else:
			shots += 1
	_deck_caption.text = "YOUR DECK  ·  %d SHOT CARDS  ·  TAP A CARD TO READ, REMOVE OR UPGRADE IT" % shots
	_green_caption.text = "GREEN DECK  ·  %d CARDS" % greens
	_note.text = "Strain comes from overswinging. Tap it to remove it." if _has_strain() else ""


func _refresh_bag(balance: int) -> void:
	"""Owned clubs as tiles to pick for the hole, the putter locked in, and
	the club offers with Buy buttons."""
	for c in _bag_row.get_children():
		c.queue_free()
	for item in host.shop_clubs():
		var tile := _club_tile(item)
		tile.button_pressed = host.shop_bag_has(item.club)
		var club: int = item.club
		tile.pressed.connect(func(): host.shop_toggle_bag(club))
		_bag_row.add_child(tile)
	var putter := _club_tile(host.shop_putter())
	putter.locked = true
	putter.disabled = true
	putter.yards = "the green"
	_bag_row.add_child(putter)
	var needed: int = host.shop_bag_needed()
	var picked: int = host.hole_bag.size()
	_bag_caption.text = "YOUR BAG FOR HOLE %d  ·  PICK UP TO %d  ·  FEWER CLUBS, MORE POINTS: 4 %s · 3 %s · 2 %s · 1 %s  ·  PUTTER ALWAYS IN" % [
		_hole, host.shop_bag_size(), host.shop_bag_multiplier(4), host.shop_bag_multiplier(3), host.shop_bag_multiplier(2), host.shop_bag_multiplier(1)]
	_continue_button.disabled = needed > 0
	_continue_button.text = "PICK A CLUB" if needed > 0 else "TEE OFF  ·  %s POINTS  →" % host.shop_bag_multiplier(picked)

	for c in _club_offers.get_children():
		c.queue_free()
	for i in range(shop.club_offers.size()):
		var item: ClubItem = shop.club_offers[i]
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 6)
		var tile := _club_tile(item)
		tile.toggle_mode = false
		slot.add_child(tile)
		var idx := i
		var buy := _button("BUY  ·  %d" % item.price(), func(): host.shop_buy_club(idx))
		buy.disabled = balance < item.price()
		slot.add_child(buy)
		_club_offers.add_child(slot)
	if shop.club_offers.is_empty():
		_club_offers.add_child(_caption("SOLD OUT"))


func _club_tile(item: ClubItem) -> ClubTile:
	var tile := ClubTile.new()
	tile.item = item
	tile.yards = host.shop_club_yards(item.club)
	tile.uses = host.shop_club_uses(item.club)
	return tile


func clear_selection() -> void:
	"""Kept for the host; deck picks now happen in the zoom view."""
	pass


func _open_deck_card(card) -> void:
	var balance: int = host.shop_balance()
	var can_up := RunShop.can_upgrade(card)
	var note := ""
	if balance < RunShop.REMOVE_PRICE:
		note = "Not enough points: %d." % balance
	elif not can_up:
		note = "Already at its lowest cost." if ShotCardFace.cost_for(card.data) > 0 or card.upgrade_level > 0 else ""
	_zoom.open(card, [
		{"label": "REMOVE  ·  %d PTS" % RunShop.REMOVE_PRICE, "on_press": func(): host.shop_remove(card),
			"disabled": balance < RunShop.REMOVE_PRICE},
		{"label": "UPGRADE  ·  %d PTS  (−1 COST)" % RunShop.upgrade_price(card), "on_press": func(): host.shop_upgrade(card),
			"disabled": balance < RunShop.upgrade_price(card) or not can_up},
	], note, true, _tapped)


func _card(instance, scale: float, on_tap: Callable) -> Button:
	"""A card face that opens the zoom view when tapped."""
	var face := Button.new()
	main_ui.build_shot_card(face, instance)
	face.disabled = false
	face.custom_minimum_size = CardFaceView.SIZE * scale
	var drawn := face.get_node_or_null("Face") as Control
	if drawn:
		drawn.custom_minimum_size = CardFaceView.SIZE * scale  # the face draws at whatever size it is given
	face.pressed.connect(func():
		_tapped = face  # the zoom grows out of it
		on_tap.call())
	return face


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = DECK_COLUMNS
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	return g


func _has_strain() -> bool:
	for card in host.shop_deck_cards():
		if card.data.card_type == CardData.CardType.NEGATIVE:
			return true
	return false


func _item_face(title: String, text: String) -> Control:
	"""An item drawn as a card: red ITEM bar, name, effect."""
	var face := CardFaceView.new()
	face.tag = "ITEM"
	face.cost_text = ""
	face.title = title
	face.description = text
	face.stats = [["STROKES", "-1"], ["USE", "NOW"]]
	face.set_icon("eraser")
	return face


func _label(text: String, size: int, color: Color, font: Font = null) -> Label:
	return ScorecardStyle.label(text, size, color, font)


func _caption(text: String) -> Label:
	return ScorecardStyle.label(text, 16, SOFT, ScorecardStyle.header_font(false))


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
