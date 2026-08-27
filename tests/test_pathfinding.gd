extends RefCounted
## PathfindingRules on the fixture map: costs and range, terrain preference,
## roads, fog rules, blocked destinations, turn estimates, and the auto-march
## walker. The fixture map is the alpha..epsilon plains line with a mountain
## pass (zeta) arcing beta-zeta-delta and a forest (eta) behind it.


func test_reachable_costs_and_budget(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	var in_range := PathfindingRules.reachable(data, state, army_id, 2.0, false, {})
	t.check_near(float(in_range.get("beta", -1.0)), 1.0, 0.001, "one plains step costs 1")
	t.check_near(float(in_range.get("delta", -1.0)), 1.0, 0.001, "other direction too")
	t.check_near(float(in_range.get("epsilon", -1.0)), 2.0, 0.001, "two steps exactly spend the budget")
	t.check(not in_range.has("gamma"), "the region the army stands in is not listed")
	t.check(not in_range.has("alpha"), "a settlement we are at war with cannot be entered")
	t.check(not in_range.has("zeta"), "the mountain pass costs 3, beyond one turn")

	var forced := PathfindingRules.reachable(data, state, army_id, 2.0, true, {})
	t.check_near(float(forced.get("zeta", -1.0)), 3.0, 0.001, "forced march doubles the budget")
	t.check(not forced.has("eta"), "the forest behind the pass is beyond even a forced march")


func test_path_prefers_cheap_terrain(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(data, state)

	var route := PathfindingRules.best_path(data, state, army_id, "delta", false, {})
	t.check(route["reachable"], "delta is reachable from beta")
	t.check_eq(route["path"], ["gamma", "delta"], "the plains detour beats the mountain pass")
	t.check_near(float(route["cost"]), 2.0, 0.001, "two plains steps")
	t.check_eq(int(route["turns"]), 1, "arrives on current movement")
	t.check_eq(route["legs"].size(), 2, "one leg per entered region")
	t.check_near(float(route["legs"][0]["cost"]), 1.0, 0.001, "first leg costed")


func test_roads_cut_step_costs(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["beta"]["buildings"]["test_roads"] = 1
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	var in_range := PathfindingRules.reachable(data, state, army_id, 2.0, false, {})
	t.check_near(float(in_range.get("beta", -1.0)), 0.75, 0.001, "a road at the destination cuts the step cost")


func test_blocked_destination_routes_to_approach(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	var route := PathfindingRules.best_path(data, state, army_id, "alpha", false, {})
	t.check(route["blocked_destination"], "a hostile settlement is a blocked destination")
	t.check(route["reachable"], "but the army can march up to it")
	t.check_eq(route["path"], ["beta"], "the path stops on the approach region")

	var at_gates := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(data, state)
	var standing := PathfindingRules.best_path(data, state, at_gates, "alpha", false, {})
	t.check(standing["blocked_destination"], "still blocked from its own doorstep")
	t.check(not standing["reachable"], "and there is nothing left to march")
	t.check_eq(standing["path"], [], "no legs when already on the approach")


func test_unreachable_and_unknown_destinations(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	Fixtures.add_army(state, "blue", "delta", ["test_mob"])
	MovementRules.reset_movement(data, state)

	t.check(not PathfindingRules.best_path(data, state, army_id, "atlantis", false, {})["reachable"],
		"unknown region ids are not reachable")

	# With the corridor's hostile army VISIBLE, epsilon's only approach dies.
	var route := PathfindingRules.best_path(data, state, army_id, "epsilon", false, {"delta": true})
	t.check(not route["reachable"], "a seen hostile army closes the only corridor")
	t.check(not route["blocked_destination"], "epsilon itself would welcome us")


func test_hidden_armies_do_not_bend_paths(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	Fixtures.add_army(state, "blue", "delta", ["test_mob"])
	MovementRules.reset_movement(data, state)

	# delta is NOT in the visible set: the preview must walk straight through,
	# or the route itself would betray an army fog hides.
	var route := PathfindingRules.best_path(data, state, army_id, "epsilon", false, {})
	t.check(route["reachable"], "path ignores what fog hides")
	t.check_eq(route["path"], ["delta", "epsilon"], "straight through the hidden army")


func test_tie_breaks_and_save_round_trip_agree(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	# beta-zeta and delta-zeta tie at cost 3; sorted iteration must always
	# pick beta as the parent.
	var live := PathfindingRules.best_path(data, state, army_id, "zeta", true, {})
	t.check_eq(live["path"], ["beta", "zeta"], "equal-cost tie resolves to the sorted-first parent")

	var reloaded: Dictionary = JSON.parse_string(JSON.stringify(state))
	var replay := PathfindingRules.best_path(data, reloaded, army_id, "zeta", true, {})
	t.check_eq(replay["path"], live["path"], "a JSON round trip replays the same route")
	t.check_near(float(replay["cost"]), float(live["cost"]), 0.001, "and the same cost")


func test_estimated_turns_mirror_movement_math(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	Fixtures.add_character(state, "red", "guide", {"trait_points": {"test_pathfinder": 1}, "location": "gamma"})
	state["armies"][army_id]["general"] = "guide"
	MovementRules.reset_movement(data, state)
	t.check_near(float(state["armies"][army_id]["movement_left"]), 2.5, 0.001, "pathfinder general adds movement")

	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, 2.5, false), 1, "fits current movement")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, 2.6, false), 2, "a hair over rolls to next turn")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, 7.6, false), 4, "long hauls add whole turns")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, 5.0, true), 1, "forced march doubles what fits now")


func test_advance_march_walks_and_resumes(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	state["armies"][army_id]["march_path"] = ["beta", "zeta", "eta"]
	state["armies"][army_id]["march_forced"] = false

	var first := PathfindingRules.advance_march(data, state, army_id)
	t.check_eq(state["armies"][army_id]["region"], "beta", "first leg walked")
	t.check_eq(int(first["steps"]), 1, "the pass costs more than the points left")
	t.check(not first["arrived"] and not first["halted"], "order held for next turn")

	MovementRules.reset_movement(data, state)
	PathfindingRules.advance_march(data, state, army_id)
	t.check_eq(state["armies"][army_id]["region"], "zeta", "second turn crosses the pass")

	MovementRules.reset_movement(data, state)
	var last := PathfindingRules.advance_march(data, state, army_id)
	t.check_eq(state["armies"][army_id]["region"], "eta", "third turn enters the forest")
	t.check(last["arrived"], "march reported complete")
	t.check(not state["armies"][army_id].has("march_path"), "order cleared on arrival")

	t.check(PathfindingRules.advance_march(data, state, army_id).is_empty(), "no order, no report")


func test_advance_march_halts_when_blocked(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(data, state)

	var stances_before: Dictionary = state["factions"]["red"]["diplomacy"].duplicate()
	state["armies"][army_id]["march_path"] = ["alpha"]
	state["armies"][army_id]["march_forced"] = false
	var report := PathfindingRules.advance_march(data, state, army_id)
	t.check(report["halted"], "a war-held settlement halts the march")
	t.check_eq(state["armies"][army_id]["region"], "beta", "the army stands its ground")
	t.check(not state["armies"][army_id].has("march_path"), "the dead order is discarded")
	for other_faction in stances_before:
		t.check_eq(state["factions"]["red"]["diplomacy"][other_faction], stances_before[other_faction],
			"auto-march never touches the stance with " + String(other_faction))
