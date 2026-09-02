extends RefCounted
## Headless smoke test for the campaign UI: boot the screen on a real
## campaign, click regions, select and order an army, end a turn, save/load,
## open the family scroll. No rendering happens headless — this guards the
## UI's logic paths, not its looks.
##
## Most tests set playback_enabled = false: the day's sequence is an animation
## driven by frame time, and a headless loop has no frames. The turn itself is
## unaffected — the engine resolves it in full either way — and
## test_the_day_plays_and_skips covers the playback path deliberately.


func test_campaign_screen_boots_and_plays(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	screen.playback_enabled = false

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

	# The annals open (a turn has passed — the scribes have something).
	screen.annals_panel.open_for(game)
	t.check(screen.annals_panel._content.get_child_count() > 0, "the annals render")
	screen.annals_panel.hide()

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


func _button_event(button: int, is_pressed: bool, at: Vector2, double: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = is_pressed
	event.position = at
	event.double_click = double
	return event


func _motion_event(at: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	return event


func test_map_gestures(t) -> void:
	## The command grammar of the map: a left press is only a click if the
	## mouse never travels — travel pans instead. Middle-drag pans as ever.
	## The right button no longer pans at all: it asks for the dossier.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 7)
	var view := MapView.new()
	view.game = game
	view.size = Vector2(800, 600)
	tree.root.add_child(view)

	var clicks: Array = []
	var menus: Array = []
	view.region_clicked.connect(func(region_id: String): clicks.append(region_id))
	view.region_context_requested.connect(func(region_id: String): menus.append(region_id))

	var capital: String = game.state["factions"]["julii"]["capital"]
	view.center_on(capital)
	var at := view.to_screen(view.world_pos(game.data.regions[capital]))

	# A press and a still release: that is the click.
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, true, at))
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, false, at))
	t.check_eq(clicks.size(), 1, "a still release delivers the click")
	if clicks.size() == 1:
		t.check_eq(String(clicks[0]), capital, "on the region under the cursor")

	# Travel turns the press into a pan and swallows the click.
	var camera_before := view._camera_offset
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, true, at))
	view._gui_input(_motion_event(at + Vector2(40, 25), Vector2(40, 25)))
	view._gui_input(_motion_event(at + Vector2(80, 50), Vector2(40, 25)))
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, false, at + Vector2(80, 50)))
	t.check(view._camera_offset != camera_before, "left-drag pans the map")
	t.check_eq(clicks.size(), 1, "a drag is never a click")

	# A hand's wobble under the threshold still clicks — and the click stays
	# aimed at the PRESSED region: the tolerance forgives the wobble, it must
	# never let the wobble re-aim an order across a border.
	at = view.to_screen(view.world_pos(game.data.regions[capital]))
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, true, at))
	view._gui_input(_motion_event(at + Vector2(3, 2), Vector2(3, 2)))
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, false, at + Vector2(3, 2)))
	t.check_eq(clicks.size(), 2, "a wobble under the threshold does not eat the click")
	if clicks.size() == 2:
		t.check_eq(String(clicks[1]), capital, "and the click names the pressed region")

	# Middle-drag pans as it always has. The drag runs down the world's long
	# axis — a pure-x drag can die against the camera clamp when the view
	# already rests on that boundary.
	camera_before = view._camera_offset
	view._gui_input(_button_event(MOUSE_BUTTON_MIDDLE, true, at))
	view._gui_input(_motion_event(at + Vector2(0, -60), Vector2(0, -60)))
	view._gui_input(_button_event(MOUSE_BUTTON_MIDDLE, false, at + Vector2(0, -60)))
	t.check(view._camera_offset != camera_before, "middle-drag still pans")

	# The right button asks for the dossier — and never moves the camera.
	at = view.to_screen(view.world_pos(game.data.regions[capital]))
	camera_before = view._camera_offset
	view._gui_input(_button_event(MOUSE_BUTTON_RIGHT, true, at))
	view._gui_input(_motion_event(at + Vector2(50, 30), Vector2(50, 30)))
	view._gui_input(_button_event(MOUSE_BUTTON_RIGHT, false, at + Vector2(50, 30)))
	t.check_eq(menus.size(), 1, "right-click requests the region dossier")
	if menus.size() == 1:
		t.check_eq(String(menus[0]), capital, "for the region under the cursor")
	t.check(view._camera_offset == camera_before, "the right button no longer pans")
	t.check_eq(clicks.size(), 2, "and it is never a left-click")

	# A double-click's second press centers the camera and orders nothing.
	at = view.to_screen(view.world_pos(game.data.regions[capital]))
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, true, at))
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, false, at))
	camera_before = view._camera_offset
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, true, at, true))
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, false, at))
	t.check_eq(clicks.size(), 3, "the double-click's second press issues no second order")
	t.check(view._camera_offset != camera_before, "it centers the camera instead")

	# The right button stays silent mid-chord: no dossier while a left press
	# or a drag is live, so no click can fire underneath an opening menu.
	at = view.to_screen(view.world_pos(game.data.regions[capital]))
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, true, at))
	view._gui_input(_button_event(MOUSE_BUTTON_RIGHT, true, at))
	t.check_eq(menus.size(), 1, "no dossier during a live left press")
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, false, at))
	t.check_eq(clicks.size(), 4, "the left release still clicks once the chord is over")
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, true, at))
	view._gui_input(_motion_event(at + Vector2(30, -30), Vector2(30, -30)))
	view._gui_input(_button_event(MOUSE_BUTTON_RIGHT, true, at + Vector2(30, -30)))
	t.check_eq(menus.size(), 1, "no dossier mid-drag either")
	view._gui_input(_button_event(MOUSE_BUTTON_LEFT, false, at + Vector2(30, -30)))
	t.check_eq(clicks.size(), 4, "and the drag still swallows the click")

	# A sea gesture obeys the same grammar: a still release addresses the
	# sea; a drag over water is a pan, never a sail order.
	var seas: Array = []
	view.sea_zone_clicked.connect(func(zone_id: String): seas.append(zone_id))
	var sea_at := Vector2.ZERO
	var found_sea := false
	var zone_ids: Array = game.data.sea_zones.keys()
	zone_ids.sort()
	for zone_id in zone_ids:
		var anchor: Dictionary = game.data.sea_zones[zone_id].get("position", {})
		if anchor.is_empty():
			continue
		var candidate := view.to_screen(Vector2(
			float(anchor["x"]), float(anchor["y"])) * MapView.WORLD_SCALE)
		if view._region_at(candidate) == "" and view._sea_zone_at(candidate) == zone_id:
			sea_at = candidate
			found_sea = true
			break
	t.check(found_sea, "an open-water anchor exists to click")
	if found_sea:
		view._gui_input(_button_event(MOUSE_BUTTON_LEFT, true, sea_at))
		view._gui_input(_button_event(MOUSE_BUTTON_LEFT, false, sea_at))
		t.check_eq(seas.size(), 1, "a still release over open water addresses the sea")
		view._gui_input(_button_event(MOUSE_BUTTON_LEFT, true, sea_at))
		view._gui_input(_motion_event(sea_at + Vector2(0, -40), Vector2(0, -40)))
		view._gui_input(_button_event(MOUSE_BUTTON_LEFT, false, sea_at + Vector2(0, -40)))
		t.check_eq(seas.size(), 1, "a drag over water is a pan, not a sail order")
	view.free()


