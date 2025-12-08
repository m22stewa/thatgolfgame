extends Node
class_name CardLibrary

## Static library of all available cards in the game.
## Provides factory methods to create card instances.

# Singleton pattern - set via autoload
static var instance: CardLibrary

# All registered card data indexed by ID
var _cards: Dictionary = {}


func _ready() -> void:
	CardLibrary.instance = self
	_register_all_cards()


func _register_all_cards() -> void:
	_register_golf_cards()
	_register_club_cards()


#region Card Registration

func _register_club_cards() -> void:
	# Register a card for each club type
	var clubs = [
		{"id": "club_driver", "name": "Driver", "club": "DRIVER", "desc": "Max distance off the tee."},
		{"id": "club_3wood", "name": "3 Wood", "club": "WOOD_3", "desc": "Long distance fairway wood."},
		{"id": "club_5wood", "name": "5 Wood", "club": "WOOD_5", "desc": "Versatile fairway wood."},
		{"id": "club_3iron", "name": "3 Iron", "club": "IRON_3", "desc": "Long iron for distance."},
		{"id": "club_5iron", "name": "5 Iron", "club": "IRON_5", "desc": "Mid-long iron."},
		{"id": "club_6iron", "name": "6 Iron", "club": "IRON_6", "desc": "Mid iron utility."},
		{"id": "club_7iron", "name": "7 Iron", "club": "IRON_7", "desc": "Standard mid iron."},
		{"id": "club_8iron", "name": "8 Iron", "club": "IRON_8", "desc": "Short-mid iron."},
		{"id": "club_9iron", "name": "9 Iron", "club": "IRON_9", "desc": "Short iron for approach."},
		{"id": "club_pw", "name": "Pitching Wedge", "club": "PITCHING_WEDGE", "desc": "High loft for approach."},
		{"id": "club_sw", "name": "Sand Wedge", "club": "SAND_WEDGE", "desc": "Max loft, best for bunkers."},
		{"id": "club_putter", "name": "Putter", "club": "PUTTER", "desc": "For the green."}
	]
	
	for c in clubs:
		var card = CardData.create(c.id, c.name, CardData.Rarity.COMMON)
		card.card_type = CardData.CardType.CLUB
		card.target_club = c.club
		card.description = c.desc
		_register(card)


