extends RefCounted
## Phase 6: the AI plays the game — tunes its settlements, defends what it
## holds, and expands into the world — deterministically.


func test_ai_manages_settlements(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["alpha"]["tax_level"] = "very_high"
	var rng := CampaignRng.seeded(9)
	AiRules.take_turn(data, state, "blue", rng, AutoResolver.new(), [])

	t.check_eq(state["settlements"]["alpha"]["tax_level"], "high",
		"AI eases taxes that are rioting the town")
	t.check_eq(state["settlements"]["alpha"]["construction_queue"].size(), 1,
		"AI queues a building with money in hand")
	t.check_eq(state["settlements"]["alpha"]["construction_queue"][0]["chain"], "tribal_government",
		"government outranks every other chain in the build priorities")
	t.check_eq(state["settlements"]["alpha"]["recruitment_queue"].size(), 1,
		"AI garrisons an undefended settlement")


func test_ai_respects_reserves(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["factions"]["blue"]["treasury"] = 200  # too poor for reserve-backed spending
	var rng := CampaignRng.seeded(9)
	AiRules.take_turn(data, state, "blue", rng, AutoResolver.new(), [])
	t.check(state["settlements"]["alpha"]["construction_queue"].is_empty(),
		"a broke AI does not build")
	t.check(state["settlements"]["alpha"]["recruitment_queue"].is_empty(),
		"a broke AI does not recruit")


func test_ai_relieves_a_siege(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var besieger := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	SiegeRules.begin_siege(data, state, besieger, "alpha")
	t.check(state["settlements"]["alpha"]["siege"] != null, "siege laid")

	var relief := Fixtures.add_army(state, "blue", "alpha", ["test_elites", "test_elites", "test_elites"])
	var notices: Array = []
	var rng := CampaignRng.seeded(4)
	AiRules.take_turn(data, state, "blue", rng, AutoResolver.new(), notices)

	var battle_fought := false
	for notice in notices:
		if notice.get("kind", "") == "battle":
			battle_fought = true
	t.check(battle_fought, "the AI attacked the besieger")
	t.check(not state["armies"].has(besieger) or state["armies"].has(relief),
		"the relief army came to grips with the enemy")


func test_form_army_and_return(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var garrison: Array = state["settlements"]["beta"]["garrison"]
	garrison.append({"template": "test_spears", "experience": 0, "strength_pct": 100})
	garrison.append({"template": "test_spears", "experience": 2, "strength_pct": 100})

	var army_id := ArmyRules.form_army(data, state, "beta")
	t.check(army_id != "", "garrison fielded as an army")
	t.check(state["settlements"]["beta"]["garrison"].is_empty(), "garrison emptied")
	t.check_eq(state["armies"][army_id]["units"].size(), 2, "both units marched out")
	t.check_eq(float(state["armies"][army_id]["movement_left"]), 0.0,
		"a freshly mustered army marches next season")

	t.check(CombatRules.garrison_army(data, state, army_id, "beta"), "and can garrison back")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 2, "units returned to the walls")


func test_form_army_with_general(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "marcus", {"location": "beta", "command": 4})
	state["settlements"]["beta"]["garrison"].append(
		{"template": "test_spears", "experience": 0, "strength_pct": 100})
	var army_id := ArmyRules.form_army(data, state, "beta", [], "marcus")
	t.check_eq(state["armies"][army_id]["general"], "marcus", "the governor takes command")

	# A general already leading an army cannot lead a second one.
	state["settlements"]["beta"]["garrison"].append(
		{"template": "test_spears", "experience": 0, "strength_pct": 100})
	var second := ArmyRules.form_army(data, state, "beta", [], "marcus")
	t.check_eq(state["armies"][second]["general"], null, "no man leads two armies")


func test_war_candidate_gates(t) -> void:
	## The declaration gates themselves: strength ratio, borders, and the
	## protection of existing treaties.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	var ai_rules: Dictionary = data.balance["ai"]

	# Red is not 1.4x blue's strength: no candidate.
	state["settlements"]["alpha"]["garrison"] = [
		{"template": "test_mob", "experience": 0, "strength_pct": 100},
		{"template": "test_mob", "experience": 0, "strength_pct": 100},
	]
	var red_strength := AiRules._faction_strength(data, state, "red")
	t.check_eq(AiRules._war_candidate(data, state, "red", red_strength, ai_rules), "",
		"too weak to pick a fight")

	# Overwhelming strength finds the neighbor.
	state["settlements"]["beta"]["garrison"] = [
		{"template": "test_elites", "experience": 3, "strength_pct": 100},
		{"template": "test_elites", "experience": 3, "strength_pct": 100},
		{"template": "test_elites", "experience": 3, "strength_pct": 100},
	]
	red_strength = AiRules._faction_strength(data, state, "red")
	t.check_eq(AiRules._war_candidate(data, state, "red", red_strength, ai_rules), "blue",
		"a weak bordering neighbor is the candidate")

	# An alliance protects the weak neighbor entirely.
	DiplomacyRules.set_stance(state, "red", "blue", "alliance")
	t.check_eq(AiRules._war_candidate(data, state, "red", red_strength, ai_rules), "",
		"allies are never candidates")


func test_ai_declares_no_war_without_cause(t) -> void:
	## At war already (with red): the war cap stops any new declaration, so no
	## RNG is even drawn for diplomacy.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(1)
	AiRules.take_turn(data, state, "blue", rng, AutoResolver.new(), [])
	t.check_eq(DiplomacyRules.stance_between(state, "blue", "red"), "war",
		"existing war unchanged")


func test_ai_expands_into_the_world(t) -> void:
	## The real campaign: after 30 turns of AI play the map must have changed
	## hands — rebels lose ground — and the Roman houses must not have turned
	## on each other before any civil war.
	var game := Game.new_campaign("julii", 42)
	var rebel_regions_start := _regions_of(game.state, "rebels")
	var ai_regions_start := {}
	for faction_id in game.state["factions"]:
		ai_regions_start[faction_id] = _regions_of(game.state, faction_id)

	for i in range(30):
		game.end_turn()

	var rebel_regions_end := _regions_of(game.state, "rebels")
	t.check(rebel_regions_end < rebel_regions_start,
		"rebels lost ground (%d -> %d)" % [rebel_regions_start, rebel_regions_end])

	var some_ai_grew := false
	for faction_id in game.state["factions"]:
		if faction_id in ["rebels", "julii"]:
			continue
		if _regions_of(game.state, faction_id) > int(ai_regions_start[faction_id]):
			some_ai_grew = true
	t.check(some_ai_grew, "at least one AI faction expanded")

	for house in ["julii", "junii", "cornelii"]:
		for other in ["julii", "junii", "cornelii", "senate"]:
			if house == other:
				continue
			if game.state["factions"][house]["at_civil_war"] \
					or game.state["factions"][other]["at_civil_war"]:
				continue
			t.check(not DiplomacyRules.at_war(game.state, house, other),
				"%s at war with %s before any civil war" % [house, other])

	# The AI's bookkeeping must survive a save round trip and march in step.
	var restored := SaveGame.from_json(SaveGame.to_json(game.state))
	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored
	game.end_turn()
	resumed.end_turn()
	t.check_eq(_canonical(game.state), _canonical(resumed.state),
		"AI decisions replay identically from a save")


func _regions_of(state: Dictionary, faction_id: String) -> int:
	var count := 0
	for settlement in state["settlements"].values():
		if settlement["owner"] == faction_id:
			count += 1
	return count


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))
