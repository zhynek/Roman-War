extends RefCounted
## The committed map geometry must load headlessly, cover every authored
## region, agree with the region anchors it was generated from, and carry a
## road for every land adjacency. The fixture world has no geometry and must
## say so, because MapView falls back to nearest-anchor picking there.

const SCALE := 14.0  # MapView.WORLD_SCALE


func test_geometry_loads_and_agrees_with_regions(t) -> void:
	var data := GameData.load_from("res://data")
	var geometry := MapGeometry.load_for(data, SCALE)
	t.check(geometry != null, "map_geometry.json loads for the authored world")
	if geometry == null:
		return

	var region_ids: Array = data.regions.keys()
	region_ids.sort()
	var mismatches: Array = []
	for region_id in region_ids:
		var position: Dictionary = data.regions[region_id]["position"]
		var world := Vector2(float(position["x"]), float(position["y"])) * SCALE
		if geometry.region_at_world(world) != region_id:
			mismatches.append(region_id)
	t.check_eq(mismatches, [], "every region token picks its own cell")

	t.check_eq(geometry.region_at_world(Vector2(-9999999, -9999999)), "", "open ocean picks nothing")


func test_every_adjacency_has_a_road(t) -> void:
	var data := GameData.load_from("res://data")
	var geometry := MapGeometry.load_for(data, SCALE)
	if geometry == null:
		t.check(false, "geometry must load")
		return
	var missing: Array = []
	var region_ids: Array = data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		for neighbor in data.regions[region_id].get("adjacent", []):
			if geometry.edge_path(region_id, neighbor).size() < 2:
				missing.append(region_id + "-" + String(neighbor))
	t.check_eq(missing, [], "every land adjacency carries a road path")


func test_landmasses_triangulate_for_drawing(t) -> void:
	var data := GameData.load_from("res://data")
	var geometry := MapGeometry.load_for(data, SCALE)
	if geometry == null:
		t.check(false, "geometry must load")
		return
	t.check(geometry.landmasses.size() >= 3, "islands and mainland present")
	for landmass in geometry.landmasses:
		t.check(not (landmass["tris"] as Array).is_empty(), "every landmass outline ear-clips into a fill")
	var missing_fill := 0
	for region_id in geometry.cells:
		if (geometry.cells[region_id]["tris"] as Array).is_empty():
			missing_fill += 1
	t.check_eq(missing_fill, 0, "every cell triangulates for its tint fill")


func test_fixture_world_has_no_geometry(t) -> void:
	var data := Fixtures.data()
	t.check(MapGeometry.load_for(data, SCALE) == null,
		"fixture regions are not covered, so the map falls back to tokens")
