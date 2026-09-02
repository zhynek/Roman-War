class_name AutoResolver
extends BattleResolver
## Statistical battle resolver. Strengths come from the shared, RNG-free
## BattleResolver.estimate() (numbers x quality x kit x experience, unit-class
## matchups against the enemy's composition, per-class terrain and walls,
## generals, doctrines, combined arms, fatigue); this class adds the fortune
## rolls, casualties, experience and the general's fate. Deliberately a paper
## model — a real-time battle scene replaces it behind the same interface.


func resolve(data: GameData, rng: CampaignRng, attacker_units: Array, defender_units: Array, context: Dictionary) -> Dictionary:
	var battle_rules: Dictionary = data.balance["battle"]
	var estimate := BattleResolver.estimate(data, attacker_units, defender_units, context)

	var randomness := float(battle_rules["randomness_pct"])
	var attacker_fortune := rng.randf_pct(randomness)
	var defender_fortune := rng.randf_pct(randomness)
	var attacker_strength: float = estimate["attacker"]["strength"] * attacker_fortune
	var defender_strength: float = estimate["defender"]["strength"] * defender_fortune

	var attacker_won := attacker_strength > defender_strength
	var ratio := 1.0
	if attacker_strength > 0.0 and defender_strength > 0.0:
		ratio = attacker_strength / defender_strength

	var attacker_casualties := float(battle_rules["attacker_casualty_base_pct"]) / maxf(ratio, 0.35)
	var defender_casualties := float(battle_rules["defender_casualty_base_pct"]) * maxf(ratio, 0.35)
	if attacker_won:
		defender_casualties += float(battle_rules["loser_extra_casualty_pct"])
	else:
		attacker_casualties += float(battle_rules["loser_extra_casualty_pct"])
	var casualty_min := float(battle_rules["casualty_min_pct"])
	var casualty_max := float(battle_rules["casualty_max_pct"])
	attacker_casualties = clampf(attacker_casualties, casualty_min, casualty_max)
	defender_casualties = clampf(defender_casualties, casualty_min, casualty_max)

	var scatter := float(battle_rules["unit_casualty_scatter_pct"])
	_apply_casualties(attacker_units, attacker_casualties, scatter, rng)
	_apply_casualties(defender_units, defender_casualties, scatter, rng)

	var experience_gain := int(battle_rules["experience_gain_on_victory"])
	var experience_max := int(data.balance["recruitment"]["experience_max"])
	var winners := attacker_units if attacker_won else defender_units
	for unit in winners:
		unit["experience"] = mini(int(unit["experience"]) + experience_gain, experience_max)

	var general_death_chance := float(battle_rules["general_death_chance_on_defeat"])
	var attacker_general_died: bool = (not attacker_won) \
		and context.get("attacker_general") != null and rng.chance(general_death_chance)
	var defender_general_died: bool = attacker_won \
		and context.get("defender_general") != null and rng.chance(general_death_chance)

	return {
		"winner": "attacker" if attacker_won else "defender",
		"attacker_casualty_pct": attacker_casualties,
		"defender_casualty_pct": defender_casualties,
		"attacker_general_died": attacker_general_died,
		"defender_general_died": defender_general_died,
		"experience_gained": experience_gain,
		"breakdown": {
			"attacker": estimate["attacker"],
			"defender": estimate["defender"],
			"ratio": estimate["ratio"],
			"fortune": {"attacker": attacker_fortune, "defender": defender_fortune},
		},
	}


func _apply_casualties(units: Array, casualty_pct: float, scatter_pct: float, rng: CampaignRng) -> void:
	for i in range(units.size() - 1, -1, -1):
		var unit: Dictionary = units[i]
		var unit_casualties := casualty_pct * rng.randf_pct(scatter_pct)
		var remaining := int(round(float(unit["strength_pct"]) * (1.0 - unit_casualties / 100.0)))
		if remaining < 10:
			units.remove_at(i)
		else:
			unit["strength_pct"] = remaining
