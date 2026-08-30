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


func test_screen_fills_its_window(t) -> void:
	## The campaign screen once set anchors without offsets, leaving it at size
	## (0, 0) so every child fell back to its minimum and the game huddled in
	## the top-left corner of the window.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 7)
	var host := Control.new()
	tree.root.add_child(host)
	host.size = Vector2(1440, 900)
	var screen := CampaignScreen.create(game)
	host.add_child(screen)

	t.check_eq(screen.size, host.size, "the screen fills its host, not its minimum size")
	t.check(screen.size.x > 0.0 and screen.size.y > 0.0, "the screen has a real rect")
	host.free()


func test_map_centres_once_it_knows_its_size(t) -> void:
	## center_on before the first layout has no size to centre against, so the
	## request is held until the map is laid out.
	var game := Game.new_campaign("cornelii", 7)
	var view := MapView.new()
	view.game = game
	var before := view._camera_offset
	view.center_on("latium")
	t.check_eq(view._camera_offset, before, "an unsized map does not centre on nothing")
	t.check_eq(view._pending_center, "latium", "the request is remembered")

	view.size = Vector2(900, 600)
	view._on_resized()
	t.check_eq(view._pending_center, "", "the pending request is spent")
	var centre := view.to_screen(view.world_pos(game.data.regions["latium"]))
	t.check_near(centre.x, 450.0, 0.5, "centred horizontally once sized")
	t.check_near(centre.y, 300.0, 0.5, "centred vertically once sized")
	view.free()


func test_map_camera_controls(t) -> void:
	## Every camera route a mouseless player has: buttons, keys, gestures.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 7)
	var view := MapView.new()
	view.game = game
	view.size = Vector2(800, 600)
	tree.root.add_child(view)

	var start_zoom: float = view._zoom
	view.zoom_by(MapView.ZOOM_STEP)
	t.check(view._zoom > start_zoom, "zoom in reaches a closer view")
	view.zoom_by(1.0 / MapView.ZOOM_STEP)
	t.check_near(view._zoom, start_zoom, 0.0001, "zoom out returns to where it began")

	# Zooming about the middle keeps the middle of the map where it was.
	var middle := view.size / 2.0
	var before := view._region_at(middle)
	view.zoom_by(MapView.ZOOM_STEP)
	t.check_eq(view._region_at(middle), before, "the view zooms about its own centre")

	for i in range(40):
		view.zoom_by(MapView.ZOOM_STEP)
	t.check_near(view._zoom, MapView.ZOOM_MAX, 0.0001, "zoom stops at the near limit")
	for i in range(80):
		view.zoom_by(1.0 / MapView.ZOOM_STEP)
	t.check_near(view._zoom, MapView.ZOOM_MIN, 0.0001, "zoom stops at the far limit")

	# Panning right must move the view east: a region's screen x drops.
	view.reset_view()
	var capital: String = game.state["factions"]["julii"]["capital"]
	var anchor := view.to_screen(view.world_pos(game.data.regions[capital]))
	view.pan_by(Vector2(MapView.KEY_PAN_STEP, 0))
	var after_right := view.to_screen(view.world_pos(game.data.regions[capital]))
	t.check_near(anchor.x - after_right.x, MapView.KEY_PAN_STEP, 0.001, "panning right looks east")
	view.pan_by(Vector2(-MapView.KEY_PAN_STEP, MapView.KEY_PAN_STEP))
	var after_down := view.to_screen(view.world_pos(game.data.regions[capital]))
	t.check_near(anchor.y - after_down.y, MapView.KEY_PAN_STEP, 0.001, "panning down looks south")
	t.check_near(after_down.x, anchor.x, 0.001, "and the sideways pan undoes itself")

	# Home returns to the capital at the default zoom, however lost you are.
	view.pan_by(Vector2(4000, -2500))
	view.zoom_by(MapView.ZOOM_STEP)
	view.reset_view()
	t.check_near(view._zoom, 1.0, 0.0001, "Home restores the default zoom")
	t.check_eq(view._region_at(view.size / 2.0), capital, "Home recentres on the capital")

	# The on-map buttons exist, and none of them can steal the arrow keys.
	var buttons: Array = []
	for child in view.get_children():
		if child is VBoxContainer:
			for grandchild in child.get_children():
				if grandchild is Button:
					buttons.append(grandchild)
	t.check_eq(buttons.size(), 3, "zoom in, zoom out and Home sit on the map")
	for button in buttons:
		t.check_eq(button.focus_mode, Control.FOCUS_NONE, "camera buttons never take focus")
	(buttons[0] as Button).pressed.emit()
	t.check(view._zoom > 1.0, "the + button zooms in")
	(buttons[1] as Button).pressed.emit()
	t.check_near(view._zoom, 1.0, 0.0001, "the - button zooms back out")

	view.free()


func test_keyboard_camera_through_the_screen(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 7)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	screen.size = Vector2(1200, 800)

	var zoom_before: float = screen.map_view._zoom
	screen._unhandled_key_input(_key(KEY_EQUAL))
	t.check(screen.map_view._zoom > zoom_before, "+ zooms in")
	screen._unhandled_key_input(_key(KEY_MINUS))
	t.check_near(screen.map_view._zoom, zoom_before, 0.0001, "- zooms out")

	var capital: String = game.state["factions"]["julii"]["capital"]
	screen.map_view.reset_view()
	var anchor := screen.map_view.to_screen(screen.map_view.world_pos(game.data.regions[capital]))
	screen._unhandled_key_input(_key(KEY_RIGHT))
	var panned := screen.map_view.to_screen(screen.map_view.world_pos(game.data.regions[capital]))
	t.check_near(anchor.x - panned.x, MapView.KEY_PAN_STEP, 0.001, "the right arrow looks east")
	screen._unhandled_key_input(_key(KEY_D))
	t.check(screen.map_view.to_screen(screen.map_view.world_pos(game.data.regions[capital])).x < panned.x,
		"D pans like the right arrow")

	screen._unhandled_key_input(_key(KEY_HOME))
	t.check_eq(screen.map_view._region_at(screen.map_view.size / 2.0), capital,
		"Home brings the capital back to the middle")

	# A key the map does not use is left alone for everything else.
	var untouched: float = screen.map_view._zoom
	screen._unhandled_key_input(_key(KEY_F5))
	t.check_near(screen.map_view._zoom, untouched, 0.0001, "unrelated keys move nothing")

	screen.free()


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


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


func test_clicking_inside_a_province_selects_it(t) -> void:
	## The map paints whole territories now, so a click well away from the
	## token — but inside the province — must still select that region.
	var game := Game.new_campaign("cornelii", 42)
	var view := MapView.new()
	view.game = game
	view.size = Vector2(900, 700)
	var capital: String = game.state["factions"]["cornelii"]["capital"]
	var geo := MapGeometry.for_data(game.data)
	var seat := view.world_pos(game.data.regions[capital])
	# A point inside the capital's polygon but far outside its token.
	var far_inside := Vector2.ZERO
	for point in geo.cells[capital]:
		var candidate: Vector2 = seat.lerp(point, 0.85)
		if Geometry2D.is_point_in_polygon(candidate, geo.cells[capital]) \
				and candidate.distance_to(seat) > 30.0:
			far_inside = candidate
			break
	t.check(far_inside != Vector2.ZERO, "the capital's province has room beyond its token")
	t.check_eq(view._region_at(view.to_screen(far_inside)), capital,
		"a click inside the province selects it")
	view.free()
