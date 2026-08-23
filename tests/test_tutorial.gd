extends RefCounted
## The guided opening: data sanity, the world-seed plumbing it relies on, and
## a full headless replay of the scripted path through the real UI.

const TEST_CFG := "user://test_advisor.cfg"


func test_world_seed_recorded(t) -> void:
	var game := Game.new_campaign("julii", 42)
	t.check_eq(int(game.state["world_seed"]), 42, "the seed that built the world is in the state")
	var restored := SaveGame.from_json(SaveGame.to_json(game.state))
	t.check_eq(int(restored.get("world_seed", -1)), 42, "and survives a save round trip")


func test_tutorial_data_loads(t) -> void:
	var steps := TutorialController.load_steps()
	t.check(steps.size() >= 8, "a real walkthrough (got %d steps)" % steps.size())
	var seen := {}
	for step in steps:
		t.check(not seen.has(step["id"]), "step id unique: " + String(step["id"]))
		seen[step["id"]] = true
		t.check(step.has("title") and step.has("body") and step.has("advance"),
			"step %s is complete" % String(step["id"]))


func test_guided_opening_replay(t) -> void:
	## Walk the entire scripted path headless through the real screen. If a
	## balance or data change breaks the script, this breaks CI.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42, "easy")
	var screen := CampaignScreen.create(game)
	screen.tutorial_requested = true
	tree.root.add_child(screen)
	var tutorial := screen.tutorial
	t.check(tutorial != null, "guided mode spawns the tutorial")
	tutorial.config_path = TEST_CFG

	# 1 welcome -> Next
	tutorial._advance_step()
	# 2 inspect_capital: highlights applied, then click Arretium
	t.check(screen.map_view.highlight_regions.has("etruria"), "the capital glows")
	screen.map_view.region_clicked.emit("etruria")
	t.check_eq(tutorial.current_step_index, 2, "selecting the capital advances")
	# 3 read_breakdowns -> Next
	tutorial._advance_step()
	# 4 set_taxes
	game.set_tax_level("etruria", "low")
	screen.refresh()
	t.check_eq(tutorial.current_step_index, 4, "changing taxes advances")
	# 5 queue_building
	var projects := game.available_buildings("etruria")
	t.check(not projects.is_empty(), "the capital has something to build")
	var cheapest_project: Dictionary = projects[0]
	for project in projects:
		if int(project["cost"]) < int(cheapest_project["cost"]):
			cheapest_project = project
	t.check(game.queue_building("etruria", cheapest_project["chain"]), "queueing works")
	screen.refresh()
	t.check_eq(tutorial.current_step_index, 5, "queueing a building advances")
	# 6 recruit_unit
	var units := game.available_units("etruria")
	t.check(not units.is_empty(), "the capital can recruit")
	var cheapest_unit: Dictionary = units[0]
	for unit in units:
		if int(unit["cost"]) < int(cheapest_unit["cost"]):
			cheapest_unit = unit
	t.check(game.queue_unit("etruria", cheapest_unit["id"]), "recruiting works")
	screen.refresh()
	t.check_eq(tutorial.current_step_index, 6, "recruiting advances")
	# 7 first_end_turn
	screen._end_turn()
	t.check_eq(tutorial.current_step_index, 7, "ending the turn advances")
	# 8 select_army
	var army_id := ""
	for candidate in game.state["armies"]:
		if game.state["armies"][candidate]["owner"] == "julii":
			army_id = candidate
	t.check(army_id != "", "the Julii field army exists")
	screen.map_view.region_clicked.emit(game.state["armies"][army_id]["region"])
	screen.region_panel.army_selected.emit(army_id)
	t.check_eq(tutorial.current_step_index, 8, "selecting the army advances")
	# 9 march_army: umbria -> etruria is one plains step
	t.check(game.move_army(army_id, "etruria"), "the army marches home")
	screen.refresh()
	t.check_eq(tutorial.current_step_index, 9, "reaching Etruria advances")
	# 10 lay_siege on liguria (adjacent to etruria; at war with rebels already)
	t.check(game.besiege(army_id, "liguria"), "the siege of Genua is laid")
	screen.refresh()
	t.check_eq(tutorial.current_step_index, 10, "laying siege advances")
	# 11 train_envoy
	t.check(game.train_agent("etruria", "diplomat") != "", "an envoy is trained")
	screen.refresh()
	t.check_eq(tutorial.current_step_index, 11, "training the envoy advances")
	# 12-14 panels
	screen.diplomacy_panel.open_for(game)
	t.check_eq(tutorial.current_step_index, 12, "opening diplomacy advances")
	screen.diplomacy_panel.hide()
	screen.senate_panel.open_for(game)
	t.check_eq(tutorial.current_step_index, 13, "opening the senate advances")
	screen.senate_panel.hide()
	screen.family_panel.open_for(game)
	t.check_eq(tutorial.current_step_index, 14, "opening the family advances")
	screen.family_panel.hide()
	# 15 victory_wrap -> Finish
	tutorial._advance_step()
	t.check(screen.tutorial == null, "finishing clears the tutorial")
	t.check(screen.map_view.highlight_regions.is_empty(), "highlights cleared")
	t.check(AdvisorConfig.tutorial_seen(TEST_CFG), "the walkthrough is remembered")

	DirAccess.remove_absolute(TEST_CFG)
	screen.free()


func test_skip_persists(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42, "easy")
	var screen := CampaignScreen.create(game)
	screen.tutorial_requested = true
	tree.root.add_child(screen)
	screen.tutorial.config_path = TEST_CFG
	screen.tutorial._finish()
	t.check(AdvisorConfig.tutorial_seen(TEST_CFG), "skip marks the walkthrough seen")
	DirAccess.remove_absolute(TEST_CFG)
	screen.free()


func test_config_round_trip(t) -> void:
	var cfg := AdvisorConfig.load_cfg(TEST_CFG)
	t.check_eq(cfg["provider"], "ollama", "defaults to the local model")
	cfg["provider"] = "anthropic"
	cfg["model"] = "claude-haiku-4-5"
	cfg["api_key"] = "sk-test"
	cfg["github_token"] = "ghp_test"
	t.check(AdvisorConfig.save_cfg(cfg, TEST_CFG), "config saves")
	var loaded := AdvisorConfig.load_cfg(TEST_CFG)
	t.check_eq(loaded["provider"], "anthropic", "provider round-trips")
	t.check_eq(loaded["model"], "claude-haiku-4-5", "model round-trips")
	t.check_eq(loaded["api_key"], "sk-test", "key round-trips")
	t.check_eq(loaded["github_token"], "ghp_test", "token round-trips")
	DirAccess.remove_absolute(TEST_CFG)