func test_polygon_picking_and_state_caches(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 7)
	var view := MapView.new()
	view.game = game
	view.size = Vector2(800, 600)
	tree.root.add_child(view)
	view.refresh_state()

	t.check(view.geometry != null, "the real campaign has map geometry")
	t.check(not view.visible_cache.is_empty(), "refresh_state fills the fog cache")
	t.check(not view.army_groups.is_empty(), "refresh_state groups armies")

	# Picking is by territory polygon now: a point well outside the legacy
	# 26-px anchor disc but inside the capital's territory still picks it.
	var capital: String = game.state["factions"]["julii"]["capital"]
	view.center_on(capital)
	var anchor := view.to_screen(view.world_pos(game.data.regions[capital]))
	var deep_hit := false
	for direction in range(16):
		var offset := Vector2.RIGHT.rotated(TAU * direction / 16.0) * 45.0
		if view._region_at(anchor + offset) == capital:
			deep_hit = true
			break
	t.check(deep_hit, "territory picking reaches beyond the anchor disc")

	# The settlement icon extractor reads pure campaign data.
	var params := SettlementIcons.icon_params(game, capital)
	t.check_eq(params.get("culture", ""), "roman", "the capital draws in Roman style")
	t.check(int(params.get("level", 0)) >= 1 and int(params.get("level", 0)) <= 6,
		"settlement level within the ladder")
	t.check(params.get("is_capital", false), "the capital wears the laurel")
	t.check(int(params.get("wall_level", -1)) >= 0, "wall tier extracted")

	# Decor glyph anchors are deterministic — hashed from region ids, never
	# drawn from the campaign RNG.
	var rng_before: String = game.state["rng_state"]
	var first := view.decor_points(capital)
	view._decor_cache.clear()
	t.check_eq(view.decor_points(capital), first, "decor placement is deterministic")
	t.check_eq(game.state["rng_state"], rng_before, "the map never touches the game RNG")
	view.free()

	# A fixture world has no geometry match and no positions: the view must
	# still build, cache, and pick by anchor distance.
	var fixture_game := Game.new()
	fixture_game.data = Fixtures.data()
	fixture_game.state = Fixtures.state(fixture_game.data)
	var fixture_view := MapView.new()
	fixture_view.game = fixture_game
	fixture_view.size = Vector2(800, 600)
	tree.root.add_child(fixture_view)
	fixture_view.refresh_state()
	fixture_view.center_on("beta")
	var beta_screen := fixture_view.to_screen(fixture_view.world_pos(fixture_game.data.regions["beta"]))
	t.check_eq(fixture_view._region_at(beta_screen), "beta", "fixture worlds pick by anchor")
	fixture_view.free()


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


