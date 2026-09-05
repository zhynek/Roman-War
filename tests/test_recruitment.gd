extends RefCounted
## Recruitment: building gates, population cost, era (army-reform) gates.


func test_building_gates(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var ids := []
	for unit in RecruitmentRules.available_units(data, state, "beta"):
		ids.append(unit["id"])
	t.check(ids.has("test_spears"), "barracks level 1 unit available")
	t.check(not ids.has("test_elites"), "level 2 unit gated by building tier")

	state["settlements"]["beta"]["buildings"]["test_barracks"] = 2
	ids = []
	for unit in RecruitmentRules.available_units(data, state, "beta"):
		ids.append(unit["id"])
	t.check(not ids.has("test_elites"), "post-reform unit gated by era")

	state["factions"]["red"]["era"] = "post_marian"
	ids = []
	for unit in RecruitmentRules.available_units(data, state, "beta"):
		ids.append(unit["id"])
	t.check(ids.has("test_elites"), "reform era unlocks the roster")


func test_recruiting_costs_money_and_people(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var treasury_before := int(state["factions"]["red"]["treasury"])
	var population_before := int(state["settlements"]["beta"]["population"])

	t.check(RecruitmentRules.queue_unit(data, state, "beta", "test_spears"), "queue accepts")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before - 400, "denarii paid")
	t.check_eq(int(state["settlements"]["beta"]["population"]), population_before - 80, "soldiers drawn from the people")

	var completed := RecruitmentRules.advance_queues(data, state, "beta")
	t.check_eq(completed, ["test_spears"], "unit completes next turn")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 1, "unit joins garrison")


