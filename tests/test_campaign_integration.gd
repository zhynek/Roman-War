extends RefCounted
## Full-stack tests over the real authored data tables: the campaign boots,
## many turns resolve without invariant violations, saves round-trip, and the
## same seed replays identically.

const TURNS := 24


func test_data_loads_clean(t) -> void:
	var data := GameData.load_from("res://data")
	t.check(data.ok(), "data load errors: " + ", ".join(data.load_errors))
	t.check(data.regions.size() >= 40, "map has a real region count (got %d)" % data.regions.size())
	t.check(data.units.size() >= 40, "roster has real breadth (got %d)" % data.units.size())
	t.check(data.factions.size() >= 15, "faction list complete (got %d)" % data.factions.size())
	for faction_id in ["julii", "junii", "cornelii", "senate", "rebels"]:
		t.check(data.factions.has(faction_id), "core faction present: " + faction_id)


func test_campaign_boots(t) -> void:
	var game := Game.new_campaign("julii", 42)
	t.check(game.state["settlements"].size() >= 40, "every region settled at start")
	t.check(game.state["factions"].size() >= 15, "all factions in play")
	var julii_settlements := 0
	for settlement in game.state["settlements"].values():
		if settlement["owner"] == "julii":
			julii_settlements += 1
	t.check(julii_settlements >= 1, "the player starts with a home")


func test_campaign_starts_with_agents(t) -> void:
	var game := Game.new_campaign("julii", 42)
	t.check_eq(game.state["agents"].size(), 2 * game.data.campaign["factions"].size(),
		"every house starts with an envoy and a spy")
	var kinds := {}
	for agent_id in AgentRules.agents_of(game.state, "julii"):
		var agent: Dictionary = game.state["agents"][agent_id]
		kinds[agent["kind"]] = true
		t.check_eq(agent["region"], game.state["factions"]["julii"]["capital"], "starting agents stand in the capital")
		t.check(String(agent["name"]).length() > 1, "agents are named from the culture's pool")
	t.check(kinds.has("envoy") and kinds.has("spy"), "an envoy and a spy")
	t.check(game.best_envoy("senate") != "", "the envoy at home is already in contact with the Senate next door")


func test_long_campaign_invariants(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var start_year := int(game.state["year"])
	for i in range(TURNS):
		var report := game.end_turn()
		t.check(report is Dictionary, "end_turn returns a report")

	t.check_eq(int(game.state["turn"]), TURNS, "turn counter advanced")
	t.check_eq(int(game.state["year"]), start_year + TURNS / 2, "two turns to the year")

	for region_id in game.state["settlements"]:
		var settlement: Dictionary = game.state["settlements"][region_id]
		t.check(int(settlement["population"]) >= 400, "population floor holds in " + region_id)
		t.check(game.state["factions"].has(settlement["owner"]), "owner exists for " + region_id)
	for faction_id in game.state["factions"]:
		var faction: Dictionary = game.state["factions"][faction_id]
		t.check(typeof(faction["treasury"]) == TYPE_INT or typeof(faction["treasury"]) == TYPE_FLOAT,
			"treasury numeric for " + faction_id)
		for other in faction["opinion"]:
			var value := float(faction["opinion"][other])
			t.check(value >= -100.0 and value <= 100.0, "opinion stays in range for " + faction_id)
	var max_skill := int(game.data.balance["agents"]["max_skill"])
	for agent_id in game.state["agents"]:
		var agent: Dictionary = game.state["agents"][agent_id]
		t.check(game.data.regions.has(agent["region"]), "agent stands on the map: " + agent_id)
		t.check(game.state["factions"][agent["owner"]]["alive"], "no agent serves a dead house: " + agent_id)
		t.check(int(agent["skill"]) >= 0 and int(agent["skill"]) <= max_skill, "agent skill in range: " + agent_id)


func test_same_seed_same_world(t) -> void:
	var first := Game.new_campaign("julii", 1234)
	var second := Game.new_campaign("julii", 1234)
	for i in range(8):
		first.end_turn()
		second.end_turn()
	t.check_eq(JSON.stringify(first.state), JSON.stringify(second.state), "deterministic replay")


func test_save_round_trip(t) -> void:
	var game := Game.new_campaign("julii", 7)
	for i in range(4):
		game.end_turn()
	var json_before := SaveGame.to_json(game.state)
	var restored := SaveGame.from_json(json_before)
	t.check(not restored.is_empty(), "save parses back")

	# The restored state must continue identically to the original. Compare in
	# canonical JSON form: a parsed state holds 2.0 where the live one holds 2
	# (JSON numbers are floats), which is meaningless — every reader coerces.
	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored
	game.end_turn()
	resumed.end_turn()
	t.check_eq(_canonical(game.state), _canonical(resumed.state), "resumed game marches in step")


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))


