extends RefCounted

func _layout() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/roma_city.json"))

func test_building_clicks_use_authored_approaches_even_from_roofs(t) -> void:
	var layout := _layout()
	for id in ["tavern", "barracks", "curia"]:
		var result := RomaCityNavigation.destination(layout, Vector3(99, 20, 99), "", id)
		var site: Dictionary = {}
		for candidate in layout.sites:
			if str(candidate.id) == id:
				site = candidate
		t.check(result.ok, id + " can be approached")
		t.check_eq(result.position, Vector3(site.approach[0], 0, site.approach[1]), id + " roof resolves to street approach")

func test_houses_land_outside_the_front_door_and_unknown_ids_refuse(t) -> void:
	var layout := _layout()
	var house := RomaCityNavigation.destination(layout, Vector3(-20, 8, 41), "", "house_west_0_0")
	t.check(house.ok, "residential frontage can be approached")
	t.check_near(house.position.x, -20, 0.00001, "frontage aligns with door")
	t.check(house.position.z > 48.5, "landing is outside the solid house")
	t.check(not RomaCityNavigation.destination(layout, Vector3.ZERO, "missing_site").ok, "invalid site does not silently move to a different place")
	t.check(not RomaCityNavigation.destination(layout, Vector3.ZERO, "", "missing_building").ok, "invalid building does not silently move to a different place")

func test_wall_boundary_and_nonfinite_points_are_rejected_without_clamping(t) -> void:
	var layout := _layout()
	t.check(RomaCityNavigation.inside_city(layout, Vector3(0, 0, 45), 0.3), "arrival street is inside enclosed city")
	for point in [Vector3(80, 0, 0), Vector3(0, 0, -80), Vector3(10000, 0, 10000), Vector3(INF, 0, 0), Vector3(NAN, 0, 0)]:
		t.check(not RomaCityNavigation.inside_city(layout, point, 0.3), "outside or invalid point is rejected")
	t.check(not RomaCityNavigation.destination(layout, Vector3(NAN, 0, 0)).ok, "NaN cannot enter collision queries")
	var ground := RomaCityNavigation.destination(layout, Vector3(3, 17, 45))
	t.check_eq(ground.position, Vector3(3, 0, 45), "surface height is never interpreted as a roof landing")

func test_unavailable_world_fails_safely(t) -> void:
	var result := RomaCityNavigation.landing(null, null, Vector3.ZERO)
	t.check(not result.ok, "no movement while world is unavailable")
	t.check_eq(result.reason, "jump_unavailable", "stable localized refusal key")
	t.check(not RomaCityNavigation.pick(null, null, Vector2.ZERO, null).hit, "no stale selection during scene changes")
