extends RefCounted
class_name PuttModifierDeck

## PuttModifierDeck - Gloomhaven's attack modifier deck, for putts.
##
## Every putt but a lag flips the top card: the putt's pace is
## GreenBoard.PUTT_BASE plus the cards' values. Lasts the run.
##   +N / -N  - N more / less pace
##   rolling  - add it and flip another (they chain)
##   lip      - Lip out: the cup won't take this putt, it hangs on the edge
##   star     - Sweet spot: drops at any pace, or from a hex beside the cup
##   steady   - the slopes don't act on this putt (rolling)
##   yips     - curse, -3, added for a 3-putt; leaves the deck once drawn
##   blessed  - a one-use Sweet spot; leaves the deck once drawn
## Drawing a card marked shuffle (lip, star) shuffles the discards back in
## once the putt is flipped, like Gloomhaven's x2 and null.

const BASE_DECK := {
	"plus_0": 6, "plus_1": 4, "minus_1": 4, "plus_2": 1, "minus_2": 1,
	"rolling_1": 2, "lip": 1, "star": 1,
}

# id -> {name, label (the card's face), value, rolling, special, steady, shuffle, once}
const CARDS := {
	"plus_0": {"name": "+0", "label": "+0", "value": 0},
	"plus_1": {"name": "+1", "label": "+1", "value": 1},
	"plus_2": {"name": "+2", "label": "+2", "value": 2},
	"plus_3": {"name": "+3", "label": "+3", "value": 3},
	"minus_1": {"name": "-1", "label": "−1", "value": -1},
	"minus_2": {"name": "-2", "label": "−2", "value": -2},
	"rolling_1": {"name": "Rolling +1", "label": "+1 ↻", "value": 1, "rolling": true},
	"lip": {"name": "Lip out", "label": "✕", "value": 0, "special": "lip", "shuffle": true},
	"star": {"name": "Sweet spot", "label": "★", "value": 0, "special": "star", "shuffle": true},
	"steady": {"name": "Steady", "label": "Steady ↻", "value": 0, "rolling": true, "steady": true},
	"yips": {"name": "Yips", "label": "−3", "value": -3, "once": true},
	"blessed": {"name": "Blessed", "label": "★", "value": 0, "special": "star", "shuffle": true, "once": true},
}

var draw_pile: Array[String] = []
var discard: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	draw_pile = starter_ids()
	_shuffle(draw_pile)


static func starter_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in BASE_DECK:
		for i in range(BASE_DECK[id]):
			ids.append(id)
	return ids


static func card(id: String) -> Dictionary:
	return CARDS.get(id, CARDS.plus_0)


func size() -> int:
	return draw_pile.size() + discard.size()


func peek() -> String:
	"""The top card (Caddie Peek), refilling the draw pile first if it's empty."""
	if draw_pile.is_empty():
		_reshuffle()
	return draw_pile.back() if not draw_pile.is_empty() else ""


func flip() -> Dictionary:
	"""Flip for one putt: one card, more while they're rolling. Returns
	{cards: Array[String] (ids, in order), mod (sum of values), total (the
	putt's pace), special ("lip" | "star" | "": the last one flipped), steady,
	reshuffled}."""
	var out := {"cards": [] as Array[String], "mod": 0, "total": GreenBoard.PUTT_BASE, "special": "",
		"steady": false, "reshuffled": false}
	var reshuffle := false
	for _guard in range(size()):
		if draw_pile.is_empty():
			_reshuffle()
		if draw_pile.is_empty():
			break
		var id: String = draw_pile.pop_back()
		var c := card(id)
		if not c.get("once", false):
			discard.append(id)
		out.cards.append(id)
		out.mod += int(c.value)
		if c.has("special"):
			out.special = c.special
		out.steady = out.steady or c.get("steady", false)
		reshuffle = reshuffle or c.get("shuffle", false)
		if not c.get("rolling", false):
			break
	out.total = GreenBoard.PUTT_BASE + int(out.mod)
	if reshuffle:
		_reshuffle()
		out.reshuffled = true
	return out


static func describe(flipped: Dictionary) -> String:
	"""The putt's arithmetic, pencilled: "2 + 1 + 0 = 3", or "lag = 2"."""
	var cards: Array = flipped.get("cards", [])
	if cards.is_empty():
		return "lag = %d" % GreenBoard.PUTT_BASE
	var text := str(GreenBoard.PUTT_BASE)
	for id in cards:
		var v := int(card(id).value)
		text += (" − %d" % -v) if v < 0 else (" + %d" % v)
	text += " = %d" % int(flipped.get("total", GreenBoard.PUTT_BASE))
	match flipped.get("special", ""):
		"lip": text += "  ✕"
		"star": text += "  ★"
	return text


static func chain_odds(ids: Array) -> Array:
	"""Every outcome of one flip from a shuffled pile of ids, exactly:
	[{mod, special, steady, p}], one entry per distinct outcome."""
	var counts := {}
	for id in ids:
		counts[id] = counts.get(id, 0) + 1
	var acc := {}
	_chain(counts, ids.size(), 1.0, 0, "", false, acc)
	return acc.values()


static func _chain(counts: Dictionary, left: int, p: float, mod: int, special: String, steady: bool, acc: Dictionary) -> void:
	if left <= 0:
		_add_outcome(acc, mod, special, steady, p)
		return
	for id in counts.keys():
		var n: int = counts[id]
		if n <= 0:
			continue
		var c := card(id)
		var q := p * float(n) / float(left)
		var m := mod + int(c.value)
		var sp: String = c.get("special", special)
		var st: bool = steady or c.get("steady", false)
		if c.get("rolling", false):
			counts[id] = n - 1
			_chain(counts, left - 1, q, m, sp, st, acc)
			counts[id] = n
		else:
			_add_outcome(acc, m, sp, st, q)


static func _add_outcome(acc: Dictionary, mod: int, special: String, steady: bool, p: float) -> void:
	var key := "%d|%s|%s" % [mod, special, steady]
	if not acc.has(key):
		acc[key] = {"mod": mod, "special": special, "steady": steady, "p": 0.0}
	acc[key].p += p


func add(id: String) -> void:
	"""A new card goes into the discards (shop, a 3-putt's Yips)."""
	if CARDS.has(id):
		discard.append(id)


func remove(id: String) -> bool:
	"""Take one copy out of the deck (shop). True if there was one."""
	for pile in [draw_pile, discard]:
		var i: int = pile.find(id)
		if i >= 0:
			pile.remove_at(i)
			return true
	return false


func _reshuffle() -> void:
	draw_pile.append_array(discard)
	discard.clear()
	_shuffle(draw_pile)


func _shuffle(pile: Array[String]) -> void:
	"""Fisher-Yates on the deck's own RNG, so a seeded deck repeats."""
	for i in range(pile.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := pile[i]
		pile[i] = pile[j]
		pile[j] = t
