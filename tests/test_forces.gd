extends RefCounted
## ForceRules: the one summary every banner and roster reads, over armies,
## fleets and garrisons of the synthetic fixture world.


func test_summary_counts_units_soldiers_and_upkeep(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears", "test_spears"])
	state["armies"][army_id]["units"][1]["strength_pct"] = 50
	MovementRules.reset_movement(data, state)

	var summary := ForceRules.summary(data, state, army_id)
	t.check_eq(summary["kind"], "army", "an army id is an army")
	t.check_eq(summary["owner"], "red", "owner read from the army")
	t.check_eq(summary["region"], "gamma", "region read from the army")
	t.check_eq(summary["units"], 2, "unit count")
	t.check_eq(summary["max_units"], 20, "cap from balance.forces")
	t.check_near(float(summary["fill"]), 0.1, 0.0001, "fill is units over the cap")
	t.check_eq(summary["soldiers"], 120, "80 + 40 men present")
	t.check_eq(summary["max_soldiers"], 160, "160 men at full strength")
	t.check_eq(summary["strength_pct"], 75, "three quarters strength")
	t.check_eq(summary["upkeep"], 240, "upkeep sums both units")
	t.check(summary["general"] == null, "a captain's army has no general")
	t.check_near(float(summary["movement_left"]), 2.0, 0.0001, "movement left after reset")
	t.check_near(float(summary["movement_max"]), 2.0, 0.0001, "movement budget")
	t.check(float(summary["strength"]) > 0.0, "the resolver's estimate is exposed")
	t.check(summary["besieging"] == null, "not besieging")


func test_summary_with_general_and_siege(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var general := Fixtures.add_character(state, "red", "red_marcus", {"command": 4, "location": "beta", "role": "leader"})
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	state["armies"][army_id]["general"] = general
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege laid")

	var summary := ForceRules.summary(data, state, army_id)
	t.check_eq(summary["general"]["id"], general, "general id")
	t.check_eq(summary["general"]["command"], 4, "effective command")
	t.check(summary["general"]["is_leader"], "the leader is flagged")
	t.check_eq(summary["besieging"], "alpha", "besieging the region it invests")
	t.check_near(float(summary["movement_left"]), 0.0, 0.0001, "the siege took the turn")


func test_summary_for_garrison_and_fleet(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["beta"]["garrison"].append({"template": "test_mob", "experience": 0, "strength_pct": 100})
	var garrison := ForceRules.summary(data, state, "garrison:beta")
	t.check_eq(garrison["kind"], "garrison", "garrison pseudo-id resolves")
	t.check_eq(garrison["region"], "beta", "garrison region")
	t.check_eq(garrison["units"], 1, "garrison unit count")
	t.check_eq(garrison["soldiers"], 60, "garrison head count")

	var fleet_id := Fixtures.add_fleet(state, "red", "test_sea", ["test_galley", "test_galley"])
	var fleet := ForceRules.summary(data, state, fleet_id)
	t.check_eq(fleet["kind"], "fleet", "fleet id resolves")
	t.check_eq(fleet["sea_zone"], "test_sea", "fleet zone")
	t.check_eq(fleet["units"], 2, "ships counted as units")
	t.check_eq(fleet["upkeep"], 200, "fleet upkeep")

	t.check(ForceRules.summary(data, state, "army_999").is_empty(), "unknown ids give an empty summary")
	t.check(ForceRules.summary(data, state, "nonsense").is_empty(), "garbage ids give an empty summary")


func test_forces_in_region_are_numerically_ordered(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["next_id"] = 9
	var first := Fixtures.add_army(state, "red", "gamma", ["test_spears"])   # army_9
	var second := Fixtures.add_army(state, "blue", "gamma", ["test_mob"])    # army_10
	Fixtures.add_army(state, "red", "delta", ["test_spears"])
	t.check_eq(ForceRules.armies_in(state, "gamma"), [first, second], "army_9 sorts before army_10")
	t.check(ForceRules.id_less("army_2", "army_10"), "numeric suffix order")
	t.check(not ForceRules.id_less("fleet_1", "army_1"), "different prefixes fall back to string order")
