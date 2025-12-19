extends Node
class_name TempoManager

## TempoManager - Manages the Tempo resource for playing swing cards
## Tempo grows each shot: Shot 1 = 2, Shot 2 = 3, Shot 3 = 4, etc. (Marvel Snap pattern)

signal tempo_changed(current: int, max_tempo: int)
signal tempo_spent(amount: int, remaining: int)
signal tempo_insufficient(required: int, available: int)

# Base tempo starts at 2 for shot 1
const BASE_TEMPO: int = 2

# Current shot number (1-indexed)
var current_shot: int = 1

# Tempo for this shot
var max_tempo: int = BASE_TEMPO
var current_tempo: int = BASE_TEMPO


func _ready() -> void:
	reset_for_shot(1)


func reset_for_shot(shot_number: int) -> void:
	"""Reset tempo for a new shot. Tempo = BASE_TEMPO + (shot_number - 1)"""
	current_shot = shot_number
	max_tempo = BASE_TEMPO + (shot_number - 1)
	current_tempo = max_tempo
	tempo_changed.emit(current_tempo, max_tempo)
	print("[TempoManager] Shot %d: Tempo = %d" % [shot_number, max_tempo])


func reset_for_hole() -> void:
	"""Reset tempo at the start of a new hole"""
	reset_for_shot(1)


func can_afford(cost: int) -> bool:
	"""Check if we have enough tempo to play a card"""
	return current_tempo >= cost


func spend_tempo(cost: int) -> bool:
	"""Spend tempo to play a card. Returns false if insufficient tempo."""
	if cost <= 0:
		return true
	
	if current_tempo < cost:
		tempo_insufficient.emit(cost, current_tempo)
		return false
	
	current_tempo -= cost
	tempo_spent.emit(cost, current_tempo)
	tempo_changed.emit(current_tempo, max_tempo)
	print("[TempoManager] Spent %d tempo, %d remaining" % [cost, current_tempo])
	return true


func refund_tempo(amount: int) -> void:
	"""Refund tempo (e.g., if card play is cancelled)"""
	current_tempo = min(current_tempo + amount, max_tempo)
	tempo_changed.emit(current_tempo, max_tempo)


func get_current_tempo() -> int:
	return current_tempo


func get_max_tempo() -> int:
	return max_tempo


func get_shot_number() -> int:
	return current_shot


func advance_shot() -> void:
	"""Move to next shot (increases available tempo)"""
	reset_for_shot(current_shot + 1)
