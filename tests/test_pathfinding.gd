extends RefCounted
## PathfindingRules: terrain-priced routes, budget-bounded reach, blocked
## destinations, hidden-army previews, and queued marches — all on the
## fixture map, whose mountain pass (alpha-zeta-eta-epsilon, cost 4.5) is one
## hop shorter but strictly dearer than the plains line (cost 4.0).


func test_step_costs_price_terrain(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check_eq(MovementRules.step_cost(data, state, "gamma"), 1.0, "plains step costs 1.0")
	t.check_eq(MovementRules.step_cost(data, state, "zeta"), 2.0, "mountain step costs 2.0")
	t.check_eq(MovementRules.step_cost(data, state, "eta"), 1.5, "forest step costs 1.5")


func test_roads_discount_the_step(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.chains["test_roads"] = {
		"id": "test_roads", "kind": "roads", "cultures": ["roman"], "name": "Roads",
		"levels": [{"id": "road_1", "name": "Graded Way", "min_settlement_level": "village",
			"cost": 300, "build_turns": 1, "effects": {"road_level": 1}, "description": ""}],
	}
	state["settlements"]["beta"]["buildings"]["test_roads"] = 1
	t.check_eq(MovementRules.step_cost(data, state, "beta"), 0.75,
		"a tier-1 road cuts the destination step to three quarters")


func test_best_path_prefers_the_cheap_route(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "alpha", ["test_spears"])
	var found := PathfindingRules.best_path(data, state, army_id, "epsilon")
	t.check_eq(found["path"], ["beta", "gamma", "delta", "epsilon"],
		"the plains line beats the shorter-in-hops mountain pass")
	t.check_eq(found["cost"], 4.0, "four plains steps")
	t.check_eq(found["legs"].size(), 4, "one leg per step")
	t.check_eq(found["turns"], 2, "two points a turn arrives on the second")
	t.check(not found["blocked_destination"], "an open destination is not blocked")


func test_reachable_respects_budget_and_forced_march(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "alpha", ["test_spears"])
	var normal := PathfindingRules.reachable(data, state, army_id)
	t.check_eq(normal.size(), 3, "two points reach beta, gamma and the pass mouth")
	t.check_eq(normal.get("beta", -1.0), 1.0, "one step down the line")
	t.check_eq(normal.get("gamma", -1.0), 2.0, "two steps down the line")
	t.check_eq(normal.get("zeta", -1.0), 2.0, "the mountain crossing swallows both points")
	var forced := PathfindingRules.reachable(data, state, army_id, -1.0, true)
	t.check_eq(forced.get("epsilon", -1.0), 4.0, "forced march doubles the day's reach")
	t.check_eq(forced.get("eta", -1.0), 3.5, "the pass opens under forced march")


func test_blocked_destination_halts_beside_it(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	var found := PathfindingRules.best_path(data, state, army_id, "alpha")
	t.check(found["blocked_destination"], "an at-war settlement cannot be marched into")
	t.check_eq(found["path"], ["beta"], "the column halts in the region beside it")
	t.check_eq(found["cost"], 1.0, "priced to the halt, not the target")


func test_hidden_armies_do_not_bend_the_preview(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	Fixtures.add_army(state, "blue", "gamma", ["test_mob"])

	# Full knowledge: the hostile column bars gamma and alpha is at war, so
	# nothing leads toward delta at all.
	t.check_eq(PathfindingRules.best_path(data, state, army_id, "delta"), {},
		"with everything known the way is shut")
	t.check_eq(PathfindingRules.reachable(data, state, army_id).size(), 0,
		"nowhere legal to step")

	# Through the fog: a preview that cannot see gamma must plot straight
	# through it rather than leak the ambush by swerving.
	var seen := {"beta": true}
	var preview := PathfindingRules.best_path(data, state, army_id, "delta", seen)
	t.check_eq(preview["path"], ["gamma", "delta"], "the unseen army does not bend the route")

	# Executing that march then halts against reality without declaring war.
	var army: Dictionary = state["armies"][army_id]
	army["march_path"] = preview["path"].duplicate()
	army["march_forced"] = false
	var outcome := PathfindingRules.advance_march(data, state, army_id)
	t.check_eq(outcome["moved"], 0, "the column never enters the held region")
	t.check(outcome["halted"], "the march is cancelled")
	t.check(not state["armies"][army_id].has("march_path"), "the cancelled path is cleared")
	t.check_eq(state["armies"][army_id]["region"], "beta", "the army stands where it was")


func test_advance_march_spends_turns(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "alpha", ["test_spears"])
	var army: Dictionary = state["armies"][army_id]
	army["march_path"] = ["beta", "gamma", "delta", "epsilon"]
	army["march_forced"] = false

	var first_turn := PathfindingRules.advance_march(data, state, army_id)
	t.check_eq(first_turn["moved"], 2, "two plains steps on two points")
	t.check(not first_turn["arrived"] and not first_turn["halted"], "the march continues")
	t.check_eq(army["march_path"], ["delta", "epsilon"], "the remaining road is queued")

	MovementRules.reset_movement(data, state)
	var second_turn := PathfindingRules.advance_march(data, state, army_id)
	t.check(second_turn["arrived"], "a fresh turn completes the march")
	t.check_eq(army["region"], "epsilon", "the army arrived")
	t.check(not army.has("march_path") and not army.has("march_forced"),
		"an arrived march leaves no queue behind")


func test_estimated_turns_mirrors_the_budget(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "alpha", ["test_spears"])
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, 2.0), 1,
		"this turn's points cover it")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, 2.5), 2,
		"a half step over spills into next turn")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, 6.1), 4,
		"long roads count full turns")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, 4.0, true), 1,
		"forced march doubles the first day too")

	Fixtures.add_character(state, "red", "guide", {"trait_points": {"test_pathfinder": 1}, "location": "alpha"})
	state["armies"][army_id]["general"] = "guide"
	MovementRules.reset_movement(data, state)
	t.check_eq(state["armies"][army_id]["movement_left"], 2.5, "a pathfinder general adds half a step")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, 4.5), 2,
		"2.5 now and 2.5 next turn covers 4.5")


