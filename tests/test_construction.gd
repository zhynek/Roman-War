extends RefCounted
## Settlement tiers: government chain IS the settlement level; population
## thresholds and culture caps gate the upgrade; queues cost money up front.


func test_settlement_level_is_government_tier(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check_eq(SettlementRules.settlement_level(data, state["settlements"]["beta"]), "town", "tier 2 = town")


func test_government_upgrade_needs_population(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# beta: 2000 pop, government tier 2. Next tier (large_town) needs 2000 — allowed.
	var chains := []
	for project in ConstructionRules.available_projects(data, state, "beta"):
		chains.append(project["chain"])
	t.check(chains.has("test_government"), "upgrade offered at threshold")

	state["settlements"]["beta"]["population"] = 1999
	chains = []
	for project in ConstructionRules.available_projects(data, state, "beta"):
		chains.append(project["chain"])
	t.check(not chains.has("test_government"), "upgrade withheld below threshold")


func test_barbarian_settlement_cap(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement: Dictionary = state["settlements"]["alpha"]
	settlement["population"] = 50000
	settlement["buildings"]["tribal_government"] = 4  # minor_city, the tribal cap
	var chains := []
	for project in ConstructionRules.available_projects(data, state, "alpha"):
		chains.append(project["chain"])
	t.check(not chains.has("tribal_government"), "tribal culture cannot pass its cap")


func test_queue_pays_and_completes(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var treasury_before := int(state["factions"]["red"]["treasury"])
	t.check(ConstructionRules.queue_project(data, state, "beta", "test_health"), "queue accepts")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before - 400, "cost paid up front")

	var completed := ConstructionRules.advance_queues(data, state, "beta")
	t.check_eq(completed, ["drain_1"], "one-turn build completes")
	t.check_eq(int(state["settlements"]["beta"]["buildings"]["test_health"]), 1, "building present")


func test_cannot_demolish_farms_or_government(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check(not ConstructionRules.demolish(data, state, "beta", "test_farms"), "farms are permanent")
	t.check(not ConstructionRules.demolish(data, state, "beta", "test_government"), "government is permanent")
	state["settlements"]["beta"]["buildings"]["test_walls"] = 1
	t.check(ConstructionRules.demolish(data, state, "beta", "test_walls"), "walls can be pulled down")
	t.check(not state["settlements"]["beta"]["buildings"].has("test_walls"), "tier-1 demolition removes the chain")

func test_technique_gates_and_cheapens_building(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.chains["test_health"]["levels"][0]["requires_technique"] = "test_letters"
	state["settlements"]["beta"]["population"] = 3000
	var chains := []
	for project in ConstructionRules.available_projects(data, state, "beta"):
		chains.append(project["chain"])
	t.check(not chains.has("test_health"), "a building level may require a practiced technique")
	state["factions"]["red"]["knowledge"]["test_letters"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	var drain_cost := 0
	for project in ConstructionRules.available_projects(data, state, "beta"):
		if project["chain"] == "test_health":
			drain_cost = int(project["cost"])
	t.check_eq(drain_cost, 400, "adoption unlocks it at full price")

	# A builder's craft cheapens every project (build_cost_pct is authored negative).
	data.techniques["test_letters"]["effects"] = {"build_cost_pct": -10}
	for project in ConstructionRules.available_projects(data, state, "beta"):
		if project["chain"] == "test_health":
			drain_cost = int(project["cost"])
	t.check_eq(drain_cost, 360, "ten parts in a hundred off the bill")


func test_requires_building_gates_armoury(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var chains := []
	for project in ConstructionRules.available_projects(data, state, "beta"):
		chains.append(project["chain"])
	t.check(not chains.has("test_armoury"), "no armoury without a drill yard")
	var blockers := ConstructionRules.blockers_for(data, state, "beta", data.chains["test_armoury"], 1)
	var kinds := []
	for blocker in blockers:
		kinds.append(blocker["kind"])
	t.check(kinds.has("requires_building"), "and the blocker says why")
	state["settlements"]["beta"]["buildings"]["test_barracks"] = 2
	chains = []
	for project in ConstructionRules.available_projects(data, state, "beta"):
		chains.append(project["chain"])
	t.check(chains.has("test_armoury"), "a tier-2 barracks unlocks the armoury")
