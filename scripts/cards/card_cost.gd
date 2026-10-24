extends RefCounted
class_name CardCost

## CardCost - What a card costs to play, in Chips. Every playable card costs
## MIN..MAX (bigger effects cost more); Pro Shop upgrades take 1 off at a
## time but never below MIN. Strain is unplayable and has no cost.

const MIN := 1
const MAX := 6


static func after_upgrades(base: int, upgrade_level: int) -> int:
	return clampi(base - upgrade_level, MIN, MAX)


static func base_of(data: CardData) -> int:
	"""The printed cost (before upgrades); 0 for a card with no cost (Strain)."""
	for e in data.effects:
		if "power_cost" in e:
			return int(e.power_cost)
	return 0


static func of(data: CardData, upgrade_level: int = 0) -> int:
	var base := base_of(data)
	return after_upgrades(base, upgrade_level) if base > 0 else 0
