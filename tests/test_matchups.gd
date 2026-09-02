extends RefCounted
## Unit-class counters, per-class terrain, walls, kit and combined arms as the
## RNG-free estimator sees them — over the REAL data/unit_classes.json table
## (the fixtures load it like balance.json), so these guard the shipped matrix.
## The fixture arms test_pikes / test_horse / test_slingers have equal base mass.


func _army(templates: Array) -> Array:
	var units: Array = []
	for template in templates:
		units.append({"template": template, "experience": 0, "strength_pct": 100})
	return units


func _context(extra: Dictionary = {}) -> Dictionary:
	var context := {"terrain": "plains", "wall_level": 0}
	context.merge(extra, true)
	return context


func _ratio(data: GameData, attackers: Array, defenders: Array, extra: Dictionary = {}) -> float:
	return float(BattleResolver.estimate(data, _army(attackers), _army(defenders), _context(extra))["ratio"])


func _factor(side: Dictionary, label: String) -> float:
	for factor in side["factors"]:
		if factor["label"] == label:
			return float(factor["value"])
	return 1.0


func test_estimate_is_pure(t) -> void:
	var data := Fixtures.data()
	var attackers := _army(["test_horse", "test_pikes"])
	var defenders := _army(["test_slingers"])
	var first := BattleResolver.estimate(data, attackers, defenders, _context())
	var second := BattleResolver.estimate(data, attackers, defenders, _context())
	t.check_eq(JSON.stringify(first), JSON.stringify(second), "same inputs, same estimate")
	t.check_eq(int(attackers[0]["strength_pct"]), 100, "estimating bleeds nobody")
	t.check_eq(attackers[0].keys().size(), 3, "estimating stamps nothing on the unit")
	t.check(float(first["attacker"]["strength"]) > 0.0 and float(first["ratio"]) > 0.0, "strengths are positive")


func test_resolve_reports_the_prefortune_estimate(t) -> void:
	var data := Fixtures.data()
	var resolver := AutoResolver.new()
	var attackers := _army(["test_horse", "test_horse"])
	var defenders := _army(["test_slingers", "test_pikes"])
	var estimate := BattleResolver.estimate(data, attackers, defenders, _context())
	var result := resolver.resolve(data, CampaignRng.seeded(3), attackers.duplicate(true), defenders.duplicate(true), _context())
	t.check_near(float(result["breakdown"]["attacker"]["strength"]), float(estimate["attacker"]["strength"]), 0.0001,
		"breakdown carries the attacker's paper strength")
	t.check_near(float(result["breakdown"]["ratio"]), float(estimate["ratio"]), 0.0001, "and the paper ratio")
	var fortune: Dictionary = result["breakdown"]["fortune"]
	var spread := float(data.balance["battle"]["randomness_pct"]) / 100.0
	t.check(absf(float(fortune["attacker"]) - 1.0) <= spread + 0.000001, "fortune stays inside the spread")


func test_pikes_stop_cavalry_on_plains(t) -> void:
	var data := Fixtures.data()
	t.check(_ratio(data, ["test_horse"], ["test_pikes"]) < 0.7,
		"horse charging a phalanx on the flat is beaten (%.2f)" % _ratio(data, ["test_horse"], ["test_pikes"]))
	t.check(_ratio(data, ["test_pikes"], ["test_horse"]) > 1.4,
		"pikes attacking horse keep the upper hand (%.2f)" % _ratio(data, ["test_pikes"], ["test_horse"]))


func test_cavalry_rides_down_slingers(t) -> void:
	var data := Fixtures.data()
	var ratio := _ratio(data, ["test_horse"], ["test_slingers"])
	t.check(ratio > 1.3, "horse against foot missiles in the open (%.2f)" % ratio)
	t.check(_ratio(data, ["test_slingers"], ["test_pikes"]) > 1.0, "slingers wear down a pike block they can outpace")