func test_movement_ux_paths(t) -> void:
	## Range overlay, hover path preview, tooltip content, and a multi-hop
	## click that becomes a march order — never a war. The world is searched
	## across a few fixed seeds for a fully scouted multi-leg land target, so
	## the order's outcome is deterministic: arrive, or stay queued.
	var tree := Engine.get_main_loop() as SceneTree
	var game: Game
	var screen: CampaignScreen
	var army_id := ""
	var home := ""
	var target := ""
	for seed_value in [42, 7, 11, 1234, 99]:
		game = Game.new_campaign("julii", seed_value)
		screen = CampaignScreen.create(game)
		tree.root.add_child(screen)
		army_id = ""
		var army_ids: Array = game.state["armies"].keys()
		army_ids.sort()
		for candidate in army_ids:
			if game.state["armies"][candidate]["owner"] == "julii":
				army_id = candidate
				break
		if army_id != "":
			home = game.state["armies"][army_id]["region"]
			target = _scouted_multi_leg_target(game, army_id, home)
		if target != "":
			break
		screen.free()
	t.check(army_id != "", "julii fields an army")
	t.check(target != "", "a scouted multi-leg destination exists in some seed")
	if target == "":
		return

	screen._on_region_clicked(home)
	screen._on_army_selected(army_id)
	t.check(not screen.map_view.highlight_regions.is_empty(),
		"selecting an army lights its reach")
	t.check(screen.map_view.tooltip != null, "the map has a tooltip")
	var capital: String = game.state["factions"]["julii"]["capital"]
	t.check(screen._tooltip_for(capital).contains(
		String(game.data.regions[capital]["settlement_name"])),
		"the tooltip names the settlement")

	screen._on_region_hovered(target)
	t.check(not screen.map_view.path_preview.is_empty(), "hover sketches the route")
	t.check((screen.map_view.path_preview["legs"] as Array).size() >= 2,
		"the sketch has per-leg costs")

	var stances_before: Dictionary = game.state["factions"]["julii"]["diplomacy"].duplicate()
	screen._on_region_clicked(target)
	var army: Dictionary = game.state["armies"][army_id]
	t.check(army["region"] != home, "the multi-leg order moved the army at once")
	t.check(army["region"] == target or army.has("march_path"),
		"the army arrived or the rest of the road is queued")
	for other_faction in stances_before:
		if stances_before[other_faction] != "war":
			t.check(game.state["factions"]["julii"]["diplomacy"][other_faction] != "war",
				"the march did not declare war on " + String(other_faction))
	t.check(screen.map_view.path_preview.is_empty(), "the sketch clears after the order")
	screen.free()


