extends Control
class_name ShopPanel

## ShopPanel - The Pro Shop, full screen at the start of each hole (after the
## flyover).
##
## Two tabs, Clubs (open first) and Cards, with Tee Off below both.
##
## Clubs, in three areas. Left, above: your clubs - tap one to put it in the
## bag. Left, below: upgrades, better clubs for sale. Right: the bag for the
## hole, up to BAG_SIZE clubs plus the putter, stacked so only each card's ink
## column shows (the last one whole) - tap one to take it out.
##
## Cards. Left: the RunShop's offers as real card faces with Buy buttons, the
## Eraser item, and a reroll. Right: your deck as card faces, the shot deck in
## rows of DECK_COLUMNS and the green deck below it. Tap any card to read it
## big (CardZoom) with what you can do to it here: Buy an offer; Remove or
## Upgrade a deck card. On hole 1 the Cards tab is shut: no points to spend yet.
##
## It only displays and forwards clicks: the host (hex_grid) owns the decks
## and the wallet and implements shop_* actions, then calls refresh().

const INK := ScorecardStyle.INK
const SOFT := ScorecardStyle.INK_SOFT
const RED := ScorecardStyle.RED
const DECK_COLUMNS := 6
const DECK_SCALE := 0.7   # deck cards a little smaller than the offers
const OFFER_SCALE := 0.74
const BAG_SLOTS := 4  # clubs in the bag besides the putter (hex_grid.BAG_SIZE)
const BAG_STEP := 52.0 * ClubTile.SCALE  # stacked bag cards: just the ink column shows

var shop: RunShop
var host  # hex_grid: shop_balance(), shop_deck_cards(), shop_buy(i), shop_buy_eraser(), shop_reroll(), shop_remove(card), shop_upgrade(card), shop_continue()
var main_ui  # builds card faces (build_shot_card)

var _balance: Label
var _clubs_caption: Label
var _clubs_row: HFlowContainer
var _bag_caption: Label
var _bag_odds: Label
var _bag_stack: Control
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
var _clubs_tab: Button
var _cards_tab: Button
var _clubs_page: Control
var _cards_page: Control
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

	# The tabs, sitting on a red rule
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	col.add_child(tabs)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	tabs.add_child(tab_row)
	_clubs_tab = _tab("CLUBS", func(): _show_tab(true))
	tab_row.add_child(_clubs_tab)
	_cards_tab = _tab("CARDS", func(): _show_tab(false))
	tab_row.add_child(_cards_tab)
	tabs.add_child(_rule(RED, 3))

	# Clubs: your clubs over upgrades on the left, the bag on the right
	var clubs := HBoxContainer.new()
	clubs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clubs.add_theme_constant_override("separation", 40)
	col.add_child(clubs)
	_clubs_page = clubs
	var clubs_left := VBoxContainer.new()
	clubs_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clubs_left.add_theme_constant_override("separation", 8)
	clubs.add_child(clubs_left)
	_clubs_caption = _caption("")
	clubs_left.add_child(_clubs_caption)
	_clubs_row = HFlowContainer.new()
	_clubs_row.custom_minimum_size = Vector2(0, ClubTile.SIZE.y)
	_clubs_row.add_theme_constant_override("h_separation", 12)
	_clubs_row.add_theme_constant_override("v_separation", 12)
	clubs_left.add_child(_clubs_row)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	clubs_left.add_child(gap)
	clubs_left.add_child(_caption("UPGRADES  ·  A BETTER CLUB REPLACES YOURS"))
	_club_offers = HBoxContainer.new()
	_club_offers.add_theme_constant_override("separation", 12)
	clubs_left.add_child(_club_offers)

	var bag_divider := ColorRect.new()
	bag_divider.color = ScorecardStyle.RULE
	bag_divider.custom_minimum_size = Vector2(2, 0)
	clubs.add_child(bag_divider)
	var bag_col := VBoxContainer.new()
	bag_col.add_theme_constant_override("separation", 8)
	clubs.add_child(bag_col)
	_bag_caption = _caption("")
	bag_col.add_child(_bag_caption)
	var bag_box := PanelContainer.new()
	var bag_style := ScorecardStyle.paper_box(ScorecardStyle.RULE, 2, ScorecardStyle.PAPER_DARK, 6)
	bag_style.set_content_margin_all(14)
	bag_box.add_theme_stylebox_override("panel", bag_style)
	bag_col.add_child(bag_box)
	_bag_stack = Control.new()
	_bag_stack.custom_minimum_size = Vector2(BAG_STEP * BAG_SLOTS + ClubTile.SIZE.x, ClubTile.SIZE.y)
	bag_box.add_child(_bag_stack)
	_bag_odds = _caption("")
	bag_col.add_child(_bag_odds)

	# Cards: offers on the left, your deck on the right
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 40)
	col.add_child(body)
	_cards_page = body

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
	var cards := next_hole > 1
	_cards_tab.disabled = not cards
	_cards_tab.text = "CARDS" if cards else "CARDS  ·  AFTER HOLE 1"
	visible = true
	refresh()
	_show_tab(true)