func test_rough_ground_blunts_cavalry(t) -> void:
	var data := Fixtures.data()
	var plains := _ratio(data, ["test_horse"], ["test_elites"])
	var forest := _ratio(data, ["test_horse"], ["test_elites"], {"terrain": "forest"})
	var mountains := _ratio(data, ["test_horse"], ["test_elites"], {"terrain": "mountains"})
	t.check(plains > 1.0, "on the plain the horse have the edge over sword infantry (%.2f)" % plains)
	t.check(forest < plains and forest < 1.0, "under the trees the same charge fails (%.2f)" % forest)
	t.check(mountains < forest, "and in the mountains it fails worse (%.2f)" % mountains)
	var estimate := BattleResolver.estimate(data, _army(["test_horse"]), _army(["test_elites"]), _context({"terrain": "forest"}))
	t.check(_factor(estimate["attacker"], "class_terrain") < 1.0, "the class-terrain factor names the cause")
	t.check(_factor(estimate["defender"], "terrain") > 1.0, "the defender's ground bonus still applies on top")


func test_cavalry_is_useless_in_an_assault(t) -> void:
	var data := Fixtures.data()
	var walls := _context({"wall_level": 2})
	var horse := BattleResolver.estimate(data, _army(["test_horse"]), _army(["test_spears"]), walls)
	var foot := BattleResolver.estimate(data, _army(["test_elites"]), _army(["test_spears"]), walls)
	t.check(_factor(horse["attacker"], "assault") < _factor(foot["attacker"], "assault"),
		"horse storm walls far worse than infantry (%.2f vs %.2f)" % [_factor(horse["attacker"], "assault"), _factor(foot["attacker"], "assault")])
	t.check(_factor(horse["defender"], "wall_defense") > 1.0, "spearmen fight better from a wall")
	var field := _ratio(data, ["test_horse"], ["test_spears"])
	var assault := float(horse["ratio"])
	t.check(assault < field * 0.5, "walls plus the class penalty gut a mounted assault (%.2f -> %.2f)" % [field, assault])


func test_upgrades_raise_strength(t) -> void:
	var data := Fixtures.data()
	var plain := _army(["test_spears"])
	var armed := _army(["test_spears"])
	armed[0]["weapon"] = 2
	armed[0]["armor"] = 1
	var estimate := BattleResolver.estimate(data, armed, plain, _context())
	t.check(_factor(estimate["attacker"], "upgrades") > 1.1, "two weapon and one armour level show as a kit factor")
	t.check(float(estimate["ratio"]) > 1.15, "and win the mirror match on paper (%.2f)" % float(estimate["ratio"]))
	t.check_near(_factor(estimate["defender"], "upgrades"), 1.0, 0.000001, "unarmed side lists no kit factor")


func test_phalanx_attribute_applies(t) -> void:
	var data := Fixtures.data()
	var plain_pikes: Dictionary = data.units["test_pikes"].duplicate(true)
	plain_pikes["id"] = "test_pikes_plain"
	plain_pikes.erase("attributes")
	data.units["test_pikes_plain"] = plain_pikes
	var against_phalanx := _ratio(data, ["test_horse"], ["test_pikes"])
	var against_plain := _ratio(data, ["test_horse"], ["test_pikes_plain"])
	t.check(against_phalanx < against_plain, "the phalanx attribute stiffens the pike front against horse")
	var hills_phalanx := _ratio(data, ["test_elites"], ["test_pikes"], {"terrain": "hills"})
	var hills_plain := _ratio(data, ["test_elites"], ["test_pikes_plain"], {"terrain": "hills"})
	t.check(hills_phalanx > hills_plain, "and costs the block its order on the hills")


func test_combined_arms_bonus(t) -> void:
	var data := Fixtures.data()
	var mixed := BattleResolver.estimate(data, _army(["test_elites", "test_horse", "test_slingers"]), _army(["test_spears"]), _context())
	var single := BattleResolver.estimate(data, _army(["test_elites", "test_elites", "test_elites"]), _army(["test_spears"]), _context())
	var bonus := 1.0 + float(data.balance["battle"]["combined_arms_bonus_pct"]) / 100.0
	t.check_near(_factor(mixed["attacker"], "combined_arms"), bonus, 0.000001, "line + shock + missiles fight together")
	t.check_near(_factor(single["attacker"], "combined_arms"), 1.0, 0.000001, "an all-sword stack does not")
	t.check_eq(mixed["attacker"]["rows"].size(), 3, "one row per class")


