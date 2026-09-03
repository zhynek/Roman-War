class_name AutoResolver
extends BattleResolver
## Statistical battle resolver. Strengths come from the shared, RNG-free
## BattleResolver.estimate() (numbers x class mass x quality x kit x
## experience, unit-class matchups against the enemy's composition, per-class
## terrain and walls, generals, martial ethos, practiced warcraft, combined
## arms, fatigue); this class adds the fortune rolls, casualties, the rout,
## experience and the general's fate.
##
## Casualties come in two parts. The MELEE part is set by the strength ratio
## and shared out so that units the enemy countered bleed more than the side's
## mean and units that countered him bleed less (soldier-normalised, so the
## side's mean melee loss is the melee pool). The ROUT part falls on the loser
## only: most of an ancient battle's dead fell in the pursuit, so it scales
## with the winner's pursuit (his fast units) and is reduced for each losing
## unit by its escape factor (its own speed). Reported casualty percentages
## are the men actually lost. Deliberately a paper model — a real-time battle
## scene replaces it behind the same interface.
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
	var estimate := BattleResolver.estimate(data, attacker_units, defender_units, context)
	var attacker_before := ArmyRules.soldiers(data, attacker_units)
	var defender_before := ArmyRules.soldiers(data, defender_units)

	# No enemy in the field: walk in. Nothing is rolled, lost or learned.
	if bool(estimate.get("walkover", false)):
		var attacker_stands: bool = float(estimate["attacker"]["strength"]) > 0.0
		return {
			"winner": "attacker" if attacker_stands else "defender",
			"attacker_casualty_pct": 0.0,
			"defender_casualty_pct": 0.0,
			"attacker_general_died": false,
			"defender_general_died": false,
			"experience_gained": 0,
			"attacker_destroyed": attacker_units.is_empty(),
			"defender_destroyed": defender_units.is_empty(),
			"walkover": true,
			"breakdown": {
				"attacker": estimate["attacker"], "defender": estimate["defender"],
				"ratio": estimate["ratio"], "fortune": {"attacker": 1.0, "defender": 1.0},
			},
			"rounds": [],
			"attacker_report": _unharmed_report(attacker_units),
			"defender_report": _unharmed_report(defender_units),
		}

	# Fortune: two draws, attacker first (the order every save replays).
	var randomness := float(battle_rules["randomness_pct"])
	var attacker_fortune := rng.randf_pct(randomness)
	var defender_fortune := rng.randf_pct(randomness)
	var attacker_strength: float = estimate["attacker"]["strength"] * attacker_fortune
	var defender_strength: float = estimate["defender"]["strength"] * defender_fortune

	var attacker_won := attacker_strength > defender_strength
	var ratio := 1.0
	if attacker_strength > 0.0 and defender_strength > 0.0:
		ratio = attacker_strength / defender_strength

	# Melee pools from the ratio (floored so a rout is not free), clamped as a whole.
	var casualty_min := float(battle_rules["casualty_min_pct"])
	var casualty_max := float(battle_rules["casualty_max_pct"])
	var ratio_floor := float(battle_rules["melee_ratio_floor"])
	var attacker_melee := clampf(float(battle_rules["attacker_casualty_base_pct"]) / maxf(ratio, ratio_floor), casualty_min, casualty_max)
	var defender_melee := clampf(float(battle_rules["defender_casualty_base_pct"]) * maxf(ratio, ratio_floor), casualty_min, casualty_max)

	# The rout: the loser's extra losses, driven by how fast the winner can chase.
	var winner_estimate: Dictionary = estimate["attacker"] if attacker_won else estimate["defender"]
	var rout := rout_pct(battle_rules, float(winner_estimate["pursuit"]))

	var attacker_report := distribute_casualties(attacker_units, estimate["attacker"], attacker_melee,
		0.0 if attacker_won else rout, battle_rules, rng)
	var defender_report := distribute_casualties(defender_units, estimate["defender"], defender_melee,
		rout if attacker_won else 0.0, battle_rules, rng)

	var attacker_after := ArmyRules.soldiers(data, attacker_units)
	var defender_after := ArmyRules.soldiers(data, defender_units)
	var attacker_casualties := _loss_pct(attacker_before, attacker_after)
	var defender_casualties := _loss_pct(defender_before, defender_after)

	# Experience: the victors learn, and an underdog victory teaches twice.
	var underdog_ratio := float(battle_rules["underdog_strength_ratio"])
	var paper_ratio := float(estimate["ratio"])
	var was_underdog := (paper_ratio * underdog_ratio <= 1.0) if attacker_won else (paper_ratio >= underdog_ratio)
	var experience_gain := int(battle_rules["experience_gain_underdog"]) if was_underdog \
		else int(battle_rules["experience_gain_on_victory"])
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
		"attacker_destroyed": attacker_units.is_empty(),
		"defender_destroyed": defender_units.is_empty(),
		"walkover": false,
		"breakdown": {
			"attacker": estimate["attacker"],
			"defender": estimate["defender"],
			"ratio": estimate["ratio"],
			"fortune": {"attacker": attacker_fortune, "defender": defender_fortune},
		},
		"rounds": _round_log(battle_rules, attacker_won, ratio, attacker_casualties, defender_casualties),
		"attacker_report": attacker_report,
		"defender_report": defender_report,
	}