func _register_golf_cards() -> void:
	# === CLEAN STRIKE (4) ===
	var clean_strike = CardData.create("clean_strike", "Clean Strike", CardData.Rarity.COMMON)
	clean_strike.card_type = CardData.CardType.SHOT
	clean_strike.description = "No change to distance, accuracy, roll, or score."
	clean_strike.flavor_text = "Represents a normal, expected shot."
	clean_strike.tags = ["neutral"]
	_register(clean_strike)
	
	# === CONTROLLED AIM (2) ===
	var controlled_aim = CardData.create("controlled_aim", "Controlled Aim", CardData.Rarity.COMMON)
	controlled_aim.card_type = CardData.CardType.SHOT
	controlled_aim.description = "AOE radius -1 ring (minimum 0)."
	controlled_aim.flavor_text = "Small precision boost, no distance change."
	controlled_aim.tags = ["accuracy"]
	
	var ca_effect = EffectSimpleStat.new()
	ca_effect.target_stat = "aoe_radius"
	ca_effect.value = -1
	controlled_aim.effects.append(ca_effect)
	_register(controlled_aim)
	
	# === SLIGHTLY SHORT (3) ===
	var slightly_short = CardData.create("slightly_short", "Slightly Short", CardData.Rarity.COMMON)
	slightly_short.card_type = CardData.CardType.SHOT
	slightly_short.description = "Distance -1 tile."
	slightly_short.flavor_text = "Common small distance miss."
	slightly_short.tags = ["distance"]
	
	var ss_effect = EffectSimpleStat.new()
	ss_effect.target_stat = "power_mod"
	ss_effect.value = -1
	slightly_short.effects.append(ss_effect)
	_register(slightly_short)
	
	# === WAY SHORT (1) ===
	var way_short = CardData.create("way_short", "Way Short", CardData.Rarity.UNCOMMON)
	way_short.card_type = CardData.CardType.SHOT
	way_short.description = "Distance -2 tiles."
	way_short.flavor_text = "Larger mishit, but not catastrophic."
	way_short.tags = ["distance"]
	
	var ws_effect = EffectSimpleStat.new()
	ws_effect.target_stat = "power_mod"
	ws_effect.value = -2
	way_short.effects.append(ws_effect)
	_register(way_short)
	
	# === SOLID CONTACT (1) ===
	var solid_contact = CardData.create("solid_contact", "Solid Contact", CardData.Rarity.COMMON)
	solid_contact.card_type = CardData.CardType.SHOT
	solid_contact.description = "Distance +1 tile."
	solid_contact.flavor_text = "Minor distance bonus for well-struck shots."
	solid_contact.tags = ["distance"]
	
	var sc_effect = EffectSimpleStat.new()
	sc_effect.target_stat = "power_mod"
	sc_effect.value = 1
	solid_contact.effects.append(sc_effect)
	_register(solid_contact)
	
	# === CRUSHED IT (1) ===
	var crushed_it = CardData.create("crushed_it", "Crushed It", CardData.Rarity.RARE)
	crushed_it.card_type = CardData.CardType.SHOT
	crushed_it.description = "Distance +2 tiles."
	crushed_it.flavor_text = "Big distance boost, exciting on drives."
	crushed_it.tags = ["distance"]
	
	var ci_effect = EffectSimpleStat.new()
	ci_effect.target_stat = "power_mod"
	ci_effect.value = 2
	crushed_it.effects.append(ci_effect)
	_register(crushed_it)
	
	# === SHANK (2) ===
	var shank = CardData.create("shank", "Shank", CardData.Rarity.UNCOMMON)
	shank.card_type = CardData.CardType.SHOT
	shank.description = "AOE radius +1 ring."
	shank.flavor_text = "Less accurate shot, larger landing zone."
	shank.tags = ["accuracy"]
	
	var shank_effect = EffectSimpleStat.new()
	shank_effect.target_stat = "aoe_radius"
	shank_effect.value = 1
	shank.effects.append(shank_effect)
	_register(shank)
	
	# === WILD PUSH (1) ===
	var wild_push = CardData.create("wild_push", "Wild Push", CardData.Rarity.UNCOMMON)
	wild_push.card_type = CardData.CardType.SHOT
	wild_push.description = "AOE radius +1 ring; add small curve toward miss side."
	wild_push.flavor_text = "Feels like a directional hook/slice miss."
	wild_push.tags = ["accuracy", "curve"]
	
	var wp_aoe = EffectSimpleStat.new()
	wp_aoe.target_stat = "aoe_radius"
	wp_aoe.value = 1
	wild_push.effects.append(wp_aoe)
	
	var wp_curve = EffectCurveShot.new()
	wp_curve.curve_direction = 2 # Random
	wp_curve.curve_strength = 0.2
	wild_push.effects.append(wp_curve)
	_register(wild_push)
	
	# === LASER LINE (1) ===
	var laser_line = CardData.create("laser_line", "Laser Line", CardData.Rarity.RARE)
	laser_line.card_type = CardData.CardType.SHOT
	laser_line.description = "Set AOE radius to 0."
	laser_line.flavor_text = "Very accurate \"sniper\" shot."
	laser_line.tags = ["accuracy"]
	
	var ll_effect = EffectSimpleStat.new()
	ll_effect.target_stat = "aoe_radius"
	ll_effect.value = 0
	ll_effect.set_mode = true
	laser_line.effects.append(ll_effect)
	_register(laser_line)
	
	# === HEAVY SPIN (1) ===
	var heavy_spin = CardData.create("heavy_spin", "Heavy Spin", CardData.Rarity.UNCOMMON)
	heavy_spin.card_type = CardData.CardType.SHOT
	heavy_spin.description = "Roll -1 tile (minimum 0)."
	heavy_spin.flavor_text = "Helps shots stop faster, good for approaches."
	heavy_spin.tags = ["roll", "spin"]
	
	var hs_effect = EffectSimpleStat.new()
	hs_effect.target_stat = "roll_mod"
	hs_effect.value = -1
	heavy_spin.effects.append(hs_effect)
	_register(heavy_spin)
	
	# === HOT BOUNCE (1) ===
	var hot_bounce = CardData.create("hot_bounce", "Hot Bounce", CardData.Rarity.UNCOMMON)
	hot_bounce.card_type = CardData.CardType.SHOT
	hot_bounce.description = "Roll +1 tile."
	hot_bounce.flavor_text = "Extra rollout after landing."
	hot_bounce.tags = ["roll"]
	
	var hb_effect = EffectSimpleStat.new()
	hb_effect.target_stat = "roll_mod"
	hb_effect.value = 1
	hot_bounce.effects.append(hb_effect)
	_register(hot_bounce)
	
	# === LUCKY BOUNCE (1) ===
	var lucky_bounce = CardData.create("lucky_bounce", "Lucky Bounce", CardData.Rarity.RARE)
	lucky_bounce.card_type = CardData.CardType.SHOT
	lucky_bounce.description = "Roll +1 tile; draw another modifier card (rolling)."
	lucky_bounce.flavor_text = "Can stack with other modifiers for wild outcomes."
	lucky_bounce.tags = ["roll", "special"]
	
	var lb_effect = EffectSimpleStat.new()
	lb_effect.target_stat = "roll_mod"
	lb_effect.value = 1
	lucky_bounce.effects.append(lb_effect)
	# TODO: Implement "Draw another modifier" effect
	_register(lucky_bounce)
	
	# === CLUTCH FINISH (1) ===
	var clutch_finish = CardData.create("clutch_finish", "Clutch Finish", CardData.Rarity.RARE)
	clutch_finish.card_type = CardData.CardType.SHOT
	clutch_finish.description = "+1 score multiplier."
	clutch_finish.flavor_text = "Only if ball ends on green or in hole this shot."
	clutch_finish.tags = ["scoring"]
	
	var cf_effect = EffectMultBonus.new()
	cf_effect.bonus_mult = 1.0
	# Trigger condition: OnGreen (5) or OnHole (not in enum, but OnGreen usually covers it or we need logic)
	# Assuming OnGreen covers it for now
	cf_effect.trigger_condition = 5 # OnGreen
	clutch_finish.effects.append(cf_effect)
	_register(clutch_finish)