func _show_tab(clubs: bool) -> void:
	_clubs_page.visible = clubs
	_cards_page.visible = not clubs
	_note.visible = not clubs
	_style_tab(_clubs_tab, clubs)
	_style_tab(_cards_tab, not clubs)


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
	_green_caption.text = "PUTTING DECK  ·  %s" % host.shop_putt_deck_text() if host.has_method("shop_putt_deck_text") else "GREEN DECK  ·  %d CARDS" % greens
	_note.text = "Strain comes from overswinging. Tap it to remove it." if _has_strain() else ""


func _refresh_bag(balance: int) -> void:
	"""Your clubs to tap into the bag, the bag stacked (putter at the back,
	then longest first), and the upgrades with Buy buttons."""
	for c in _clubs_row.get_children():
		c.queue_free()
	for c in _bag_stack.get_children():
		c.queue_free()
	var picked: int = host.hole_bag.size()
	var full: bool = picked >= host.shop_bag_size()
	var bagged: Array = [host.shop_putter()]
	for item in host.shop_clubs():
		var club: int = item.club
		if host.shop_bag_has(club):
			bagged.append(item)
			continue
		var tile := _club_tile(item)
		tile.toggle_mode = false
		if full:
			tile.modulate.a = 0.5  # no room in the bag
		tile.pressed.connect(func(): host.shop_toggle_bag(club))
		_clubs_row.add_child(tile)
	if _clubs_row.get_child_count() == 0:
		_clubs_row.add_child(_caption("ALL YOUR CLUBS ARE IN THE BAG"))
	for i in range(bagged.size()):
		var item: ClubItem = bagged[i]
		var tile := _club_tile(item)
		tile.toggle_mode = false
		tile.position = Vector2(BAG_STEP * i, 0)
		if i == 0:  # the putter
			tile.locked = true
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			var club: int = item.club
			tile.pressed.connect(func(): host.shop_toggle_bag(club))
		_bag_stack.add_child(tile)

	var needed: int = host.shop_bag_needed()
	_clubs_caption.text = ("YOUR CLUBS  ·  THE BAG IS FULL" if full else "YOUR CLUBS  ·  TAP ONE TO PUT IT IN THE BAG")
	_bag_caption.text = "YOUR BAG FOR HOLE %d  ·  %d OF %d  ·  TAP TO TAKE OUT" % [_hole, picked, host.shop_bag_size()]
	_bag_odds.text = "FEWER CLUBS, MORE POINTS:  4 %s · 3 %s · 2 %s · 1 %s\nPUTTER ALWAYS IN" % [
		host.shop_bag_multiplier(4), host.shop_bag_multiplier(3), host.shop_bag_multiplier(2), host.shop_bag_multiplier(1)]
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
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE  # bought with the button below
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
	tile.stats = host.shop_club_stats(item)
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


func _tab(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300, 60)
	b.add_theme_font_override("font", ScorecardStyle.header_font())
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(on_press)
	return b


func _style_tab(b: Button, active: bool) -> void:
	"""The open tab is red, joined to the rule below it; the other is paper."""
	var fill := RED if active else ScorecardStyle.PAPER_DARK
	var text := ScorecardStyle.PAPER if active else INK
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := ScorecardStyle.paper_box(RED if active else ScorecardStyle.RULE, 0 if active else 2, fill, 0)
		box.border_width_bottom = 0
		box.corner_radius_top_left = 8
		box.corner_radius_top_right = 8
		if state == "hover" and not active:
			box.bg_color = ScorecardStyle.PAPER
		b.add_theme_stylebox_override(state, box)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, text)
	b.add_theme_color_override("font_disabled_color", ScorecardStyle.INK_SOFT)


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