func _scouted_multi_leg_target(game: Game, army_id: String, home: String) -> String:
	## A land destination at least two legs out that no ship could reach
	## instead (the order chain would legitimately sail), and whose road is
	## provably clean — the test peeks with full knowledge that no at-war
	## settlement or army stands on any step, so the march cannot halt.
	var player: String = game.state["player_faction"]
	var region_ids: Array = game.data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		if _sea_reachable(game, home, region_id):
			continue
		var preview := game.army_path_preview(army_id, region_id)
		if preview.is_empty() or preview["blocked_destination"] \
				or (preview["path"] as Array).size() < 2:
			continue
		var clean := true
		for step in preview["path"]:
			var holder: String = game.state["settlements"].get(step, {}).get("owner", "")
			if holder != "" and DiplomacyRules.at_war(game.state, player, holder):
				clean = false
				break
			for other in game.state["armies"].values():
				if other["region"] == step and DiplomacyRules.at_war(game.state, player, other["owner"]):
					clean = false
					break
			if not clean:
				break
		if clean:
			return region_id
	return ""


func test_fleet_orders_from_the_map(t) -> void:
	# The Cornelii: the Roman house that actually starts with a fleet.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	var fleet_id := ""
	var fleet_ids: Array = game.state["fleets"].keys()
	fleet_ids.sort()
	for candidate in fleet_ids:
		if game.state["fleets"][candidate]["owner"] == "cornelii":
			fleet_id = candidate
			break
	t.check(fleet_id != "", "the cornelii put to sea")
	if fleet_id != "":
		var zone: String = game.state["fleets"][fleet_id]["sea_zone"]
		screen._on_sea_zone_clicked(zone)
		t.check_eq(screen.selected_fleet, fleet_id, "clicking the fleet's sea takes the helm")
		t.check(not screen.map_view.highlight_zones.is_empty(), "the open lanes light up")
		var lanes: Array = screen.map_view.highlight_zones.keys()
		lanes.sort()
		screen._on_sea_zone_clicked(String(lanes[0]))
		t.check_eq(game.state["fleets"][fleet_id]["sea_zone"], String(lanes[0]),
			"the fleet sailed down the lane")
		t.check_eq(screen.map_view.selected_sea_zone, String(lanes[0]),
			"the selection ring follows the fleet")
		# Any refresh re-derives the overlay from live state — no stale lanes.
		screen.refresh()
		t.check_eq(screen.map_view.selected_sea_zone, String(lanes[0]),
			"refresh keeps the ring on the fleet's real sea")
		# Loading a save stands the fleet down entirely.
		screen._save_game()
		screen._load_game()
		t.check_eq(screen.selected_fleet, "", "loading stands the fleet down")
		t.check_eq(screen.map_view.selected_sea_zone, "", "no ghost ring after a load")
		# A region click drops the helm too.
		screen._on_sea_zone_clicked(String(lanes[0]))
		screen._on_region_clicked(game.state["factions"]["cornelii"]["capital"])
		t.check_eq(screen.selected_fleet, "", "selecting land stands the fleet down")
	screen.free()


