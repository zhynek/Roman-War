extends RefCounted
## Phase 5 diplomacy: the attitude factor model, remembered grudges, offers
## priced in denarii, tribute schedules, peaceful cessions, and the senate's
## courtship missions.


func test_attitude_breakdown_factors(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["difficulty"] = "very_hard"
	var by_label := {}
	for factor in DiplomacyRules.attitude_breakdown(data, state, "blue", "red"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("stance", 0.0), -60.0, 0.001, "war poisons the stance factor")
	t.check_near(by_label.get("shared_border", 0.0), -10.0, 0.001, "neighbors chafe")
	t.check(not by_label.has("same_culture"), "roman and tribal share no kinship")
	t.check_near(by_label.get("difficulty", 0.0), -20.0, 0.001,
		"very_hard AI holds the player in contempt")
	t.check_near(DiplomacyRules.attitude_total(data, state, "blue", "red"), -90.0, 0.001,
		"total is the factor sum")


func test_memory_record_clamp_and_decay(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.record_memory(data, state, "blue", "red", -100.0)
	t.check_near(float(state["factions"]["blue"]["attitude_memory"]["red"]), -80.0, 0.001,
		"grudges clamp at the floor")
	DiplomacyRules.decay_memories(data, state)
	t.check_near(float(state["factions"]["blue"]["attitude_memory"]["red"]), -79.0, 0.001,
		"grudges fade a step per turn")
	DiplomacyRules.record_memory(data, state, "blue", "red", 200.0)
	t.check_near(float(state["factions"]["blue"]["attitude_memory"]["red"]), 60.0, 0.001,
		"gratitude clamps at the ceiling")


func test_declare_war_records_the_grudge(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "alliance")
	DiplomacyRules.declare_war(data, state, "red", "blue")
	t.check(DiplomacyRules.at_war(state, "red", "blue"), "war stands")
	t.check_near(float(state["factions"]["blue"]["attitude_memory"]["red"]), -70.0, 0.001,
		"a betrayed ally remembers the declaration AND the broken oath")
	t.check(not state["factions"]["red"]["attitude_memory"].has("blue"),
		"the aggressor carries no grudge of his own making")


func test_payment_buys_peace_monotonically(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["factions"]["red"]["treasury"] = 200000
	var bare := {"from": "red", "to": "blue", "stance": "neutral",
		"give_payment": 0, "give_tribute": null, "give_regions": [],
		"ask_payment": 0, "ask_tribute": null, "ask_regions": []}
	var verdict_bare := DiplomacyRules.evaluate_offer(data, state, "red", "blue", bare)
	t.check(not verdict_bare["accept"], "a bare peace between sworn enemies is refused")

	var paid: Dictionary = bare.duplicate(true)
	paid["give_payment"] = 100000
	var verdict_paid := DiplomacyRules.evaluate_offer(data, state, "red", "blue", paid)
	t.check(float(verdict_paid["score"]) > float(verdict_bare["score"]),
		"more silver, higher score")
	t.check(verdict_paid["accept"], "enough silver buys the peace")


func test_apply_peace_with_tribute(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var offer := {"from": "red", "to": "blue", "stance": "neutral",
		"give_payment": 500, "give_tribute": null, "give_regions": [],
		"ask_payment": 0, "ask_tribute": {"amount": 100, "turns": 3}, "ask_regions": []}
	DiplomacyRules.apply_offer(data, state, offer)
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "neutral", "the war ends")
	t.check_eq(int(state["factions"]["red"]["treasury"]), 4500, "the payment left red's purse")
	t.check_eq(int(state["factions"]["blue"]["treasury"]), 5500, "and reached blue's")
	t.check_eq(state["tributes"].size(), 1, "a tribute schedule stands")

	for i in range(3):
		DiplomacyRules.process_turn(data, state)
	t.check_eq(int(state["factions"]["red"]["treasury"]), 4800, "three tribute payments came in")
	t.check_eq(int(state["factions"]["blue"]["treasury"]), 5200, "and left the payer")
	t.check(state["tributes"].is_empty(), "the schedule ran its course")
	DiplomacyRules.process_turn(data, state)
	t.check_eq(int(state["factions"]["red"]["treasury"]), 4800, "no payment beyond the term")


func test_cede_region_hands_over_cleanly(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["epsilon"]["garrison"].append(
		{"template": "test_spears", "experience": 0, "strength_pct": 100})
	Fixtures.add_character(state, "red", "governor_e", {"location": "epsilon"})
	SettlementRules.refresh_governors(data, state)

	DiplomacyRules.cede_region(data, state, "epsilon", "blue")
	t.check_eq(state["settlements"]["epsilon"]["owner"], "blue", "epsilon changed hands")
	t.check_eq(state["settlements"]["epsilon"]["garrison"].size(), 0, "no garrison stayed behind")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 1,
		"the garrison marched home to beta")
	t.check_eq(state["characters"]["governor_e"]["location"], "beta",
		"the family fled ahead of the new administration")
	t.check(int(state["settlements"]["epsilon"]["recently_conquered"]) > 0,
		"new subjects still need convincing")
	t.check(state["factions"]["red"]["alive"], "red lives on in beta")


func test_offer_never_takes_capital_or_last_home(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["factions"]["red"]["treasury"] = 1000000
	var for_capital := {"from": "red", "to": "blue", "stance": "neutral",
		"give_payment": 500000, "give_tribute": null, "give_regions": [],
		"ask_payment": 0, "ask_tribute": null, "ask_regions": ["alpha"]}
	t.check(not DiplomacyRules.evaluate_offer(data, state, "red", "blue", for_capital)["accept"],
		"no price buys a faction's last settlement (and capital)")

	# Red asks blue for a region blue does not even own.
	var not_owned: Dictionary = for_capital.duplicate(true)
	not_owned["ask_regions"] = ["gamma"]
	t.check(not DiplomacyRules.evaluate_offer(data, state, "red", "blue", not_owned)["accept"],
		"cannot cede what is not held")


func test_pending_offer_expires(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["pending_offers"].append({"id": "offer_1", "from": "blue", "to": "red",
		"stance": "trade", "expires_turn": 2})
	var events := DiplomacyRules.process_turn(data, state)
	t.check_eq(state["pending_offers"].size(), 1, "a fresh offer waits")
	state["turn"] = 2
	events = DiplomacyRules.process_turn(data, state)
	t.check(state["pending_offers"].is_empty(), "the offer lapsed")
	var expired := false
	for event in events:
		if event.get("kind", "") == "offer_expired":
			expired = true
	t.check(expired, "the player hears the offer lapsed")


func test_senate_courtship_missions(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.missions = {"seal_a_friendship": {"id": "seal_a_friendship", "kind": "make_alliance",
		"deadline_turns": 8, "reward": {"treasury": 500}}}
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	var rng := CampaignRng.seeded(1)

	var notices := SenateRules.process_turn(data, state, rng)
	var mission = state["factions"]["red"]["mission"]
	t.check(mission != null, "the senate found red a mission")
	t.check_eq(mission.get("target_faction", ""), "blue", "the only bordering foreigner is courted")

	DiplomacyRules.set_stance(state, "red", "blue", "alliance")
	var treasury_before := int(state["factions"]["red"]["treasury"])
	notices = SenateRules.process_turn(data, state, rng)
	var completed := false
	for notice in notices:
		if notice.get("kind", "") == "mission_complete":
			completed = true
	t.check(completed, "the alliance completed the mission")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before + 500,
		"the senate pays its debts")
	t.check(state["factions"]["red"]["mission"] == null, "the slate is clean again")


func test_ai_declares_war_on_weak_hated_neighbor(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	DiplomacyRules.record_memory(data, state, "red", "blue", -35.0)
	var events: Array = []
	AiDiplomacy.run(data, state, "red", data.ai_personas["default"], events)
	t.check(DiplomacyRules.at_war(state, "red", "blue"), "the grudge, the border and the weakness add up to war")
	var declared := false
	for event in events:
		if event.get("kind", "") == "war_declared" and event.get("on", "") == "blue":
			declared = true
	t.check(declared, "the declaration is reported")


func test_ai_holds_when_outmatched(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	for i in range(6):
		state["settlements"]["alpha"]["garrison"].append(
			{"template": "test_elites", "experience": 0, "strength_pct": 100})
	DiplomacyRules.record_memory(data, state, "red", "blue", -35.0)
	var events: Array = []
	AiDiplomacy.run(data, state, "red", data.ai_personas["default"], events)
	t.check(not DiplomacyRules.at_war(state, "red", "blue"),
		"hatred without the strength to act on it stays hatred")


func test_ai_sues_for_peace_when_losing(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_army(state, "red", "beta", ["test_mob"])
	Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears"])
	Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears"])
	var events: Array = []
	AiDiplomacy.run(data, state, "red", data.ai_personas["default"], events)
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "neutral",
		"the losing side bought its peace")
	t.check_eq(state["tributes"].size(), 1, "with tribute it could not pay in silver")
	var made := false
	for event in events:
		if event.get("kind", "") == "peace_made":
			made = true
	t.check(made, "the peace is reported")


func test_ai_courts_player_with_pending_offer(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["player_faction"] = "blue"
	Fixtures.add_army(state, "red", "beta", ["test_mob"])
	Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears"])
	Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears"])
	var events: Array = []
	AiDiplomacy.run(data, state, "red", data.ai_personas["default"], events)
	t.check_eq(state["pending_offers"].size(), 1, "an envoy waits at the player's door")
	t.check(DiplomacyRules.at_war(state, "red", "blue"), "nothing changes until the player answers")

	AiDiplomacy.run(data, state, "red", data.ai_personas["default"], events)
	t.check_eq(state["pending_offers"].size(), 1, "one envoy at a time — no spam")

	var game := Game.new()
	game.data = data
	game.resolver = AutoResolver.new()
	game.state = state
	var offer_id: String = state["pending_offers"][0]["id"]
	t.check(game.respond_offer(offer_id, true), "the player can accept it")
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "neutral", "and peace follows")


func test_ai_trades_with_compatible_neighbor(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	for i in range(2):
		state["settlements"]["beta"]["garrison"].append(
			{"template": "test_spears", "experience": 0, "strength_pct": 100})
		state["settlements"]["alpha"]["garrison"].append(
			{"template": "test_spears", "experience": 0, "strength_pct": 100})
	var events: Array = []
	AiDiplomacy.run(data, state, "red", data.ai_personas["default"], events)
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "trade",
		"well-matched neutral neighbors open their markets")
	var agreed := false
	for event in events:
		if event.get("kind", "") == "trade_agreed":
			agreed = true
	t.check(agreed, "the agreement is reported")


func test_trade_mission_accepts_trade_or_alliance(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.missions = {"open_roads": {"id": "open_roads", "kind": "reach_trade_agreement",
		"deadline_turns": 6, "reward": {"treasury": 300}}}
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	var rng := CampaignRng.seeded(2)

	SenateRules.process_turn(data, state, rng)
	var mission = state["factions"]["red"]["mission"]
	t.check(mission != null and mission.get("target_faction", "") == "blue",
		"a trade mission targets the neighbor")
	DiplomacyRules.set_stance(state, "red", "blue", "trade")
	var notices := SenateRules.process_turn(data, state, rng)
	var completed := false
	for notice in notices:
		if notice.get("kind", "") == "mission_complete":
			completed = true
	t.check(completed, "a trade agreement satisfies the senate")