func _register_common_cards() -> void:
	# === LONG DRIVER ===
	var long_driver = CardData.create("long_driver", "Long Driver", CardData.Rarity.COMMON)
	long_driver.card_type = CardData.CardType.SHOT
	long_driver.description = "Rewards long distance shots."
	long_driver.tags = ["drive", "distance"]
	
	var ld_effect = EffectDistanceBonus.new()
	ld_effect.distance_mode = 1  # LongShot
	ld_effect.threshold_distance = 8.0
	ld_effect.flat_bonus_chips = 20
	ld_effect.flat_bonus_mult = 0.5
	long_driver.effects.append(ld_effect)
	_register(long_driver)
	
	# === DISTANCE TRACKER ===
	var dist_tracker = CardData.create("distance_tracker", "Distance Tracker", CardData.Rarity.COMMON)
	dist_tracker.card_type = CardData.CardType.PASSIVE
	dist_tracker.description = "Earn chips for every cell traveled."
	dist_tracker.tags = ["distance", "passive"]
	
	var dt_effect = EffectDistanceBonus.new()
	dt_effect.distance_mode = 0  # PerCell
	dt_effect.chips_per_unit = 2.0
	dist_tracker.effects.append(dt_effect)
	_register(dist_tracker)
	
	# === SAND WEDGE ===
	var sand_wedge = CardData.create("sand_wedge", "Sand Wedge", CardData.Rarity.COMMON)
	sand_wedge.card_type = CardData.CardType.SHOT
	sand_wedge.description = "Bonus when escaping from bunkers."
	sand_wedge.tags = ["bunker", "sand"]
	
	var sw_effect = EffectTerrainBonus.new()
	sw_effect.target_terrain = "Bunker"
	sw_effect.terrain_is_start = true  # Bonus for starting in bunker
	sw_effect.bonus_chips = 25
	sw_effect.bonus_mult = 1.0
	sand_wedge.effects.append(sw_effect)
	_register(sand_wedge)
	
	# === WIDE ANGLE ===
	var wide_angle = CardData.create("wide_angle", "Wide Angle", CardData.Rarity.COMMON)
	wide_angle.card_type = CardData.CardType.SHOT
	wide_angle.description = "Expands the landing zone."
	wide_angle.tags = ["aoe", "utility"]
	
	var wa_effect = EffectAOEExpand.new()
	wa_effect.radius_bonus = 1
	wide_angle.effects.append(wa_effect)
	_register(wide_angle)