func _sea_reachable(game: Game, from_region: String, to_region: String) -> bool:
	## Mirrors MovementRules.sea_move_army's zone test: same or adjacent zone.
	var from_zones: Array = game.data.regions[from_region].get("sea_zones", [])
	var to_zones: Array = game.data.regions[to_region].get("sea_zones", [])
	for zone in from_zones:
		if to_zones.has(zone):
			return true
		for adjacent_zone in game.data.sea_zones.get(zone, {}).get("adjacent", []):
			if to_zones.has(adjacent_zone):
				return true
	return false


func test_map_camera_controls(t) -> void:
	## Every camera route a mouseless player has: buttons, keys, gestures.
	## The zoom_by / pan_by / reset_view API came from the other map branch and
	## is grafted onto the renderer main kept, so this still holds.
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
	screen.playback_enabled = false

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


func test_fog_hides_built_road_tiers(t) -> void:
	## Seleucia starts with a road at assyria — deep inside julii's fog. The
	## paving is built state, not geography: it must not render for julii,
	## and must render for the faction that can see it.
	var tree := Engine.get_main_loop() as SceneTree
	var blind := CampaignScreen.create(Game.new_campaign("julii", 7))
	tree.root.add_child(blind)
	t.check(not blind.map_view.visible_cache.has("assyria"), "assyria starts unscouted for julii")
	var leaked := false
	for key in blind.map_view.road_levels:
		var ends: PackedStringArray = String(key).split("|")
		if (String(ends[0]) == "assyria" or String(ends[1]) == "assyria") \
				and int(blind.map_view.road_levels[key]) > 0:
			leaked = true
	t.check(not leaked, "no paved road renders out of unscouted assyria")
	blind.free()

	var owner := CampaignScreen.create(Game.new_campaign("seleucia", 7))
	tree.root.add_child(owner)
	var shown := false
	for key in owner.map_view.road_levels:
		var ends: PackedStringArray = String(key).split("|")
		if (String(ends[0]) == "assyria" or String(ends[1]) == "assyria") \
				and int(owner.map_view.road_levels[key]) > 0:
			shown = true
	t.check(shown, "the road's own builder sees it paved")
	owner.free()
func test_the_day_plays_and_skips(t) -> void:
	## The playback path: end a turn with the sequence on, skip it, and check
	## the day closes on a populated Dispatch that dismisses cleanly.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 42)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	# Turn 1 is quiet for a house nobody is playing; run a few so the journal
	# has something in it worth playing.
	screen.playback_enabled = false
	for i in range(12):
		screen._end_turn()
	screen.playback_enabled = true

	var turn_before := int(game.state["turn"])
	screen._end_turn()
	t.check_eq(int(game.state["turn"]), turn_before + 1,
		"the turn resolves in full before a single frame of the day is played")
	t.check(screen.dispatch_panel != null, "the dispatch exists")

	if screen.turn_sequence.is_playing():
		# A second end turn must not run a second day underneath the first.
		screen._end_turn()
		t.check_eq(int(game.state["turn"]), turn_before + 1,
			"ending the turn again while the day plays does nothing")
		screen.turn_sequence.skip_to_end()
	t.check(not screen.turn_sequence.is_playing(), "skip ends the day at once")
	t.check(screen.map_view.highlight_regions.is_empty(), "skip clears the map highlight")

	t.check(screen.dispatch_panel.visible, "the day closes on the dispatch")
	t.check(screen.dispatch_panel._content.get_child_count() > 0, "the dispatch has something to say")
	screen.dispatch_panel._on_dismiss()
	t.check(not screen.dispatch_panel.visible, "the dispatch dismisses")

	# And the next day can begin.
	screen._end_turn()
	t.check_eq(int(game.state["turn"]), turn_before + 2, "the next day begins")
	screen.turn_sequence.skip_to_end()

	screen.free()


