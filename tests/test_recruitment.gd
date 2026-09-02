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
	t.check_eq(int(recruit.get("weapon", 0)), 1, "the barracks smith's blade")
	t.check(not recruit.has("armor"), "no armoury, no armour key at all")

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


func test_retrain_refits_but_never_downgrades(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	beta["buildings"]["test_barracks"] = 2
	beta["buildings"]["test_armoury"] = 1  # town standard: weapon 2, armour 1
	var veteran := {"template": "test_spears", "experience": 3, "strength_pct": 60, "weapon": 3}
	var fresh := {"template": "test_spears", "experience": 0, "strength_pct": 100}
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
		{"template": "test_spears", "experience": 1, "strength_pct": 40, "weapon": 2},
		{"template": "test_spears", "experience": 0, "strength_pct": 50, "armor": 1},
	]
	RecruitmentRules.merge_units(units)
	t.check_eq(units.size(), 1, "merged into one")
	t.check_eq(int(units[0]["weapon"]), 2, "best blades kept")
	t.check_eq(int(units[0]["armor"]), 1, "best mail kept")
