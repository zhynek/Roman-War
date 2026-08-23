class_name CampaignRng
extends RefCounted
## Single deterministic randomness source for the whole campaign. Its internal
## state is persisted inside the GameState dict ("rng_state"), so a saved game
## replays identically. No engine code may use randi()/randf() directly.

var _rng := RandomNumberGenerator.new()


static func seeded(seed_value: int) -> CampaignRng:
	var rng := CampaignRng.new()
	rng._rng.seed = seed_value
	return rng


func randf() -> float:
	return _rng.randf()


func randf_pct(spread: float) -> float:
	## Uniform multiplier in [1 - spread/100, 1 + spread/100].
	return 1.0 + (_rng.randf() * 2.0 - 1.0) * spread / 100.0


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func chance(probability: float) -> bool:
	return _rng.randf() < probability


func pick(list: Array) -> Variant:
	return list[_rng.randi_range(0, list.size() - 1)]


func get_state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value


func state_string() -> String:
	## RNG state is a full 64-bit integer; JSON numbers are float64 and would
	## silently round it. It therefore travels through GameState as a string.
	return str(_rng.state)


static func from_state_string(value: String) -> CampaignRng:
	var rng := CampaignRng.new()
	rng._rng.state = value.to_int()
	return rng