func test_dispatch_reopens_from_the_top_bar(t) -> void:
	## The journal lives in the game state, so the day just closed can be read
	## again — including after a save and load.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 7)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	screen.playback_enabled = false
	for i in range(10):
		screen._end_turn()

	screen._show_dispatch()
	t.check(screen.dispatch_panel.visible, "the dispatch reopens on demand")
	screen.dispatch_panel._on_dismiss()

	screen._save_game()
	screen._load_game()
	t.check_eq(int(game.state["journal"]["turn"]), int(game.state["turn"]),
		"the journal came back with the save")
	screen._show_dispatch()
	t.check(screen.dispatch_panel.visible, "and still opens after a load")
	screen.dispatch_panel._on_dismiss()

	screen.free()


func test_campaign_screen_fills_its_window(t) -> void:
	## Regression: `set_anchors_preset` KEEPS the control's current rect, so a
	## freshly built (0x0) CampaignScreen stayed 0x0 and rendered at its minimum
	## size in the top-left corner, growing only by the delta of a window
	## resize — Godot's grey clear colour over the rest of the window. The
	## screen, and every full-rect overlay on it, must anchor AND zero offsets.
	## resize. The whole screen must anchor full-rect AND zero its offsets.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 11)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)

	t.check_near(screen.anchor_left, 0.0, 0.001, "anchored to the left edge")
	t.check_near(screen.anchor_top, 0.0, 0.001, "anchored to the top edge")
	t.check_near(screen.anchor_right, 1.0, 0.001, "anchored to the right edge")
	t.check_near(screen.anchor_bottom, 1.0, 0.001, "anchored to the bottom edge")
	for offset in [screen.offset_left, screen.offset_top,
			screen.offset_right, screen.offset_bottom]:
		t.check_near(offset, 0.0, 0.001, "offsets are zeroed, not left at -size")

	var window := tree.root.get_visible_rect().size
	t.check_near(screen.size.x, window.x, 1.0, "the screen is as wide as its window")
	t.check_near(screen.size.y, window.y, 1.0, "the screen is as tall as its window")

	# The day's overlays are full-rect too: a 0x0 TurnSequence would play the
	# whole day inside a single corner pixel.
	for overlay in [screen.turn_sequence, screen.dispatch_panel]:
		t.check_near(overlay.size.x, window.x, 1.0,
			"%s spans the window" % overlay.get_class())
		t.check_near(overlay.size.y, window.y, 1.0,
			"%s fills the window height" % overlay.get_class())

	screen.free()


func test_clicking_inside_a_province_selects_it(t) -> void:
	## The map paints whole territories, so a click well away from the token —
	## but inside the province — must still select that region. Written against
	## the geometry main kept: cells carry convex fills and the lookup is
	## region_at_world, rather than the other branch's raw polygon per cell.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 42)
	var view := MapView.new()
	view.game = game
	view.size = Vector2(900, 700)
	tree.root.add_child(view)
	var capital: String = game.state["factions"]["cornelii"]["capital"]
	view.center_on(capital)
	t.check(view.geometry != null, "the campaign has map geometry")

	# Walk outward from the seat until we are well outside the old anchor disc
	# but still inside the capital's own territory.
	var seat := view.world_pos(game.data.regions[capital])
	var far_inside := Vector2.ZERO
	for ring in range(4, 14):
		var radius := float(ring) * 8.0
		for step in range(24):
			var candidate := seat + Vector2.RIGHT.rotated(TAU * step / 24.0) * radius
			if view.geometry.region_at_world(candidate) == capital \
					and candidate.distance_to(seat) > 30.0:
				far_inside = candidate
				break
		if far_inside != Vector2.ZERO:
			break
	t.check(far_inside != Vector2.ZERO, "the capital's province has room beyond its token")
	t.check_eq(view._region_at(view.to_screen(far_inside)), capital,
		"a click inside the province selects it")
	view.free()


