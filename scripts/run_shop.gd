extends RefCounted
class_name RunShop

## RunShop - The Pro Shop between holes: where trick-shot points get spent.
##
## Pure rules (offers, prices, what can be upgraded or removed); hex_grid owns
## the decks and the wallet and applies purchases. Offers are drawn from the
## run's seeded RNG, weighted by rarity, never twice the same card in a row of
## offers.

const OFFER_COUNT := 3
const PRICES := {
	CardData.Rarity.COMMON: 60,
	CardData.Rarity.UNCOMMON: 100,
	CardData.Rarity.RARE: 150,
	CardData.Rarity.LEGENDARY: 250,
}
const RARITY_WEIGHT := {
	CardData.Rarity.COMMON: 6.0,
	CardData.Rarity.UNCOMMON: 3.0,
	CardData.Rarity.RARE: 1.0,
	CardData.Rarity.LEGENDARY: 0.3,
}
const REMOVE_PRICE := 50
const UPGRADE_PRICE := 75
const REROLL_PRICE := 25
const ERASER_PRICE := 150  # item: -1 stroke off the run score

# Cards the shop can sell: shot cards (shot deck) and green cards (putt deck)
const POOL := [
	"draw_shot", "fade_shot", "hard_draw", "hard_fade", "loft", "stop",
	"release", "dart", "knockdown", "stinger", "flag_hunter",
	"read_green", "firm_putt", "dead_weight",
	"extinguisher", "groundskeeper", "shutoff",
]

var offers: Array[CardData] = []
var eraser_available := true


func roll_offers(rng: RandomNumberGenerator) -> void:
	"""OFFER_COUNT different cards, weighted by rarity."""
	offers.clear()
	eraser_available = true
	var pool: Array[CardData] = []
	for id in POOL:
		var data: CardData = CardLibrary.instance.get_card(id) if CardLibrary.instance else null
		if data:
			pool.append(data)
	for i in range(OFFER_COUNT):
		if pool.is_empty():
			break
		var total := 0.0
		for d in pool:
			total += float(RARITY_WEIGHT.get(d.rarity, 1.0))
		var pick := rng.randf() * total
		for d in pool:
			pick -= float(RARITY_WEIGHT.get(d.rarity, 1.0))
			if pick <= 0.0:
				offers.append(d)
				pool.erase(d)
				break


static func price_of(data: CardData) -> int:
	return int(PRICES.get(data.rarity, 100))


static func is_green_card(data: CardData) -> bool:
	"""Green cards live in the putting deck."""
	for e in data.effects:
		if e is EffectPuttCard:
			return true
	return false


static func can_upgrade(card: CardInstance) -> bool:
	"""Upgrades take a shot card's power cost down by 1 (to 0)."""
	for e in card.data.effects:
		if e is EffectShotShape:
			return e.power_cost - card.upgrade_level > 0
	return false
