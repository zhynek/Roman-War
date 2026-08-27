extends RefCounted
## The interaction layer: selecting an army lights its reachable range and
## previews routes on hover; a click beyond one step becomes a standing
## march order and never a war; fleets select and sail from the open sea.


func _first_army_of(game: Game, faction_id: String) -> String:
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		if game.state["armies"][army_id]["owner"] == faction_id:
			return army_id
	return ""


func test_army_selection_lights_range_and_hover_previews(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 7)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	var army_id := _first_army_of(game, "julii")
	t.check(army_id != "", "julii fields an army")
	screen._on_region_clicked(game.state["armies"][army_id]["region"])
	screen._on_army_selected(army_id)
	t.check_eq(screen.map_view.preview_army, army_id, "the map previews for the selected army")
	t.check(not screen.map_view.highlight_regions.is_empty(), "reachable range lights up")

	var in_range: Array = screen.map_view.highlight_regions.keys()
	in_range.sort()
	screen.map_view.hover_at(String(in_range[0]))
	t.check(screen.map_view.path_preview_points().size() >= 2, "hovering an in-range region draws the route")
	t.check(screen.map_view.tooltip != null and screen.map_view.tooltip.visible, "the tooltip shows")

	screen.map_view.hover_at("")
	t.check(not screen.map_view.tooltip.visible, "leaving the map hides the tooltip")

	screen._on_army_selected(army_id)
	t.check(screen.map_view.highlight_regions.is_empty(), "deselecting clears the range")
	screen.free()


func test_far_click_orders_a_march_never_a_war(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 7)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	var army_id := _first_army_of(game, "julii")
	screen._on_region_clicked(game.state["armies"][army_id]["region"])
	screen._on_army_selected(army_id)

	# Somewhere at least two legs away that the army may freely enter.
	var target := ""
	var region_ids: Array = game.data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		var route := game.army_path_preview(army_id, region_id)
		if route.get("reachable", false) and not route.get("blocked_destination", false) \
				and (route["path"] as Array).size() >= 2:
			target = region_id
			break
	t.check(target != "", "the map offers a multi-hop destination")
	if target == "":
		screen.free()
		return

	var stances_before: Dictionary = game.state["factions"]["julii"]["diplomacy"].duplicate()
	var from_region: String = game.state["armies"][army_id]["region"]
	screen._on_region_clicked(target)

	var army: Dictionary = game.state["armies"][army_id]
	t.check(army["region"] != from_region or army.has("march_path"),
		"the far click became movement or a standing order")
	for other_faction in stances_before:
		if stances_before[other_faction] != "war":
			t.check(game.state["factions"]["julii"]["diplomacy"][other_faction] != "war",
				"marching multi-hop declared no war on " + String(other_faction))

	if army.has("march_path"):
		var found_halt := false
		for child in screen.region_panel.get_children():
			if child is Button and (child as Button).text.begins_with("Halt"):
				found_halt = true
		t.check(found_halt, "the region panel offers to halt the march")
	screen.free()


func test_fleet_selects_and_sails_from_open_water(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 7)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	var fleet_id := ""
	var fleet_ids: Array = game.state["fleets"].keys()
	fleet_ids.sort()
	for candidate in fleet_ids:
		if game.state["fleets"][candidate]["owner"] == "cornelii":
			fleet_id = candidate
			break
	t.check(fleet_id != "", "cornelii puts to sea at the start")
	if fleet_id == "":
		screen.free()
		return
	game.state["fleets"][fleet_id]["movement_left"] = 2.0

	var zone := String(game.state["fleets"][fleet_id]["sea_zone"])
	screen._on_sea_zone_clicked(zone)
	t.check_eq(screen.selected_fleet, fleet_id, "clicking its zone selects the fleet")
	t.check(not screen.map_view.highlight_zones.is_empty(), "its reachable zones ring up")

	var adjacent: Array = game.data.sea_zones[zone].get("adjacent", [])
	t.check(not adjacent.is_empty(), "the home zone has neighbours")
	if not adjacent.is_empty():
		screen._on_sea_zone_clicked(String(adjacent[0]))
		t.check_eq(String(game.state["fleets"][fleet_id]["sea_zone"]), String(adjacent[0]),
			"the fleet sails without ever opening the diplomacy scroll")

	screen._on_sea_zone_clicked(String(game.state["fleets"][fleet_id]["sea_zone"]))
	t.check_eq(screen.selected_fleet, "", "clicking the fleet's zone again deselects it")
	screen.free()
