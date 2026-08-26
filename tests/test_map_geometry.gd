extends RefCounted
## The committed map geometry, loaded headlessly: every campaign region has
## territory, that territory contains the region's map position, every land
## adjacency has a road, and fills decomposed for rendering.


func test_geometry_covers_the_campaign_map(t) -> void:
	var geometry := MapGeometry.load_from()
	t.check(geometry != null, "map_geometry.json loads")
	if geometry == null:
		return
	var data := GameData.load_from("res://data")

	for region_id in data.regions:
		t.check(geometry.cells.has(region_id), "territory exists for " + region_id)
		var world := Vector2(
			float(data.regions[region_id]["position"]["x"]),
			float(data.regions[region_id]["position"]["y"])) * MapView.WORLD_SCALE
		t.check_eq(geometry.region_at_world(world), region_id,
			"the position of %s lies in its own territory" % region_id)
		t.check(not geometry.cells[region_id]["fills"].is_empty(),
			"territory of %s decomposes into convex fills" % region_id)

	for region_id in data.regions:
		for neighbor in data.regions[region_id].get("adjacent", []):
			t.check(not geometry.edge_path(region_id, String(neighbor)).is_empty(),
				"road exists %s - %s" % [region_id, neighbor])

	t.check(geometry.landmasses.size() >= 2, "a mainland and islands")
	for mass in geometry.landmasses:
		t.check(not (mass["fills"] as Array).is_empty(),
			"every coastline ring decomposes into land fills")
	t.check(geometry.world_rect.size.x > 100.0, "world bounds cover the map")
	t.check_eq(geometry.region_at_world(Vector2(-4000, -4000)), "", "open ocean is nobody's")

	# edge_path is direction-aware: b->a returns the reversed polyline.
	var sample_region := ""
	var sample_neighbor := ""
	var region_ids: Array = data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		var adjacent: Array = data.regions[region_id].get("adjacent", [])
		if not adjacent.is_empty():
			sample_region = region_id
			var sorted_adjacent := adjacent.duplicate()
			sorted_adjacent.sort()
			sample_neighbor = String(sorted_adjacent[0])
			break
	if sample_region != "":
		var forward := geometry.edge_path(sample_region, sample_neighbor)
		var back := geometry.edge_path(sample_neighbor, sample_region)
		t.check_eq(forward[0], back[back.size() - 1], "a road read backwards is reversed")
