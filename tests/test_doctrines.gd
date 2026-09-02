extends RefCounted
## Military doctrines: prerequisites with reasons, paying and completing a
## reform, one at a time, and the effects reaching battle, upkeep, order,
## sieges and movement. The AI adopts too, and saves carry it all.


func _by_id(rows: Array) -> Dictionary:
	var result := {}
	for row in rows:
		result[row["id"]] = row
	return result


func test_prerequisites_report_reasons(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rows := _by_id(DoctrineRules.available(data, state, "red"))
	t.check(rows.has("test_horse_drill") and not rows.has("test_tribal_fury"), "only the faction's culture's doctrines are listed")
	t.check_eq(rows["test_horse_drill"]["status"], "locked", "no stables yet")
	t.check(String(rows["test_horse_drill"]["unmet"][0]).contains("stables"), "the reason names the missing building")
	t.check_eq(rows["test_camp_law"]["status"], "locked", "no battle won yet")
	t.check(String(rows["test_camp_law"]["unmet"][0]).contains("battles won"), "the reason names the war record")

	state["settlements"]["beta"]["buildings"]["test_stables"] = 1
	rows = _by_id(DoctrineRules.available(data, state, "red"))
	t.check_eq(rows["test_horse_drill"]["status"], "available", "a paddock in any town unlocks it")


func test_adopt_pays_and_completes_after_turns(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var red: Dictionary = state["factions"]["red"]
	t.check(not DoctrineRules.adopt(data, state, "red", "test_horse_drill"), "locked doctrines cannot be bought")
	state["settlements"]["beta"]["buildings"]["test_stables"] = 1
	var treasury_before := int(red["treasury"])
	t.check(DoctrineRules.adopt(data, state, "red", "test_horse_drill"), "adoption accepted")
	t.check_eq(int(red["treasury"]), treasury_before - 1000, "the reform is paid up front")
	t.check_eq(red["reforms"].size(), 1, "one reform in progress")
	t.check(not DoctrineRules.adopt(data, state, "red", "test_horse_drill"), "cannot buy it twice")

	var completed := DoctrineRules.advance_reforms(data, state)
	t.check(not completed.has("red"), "two-turn reform is not done after one")
	completed = DoctrineRules.advance_reforms(data, state)
	t.check_eq(completed.get("red", []), ["test_horse_drill"], "done after two")
	t.check_eq(red["doctrines"], ["test_horse_drill"], "and practised from now on")
	t.check(red["reforms"].is_empty(), "the queue is clear")


func test_one_reform_at_a_time(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["beta"]["buildings"]["test_stables"] = 1
	state["factions"]["red"]["war_record"]["battles_won"] = 1
	t.check(DoctrineRules.adopt(data, state, "red", "test_horse_drill"), "first reform starts")
	t.check(not DoctrineRules.adopt(data, state, "red", "test_camp_law"), "a second must wait")
	DoctrineRules.advance_reforms(data, state)
	DoctrineRules.advance_reforms(data, state)
	t.check(DoctrineRules.adopt(data, state, "red", "test_camp_law"), "and starts once the first is done")


func test_effects_reach_battle_estimate(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var horse := [{"template": "test_horse", "experience": 0, "strength_pct": 100}]
	var foot := [{"template": "test_elites", "experience": 0, "strength_pct": 100}]
	var plain := BattleResolver.estimate(data, horse, foot, {"terrain": "plains", "wall_level": 0})
	DoctrineRules.grant(state["factions"]["red"], "test_horse_drill")
	var drilled := BattleResolver.estimate(data, horse, foot,
		{"terrain": "plains", "wall_level": 0, "attacker_mods": DoctrineRules.army_mods(data, state, "red")})
	t.check(float(drilled["attacker"]["strength"]) > float(plain["attacker"]["strength"]), "three points of attack show")
	var doctrine_factor := 1.0
	for factor in drilled["attacker"]["factors"]:
		if factor["label"] == "doctrines":
			doctrine_factor = float(factor["value"])
	t.check(doctrine_factor > 1.0, "as a named doctrines factor")


func test_effects_reach_upkeep(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_army(state, "red", "beta", ["test_horse", "test_spears"])
	t.check_eq(EconomyRules.faction_upkeep(data, state, "red"), 320, "200 + 120 before the doctrine")
	DoctrineRules.grant(state["factions"]["red"], "test_horse_drill")
	t.check_eq(EconomyRules.faction_upkeep(data, state, "red"), 280, "horse a fifth cheaper, spears unchanged")


func test_effects_reach_order_siege_and_march(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	beta["garrison"] = [{"template": "test_spears", "experience": 0, "strength_pct": 100}]
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	var by_label := {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("garrison", 0.0), 16.0, 0.001, "garrison bonus before")
	t.check_eq(SiegeRules.equipment_turns_for(data, state, "red"), int(data.balance["siege"]["equipment_turns"]), "base siege turns")

	DoctrineRules.grant(state["factions"]["red"], "test_camp_law")
	by_label = {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("garrison", 0.0), 19.2, 0.001, "garrison polices 20% better")
	t.check_eq(SiegeRules.equipment_turns_for(data, state, "red"), int(data.balance["siege"]["equipment_turns"]) - 1, "siege works a turn sooner")
	MovementRules.reset_movement(data, state)
	t.check_near(float(state["armies"][army_id]["movement_left"]), 2.5, 0.001, "armies march half a step further")
	RecruitmentRules.queue_unit(data, state, "beta", "test_spears")
	t.check_near(float(beta["levy_strain"]), 2.0, 0.001, "the levy strains half as much")


func test_war_record_unlocks_learning(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.doctrines["test_anti_horse"] = {
		"id": "test_anti_horse", "name": "Anti-Horse Drill", "cultures": ["roman"], "cost": 500, "turns": 1,
		"prerequisites": {"faced": {"class": "cavalry", "battles": 1}},
		"effects": {"matchups": [{"class": "spear", "versus": "cavalry", "pct": 10}]},
		"historical_note": "", "description": "",
	}
	var rows := _by_id(DoctrineRules.available(data, state, "red"))
	t.check_eq(rows["test_anti_horse"]["status"], "locked", "never fought horse")
	t.check(String(rows["test_anti_horse"]["unmet"][0]).contains("against cavalry"), "the reason says whom to fight")
	var attacker_id := Fixtures.add_army(state, "red", "beta", ["test_pikes", "test_pikes"])
	var defender_id := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	state["armies"][defender_id]["units"] = [{"template": "test_horse", "experience": 0, "strength_pct": 100}]
	CombatRules.attack_army(data, state, AutoResolver.new(), CampaignRng.seeded(5), attacker_id, defender_id)
	rows = _by_id(DoctrineRules.available(data, state, "red"))
	t.check_eq(rows["test_anti_horse"]["status"], "available", "one battle against horse is enough")


func test_ai_adopts_when_rich(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	AiStub.take_turn(data, state, "blue")
	var blue: Dictionary = state["factions"]["blue"]
	t.check_eq(blue["reforms"].size(), 1, "a rich tribe starts a reform")
	t.check_eq(blue["reforms"][0]["doctrine"], "test_tribal_fury", "the one it qualifies for")
	blue["treasury"] = 1000
	blue["reforms"] = []
	AiStub.take_turn(data, state, "blue")
	t.check(blue["reforms"].is_empty(), "a poor one keeps its reserve")


func test_save_round_trip_with_reforms(t) -> void:
	var game := Game.new_campaign("julii", 7)
	t.check(game.adopt_doctrine("pilum_volley"), "the Julii can drill the pilum at the start")
	var restored := SaveGame.from_json(SaveGame.to_json(game.state))
	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored
	for i in range(4):
		game.end_turn()
		resumed.end_turn()
	t.check(game.state["factions"]["julii"]["doctrines"].has("pilum_volley"), "the reform completed")
	t.check_eq(JSON.stringify(JSON.parse_string(JSON.stringify(game.state))),
		JSON.stringify(JSON.parse_string(JSON.stringify(resumed.state))), "saved and live games agree")


func test_starting_doctrines_from_campaign(t) -> void:
	var game := Game.new_campaign("julii", 42)
	t.check_eq(game.state["factions"]["julii"]["doctrines"], ["manipular_drill"], "Rome starts with the maniple")
	t.check_eq(game.state["factions"]["macedon"]["doctrines"], ["sarissa_drill"], "Macedon with the sarissa")
	t.check(game.state["factions"]["pontus"]["doctrines"].is_empty(), "Pontus starts with none")
	var summary := game.faction_doctrines()
	t.check_eq(summary["adopted"][0]["name"], "Manipular Drill", "the facade names them")
	t.check(game.available_doctrines().size() >= 8, "and lists a tree to pursue")