func _register_uncommon_cards() -> void:
	# === TRICK SHOT ===
	var trick_shot = CardData.create("trick_shot", "Trick Shot", CardData.Rarity.UNCOMMON)
	trick_shot.card_type = CardData.CardType.SHOT
	trick_shot.description = "Earn bonuses for each bounce."
	trick_shot.tags = ["bounce", "trick"]
	
	var ts_effect = EffectBounceBonus.new()
	ts_effect.chips_per_bounce = 10
	ts_effect.mult_per_bounce = 0.3
	trick_shot.effects.append(ts_effect)
	_register(trick_shot)
	
	# === HOOK SHOT ===
	var hook_shot = CardData.create("hook_shot", "Hook Shot", CardData.Rarity.UNCOMMON)
	hook_shot.card_type = CardData.CardType.SHOT
	hook_shot.description = "Ball curves left after initial flight."
	hook_shot.tags = ["curve", "hook"]
	
	var hs_effect = EffectCurveShot.new()
	hs_effect.curve_direction = 0  # Left
	hs_effect.curve_strength = 0.4
	hs_effect.bonus_on_curve_land = 15
	hook_shot.effects.append(hs_effect)
	_register(hook_shot)
	
	# === SLICE SHOT ===
	var slice_shot = CardData.create("slice_shot", "Slice Shot", CardData.Rarity.UNCOMMON)
	slice_shot.card_type = CardData.CardType.SHOT
	slice_shot.description = "Ball curves right after initial flight."
	slice_shot.tags = ["curve", "slice"]
	
	var ss_effect = EffectCurveShot.new()
	ss_effect.curve_direction = 1  # Right
	ss_effect.curve_strength = 0.4
	ss_effect.bonus_on_curve_land = 15
	slice_shot.effects.append(ss_effect)
	_register(slice_shot)
	
	# === ROLL MASTER ===
	var roll_master = CardData.create("roll_master", "Roll Master", CardData.Rarity.UNCOMMON)
	roll_master.card_type = CardData.CardType.PASSIVE
	roll_master.description = "Ball rolls further after landing."
	roll_master.tags = ["roll", "passive"]
	
	var rm_effect = EffectRollModifier.new()
	rm_effect.roll_distance_modifier = 1.75
	rm_effect.friction_modifier = 0.7
	rm_effect.bonus_chips_on_roll_stop = 5
	roll_master.effects.append(rm_effect)
	_register(roll_master)
	
	# === GREEN READER ===
	var green_reader = CardData.create("green_reader", "Green Reader", CardData.Rarity.UNCOMMON)
	green_reader.card_type = CardData.CardType.PASSIVE
	green_reader.description = "Big bonus when landing on the green."
	green_reader.tags = ["green", "putting"]
	
	var gr_effect = EffectTerrainBonus.new()
	gr_effect.target_terrain = "Green"
	gr_effect.bonus_chips = 20
	gr_effect.bonus_mult = 1.5
	green_reader.effects.append(gr_effect)
	_register(green_reader)
	
	# === COMBO BUILDER ===
	var combo_builder = CardData.create("combo_builder", "Combo Builder", CardData.Rarity.UNCOMMON)
	combo_builder.card_type = CardData.CardType.SHOT
	combo_builder.description = "+5 Chips and +0.2 Mult. Simple but effective."
	combo_builder.tags = ["combo", "balanced"]
	
	var cb_chips = EffectChipsBonus.new()
	cb_chips.bonus_chips = 5
	combo_builder.effects.append(cb_chips)
	
	var cb_mult = EffectMultBonus.new()
	cb_mult.bonus_mult = 0.2
	combo_builder.effects.append(cb_mult)
	_register(combo_builder)


