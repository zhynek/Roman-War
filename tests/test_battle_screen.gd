extends RefCounted
## The battle playback's step logic, driven headless: the timeline walks the
## round log, blocks advance to contact then bleed with their side's losses,
## the loser routs after the break, skip lands exactly on the final tableau,
## and the campaign screen hosts and strikes the theatre.


func _army(templates: Array) -> Array:
	var units: Array = []
	for template in templates:
		units.append({"template": template, "experience": 0, "strength_pct": 100})
	return units


func _staged(seed_value: int) -> Dictionary:
	## A real resolution on fixture data — the playback consumes the honest
	## resolver contract, never a hand-forged dict.
	var game := Game.new()
	game.data = Fixtures.data()
	var rng := CampaignRng.seeded(seed_value)
	var attacker := _army(["test_spears", "test_spears"])
	var defender := _army(["test_mob", "test_mob", "test_mob"])
	var result := AutoResolver.new().resolve(game.data, rng, attacker, defender,
		{"terrain": "plains", "wall_level": 0})
	return {"game": game, "result": result}


func _staged_with_rout() -> Dictionary:
	## The first seed whose loser keeps at least one unit on its feet, so the
	## rout is observable. Deterministic: the scan order never changes.
	for seed_value in range(1, 40):
		var staged := _staged(seed_value)
		var result: Dictionary = staged["result"]
		var loser_report: Array = result["defender_report"] \
			if result["winner"] == "attacker" else result["attacker_report"]
		for entry in loser_report:
			if not entry["destroyed"]:
				return staged
	return _staged(1)


func test_blocks_advance_and_bleed(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var staged := _staged_with_rout()
	var result: Dictionary = staged["result"]
	var screen := BattleScreen.create(staged["game"], result, "Red", "Blue")
	tree.root.add_child(screen)

	t.check_eq(String(screen.round_now()["phase"]), "skirmish", "the day opens with skirmish")
	var opening: Array = screen.unit_states()
	var reported := (result["attacker_report"] as Array).size() \
		+ (result["defender_report"] as Array).size()
	t.check_eq(opening.size(), reported, "every reported unit stands on the field")
	var attacker_front := 0.0
	var defender_front := 1.0
	for state in opening:
		if state["side"] == "attacker":
			attacker_front = maxf(attacker_front, float(state["x"]))
		else:
			defender_front = minf(defender_front, float(state["x"]))
	t.check(attacker_front < defender_front, "the lines form up apart")

	screen._t = BattleScreen.ROUND_SECONDS * 2.5  # the middle of the melee
	var melee: Array = screen.unit_states()
	t.check_eq(String(screen.round_now()["phase"]), "melee", "mid-battle sits in the melee")
	var advanced := false
	var bled := false
	for i in range(melee.size()):
		if melee[i]["side"] == "attacker" and float(melee[i]["x"]) > float(opening[i]["x"]):
			advanced = true
		if float(melee[i]["strength"]) < float(opening[i]["strength"]):
			bled = true
	t.check(advanced, "the attacker closed the ground")
	t.check(bled, "the press draws blood")
	var now := screen.round_now()
	t.check(float(now["attacker_morale"]) < 100.0 and float(now["defender_morale"]) < 100.0,
		"both lines' morale is worn down")
	screen.free()


func test_break_routs_the_loser(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var staged := _staged_with_rout()
	var result: Dictionary = staged["result"]
	var screen := BattleScreen.create(staged["game"], result, "Red", "Blue")
	tree.root.add_child(screen)
	var loser: String = "defender" if result["winner"] == "attacker" else "attacker"

	var break_index := -1
	for i in range((result["rounds"] as Array).size()):
		if String(result["rounds"][i]["breaking"]) != "":
			break_index = i
	t.check(break_index >= 0, "the log carries its break")

	screen._t = BattleScreen.ROUND_SECONDS * (float(break_index) + 0.9)
	var routers := 0
	var held_x := {}
	for state in screen.unit_states():
		if state["side"] == loser and not state["fallen"]:
			t.check(state["routing"], "the broken side takes to its heels")
			routers += 1
			held_x[state["y"]] = float(state["x"])
		elif state["side"] != loser:
			t.check(not state["routing"], "the victors hold the field")
	t.check(routers > 0, "someone lives to run")

	# Into the pursuit: morale spent, and the routed further from the enemy.
	screen._t = BattleScreen.ROUND_SECONDS * (float(break_index) + 1.7)
	t.check_eq(float(screen.round_now()[loser + "_morale"]), 0.0,
		"the loser's morale is spent past the break")
	for state in screen.unit_states():
		if state["side"] == loser and not state["fallen"] and held_x.has(state["y"]):
			var toward_home: bool = float(state["x"]) < float(held_x[state["y"]]) \
				if loser == "attacker" else float(state["x"]) > float(held_x[state["y"]])
			t.check(toward_home, "the rout streams away from the field")
	screen.free()


func test_skip_lands_on_the_final_tableau(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var staged := _staged_with_rout()
	var result: Dictionary = staged["result"]
	var screen := BattleScreen.create(staged["game"], result, "Red", "Blue")
	tree.root.add_child(screen)

	screen.skip()
	t.check(screen.is_finished(), "skip runs the clock out")
	var reports: Array = (result["attacker_report"] as Array) + (result["defender_report"] as Array)
	var states: Array = screen.unit_states()
	t.check_eq(states.size(), reports.size(), "the tableau matches the reports")
	for i in range(states.size()):
		t.check(absf(float(states[i]["strength"]) - float(reports[i]["strength_after"])) < 0.01,
			"each block ends at its reported strength")
		if reports[i]["destroyed"]:
			t.check(states[i]["fallen"], "the destroyed lie where they fell")
	t.check(screen._button.text == "Close", "the curtain call offers Close")
	screen.free()


func test_campaign_screen_hosts_the_theatre(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := CampaignScreen.create(Game.new_campaign("julii", 7))
	tree.root.add_child(screen)
	var staged := _staged_with_rout()

	# No log, no theatre — a resolver that does not narrate plays nothing.
	screen._show_battle({}, "Red", "Blue")
	t.check(screen.battle_screen == null, "an empty result opens nothing")

	screen._show_battle(staged["result"], "Red", "Blue")
	t.check(screen.battle_screen != null and screen.battle_screen.get_parent() == screen,
		"a fought battle raises the curtain")
	screen.battle_screen.skip()
	screen.battle_screen._on_button()  # finished: the button is Close
	t.check(screen.battle_screen == null, "closing strikes the set")
	screen.free()
