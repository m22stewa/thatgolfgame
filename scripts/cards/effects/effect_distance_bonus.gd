extends CardEffect
class_name EffectDistanceBonus

## Grants bonus based on shot distance.
## Rewards long drives or precision short shots.

@export_enum("PerCell", "LongShot", "ShortShot") var distance_mode: int = 0
@export var threshold_distance: float = 10.0  # For LongShot/ShortShot modes
@export var chips_per_unit: float = 1.0       # For PerCell mode
@export var flat_bonus_chips: int = 0
@export var flat_bonus_mult: float = 0.0

func _init() -> void:
	effect_id = "distance_bonus"
	effect_name = "Distance Bonus"
	apply_phase = 3  # OnScoring
	trigger_condition = 0  # Always


func apply_on_scoring(context: ShotContext, upgrade_level: int = 0) -> void:
	var distance = context.get_shot_distance()
	
	match distance_mode:
		0:  # PerCell - chips based on distance
			var scaled_per_unit = chips_per_unit + (upgrade_level * 0.5)
			var bonus = int(distance * scaled_per_unit)
			context.chips += bonus
			print("Card Effect: +%d chips (%.1f per cell × %.1f cells)" % [bonus, scaled_per_unit, distance])
		
		1:  # LongShot - bonus if distance exceeds threshold
			if distance >= threshold_distance:
				var scaled_chips = flat_bonus_chips + (upgrade_level * 10)
				var scaled_mult = flat_bonus_mult + (upgrade_level * 0.3)
				
				if scaled_chips > 0:
					context.chips += scaled_chips
				if scaled_mult > 0:
					context.mult += scaled_mult
				
				print("Card Effect: Long Shot! +%d chips, +%.1f mult" % [scaled_chips, scaled_mult])
		
		2:  # ShortShot - bonus if distance is under threshold
			if distance <= threshold_distance:
				var scaled_chips = flat_bonus_chips + (upgrade_level * 10)
				var scaled_mult = flat_bonus_mult + (upgrade_level * 0.3)
				
				if scaled_chips > 0:
					context.chips += scaled_chips
				if scaled_mult > 0:
					context.mult += scaled_mult
				
				print("Card Effect: Precision Shot! +%d chips, +%.1f mult" % [scaled_chips, scaled_mult])


func get_description(upgrade_level: int = 0) -> String:
	match distance_mode:
		0:
			var scaled = chips_per_unit + (upgrade_level * 0.5)
			return "+%.1f Chips per cell traveled" % scaled
		1:
			var sc = flat_bonus_chips + (upgrade_level * 10)
			var sm = flat_bonus_mult + (upgrade_level * 0.3)
			return "If distance ≥ %.0f: +%d Chips, +%.1f Mult" % [threshold_distance, sc, sm]
		2:
			var sc = flat_bonus_chips + (upgrade_level * 10)
			var sm = flat_bonus_mult + (upgrade_level * 0.3)
			return "If distance ≤ %.0f: +%d Chips, +%.1f Mult" % [threshold_distance, sc, sm]
		_:
			return "Distance bonus"
