extends RefCounted
## Banners on the map: laid out for every visible army and fleet, picked
## before the tokens they stand beside, selected by a left click and ordered
## by a right click; the force card and the province panel's regrouping
## rows. Headless: no rendering, only the layout, picking and input paths.


func _julii_army(game: Game) -> String:
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		if game.state["armies"][army_id]["owner"] == "julii":
			return army_id
	return ""


func _entry_for(view: MapView, force_id: String) -> Dictionary:
	for entry in view.banner_layout():
		if entry["id"] == force_id:
			return entry
	return {}


func _mouse(button: int, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	return event


func _motion(to: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.relative = relative
	return event


func _button(root: Control, prefix: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node is Button and not (node is CheckBox) and not (node is OptionButton) \
				and (node as Button).text.begins_with(prefix):
			return node
	return null


func test_banners_are_laid_out_and_picked_before_tokens(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var view := MapView.new()
	view.game = game
	view.size = Vector2(800, 600)
	tree.root.add_child(view)

	var army_id := _julii_army(game)
	var region: String = game.state["armies"][army_id]["region"]
	view.center_on(region)

	var entry := _entry_for(view, army_id)
	t.check(not entry.is_empty(), "our army has a banner")
	t.check_eq(entry["kind"], "army", "banner kind")
	t.check_eq(int(entry["summary"]["units"]), game.state["armies"][army_id]["units"].size(), "banner carries the summary")
	var centre: Vector2 = (entry["rect"] as Rect2).get_center()
	t.check_eq(view._pick(centre)["id"], army_id, "the banner is picked where it is drawn")
	t.check_eq(view._pick(view.to_screen(view.world_pos(game.data.regions[region])))["kind"], "region",
		"the token centre still picks the region")
	view._update_hover(centre)
	t.check_eq(view.hover_force, army_id, "hovering a banner notices it")
	t.check(view._tooltip_text().contains("units"), "and the tooltip explains it")

	# Every laid-out army banner is in a region we can see; none in the fog.
	var visible := game.visible_regions()
	for other in view.banner_layout():
		if other["kind"] == "army":
			t.check(visible.has(game.state["armies"][other["id"]]["region"]), "no banner leaks through the fog")

	# Picking must survive zoom and pan.
	view._zoom_at(Vector2(100, 100), 1.4)
	view._camera_offset += Vector2(23, -41)
	var moved := _entry_for(view, army_id)
	t.check(not moved.is_empty() and view._pick((moved["rect"] as Rect2).get_center())["id"] == army_id,
		"picking holds after zoom and pan")

	# Zoomed far out, banners give way to badges and picking falls through to tokens.
	view._zoom_at(Vector2(100, 100), 0.3)
	t.check(view.banner_layout().is_empty(), "compact mode below the banner zoom")
	view.free()


func test_left_click_selects_and_right_click_orders(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	screen.playback_enabled = false
	var view := screen.map_view
	view.size = Vector2(800, 600)

	var army_id := _julii_army(game)
	var from_region: String = game.state["armies"][army_id]["region"]
	view.center_on(from_region)
	var banner: Vector2 = (_entry_for(view, army_id)["rect"] as Rect2).get_center()

	view._gui_input(_mouse(MOUSE_BUTTON_LEFT, true, banner))
	view._gui_input(_mouse(MOUSE_BUTTON_LEFT, false, banner))
	t.check_eq(screen.selected_army, army_id, "a left click on the banner selects the army")
	t.check_eq(view.selected_force, army_id, "the map outlines the selection")
	t.check(not view.highlight_regions.is_empty(), "reachable neighbours are ringed")
	t.check(screen.force_panel.visible, "the force card opens")

	var target := ""
	for neighbor in game.data.regions[from_region].get("adjacent", []):
		if view.highlight_regions.get(neighbor, "") == "march":
			target = neighbor
			break
	t.check(target != "", "a neighbour is reachable this season")
	var token: Vector2 = view.to_screen(view.world_pos(game.data.regions[target]))

	# A right press on a ringed province is the order.
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, true, token))
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, false, token))
	t.check_eq(game.state["armies"][army_id]["region"], target, "a right click marches the army")
	t.check_eq(screen.selected_army, army_id, "the selection follows the army")
	t.check_eq(view.selected_region, target, "and so does the selected province")

	# End turn: the selection survives and the rings come back with the movement.
	screen._end_turn()
	t.check_eq(screen.selected_army, army_id, "selection persists across the turn")
	t.check(not view.highlight_regions.is_empty(), "rings recomputed after the reset")

	# Esc clears the force, a second Esc the province.
	screen.deselect()
	t.check_eq(screen.selected_army, "", "Esc clears the force")
	t.check(not screen.force_panel.visible, "and the card hides")
	t.check_eq(view.selected_region, target, "the province stays selected")
	screen.deselect()
	t.check_eq(view.selected_region, "", "a second Esc clears the province")

	# Tab finds a force with orders to give.
	screen.cycle_selection()
	t.check(screen.selected_force() != "", "Tab selects a force awaiting orders")
	screen.free()


func test_multi_step_order_from_the_map(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	# This exercises marching over an already acquired atlas.
	for region in game.data.regions:
		game.state["cartography"]["julii"][region] = 0
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var army_id := _julii_army(game)
	var home: String = game.state["armies"][army_id]["region"]
	screen.select_force("army", army_id)

	# Pick a ringed region that is NOT adjacent: a real multi-step march.
	var far := ""
	for region_id in screen.map_view.highlight_regions:
		if screen.map_view.highlight_regions[region_id] == "march" \
				and not MapRules.are_adjacent(game.data, home, region_id):
			far = region_id
			break
	t.check(far != "", "somewhere two steps away is within reach (rings show it)")
	if far != "":
		screen._on_order_target("region", far, false)
		t.check(game.state["armies"][army_id]["region"] != home, "the army set out at once")
		t.check(game.state["armies"][army_id]["region"] == far or game.state["armies"][army_id].has("march_path"),
			"and arrived, or the rest of the road is queued")
		t.check(screen.report_log.get_parsed_text().contains("marches"), "the log says so")
	screen.free()


func test_force_panel_shows_the_roster_and_marches(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	t.check(not screen.force_panel.visible, "no force selected, no force card")

	var army_id := _julii_army(game)
	var army: Dictionary = game.state["armies"][army_id]
	screen.select_force("army", army_id)
	t.check(screen.force_panel.visible, "selecting shows the force card")
	var text := ""
	for node in screen.force_panel.find_children("*", "Label", true, false):
		text += (node as Label).text + "\n"
	for unit in army["units"]:
		t.check(text.contains(game.data.units[unit["template"]]["name"]), "roster lists " + unit["template"])
	t.check(text.contains("Units %d/%d" % [army["units"].size(), ForceRules.max_units(game.data)]), "stats line counts the units")
	t.check(text.contains("Upkeep"), "stats line shows upkeep")
	if army["general"] != null:
		t.check(text.contains(game.state["characters"][army["general"]]["name"]), "the general is named")

	# The March-to list is the trackpad route: pick its first entry and go.
	var options: OptionButton = null
	var go: Button = null
	for node in screen.force_panel.find_children("*", "OptionButton", true, false):
		options = node
	for node in screen.force_panel.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with("March"):
			go = node
	t.check(options != null and go != null and options.item_count > 0, "March to offers reachable regions")
	if options != null and go != null and options.item_count > 0:
		options.selected = 0
		var home: String = army["region"]
		go.pressed.emit()
		t.check(game.state["armies"][army_id]["region"] != home, "Go marches the army")
		t.check_eq(screen.selected_army, army_id, "the card follows the army")

	# Garrisoning from the card dissolves the army and clears the card.
	if game.state["settlements"].get(game.state["armies"][army_id]["region"], {}).get("owner", "") == "julii":
		var garrison := _button(screen.force_panel, "Garrison")
		t.check(garrison != null, "the card offers to garrison in an own city")
		if garrison != null:
			garrison.pressed.emit()
		t.check(not game.state["armies"].has(army_id), "the army joined the garrison")
		t.check_eq(screen.selected_army, "", "and the selection is dropped")
		t.check(not screen.force_panel.visible, "the card hides with nothing selected")
	screen.free()


func test_regrouping_from_the_panels(t) -> void:
	## Raise a detachment from a garrison, merge it into the field army, split
	## it off again, transfer it back and disband it — all through the panels.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var army_id := _julii_army(game)
	var home: String = game.state["armies"][army_id]["region"]
	# March the field army into a Julii city with a garrison, if it is not in one.
	var city := home
	if game.state["settlements"].get(home, {}).get("owner", "") != "julii":
		for region_id in game.reachable_regions(army_id)["reach"]:
			if game.state["settlements"].get(region_id, {}).get("owner", "") == "julii":
				city = region_id
				break
		game.march_army(army_id, city)
	t.check_eq(game.state["armies"][army_id]["region"], city, "the field army stands in an own city")
	var garrison: Array = game.state["settlements"][city]["garrison"]
	t.check(garrison.size() >= 1, "the city has a garrison to draw on")
	var garrison_before := garrison.size()

	# Raise: tick the first garrison unit, raise it under a captain.
	screen._on_region_clicked(city)
	screen.region_panel.set_garrison_checked([0])
	var raise := _button(screen.region_panel, "Raise army")
	t.check(raise != null, "the garrison offers Raise army")
	raise.pressed.emit()
	var raised := screen.selected_army
	t.check(raised != "" and raised != army_id and game.state["armies"].has(raised), "a new army is raised and selected")
	t.check_eq(game.state["settlements"][city]["garrison"].size(), garrison_before - 1, "the garrison shrank by one")
	t.check(screen.force_panel.visible, "the force card shows the new army")

	# Merge it into the field army: the selection moves to the survivor.
	var merge := _button(screen.force_panel, "Merge into")
	t.check(merge != null, "Merge into is offered")
	var units_before: int = game.state["armies"][army_id]["units"].size()
	merge.pressed.emit()
	t.check(not game.state["armies"].has(raised), "the raised army merged away")
	t.check_eq(game.state["armies"][army_id]["units"].size(), units_before + 1, "the field army grew")
	t.check_eq(screen.selected_army, army_id, "the selection follows the merged army")

	# Split the last unit off again under a captain.
	screen.force_panel.set_checked([units_before])
	var split := _button(screen.force_panel, "Split ticked")
	t.check(split != null, "Split is offered")
	split.pressed.emit()
	var detachment := screen.selected_army
	t.check(detachment != army_id and game.state["armies"].has(detachment), "a detachment exists and is selected")
	t.check_eq(game.state["armies"][detachment]["units"].size(), 1, "with the one ticked unit")

	# A refused order explains itself in the log instead of doing nothing.
	var log_before: int = screen.report_log.get_parsed_text().length()
	screen.force_panel.set_checked([])
	var split_again := _button(screen.force_panel, "Split ticked")
	split_again.pressed.emit()
	t.check(screen.report_log.get_parsed_text().length() > log_before, "a refusal is logged")

	# Transfer the detachment's unit into the garrison: the empty army dissolves.
	screen.force_panel.set_checked([0])
	var transfer := _button(screen.force_panel, "Transfer ticked")
	t.check(transfer != null, "Transfer is offered in an own city")
	transfer.pressed.emit()
	t.check(not game.state["armies"].has(detachment), "the emptied detachment is gone")
	t.check_eq(game.state["settlements"][city]["garrison"].size(), garrison_before, "the garrison is whole again")
	t.check_eq(screen.selected_army, "", "nothing is selected once the detachment is gone")
	t.check_eq(screen.map_view.selected_region, city, "the city stays selected")

	# Disband a garrison unit through the confirmed path.
	var population_before: int = game.state["settlements"][city]["population"]
	screen._resolve_disband("garrison:" + city, [0])
	t.check_eq(game.state["settlements"][city]["garrison"].size(), garrison_before - 1, "one unit sent home")
	t.check(int(game.state["settlements"][city]["population"]) > population_before, "the men rejoin the population")
	screen.free()


func test_harbour_launch_and_dock_from_the_panels(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var port := ""
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if game.state["settlements"][region_id]["owner"] == "julii" and MapRules.coastal(game.data, region_id):
			port = region_id
			break
	t.check(port != "", "the Julii hold a port")
	var harbour: Array = NavalRules.harbour_of(game.state, port)
	for i in range(2):
		harbour.append({"template": "coastal_galley", "experience": 0, "strength_pct": 100})

	screen._on_region_clicked(port)
	screen.region_panel.set_harbour_checked([0, 1])
	var launch := _button(screen.region_panel, "Launch fleet")
	t.check(launch != null, "the harbour offers Launch fleet")
	launch.pressed.emit()
	var fleet_id := screen.selected_fleet
	t.check(fleet_id != "" and game.state["fleets"].has(fleet_id), "a fleet is launched and selected")
	t.check_eq(game.state["fleets"][fleet_id]["ships"].size(), 2, "with both ships")
	t.check_eq(harbour.size(), 0, "the harbour is empty")
	t.check(screen.force_panel.visible, "the fleet card is shown")
	t.check_eq(screen.map_view.selected_sea_zone, game.state["fleets"][fleet_id]["sea_zone"], "the map rings the fleet's sea")

	# Split one ship off, then merge it back, then dock.
	screen.force_panel.set_checked([1])
	var split := _button(screen.force_panel, "Split ticked ships")
	t.check(split != null, "Split is offered")
	split.pressed.emit()
	var detached := screen.selected_fleet
	t.check(detached != fleet_id and game.state["fleets"].has(detached), "a one-ship fleet is selected")
	var merge := _button(screen.force_panel, "Merge into")
	t.check(merge != null, "Merge into is offered")
	merge.pressed.emit()
	t.check(not game.state["fleets"].has(detached) and screen.selected_fleet == fleet_id, "merged back, selection on the survivor")
	var dock := _button(screen.force_panel, "Dock at")
	t.check(dock != null, "Dock at is offered")
	dock.pressed.emit()
	t.check(game.state["fleets"].has(fleet_id), "a fleet launched this season has no lane left to make port")
	game.state["fleets"][fleet_id]["movement_left"] = 2.0   # next season, in effect
	screen.refresh()
	# The right button docks too: a port of ours on this sea.
	screen._on_order_target("region", port, false)
	t.check(not game.state["fleets"].has(fleet_id), "the fleet docked")
	t.check_eq(harbour.size(), 2, "both ships are back in the harbour")
	t.check_eq(screen.selected_fleet, "", "nothing selected after docking")
	t.check_eq(screen.map_view.selected_region, port, "the port is selected instead")
	screen.free()


func test_fleet_banners_follow_sea_visibility(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var view := screen.map_view
	view.size = Vector2(800, 600)

	# Give the Julii a fleet in a sea their coast touches.
	var zone := ""
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if game.state["settlements"][region_id]["owner"] == "julii" and MapRules.coastal(game.data, region_id):
			zone = game.data.regions[region_id]["sea_zones"][0]
			break
	t.check(zone != "", "the Julii hold a coast")
	var fleet_id := "fleet_%d" % int(game.state["next_id"])
	game.state["next_id"] = int(game.state["next_id"]) + 1
	game.state["fleets"][fleet_id] = {"owner": "julii", "sea_zone": zone,
		"ships": [{"template": "coastal_galley", "experience": 0, "strength_pct": 100}], "movement_left": 2.0}
	screen.refresh()

	t.check(game.visible_sea_zones().has(zone), "our own fleet's sea is visible")
	view.center_on_zone(zone)
	var entry := _entry_for(view, fleet_id)
	t.check(not entry.is_empty() and entry["kind"] == "fleet", "the fleet has a banner at its anchor")
	if not entry.is_empty():
		t.check_eq(view._pick((entry["rect"] as Rect2).get_center())["id"], fleet_id, "the fleet banner is pickable")

	# Fleets in seas we have no eyes on are not drawn.
	var far := ""
	var visible_zones := game.visible_sea_zones()
	var zone_ids: Array = game.data.sea_zones.keys()
	zone_ids.sort()
	for zone_id in zone_ids:
		if not visible_zones.has(zone_id):
			far = zone_id
			break
	if far != "":
		game.state["fleets"]["fleet_far"] = {"owner": "carthage", "sea_zone": far,
			"ships": [{"template": "coastal_galley", "experience": 0, "strength_pct": 100}], "movement_left": 2.0}
		screen.refresh()
		t.check(_entry_for(view, "fleet_far").is_empty(), "no banner for a fleet beyond our sight")

	# Select it and sail it with a right click on a neighbouring sea anchor.
	screen.select_force("fleet", fleet_id)
	t.check_eq(screen.selected_fleet, fleet_id, "fleet selected")
	t.check(not view.highlight_zones.is_empty(), "neighbouring seas are ringed")
	var lanes: Array = view.highlight_zones.keys()
	lanes.sort()
	var next_zone: String = lanes[0]
	screen._on_order_target("zone", next_zone, false)
	t.check_eq(game.state["fleets"][fleet_id]["sea_zone"], next_zone, "the fleet sailed")
	t.check(screen.force_panel.visible and screen.force_panel.get_child_count() > 0, "the force card describes the fleet")

	# A foreign fleet's banner is looked at, never commanded.
	var foreign := ""
	var fleet_ids: Array = game.state["fleets"].keys()
	fleet_ids.sort()
	for candidate in fleet_ids:
		if game.state["fleets"][candidate]["owner"] != "julii" and visible_zones.has(game.state["fleets"][candidate]["sea_zone"]):
			foreign = candidate
			break
	if foreign != "":
		screen._on_force_clicked("fleet", foreign)
		t.check_eq(screen.selected_fleet, "", "a foreign banner selects nothing")
	screen.free()


func test_the_province_follows_a_marching_army_across_the_turn(t) -> void:
	## A queued march advances during End Turn without any order of ours: the
	## selected province, its panel and the camera must follow the column.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	# This exercises marching over an already acquired atlas.
	for region in game.data.regions:
		game.state["cartography"]["julii"][region] = 0
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	screen.playback_enabled = false
	var army_id := _julii_army(game)
	var home: String = game.state["armies"][army_id]["region"]
	screen.select_force("army", army_id)
	# Spend part of the first day so a reachable Italian route spans seasons.
	game.state["armies"][army_id]["movement_left"] = 1.5
	# Somewhere beyond this season's reach: pick the farthest land preview.
	var far := ""
	var far_turns := 1
	var region_ids: Array = game.data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		var preview := game.army_path_preview(army_id, region_id)
		if preview.is_empty() or (preview["path"] as Array).is_empty() or preview["blocked_destination"]:
			continue
		if int(preview["turns"]) > far_turns:
			far = region_id
			far_turns = int(preview["turns"])
	t.check(far != "", "a multi-turn destination exists")
	if far == "":
		screen.free()
		return
	screen._on_order_target("region", far, false)
	t.check(screen._planning_order, "a distant destination asks for a journey order")
	screen.command_bar.issue.pressed.emit()
	var after_order: String = game.state["armies"][army_id]["region"]
	t.check(after_order != home and game.state["armies"][army_id].has("march_path"), "the army set out with the road queued")
	screen._end_turn()
	if not game.state["armies"].has(army_id):
		screen.free()
		return
	var now: String = game.state["armies"][army_id]["region"]
	t.check_eq(screen.selected_army, army_id, "the army stays selected")
	t.check_eq(screen.map_view.selected_region, now, "and the selected province followed it")
	t.check_eq(screen.region_panel.region_id, now, "so does the province panel")
	screen.free()


func test_a_red_ring_on_the_armys_own_province_strikes(t) -> void:
	## An enemy standing in the same province as our army (a beaten survivor)
	## is ringed red there; the right-click on that province attacks him
	## rather than opening the dossier.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	screen.playback_enabled = false
	var army_id := _julii_army(game)
	var here: String = game.state["armies"][army_id]["region"]
	# A rebel band appears where our army stands (rebels are always at war).
	var band := "army_%d" % int(game.state["next_id"])
	game.state["next_id"] = int(game.state["next_id"]) + 1
	game.state["armies"][band] = {"owner": "rebels", "region": here, "general": null,
		"units": [{"template": "rebel_mob", "experience": 0, "strength_pct": 100, "weapon": 0, "armor": 0}],
		"movement_left": 0.0, "forced_march": false}
	if not game.data.units.has("rebel_mob"):
		var any_id: String = game.data.units.keys()[0]
		game.state["armies"][band]["units"][0]["template"] = any_id
	screen.select_force("army", army_id)
	t.check_eq(String(screen.map_view.highlight_regions.get(here, "")), "attack", "the army's own province rings red")
	var dialogs_before := 0
	for child in screen.get_children():
		if child is ConfirmationDialog:
			dialogs_before += 1
	screen._on_order_target("region", here, false)
	var dialogs := 0
	for child in screen.get_children():
		if child is ConfirmationDialog:
			dialogs += 1
	t.check_eq(dialogs, dialogs_before + 1, "the right-click asks to attack, it does not open the dossier")
	screen.free()


func test_a_foreign_banner_never_walks_an_agent(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var home := ""
	var kind := ""
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = game.state["settlements"][region_id]
		if settlement["owner"] != "julii":
			continue
		for candidate in ["diplomat", "spy", "assassin"]:
			if game.data.agent_kinds.has(candidate) and AgentRules.building_gate_met(game.data, settlement, game.data.agent_kinds[candidate]):
				home = region_id
				kind = candidate
				break
		if home != "":
			break
	t.check(home != "", "some julii town can train an agent")
	if home == "":
		screen.free()
		return
	var agent_id := game.recruit_agent(home, kind)
	screen._on_region_clicked(home)
	screen._on_agent_selected(agent_id)
	t.check_eq(screen.selected_agent, agent_id, "the agent is selected")
	# A visible foreign army somewhere else.
	var foreign := ""
	var visible := game.visible_regions()
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for candidate in army_ids:
		var army: Dictionary = game.state["armies"][candidate]
		if army["owner"] != "julii" and visible.has(army["region"]) and army["region"] != home:
			foreign = candidate
			break
	if foreign != "":
		screen._on_force_clicked("army", foreign)
		t.check_eq(game.state["agents"][agent_id]["region"], home, "looking at a foreign banner moves nobody")
		t.check_eq(screen.selected_agent, "", "and stands the agent down")
	screen.free()
