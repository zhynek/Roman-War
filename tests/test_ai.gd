extends RefCounted
## The campaign AI (Phase 6): economy floors and need-driven builds, tax
## nudges, objective selection, mustering, sieges, and the two safety rails —
## never a hostile act against a faction not already at war, and full
## determinism under a fixed seed.


func test_persona_fallback(t) -> void:
	var data := Fixtures.data()
	var persona := AiRules.persona_for(data, "blue")
	t.check_eq(persona.get("id", ""), "default", "unknown faction persona falls back to default")


func test_garrison_floor_on_the_frontier(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(1)
	var resolver := AutoResolver.new()
	# At peace: no objective, no muster — the economy just garrisons. Alpha
	# borders red-held beta (not allied), so the frontier floor applies.
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	AiRules.take_turn(data, state, rng, resolver, "blue")
	var queued: int = state["settlements"]["alpha"]["recruitment_queue"].size()
	t.check_eq(queued, 4, "frontier settlement garrisons to the frontier floor")


func test_treasury_reserve_respected(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(1)
	var resolver := AutoResolver.new()
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	state["factions"]["blue"]["treasury"] = 1650  # one 100-cost unit above the 1500 reserve
	AiRules.take_turn(data, state, rng, resolver, "blue")
	t.check_eq(state["settlements"]["alpha"]["recruitment_queue"].size(), 1,
		"spending stops at the treasury reserve")
	t.check(state["settlements"]["alpha"]["construction_queue"].is_empty(),
		"no building bought below the reserve either")


func test_low_order_prefers_order_building(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(1)
	var resolver := AutoResolver.new()
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	state["settlements"]["alpha"]["tax_level"] = "very_high"  # order sinks below the need threshold
	AiRules.take_turn(data, state, rng, resolver, "blue")
	var queue: Array = state["settlements"]["alpha"]["construction_queue"]
	t.check(not queue.is_empty(), "an unhappy settlement builds something")
	t.check_eq(queue[0]["chain"], "tribal_government",
		"the order group (government law) wins when order is low")


func test_tax_nudges_track_order(t) -> void:
	var data := Fixtures.data()
	var lowered := Fixtures.state(data)
	var rng := CampaignRng.seeded(1)
	var resolver := AutoResolver.new()
	DiplomacyRules.set_stance(lowered, "red", "blue", "neutral")
	lowered["settlements"]["alpha"]["tax_level"] = "very_high"
	AiRules.take_turn(data, lowered, rng, resolver, "blue")
	t.check_eq(lowered["settlements"]["alpha"]["tax_level"], "high",
		"crushing taxes ease off when order is low")

	var raised := Fixtures.state(data)
	DiplomacyRules.set_stance(raised, "red", "blue", "neutral")
	raised["settlements"]["alpha"]["tax_level"] = "very_low"
	for i in range(4):
		raised["settlements"]["alpha"]["garrison"].append(
			{"template": "test_mob", "experience": 0, "strength_pct": 100})
	AiRules.take_turn(data, raised, rng, resolver, "blue")
	t.check_eq(raised["settlements"]["alpha"]["tax_level"], "low",
		"a contented, garrisoned town can bear more tax")


func test_no_hostile_act_without_war(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(3)
	var resolver := AutoResolver.new()
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	# Blue matches red in strength: neither weakness tempts nor the strength
	# gate opens, so the peace must simply hold.
	var red_army := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	var blue_army := Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears"])
	var events := AiRules.take_turn(data, state, rng, resolver, "red")
	t.check(state["armies"].has(blue_army), "the matched army is untouched")
	t.check(not DiplomacyRules.at_war(state, "red", "blue"),
		"no war was declared by the AI's turn")
	for event in events:
		t.check(not event.get("kind", "") in ["war_declared", "ai_attack", "ai_siege", "ai_conquest"],
			"nothing hostile to report (got %s)" % event.get("kind", ""))
	t.check(state["armies"].has(red_army), "own army stands")


func test_attacks_favorable_battle_at_war(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(3)
	var resolver := AutoResolver.new()
	Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	var events := AiRules.take_turn(data, state, rng, resolver, "red")
	var attacked := false
	for event in events:
		if event.get("kind", "") == "ai_attack" and event.get("defender", "") == "blue":
			attacked = true
	t.check(attacked, "at war, the AI takes the favorable battle")


func test_besieges_and_captures_rebel_settlement(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# Alpha becomes a rebel TOWN (tier 2 -> 3 turns of supplies, so the
	# equipment-ready assault at turn 3 beats the starve-out); red is the only
	# acting AI (rebels "play" the player slot so they stay passive).
	state["player_faction"] = "rebels"
	state["settlements"]["alpha"]["owner"] = "rebels"
	state["settlements"]["alpha"]["buildings"] = {"tribal_government": 2}
	state["factions"]["blue"]["alive"] = false
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	MovementRules.reset_movement(data, state)

	var game := Game.new()
	game.data = data
	game.resolver = AutoResolver.new()
	game.state = state
	var conquered := false
	for i in range(8):
		var report := game.end_turn()
		for event in report["ai"]:
			if event.get("kind", "") == "ai_conquest" and event.get("region", "") == "alpha":
				conquered = true
		if conquered:
			break
	t.check(conquered, "the AI reported the conquest by assault")
	t.check_eq(state["settlements"]["alpha"]["owner"], "red", "the rebel town fell to the AI")
	t.check(int(state["settlements"]["alpha"]["recently_conquered"]) > 0,
		"capture went through the occupation path")


func test_defends_and_relieves_a_siege(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["player_faction"] = "rebels"
	# Blue is made incapable of suing for peace (a rational lone raider would
	# simply buy one) and pointed at epsilon. Red starts with NO field army —
	# otherwise blue would honestly defend its home instead of raiding — and
	# the relief force marches in only once the siege is real.
	data.ai_personas["warlike"] = data.ai_personas["default"].duplicate(true)
	data.ai_personas["warlike"]["peace_willingness"] = 0.0
	data.factions["blue"]["ai_persona"] = "warlike"
	state["factions"]["blue"]["ai"] = {
		"objective": {"kind": "take", "region": "epsilon", "set_turn": 0},
		"muster": "alpha",
	}
	Fixtures.add_army(state, "blue", "delta", ["test_mob"])
	MovementRules.reset_movement(data, state)

	var game := Game.new()
	game.data = data
	game.resolver = AutoResolver.new()
	game.state = state
	var siege_seen := false
	var relief_sent := false
	for i in range(8):
		game.end_turn()
		if state["settlements"]["epsilon"]["siege"] != null:
			siege_seen = true
			if not relief_sent:
				relief_sent = true
				Fixtures.add_army(state, "red", "gamma", ["test_spears", "test_spears", "test_spears"])
	t.check(siege_seen, "the raider actually invested epsilon")
	t.check(relief_sent, "and a relief force marched")
	t.check_eq(state["settlements"]["epsilon"]["owner"], "red", "epsilon held")
	t.check(state["settlements"]["epsilon"]["siege"] == null, "the siege was broken")
	var blue_armies := 0
	for army in state["armies"].values():
		if army["owner"] == "blue":
			blue_armies += 1
	t.check_eq(blue_armies, 0, "the raider was destroyed")


func test_bought_peace_holds_as_a_truce(t) -> void:
	## The flap this guards against: a losing side buys peace, and the winner
	## re-declares the same season, forever. A concluded peace banks decaying
	## goodwill on both sides, so the truce holds until it fades.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["player_faction"] = "rebels"  # red and blue are both AI here
	Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	var events: Array = []
	AiDiplomacy.run(data, state, "blue", data.ai_personas["default"], events)
	var made := false
	for event in events:
		if event.get("kind", "") == "peace_made":
			made = true
	t.check(made, "the outmatched side bought its peace")

	events.clear()
	AiDiplomacy.run(data, state, "red", data.ai_personas["default"], events)
	t.check(not DiplomacyRules.at_war(state, "red", "blue"),
		"the winner does not re-declare the same season — the truce holds")
	for i in range(6):
		DiplomacyRules.decay_memories(data, state)
		AiDiplomacy.run(data, state, "red", data.ai_personas["default"], [])
	t.check(not DiplomacyRules.at_war(state, "red", "blue"),
		"and still holds three years on, while the goodwill lasts")


func test_musters_and_raises_field_army(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(5)
	var resolver := AutoResolver.new()
	var persona: Dictionary = data.ai_personas["default"]
	state["factions"]["blue"]["ai"] = {
		"objective": {"kind": "take", "region": "beta", "set_turn": 0},
		"muster": "alpha",
	}
	for i in range(8):
		state["settlements"]["alpha"]["garrison"].append(
			{"template": "test_mob", "experience": 0, "strength_pct": 100})
	# Beta is defended well enough that the fresh army waits at the muster.
	state["settlements"]["beta"]["garrison"].append(
		{"template": "test_spears", "experience": 0, "strength_pct": 100})
	state["settlements"]["beta"]["garrison"].append(
		{"template": "test_spears", "experience": 0, "strength_pct": 100})

	var events: Array = []
	AiMilitary.run(data, state, rng, resolver, "blue", persona, events)
	var raised := ""
	for army_id in state["armies"]:
		if state["armies"][army_id]["owner"] == "blue":
			raised = army_id
	t.check(raised != "", "a field army was raised from the muster surplus")
	t.check_eq(state["armies"][raised]["units"].size(), 4, "surplus above the frontier floor marches")
	t.check_eq(state["settlements"]["alpha"]["garrison"].size(), 4, "the floor garrison stays")
	t.check_near(float(state["armies"][raised]["movement_left"]), 0.0, 0.001,
		"a fresh army spends its first turn forming up")
	t.check(state["settlements"]["beta"]["siege"] == null, "no siege bum-rushed with zero movement")

	# Next turn, with the ward gone, the army marches out and invests beta.
	state["settlements"]["beta"]["garrison"].clear()
	MovementRules.reset_movement(data, state)
	AiMilitary.run(data, state, rng, resolver, "blue", persona, events)
	var siege = state["settlements"]["beta"]["siege"]
	t.check(siege != null and siege["besieger"] == raised, "the raised army invests the objective")


func test_merge_never_eats_a_besieger(t) -> void:
	## A besieging army merged away leaves settlement.siege pointing at a dead
	## id and silently resets the siege — so besiegers never merge at all.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var besieger := Fixtures.add_army(state, "blue", "alpha", ["test_mob", "test_mob"])
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, besieger, "beta"), "the siege is laid")

	# A general-led relief stack arrives in the same region: normally the
	# generaled army absorbs the leaderless one.
	var relief := Fixtures.add_army(state, "blue", "beta", ["test_mob"])
	Fixtures.add_character(state, "blue", "blue_general", {"location": "beta"})
	state["armies"][relief]["general"] = "blue_general"

	state["factions"]["blue"]["ai"] = {"objective": {"kind": "take", "region": "beta", "set_turn": 0}, "muster": "alpha"}
	var events: Array = []
	AiMilitary.run(data, state, CampaignRng.seeded(2), AutoResolver.new(), "blue",
		data.ai_personas["default"], events)
	t.check(state["armies"].has(besieger), "the besieger survives as itself")
	var siege = state["settlements"]["beta"]["siege"]
	t.check(siege != null and siege["besieger"] == besieger, "and the siege pointer holds")


func test_ai_turn_is_deterministic(t) -> void:
	var data := Fixtures.data()
	var first := Fixtures.state(data)
	Fixtures.add_army(first, "red", "beta", ["test_spears", "test_spears"])
	Fixtures.add_army(first, "blue", "alpha", ["test_mob", "test_mob"])
	MovementRules.reset_movement(data, first)
	var second: Dictionary = first.duplicate(true)

	var game_a := Game.new()
	game_a.data = data
	game_a.resolver = AutoResolver.new()
	game_a.state = first
	var game_b := Game.new()
	game_b.data = data
	game_b.resolver = AutoResolver.new()
	game_b.state = second
	for i in range(6):
		game_a.end_turn()
		game_b.end_turn()
	t.check_eq(JSON.stringify(first), JSON.stringify(second),
		"AI-driven turns replay identically from identical state")


func test_ensure_state_keys_fills_ai(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["factions"]["red"].erase("ai")
	NewGame.ensure_state_keys(state)
	t.check(state["factions"]["red"].has("ai"), "a pre-phase save gains the ai key on load")


func test_ai_adopts_the_best_priced_craft(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var persona: Dictionary = data.ai_personas["default"]
	var red: Dictionary = state["factions"]["red"]
	# At peace, with a school built: letters (civic, 400) out-prices smithing
	# (military, 600) on the value-per-denarius score.
	state["factions"]["red"]["diplomacy"]["blue"] = "neutral"
	state["factions"]["blue"]["diplomacy"]["red"] = "neutral"
	state["settlements"]["beta"]["buildings"]["test_education"] = 1
	red["knowledge"]["test_smithing"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	red["knowledge"]["test_letters"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	AiKnowledge.run(data, state, "red", persona)
	t.check_eq(String(red["knowledge"]["test_letters"]["stage"]), "adopting",
		"at peace the court funds the cheap civic craft")
	t.check_eq(String(red["knowledge"]["test_smithing"]["stage"]), "aware",
		"and only one program at a time")
	AiKnowledge.run(data, state, "red", persona)
	t.check_eq(String(red["knowledge"]["test_smithing"]["stage"]), "aware",
		"hands stay full while the program runs")


func test_ai_at_war_arms_first(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var persona: Dictionary = data.ai_personas["default"]
	var red: Dictionary = state["factions"]["red"]
	# Red is at war with blue (fixture default): the war boost doubles the
	# military score, 2.0/600 beating 1.0/400.
	state["settlements"]["beta"]["buildings"]["test_education"] = 1
	red["knowledge"]["test_smithing"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	red["knowledge"]["test_letters"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	AiKnowledge.run(data, state, "red", persona)
	t.check_eq(String(red["knowledge"]["test_smithing"]["stage"]), "adopting",
		"a court at war funds the arsenal first")


func test_ai_adoption_respects_reserve_and_prerequisites(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var persona: Dictionary = data.ai_personas["default"]
	var red: Dictionary = state["factions"]["red"]
	red["knowledge"]["test_smithing"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	red["knowledge"]["test_letters"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	red["treasury"] = 2000
	AiKnowledge.run(data, state, "red", persona)
	t.check_eq(String(red["knowledge"]["test_smithing"]["stage"]), "aware",
		"600 would break the 1500 reserve: the war craft waits")
	t.check_eq(String(red["knowledge"]["test_letters"]["stage"]), "aware",
		"and the school-less court cannot take up letters at any price")
