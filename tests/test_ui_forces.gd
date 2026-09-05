extends RefCounted
## Banners on the map: laid out for every visible army and fleet, picked
## before the tokens they stand beside, selected by a left click and ordered
## by a right click that did not drag. Headless: no rendering, only the
## layout, picking and input paths.


func _julii_army(game: Game) -> String:
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		if game.state["armies"][army_id]["owner"] == "julii":
			return army_id
	return ""


func _entry_for(view: MapView, force_id: String) -> Dictionary:
	for entry in view._layout_banners():
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
	t.check_eq(entry["summary"]["units"], game.state["armies"][army_id]["units"].size(), "banner carries the summary")
	var centre: Vector2 = (entry["rect"] as Rect2).get_center()
	t.check_eq(view._pick(centre)["id"], army_id, "the banner is picked where it is drawn")
	t.check_eq(view._pick(view.to_screen(view.world_pos(game.data.regions[region])))["kind"], "region",
		"the token centre still picks the region")
	t.check(view._get_tooltip(centre).contains("units"), "hovering a banner explains it")

	# Every laid-out army banner is in a region we can see; none in the fog.
	var visible := game.visible_regions()
	for other in view._layout_banners():
		if other["kind"] == "army":
			t.check(visible.has(game.state["armies"][other["id"]]["region"]), "no banner leaks through the fog")

	# Picking must survive zoom and pan.
	view._zoom_at(Vector2(100, 100), 1.4)
	view._camera_offset += Vector2(23, -41)
	var moved := _entry_for(view, army_id)
	t.check_eq(view._pick((moved["rect"] as Rect2).get_center())["id"], army_id, "picking holds after zoom and pan")

	# Zoomed far out, banners give way to badges and picking falls through to tokens.
	view._zoom_at(Vector2(100, 100), 0.3)
	t.check(view._layout_banners().is_empty(), "compact mode below the banner zoom")
	view.free()


func test_left_click_selects_and_right_click_orders(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var view := screen.map_view
	view.size = Vector2(800, 600)

	var army_id := _julii_army(game)
	var from_region: String = game.state["armies"][army_id]["region"]
	view.center_on(from_region)
	var banner: Vector2 = (_entry_for(view, army_id)["rect"] as Rect2).get_center()

	view._gui_input(_mouse(MOUSE_BUTTON_LEFT, true, banner))
	t.check_eq(screen.selected_army, army_id, "a left click on the banner selects the army")
	t.check_eq(view.selected_force, army_id, "the map outlines the selection")
	t.check(not view.highlight_regions.is_empty(), "reachable neighbours are ringed")

	var target := ""
	for neighbor in game.data.regions[from_region].get("adjacent", []):
		if view.highlight_regions.get(neighbor, "") == "march":
			target = neighbor
			break
	t.check(target != "", "a neighbour is reachable this season")
	var token: Vector2 = view.to_screen(view.world_pos(game.data.regions[target]))

	# A right-DRAG pans and never orders.
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, true, token))
	view._gui_input(_motion(token + Vector2(30, 0), Vector2(30, 0)))
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, false, token + Vector2(30, 0)))
	t.check_eq(game.state["armies"][army_id]["region"], from_region, "a right drag pans, it does not march")

	# A right-CLICK (no drag) is the order. The map has panned by 30 px, so ask
	# for the token's position again.
	token = view.to_screen(view.world_pos(game.data.regions[target]))
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, true, token))
	view._gui_input(_motion(token + Vector2(1, 1), Vector2(1, 1)))
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, false, token + Vector2(1, 1)))
	t.check_eq(game.state["armies"][army_id]["region"], target, "a right click marches the army")
	t.check_eq(screen.selected_army, army_id, "the selection follows the army")
	t.check_eq(view.selected_region, target, "and so does the selected region")

	# End turn: the selection survives and the rings come back with the movement.
	screen._end_turn()
	t.check_eq(screen.selected_army, army_id, "selection persists across the turn")
	t.check(not view.highlight_regions.is_empty(), "rings recomputed after the reset")

	# Esc clears the force, a second Esc the region.
	screen.deselect()
	t.check_eq(screen.selected_army, "", "Esc clears the force")
	t.check_eq(view.selected_region, target, "the region stays selected")
	screen.deselect()
	t.check_eq(view.selected_region, "", "a second Esc clears the region")

	# Tab finds a force with orders to give.
	screen.cycle_selection()
	t.check(screen.selected_force() != "", "Tab selects a force awaiting orders")
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
	for region_id in game.state["settlements"]:
		if game.state["settlements"][region_id]["owner"] == "julii" and MapRules.coastal(game.data, region_id):
			zone = game.data.regions[region_id]["sea_zones"][0]
			break
	t.check(zone != "", "the Julii hold a coast")
	var fleet_id := "fleet_%d" % int(game.state["next_id"])
	game.state["next_id"] = int(game.state["next_id"]) + 1
	game.state["fleets"][fleet_id] = {"owner": "julii", "sea_zone": zone,
		"ships": [{"template": "coastal_galley", "experience": 0, "strength_pct": 100}], "movement_left": 2.0}

	t.check(game.visible_sea_zones().has(zone), "our own fleet's sea is visible")
	view.center_on_zone(zone)
	var entry := _entry_for(view, fleet_id)
	t.check(not entry.is_empty() and entry["kind"] == "fleet", "the fleet has a banner at its anchor")
	t.check_eq(view._pick((entry["rect"] as Rect2).get_center())["id"], fleet_id, "the fleet banner is pickable")

	# Fleets in seas we have no eyes on are not drawn.
	var far := ""
	var visible_zones := game.visible_sea_zones()
	for zone_id in game.data.sea_zones:
		if not visible_zones.has(zone_id):
			far = zone_id
			break
	if far != "":
		game.state["fleets"]["fleet_far"] = {"owner": "carthage", "sea_zone": far,
			"ships": [{"template": "coastal_galley", "experience": 0, "strength_pct": 100}], "movement_left": 2.0}
		t.check(_entry_for(view, "fleet_far").is_empty(), "no banner for a fleet beyond our sight")

	# Select it and sail it with a right click on a neighbouring sea anchor.
	screen.select_force("fleet", fleet_id)
	t.check_eq(screen.selected_fleet, fleet_id, "fleet selected")
	t.check(not view.highlight_zones.is_empty(), "neighbouring seas are ringed")
	var next_zone: String = view.highlight_zones.keys()[0]
	screen._on_order_target("zone", next_zone, false)
	t.check_eq(game.state["fleets"][fleet_id]["sea_zone"], next_zone, "the fleet sailed")
	t.check(screen.region_panel.get_child_count() > 0, "the panel describes the fleet")
	screen.free()
