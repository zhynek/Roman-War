extends RefCounted
## Phase 6 faction AI: expansion, defence, deliberate war, white peace,
## settlement stewardship — on the synthetic fixture world plus one long
## real-data campaign proving the map actually changes hands.


func _game(data: GameData, state: Dictionary) -> Game:
	var game := Game.new()
	game.data = data
	game.resolver = AutoResolver.new()
	game.state = state
	return game


## --- CombatRules helpers the AI stands on ---------------------------------

func test_raise_army_from_garrison(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var garrison: Array = state["settlements"]["beta"]["garrison"]
	for i in range(3):
		garrison.append({"template": "test_spears", "experience": i, "strength_pct": 100})
	Fixtures.add_character(state, "red", "red_general", {"location": "beta", "command": 4})

	var army_id := CombatRules.raise_army(data, state, "beta", [0, 2], "red_general")
	t.check(army_id != "", "army raised")
	t.check_eq(state["armies"][army_id]["units"].size(), 2, "two units took the field")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 1, "one stayed behind")
	t.check_eq(int(state["settlements"]["beta"]["garrison"][0]["experience"]), 1,
		"the middle unit stayed")
	t.check_eq(state["armies"][army_id]["general"], "red_general", "the general takes command")
	t.check_eq(state["armies"][army_id]["owner"], "red", "army belongs to the settlement's house")
	t.check_eq(float(state["armies"][army_id]["movement_left"]), 0.0, "raised armies march next turn")

	var second := CombatRules.raise_army(data, state, "beta", [0], "red_general")
	t.check(second != "", "second army raised")
	t.check_eq(state["armies"][second]["general"], null,
		"a general already leading an army is not drafted twice")

	t.check(CombatRules.detach_to_garrison(data, state, second, [0]), "units detach back home")
	t.check(not state["armies"].has(second), "an emptied army dissolves")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 1, "garrison holds the detached unit")


## --- Expansion -------------------------------------------------------------

