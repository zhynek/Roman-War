extends RefCounted

func test_city_uses_only_its_report_and_does_not_mutate_it(t) -> void:
	var data := GameData.load_from()
	var report := {"owner": "julii", "level": "minor_city", "population": 6500, "buildings": ["roman_gov_4", "roman_walls_3", "field_farms_2"], "turn": 3}
	var before := JSON.stringify(report)
	var first := CampaignCityModel.plan(data, "etruria", report)
	var again := CampaignCityModel.plan(data, "etruria", report)
	t.check_eq(first, again, "observed architecture has stable hashed wards")
	t.check_eq(JSON.stringify(report), before, "model derivation preserves its detached report")
	t.check_eq(CampaignCityModel.plan(data, "etruria", {}), {}, "geographic knowledge alone does not invent observed architecture")
	t.check_eq(int(first.kinds.walls), 3, "the observed completed wall tier selects the fortification")
	t.check(not first.kinds.has("barracks"), "unreported construction cannot appear")

func test_city_growth_keeps_existing_blocks_and_adds_outer_wards(t) -> void:
	var data := GameData.load_from()
	var report := {"owner": "julii", "level": "town", "population": 1000, "buildings": []}
	var small := CampaignCityModel.plan(data, "etruria", report)
	report.level = "huge_city"
	report.population = 30000
	var large := CampaignCityModel.plan(data, "etruria", report)
	t.check(float(large.radius) > float(small.radius), "settlement advancement expands the footprint")
	t.check(large.houses.size() > small.houses.size() * 2, "a major city contains visibly more housing")
	var large_positions := {}
	for house in large.houses:
		large_positions[house.at] = true
	for house in small.houses:
		t.check(large_positions.has(house.at), "growth preserves the original street blocks")

func test_city_reports_refresh_geometry_only_when_appearance_changes(t) -> void:
	var report := {"owner": "julii", "level": "minor_city", "population": 6500, "buildings": ["roman_gov_4", "roman_walls_3"], "turn": 3}
	var first := CampaignCityModel.appearance_key(report)
	report.turn = 9
	report.buildings.reverse()
	t.check_eq(CampaignCityModel.appearance_key(report), first, "new report dates and building order do not rebuild retained models")
	report.buildings.append("roman_brk_2")
	t.check(CampaignCityModel.appearance_key(report) != first, "completed construction invalidates the model")
	var after_building := CampaignCityModel.appearance_key(report)
	report.watchpost = {"owner": "julii", "level": 1}
	t.check(CampaignCityModel.appearance_key(report) != after_building, "an observed watchpost changes the same report-based model")

func test_city_model_has_finite_bounded_geometry_at_both_detail_levels(t) -> void:
	var data := GameData.load_from()
	var report := {"owner": "julii", "level": "large_city", "population": 15000, "buildings": ["roman_gov_5", "roman_walls_4", "roman_brk_3", "roman_jupiter_3", "field_farms_3", "civic_mkt_2"], "watchpost": {"owner": "julii", "level": 1}}
	var spec := CampaignCityModel.plan(data, "latium", report)
	var ground := func(point: Vector2) -> Vector3: return Vector3(point.x, 0.95, point.y)
	for detailed in [false, true]:
		var mesh := CampaignCityModel.build(spec, Vector2.ZERO, ground, detailed)
		t.check(mesh != null and mesh.get_surface_count() == 1, "each detail layer is one batched procedural mesh")
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var valid := true
		for vertex in vertices:
			if not vertex.is_finite() or absf(vertex.x) > 24 or absf(vertex.z) > 24 or vertex.y < 0 or vertex.y > 8:
				valid = false
				break
		t.check(valid, "city geometry stays finite inside its known clearing")
		t.check(vertices.size() < 120000, "each city detail mesh has a bounded vertex budget")

func test_city_approaches_keep_houses_clear_and_open_the_wall(t) -> void:
	var data := GameData.load_from()
	var direction := Vector2(0.7, -1).normalized()
	var approaches: Array = [PackedVector2Array([Vector2.ZERO, direction * 30])]
	var report := {"owner": "julii", "level": "large_city", "population": 15000, "buildings": ["roman_walls_4"]}
	var spec := CampaignCityModel.plan(data, "etruria", report, approaches)
	for house in spec.houses:
		t.check(CampaignCityModel.path_distance(house.at, approaches) >= 2.0, "housing leaves the actual geographic road corridor clear")
	var gate := false
	for angle in CampaignCityModel.gate_angles(approaches, float(spec.radius)):
		if absf(angle_difference(float(angle), direction.angle())) < 0.001:
			gate = true
	t.check(gate, "the wall has a gate on the actual angled approach")
