extends RefCounted
## Movement points, terrain costs, hostile-region blocking, and fog of war on
## the synthetic fixture map.


func test_movement_costs_and_range(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	t.check(MovementRules.move_army(data, state, army_id, "delta"), "first step within budget")
	t.check(MovementRules.move_army(data, state, army_id, "epsilon"), "second step within budget")
	t.check(not MovementRules.move_army(data, state, army_id, "delta"), "movement points exhausted")


func test_forced_march_stretches_range(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	t.check(MovementRules.move_army(data, state, army_id, "delta"), "first step within budget")
	t.check(MovementRules.move_army(data, state, army_id, "epsilon", true), "forced march stretches the budget")
	t.check(MovementRules.move_army(data, state, army_id, "delta", true), "three steps on two points, at a price")
	t.check(state["armies"][army_id]["forced_march"], "army marked fatigued")


func test_cannot_walk_into_enemy_settlement(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(not MovementRules.move_army(data, state, army_id, "alpha"),
		"hostile settlements demand a siege, not a stroll")


func test_siege_and_starve(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(4)
	var army_id := Fixtures.add_army(state, "red", "beta",
		["test_spears", "test_spears", "test_spears", "test_spears"])
	MovementRules.reset_movement(data, state)

	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege begins")
	t.check_eq(state["armies"][army_id]["region"], "alpha", "besieger camps at the walls")
	t.check(SiegeRules.assault(data, state, rng, resolver, army_id, "alpha").is_empty(),
		"no assault without equipment")

	var captured := false
	for i in range(12):
		for event in SiegeRules.advance_sieges(data, state, rng, resolver):
			if event["result"].get("captured", false):
				CombatRules.capture_settlement(data, state, rng, event["region"],
					event["result"]["capture_pending_owner"], "occupy")
				captured = true
		if captured or not state["armies"].has(army_id):
			break
	if state["armies"].has(army_id):
		t.check(captured and state["settlements"]["alpha"]["owner"] == "red",
			"starving garrison falls to the surviving besieger")


func test_attack_needs_movement_and_ends_the_turn(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(3)
	var attacker := Fixtures.add_army(state, "red", "beta",
		["test_spears", "test_spears", "test_spears", "test_spears"])
	var defender := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	state["armies"][attacker]["movement_left"] = 0.0
	t.check(CombatRules.attack_army(data, state, resolver, rng, attacker, defender).is_empty(),
		"an army that has marched itself out cannot attack")
	state["armies"][attacker]["movement_left"] = 2.0
	var result := CombatRules.attack_army(data, state, resolver, rng, attacker, defender)
	t.check(not result.is_empty(), "with movement the attack resolves")
	t.check_near(float(state["armies"][attacker]["movement_left"]), 0.0, 0.0001,
		"a battle takes the rest of the season, won or lost")
	var second := Fixtures.add_army(state, "blue", "beta", ["test_mob"])
	t.check(CombatRules.attack_army(data, state, resolver, rng, attacker, second).is_empty(),
		"no army fights twice in one turn")


func test_siege_costs_movement_and_respects_relief_armies(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	state["armies"][army_id]["movement_left"] = 0.0
	t.check(not SiegeRules.begin_siege(data, state, army_id, "alpha"), "no movement, no siege — never a free hop")
	MovementRules.reset_movement(data, state)
	var relief := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	t.check(not SiegeRules.begin_siege(data, state, army_id, "alpha"), "a relieving army must be beaten first")
	state["armies"].erase(relief)
	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege laid once the road is clear")
	t.check_near(float(state["armies"][army_id]["movement_left"]), 0.0, 0.0001, "investing takes the turn")

	# Marching away lifts the siege at once, not at the end of the turn.
	MovementRules.reset_movement(data, state)
	t.check(MovementRules.move_army(data, state, army_id, "beta"), "the besieger marches off")
	t.check(state["settlements"]["alpha"]["siege"] == null, "the siege is released immediately")


func test_reachable_and_multi_step_march(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	var plan := MovementRules.reachable(data, state, army_id)
	t.check(plan["reach"].has("delta") and plan["reach"].has("epsilon"), "two plains steps within two points")
	t.check_near(float(plan["reach"]["epsilon"]["cost"]), 2.0, 0.0001, "cost accumulates along the path")
	t.check_eq(plan["reach"]["epsilon"]["via"], "delta", "the path is remembered")
	t.check(not plan["reach"]["epsilon"]["forced"], "within the plain budget")
	t.check(plan["reach"].has("beta"), "our own city is reachable")
	t.check_eq(plan["blocked"].get("alpha", ""), "hostile_settlement", "the enemy city blocks and is reported")
	t.check(not plan["reach"].has("alpha"), "a blocked region is never reachable")

	var result := MovementRules.march(data, state, army_id, "epsilon")
	t.check(result["arrived"], "the column arrives")
	t.check_eq(result["path"], ["delta", "epsilon"], "two steps walked")
	t.check_eq(state["armies"][army_id]["region"], "epsilon", "army stands at the destination")
	t.check_near(float(state["armies"][army_id]["movement_left"]), 0.0, 0.0001, "budget spent")


func test_forced_march_is_taken_only_where_needed(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(data, state)
	# beta -> gamma -> delta -> epsilon costs 3.0: beyond two points, within a forced four.
	var plan := MovementRules.reachable(data, state, army_id)
	t.check(plan["reach"]["epsilon"]["forced"], "three steps need a forced march")
	var refused := MovementRules.march(data, state, army_id, "epsilon")
	t.check_eq(refused["reason"], "needs_forced_march", "without Shift the march is refused, not shortened")
	t.check_eq(state["armies"][army_id]["region"], "beta", "and nobody moved")
	var forced := MovementRules.march(data, state, army_id, "epsilon", true)
	t.check(forced["arrived"], "forced, it arrives")
	t.check(state["armies"][army_id]["forced_march"], "and the men are weary")

	# A destination within the plain budget never tires the men, Shift or not.
	MovementRules.reset_movement(data, state)
	MovementRules.march(data, state, army_id, "delta", true)
	t.check(not state["armies"][army_id]["forced_march"], "a short march with Shift held is still a plain march")


func test_march_halts_on_an_army_the_fog_hid(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# Take epsilon from red: with the army at beta, delta is two hops out and
	# beyond red's sight.
	state["settlements"]["epsilon"]["owner"] = "rebels"
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	Fixtures.add_army(state, "blue", "delta", ["test_mob"])
	MovementRules.reset_movement(data, state)
	var visible := VisibilityRules.visible_regions(data, state, "red")
	t.check(not visible.has("delta"), "delta is beyond red's sight")

	var plan := MovementRules.reachable(data, state, army_id, visible)
	t.check(plan["reach"].has("delta"), "a fogged region is planned as passable — highlights leak nothing")
	var omniscient := MovementRules.reachable(data, state, army_id)
	t.check_eq(omniscient["blocked"].get("delta", ""), "hostile_army", "omniscient planning sees the ambush")

	var result := MovementRules.march(data, state, army_id, "delta")
	t.check(not result["arrived"], "the column never reaches delta")
	t.check_eq(result["path"], ["gamma"], "it walked as far as gamma")
	t.check_eq(result["stopped_at"], "gamma", "and halted there on contact")
	t.check_eq(result["reason"], "hostile_army", "saying why")
	t.check_eq(state["armies"][army_id]["region"], "gamma", "the army stands at gamma")


func test_targets_and_fleet_sailing(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	Fixtures.add_army(state, "blue", "gamma", ["test_mob"])
	MovementRules.reset_movement(data, state)
	var targets := MovementRules.targets_for(data, state, army_id)
	t.check_eq(targets.get("gamma", ""), "attack", "an adjacent hostile army is a target")
	t.check_eq(targets.get("alpha", ""), "siege", "an adjacent at-war city can be invested")
	state["armies"][army_id]["movement_left"] = 0.0
	t.check(MovementRules.targets_for(data, state, army_id).is_empty(), "no movement, no targets")

	var fleet_id := Fixtures.add_fleet(state, "red", "test_sea", ["test_galley"])
	var reach := MovementRules.fleet_reachable(data, state, fleet_id)
	t.check(reach.has("test_sea_2") and reach.has("test_sea_3"), "two lanes on two points")
	t.check_eq(reach["test_sea_3"]["via"], "test_sea_2", "the route is remembered")
	var voyage := MovementRules.sail(data, state, fleet_id, "test_sea_3")
	t.check(voyage["arrived"], "the fleet arrives two seas over")
	t.check_eq(state["fleets"][fleet_id]["sea_zone"], "test_sea_3", "fleet zone updated")
	t.check_near(float(state["fleets"][fleet_id]["movement_left"]), 0.0, 0.0001, "both lanes paid")


func test_governorship_follows_the_general_within_the_turn(t) -> void:
	## A general who marches out of his city stops governing it at once —
	## the panel must not show a governor who has left.
	var game := Game.new_campaign("julii", 42)
	var army_id := ""
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for candidate in army_ids:
		var army: Dictionary = game.state["armies"][candidate]
		if army["owner"] == "julii" and army["general"] != null:
			army_id = candidate
			break
	t.check(army_id != "", "the Julii field a led army")
	if army_id == "":
		return
	var army: Dictionary = game.state["armies"][army_id]
	var home: String = army["region"]
	t.check_eq(game.state["settlements"][home]["governor"], army["general"], "the general governs where he stands")
	var destination := ""
	for neighbor in game.data.regions[home].get("adjacent", []):
		if MovementRules.can_enter(game.data, game.state, army_id, neighbor):
			destination = neighbor
			break
	t.check(game.march_army(army_id, destination)["arrived"], "he marches out")
	t.check(game.state["settlements"][home]["governor"] != army["general"], "and the seat falls vacant this turn")


func test_fog_on_fixture_map(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var visible := VisibilityRules.visible_regions(data, state, "red")
	t.check(visible.has("beta") and visible.has("epsilon"), "own regions visible")
	t.check(visible.has("alpha") and visible.has("gamma") and visible.has("delta"),
		"one-hop scouting from holdings")

	var blue_visible := VisibilityRules.visible_regions(data, state, "blue")
	t.check(not blue_visible.has("gamma"), "blue cannot see two hops out")
