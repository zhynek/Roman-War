extends RefCounted
## The adversarial review of the Phase 9 port: every loophole the reviewers
## reproduced, closed and pinned here — fatigue laundered through a garrison,
## ships docking for free by transfer, sieges laid past a not-yet-hostile
## relief army, assaults that cost no movement, armies slipping into an
## invested city, legacy ships marching in field armies, a merge lifting a
## siege, a bribe leaving a ghost siege, a ceded port's ships changing hands,
## the two raise paths, attacks as free hops, and the query surface answering
## for foreign forces.


class WinResolver:
	extends BattleResolver
	func resolve(_data: GameData, _rng: CampaignRng, _attacker_units: Array, _defender_units: Array, _context: Dictionary) -> Dictionary:
		return {"winner": "attacker", "attacker_casualty_pct": 0.0, "defender_casualty_pct": 0.0,
			"attacker_general_died": false, "defender_general_died": false, "experience_gained": 0}


func _game(data: GameData, state: Dictionary) -> Game:
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	return game


func _unit(template: String) -> Dictionary:
	return {"template": template, "experience": 0, "strength_pct": 100, "weapon": 0, "armor": 0}


func test_fatigue_marches_out_of_the_garrison_with_the_men(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _game(data, state)
	var army := Fixtures.add_army(state, "red", "gamma", ["test_spears", "test_spears"])
	t.check(game.move_army(army, "beta", true), "the column forced-marches home")
	t.check(state["armies"][army]["forced_march"], "and is weary")
	t.check(game.garrison_army(army), "it garrisons")
	t.check(state["settlements"]["beta"].get("muster_fatigued", false), "the garrison remembers the weariness")
	var raised := game.raise_units("beta", [0, 1])
	t.check(raised["ok"], "the same men are raised again")
	t.check(state["armies"][raised["army_id"]]["forced_march"], "still weary — no free doubled march before a battle")
	MovementRules.reset_movement(data, state)
	t.check(not state["settlements"]["beta"].has("muster_fatigued"), "the season's memory is forgotten at the reset")

	# Through a transfer too: tired men into the garrison, then into a fresh army.
	var second := Fixtures.state(data)
	var game2 := _game(data, second)
	var tired := Fixtures.add_army(second, "red", "gamma", ["test_spears"])
	var fresh := Fixtures.add_army(second, "red", "beta", ["test_spears"])
	t.check(game2.move_army(tired, "beta", true), "the tired column arrives")
	t.check(game2.transfer_units(tired, "garrison:beta", [0])["ok"], "its men drop into the garrison")
	t.check(game2.transfer_units("garrison:beta", fresh, [0])["ok"], "and into the fresh army")
	t.check(second["armies"][fresh]["forced_march"], "which is weary now too")


func test_ships_making_port_by_transfer_pay_the_lane(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _game(data, state)
	data.regions["epsilon"]["sea_zones"] = ["test_sea", "test_sea_2"]   # a port on two seas
	var f1 := Fixtures.add_fleet(state, "red", "test_sea", ["test_galley", "test_galley"])
	var f2 := Fixtures.add_fleet(state, "red", "test_sea_2", ["test_galley"])
	t.check(game.transfer_units(f1, "harbour:epsilon", [0, 1])["ok"], "ships make port by transfer")
	t.check_near(float(state["settlements"]["epsilon"]["muster_sail_left"]), 1.0, 0.001, "the harbour remembers the lane they spent")
	t.check(game.transfer_units("harbour:epsilon", f2, [0, 1])["ok"], "and out again into a fleet on the other sea")
	t.check_near(float(state["fleets"][f2]["movement_left"]), 1.0, 0.001, "which sails no further than the crossing left them")
	var spent := Fixtures.add_fleet(state, "red", "test_sea", ["test_galley"])
	state["fleets"][spent]["movement_left"] = 0.0
	t.check_eq(game.transfer_units(spent, "harbour:epsilon", [0])["error"], ForceRules.ERR_NO_MOVEMENT,
		"a fleet with no lane left cannot slip into port")


func test_a_relief_army_blocks_the_siege_whatever_the_stance(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	var relief := Fixtures.add_army(state, "blue", "alpha", ["test_mob", "test_mob"])
	var army := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	var game := _game(data, state)
	t.check(not game.besiege(army, "alpha"), "no siege past the city's own field army")
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "neutral", "and a refused order declares no war")
	state["armies"].erase(relief)
	t.check(game.besiege(army, "alpha"), "with the field army gone the walls can be invested")
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "war", "which is the declaration")


func test_an_assault_takes_the_season(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _game(data, state)
	game.resolver = WinResolver.new()
	var army := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	var enemy := Fixtures.add_army(state, "blue", "zeta", ["test_mob"])
	state["settlements"]["alpha"]["garrison"].append(_unit("test_mob"))
	t.check(SiegeRules.begin_siege(data, state, army, "alpha"), "the siege is laid")
	state["settlements"]["alpha"]["siege"]["equipment_ready"] = true
	t.check(game.assault_settlement(army, "alpha", "occupy").is_empty(), "no storm without movement")
	MovementRules.reset_movement(data, state)
	var result := game.assault_settlement(army, "alpha", "occupy")
	t.check(result.get("captured", false), "with the season's movement the city falls")
	t.check_near(float(state["armies"][army]["movement_left"]), 0.0, 0.0001, "and the season is spent")
	t.check(game.attack_army(army, enemy).is_empty(), "no second battle the same season")


func test_no_army_walks_into_an_invested_city(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _game(data, state)
	var besieger := Fixtures.add_army(state, "blue", "alpha", ["test_mob", "test_mob"])
	t.check(SiegeRules.begin_siege(data, state, besieger, "beta"), "blue invests beta")
	var relief := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	var before: int = state["settlements"]["beta"]["garrison"].size()
	t.check(not game.garrison_army(relief), "the relief army cannot slip past the siege lines")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), before, "the garrison is unchanged")
	t.check(state["armies"].has(relief), "the army stands outside")


func test_legacy_ships_in_armies_go_to_the_harbour_on_load(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army := Fixtures.add_army(state, "red", "beta", ["test_galley", "test_spears"])
	var only_ships := Fixtures.add_army(state, "red", "gamma", ["test_galley"])
	state["settlements"]["beta"].erase("harbour")
	NewGame.ensure_state_keys(state, data)
	t.check_eq(NavalRules.normalise(data, state), 2, "both ships are moved")
	t.check_eq(state["armies"][army]["units"].size(), 1, "the column keeps its foot soldiers")
	t.check(not state["armies"].has(only_ships), "an army of nothing but ships dissolves")
	# beta is landlocked in the fixture: the ships sail for red's port, epsilon.
	t.check_eq(NavalRules.harbour_of(state, "epsilon").size(), 2, "the ships wait in the owner's nearest port")
	t.check_eq(NavalRules.normalise(data, state), 0, "and a second pass moves nothing")


func test_a_merge_hands_the_siege_to_the_army_that_stays(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _game(data, state)
	var besieger := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	t.check(SiegeRules.begin_siege(data, state, besieger, "alpha"), "the siege is laid")
	state["settlements"]["alpha"]["siege"]["turns"] = 1
	var reinforcements := Fixtures.add_army(state, "red", "alpha", ["test_spears", "test_spears"])
	t.check(game.merge_armies(besieger, reinforcements)["ok"], "the besieger merges into the reinforcements")
	var siege = state["settlements"]["alpha"]["siege"]
	t.check(siege != null and siege["besieger"] == reinforcements, "which now hold the siege")
	t.check_eq(int(siege["turns"]), 1, "with its clock intact")


func test_a_bribed_besieger_lifts_the_siege(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var band := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	t.check(SiegeRules.begin_siege(data, state, band, "beta"), "the band invests beta")
	var agent_id := AgentRules.recruit_agent(data, state, "beta", "diplomat")
	t.check(agent_id != "", "a diplomat is hired")
	t.check(AgentRules.bribe_army(data, state, agent_id, band)["success"], "the band takes the coin")
	t.check(state["settlements"]["beta"]["siege"] == null, "and the siege is lifted with it")


func test_a_ceded_ports_ships_sail_for_the_owners_other_port(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.regions["beta"]["sea_zones"] = ["test_sea"]   # the refuge has a coast
	var harbour := NavalRules.harbour_of(state, "epsilon")
	for i in range(2):
		harbour.append(_unit("test_galley"))
	DiplomacyRules.cede_region(data, state, "epsilon", "blue")
	t.check_eq(state["settlements"]["epsilon"]["owner"], "blue", "the port changes hands")
	t.check(NavalRules.harbour_of(state, "epsilon").is_empty(), "with an empty harbour")
	t.check_eq(NavalRules.harbour_of(state, "beta").size(), 2, "the ships wait in red's other port")


func test_the_whole_garrison_raise_marches_like_the_ticked_one(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _game(data, state)
	for i in range(3):
		state["settlements"]["beta"]["garrison"].append(_unit("test_spears"))
	var army_id := game.raise_army("beta")
	t.check(army_id != "" and state["armies"].has(army_id), "the garrison marches out")
	if army_id != "":
		var army: Dictionary = state["armies"][army_id]
		t.check_near(float(army["movement_left"]), MovementRules.movement_points_for(data, state, army), 0.001,
			"with the season's full march, like a ticked raise")


func test_an_attack_across_the_border_pays_the_step(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _game(data, state)
	var army := Fixtures.add_army(state, "red", "alpha", ["test_spears", "test_spears", "test_spears"])
	var enemy := Fixtures.add_army(state, "blue", "zeta", ["test_mob"])   # mountains: a 2.0 step
	state["armies"][army]["movement_left"] = 1.0
	t.check(not game.targets_for(army).has("zeta"), "half a march does not reach the pass")
	t.check(game.attack_army(army, enemy).is_empty(), "and the attack is refused")
	state["armies"][army]["movement_left"] = 2.0
	t.check(game.targets_for(army).has("zeta"), "a full march does")
	t.check(not game.attack_army(army, enemy).is_empty(), "and the battle is fought")


func test_the_query_surface_answers_for_our_forces_only(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _game(data, state)
	var enemy := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	var foreign_fleet := Fixtures.add_fleet(state, "blue", "test_sea", ["test_galley"])
	t.check(game.reachable_regions(enemy)["reach"].is_empty(), "no reach for a foreign army")
	t.check(game.targets_for(enemy).is_empty(), "no targets for a foreign army")
	t.check(game.reachable_zones(foreign_fleet).is_empty(), "no lanes for a foreign fleet")
	var ours := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	t.check(not game.reachable_regions(ours)["reach"].is_empty(), "our own army answers")
