class_name AutoResolver
extends BattleResolver
## Statistical battle estimator: strengths from numbers x stats x experience,
## modified by terrain, walls, generals, and fatigue, with bounded randomness.
## Deliberately conservative — the future real-time resolver replaces this
## behind the same interface.
##
## Besides the single-shot outcome it returns a synthesized round log — the
## same battle told as phases, for playback. The log is derived entirely from
## quantities already computed: it draws NOTHING from the RNG, so a campaign
## with playback replays byte-identically to one without.

## The narrative arc of every auto-resolved battle, in order. Structural, like
## the result's key names — the per-phase numbers live in balance.json.
const ROUND_PHASES: Array[String] = ["skirmish", "charge", "melee", "break", "pursuit"]


func resolve(data: GameData, rng: CampaignRng, attacker_units: Array, defender_units: Array, context: Dictionary) -> Dictionary:
	var battle_rules: Dictionary = data.balance["battle"]
	var experience_pct := float(battle_rules["experience_strength_pct_per_chevron"])

	var attacker_strength := BattleResolver.force_strength(
		data, attacker_units, context.get("attacker_general"), experience_pct)
	var defender_strength := BattleResolver.force_strength(
		data, defender_units, context.get("defender_general"), experience_pct)

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
	var attacker_report := _apply_casualties(attacker_units, attacker_casualties, scatter, rng)
	var defender_report := _apply_casualties(defender_units, defender_casualties, scatter, rng)

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
		"rounds": _round_log(battle_rules, attacker_won, ratio,
			attacker_casualties, defender_casualties),
		"attacker_report": attacker_report,
		"defender_report": defender_report,
	}


func _apply_casualties(units: Array, casualty_pct: float, scatter_pct: float, rng: CampaignRng) -> Array:
	## Mutates the force in place as ever — the draw order (reverse index) is
	## load-bearing for replay compatibility — and reports each unit's fate in
	## the array's forward order, for the battle playback.
	var report: Array = []
	for i in range(units.size() - 1, -1, -1):
		var unit: Dictionary = units[i]
		var unit_casualties := casualty_pct * rng.randf_pct(scatter_pct)
		var remaining := int(round(float(unit["strength_pct"]) * (1.0 - unit_casualties / 100.0)))
		var destroyed := remaining < 10
		report.append({
			"template": String(unit["template"]),
			"strength_before": int(unit["strength_pct"]),
			"strength_after": 0 if destroyed else remaining,
			"destroyed": destroyed,
		})
		if destroyed:
			units.remove_at(i)
		else:
			unit["strength_pct"] = remaining
	report.reverse()
	return report


func _round_log(battle_rules: Dictionary, attacker_won: bool, ratio: float,
		attacker_casualties: float, defender_casualties: float) -> Array:
	## The battle retold as ROUND_PHASES, synthesized after the fact from the
	## quantities already computed — never an extra die. Each side's phase
	## casualties sum exactly to its single-shot total (the last phase takes
	## the remainder, absorbing float drift); the loser's morale walks its
	## balance-data track to zero and the round it zeroes carries the break.
	var winner_shares: Array = battle_rules["round_winner_casualty_shares"]
	var loser_shares: Array = battle_rules["round_loser_casualty_shares"]
	var loser_track: Array = battle_rules["round_loser_morale_track"]
	var winner_progress: Array = battle_rules["round_winner_morale_progress"]

	# How lopsided the field was decides how shaken the winner ends: a
	# near-run thing leaves them at the floor, a walkover near the ceiling.
	var advantage := maxf(ratio, 1.0 / maxf(ratio, 0.001))
	var winner_end := lerpf(float(battle_rules["round_winner_morale_min"]),
		float(battle_rules["round_winner_morale_max"]), 1.0 - 1.0 / advantage)

	var attacker_shares := winner_shares if attacker_won else loser_shares
	var defender_shares := loser_shares if attacker_won else winner_shares
	var break_round := ROUND_PHASES.find("break")
	var rounds: Array = []
	var attacker_spent := 0.0
	var defender_spent := 0.0
	for i in range(ROUND_PHASES.size()):
		var attacker_round := attacker_casualties * float(attacker_shares[i])
		var defender_round := defender_casualties * float(defender_shares[i])
		if i == ROUND_PHASES.size() - 1:
			attacker_round = attacker_casualties - attacker_spent
			defender_round = defender_casualties - defender_spent
		attacker_spent += attacker_round
		defender_spent += defender_round
		var winner_morale := 100.0 - (100.0 - winner_end) * float(winner_progress[i])
		var loser_morale := float(loser_track[i])
		rounds.append({
			"phase": ROUND_PHASES[i],
			"attacker_casualty_pct": attacker_round,
			"defender_casualty_pct": defender_round,
			"attacker_morale": winner_morale if attacker_won else loser_morale,
			"defender_morale": loser_morale if attacker_won else winner_morale,
			"breaking": ("defender" if attacker_won else "attacker") if i == break_round else "",
		})
	return rounds