func test_cannot_drain_village_dry(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["beta"]["population"] = 450
	t.check(not RecruitmentRules.queue_unit(data, state, "beta", "test_spears"),
		"recruitment refused when it would empty the settlement")


func test_merge_units(t) -> void:
	var units := [
		{"template": "test_spears", "experience": 2, "strength_pct": 40},
		{"template": "test_spears", "experience": 0, "strength_pct": 50},
		{"template": "test_spears", "experience": 1, "strength_pct": 90},
	]
	RecruitmentRules.merge_units(units)
	t.check_eq(units.size(), 2, "three part-strength units merge into two")
	t.check_eq(int(units[0]["strength_pct"]), 100, "first unit filled to full")
	t.check_eq(int(units[0]["experience"]), 2, "highest experience kept")

func test_technique_gates_the_roster(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.units["test_spears"]["requires_technique"] = "test_smithing"
	var ids := []
	for unit in RecruitmentRules.available_units(data, state, "beta"):
		ids.append(unit["id"])
	t.check(not ids.has("test_spears"), "a unit may require a practiced technique")
	state["factions"]["red"]["knowledge"]["test_smithing"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	ids = []
	for unit in RecruitmentRules.available_units(data, state, "beta"):
		ids.append(unit["id"])
	t.check(not ids.has("test_spears"), "awareness is not practice")
	state["factions"]["red"]["knowledge"]["test_smithing"]["stage"] = "adopted"
	ids = []
	for unit in RecruitmentRules.available_units(data, state, "beta"):
		ids.append(unit["id"])
	t.check(ids.has("test_spears"), "adoption unlocks it")


func test_recruits_are_stamped_with_the_city_standard(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	RecruitmentRules.queue_unit(data, state, "beta", "test_spears")
	RecruitmentRules.advance_queues(data, state, "beta")
	var militia: Dictionary = state["settlements"]["beta"]["garrison"][0]
	t.check_eq(int(militia.get("weapon", -1)), 0, "no forges, no technique: bare steel")

	# The smith's yard (building effect) and the practiced craft stack.
	data.chains["test_barracks"]["levels"][0]["effects"] = {"weapon_upgrade": 1}
	state["factions"]["red"]["knowledge"]["test_smithing"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	RecruitmentRules.queue_unit(data, state, "beta", "test_spears")
	RecruitmentRules.advance_queues(data, state, "beta")
	var armed: Dictionary = state["settlements"]["beta"]["garrison"][1]
	t.check_eq(int(armed.get("weapon", -1)), 2, "forge plus technique arm the new man")
	t.check_eq(int(armed.get("armor", -1)), 0, "armor tracks its own effect")

	# Retraining re-arms the old militia to the new standard, free.
	RecruitmentRules.retrain_garrison(data, state, "beta")
	t.check_eq(int(militia.get("weapon", -1)), 2, "retraining is re-arming")


func test_merge_keeps_the_better_arms(t) -> void:
	var units := [
		{"template": "test_spears", "experience": 0, "strength_pct": 40, "weapon": 0, "armor": 1},
		{"template": "test_spears", "experience": 0, "strength_pct": 50, "weapon": 2, "armor": 0},
	]
	RecruitmentRules.merge_units(units)
	t.check_eq(units.size(), 1, "the two bands merge")
	t.check_eq(int(units[0]["weapon"]), 2, "the better blades are kept")
	t.check_eq(int(units[0]["armor"]), 1, "and the better mail")

func test_raise_army_closes_the_rearming_loop(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := Game.new()
	game.data = data
	game.state = state
	state["settlements"]["beta"]["garrison"] = [
		{"template": "test_spears", "experience": 1, "strength_pct": 100, "weapon": 1, "armor": 0},
	]
	t.check_eq(game.raise_army("alpha"), "", "another court's garrison refuses the order")
	var army_id := game.raise_army("beta")
	t.check(army_id != "", "the garrison marches out")
	t.check_eq(state["armies"][army_id]["units"].size(), 1, "as a field army")
	t.check_eq(int(state["armies"][army_id]["units"][0]["weapon"]), 1, "arms and all")
	t.check(state["settlements"]["beta"]["garrison"].is_empty(), "leaving the walls bare")
	# Men fresh from the walls keep the season's march (ForceRules.raise_army:
	# the whole-garrison button follows the same rules as a ticked raise).
	t.check_near(float(state["armies"][army_id]["movement_left"]),
		MovementRules.movement_points_for(data, state, state["armies"][army_id]), 0.001,
		"raised this season with the season's march")
	t.check_eq(game.raise_army("beta"), "", "nothing left to raise")


## --- Kit and drill from the town's buildings --------------------------------

func test_recruits_get_upgrades_from_buildings(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	beta["buildings"]["test_barracks"] = 2  # drill yard: xp 1, weapon 1
	t.check(RecruitmentRules.queue_unit(data, state, "beta", "test_spears"), "queue accepts")
	RecruitmentRules.advance_queues(data, state, "beta")
	var recruit: Dictionary = beta["garrison"][0]
	t.check_eq(int(recruit["experience"]), 1, "the drill yard's experience")
	t.check_eq(int(recruit["weapon"]), 1, "the barracks smith's blade")
	t.check_eq(int(recruit["armor"]), 0, "no armoury, no mail")

	beta["buildings"]["test_armoury"] = 1  # +1 weapon, +1 armour, summed across chains
	RecruitmentRules.queue_unit(data, state, "beta", "test_spears")
	RecruitmentRules.advance_queues(data, state, "beta")
	var armed: Dictionary = beta["garrison"][1]
	t.check_eq(int(armed["weapon"]), 2, "barracks and armoury weapon levels add")
	t.check_eq(int(armed["armor"]), 1, "the armoury's mail")
	var profile := RecruitmentRules.recruit_profile(data, state, "beta", "test_spears")
	t.check_eq(int(profile["weapon"]), 2, "the recruit profile says the same")


func test_upgrade_cap(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	data.chains["test_forge"] = {
		"id": "test_forge", "kind": "temple", "god": "Vulcan", "cultures": ["roman"], "name": "Forge Shrine",
		"levels": [{"id": "forge_1", "name": "Forge", "min_settlement_level": "village", "cost": 300,
			"build_turns": 1, "effects": {"weapon_upgrade": 2}, "description": ""}],
	}
	beta["buildings"]["test_barracks"] = 2
	beta["buildings"]["test_armoury"] = 1
	beta["buildings"]["test_forge"] = 1  # 1 + 1 + 2 = 4 weapon levels on offer
	var profile := RecruitmentRules.recruit_profile(data, state, "beta")
	t.check_eq(int(profile["weapon"]), int(data.balance["recruitment"]["upgrade_max"]), "kit is capped")
	data.techniques["test_guild"] = {
		"id": "test_guild", "name": "Guild", "domain": "metallurgy_craft", "historical_basis": "fixture",
		"start_adopted": {"cultures": [], "factions": []}, "origin_cultures": [],
		"prerequisites": {"building_kind": "", "building_level": 0, "resource": "", "hidden_resource": "", "coastal": false, "techniques": []},
		"adoption": {"cost": 1, "turns": 1}, "culture_resistance": {}, "effects": {"upgrade_cap": 1},
	}
	Fixtures.adopt_technique(state, "red", "test_guild")
	profile = RecruitmentRules.recruit_profile(data, state, "beta")
	t.check_eq(int(profile["weapon"]), int(data.balance["recruitment"]["upgrade_max"]) + 1, "a practiced guild raises the cap")


func test_retrain_refits_but_never_downgrades(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	beta["buildings"]["test_barracks"] = 2
	beta["buildings"]["test_armoury"] = 1  # town standard: weapon 2, armour 1
	var veteran := {"template": "test_spears", "experience": 3, "strength_pct": 60, "weapon": 3, "armor": 0}
	var fresh := {"template": "test_spears", "experience": 0, "strength_pct": 100, "weapon": 0, "armor": 0}
	beta["garrison"] = [veteran, fresh]
	var treasury_before := int(state["factions"]["red"]["treasury"])
	t.check_eq(RecruitmentRules.retrain_garrison(data, state, "beta"), 1, "one depleted unit refilled")
	t.check_eq(int(veteran["strength_pct"]), 100, "refilled")
	t.check_eq(int(veteran["weapon"]), 3, "better kit than the town issues is kept")
	t.check_eq(int(veteran["armor"]), 1, "the armoury's mail is issued")
	t.check_eq(int(veteran["experience"]), 3, "experience untouched")
	t.check_eq(int(fresh["weapon"]), 2, "a full-strength unit is refitted too")
	t.check(int(state["factions"]["red"]["treasury"]) < treasury_before, "the refill cost denarii")


func test_merge_keeps_best_kit(t) -> void:
	var units := [
		{"template": "test_spears", "experience": 1, "strength_pct": 40, "weapon": 2, "armor": 0},
		{"template": "test_spears", "experience": 0, "strength_pct": 50, "weapon": 0, "armor": 1},
	]
	RecruitmentRules.merge_units(units)
	t.check_eq(units.size(), 1, "merged into one")
	t.check_eq(int(units[0]["weapon"]), 2, "best blades kept")
	t.check_eq(int(units[0]["armor"]), 1, "best mail kept")


func test_levy_strain_from_the_muster(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	var order_rules: Dictionary = data.balance["public_order"]
	RecruitmentRules.queue_unit(data, state, "beta", "test_spears")
	var expected := 80.0 / 2000.0 * float(order_rules["levy_strain_scale"])
	t.check_near(float(beta["levy_strain"]), expected, 0.001, "eighty men from two thousand strain the town")
	beta["buildings"]["test_barracks"] = 2  # a drill yard softens the levy
	RecruitmentRules.queue_unit(data, state, "beta", "test_spears")
	var population := float(beta["population"]) + 80.0
	var softened := 80.0 / population * float(order_rules["levy_strain_scale"]) \
		* (1.0 - float(order_rules["levy_strain_drill_reduction_pct"]) / 100.0)
	t.check_near(float(beta["levy_strain"]), expected + softened, 0.01, "drilled towns take the levy better")
	PublicOrderRules.decay_levy_strain(data, beta)
	t.check_near(float(beta["levy_strain"]), expected + softened - float(order_rules["levy_strain_decay_per_turn"]), 0.01,
		"and it fades each turn")


func test_bodyguards_are_not_recruitable(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var ids := []
	for unit in RecruitmentRules.available_units(data, state, "beta"):
		ids.append(unit["id"])
	t.check(not ids.has("test_guard"), "a general's escort is never a barracks product")
	t.check(not RecruitmentRules.queue_unit(data, state, "beta", "test_guard"), "nor can it be queued")


func test_a_besieged_city_neither_recruits_nor_builds(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check(RecruitmentRules.queue_unit(data, state, "beta", "test_spears"), "peacetime muster accepted")
	state["settlements"]["beta"]["construction_queue"].append({"chain": "test_health", "turns_left": 1})
	state["settlements"]["beta"]["siege"] = {"besieger": "army_99", "turns": 1, "equipment_ready": false}
	t.check(not RecruitmentRules.queue_unit(data, state, "beta", "test_spears"), "nobody musters under siege")
	state["settlements"]["beta"]["garrison"].append({"template": "test_spears", "experience": 0, "strength_pct": 50})
	t.check_eq(RecruitmentRules.retrain_garrison(data, state, "beta"), 0, "no retraining under siege")
	t.check(RecruitmentRules.advance_queues(data, state, "beta").is_empty(), "the muster stands still")
	t.check(ConstructionRules.advance_queues(data, state, "beta").is_empty(), "so does the building work")
	state["settlements"]["beta"]["siege"] = null
	t.check_eq(RecruitmentRules.advance_queues(data, state, "beta"), ["test_spears"], "work resumes when the siege lifts")
