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


func test_bodyguards_are_not_recruitable(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var ids := []
	for unit in RecruitmentRules.available_units(data, state, "beta"):
		ids.append(unit["id"])
	t.check(not ids.has("test_guard"), "a general's escort is never a barracks product")
	t.check(not RecruitmentRules.queue_unit(data, state, "beta", "test_guard"), "nor can it be queued")


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