func test_march_army_respects_the_owners_fog(t) -> void:
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	var army_id := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	Fixtures.add_army(game.state, "blue", "gamma", ["test_mob"])
	# Red holds beta, so gamma is scouted: the hostile column there is seen
	# and bars the road — nothing leads toward delta.
	t.check_eq(game.march_army(army_id, "delta"), {}, "a seen enemy shuts the road")
	t.check_eq(game.state["armies"][army_id]["region"], "beta", "no step was taken")


func test_halt_march_clears_the_queue(t) -> void:
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	var army_id := Fixtures.add_army(game.state, "red", "alpha", ["test_spears"])
	var outcome := game.march_army(army_id, "epsilon")
	t.check_eq(outcome["moved"], 2, "the first day covers two plains steps")
	t.check(not outcome["arrived"], "epsilon is another day away")
	t.check_eq(outcome["turns"], 2, "quoted as a two-turn march")
	t.check(game.state["armies"][army_id].has("march_path"), "the rest is queued")
	t.check(game.halt_march(army_id), "a queued march can be recalled")
	t.check(not game.state["armies"][army_id].has("march_path"), "the queue is gone")
	t.check(not game.halt_march(army_id), "nothing left to recall")


func test_marches_resume_across_turns_and_saves(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var army_id := ""
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for candidate in army_ids:
		if game.state["armies"][candidate]["owner"] == "julii":
			army_id = candidate
			break
	t.check(army_id != "", "julii fields an army")

	# The nearest destination that takes more than one turn to reach.
	var target := ""
	var region_ids: Array = game.data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		var preview := game.army_path_preview(army_id, region_id)
		if preview.is_empty() or preview["blocked_destination"]:
			continue
		if preview["turns"] >= 2 and float(preview["cost"]) <= 6.0:
			target = region_id
			break
	t.check(target != "", "a multi-turn target exists")
	if target == "":
		return

	var outcome := game.march_army(army_id, target)
	t.check(int(outcome["moved"]) >= 1, "the column sets out at once")
	t.check(not outcome["arrived"], "a multi-turn march does not arrive on day one")
	t.check(game.state["armies"][army_id].has("march_path"), "the road ahead is queued")

	# A save taken mid-march must continue in lockstep with the live game.
	var save_path := "user://test_march_save.json"
	t.check(game.save_to(save_path), "mid-march save written")
	var twin := Game.new()
	twin.data = game.data
	twin.resolver = AutoResolver.new()
	t.check(twin.load_from(save_path), "mid-march save loads")

	var report := game.end_turn()
	twin.end_turn()
	var continued := false
	for march in report["marches"]:
		if march["army"] == army_id:
			continued = true
	t.check(continued, "the turn report records the resumed march")
	# Canonical JSON, as test_campaign_integration compares states: a parsed
	# save holds sorted keys and floats where the live game holds ints.
	t.check_eq(_canonical(game.state["armies"]), _canonical(twin.state["armies"]),
		"the loaded twin marches in lockstep")
	t.check_eq(game.state["rng_state"], twin.state["rng_state"],
		"march continuation draws no randomness")

	for i in range(5):
		if not game.state["armies"].has(army_id):
			break
		if not game.state["armies"][army_id].has("march_path"):
			break
		game.end_turn()
	if game.state["armies"].has(army_id):
		t.check(not game.state["armies"][army_id].has("march_path"),
			"the march ends within its estimate")


func _canonical(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))


func test_paths_are_deterministic_whatever_the_dict_order(t) -> void:
	## Two equal-cost routes around a diamond must resolve identically however
	## the region dictionary happens to be ordered (a JSON round-trip reorders
	## dictionaries).
	var balance: Dictionary = Fixtures.data().balance
	for flipped in [false, true]:
		var data := GameData.new()
		data.balance = balance
		var ids := ["apex", "left", "right", "foot"] if not flipped else ["foot", "right", "left", "apex"]
		for region_id in ids:
			data.regions[region_id] = {"id": region_id, "terrain": "plains", "adjacent": [], "sea_zones": []}
		data.regions["apex"]["adjacent"] = ["left", "right"]
		data.regions["left"]["adjacent"] = ["apex", "foot"]
		data.regions["right"]["adjacent"] = ["apex", "foot"]
		data.regions["foot"]["adjacent"] = ["left", "right"]
		var state := {
			"factions": {"red": {"diplomacy": {}}},
			"settlements": {}, "characters": {},
			"armies": {"army_1": {"owner": "red", "region": "apex", "units": [],
				"general": null, "movement_left": 2.0, "forced_march": false}},
		}
		var found := PathfindingRules.best_path(data, state, "army_1", "foot")
		t.check_eq(found["path"], ["left", "foot"],
			"ties break lexicographically (order flipped: %s)" % flipped)