func _register_rare_cards() -> void:
	# === EAGLE EYE ===
	var eagle_eye = CardData.create("eagle_eye", "Eagle Eye", CardData.Rarity.RARE)
	eagle_eye.card_type = CardData.CardType.PASSIVE
	eagle_eye.description = "Massive bonus for precision short shots."
	eagle_eye.flavor_text = "\"See the line, be the ball.\""
	eagle_eye.tags = ["precision", "putting"]
	
	var ee_effect = EffectDistanceBonus.new()
	ee_effect.distance_mode = 2  # ShortShot
	ee_effect.threshold_distance = 2.0
	ee_effect.flat_bonus_chips = 50
	ee_effect.flat_bonus_mult = 2.0
	eagle_eye.effects.append(ee_effect)
	_register(eagle_eye)
	
	# === BANK SHOT PRO ===
	var bank_shot = CardData.create("bank_shot_pro", "Bank Shot Pro", CardData.Rarity.RARE)
	bank_shot.card_type = CardData.CardType.SHOT
	bank_shot.description = "Huge rewards for bounce shots."
	bank_shot.flavor_text = "\"Geometry is my co-pilot.\""
	bank_shot.tags = ["bounce", "trick"]
	
	var bs_bounce = EffectBounceBonus.new()
	bs_bounce.chips_per_bounce = 20
	bs_bounce.mult_per_bounce = 0.5
	bs_bounce.max_bonus_bounces = 8
	bank_shot.effects.append(bs_bounce)
	_register(bank_shot)
	
	# === PRESSURE PLAYER ===
	var pressure = CardData.create("pressure_player", "Pressure Player", CardData.Rarity.RARE)
	pressure.card_type = CardData.CardType.JOKER
	pressure.description = "+3 Mult. Jokers are always active!"
	pressure.flavor_text = "\"I live for the clutch.\""
	pressure.tags = ["joker", "mult"]
	
	var pp_mult = EffectMultBonus.new()
	pp_mult.bonus_mult = 3.0
	pressure.effects.append(pp_mult)
	_register(pressure)
	
	# === WIDE BERTH ===
	var wide_berth = CardData.create("wide_berth", "Wide Berth", CardData.Rarity.RARE)
	wide_berth.card_type = CardData.CardType.PASSIVE
	wide_berth.description = "Greatly expands landing zone."
	wide_berth.tags = ["aoe", "utility"]
	
	var wb_aoe = EffectAOEExpand.new()
	wb_aoe.radius_bonus = 2
	wide_berth.effects.append(wb_aoe)
	_register(wide_berth)


func _register_legendary_cards() -> void:
	# === ACE IN THE HOLE ===
	var ace = CardData.create("ace_in_hole", "Ace in the Hole", CardData.Rarity.LEGENDARY)
	ace.card_type = CardData.CardType.SHOT
	ace.description = "Incredible scoring potential on perfect shots."
	ace.flavor_text = "\"One shot. One legend.\""
	ace.tags = ["legendary", "precision"]
	
	# Multiple synergistic effects
	var ace_short = EffectDistanceBonus.new()
	ace_short.distance_mode = 2  # ShortShot
	ace_short.threshold_distance = 1.5
	ace_short.flat_bonus_chips = 100
	ace_short.flat_bonus_mult = 5.0
	ace.effects.append(ace_short)
	
	var ace_green = EffectTerrainBonus.new()
	ace_green.target_terrain = "Green"
	ace_green.bonus_chips = 50
	ace_green.bonus_mult = 2.0
	ace.effects.append(ace_green)
	_register(ace)
	
	# === CHAOS DRIVER ===
	var chaos = CardData.create("chaos_driver", "Chaos Driver", CardData.Rarity.LEGENDARY)
	chaos.card_type = CardData.CardType.SHOT
	chaos.description = "Random curve, huge AOE, big rewards."
	chaos.flavor_text = "\"Let chaos reign.\""
	chaos.tags = ["legendary", "chaos", "curve"]
	
	var chaos_curve = EffectCurveShot.new()
	chaos_curve.curve_direction = 2  # Random
	chaos_curve.curve_strength = 0.6
	chaos_curve.bonus_on_curve_land = 40
	chaos.effects.append(chaos_curve)
	
	var chaos_aoe = EffectAOEExpand.new()
	chaos_aoe.radius_bonus = 3
	chaos.effects.append(chaos_aoe)
	
	var chaos_chips = EffectChipsBonus.new()
	chaos_chips.bonus_chips = 30
	chaos.effects.append(chaos_chips)
	_register(chaos)
	
	# === THE MULLIGAN ===
	var mulligan = CardData.create("the_mulligan", "The Mulligan", CardData.Rarity.LEGENDARY)
	mulligan.card_type = CardData.CardType.JOKER
	mulligan.description = "+50 Chips, +2 Mult on every shot."
	mulligan.flavor_text = "\"Everyone deserves a second chance.\""
	mulligan.tags = ["legendary", "joker"]
	
	var mull_chips = EffectChipsBonus.new()
	mull_chips.bonus_chips = 50
	mulligan.effects.append(mull_chips)
	
	var mull_mult = EffectMultBonus.new()
	mull_mult.bonus_mult = 2.0
	mulligan.effects.append(mull_mult)
	_register(mulligan)


