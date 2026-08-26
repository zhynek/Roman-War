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
