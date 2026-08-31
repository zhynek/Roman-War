class_name AutoResolver
extends BattleResolver
## Statistical battle estimator: strengths from numbers x stats x experience,
## modified by terrain, walls, generals, and fatigue, with bounded randomness.
## Deliberately conservative — the future real-time resolver replaces this
## behind the same interface.


func resolve(data: GameData, rng: CampaignRng, attacker_units: Array, defender_units: Array, context: Dictionary) -> Dictionary:
	var battle_rules: Dictionary = data.balance["battle"]
	var experience_pct := float(battle_rules["experience_strength_pct_per_chevron"])

	var attacker_strength := BattleResolver.force_strength(
		data, attacker_units, context.get("attacker_general"), experience_pct)
	var defender_strength := BattleResolver.force_strength(
		data, defender_units, context.get("defender_general"), experience_pct)

	# What a martial society actually buys: men who have drilled since boyhood
	# because that is what their people are for. Everything it costs is paid in
	# SocietyRules — legitimacy, conscription load, and generals with armies.
	var martial_pct := float(battle_rules["martial_ethos_strength_pct_at_full"]) / 100.0
	attacker_strength *= 1.0 + float(context.get("attacker_martial", 0.0)) / 100.0 * martial_pct
	defender_strength *= 1.0 + float(context.get("defender_martial", 0.0)) / 100.0 * martial_pct

	var terrain: String = context.get("terrain", "plains")
	defender_strength *= float(battle_rules["terrain_defense_multiplier"].get(terrain, 1.0))

	var wall_level := int(context.get("wall_level", 0))
	var wall_multipliers: Array = battle_rules["wall_defense_multiplier"]
	defender_strength *= float(wall_multipliers[mini(wall_level, wall_multipliers.size() - 1)])

	if context.get("attacker_fatigued", false):
		attacker_strength *= float(battle_rules["fatigue_multiplier"])
	if context.get("sally", false):
		defender_strength *= 1.0 + float(data.balance["siege"]["sally_strength_bonus_pct"]) / 100.0

	attacker_strength *= rng.randf_pct(float(battle_rules["randomness_pct"]))
	defender_strength *= rng.randf_pct(float(battle_rules["randomness_pct"]))

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
