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

	# The knowledge scroll opens with the Roman endowment already practiced.
	screen.knowledge_panel.open_for(game)
	t.check(screen.knowledge_panel._content.get_child_count() > 0, "knowledge scroll populated")
	screen.knowledge_panel.hide()

	# The book of policies opens with the authored edicts on offer.
	screen.edicts_panel.open_for(game)
	t.check(screen.edicts_panel._content.get_child_count() > 0, "book of policies populated")
	screen.edicts_panel.hide()

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


func test_negotiation_and_envoys(t) -> void:
	## The diplomacy scroll's new machinery, driven headless: attitude rows,
	## the negotiation dialog's live appraisal and proposal path, a pending
	## envoy answered, and the world-news log formatting.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	screen.diplomacy_panel.open_for(game)
	t.check(screen.diplomacy_panel._content.get_child_count() > 0, "the powers are listed")

	# The negotiation dialog previews and proposes a trade offer.
	var negotiation: NegotiationDialog = screen.diplomacy_panel.negotiation
	negotiation.open_for(game, "carthage")
	t.check(negotiation._hint.get_parsed_text().length() > 0, "the live appraisal renders")
	var trade_index := negotiation._stance_values.find("trade")
	t.check(trade_index >= 0, "trade is on the table with a neutral power")
	negotiation._stance.selected = trade_index
	var offer := negotiation.build_offer()
	t.check_eq(offer["to"], "carthage", "the offer addresses the right court")
	t.check_eq(offer["stance"], "trade", "with the chosen stance")
	negotiation._propose()
	t.check(negotiation._hint.get_parsed_text().length() > 0, "the verdict is shown either way")
	# A second click must never re-apply an agreement (the accepted form
	# rebuilds empty; a refused one just gets refused again).
	var state_after_first := JSON.stringify(JSON.parse_string(JSON.stringify(game.state)))
	negotiation._propose()
	t.check_eq(JSON.stringify(JSON.parse_string(JSON.stringify(game.state))), state_after_first,
		"proposing twice changes nothing the first click did not")
	negotiation.hide()

	# A pending envoy renders and can be answered.
	game.state["pending_offers"].append({"id": "offer_test", "from": "carthage", "to": "julii",
		"stance": "trade", "give_payment": 0, "give_tribute": null, "give_regions": [],
		"ask_payment": 0, "ask_tribute": null, "ask_regions": [], "expires_turn": 999})
	screen.diplomacy_panel._rebuild()
	t.check(screen.diplomacy_panel._content.get_child_count() > 0, "the envoy section renders")
	t.check(game.respond_offer("offer_test", true), "the envoy is answered")
	t.check_eq(DiplomacyRules.stance_between(game.state, "julii", "carthage"), "trade",
		"and the agreement stands")
	screen.diplomacy_panel.hide()

	# World news formatting covers every event kind without touching state.
	var log_before: int = screen.report_log.get_parsed_text().length()
	screen._log_world_news({
		"ai": [
			{"kind": "war_declared", "by": "gaul", "on": "julii"},
			{"kind": "war_declared", "by": "gaul", "on": "germania"},
			{"kind": "ai_conquest", "faction": "gaul", "region": "latium", "occupation": "occupy", "from": "rebels"},
			{"kind": "peace_made", "between": ["gaul", "germania"]},
			{"kind": "trade_agreed", "between": ["carthage", "egypt"]},
			{"kind": "offer_sent", "from": "carthage", "to": "julii"},
			{"kind": "ai_attack", "faction": "gaul", "defender": "julii", "region": "latium", "winner": "attacker"},
			{"kind": "ai_siege", "faction": "gaul", "region": "latium", "owner": "julii"},
		],
		"diplomacy": [
			{"kind": "tribute_paid", "from": "julii", "to": "gaul", "amount": 100},
			{"kind": "tribute_paid", "from": "gaul", "to": "julii", "amount": 100},
			{"kind": "offer_expired", "from": "carthage"},
		],
	})
	t.check(screen.report_log.get_parsed_text().length() > log_before, "world news reached the log")

	screen.free()


func test_agent_orders_through_the_ui(t) -> void:
	## Recruit an agent, select him in the panel, walk him across a border by
	## clicking the map, and read a spy's report — the whole loop headless.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	# Find any julii settlement able to train any agent kind at campaign start
	# (spies want a market, which a young province may not have built yet).
	var home := ""
	var kind := ""
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	var kind_ids: Array = game.data.agent_kinds.keys()
	kind_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = game.state["settlements"][region_id]
		if settlement["owner"] != "julii":
			continue
		for candidate in kind_ids:
			if candidate != "spy" and home != "":
				continue  # prefer a spy so the report path gets exercised
			if AgentRules.building_gate_met(game.data, settlement, game.data.agent_kinds[candidate]):
				home = region_id
				kind = candidate
				if kind == "spy":
					break
		if kind == "spy":
			break
	t.check(home != "", "some julii town can train an agent at the start")

	var agent_id := game.recruit_agent(home, kind)
	t.check(agent_id != "", "the agent is hired through the facade")

	screen._on_region_clicked(home)
	var rows_before: int = screen.region_panel.get_child_count()
	screen._on_agent_selected(agent_id)
	t.check_eq(screen.selected_agent, agent_id, "the agent is selected")
	t.check(screen.region_panel.get_child_count() > rows_before, "his orders unfold in the panel")

	AgentRules.reset_movement(game.data, game.state)
	var neighbors: Array = game.data.regions[home].get("adjacent", []).duplicate()
	neighbors.sort()
	var destination: String = neighbors[0]
	screen._on_region_clicked(destination)
	t.check_eq(game.state["agents"][agent_id]["region"], destination,
		"a map click walks the agent across any border")
	t.check_eq(screen.selected_agent, agent_id, "and he stays selected for the next step")

	if kind == "spy":
		screen._scout_order(agent_id)
		t.check(screen.report_log.get_parsed_text().contains("informer reports"),
			"the spy's report reaches the log")

	# Selecting an army drops the agent selection, and vice versa.
	var army_id := ""
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for candidate in army_ids:
		if game.state["armies"][candidate]["owner"] == "julii":
			army_id = candidate
			break
	if army_id != "":
		screen._on_region_clicked(game.state["armies"][army_id]["region"])
		screen._on_army_selected(army_id)
		t.check_eq(screen.selected_agent, "", "army selection clears the agent")

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
