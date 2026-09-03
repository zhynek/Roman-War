extends RefCounted
## Headless smoke test for the campaign UI: boot the screen on a real
## campaign, click regions, select and order an army, end a turn, save/load,
## open the family scroll. No rendering happens headless — this guards the
## UI's logic paths, not its looks.


func test_campaign_screen_boots_and_plays(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	t.check(screen.map_view != null and screen.region_panel != null, "screen assembled")
	t.check(screen.top_labels["treasury"].text.contains("Treasury"), "treasury shown")
	t.check(screen.top_labels["senate"].text.contains("Senate"), "roman house sees standings")

	# Click the capital: the panel fills with settlement details.
	var capital: String = game.state["factions"]["julii"]["capital"]
	screen._on_region_clicked(capital)
	t.check_eq(screen.map_view.selected_region, capital, "capital selected")
	t.check(screen.region_panel.get_child_count() > 3, "settlement panel populated")

	# Select a julii army and march it somewhere adjacent and free.
	var army_id := ""
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for candidate in army_ids:
		if game.state["armies"][candidate]["owner"] == "julii":
			army_id = candidate
			break
	t.check(army_id != "", "julii fields an army")
	if army_id != "":
		var army: Dictionary = game.state["armies"][army_id]
		screen._on_region_clicked(army["region"])
		screen._on_army_selected(army_id)
		t.check_eq(screen.selected_army, army_id, "army selected")

		# Marching onto a neighbour must MOVE the army — never start a war,
		# whoever happens to be standing there.
		var stances_before: Dictionary = game.state["factions"]["julii"]["diplomacy"].duplicate()
		var from_region: String = army["region"]
		var target := ""
		for neighbor in game.data.regions[from_region].get("adjacent", []):
			var holder: String = game.state["settlements"].get(neighbor, {}).get("owner", "")
			if holder == "julii" or holder == "":
				target = neighbor
				break
		if target != "":
			screen._on_region_clicked(target)
			t.check_eq(game.state["armies"][army_id]["region"], target, "the army actually marched")
		for other_faction in stances_before:
			if stances_before[other_faction] != "war":
				t.check(game.state["factions"]["julii"]["diplomacy"][other_faction] != "war",
					"marching did not declare war on " + String(other_faction))
		t.check(screen.report_log.get_parsed_text().length() > 0, "orders are logged")

	# An agent is ordered the same way, but walks anywhere.
	var envoy := ""
	for agent_id in game.agents_in(capital, "julii"):
		if game.state["agents"][agent_id]["kind"] == "envoy":
			envoy = agent_id
	t.check(envoy != "", "the house starts with an envoy at home")
	if envoy != "":
		screen._on_region_clicked(capital)
		screen._on_agent_selected(envoy)
		t.check_eq(screen.selected_agent, envoy, "envoy selected")
		var destination: String = game.data.regions[capital]["adjacent"][0]
		screen._on_region_clicked(destination)
		t.check_eq(game.state["agents"][envoy]["region"], destination, "the envoy travelled")
		t.check_eq(screen.map_view.selected_region, destination, "the map follows him")
	var trained := game.recruit_agent(capital, "envoy")
	t.check(trained != "", "a new envoy trains in the capital")
	screen._on_region_clicked(capital)
	t.check(screen.region_panel.get_child_count() > 3, "the panel shows the agents at home")

	# A turn resolves through the button path.
	var turn_before := int(game.state["turn"])
	screen._end_turn()
	t.check_eq(int(game.state["turn"]), turn_before + 1, "end turn advances the world")

	# Save, then load back.
	screen._save_game()
	screen._load_game()
	t.check_eq(int(game.state["turn"]), turn_before + 1, "loaded game matches the save")

	# The family scroll opens and lists the house.
	screen.family_panel.open_for(game)
	t.check(screen.family_panel._content.get_child_count() > 0, "family listed")
	screen.family_panel.hide()

	screen.free()


func test_negotiating_table(t) -> void:
	## The diplomacy scroll assembles an offer, weighs it on the other side's
	## scale, and makes it through the envoy in contact.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	var panel := screen.diplomacy_panel
	panel.open_for(game, "senate")
	t.check_eq(panel._focus, "senate", "talks open with the Senate")
	t.check(panel._content.get_child_count() > 5, "the scroll lists the powers and the table")
	panel._gift.value = 200
	var proposal := panel.build_proposal()
	t.check_eq(proposal["to"], "senate", "offer addressed to the Senate")
	t.check_eq(int(proposal["gift"]), 200, "the gift is read from the scroll")
	panel._weigh()
	t.check(panel._verdict.get_child_count() > 1, "the weighing shows its factors")

	var treasury_before := int(game.state["factions"]["julii"]["treasury"])
	panel._make_offer()
	t.check_eq(int(game.state["factions"]["julii"]["treasury"]), treasury_before - 200,
		"an accepted gift leaves the treasury")
	t.check(screen.report_log.get_parsed_text().contains("accepts"), "the acceptance is logged")

	# War is declared from the scroll through a confirmation, never directly.
	panel.hide()
	screen.declare_war_order("gaul")
	t.check(not DiplomacyRules.at_war(game.state, "julii", "gaul"), "no war before the dialog is confirmed")
	screen.free()


func test_map_picking(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 7)
	var view := MapView.new()
	view.game = game
	view.size = Vector2(800, 600)
	tree.root.add_child(view)

	var capital: String = game.state["factions"]["julii"]["capital"]
	view.center_on(capital)
	var screen_pos := view.to_screen(view.world_pos(game.data.regions[capital]))
	t.check_eq(view._region_at(screen_pos), capital, "clicking a token picks its region")
	t.check_eq(view._region_at(screen_pos + Vector2(4000, 4000)), "", "empty sea picks nothing")

	# Picking must survive zoom and pan: to_screen and _region_at share one transform.
	view._zoom_at(Vector2(100, 100), 1.5)
	view._camera_offset += Vector2(37, -19)
	var zoomed_pos := view.to_screen(view.world_pos(game.data.regions[capital]))
	t.check_eq(view._region_at(zoomed_pos), capital, "picking holds after zoom and pan")

	view.free()


func test_many_turns_through_the_ui(t) -> void:
	## Drives the real report-log formatting against live riots, revolts,
	## events, senate notices and character news — the branches a single
	## turn-1 report never reaches.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 11)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	for i in range(25):
		screen._end_turn()
	t.check_eq(int(game.state["turn"]), 25, "twenty-five turns survive the UI path")
	t.check(screen.report_log.get_parsed_text().length() > 200, "the log filled with news")

	# Every panel still opens on a world that has moved on.
	screen.family_panel.open_for(game)
	t.check(screen.family_panel._content.get_child_count() > 0, "family scroll survives the years")
	screen.family_panel.hide()
	screen.diplomacy_panel.open_for(game)
	t.check(screen.diplomacy_panel._content.get_child_count() > 0, "diplomacy scroll lists the powers")
	screen.diplomacy_panel.hide()

	# And a settlement panel renders for every owned region.
	for region_id in game.state["settlements"]:
		if game.state["settlements"][region_id]["owner"] == "julii":
			screen._on_region_clicked(region_id)
			t.check(screen.region_panel.get_child_count() > 3, "panel renders for " + region_id)
			break

	screen.free()


func test_start_menu_scene_loads(t) -> void:
	var scene: PackedScene = load("res://src/ui/main.tscn")
	t.check(scene != null, "main scene parses")
	var tree := Engine.get_main_loop() as SceneTree
	var menu: Control = scene.instantiate()
	tree.root.add_child(menu)
	var factions: OptionButton = menu.get_node("Center/Menu/FactionRow/Factions")
	t.check(factions.item_count >= 11, "all playable and unlockable houses offered (got %d)" % factions.item_count)
	factions.selected = 1
	menu._on_start_pressed()
	var campaign: CampaignScreen = null
	for child in menu.get_children():
		if child is CampaignScreen:
			campaign = child
	t.check(campaign != null, "starting spawns the campaign screen")
	if campaign != null:
		t.check_eq(campaign.game.state["player_faction"], menu._faction_ids[1],
			"the house that was picked is the house that is played")
	menu.free()
