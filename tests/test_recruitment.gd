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
	t.check_eq(int(militia.get("weapons", -1)), 0, "no forges, no technique: bare steel")

	# The smith's yard (building effect) and the practiced craft stack.
	data.chains["test_barracks"]["levels"][0]["effects"] = {"weapon_upgrade": 1}
	state["factions"]["red"]["knowledge"]["test_smithing"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	RecruitmentRules.queue_unit(data, state, "beta", "test_spears")
	RecruitmentRules.advance_queues(data, state, "beta")
	var armed: Dictionary = state["settlements"]["beta"]["garrison"][1]
	t.check_eq(int(armed.get("weapons", -1)), 2, "forge plus technique arm the new man")
	t.check_eq(int(armed.get("armor", -1)), 0, "armor tracks its own effect")

	# Retraining re-arms the old militia to the new standard, free.
	RecruitmentRules.retrain_garrison(data, state, "beta")
	t.check_eq(int(militia.get("weapons", -1)), 2, "retraining is re-arming")


func test_merge_keeps_the_better_arms(t) -> void:
	var units := [
		{"template": "test_spears", "experience": 0, "strength_pct": 40, "weapons": 0, "armor": 1},
		{"template": "test_spears", "experience": 0, "strength_pct": 50, "weapons": 2, "armor": 0},
	]
	RecruitmentRules.merge_units(units)
	t.check_eq(units.size(), 1, "the two bands merge")
	t.check_eq(int(units[0]["weapons"]), 2, "the better blades are kept")
	t.check_eq(int(units[0]["armor"]), 1, "and the better mail")

func test_raise_army_closes_the_rearming_loop(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := Game.new()
	game.data = data
	game.state = state
	state["settlements"]["beta"]["garrison"] = [
		{"template": "test_spears", "experience": 1, "strength_pct": 100, "weapons": 1, "armor": 0},
	]
	t.check_eq(game.raise_army("alpha"), "", "another court's garrison refuses the order")
	var army_id := game.raise_army("beta")
	t.check(army_id != "", "the garrison marches out")
	t.check_eq(state["armies"][army_id]["units"].size(), 1, "as a field army")
	t.check_eq(int(state["armies"][army_id]["units"][0]["weapons"]), 1, "arms and all")
	t.check(state["settlements"]["beta"]["garrison"].is_empty(), "leaving the walls bare")
	t.check_near(float(state["armies"][army_id]["movement_left"]), 0.0, 0.001,
		"raised this season — it marches next")
	t.check_eq(game.raise_army("beta"), "", "nothing left to raise")
