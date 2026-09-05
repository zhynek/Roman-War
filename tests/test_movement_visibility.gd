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


func test_fog_on_fixture_map(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var visible := VisibilityRules.visible_regions(data, state, "red")
	t.check(visible.has("beta") and visible.has("epsilon"), "own regions visible")
	t.check(visible.has("alpha") and visible.has("gamma") and visible.has("delta"),
		"one-hop scouting from holdings")

	var blue_visible := VisibilityRules.visible_regions(data, state, "blue")
	t.check(not blue_visible.has("gamma"), "blue cannot see two hops out")


func _facade(data: GameData, state: Dictionary) -> Game:
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	return game


func test_attack_needs_movement_and_ends_the_turn(t) -> void:
	## The player's attacks cost the season: an army that has marched itself
	## out cannot attack, and no army fights twice in one turn.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _facade(data, state)
	var attacker := Fixtures.add_army(state, "red", "beta",
		["test_spears", "test_spears", "test_spears", "test_spears"])
	var defender := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	state["armies"][attacker]["movement_left"] = 0.0
	t.check(game.attack_army(attacker, defender).is_empty(), "an army that has marched itself out cannot attack")
	t.check(MovementRules.targets_for(data, state, attacker).is_empty(), "and has no targets to show")
	state["armies"][attacker]["movement_left"] = 2.0
	t.check_eq(MovementRules.targets_for(data, state, attacker).get("alpha", ""), "attack", "with movement the enemy is a target")
	var result := game.attack_army(attacker, defender)
	t.check(not result.is_empty(), "with movement the attack resolves")
	if state["armies"].has(attacker):
		t.check_near(float(state["armies"][attacker]["movement_left"]), 0.0, 0.0001,
			"a battle takes the rest of the season, won or lost")
		var second := Fixtures.add_army(state, "blue", state["armies"][attacker]["region"], ["test_mob"])
		t.check(game.attack_army(attacker, second).is_empty(), "no army fights twice in one turn")


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


func test_reachable_regions_through_the_facade(t) -> void:
	## The rings the map draws: where the army gets this season, where only a
	## forced march reaches, and what bars the way — through the owner's fog.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _facade(data, state)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)
	var plan := game.reachable_regions(army_id)
	t.check(plan["reach"].has("delta") and plan["reach"].has("epsilon"), "two plains steps within two points")
	t.check_near(float(plan["reach"]["epsilon"]["cost"]), 2.0, 0.0001, "cost accumulates along the path")
	t.check(not plan["reach"]["epsilon"]["forced"], "within the plain budget")
	t.check(plan["reach"].has("eta") and plan["reach"]["eta"]["forced"], "the forest beyond takes a forced march")
	t.check(plan["reach"].has("beta"), "our own city is reachable")
	t.check_eq(plan["blocked"].get("alpha", ""), "hostile_settlement", "the enemy city blocks and is reported")
	t.check(not plan["reach"].has("alpha"), "a blocked region is never reachable")
	state["armies"][army_id]["movement_left"] = 0.0
	t.check(game.reachable_regions(army_id)["reach"].is_empty(), "no movement, nowhere to go")
	t.check(game.reachable_regions("army_999")["reach"].is_empty(), "an unknown army reaches nothing")


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
		if army["owner"] == "julii" and army["general"] != null \
				and game.state["settlements"].get(army["region"], {}).get("owner", "") == "julii":
			army_id = candidate
			break
	t.check(army_id != "", "the Julii field a led army in one of their cities")
	if army_id == "":
		return
	var army: Dictionary = game.state["armies"][army_id]
	var home: String = army["region"]
	SettlementRules.refresh_governors(game.data, game.state)
	t.check_eq(game.state["settlements"][home]["governor"], army["general"], "the general governs where he stands")
	var destination := ""
	for neighbor in game.data.regions[home].get("adjacent", []):
		if MovementRules.can_enter(game.data, game.state, army_id, neighbor):
			destination = neighbor
			break
	t.check(destination != "", "a road out of the city is open")
	if destination == "":
		return
	t.check(game.move_army(army_id, destination), "he marches out")
	t.check(game.state["settlements"][home]["governor"] != army["general"], "and the seat falls vacant this turn")


func test_peace_lifts_a_siege_and_starving_waits_for_an_assault_window(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(9)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege laid")

	# A village holds two turns and equipment takes two: the second end turn
	# readies the equipment but must NOT starve the city yet.
	SiegeRules.advance_sieges(data, state, rng, resolver)
	var events := SiegeRules.advance_sieges(data, state, rng, resolver)
	t.check(state["settlements"]["alpha"]["siege"] != null, "the siege stands after two turns")
	t.check(state["settlements"]["alpha"]["siege"]["equipment_ready"], "equipment is ready")
	t.check(events.is_empty(), "no starve-out on the turn the equipment came ready")
	t.check_eq(state["settlements"]["alpha"]["owner"], "blue", "the city is still theirs — the besieger gets his assault turn")

	# Peace lifts the siege before it can be decided.
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	t.check(SiegeRules.assault(data, state, rng, resolver, army_id, "alpha").is_empty(), "no assault on a city we are at peace with")
	SiegeRules.advance_sieges(data, state, rng, resolver)
	t.check(state["settlements"]["alpha"]["siege"] == null, "peace lifts the siege")