func test_ai_besieges_and_captures_weak_enemy(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# Blue (AI) fields a real army next to red's lightly-held capital.
	Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears", "test_spears"])
	state["settlements"]["beta"]["garrison"].append(
		{"template": "test_spears", "experience": 0, "strength_pct": 100})
	var game := _game(data, state)

	var siege_seen := false
	var captured_seen := false
	for i in range(6):
		var report := game.end_turn()
		for notice in report["ai"]:
			if notice["kind"] == "siege_laid" and notice["region"] == "beta":
				siege_seen = true
			if notice["kind"] == "captured" and notice["region"] == "beta":
				captured_seen = true
	t.check(siege_seen, "the AI laid siege to the weak settlement")
	t.check(captured_seen, "the AI reported the capture")
	t.check_eq(state["settlements"]["beta"]["owner"], "blue", "the settlement changed hands")
	t.check(state["settlements"]["beta"]["garrison"].size() > 0,
		"the conqueror garrisons what it takes")


func test_ai_defends_besieged_settlement(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# Red (the player) besieges blue's home with a token force; a blue army
	# stands in the region and should destroy it rather than starve.
	var blue_army := Fixtures.add_army(state, "blue", "alpha", ["test_spears", "test_spears"])
	var red_army := Fixtures.add_army(state, "red", "beta", ["test_mob"])
	MovementRules.reset_movement(data, state)
	var game := _game(data, state)
	t.check(SiegeRules.begin_siege(data, state, red_army, "alpha"), "the player invests alpha")

	game.end_turn()
	t.check_eq(state["settlements"]["alpha"]["owner"], "blue", "alpha holds")
	t.check(state["settlements"]["alpha"]["siege"] == null, "the siege is broken")
	t.check(not state["armies"].has(red_army) or state["armies"][red_army]["units"].size() < 1
		or int(state["armies"][red_army]["units"][0]["strength_pct"]) < 100,
		"the besieger was mauled or destroyed")
	t.check(state["armies"].has(blue_army), "the defending army survives")


## --- War and peace ---------------------------------------------------------

func test_ai_declares_war_only_when_dominant_and_neutral(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# Peace everywhere, blue rich and strong next to an undefended red.
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	state["factions"]["blue"]["treasury"] = 50000
	Fixtures.add_army(state, "blue", "alpha",
		["test_spears", "test_spears", "test_spears", "test_spears", "test_spears", "test_spears"])
	var game := _game(data, state)

	var report := game.end_turn()
	t.check_eq(DiplomacyRules.stance_between(state, "blue", "red"), "war",
		"the strong neighbor smells weakness")
	var declared := false
	for notice in report["ai"]:
		if notice["kind"] == "war_declared" and notice["faction"] == "blue" and notice["target"] == "red":
			declared = true
	t.check(declared, "the declaration reaches the report")


func test_ai_respects_alliances_and_poverty(t) -> void:
	var data := Fixtures.data()
	var allied := Fixtures.state(data)
	DiplomacyRules.set_stance(allied, "red", "blue", "alliance")
	allied["factions"]["blue"]["treasury"] = 50000
	Fixtures.add_army(allied, "blue", "alpha",
		["test_spears", "test_spears", "test_spears", "test_spears", "test_spears", "test_spears"])
	_game(data, allied).end_turn()
	t.check_eq(DiplomacyRules.stance_between(allied, "blue", "red"), "alliance",
		"an ally is not stabbed for convenience")

	var poor := Fixtures.state(data)
	DiplomacyRules.set_stance(poor, "red", "blue", "neutral")
	poor["factions"]["blue"]["treasury"] = 1000
	Fixtures.add_army(poor, "blue", "alpha",
		["test_spears", "test_spears", "test_spears", "test_spears", "test_spears", "test_spears"])
	_game(data, poor).end_turn()
	t.check_eq(DiplomacyRules.stance_between(poor, "blue", "red"), "neutral",
		"no war without a war chest")


func test_ai_white_peace_ends_stalled_war_but_never_with_player(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# Green joins the far end of the line; blue and green are at war with each
	# other and with red — but red's beta blocks the only road between them, so
	# the blue-green war can never be prosecuted.
	Fixtures.add_faction(state, "green", "delta")
	Fixtures.add_settlement(state, "delta", "green", 1000, {"tribal_government": 1})
	DiplomacyRules.set_stance(state, "green", "blue", "war")
	DiplomacyRules.set_stance(state, "green", "red", "war")
	DiplomacyRules.set_stance(state, "green", "rebels", "war")
	var game := _game(data, state)

	for i in range(10):
		game.end_turn()
	t.check_eq(DiplomacyRules.stance_between(state, "blue", "green"), "neutral",
		"the unprosecutable war guttered out")
	t.check_eq(DiplomacyRules.stance_between(state, "blue", "red"), "war",
		"no AI ever makes peace with the player on its own")
	t.check(not state["ai"]["war_turns"].has(AiDiplomacy.war_key("blue", "red")),
		"wars against the player are not even tracked for peace")


## --- Settlement stewardship ------------------------------------------------

func test_ai_builds_recruits_and_taxes(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["factions"]["blue"]["treasury"] = 10000
	var game := _game(data, state)

	for i in range(4):
		game.end_turn()
	var alpha: Dictionary = state["settlements"]["alpha"]
	t.check(int(alpha["buildings"].get("tribal_government", 0)) >= 2
		or not alpha["construction_queue"].is_empty(),
		"the AI develops its settlement (government first)")
	t.check(alpha["garrison"].size() >= 2, "the AI garrisons toward its threat floor")
	t.check(Constants.TAX_LEVELS.has(alpha["tax_level"]), "taxes stay a legal level")
	for region_id in ["beta", "epsilon"]:
		t.check_eq(state["settlements"][region_id]["tax_level"], "normal",
			"the AI never touches the player's settlements (%s)" % region_id)


func test_ai_relocates_lost_capital(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# Blue's capital alpha has fallen to red; blue keeps a second home on delta.
	Fixtures.add_settlement(state, "delta", "blue", 900, {"tribal_government": 1})
	state["settlements"]["alpha"]["owner"] = "red"
	_game(data, state).end_turn()
	t.check_eq(state["factions"]["blue"]["capital"], "delta",
		"the house rules from its largest remaining city")


## --- The world turns -------------------------------------------------------

func test_long_campaign_map_changes_hands(t) -> void:
	var turns := 40
	var game := Game.new_campaign("julii", 42)
	var state: Dictionary = game.state
	var initial_owners := {}
	for region_id in state["settlements"]:
		initial_owners[region_id] = state["settlements"][region_id]["owner"]

	var captures := 0
	var sieges := 0
	for i in range(turns):
		var report := game.end_turn()
		for notice in report["ai"]:
			if notice["kind"] == "captured":
				captures += 1
			elif notice["kind"] == "siege_laid":
				sieges += 1

	var changed := 0
	var conquerors := {}
	for region_id in state["settlements"]:
		var owner: String = state["settlements"][region_id]["owner"]
		if owner != initial_owners[region_id]:
			changed += 1
			if owner != "rebels":
				conquerors[owner] = true
	t.check(changed >= 5, "the map changes hands (%d regions changed)" % changed)
	t.check(captures >= 3, "AI factions storm cities (%d captures)" % captures)
	t.check(sieges >= 5, "AI factions lay sieges (%d sieges)" % sieges)
	t.check(conquerors.size() >= 3, "conquest is widespread (%d factions took ground)" % conquerors.size())

	# Invariants the AI must never break, whatever it got up to.
	for region_id in state["settlements"]:
		var settlement: Dictionary = state["settlements"][region_id]
		var siege = settlement["siege"]
		t.check(siege == null or state["armies"].has(siege["besieger"]),
			"no orphan siege in " + region_id)
	for army_id in state["armies"]:
		var army: Dictionary = state["armies"][army_id]
		t.check(not army["units"].is_empty(), "no empty army survives: " + army_id)
		t.check(state["factions"][army["owner"]]["alive"],
			"no army of a dead faction: " + army_id)
		t.check(army["units"].size() <= int(game.data.balance["ai"]["army_max_units"]),
			"AI armies respect the size cap: " + army_id)
	var player_touched := false
	for region_id in state["settlements"]:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] == "julii" and settlement["tax_level"] != "normal":
			player_touched = true
	t.check(not player_touched, "the AI never manages the player's settlements")
