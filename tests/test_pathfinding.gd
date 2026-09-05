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
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, _legs([1.0, 1.0])), 1,
		"this turn's points cover it")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, _legs([1.0, 1.0, 0.5])), 2,
		"a half step over spills into next turn")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, _legs([2.0, 2.0, 2.0, 0.1])), 4,
		"long roads count full turns")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, _legs([2.0, 2.0]), true), 1,
		"forced march doubles the first day too")
	# The estimate walks legs the way marching spends them: on a forest chain
	# a two-point army wastes half a point every turn, and the quote says so.
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, _legs([1.5, 1.5, 1.5, 1.5])), 4,
		"wasted remainders count — four forest steps take four turns")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, _legs([2.5])), -1,
		"a leg no full turn could pay for is called out")

	Fixtures.add_character(state, "red", "guide", {"trait_points": {"test_pathfinder": 1}, "location": "alpha"})
	state["armies"][army_id]["general"] = "guide"
	MovementRules.reset_movement(data, state)
	t.check_eq(state["armies"][army_id]["movement_left"], 2.5, "a pathfinder general adds half a step")
	t.check_eq(PathfindingRules.estimated_turns(data, state, army_id, _legs([2.0, 2.0, 0.5])), 2,
		"2.5 now and 2.5 next turn covers 4.5")


func _legs(costs: Array) -> Array:
	var legs: Array = []
	for cost in costs:
		legs.append({"region": "x", "cost": cost})
	return legs


func test_hidden_settlements_do_not_bend_the_preview(t) -> void:
	## Settlement allegiance is hidden information too: an unexplored at-war
	## settlement must not bend a route or mark a destination as barred —
	## that would paint the political map through the fog.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	# Full knowledge: blue's alpha blocks and the path halts beside it.
	var known := PathfindingRules.best_path(data, state, army_id, "alpha")
	t.check(known["blocked_destination"], "a seen at-war settlement bars the gate")
	# Through fog that hides alpha: the preview walks straight in.
	var seen := {"gamma": true, "beta": true}
	var fogged := PathfindingRules.best_path(data, state, army_id, "alpha", seen)
	t.check(not fogged["blocked_destination"], "an unseen allegiance is not revealed")
	t.check_eq(fogged["path"], ["beta", "alpha"], "the route is not bent around the fog")
	# Reach shows the fogged region as enterable, for the same reason.
	var reach := PathfindingRules.reachable(data, state, army_id, -1.0, false, seen)
	t.check(reach.has("alpha"), "the range overlay does not leak allegiance either")


func test_steps_no_turn_could_pay_are_never_offered(t) -> void:
	## A slowed army must not be quoted a route through a mountain step it
	## can never afford — the preview and the march must agree.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "alpha", ["test_spears"])
	Fixtures.add_character(state, "red", "laggard", {"location": "alpha"})
	state["characters"]["laggard"]["trait_points"] = {}
	state["armies"][army_id]["general"] = "laggard"
	# Shrink the army to 1.5 points a turn by trimming the base directly.
	var old_base = data.balance["movement"]["base_movement_points"]
	data.balance["movement"]["base_movement_points"] = 1.5
	state["armies"][army_id]["movement_left"] = 1.5
	# zeta is mountains (2.0): unreachable at 1.5 points a turn...
	t.check_eq(PathfindingRules.best_path(data, state, army_id, "zeta"), {},
		"no route is quoted through an unpayable step")
	# ...but a forced march (x2) opens it, and both agree again.
	var forced := PathfindingRules.best_path(data, state, army_id, "zeta", {}, true)
	t.check_eq(forced.get("path", []), ["zeta"], "forced march opens the pass")
	data.balance["movement"]["base_movement_points"] = old_base


func test_explicit_orders_cancel_a_queued_march(t) -> void:
	## A besieger must not walk away from its own siege because an old road
	## was still queued — any explicit order supersedes the march.
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	game.resolver = AutoResolver.new()
	var army_id := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	game.state["armies"][army_id]["movement_left"] = 0.0
	var outcome := game.march_army(army_id, "epsilon")
	t.check_eq(int(outcome["moved"]), 0, "no points today — the whole road is queued")
	t.check(game.state["armies"][army_id].has("march_path"), "the march is queued")
	# A siege from next door pays the step like any march, so the points come back first.
	game.state["armies"][army_id]["movement_left"] = 2.0
	t.check(game.besiege(army_id, "alpha"), "the army can lay siege from here")
	t.check(not game.state["armies"][army_id].has("march_path"),
		"laying siege cancels the queued march")

	# And a plain manual move does too.
	var walker := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	game.state["armies"][walker]["movement_left"] = 0.0
	game.march_army(walker, "epsilon")
	t.check(game.state["armies"][walker].has("march_path"), "second march queued")
	game.state["armies"][walker]["movement_left"] = 2.0
	t.check(game.move_army(walker, "gamma"), "a manual step is taken")
	t.check(not game.state["armies"][walker].has("march_path"),
		"the manual order superseded the march")


func test_marching_at_a_barred_neighbor_reports_the_bar(t) -> void:
	## Already beside an at-war settlement: march_army has nothing to walk,
	## and says "barred", not "unreachable".
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	var army_id := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	var outcome := game.march_army(army_id, "alpha")
	t.check(not outcome.is_empty(), "the outcome names the problem")
	t.check(outcome.get("halted", false) and outcome.get("blocked_destination", false),
		"barred, not unreachable")
	t.check_eq(game.state["armies"][army_id]["region"], "beta", "no step was taken")


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


func test_a_besieger_never_marches_off_his_siege(t) -> void:
	## Game cancels queued marches on every hostile order; advance_march is
	## the backstop, so even a caller that forgets can never walk a besieger
	## away and silently dissolve the siege.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "alpha", ["test_spears"])
	state["settlements"]["alpha"]["siege"] = {"besieger": army_id, "turns": 1, "equipment_ready": false}
	state["armies"][army_id]["march_path"] = ["beta"]
	state["armies"][army_id]["march_forced"] = false
	MovementRules.reset_movement(data, state)

	var outcome := PathfindingRules.advance_march(data, state, army_id)
	t.check(outcome["halted"], "the stale order is reported halted")
	t.check_eq(state["armies"][army_id]["region"], "alpha", "the army holds the siege lines")
	t.check(not state["armies"][army_id].has("march_path"), "the dead order is discarded")
	t.check(state["settlements"]["alpha"]["siege"] != null, "the siege stands")


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
