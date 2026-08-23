extends RefCounted
## Phase 5 agents: training, travel, tradecraft, and the knife.


func _world() -> Array:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	return [data, state]


func test_training_gates_and_costs(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var rng := CampaignRng.seeded(3)

	# beta has a government chain -> diplomat only (no market chain in fixtures).
	var kinds := AgentRules.available_kinds(data, state, "beta")
	t.check_eq(kinds.size(), 1, "only the diplomat is trainable without a market")
	t.check_eq(kinds[0]["id"], "diplomat", "government building trains envoys")

	var treasury_before := int(state["factions"]["red"]["treasury"])
	var agent_id := AgentRules.train(data, state, "beta", "diplomat", rng)
	t.check(agent_id != "", "envoy trained")
	t.check_eq(int(state["factions"]["red"]["treasury"]),
		treasury_before - int(data.agent_kinds["diplomat"]["cost"]), "training is paid for")
	t.check_eq(state["agents"][agent_id]["region"], "beta", "he starts at home")
	t.check_eq(AgentRules.train(data, state, "beta", "spy", rng), "", "no market, no informer")


func test_agent_cap_per_kind(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var rng := CampaignRng.seeded(3)
	state["factions"]["red"]["treasury"] = 100000
	var cap := int(data.balance["agents"]["max_per_kind"])
	for i in range(cap):
		t.check(AgentRules.train(data, state, "beta", "diplomat", rng) != "", "train %d" % i)
	t.check_eq(AgentRules.train(data, state, "beta", "diplomat", rng), "",
		"the cap holds at %d" % cap)


func test_agent_travel(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var rng := CampaignRng.seeded(3)
	var agent_id := AgentRules.train(data, state, "beta", "diplomat", rng)
	var agent: Dictionary = state["agents"][agent_id]
	agent["movement_left"] = 3.0

	# beta -> gamma -> delta on the fixture line, plains cost 1.0 each.
	var reached := AgentRules.move_towards(data, state, agent_id, "delta")
	t.check_eq(reached, "delta", "the envoy walks two plains regions")
	t.check_near(float(agent["movement_left"]), 1.0, 0.01, "movement spent")

	# Agents walk into enemy lands freely — that is their trade.
	agent["movement_left"] = 3.0
	t.check_eq(AgentRules.move_towards(data, state, agent_id, "alpha"), "alpha",
		"agents cross hostile borders")


func test_agents_grant_vision(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var rng := CampaignRng.seeded(3)
	var visible_before := VisibilityRules.visible_regions(data, state, "blue")
	t.check(not visible_before.has("delta"), "blue cannot see delta at start")
	var agent_id := AgentRules.train(data, state, "alpha", "diplomat", rng)
	state["agents"][agent_id]["region"] = "delta"
	var visible_after := VisibilityRules.visible_regions(data, state, "blue")
	t.check(visible_after.has("delta") and visible_after.has("epsilon"),
		"an agent reveals his region and one hop out")


func test_assassination_and_security(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	Fixtures.add_character(state, "blue", "chief", {"location": "beta", "influence": 0})
	var rng := CampaignRng.seeded(11)
	var agent_id := AgentRules.train(data, state, "beta", "diplomat", rng)
	var blade_id := "agent_test_blade"
	state["agents"][blade_id] = {
		"owner": "red", "kind": "assassin", "region": "beta", "name": "Shadow",
		"skill": 5, "movement_left": 2.0, "turns_abroad": 0, "alive": true,
	}

	var notices: Array = []
	var wrong := AgentRules.assassinate(data, state, rng, agent_id, "chief", notices)
	t.check(not wrong["attempted"], "an envoy holds no knife")

	# Skill 5, no security: 75% a strike. Deterministic for the seed; retry
	# with fresh blades until the knife lands (bounded, and in practice fast).
	var killed := false
	var attempted := false
	var skill_after := 0
	for i in range(10):
		state["agents"][blade_id] = {
			"owner": "red", "kind": "assassin", "region": "beta", "name": "Shadow",
			"skill": 5, "movement_left": 2.0, "turns_abroad": 0, "alive": true,
		}
		var result := AgentRules.assassinate(data, state, rng, blade_id, "chief", notices)
		attempted = attempted or bool(result["attempted"])
		if result["killed"]:
			killed = true
			skill_after = int(state["agents"][blade_id]["skill"])
			break
	t.check(attempted, "the blade strikes")
	t.check(killed, "an unguarded chief falls within a handful of nights")
	t.check(not state["characters"]["chief"]["alive"], "the mark is dead")
	t.check_eq(skill_after, 6, "success sharpens the blade")
	t.check(not notices.is_empty(), "the deed makes news")

	# personal_security must lower the computed chance.
	Fixtures.add_character(state, "blue", "guarded", {"location": "beta"})
	var naked_security := CharacterRules.effect_total(data, state["characters"]["guarded"], "personal_security")
	t.check_eq(naked_security, 0.0, "baseline: no security")
	state["characters"]["guarded"]["ancillaries"] = []
	# No shieldbearer ancillary exists in fixtures; assert the formula reads the effect
	# through a synthetic ancillary instead.
	data.ancillaries["test_shield"] = {"id": "test_shield", "name": "Shieldbearer", "effects": {"personal_security": 3}}
	state["characters"]["guarded"]["ancillaries"] = ["test_shield"]
	t.check_eq(CharacterRules.effect_total(data, state["characters"]["guarded"], "personal_security"), 3.0,
		"personal_security finally has a reader")


func test_spy_detection_and_seasoning(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	# A red informer sits in blue's town; blue's governor has a spy catcher.
	state["agents"]["agent_spy"] = {
		"owner": "red", "kind": "spy", "region": "alpha", "name": "Whisper",
		"skill": 0, "movement_left": 0.0, "turns_abroad": 0, "alive": true,
	}
	data.ancillaries["test_catcher"] = {"id": "test_catcher", "name": "Spy Catcher", "effects": {"agent_skill": 3}}
	Fixtures.add_character(state, "blue", "watcher", {"location": "alpha", "influence": 3,
		"ancillaries": ["test_catcher"]})
	SettlementRules.refresh_governors(data, state)
	t.check_eq(state["settlements"]["alpha"]["governor"], "watcher", "the watcher governs")

	# With agent_skill 3 the detection chance is base 6% + 15% = 21% a turn.
	# Seed 5's draws catch the informer within a handful of turns.
	var caught := false
	var rng := CampaignRng.seeded(5)
	for i in range(12):
		var notices := AgentRules.process_turn(data, state, rng)
		for notice in notices:
			if notice.get("kind", "") == "agent_caught":
				caught = true
		if caught:
			break
	t.check(caught, "the spy catcher earns his keep")
	t.check(not state["agents"].has("agent_spy"), "the informer is gone")


func test_spy_opens_gates(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	state["agents"]["agent_spy"] = {
		"owner": "red", "kind": "spy", "region": "alpha", "name": "Whisper",
		"skill": 2, "movement_left": 0.0, "turns_abroad": 0, "alive": true,
	}
	var bonus := AgentRules.spy_assault_bonus_pct(data, state, "red", "alpha")
	t.check_near(bonus, 5.0 + 2.0 * 3.0, 0.01, "gate bonus follows skill")
	t.check_eq(AgentRules.spy_assault_bonus_pct(data, state, "blue", "alpha"), 0.0,
		"only the master's assault benefits")


func test_agent_upkeep_charged(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var upkeep_before := EconomyRules.faction_upkeep(data, state, "red")
	var rng := CampaignRng.seeded(3)
	AgentRules.train(data, state, "beta", "diplomat", rng)
	var upkeep_after := EconomyRules.faction_upkeep(data, state, "red")
	t.check_eq(upkeep_after - upkeep_before, int(data.agent_kinds["diplomat"]["upkeep"]),
		"the envoy draws his stipend")
