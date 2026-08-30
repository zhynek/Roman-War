extends RefCounted
## The procedural landmass: headless tests never draw, so these pin the two
## properties the renderer depends on — every region owns a usable polygon
## containing its own settlement point (so picking and art agree), and the
## whole construction is deterministic (CLAUDE.md's replay rule).


func test_every_region_gets_a_cell_around_its_settlement(t) -> void:
	var data := GameData.load_from("res://data")
	var geo := MapGeometry.for_data(data)
	t.check_eq(geo.ids.size(), data.regions.size(), "one cell per region")
	for id in geo.ids:
		var cell: PackedVector2Array = geo.cells[id]
		t.check(cell.size() >= 3, "%s has a drawable polygon (%d verts)" % [id, cell.size()])
		t.check(Geometry2D.is_point_in_polygon(geo.world_of(id), cell),
			"%s's settlement point lies inside its own province" % id)
		t.check_eq(geo.tags[id].size(), cell.size(), "%s tags every edge" % id)


func test_geometry_is_deterministic(t) -> void:
	var data := GameData.load_from("res://data")
	var first := MapGeometry.new()
	first._build(data)
	var second := MapGeometry.new()
	second._build(data)
	for id in first.ids:
		t.check(first.cells[id] == second.cells[id],
			"%s rebuilds to identical vertices" % id)
	t.check(first.coast_lines == second.coast_lines, "coast segments identical")
	t.check(first.frontier_lines == second.frontier_lines, "frontier segments identical")


func test_landlocked_regions_have_no_coastline(t) -> void:
	## The frontier tag: an inland edge of the known world must not read as a
	## shore, or Parthia grows a beach with a glowing shelf.
	var data := GameData.load_from("res://data")
	var geo := MapGeometry.for_data(data)
	for id in geo.ids:
		if not (data.regions[id].get("sea_zones", []) as Array).is_empty():
			continue
		for tag in geo.tags[id]:
			t.check(tag != MapGeometry.COAST,
				"landlocked %s carries no coast edge" % id)


func test_shelf_runs_follow_the_shore_only(t) -> void:
	## The shelf is stroked along coast_runs, so a landlocked region must
	## contribute none of them — Parthia gets no beach.
	var data := GameData.load_from("res://data")
	var geo := MapGeometry.for_data(data)
	var coastal_with_runs := 0
	for id in geo.ids:
		var runs: Array = geo.coast_runs[id]
		if (data.regions[id].get("sea_zones", []) as Array).is_empty():
			t.check(runs.is_empty(), "landlocked %s contributes no shelf" % id)
		else:
			for run in runs:
				t.check(run.size() >= 2, "%s's shelf run is drawable" % id)
			if not runs.is_empty():
				coastal_with_runs += 1
	t.check(coastal_with_runs >= 40, "most coastal regions have a shore (got %d)" % coastal_with_runs)