func test_building_yard_opens_and_shows_a_chain(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 11)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var capital: String = game.state["factions"]["cornelii"]["capital"]
	screen._on_region_clicked(capital)

	t.check(not screen.build_drawer.visible, "the yard starts shut")
	screen.open_drawer("construction", "")
	t.check(screen.build_drawer.visible, "and opens on request")
	# Opening with nothing chosen must never land on a blank pane.
	t.check(screen.build_drawer._list.get_child_count() > 0, "the chain list fills")
	t.check(screen.build_drawer._detail.get_child_count() > 0, "the detail pane fills")
	t.check(screen.build_drawer._ladder.get_child_count() > 0, "the tier ladder fills")

	screen.open_drawer("construction", "roman_walls")
	var ladder: int = screen.build_drawer._ladder.get_child_count()
	t.check(ladder >= 5, "the walls ladder shows every rung and its chevrons (%d)" % ladder)
	screen.queue_free()


func test_the_yard_follows_the_map_selection(t) -> void:
	## _on_region_clicked does not go through refresh(), so without an explicit
	## re-render the drawer keeps showing the previous city's ladder.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 12)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var owned: Array = []
	for region_id in game.state["settlements"]:
		if game.state["settlements"][region_id]["owner"] == "cornelii":
			owned.append(region_id)
	owned.sort()
	t.check(owned.size() >= 2, "the house holds more than one city to compare")
	screen._on_region_clicked(String(owned[0]))
	screen.open_drawer("construction", "")
	var first := screen.build_drawer._title.text
	screen._on_region_clicked(String(owned[1]))
	t.check(screen.build_drawer._title.text != first,
		"clicking another city redraws the yard for it")
	screen.queue_free()


func test_the_yard_survives_a_refresh_and_a_turn(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 13)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	screen._on_region_clicked(String(game.state["factions"]["cornelii"]["capital"]))
	screen.open_drawer("construction", "roman_walls")
	screen.refresh()
	t.check(screen.build_drawer.visible, "a refresh does not shut the yard")
	t.check(screen.build_drawer._ladder.get_child_count() > 0, "nor empty it")
	t.check_eq(screen.drawer_chain, "roman_walls", "the chosen chain is remembered")
	game.end_turn()
	screen.refresh()
	t.check(screen.build_drawer._detail.get_child_count() > 0, "and it survives a turn")
	screen.queue_free()


func test_escape_shuts_the_yard_and_leaves_the_camera_alone(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 14)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	screen._on_region_clicked(String(game.state["factions"]["cornelii"]["capital"]))
	screen.open_drawer("construction", "")
	screen._unhandled_key_input(_key(KEY_ESCAPE))
	t.check(not screen.build_drawer.visible, "escape shuts it")
	# The arrow keys must still drive the map: that contract predates the drawer.
	var before: Vector2 = screen.map_view._camera_offset
	screen._unhandled_key_input(_key(KEY_RIGHT))
	t.check(screen.map_view._camera_offset != before, "and the camera still answers")
	screen.queue_free()


func test_the_yard_queues_through_the_facade(t) -> void:
	## Queueing must go through Game so the guided trail's counters still fire.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 15)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var capital: String = game.state["factions"]["cornelii"]["capital"]
	screen._on_region_clicked(capital)
	var before := int(game.state["guided"]["counters"].get("buildings_queued", 0))
	var projects: Array = game.available_buildings(capital)
	t.check(not projects.is_empty(), "the capital has something to raise")
	projects.sort_custom(func(a, b): return int(a["cost"]) < int(b["cost"]))
	var purse := int(game.state["factions"]["cornelii"]["treasury"])
	t.check(int(projects[0]["cost"]) <= purse, "and can afford the cheapest of them")
	t.check(game.queue_building(capital, String(projects[0]["chain"])), "the order takes")
	t.check_eq(int(game.state["guided"]["counters"].get("buildings_queued", 0)), before + 1,
		"the trail still counts a queued building")
	screen.queue_free()