func test_win_chance_is_monotonic(t) -> void:
	var spread := 15.0
	var even := BattleResolver.win_chance(1.0, 1.0, spread)
	t.check_near(even, 0.5, 0.01, "even odds are a coin flip")
	t.check(BattleResolver.win_chance(0.8, 1.0, spread) < even, "the weaker side is the underdog")
	t.check(BattleResolver.win_chance(1.2, 1.0, spread) > even, "the stronger side is favoured")
	t.check(BattleResolver.win_chance(1.3, 1.0, spread) > 0.97, "a 1.3 edge is nearly safe at 15%% fortune")
	t.check(BattleResolver.win_chance(1.3, 1.0, 20.0) < BattleResolver.win_chance(1.3, 1.0, spread), "wider fortune means more upsets")
	t.check_eq(BattleResolver.win_chance(0.0, 1.0, spread), 0.0, "no army, no chance")
	t.check_eq(BattleResolver.win_chance(1.0, 0.0, spread), 1.0, "no enemy, no contest")


## --- Casualties, the rout and what the result reports --------------------

func _resolve(data: GameData, seed_value: int, attackers: Array, defenders: Array, extra: Dictionary = {}) -> Dictionary:
	## Runs one battle on fresh copies and returns {result, attackers, defenders}.
	var attacker_units := _army(attackers)
	var defender_units := _army(defenders)
	var result := AutoResolver.new().resolve(data, CampaignRng.seeded(seed_value), attacker_units, defender_units, _context(extra))
	return {"result": result, "attackers": attacker_units, "defenders": defender_units}


func _loss_of(units_after: Array, template: String) -> float:
	## Strength lost by the (single) unit of this template; destroyed = 100.
	for unit in units_after:
		if unit["template"] == template:
			return 100.0 - float(unit["strength_pct"])
	return 100.0


func test_countered_units_bleed_more(t) -> void:
	var data := Fixtures.data()
	# A winning attack (no rout on this side): the melee pool alone is shared
	# out, and the horse the pikes countered carries more of it than the swords.
	var horse_loss := 0.0
	var foot_loss := 0.0
	for seed_value in range(30):
		var battle := _resolve(data, seed_value, ["test_horse", "test_elites", "test_elites"], ["test_pikes"])
		if battle["result"]["winner"] != "attacker":
			continue
		horse_loss += _loss_of(battle["attackers"], "test_horse")
		foot_loss += _loss_of(battle["attackers"], "test_elites")
	t.check(horse_loss > foot_loss * 1.15,
		"the cavalry the pikes countered bleeds more than the swordsmen beside it (%.0f vs %.0f)" % [horse_loss / 30.0, foot_loss / 30.0])


func test_pursuit_makes_cavalry_winners_kill_more(t) -> void:
	var data := Fixtures.data()
	var battle_rules: Dictionary = data.balance["battle"]
	var horse := BattleResolver.estimate(data, _army(["test_horse", "test_horse"]), _army(["test_slingers"]), _context())
	var foot := BattleResolver.estimate(data, _army(["test_elites", "test_elites"]), _army(["test_slingers"]), _context())
	t.check(float(horse["attacker"]["pursuit"]) > float(foot["attacker"]["pursuit"]), "a mounted army pursues faster")
	var rout_by_horse := AutoResolver.rout_pct(battle_rules, float(horse["attacker"]["pursuit"]))
	var rout_by_foot := AutoResolver.rout_pct(battle_rules, float(foot["attacker"]["pursuit"]))
	t.check(rout_by_horse > rout_by_foot, "so the rout it inflicts is bloodier (%.1f vs %.1f)" % [rout_by_horse, rout_by_foot])

	# The same beaten slingers, run down by each: identical melee pool, the rout differs.
	var rules := battle_rules.duplicate(true)
	rules["unit_casualty_scatter_pct"] = 0
	var caught_by_horse := _army(["test_slingers", "test_slingers"])
	var caught_by_foot := _army(["test_slingers", "test_slingers"])
	AutoResolver.distribute_casualties(caught_by_horse, horse["defender"], 20.0, rout_by_horse, rules, CampaignRng.seeded(1))
	AutoResolver.distribute_casualties(caught_by_foot, foot["defender"], 20.0, rout_by_foot, rules, CampaignRng.seeded(1))
	t.check(int(caught_by_horse[0]["strength_pct"]) < int(caught_by_foot[0]["strength_pct"]),
		"fewer slingers get away from horsemen (%d%% vs %d%% left)" % [int(caught_by_horse[0]["strength_pct"]), int(caught_by_foot[0]["strength_pct"])])


