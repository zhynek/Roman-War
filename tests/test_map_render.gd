extends RefCounted
## The layered map renderer's logic paths (nothing rasterizes headless):
## polygon picking claims whole cells instead of 26-pixel token discs,
## icon parameters come from the rules and not guesses, and worlds without
## geometry — the fixtures — still instantiate, pick, and refresh.


func test_polygon_picking_claims_the_whole_cell(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new_campaign("julii", 7)
	var view := MapView.new()
	view.game = game
	view.size = Vector2(800, 600)
	tree.root.add_child(view)
	t.check(view.geometry() != null, "the authored campaign loads polygon geometry")

	# Find a point inside some region's cell that lies farther than the old
	# 26 px pick radius from EVERY region anchor — the old map called this
	# empty sea; the new one must attribute it to its region.
	var geometry := view.geometry()
	var region_ids: Array = game.data.regions.keys()
	region_ids.sort()
	var found_region := ""
	var found_world := Vector2.ZERO
	for region_id in region_ids:
		var cell: Dictionary = geometry.cells[region_id]
		var bounds: Rect2 = cell["bounds"]
		for iy in range(6):
			for ix in range(6):
				var candidate: Vector2 = bounds.position + Vector2(
					bounds.size.x * (float(ix) + 0.5) / 6.0, bounds.size.y * (float(iy) + 0.5) / 6.0)
				var inside := false
				for polygon in cell["polygons"]:
					if Geometry2D.is_point_in_polygon(candidate, polygon):
						inside = true
						break
				if not inside:
					continue
				var beyond_every_disc := true
				for other_id in region_ids:
					if view.world_pos(game.data.regions[other_id]).distance_to(candidate) < 30.0:
						beyond_every_disc = false
						break
				if beyond_every_disc:
					found_region = region_id
					found_world = candidate
					break
			if found_region != "":
				break
		if found_region != "":
			break
	t.check(found_region != "", "some cell offerss ground beyond every token disc")
	if found_region != "":
		view.center_on(found_region)
		t.check_eq(view._region_at(view.to_screen(found_world)), found_region,
			"clicking open countryside picks its region")
	view.free()


func test_icon_params_come_from_the_rules(t) -> void:
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	game.resolver = AutoResolver.new()

	var beta := SettlementIcons.icon_params(game, "beta")
	t.check_eq(beta["level"], 1, "government tier 2 reads as a town")
	t.check_eq(beta["culture"], "roman", "culture follows the owner")
	t.check_eq(int(beta["wall_level"]), 0, "no walls built, none drawn")
	t.check(not beta["port"], "an inland town has no quay")
	t.check(beta["capital"], "beta is red's capital")
	t.check(not beta["siege"], "no siege ring at peace")

	game.state["settlements"]["beta"]["buildings"]["test_walls"] = 1
	t.check_eq(int(SettlementIcons.icon_params(game, "beta")["wall_level"]), 1,
		"built walls raise the drawn circuit")

	var alpha := SettlementIcons.icon_params(game, "alpha")
	t.check_eq(alpha["culture"], "barbarian", "tribal settlements draw tribal")
	game.state["settlements"]["alpha"]["siege"] = {"besieger": "red", "turns": 1}
	t.check(SettlementIcons.icon_params(game, "alpha")["siege"], "a siege shows its ring")

	t.check(SettlementIcons.icon_params(game, "gamma").is_empty(), "unsettled regions draw nothing")


func test_fixture_world_falls_back_and_still_picks(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	game.resolver = AutoResolver.new()

	var view := MapView.new()
	view.game = game
	view.size = Vector2(800, 600)
	tree.root.add_child(view)
	t.check(view.geometry() == null, "fixtures carry no polygon geometry")

	view.center_on("beta")
	var screen := view.to_screen(view.world_pos(game.data.regions["beta"]))
	t.check_eq(view._region_at(screen), "beta", "nearest-anchor fallback picks the token")
	t.check_eq(view._region_at(screen + Vector2(4000, 4000)), "", "and open sea picks nothing")

	view.refresh_state()
	view.selected_region = "beta"
	view.highlight_regions = {"alpha": "normal"}
	view.refresh_state()
	t.check(true, "refresh_state runs without geometry")
	view.free()