func test_the_yard_fits_the_map_at_its_minimum_size(t) -> void:
	## MapView's own minimum is 600x400. A fixed plate height cannot coexist
	## with that, so the drawer measures itself against the map it sits in.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 16)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	screen._on_region_clicked(String(game.state["factions"]["cornelii"]["capital"]))
	screen.open_drawer("construction", "roman_walls")
	screen.build_drawer.fit_to(Vector2(600, 400))
	t.check(absf(screen.build_drawer.offset_top) < 400.0,
		"the drawer never taller than the map that holds it")
	t.check(screen.build_drawer._compact, "and it goes compact when the map is short")
	screen.build_drawer.render(game, screen.map_view.selected_region,
		"construction", "roman_walls", 0)
	t.check(screen.build_drawer._detail.get_child_count() > 0, "still rendering when compact")
	screen.build_drawer.fit_to(Vector2(1600, 1000))
	t.check(not screen.build_drawer._compact, "and back to full on a big window")
	screen.queue_free()


func test_the_muster_hall_shows_a_unit_and_what_it_needs(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 17)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	var capital: String = game.state["factions"]["cornelii"]["capital"]
	screen._on_region_clicked(capital)
	screen.open_drawer("units", "")
	t.check(screen.build_drawer._list.get_child_count() > 0, "the roster fills")
	t.check(screen.build_drawer._detail.get_child_count() > 0, "a unit is shown")
	# The reverse link: a unit's panel draws the ladder of the chain that opens it.
	t.check(screen.build_drawer._ladder.get_child_count() > 0,
		"and the training ground's ladder with it")

	screen.open_drawer("units", "roman_principes")
	var sheet := game.unit_dossier(capital, "roman_principes")
	t.check_eq(String(sheet["requires"]["kind"]), "barracks", "principes want a barracks")
	t.check(screen.build_drawer._detail.get_child_count() > 0, "and the panel renders for them")
	screen.queue_free()


func test_both_tabs_render_for_every_owned_city(t) -> void:
	## The drawer must survive whatever the map selection is: a village with
	## almost nothing built, a captured foreign city, a city under siege.
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("cornelii", 18)
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	for i in 6:
		game.end_turn()
	var owned: Array = []
	for region_id in game.state["settlements"]:
		if game.state["settlements"][region_id]["owner"] == "cornelii":
			owned.append(region_id)
	owned.sort()
	for region_id in owned:
		screen._on_region_clicked(String(region_id))
		for tab in ["construction", "units"]:
			screen.open_drawer(tab, "")
			t.check(screen.build_drawer._detail.get_child_count() > 0,
				"%s renders in %s" % [tab, region_id])
	screen.queue_free()
	t.check_near(screen.anchor_top, 0.0, 0.001, "and the top")
	t.check_near(screen.anchor_right, 1.0, 0.001, "stretched to the right edge")
	t.check_near(screen.anchor_bottom, 1.0, 0.001, "and the bottom")
	# The offsets are the actual bug: nonzero here means the screen renders
	# smaller than its window by exactly that much, forever.
	t.check_near(screen.offset_left, 0.0, 0.001, "no left inset")
	t.check_near(screen.offset_top, 0.0, 0.001, "no top inset")
	t.check_near(screen.offset_right, 0.0, 0.001, "no right inset — the screen fills the window")
	t.check_near(screen.offset_bottom, 0.0, 0.001, "no bottom inset")
	screen.free()
