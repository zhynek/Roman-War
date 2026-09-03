extends RefCounted
## Military techniques (the warcraft domain): prerequisites that read the war
## record and closed traditions, the `war` block reaching the battle estimate,
## upkeep, order, sieges, marches and the levy, and the 270 BC endowment.


func _kinds(blockers: Array) -> Array:
	var kinds: Array = []
	for blocker in blockers:
		kinds.append(String(blocker["kind"]))
	return kinds


func test_war_prerequisites_are_blockers(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var caches := KnowledgeRules.build_caches(data, state, false)
	var drill: Dictionary = data.techniques["test_horse_drill"]
	t.check_eq(_kinds(KnowledgeRules.unmet_prerequisites(data, state, caches, "red", drill)), ["building"],
		"no stables yet: the blocker names the building")
	state["settlements"]["beta"]["buildings"]["test_stables"] = 1
	caches = KnowledgeRules.build_caches(data, state, false)
	t.check(KnowledgeRules.prerequisites_met(data, state, caches, "red", drill), "a paddock in any town unlocks it")

	var camp: Dictionary = data.techniques["test_camp_law"]
	var blockers := KnowledgeRules.unmet_prerequisites(data, state, caches, "red", camp)
	t.check_eq(_kinds(blockers), ["battles_won"], "no battle won yet")
	t.check_eq(int(blockers[0]["params"]["needs"]), 1, "and says how many it wants")
	state["factions"]["red"]["war_record"]["battles_won"] = 1
	t.check(KnowledgeRules.prerequisites_met(data, state, caches, "red", camp), "one victory is enough")

	var fury: Dictionary = data.techniques["test_tribal_fury"]
	t.check_eq(_kinds(KnowledgeRules.unmet_prerequisites(data, state, caches, "blue", fury)), ["faced"],
		"the tribe has not yet met the spear wall")
	var stud: Dictionary = data.techniques["test_royal_stud"]
	state["factions"]["blue"]["war_record"]["battles_won"] = 1
	t.check(_kinds(KnowledgeRules.unmet_prerequisites(data, state, caches, "red", stud)).has("tradition"),
		"a tradition closed to red")
	t.check(KnowledgeRules.prerequisites_met(data, state, caches, "blue", stud), "and open to blue")
	t.check(not KnowledgeRules.open_to(stud, "red") and KnowledgeRules.open_to(drill, "red"), "open_to agrees")


func test_closed_traditions_do_not_spread(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.adopt_technique(state, "blue", "test_royal_stud")
	Fixtures.adopt_technique(state, "blue", "test_horse_drill")
	var candidates: Array = []
	KnowledgeRules._spread_candidates(data, state, "blue", "red", candidates)
	var tids: Array = []
	for candidate in candidates:
		tids.append(candidate["tid"])
	t.check_eq(tids, ["test_horse_drill"], "rumour carries the drill but not the closed stud")
	KnowledgeRules.on_settlement_captured(data, state, "red", "blue")
	var red_knowledge: Dictionary = state["factions"]["red"]["knowledge"]
	t.check(red_knowledge.has("test_horse_drill") and not red_knowledge.has("test_royal_stud"),
		"conquest teaches the same lesson")


func test_war_effects_reach_battle_estimate(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var horse := [{"template": "test_horse", "experience": 0, "strength_pct": 100}]
	var foot := [{"template": "test_elites", "experience": 0, "strength_pct": 100}]
	var plain := BattleResolver.estimate(data, horse, foot, {"terrain": "plains", "wall_level": 0})
	Fixtures.adopt_technique(state, "red", "test_horse_drill")
	var mods := KnowledgeRules.army_mods(data, state, "red")
	t.check_eq(float(mods["class_stats"]["cavalry"]["attack"]), 3.0, "the class table is merged")
	t.check_near(float(mods["pursuit_pct"]), 10.0, 0.001, "and the flat scalar summed")
	var drilled := BattleResolver.estimate(data, horse, foot,
		{"terrain": "plains", "wall_level": 0, "attacker_mods": mods})
	t.check(float(drilled["attacker"]["strength"]) > float(plain["attacker"]["strength"]), "three points of attack show")
	var technique_factor := 1.0
	for factor in drilled["attacker"]["factors"]:
		if factor["label"] == "techniques":
			technique_factor = float(factor["value"])
	t.check(technique_factor > 1.0, "as a named techniques factor")
	t.check(float(drilled["attacker"]["pursuit"]) > float(plain["attacker"]["pursuit"]), "and a keener pursuit")


func test_war_effects_reach_upkeep(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_army(state, "red", "beta", ["test_horse", "test_spears"])
	t.check_eq(EconomyRules.faction_upkeep(data, state, "red"), 320, "200 + 120 before the technique")
	Fixtures.adopt_technique(state, "red", "test_horse_drill")
	t.check_eq(EconomyRules.faction_upkeep(data, state, "red"), 280, "horse a fifth cheaper, spears unchanged")


func test_war_effects_reach_order_siege_march_and_levy(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	beta["garrison"] = [{"template": "test_spears", "experience": 0, "strength_pct": 100}]
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	var by_label := {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	var garrison_before := float(by_label.get("garrison", 0.0))
	t.check(garrison_before > 0.0, "the garrison polices")
	t.check_eq(SiegeRules.equipment_turns_for(data, state, "red"), int(data.balance["siege"]["equipment_turns"]), "base siege turns")
	MovementRules.reset_movement(data, state)
	var march_before := float(state["armies"][army_id]["movement_left"])

	Fixtures.adopt_technique(state, "red", "test_camp_law")
	by_label = {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(float(by_label.get("garrison", 0.0)), garrison_before * 1.2, 0.001, "garrison polices 20% better")
	t.check_eq(SiegeRules.equipment_turns_for(data, state, "red"), int(data.balance["siege"]["equipment_turns"]) - 1, "siege works a turn sooner")
	MovementRules.reset_movement(data, state)
	t.check_near(float(state["armies"][army_id]["movement_left"]), march_before + 0.5, 0.001, "armies march half a step further")
	RecruitmentRules.queue_unit(data, state, "beta", "test_spears")
	var order_rules: Dictionary = data.balance["public_order"]
	var expected := 80.0 / 2000.0 * float(order_rules["levy_strain_scale"]) * 0.5
	t.check_near(float(beta["levy_strain"]), expected, 0.001, "the levy strains half as much")


func test_class_recruit_experience(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.adopt_technique(state, "blue", "test_tribal_fury")
	t.check_eq(KnowledgeRules.class_recruit_xp(data, state, "blue", "infantry"), 1, "foot recruits start seasoned")
	t.check_eq(KnowledgeRules.class_recruit_xp(data, state, "blue", "cavalry"), 0, "horse do not")
	t.check(bool(KnowledgeRules.army_mods(data, state, "blue")["fatigue_immune"]), "and the warband shrugs off the march")


func test_war_record_unlocks_learning(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.techniques["test_anti_horse"] = {
		"id": "test_anti_horse", "name": "Anti-Horse Drill", "domain": "warcraft", "historical_basis": "fixture",
		"start_adopted": {"cultures": [], "factions": []}, "origin_cultures": ["roman"],
		"prerequisites": {"building_kind": "", "building_level": 0, "resource": "", "hidden_resource": "",
			"coastal": false, "techniques": [], "faced": {"class": "cavalry", "battles": 1}},
		"adoption": {"cost": 500, "turns": 1}, "culture_resistance": {}, "effects": {},
		"war": {"matchups": [{"class": "spear", "versus": "cavalry", "pct": 10}]},
	}
	var caches := KnowledgeRules.build_caches(data, state, false)
	var technique: Dictionary = data.techniques["test_anti_horse"]
	var blockers := KnowledgeRules.unmet_prerequisites(data, state, caches, "red", technique)
	t.check_eq(_kinds(blockers), ["faced"], "never fought horse")
	t.check_eq(String(blockers[0]["params"]["unit_class"]), "cavalry", "the blocker says whom to fight")
	var attacker_id := Fixtures.add_army(state, "red", "beta", ["test_pikes", "test_pikes"])
	var defender_id := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	state["armies"][defender_id]["units"] = [{"template": "test_horse", "experience": 0, "strength_pct": 100}]
	CombatRules.attack_army(data, state, AutoResolver.new(), CampaignRng.seeded(5), attacker_id, defender_id)
	var record: Dictionary = state["factions"]["red"]["war_record"]
	t.check_eq(int(record["faced"].get("cavalry", 0)), 1, "the record counts the horse it met")
	t.check(KnowledgeRules.prerequisites_met(data, state, caches, "red", technique), "one battle against horse is enough")


func test_endowment_and_save_round_trip(t) -> void:
	var game := Game.new_campaign("julii", 7)
	t.check(KnowledgeRules.adopted(game.state, "julii", "manipular_drill"), "Rome starts with the maniple")
	t.check(KnowledgeRules.adopted(game.state, "macedon", "sarissa_drill"), "Macedon with the sarissa")
	t.check(not KnowledgeRules.adopted(game.state, "julii", "sarissa_drill"), "and not the other way round")
	var mods := KnowledgeRules.army_mods(game.data, game.state, "julii")
	t.check(mods["class_stats"].has("infantry"), "the maniple reaches Rome's foot")
	var restored := SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(restored, game.data)
	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored
	for i in range(4):
		game.end_turn()
		resumed.end_turn()
	t.check_eq(JSON.stringify(JSON.parse_string(JSON.stringify(game.state))),
		JSON.stringify(JSON.parse_string(JSON.stringify(resumed.state))), "saved and live games agree")