func _register_consumables() -> void:
	# === LUCKY BALL ===
	var lucky_ball = CardData.create("lucky_ball", "Lucky Ball", CardData.Rarity.UNCOMMON)
	lucky_ball.card_type = CardData.CardType.CONSUMABLE
	lucky_ball.description = "One-time +3 Mult boost."
	lucky_ball.max_uses = 1
	lucky_ball.tags = ["consumable", "mult"]
	
	var lb_mult = EffectMultBonus.new()
	lb_mult.bonus_mult = 3.0
	lucky_ball.effects.append(lb_mult)
	_register(lucky_ball)
	
	# === CHIP SHOT ===
	var chip_shot = CardData.create("chip_shot_consumable", "Chip Shot", CardData.Rarity.COMMON)
	chip_shot.card_type = CardData.CardType.CONSUMABLE
	chip_shot.description = "One-time +40 Chips."
	chip_shot.max_uses = 1
	chip_shot.tags = ["consumable", "chips"]
	
	var cs_chips = EffectChipsBonus.new()
	cs_chips.bonus_chips = 40
	chip_shot.effects.append(cs_chips)
	_register(chip_shot)

#endregion


#region Public API

func _register(card_data: CardData) -> void:
	_cards[card_data.card_id] = card_data


func get_card(card_id: String) -> CardData:
	return _cards.get(card_id)


func get_all_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	for card in _cards.values():
		result.append(card)
	return result


func get_cards_by_rarity(rarity: CardData.Rarity) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in _cards.values():
		if card.rarity == rarity:
			result.append(card)
	return result


func get_cards_by_type(card_type: CardData.CardType) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in _cards.values():
		if card.card_type == card_type:
			result.append(card)
	return result


func get_cards_by_tag(tag: String) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in _cards.values():
		if card.has_tag(tag):
			result.append(card)
	return result


func create_instance(card_id: String) -> CardInstance:
	var data = get_card(card_id)
	if data:
		return CardInstance.new(data)
	return null


func get_club_deck() -> Array[CardInstance]:
	"""Return a full set of club cards"""
	var deck: Array[CardInstance] = []
	var club_ids = [
		"club_driver", "club_3wood", "club_5wood", 
		"club_3iron", "club_5iron", "club_6iron", 
		"club_7iron", "club_8iron", "club_9iron", 
		"club_pw", "club_sw", "club_putter"
	]
	
	for id in club_ids:
		var data = get_card(id)
		if data:
			deck.append(CardInstance.create_from_data(data))
			
	return deck


func get_starter_deck() -> Array[CardInstance]:
	## Returns the default starter deck for a new run
	var deck: Array[CardInstance] = []
	
	# Clean Strike (4)
	for i in 4: deck.append(create_instance("clean_strike"))
	
	# Controlled Aim (2)
	for i in 2: deck.append(create_instance("controlled_aim"))
	
	# Slightly Short (3)
	for i in 3: deck.append(create_instance("slightly_short"))
	
	# Way Short (1)
	deck.append(create_instance("way_short"))
	
	# Solid Contact (1)
	deck.append(create_instance("solid_contact"))
	
	# Crushed It (1)
	deck.append(create_instance("crushed_it"))
	
	# Shank (2)
	for i in 2: deck.append(create_instance("shank"))
	
	# Wild Push (1)
	deck.append(create_instance("wild_push"))
	
	# Laser Line (1)
	deck.append(create_instance("laser_line"))
	
	# Heavy Spin (1)
	deck.append(create_instance("heavy_spin"))
	
	# Hot Bounce (1)
	deck.append(create_instance("hot_bounce"))
	
	# Lucky Bounce (1)
	deck.append(create_instance("lucky_bounce"))
	
	# Clutch Finish (1)
	deck.append(create_instance("clutch_finish"))
	
	return deck


func get_random_card(rarity: CardData.Rarity = CardData.Rarity.COMMON) -> CardData:
	var pool = get_cards_by_rarity(rarity)
	if pool.size() > 0:
		return pool[randi() % pool.size()]
	return null


func get_random_card_weighted() -> CardData:
	## Returns a random card with rarity-based weighting
	## Common: 60%, Uncommon: 25%, Rare: 12%, Legendary: 3%
	var roll = randf()
	var rarity: CardData.Rarity
	
	if roll < 0.60:
		rarity = CardData.Rarity.COMMON
	elif roll < 0.85:
		rarity = CardData.Rarity.UNCOMMON
	elif roll < 0.97:
		rarity = CardData.Rarity.RARE
	else:
		rarity = CardData.Rarity.LEGENDARY
	
	return get_random_card(rarity)

#endregion
