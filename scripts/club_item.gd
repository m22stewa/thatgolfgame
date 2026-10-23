extends RefCounted
class_name ClubItem

## ClubItem - A club you own: its type (hex_grid.ClubType), its quality tier,
## and the features the tier paid for. Each tier above Common carries one more
## feature point, spread at random over:
##   distance    - +1 hex of carry per point (the whole band moves out)
##   spin        - -1 roll after landing per point (it checks up)
##   forgiveness - -1 landing-ring spread per point (never below 0)
## Bought in the Pro Shop; a better club replaces the one of its type.

enum Tier { COMMON, RARE, LEGENDARY, EPIC }
const TIER_NAMES := ["COMMON", "RARE", "LEGENDARY", "EPIC"]
const TIER_COLORS := [
	Color(0.5, 0.5, 0.5),     # common: grey
	Color(0.2, 0.45, 0.85),   # rare: blue
	Color(0.55, 0.3, 0.8),    # legendary: purple
	Color(0.85, 0.62, 0.12),  # epic: gold
]
const TIER_PRICES := [0, 80, 150, 240]  # points in the Pro Shop
const FEATURE_CAPS := {"distance": 2, "spin": 2, "forgiveness": 1}

var club: int = -1
var club_name: String = ""
var tier: int = Tier.COMMON
var features := {"distance": 0, "spin": 0, "forgiveness": 0}


static func create(p_club: int, p_name: String, p_tier: int, rng: RandomNumberGenerator = null) -> ClubItem:
	"""A club of this tier with its feature points dealt out (seeded)."""
	var item := ClubItem.new()
	item.club = p_club
	item.club_name = p_name
	item.tier = p_tier
	for _p in range(p_tier):
		var open: Array = FEATURE_CAPS.keys().filter(func(f): return item.features[f] < FEATURE_CAPS[f])
		if open.is_empty():
			break
		open.sort()
		var f: String = open[rng.randi_range(0, open.size() - 1) if rng else randi_range(0, open.size() - 1)]
		item.features[f] += 1
	return item


func apply(base: Dictionary) -> Dictionary:
	"""This club's stats: the club type's base stats plus its features."""
	var s := base.duplicate()
	var d: int = features.distance
	for key in ["band_min", "band_max", "distance"]:
		if s.has(key):
			s[key] = int(s[key]) + d
	if s.has("band_center"):
		s.band_center = int(s.band_center) + d
	s.roll = maxi(0, int(s.get("roll", 0)) - int(features.spin))
	s.base_spread = maxi(0, int(s.get("base_spread", 0)) - int(features.forgiveness))
	return s


func color() -> Color:
	return TIER_COLORS[tier]


func tier_name() -> String:
	return TIER_NAMES[tier]


func price() -> int:
	return TIER_PRICES[tier]


func feature_lines() -> Array[String]:
	"""Short lines for the club's tile, e.g. ["+1 DISTANCE", "SPIN 1"]."""
	var out: Array[String] = []
	if features.distance > 0:
		out.append("+%d DISTANCE" % features.distance)
	if features.spin > 0:
		out.append("SPIN %d  (−%d ROLL)" % [features.spin, features.spin])
	if features.forgiveness > 0:
		out.append("FORGIVING")
	return out