func test_old_save_upgrades(t) -> void:
	## A Phase 4 save (version 1) lacks agents, tributes and the opinion
	## memory; loading it must fill those in rather than refuse or crash.
	var game := Game.new_campaign("julii", 7)
	var old_state: Dictionary = JSON.parse_string(JSON.stringify(game.state))
	old_state.erase("agents")
	old_state.erase("tributes")
	for faction in old_state["factions"].values():
		for key in ["opinion", "war_turns", "treachery", "overlord"]:
			faction.erase(key)
	var restored := SaveGame.from_json(JSON.stringify({"version": 1, "state": old_state}))
	t.check(not restored.is_empty(), "a version-1 save still loads")
	t.check(restored.has("agents") and restored.has("tributes"), "missing tables are created")
	t.check(restored["factions"]["julii"].has("opinion"), "faction memory is created")
	t.check(SaveGame.from_json(JSON.stringify({"version": 99, "state": old_state})).is_empty(),
		"a save from the future is refused")

	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored
	var turn_before := int(resumed.state["turn"])
	resumed.end_turn()
	t.check_eq(int(resumed.state["turn"]), turn_before + 1, "the upgraded save plays on")


func test_senate_courts_and_diplomatic_missions(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var courts := SenateRules._courts_in_reach(game.data, game.state, "julii")
	t.check(not courts.is_empty(), "foreign courts lie within the Senate's reach of Etruria")
	for other in courts:
		var faction: Dictionary = game.data.factions[other]
		t.check(not faction.get("is_roman_house", false) and not faction.get("is_senate", false)
			and not faction.get("is_rebel", false), "only foreign kings are courted: " + other)
	if courts.is_empty():
		return
	var other: String = courts[0]
	var alliance := {"template": "court_a_useful_friend", "target_faction": other, "turns_left": 8}
	t.check(not SenateRules._mission_complete(game.data, game.state, "julii", alliance), "no alliance yet")
	DiplomacyRules.set_stance(game.state, "julii", other, "trade")
	t.check(not SenateRules._mission_complete(game.data, game.state, "julii", alliance), "trade rights are not an alliance")
	var trade := {"template": "open_the_markets", "target_faction": other, "turns_left": 6}
	t.check(SenateRules._mission_complete(game.data, game.state, "julii", trade), "but they open the markets")
	DiplomacyRules.set_stance(game.state, "julii", other, "alliance")
	t.check(SenateRules._mission_complete(game.data, game.state, "julii", alliance), "an alliance completes the mission")

	var leader := FamilyRules.leader_of(game.state, other)
	var murder := {"template": "remove_a_troublesome_king", "target_faction": other,
		"target_character": leader, "turns_left": 8}
	t.check(not SenateRules._mission_complete(game.data, game.state, "julii", murder), "the king still lives")
	CharacterRules.kill(game.state, leader, game.data)
	t.check(SenateRules._mission_complete(game.data, game.state, "julii", murder), "and now he does not")

	# The draw offers more than one kind of mission over enough seeds.
	var kinds := {}
	for seed_value in range(1, 40):
		var mission := SenateRules._issue_mission(game.data, game.state, "junii", CampaignRng.seeded(seed_value))
		if not mission.is_empty():
			kinds[game.data.missions[mission["template"]]["kind"]] = true
	t.check(kinds.size() >= 2, "missions now come in several kinds (got %s)" % str(kinds.keys()))


func test_growth_order_income_queries(t) -> void:
	var game := Game.new_campaign("julii", 42)
	for region_id in game.state["settlements"]:
		if game.state["settlements"][region_id]["owner"] != "julii":
			continue
		t.check(not game.growth_breakdown(region_id).is_empty(), "growth breakdown for " + region_id)
		t.check(not game.order_breakdown(region_id).is_empty(), "order breakdown for " + region_id)
		t.check(not game.income_breakdown(region_id).is_empty(), "income breakdown for " + region_id)
		t.check(not game.available_buildings(region_id).is_empty(), "something to build in " + region_id)


func test_fog_of_war(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var visible := game.visible_regions()
	t.check(visible.size() > 0, "player sees something")
	t.check(visible.size() < game.data.regions.size(), "player does not see everything")
