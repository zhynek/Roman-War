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
