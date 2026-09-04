extends RefCounted
## Phase 6: the campaign AI on the fixture world — taxes, building,
## recruiting, mustering, marching, besieging, defending, declaring war,
## making peace, offering treaties, and answering the player.


func _brain(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	return AiController.context(data, state, faction_id)


func _peace(state: Dictionary) -> void:
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")


func test_taxes_follow_order(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var brain := _brain(data, state, "blue")
	# A lawless hold with no garrison riots above "normal" taxes; the AI stops
	# one step short of the riot line.
	AiEconomy.set_taxes(data, state, brain, "alpha", false)
	var chosen: String = state["settlements"]["alpha"]["tax_level"]
	var order := PublicOrderRules.total(data, state, "alpha")
	var floor_order := float(data.balance["public_order"]["riot_threshold"]) + float(data.balance["ai"]["tax_order_margin"])
	t.check(order >= floor_order or chosen == "very_low", "order stays a margin above the riot line")
	var next_index := Constants.TAX_LEVELS.find(chosen) + 1
	if next_index < Constants.TAX_LEVELS.size() and next_index <= 4:
		state["settlements"]["alpha"]["tax_level"] = Constants.TAX_LEVELS[next_index]
		t.check(PublicOrderRules.total(data, state, "alpha") < floor_order or next_index > 4,
			"the next rate up would cross it")
	# In debt a modest house squeezes past its usual ceiling where order allows.
	var red := _brain(data, state, "red")
	red["p"] = red["p"].duplicate()
	red["p"]["greed"] = 0.2
	AiEconomy.set_taxes(data, state, red, "beta", false)
	t.check_eq(state["settlements"]["beta"]["tax_level"], "high", "a modest house stops at high")
	AiEconomy.set_taxes(data, state, red, "beta", true)
	t.check_eq(state["settlements"]["beta"]["tax_level"], "very_high", "in debt it squeezes to the top rate")


func test_builds_and_recruits_within_means(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_peace(state)
	var brain := _brain(data, state, "red")
	var reserve := AiController.reserve_for(brain, 2)
	t.check(reserve > 0, "a reserve is kept")
	var chain := AiEconomy.build(data, state, brain, "beta", reserve)
	t.check(chain != "", "something is built in beta")
	t.check_eq(state["settlements"]["beta"]["construction_queue"].size(), 1, "one project queued")
	t.check_eq(AiEconomy.build(data, state, brain, "beta", reserve), "", "one project at a time")
	var unit := AiEconomy.recruit(data, state, brain, "beta", reserve, false)
	t.check(unit != "", "a garrison unit is raised for an empty city")
	t.check_eq(state["settlements"]["beta"]["recruitment_queue"].size(), 1, "one unit queued")
	# Broke: nothing is bought.
	state["factions"]["red"]["treasury"] = 50
	state["settlements"]["beta"]["recruitment_queue"] = []
	state["settlements"]["beta"]["construction_queue"] = []
	t.check_eq(AiEconomy.recruit(data, state, brain, "beta", reserve, false), "", "no gold, no levies")
	t.check_eq(AiEconomy.build(data, state, brain, "beta", reserve), "", "no gold, no masons")


func test_garrison_target_grows_with_threat(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var brain := _brain(data, state, "blue")
	var quiet := AiEconomy.desired_garrison(data, state, brain, "alpha", false)
	Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	var threatened := AiEconomy.desired_garrison(data, state, brain, "alpha", false)
	t.check(threatened > quiet, "an enemy army next door raises the garrison target")
	t.check(AiEconomy.desired_garrison(data, state, brain, "alpha", true) > threatened, "the muster city keeps more still")
	t.check(AiMilitary.threat_at(data, state, "blue", "alpha") > 0.0, "the threat is measured")


func test_muster_and_march_on_the_nearest_town(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_peace(state)
	# An independent town at delta, two hops from epsilon (red's).
	state["settlements"]["delta"] = Fixtures._settlement("rebels", 800, {"neutral_government": 1})
	data.chains["neutral_government"] = {"id": "neutral_government", "kind": "government", "cultures": ["neutral"],
		"name": "Council", "levels": [{"id": "ngov_1", "name": "Council", "min_settlement_level": "village",
		"cost": 300, "build_turns": 1, "effects": {}, "description": ""}]}
	var brain := _brain(data, state, "red")
	t.check_eq(AiMilitary.expansion_target(data, state, brain, "epsilon"), "delta", "the nearest independent town is the target")
	t.check_eq(AiMilitary.muster_city(data, state, brain), "epsilon", "the army gathers in the nearest city")
	for i in range(8):
		state["settlements"]["epsilon"]["garrison"].append({"template": "test_spears", "experience": 0, "strength_pct": 100})
	var army_id := AiMilitary.muster(data, state, brain)
	t.check(army_id != "", "a field army musters from the surplus")
	t.check(state["armies"][army_id]["units"].size() >= int(data.balance["ai"]["field_army_min_units"]), "of a useful size")
	t.check(state["settlements"]["epsilon"]["garrison"].size() >= AiEconomy.desired_garrison(data, state, brain, "epsilon", false),
		"without stripping the walls")

	var rng := CampaignRng.seeded(3)
	var notices: Array = []
	AiMilitary.order_army(data, state, rng, AutoResolver.new(), brain, army_id, notices)
	var siege = state["settlements"]["delta"]["siege"]
	t.check(siege != null and siege["besieger"] == army_id, "the army marches up and lays siege at once")
	t.check(notices.size() == 1 and notices[0]["kind"] == "siege_laid", "and says so")


func test_assault_when_the_odds_allow(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var brain := _brain(data, state, "red")
	var host: Array = []
	for i in range(6):
		host.append("test_elites")
	var army_id := Fixtures.add_army(state, "red", "beta", host)
	MovementRules.reset_movement(data, state)
	SiegeRules.begin_siege(data, state, army_id, "alpha")
	state["settlements"]["alpha"]["siege"]["equipment_ready"] = true
	var rng := CampaignRng.seeded(3)
	var notices: Array = []
	AiMilitary.order_army(data, state, rng, AutoResolver.new(), brain, army_id, notices)
	t.check(notices.size() == 1 and notices[0]["kind"] == "assault", "an overwhelming army storms the walls")
	t.check_eq(state["settlements"]["alpha"]["owner"], "red", "and takes the hold")
	t.check_eq(notices[0]["occupation"], "occupy", "a temperate house occupies")


func test_cruelty_decides_the_sack(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var brain := _brain(data, state, "red")
	brain["p"] = brain["p"].duplicate()
	brain["p"]["cruelty"] = 0.9
	t.check_eq(AiMilitary.occupation_choice(data, state, brain, "alpha"), "exterminate", "a butcher puts a foreign hold to the sword")
	brain["p"]["cruelty"] = 0.6
	state["settlements"]["alpha"]["population"] = 5000
	t.check_eq(AiMilitary.occupation_choice(data, state, brain, "alpha"), "enslave", "a hard house enslaves a big one")
	state["settlements"]["alpha"]["population"] = 1200
	t.check_eq(AiMilitary.occupation_choice(data, state, brain, "alpha"), "occupy", "but occupies a small one")


func test_defends_a_threatened_city(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var brain := _brain(data, state, "red")
	# A big blue army stands beside undefended beta (the capital); red's small
	# field army waits at gamma, one step from beta on the far side.
	Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears"])
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	t.check_eq(AiMilitary.most_threatened(data, state, brain, "gamma"), "beta", "beta cannot hold alone")
	var rng := CampaignRng.seeded(3)
	AiMilitary.order_army(data, state, rng, AutoResolver.new(), brain, army_id, [])
	t.check(not state["armies"].has(army_id), "the army marches to beta and mans its walls")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 1, "the spears stand in the garrison")


func test_attacks_a_weaker_enemy_army(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var brain := _brain(data, state, "red")
	var legion := Fixtures.add_army(state, "red", "gamma", ["test_elites", "test_elites", "test_elites"])
	Fixtures.add_army(state, "blue", "delta", ["test_mob"])
	var rng := CampaignRng.seeded(3)
	var notices: Array = []
	AiMilitary.order_army(data, state, rng, AutoResolver.new(), brain, legion, notices)
	t.check(not notices.is_empty() and notices[0]["kind"] == "battle", "a weak enemy next door is attacked")


func test_declares_war_on_a_weak_neighbour_but_not_kin(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_peace(state)
	state["factions"]["blue"]["peace_since"] = {}  # an old peace, not one signed this season
	var brain := _brain(data, state, "blue")
	var notices: Array = []
	t.check(not AiDiplomacy.consider_war(data, state, brain, "red", notices), "no war at equal strength")
	Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears", "test_spears"])
	t.check(AiDiplomacy.consider_war(data, state, brain, "red", notices), "a weak neighbour is fair game")
	t.check(DiplomacyRules.at_war(state, "blue", "red"), "war is declared")
	t.check_eq(notices[0]["kind"], "war_declared", "and reported")

	# Roman kin keep the peace among themselves.
	data.factions["red"]["is_roman_house"] = true
	data.factions["blue"]["is_senate"] = true
	_peace(state)
	brain["memory"]["last_war_turn"] = -999
	t.check(not AiDiplomacy.consider_war(data, state, brain, "red", notices), "the Senate never wars on a house")
	data.factions["blue"].erase("is_senate")

	# A fresh treaty is never broken; an old one only for a big enough edge;
	# an ally regarded well is not attacked at all.
	DiplomacyRules.set_stance(state, "red", "blue", "trade")
	t.check(not AiDiplomacy.consider_war(data, state, brain, "red", notices), "a partner of this season is not attacked at 4:1")
	state["turn"] = 12
	brain = _brain(data, state, "blue")
	brain["memory"]["last_war_turn"] = -999
	t.check_eq(DiplomacyRules.treaty_age(state, "blue", "red"), 12, "the treaty has aged twelve seasons")
	t.check(AiDiplomacy.consider_war(data, state, brain, "red", notices), "an old trade treaty is torn up at 4:1")
	t.check(notices[-1].get("broke_treaty", false), "and the report says a treaty was broken")
	t.check_eq(int(state["factions"]["blue"]["treachery"]), 1, "which the world remembers")
	DiplomacyRules.set_stance(state, "red", "blue", "alliance")
	state["turn"] = 30
	brain = _brain(data, state, "blue")
	brain["memory"]["last_war_turn"] = -999
	state["factions"]["blue"]["peace_since"] = {}
	t.check(not AiDiplomacy.consider_war(data, state, brain, "red", notices), "an ally it regards well is never attacked")
	data.factions["red"].erase("is_roman_house")


func test_no_war_peace_war_churn(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["player_faction"] = "rebels"
	var winners := Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears"])
	Fixtures.add_army(state, "red", "beta", ["test_spears"])
	Fixtures.add_agent(state, "blue", "envoy", "alpha")
	state["factions"]["blue"]["war_turns"]["red"] = 20
	state["factions"]["red"]["war_turns"]["blue"] = 20
	var brain := _brain(data, state, "blue")
	var notices: Array = []
	# Winning by 2:1, blue does not tire of a war it is winning.
	AiDiplomacy.consider_peace(data, state, brain, "red", notices)
	t.check(DiplomacyRules.at_war(state, "blue", "red"), "the winning side does not sue for peace out of weariness")
	# Evenly matched and weary, it does — and then keeps the peace a while.
	state["armies"][winners]["units"].pop_back()
	brain["memory"]["offers"] = {}
	AiDiplomacy.consider_peace(data, state, brain, "red", notices)
	t.check(not DiplomacyRules.at_war(state, "blue", "red"), "an even, weary war ends")
	state["armies"].clear()
	Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears", "test_spears"])
	state["turn"] = int(state["turn"]) + 8
	brain = _brain(data, state, "blue")
	brain["memory"]["last_war_turn"] = -999
	t.check(not AiDiplomacy.consider_war(data, state, brain, "red", notices), "no new war within the peace's first seasons")
	state["turn"] = int(state["turn"]) + 10
	brain = _brain(data, state, "blue")
	brain["memory"]["last_war_turn"] = -999
	t.check(AiDiplomacy.consider_war(data, state, brain, "red", notices), "after the peace has aged, the odds speak again")


func test_an_army_does_not_park_in_a_city_it_cannot_take(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var brain := _brain(data, state, "red")
	for i in range(6):
		state["settlements"]["alpha"]["garrison"].append({"template": "test_elites", "experience": 0, "strength_pct": 100})
	var army_id := Fixtures.add_army(state, "red", "alpha", ["test_spears"])
	t.check_eq(AiMilitary.expansion_target(data, state, brain, "alpha", AiController.army_strength(data, state, state["armies"][army_id])), "",
		"a hold it cannot take is no target for this army")
	var rng := CampaignRng.seeded(3)
	AiMilitary.order_army(data, state, rng, AutoResolver.new(), brain, army_id, [])
	t.check(state["armies"][army_id]["region"] != "alpha", "so the army goes home instead of camping under the walls")


func test_debt_sheds_garrisons_and_a_lost_capital_moves(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	for template in ["test_mob", "test_spears", "test_elites"]:
		state["settlements"]["beta"]["garrison"].append({"template": template, "experience": 0, "strength_pct": 100})
	state["factions"]["red"]["treasury"] = -500
	state["factions"]["red"]["capital"] = "alpha"  # lost to blue
	var brain := _brain(data, state, "red")
	AiEconomy.act(data, state, CampaignRng.seeded(1), brain, [])
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 2, "in debt the costliest unit is let go")
	t.check_eq(state["settlements"]["beta"]["garrison"][0]["template"], "test_mob", "and the cheap ones stay")
	t.check_eq(state["factions"]["red"]["capital"], "epsilon", "the seat moves to the largest city still held")


func test_no_army_leaves_a_besieged_city(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	for i in range(8):
		state["settlements"]["beta"]["garrison"].append({"template": "test_spears", "experience": 0, "strength_pct": 100})
	var besieger := Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears", "test_spears", "test_spears", "test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, besieger, "beta"), "blue invests beta")
	t.check_eq(CombatRules.raise_army(data, state, "beta", 4), "", "nobody marches out of a besieged city")
	var brain := _brain(data, state, "red")
	t.check_eq(AiMilitary.muster(data, state, brain), "", "nor does the AI muster from it")


func test_answered_offers_neither_double_train_nor_downgrade(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_peace(state)
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	var envoy := Fixtures.add_agent(state, "blue", "envoy", "alpha")
	var brain := _brain(data, state, "blue")
	AiDiplomacy.make_offer(data, state, brain, "red", {"stance": "trade"}, [])
	t.check(not AgentRules.can_act(state["agents"][envoy]), "carrying an offer to the player spends the envoy's season")
	# Before the player answers, an alliance is concluded another way.
	DiplomacyRules.set_stance(state, "red", "blue", "alliance")
	var result := game.respond_to_offer(0, true)
	t.check(not result["accepted"], "a trade offer overtaken by an alliance is not applied")
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "alliance", "the alliance stands")
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	brain["memory"]["offers"] = {}
	AgentRules.reset_movement(data, state)
	AiDiplomacy.make_offer(data, state, brain, "red", {"stance": "trade"}, [])
	AgentRules.reset_movement(data, state)
	result = game.respond_to_offer(0, true)
	t.check(result["accepted"], "a live offer is taken")
	t.check_eq(int(state["agents"][envoy]["skill"]), 1, "accepting it does not train the envoy a second time")
	t.check(AgentRules.can_act(state["agents"][envoy]), "nor spend a season already paid for")


func test_seeks_peace_when_losing(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var brain := _brain(data, state, "blue")
	var host: Array = []
	for i in range(6):
		host.append("test_elites")
	Fixtures.add_army(state, "red", "beta", host)
	var envoy := Fixtures.add_agent(state, "blue", "envoy", "alpha")
	var notices: Array = []
	# red is the player here (fixture default), so the offer waits for an answer.
	AiDiplomacy.consider_peace(data, state, brain, "red", notices)
	t.check_eq(state["pending_offers"].size(), 1, "an offer of peace is laid before the player")
	t.check_eq(state["pending_offers"][0]["proposal"]["stance"], "neutral", "asking for peace")
	t.check_eq(notices[0]["kind"], "offer", "and announced")
	t.check(not AiDiplomacy.offer_due(brain, "red"), "not again for a while")

	# Without an envoy in contact, one is sent for.
	state["agents"].erase(envoy)
	brain["memory"]["offers"] = {}
	AiDiplomacy.consider_peace(data, state, brain, "red", notices)
	t.check_eq(brain["memory"]["envoy_target"], "red", "the court is marked for an envoy")


func test_offers_between_courts_resolve_at_once(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_peace(state)
	state["player_faction"] = "rebels"
	var brain := _brain(data, state, "blue")
	Fixtures.add_agent(state, "blue", "envoy", "alpha")
	var notices: Array = []
	AiDiplomacy.consider_treaties(data, state, brain, "red", notices)
	t.check_eq(DiplomacyRules.stance_between(state, "blue", "red"), "trade", "trade rights offered and taken")
	t.check(notices.size() == 1 and notices[0]["kind"] == "treaty", "reported as a treaty")


func test_player_answers_an_offer(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_peace(state)
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	Fixtures.add_agent(state, "blue", "envoy", "alpha")
	var brain := _brain(data, state, "blue")
	AiDiplomacy.make_offer(data, state, brain, "red", {"stance": "trade", "gift": 300}, [])
	t.check_eq(game.pending_offers().size(), 1, "the offer waits")
	var result := game.respond_to_offer(0, true)
	t.check(result["accepted"], "accepted")
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "trade", "the treaty stands")
	t.check_eq(int(state["factions"]["red"]["treasury"]), 5300, "and the gift arrived")
	t.check(game.pending_offers().is_empty(), "nothing left on the table")

	AiDiplomacy.make_offer(data, state, brain, "red", {"stance": "alliance"}, [])
	t.check_eq(game.pending_offers().size(), 0, "the same court does not offer twice in a season")
	brain["memory"]["offers"] = {}
	AgentRules.reset_movement(data, state)  # the accepted offer spent the envoy's season
	AiDiplomacy.make_offer(data, state, brain, "red", {"stance": "alliance"}, [])
	t.check_eq(game.pending_offers().size(), 1, "next season the court offers again")
	result = game.respond_to_offer(0, false)
	t.check(not result["accepted"] and result["reason"] == "refused", "refused")
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "trade", "and nothing changed")


func test_agents_go_where_they_are_needed(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["player_faction"] = "rebels"
	var brain := _brain(data, state, "blue")
	var envoy := Fixtures.add_agent(state, "blue", "envoy", "alpha")
	state["agents"][envoy]["region"] = "epsilon"
	brain["memory"]["envoy_target"] = "red"
	AiAgents.run_envoy(data, state, brain, envoy)
	t.check(AgentRules.in_contact(data, state, envoy, "red"), "the envoy walks into contact with the court")
	t.check_eq(brain["memory"]["envoy_target"], "", "and the errand is done")

	var rng := CampaignRng.seeded(3)
	var home := Fixtures.add_agent(state, "blue", "spy", "alpha")
	var abroad := Fixtures.add_agent(state, "blue", "spy", "alpha")
	AiAgents.act(data, state, rng, brain, [])
	t.check_eq(state["agents"][home]["region"], "alpha", "one spy keeps the home watch")
	t.check(state["agents"][abroad]["region"] != "alpha", "the other goes to the enemy")


func test_rebels_only_defend(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["gamma"] = Fixtures._settlement("rebels", 1000, {})
	var band := Fixtures.add_army(state, "rebels", "gamma", ["test_mob", "test_mob", "test_mob"])
	Fixtures.add_army(state, "red", "beta", ["test_mob"])  # a weak enemy next door, tempting to anyone else
	var brain := _brain(data, state, "rebels")
	var rng := CampaignRng.seeded(3)
	var notices: Array = []
	AiController.take_turn(data, state, rng, AutoResolver.new(), "rebels", notices)
	t.check(state["pending_offers"].is_empty() and notices.is_empty(), "the independents start nothing, not even a battle")
	t.check(not state["armies"].has(band) or state["armies"][band]["region"] == "gamma", "their bands stay home or man the walls")


func test_raising_an_army_is_one_path_for_all(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	for template in ["test_mob", "test_spears", "test_elites", "test_mob"]:
		state["settlements"]["beta"]["garrison"].append({"template": template, "experience": 0, "strength_pct": 100})
	Fixtures.add_character(state, "red", "the_governor", {"location": "beta", "influence": 5})
	Fixtures.add_character(state, "red", "the_cousin", {"location": "beta", "influence": 1})
	SettlementRules.refresh_governors(data, state)
	t.check_eq(state["settlements"]["beta"]["governor"], "the_governor", "the influential man governs")
	var army_id := game.raise_army("beta", 2)
	t.check(army_id != "", "the player raises an army from the garrison")
	var army: Dictionary = state["armies"][army_id]
	t.check_eq(army["units"].size(), 2, "of the size asked")
	t.check_eq(army["units"][0]["template"], "test_elites", "strongest first")
	t.check_eq(army["general"], "the_cousin", "led by the kinsman who is not the governor")
	t.check_eq(state["settlements"]["beta"]["governor"], "the_governor", "the governor keeps his seat")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 2, "the rest stay on the walls")
	t.check_near(float(army["movement_left"]), 2.0, 0.001, "and the army can march this season")
	t.check_eq(game.raise_army("alpha", 1), "", "never from a foreign city")


func test_ai_turn_is_deterministic(t) -> void:
	var first_data := Fixtures.data()
	var first := Fixtures.state(first_data)
	var second_data := Fixtures.data()
	var second := Fixtures.state(second_data)
	for state in [first, second]:
		state["player_faction"] = "rebels"
		Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears"])
		Fixtures.add_agent(state, "blue", "envoy", "alpha")
	var resolver := AutoResolver.new()
	for i in range(4):
		TurnEngine.end_turn(first_data, first, resolver)
		TurnEngine.end_turn(second_data, second, resolver)
	t.check_eq(JSON.stringify(first), JSON.stringify(second), "the same world plays out the same way")