func test_fast_losers_escape(t) -> void:
	var data := Fixtures.data()
	var horse_loss := 0.0
	var pike_loss := 0.0
	for seed_value in range(30):
		horse_loss += float(_resolve(data, seed_value, ["test_elites", "test_elites"], ["test_horse"])["result"]["defender_casualty_pct"])
		pike_loss += float(_resolve(data, seed_value, ["test_elites", "test_elites"], ["test_pikes"])["result"]["defender_casualty_pct"])
	t.check(horse_loss < pike_loss,
		"beaten horse ride away; beaten pikemen cannot (%.0f%% vs %.0f%%)" % [horse_loss / 30.0, pike_loss / 30.0])


func test_result_reports_actual_losses(t) -> void:
	var data := Fixtures.data()
	var attackers := _army(["test_elites", "test_horse", "test_slingers"])
	var defenders := _army(["test_pikes", "test_spears"])
	var before_attackers := ArmyRules.soldiers(data, attackers)
	var before_defenders := ArmyRules.soldiers(data, defenders)
	var result := AutoResolver.new().resolve(data, CampaignRng.seeded(21), attackers, defenders, _context())
	var attacker_loss := 100.0 * (1.0 - float(ArmyRules.soldiers(data, attackers)) / before_attackers)
	var defender_loss := 100.0 * (1.0 - float(ArmyRules.soldiers(data, defenders)) / before_defenders)
	t.check_near(float(result["attacker_casualty_pct"]), attacker_loss, 0.5, "attacker losses are the men actually lost")
	t.check_near(float(result["defender_casualty_pct"]), defender_loss, 0.5, "defender losses likewise")
	t.check(result.has("attacker_destroyed") and result.has("defender_destroyed"), "destruction flags present")


func test_crushing_victory_destroys_and_flags(t) -> void:
	var data := Fixtures.data()
	var battle := _resolve(data, 4, ["test_elites", "test_elites", "test_elites"], ["test_mob"])
	t.check_eq(battle["result"]["winner"], "attacker", "three elite cohorts crush a mob")
	t.check(battle["result"]["defender_destroyed"], "the mob is wiped out")
	t.check(not battle["result"]["attacker_destroyed"], "the victors stand")
	t.check_eq(int(battle["result"]["experience_gained"]), int(data.balance["battle"]["experience_gain_on_victory"]),
		"a favourite's win earns the ordinary lesson")


func test_underdog_victory_teaches_twice(t) -> void:
	var data := Fixtures.data()
	# Spears and a mob against an elite cohort are the paper underdog by well
	# over the threshold; widen fortune so some seed still lets them win.
	data.balance["battle"]["randomness_pct"] = 60
	var found := false
	for seed_value in range(300):
		var battle := _resolve(data, seed_value, ["test_spears", "test_mob"], ["test_elites"])
		var paper := float(battle["result"]["breakdown"]["ratio"])
		if paper * float(data.balance["battle"]["underdog_strength_ratio"]) > 1.0:
			t.check(false, "the spears should be the paper underdog (ratio %.2f)" % paper)
			return
		if battle["result"]["winner"] == "attacker":
			found = true
			t.check_eq(int(battle["result"]["experience_gained"]), int(data.balance["battle"]["experience_gain_underdog"]),
				"an underdog's victory is worth double experience")
			var survivors: Array = battle["attackers"]
			t.check(survivors.size() > 0 and int(survivors[0]["experience"]) == int(data.balance["battle"]["experience_gain_underdog"]),
				"and the survivors carry it")
			break
	t.check(found, "some fortunate seed lets the underdog win")


func test_upgraded_unit_wins_more(t) -> void:
	var data := Fixtures.data()
	var wins := 0
	for seed_value in range(30):
		var armed := _army(["test_spears"])
		armed[0]["weapon"] = 2
		armed[0]["armor"] = 1
		var result := AutoResolver.new().resolve(data, CampaignRng.seeded(seed_value), armed, _army(["test_spears"]), _context())
		if result["winner"] == "attacker":
			wins += 1
	t.check(wins >= 24, "two weapon and one armour level win the mirror match at least 24 of 30 (won %d)" % wins)