static func rout_pct(battle_rules: Dictionary, winner_pursuit: float) -> float:
	## The loser's extra casualties before escape: the base rout scaled by how
	## much faster than a marching column the winner's army can pursue.
	var base := float(battle_rules["loser_extra_casualty_pct"])
	return maxf(base * (1.0 + (winner_pursuit - 1.0) * float(battle_rules["pursuit_scale"])), 0.0)


static func distribute_casualties(units: Array, side: Dictionary, melee_pct: float, rout_pct_value: float, battle_rules: Dictionary, rng: CampaignRng) -> Array:
	## Shares a side's melee pool and rout losses over its units (see the class
	## comment), mutating them in place. One scatter draw per unit, iterating
	## from the back so removals are safe — the draw order every save replays.
	## Returns each unit's fate in the array's FORWARD order, for the playback:
	## [{template, strength_before, strength_after, destroyed}].
	var profiles := {}
	for profile in side["units"]:
		profiles[int(profile["index"])] = profile

	# Vulnerability: countered units (matchup < 1) carry more of the melee pool,
	# normalised over soldiers so the side's mean melee loss is melee_pct.
	var exponent := float(battle_rules["casualty_matchup_weight"])
	var weight_min := float(battle_rules["casualty_weight_min"])
	var weight_max := float(battle_rules["casualty_weight_max"])
	var weights: Array = []
	var soldiers_total := 0.0
	var weighted_total := 0.0
	for i in range(units.size()):
		var profile: Dictionary = profiles.get(i, {})
		var matchup := maxf(float(profile.get("matchup", 1.0)), 0.01)
		var weight := clampf(pow(matchup, -exponent), weight_min, weight_max)
		weights.append(weight)
		var soldiers := float(profile.get("soldiers", 0))
		soldiers_total += soldiers
		weighted_total += soldiers * weight
	var normaliser := soldiers_total / weighted_total if weighted_total > 0.0 else 1.0

	var casualty_max := float(battle_rules["casualty_max_pct"])
	var scatter := float(battle_rules["unit_casualty_scatter_pct"])
	var destroyed_below := int(battle_rules["unit_destroyed_below_pct"])
	var report: Array = []
	for i in range(units.size() - 1, -1, -1):
		var unit: Dictionary = units[i]
		var profile: Dictionary = profiles.get(i, {})
		var escape := maxf(float(profile.get("escape", 1.0)), 0.01)
		var loss := (melee_pct * float(weights[i]) * normaliser + rout_pct_value / escape) * rng.randf_pct(scatter)
		loss = clampf(loss, 0.0, casualty_max)
		var remaining := int(round(float(unit["strength_pct"]) * (1.0 - loss / 100.0)))
		var destroyed := remaining < destroyed_below
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
	## the remainder, absorbing float drift). The break is pinned to the
	## phase named "break"; the loser's morale walks its balance-data track,
	## which the validator holds at exactly zero on that phase.
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


static func _unharmed_report(units: Array) -> Array:
	var report: Array = []
	for unit in units:
		report.append({
			"template": String(unit["template"]),
			"strength_before": int(unit["strength_pct"]),
			"strength_after": int(unit["strength_pct"]),
			"destroyed": false,
		})
	return report


static func _loss_pct(before: int, after: int) -> float:
	if before <= 0:
		return 0.0
	return 100.0 * (1.0 - float(after) / float(before))
