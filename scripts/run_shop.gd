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
	CardData.Rarity.COMMON: 120,
	CardData.Rarity.UNCOMMON: 200,
	CardData.Rarity.RARE: 300,
	CardData.Rarity.LEGENDARY: 500,
}
const RARITY_WEIGHT := {
	CardData.Rarity.COMMON: 6.0,
	CardData.Rarity.UNCOMMON: 3.0,
	CardData.Rarity.RARE: 1.0,
	CardData.Rarity.LEGENDARY: 0.3,
}
const REMOVE_PRICE := 100
const UPGRADE_PRICE := 400  # the first upgrade of a card; each one after costs UPGRADE_STEP more
const UPGRADE_STEP := 250
const REROLL_PRICE := 50
const ERASER_PRICE := 300  # item: -1 stroke off the run score

# Cards the shop can sell: shot cards (shot deck) and green cards (putt deck)
const POOL := [
	"draw_shot", "fade_shot", "hard_draw", "hard_fade", "loft", "stop",
	"release", "dart", "knockdown", "stinger", "flag_hunter",
	"topspin", "backspin", "heavy_topspin", "zip_back", "range_finder", "locked_in",
	"read_green", "firm_putt", "charge_putt", "steady_stroke", "dead_weight",
	"extinguisher", "groundskeeper", "shutoff",
]

const CLUB_OFFER_COUNT := 2
const CLUB_TIER_WEIGHT := {  # tiers above Common; Common clubs aren't sold
	ClubItem.Tier.RARE: 6.0,
	ClubItem.Tier.LEGENDARY: 2.5,
	ClubItem.Tier.EPIC: 1.0,
}

var offers: Array[CardData] = []
var club_offers: Array[ClubItem] = []
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


func roll_club_offers(rng: RandomNumberGenerator, owned: Dictionary) -> void:
	"""CLUB_OFFER_COUNT better versions of clubs you own (owned: ClubType ->
	ClubItem), each of a different club, tier weighted toward Rare."""
	club_offers.clear()
	var types: Array = owned.keys().filter(func(c): return owned[c].tier < ClubItem.Tier.EPIC)
	types.sort()
	for _i in range(CLUB_OFFER_COUNT):
		if types.is_empty():
			break
		var club: int = types.pop_at(rng.randi_range(0, types.size() - 1))
		var have: ClubItem = owned[club]
		var tiers: Array = CLUB_TIER_WEIGHT.keys().filter(func(t): return t > have.tier)
		var total := 0.0
		for t in tiers:
			total += CLUB_TIER_WEIGHT[t]
		var pick := rng.randf() * total
		var tier: int = tiers[tiers.size() - 1]
		for t in tiers:
			pick -= CLUB_TIER_WEIGHT[t]
			if pick <= 0.0:
				tier = t
				break
		club_offers.append(ClubItem.create(club, have.club_name, tier, rng))


static func price_of(data: CardData) -> int:
	return int(PRICES.get(data.rarity, 100))


static func is_green_card(data: CardData) -> bool:
	"""Green cards live in the putting deck."""
	for e in data.effects:
		if e is EffectPuttCard:
			return true
	return false


static func can_upgrade(card: CardInstance) -> bool:
	"""Upgrades take a card's Chip cost down by 1, to CardCost.MIN."""
	return CardCost.of(card.data, card.upgrade_level) > CardCost.MIN


static func upgrade_price(card: CardInstance) -> int:
	"""Points for the card's next upgrade: dearer each time."""
	return UPGRADE_PRICE + UPGRADE_STEP * card.upgrade_level
