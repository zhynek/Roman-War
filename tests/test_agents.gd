extends RefCounted
## Phase 5 agents: training, travel, counter-intelligence, the knife, the
## gate, the purse, and the price of being caught.


func _certain(data: GameData) -> void:
	## Every skill contest succeeds.
	data.balance["agents"]["success_min_pct"] = 100
	data.balance["agents"]["success_max_pct"] = 100


func _hopeless(data: GameData) -> void:
	## Every skill contest fails.
	data.balance["agents"]["success_min_pct"] = 0
	data.balance["agents"]["success_max_pct"] = 0


func _kind_ids(offers: Array) -> Array:
	var ids: Array = []
	for offer in offers:
		ids.append(offer["id"])
	return ids


func test_training_needs_buildings_and_gold(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check_eq(_kind_ids(AgentRules.kinds_available(data, state, "beta")), ["envoy"],
		"a seat of government trains envoys alone")
	state["settlements"]["beta"]["buildings"]["test_market"] = 1
	t.check_eq(_kind_ids(AgentRules.kinds_available(data, state, "beta")), ["envoy", "spy"],
		"a market opens the spy trade")
	state["settlements"]["beta"]["buildings"]["test_market"] = 2
	t.check_eq(_kind_ids(AgentRules.kinds_available(data, state, "beta")), ["assassin", "envoy", "spy"],
		"a bazaar hides assassins")

	var rng := CampaignRng.seeded(1)
	var agent_id := AgentRules.recruit(data, state, rng, "beta", "spy")
	t.check(agent_id != "", "a spy is trained")
	t.check_eq(int(state["factions"]["red"]["treasury"]), 4600, "the price is paid")
	var agent: Dictionary = state["agents"][agent_id]
	t.check_eq(agent["region"], "beta", "he starts at home")
	t.check_eq(int(agent["skill"]), 1, "with the kind's base skill")
	t.check_near(float(agent["movement_left"]), 0.0, 0.001, "and no movement this season")
	t.check(data.names["roman"]["male"].has(agent["name"]), "named from the culture's pool")

	state["factions"]["red"]["treasury"] = 100
	t.check_eq(AgentRules.recruit(data, state, rng, "beta", "envoy"), "", "no gold, no envoy")
	t.check_eq(AgentRules.recruit(data, state, rng, "alpha", "spy"), "", "no market, no spy")


func test_agents_cross_any_border_and_sail(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var spy := Fixtures.add_agent(state, "red", "spy", "beta")
	t.check(AgentRules.move(data, state, spy, "alpha"), "a spy walks straight into an enemy city")
	t.check_eq(state["agents"][spy]["region"], "alpha", "and is there")
	t.check_near(float(state["agents"][spy]["movement_left"]), 2.0, 0.001, "one plain crossed")
	t.check(not AgentRules.move(data, state, spy, "gamma"), "no leaping over regions")
	t.check(AgentRules.sea_move(data, state, spy, "epsilon"), "coast to coast across the shared sea")
	t.check_eq(state["agents"][spy]["region"], "epsilon", "landed")
	t.check(not AgentRules.sea_move(data, state, spy, "alpha"), "the crossing takes the whole season")
	MovementRules.reset_movement(data, state)
	t.check_near(float(state["agents"][spy]["movement_left"]), 3.0, 0.001, "agents outpace armies")


func test_upkeep_and_sight(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var seen := VisibilityRules.visible_regions(data, state, "blue")
	t.check(not seen.has("delta"), "blue cannot see delta from alpha")
	Fixtures.add_agent(state, "blue", "envoy", "delta")
	seen = VisibilityRules.visible_regions(data, state, "blue")
	t.check(seen.has("delta") and not seen.has("epsilon"), "an envoy lifts the fog where he stands, no further")
	Fixtures.add_agent(state, "blue", "spy", "delta")
	seen = VisibilityRules.visible_regions(data, state, "blue")
	t.check(seen.has("gamma") and seen.has("epsilon"), "a spy sees a hop around him")
	t.check_eq(EconomyRules.faction_upkeep(data, state, "blue"), 70, "envoy 40 + spy 30 upkeep")


func test_security_and_odds(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check_near(AgentRules.settlement_security(data, state, "beta"), 2.0, 0.001, "base 1 + law 10 x 0.1")
	t.check_near(AgentRules.settlement_security(data, state, "alpha"), 1.0, 0.001, "a lawless hold has only the base")
	Fixtures.add_agent(state, "blue", "spy", "alpha", 2)
	Fixtures.add_agent(state, "red", "spy", "alpha", 5)
	t.check_near(AgentRules.settlement_security(data, state, "alpha"), 3.0, 0.001,
		"only the owner's spies keep watch (skill 2)")
	data.ancillaries["test_informant"] = {"id": "test_informant", "name": "Informant",
		"effects": {"agent_skill": 2}, "triggers": []}
	Fixtures.add_character(state, "blue", "chief", {"location": "alpha", "ancillaries": ["test_informant"]})
	SettlementRules.refresh_governors(data, state)
	t.check_near(AgentRules.settlement_security(data, state, "alpha"), 5.0, 0.001, "the governor's informant adds his skill")

	t.check_near(AgentRules.success_chance(data, 1.0, 1.0), 0.5, 0.001, "even odds at equal skill")
	t.check_near(AgentRules.success_chance(data, 10.0, 0.0), 0.95, 0.001, "never certain")
	t.check_near(AgentRules.success_chance(data, 0.0, 10.0), 0.05, 0.001, "never hopeless")

	t.check_near(AgentRules.character_security(data, state, "chief"), 4.5, 0.001,
		"at home: base 2 + half the city's watch")
	var army_id := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	state["armies"][army_id]["general"] = "chief"
	t.check_near(AgentRules.character_security(data, state, "chief"), 4.0, 0.001,
		"in the field: base 2 + bodyguard 2")
	state["characters"]["chief"]["role"] = "leader"
	t.check_near(AgentRules.character_security(data, state, "chief"), 6.0, 0.001,
		"a king is guarded like one: +2")


func test_assassination(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_certain(data)
	var rng := CampaignRng.seeded(3)
	Fixtures.add_character(state, "blue", "chief", {"role": "leader", "location": "alpha"})
	Fixtures.add_character(state, "blue", "heir", {"role": "heir", "location": "alpha"})
	Fixtures.add_character(state, "blue", "the_wife", {"role": "spouse", "gender": "female", "location": "alpha"})
	var blue_envoy := Fixtures.add_agent(state, "blue", "envoy", "alpha")
	var assassin := Fixtures.add_agent(state, "red", "assassin", "alpha")

	var targets := AgentRules.assassination_targets(data, state, assassin)
	var target_ids: Array = []
	for target in targets:
		target_ids.append(target["id"])
	t.check_eq(target_ids, ["chief", "heir", blue_envoy], "family men and foreign agents, spouses spared")

	var result := AgentRules.assassinate(data, state, rng, assassin, "chief")
	t.check(result["success"], "the knife finds the chief")
	t.check(not state["characters"]["chief"]["alive"], "he is dead")
	t.check_eq(state["characters"]["heir"]["role"], "leader", "the heir succeeds at once")
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), -5.0, 0.001, "suspicion falls on us, lightly")

	t.check(AgentRules.assassinate(data, state, rng, assassin, blue_envoy).is_empty(), "one attempt a season")
	AgentRules.reset_movement(data, state)
	result = AgentRules.assassinate(data, state, rng, assassin, blue_envoy)
	t.check(result["success"], "next season, the envoy")
	t.check(not state["agents"].has(blue_envoy), "he is gone")
	t.check(state["agents"].has(assassin), "our man walks away")
	AgentRules.reset_movement(data, state)
	t.check(AgentRules.assassinate(data, state, rng, assassin, "the_wife").is_empty(), "no target, no attempt")


func test_failure_costs_the_assassin(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_hopeless(data)
	data.balance["agents"]["caught_on_failure_pct"]["assassinate"] = 100
	var rng := CampaignRng.seeded(3)
	Fixtures.add_character(state, "blue", "chief", {"role": "leader", "location": "alpha"})
	var assassin := Fixtures.add_agent(state, "red", "assassin", "alpha")
	var security_before := AgentRules.character_security(data, state, "chief")

	var result := AgentRules.assassinate(data, state, rng, assassin, "chief")
	t.check(not result["success"] and result["caught"], "the attempt fails and the assassin is taken")
	t.check(not state["agents"].has(assassin), "he does not come back")
	t.check(state["characters"]["chief"]["alive"], "the chief lives")
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), -20.0, 0.001, "and knows exactly whose man it was")
	t.check(state["characters"]["chief"]["trait_points"].has("test_wary"), "he grows watchful")
	t.check_near(AgentRules.character_security(data, state, "chief"), security_before + 1.0, 0.001,
		"and harder to reach next time")
	var kinds: Array = []
	for notice in result["notices"]:
		kinds.append(notice["kind"])
	t.check(kinds.has("trait"), "the report tells of the new trait")


func test_sabotage(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_certain(data)
	var rng := CampaignRng.seeded(3)
	var assassin := Fixtures.add_agent(state, "red", "assassin", "alpha")
	t.check(AgentRules.sabotage_targets(data, state, assassin).is_empty(), "the chief's hall is beyond reach")
	state["settlements"]["alpha"]["buildings"]["test_walls"] = 2
	var targets := AgentRules.sabotage_targets(data, state, assassin)
	t.check_eq(targets.size(), 1, "the walls can be wrecked")
	var result := AgentRules.sabotage(data, state, rng, assassin, "test_walls")
	t.check(result["success"], "fire in the night")
	t.check_eq(int(state["settlements"]["alpha"]["buildings"]["test_walls"]), 1, "a tier is lost")
	t.check(AgentRules.sabotage(data, state, rng, assassin, "test_walls").is_empty(), "not twice in a season")
	AgentRules.reset_movement(data, state)
	AgentRules.sabotage(data, state, rng, assassin, "test_walls")
	t.check(not state["settlements"]["alpha"]["buildings"].has("test_walls"), "and next season the palisade itself")

	var home_assassin := Fixtures.add_agent(state, "red", "assassin", "beta")
	t.check(AgentRules.sabotage_targets(data, state, home_assassin).is_empty(), "never our own city")


func test_open_gates(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_certain(data)
	var rng := CampaignRng.seeded(3)
	var resolver := AutoResolver.new()
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege laid")
	t.check(SiegeRules.assault(data, state, rng, resolver, army_id, "alpha").is_empty(),
		"no assault without equipment")

	var blue_spy := Fixtures.add_agent(state, "blue", "spy", "alpha")
	t.check(not AgentRules.can_open_gates(data, state, blue_spy), "the defenders' own spy opens nothing")
	var red_spy := Fixtures.add_agent(state, "red", "spy", "alpha")
	t.check(AgentRules.can_open_gates(data, state, red_spy), "ours can")
	var result := AgentRules.open_gates(data, state, rng, red_spy)
	t.check(result["success"], "the gate is unbarred")
	t.check(state["settlements"]["alpha"]["siege"].get("gates_open", false), "the siege records it")
	t.check(SiegeRules.can_assault(state["settlements"]["alpha"]["siege"]), "an assault may go in at once")
	var battle := SiegeRules.assault(data, state, rng, resolver, army_id, "alpha")
	t.check(battle.has("winner"), "and it is fought")


func test_bribery(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var envoy := Fixtures.add_agent(state, "red", "envoy", "gamma")
	var brigands := Fixtures.add_army(state, "rebels", "gamma", ["test_mob"])
	t.check_eq(AgentRules.bribe_army_cost(data, state, envoy, brigands), 100,
		"brigands come cheap, but never under the floor price")
	var result := AgentRules.bribe_army(data, state, envoy, brigands)
	t.check(result["success"], "gold changes hands")
	t.check_eq(state["armies"][brigands]["owner"], "red", "the band takes our banner")
	t.check_eq(int(state["factions"]["red"]["treasury"]), 4900, "the price is paid")

	var envoy_home := Fixtures.add_agent(state, "red", "envoy", "beta")
	var captain := Fixtures.add_army(state, "blue", "beta", ["test_spears", "test_spears"])
	t.check_eq(AgentRules.bribe_army_cost(data, state, envoy_home, captain), 1552,
		"a foreign captain: 800 x 2.0, less 3% for a skill-1 envoy")
	Fixtures.add_character(state, "blue", "prince", {"location": "beta"})
	var led := Fixtures.add_army(state, "blue", "beta", ["test_spears"])
	state["armies"][led]["general"] = "prince"
	t.check_eq(AgentRules.bribe_army_cost(data, state, envoy_home, led), -1, "family do not sell out")
	t.check_eq(AgentRules.bribe_army_cost(data, state, envoy, captain), -1, "the envoy must stand with the army")

	state["factions"]["red"]["treasury"] = 10
	result = AgentRules.bribe_army(data, state, envoy_home, captain)
	t.check(not result["success"] and result.get("reason", "") == "treasury", "no gold, no deal")
	t.check(AgentRules.can_act(state["agents"][envoy_home]), "a refused purse costs no time")
	state["factions"]["red"]["treasury"] = 5000
	result = AgentRules.bribe_army(data, state, envoy_home, captain)
	t.check(result["success"] and state["armies"][captain]["owner"] == "red", "paid, the captain turns his coat")
	t.check_near(DiplomacyRules.opinion(state, "blue", "red"), -15.0, 0.001, "his old masters resent it")
	t.check(not AgentRules.can_act(state["agents"][envoy_home]), "and the purchase takes the season")


func test_an_attempt_spends_the_season(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_hopeless(data)
	data.balance["agents"]["caught_on_failure_pct"]["assassinate"] = 0
	var rng := CampaignRng.seeded(3)
	Fixtures.add_character(state, "blue", "chief", {"role": "leader", "location": "alpha"})
	var assassin := Fixtures.add_agent(state, "red", "assassin", "alpha")
	var result := AgentRules.assassinate(data, state, rng, assassin, "chief")
	t.check(not result["success"], "the knife misses")
	t.check(not AgentRules.can_act(state["agents"][assassin]), "and the season is spent regardless")
	t.check(AgentRules.assassination_targets(data, state, assassin).is_empty(), "no second try until next season")
	t.check(AgentRules.sabotage_targets(data, state, assassin).is_empty(), "nor another trade")
	var spy := Fixtures.add_agent(state, "red", "spy", "alpha", 1)
	state["agents"][spy]["movement_left"] = 0.0
	t.check(not AgentRules.can_open_gates(data, state, spy), "a spy who walked all day opens nothing tonight")
	var fresh := AgentRules.recruit(data, state, rng, "beta", "envoy")
	t.check(not AgentRules.can_act(state["agents"][fresh]), "a freshly trained agent waits for next season")
	t.check(AgentRules.dismiss(state, fresh), "an agent can be paid off")
	t.check(not state["agents"].has(fresh), "and is gone")


func test_a_bought_besieger_lifts_the_siege(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	var band := Fixtures.add_army(state, "rebels", "beta", ["test_mob"])
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, band, "alpha"), "brigands invest the blue hold")
	var envoy := Fixtures.add_agent(state, "red", "envoy", "alpha")
	t.check(AgentRules.bribe_army(data, state, envoy, band)["success"], "and are bought by red")
	t.check(state["settlements"]["alpha"]["siege"] == null, "red is at peace with blue, so the siege lifts")


func test_buying_an_independent_town(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["gamma"] = Fixtures._settlement("rebels", 1000, {"test_walls": 1})
	state["settlements"]["gamma"]["garrison"] = [{"template": "test_mob", "experience": 0, "strength_pct": 100}]
	var envoy := Fixtures.add_agent(state, "red", "envoy", "gamma")
	t.check_eq(AgentRules.bribe_settlement_cost(data, state, envoy), 970, "1000 souls at 1.0 each, less 3%")
	var result := AgentRules.bribe_settlement(data, state, envoy)
	t.check(result["success"], "the town is bought")
	t.check_eq(state["settlements"]["gamma"]["owner"], "red", "and is ours")
	t.check_eq(state["settlements"]["gamma"]["garrison"].size(), 1, "its watch keeps its post")
	t.check_eq(int(state["settlements"]["gamma"]["recently_conquered"]), 0, "nobody was conquered")
	var abroad := Fixtures.add_agent(state, "red", "envoy", "alpha")
	t.check_eq(AgentRules.bribe_settlement_cost(data, state, abroad), -1, "a king's city is not for sale")


func test_covert_agents_risk_detection(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(3)
	var spy := Fixtures.add_agent(state, "blue", "spy", "beta")
	var envoy := Fixtures.add_agent(state, "blue", "envoy", "beta")
	var at_home := Fixtures.add_agent(state, "blue", "spy", "alpha")
	data.balance["agents"]["detection_base_pct"] = 100
	data.balance["agents"]["detection_max_pct"] = 100
	var notices := AgentRules.process_turn(data, state, rng)
	t.check(not state["agents"].has(spy), "the spy in our city is caught")
	t.check(state["agents"].has(envoy), "the envoy is untouchable")
	t.check(state["agents"].has(at_home), "a spy at home is in no danger")
	t.check_eq(notices.size(), 1, "one report")
	t.check_eq(notices[0]["by"], "red", "made by our watch")

	# A master spy in a lawless hold is beyond the watch's reach entirely.
	data.balance["agents"]["detection_base_pct"] = 2
	var master := Fixtures.add_agent(state, "red", "spy", "alpha", 10)
	AgentRules.process_turn(data, state, rng)
	t.check(state["agents"].has(master), "no chance at all below zero")


func test_a_destroyed_house_loses_its_agents(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(3)
	Fixtures.add_agent(state, "blue", "spy", "alpha")
	Fixtures.add_agent(state, "blue", "envoy", "beta")
	CombatRules.capture_settlement(data, state, rng, "alpha", "red", "occupy")
	t.check(not state["factions"]["blue"]["alive"], "blue is finished")
	t.check(AgentRules.agents_of(state, "blue").is_empty(), "and nobody pays its agents")


func test_envoys_in_contact(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var envoy := Fixtures.add_agent(state, "red", "envoy", "beta")
	t.check(AgentRules.in_contact(data, state, envoy, "blue"), "beside their land is contact")
	t.check_eq(AgentRules.factions_in_contact(data, state, envoy), ["blue"], "the independents keep no court")
	state["agents"][envoy]["region"] = "epsilon"
	t.check(not AgentRules.in_contact(data, state, envoy, "blue"), "far from their land is not")
	Fixtures.add_army(state, "blue", "epsilon", ["test_mob"])
	t.check(AgentRules.in_contact(data, state, envoy, "blue"), "their army in our region is")
	var better := Fixtures.add_agent(state, "red", "envoy", "epsilon", 4)
	t.check_eq(AgentRules.best_envoy(data, state, "red", "blue"), better, "the most skilled envoy speaks")
	var spy := Fixtures.add_agent(state, "red", "spy", "alpha")
	t.check(not AgentRules.in_contact(data, state, spy, "blue"), "spies do not negotiate")
