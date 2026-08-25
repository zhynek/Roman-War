extends RefCounted
## Campaign agents (Phase 5): recruiting gates, movement across any border,
## spy reports, assassination odds (the personal_security and agent_skill
## effects finally read by the engine), bribery, infiltration, envoy weight
## in negotiations, and upkeep.


func test_recruit_gates_cap_and_cost(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var treasury_before := int(state["factions"]["blue"]["treasury"])
	var agent_id := AgentRules.recruit_agent(data, state, "alpha", "spy")
	t.check(agent_id != "", "the informer is hired")
	t.check_eq(int(state["factions"]["blue"]["treasury"]), treasury_before - 300, "and paid for")
	t.check_eq(state["agents"][agent_id]["region"], "alpha", "he starts at home")
	t.check_near(float(state["agents"][agent_id]["movement_left"]), 0.0, 0.001,
		"he spends his first season settling in")

	data.agent_kinds["assassin"]["building_level"] = 5
	t.check_eq(AgentRules.recruit_agent(data, state, "alpha", "assassin"), "",
		"the building gate holds")
	data.agent_kinds["assassin"]["building_level"] = 1

	for i in range(int(data.balance["agents"]["max_per_faction"]) - 1):
		AgentRules.recruit_agent(data, state, "alpha", "spy")
	t.check_eq(AgentRules.recruit_agent(data, state, "alpha", "spy"), "",
		"the faction cap holds")


func test_agents_cross_any_border(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var agent_id := AgentRules.recruit_agent(data, state, "beta", "spy")
	AgentRules.reset_movement(data, state)
	t.check(AgentRules.move_agent(data, state, agent_id, "alpha"),
		"an informer walks into a hostile land no army could enter")
	t.check_near(float(state["agents"][agent_id]["movement_left"]), 2.0, 0.001,
		"the step cost plains rates")
	t.check(not AgentRules.move_agent(data, state, agent_id, "gamma"),
		"no leaping across the map — adjacency only")
	AgentRules.move_agent(data, state, agent_id, "beta")
	AgentRules.move_agent(data, state, agent_id, "gamma")
	t.check_eq(state["agents"][agent_id]["region"], "gamma", "three steps on a full season")
	t.check(not AgentRules.move_agent(data, state, agent_id, "delta"), "and the season is spent")


func test_scout_report_reads_the_city(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["alpha"]["garrison"].append(
		{"template": "test_mob", "experience": 0, "strength_pct": 80})
	var agent_id := AgentRules.recruit_agent(data, state, "beta", "spy")
	state["agents"][agent_id]["region"] = "alpha"
	var report := AgentRules.scout_report(data, state, agent_id)
	t.check_eq(report.get("owner", ""), "blue", "the report names the master of the city")
	t.check_eq(report.get("garrison", []).size(), 1, "and counts its garrison")
	t.check_eq(int(report["garrison"][0]["strength_pct"]), 80, "down to the state of the ranks")
	t.check(report.has("public_order"), "and reads its mood")

	var diplomat_id := AgentRules.recruit_agent(data, state, "beta", "diplomat")
	t.check(AgentRules.scout_report(data, state, diplomat_id).is_empty(),
		"an envoy is no informer")


func test_assassination_odds_read_security_and_counterintel(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "blue", "victim", {"location": "alpha"})
	var agent_id := AgentRules.recruit_agent(data, state, "beta", "assassin")
	state["agents"][agent_id]["region"] = "alpha"
	var agent: Dictionary = state["agents"][agent_id]

	var bare := AgentRules.assassination_chance(data, state, agent, state["characters"]["victim"])
	t.check_near(bare, 0.55, 0.001, "base odds plus skill")

	state["characters"]["victim"]["ancillaries"] = ["test_bodyguard"]
	var guarded := AgentRules.assassination_chance(data, state, agent, state["characters"]["victim"])
	t.check_near(guarded, 0.55 - 4 * 0.08, 0.001,
		"personal_security is finally read — the bodyguard earns his keep")

	# The victim governs alpha, and his spy-catcher hardens the whole city.
	SettlementRules.refresh_governors(data, state)
	t.check_eq(state["settlements"]["alpha"]["governor"], "victim", "the victim governs")
	state["characters"]["victim"]["ancillaries"] = ["test_bodyguard", "test_spycatcher"]
	var watched := AgentRules.assassination_chance(data, state, agent, state["characters"]["victim"])
	t.check_near(watched, 0.55 - 4 * 0.08 - 3 * 0.05, 0.001,
		"agent_skill is finally read — counter-intelligence bites")


func test_assassination_resolves_and_settles_succession(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "blue", "blue_leader", {"role": "leader", "location": "alpha"})
	Fixtures.add_character(state, "blue", "blue_son", {"role": "family", "location": "alpha"})
	var agent_id := AgentRules.recruit_agent(data, state, "beta", "assassin")
	state["agents"][agent_id]["region"] = "alpha"
	state["agents"][agent_id]["skill"] = 6  # 0.8 chance — and seed 3 rolls under it

	var result := AgentRules.assassinate(data, state, CampaignRng.seeded(3), agent_id, "blue_leader")
	t.check(result["attempted"], "the attempt is made")
	t.check(result["success"], "and at these odds, with this seed, it lands")
	t.check(not state["characters"]["blue_leader"]["alive"], "the leader is dead")
	t.check_eq(state["characters"]["blue_son"]["role"], "leader", "the succession settled at once")

	# One's own faction is never a target.
	Fixtures.add_character(state, "red", "own_man", {"location": "alpha"})
	state["agents"][agent_id]["movement_left"] = 3.0
	var refused := AgentRules.assassinate(data, state, CampaignRng.seeded(3), agent_id, "own_man")
	t.check(not refused["attempted"], "the house does not eat its own")


func test_bribery_buys_leaderless_bands_only(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var band := Fixtures.add_army(state, "blue", "beta", ["test_mob"])
	var led := Fixtures.add_army(state, "blue", "beta", ["test_spears"])
	Fixtures.add_character(state, "blue", "blue_captain", {"location": "beta"})
	state["armies"][led]["general"] = "blue_captain"
	var agent_id := AgentRules.recruit_agent(data, state, "beta", "diplomat")
	var treasury_before := int(state["factions"]["red"]["treasury"])

	var bought := AgentRules.bribe_army(data, state, agent_id, band)
	t.check(bought["success"], "the leaderless band takes the coin")
	t.check_eq(int(bought["cost"]), 180, "priced per head (60 soldiers x 3)")
	t.check(not state["armies"].has(band), "and goes home")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before - 180,
		"the purse paid exactly the band's price")

	state["agents"][agent_id]["movement_left"] = 3.0
	var loyal := AgentRules.bribe_army(data, state, agent_id, led)
	t.check(loyal.get("refused_loyal", false), "men under a general follow the man, not the purse")
	t.check(state["armies"].has(led), "and stay in the field")


func test_infiltration_and_envoy_weight(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var spy_id := AgentRules.recruit_agent(data, state, "beta", "spy")
	state["agents"][spy_id]["region"] = "alpha"
	t.check_eq(AgentRules.infiltration_bonus(data, state, "alpha", "red"), 1,
		"a spy inside opens a gate for his master's assault")
	t.check_eq(AgentRules.infiltration_bonus(data, state, "alpha", "blue"), 0,
		"and no one else's")

	var envoy_id := AgentRules.recruit_agent(data, state, "beta", "diplomat")
	state["agents"][envoy_id]["region"] = "alpha"
	var offer := {"from": "red", "to": "blue", "stance": "", "give_payment": 100,
		"give_tribute": null, "give_regions": [], "ask_payment": 0,
		"ask_tribute": null, "ask_regions": []}
	var verdict := DiplomacyRules.evaluate_offer(data, state, "red", "blue", offer)
	var envoy_factor := 0.0
	for factor in verdict["breakdown"]:
		if factor["label"] == "envoy":
			envoy_factor = float(factor["value"])
	t.check_near(envoy_factor, 400.0, 0.001, "an envoy at their court sweetens the terms")


func test_agent_upkeep_charged(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var upkeep_before := EconomyRules.faction_upkeep(data, state, "red")
	AgentRules.recruit_agent(data, state, "beta", "spy")
	t.check_eq(EconomyRules.faction_upkeep(data, state, "red"), upkeep_before + 40,
		"an informer draws his forty a season")


func test_senate_demands_a_head(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.missions = {"remove_a_king": {"id": "remove_a_king", "kind": "assassinate_leader",
		"deadline_turns": 8, "reward": {"treasury": 800}}}
	Fixtures.add_character(state, "blue", "blue_king", {"role": "leader", "location": "alpha"})
	var rng := CampaignRng.seeded(4)

	SenateRules.process_turn(data, state, rng)
	var mission = state["factions"]["red"]["mission"]
	t.check(mission != null, "the senate has work for red")
	t.check_eq(mission.get("target_character", ""), "blue_king", "a named head")

	CharacterRules.kill(state, "blue_king", data)
	var notices := SenateRules.process_turn(data, state, rng)
	var completed := false
	for notice in notices:
		if notice.get("kind", "") == "mission_complete":
			completed = true
	t.check(completed, "the fallen king completes the mission")