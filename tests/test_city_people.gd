extends RefCounted

func _layout() -> Dictionary:
	return {"citizen_routes": [{"id": "walk", "role": "citizen", "count": 1,
		"points": [[20, 0], [25, 0], [25, 5]], "loop": false}],
		"people_anchors": [
			{"id": "watch", "role": "guard", "position": [0, 0]},
			{"id": "extra", "role": "guard", "status_group": "patrol_extra", "position": [8, 0]},
			{"id": "guest", "role": "patron", "position": [12, 0]},
			{"id": "seller", "role": "merchant", "position": [16, 0]},
			{"id": "protest", "role": "protester", "position": [30, 0], "count": 4},
			{"id": "bread", "role": "grain_queue", "position": [40, 0]}]}

func _active(population: RomaCityPeople, role: String, group: String = "") -> int:
	var count := 0
	for person in population.people:
		if person.role == role and bool(person.active) and (group == "" or person.status_group == group):
			count += 1
	return count

func test_city_population_policy_changes_and_picking_are_visible_immediately(t) -> void:
	var population := RomaCityPeople.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(population)
	population.build(_layout())
	var calm := {"unrest": 10.0, "mood": "calm", "grain_days": 0,
		"policies": {"patrols": "normal", "taverns": "open"}}
	population.apply_status(calm)
	t.check_eq(_active(population, "guard"), 1, "ordinary watch is present without additional patrols")
	t.check_eq(_active(population, "patron"), 1, "open tavern has visible patrons")
	t.check_eq(_active(population, "protester"), 0, "calm streets have no protesting crowd")
	t.check_eq(_active(population, "grain_queue"), 0, "no distribution queue appears without funded grain")
	t.check(population.nearest_person(Vector3(8, 0, 0), 0.5).is_empty(), "hidden patrol cannot be picked")
	var crisis := {"unrest": 95.0, "mood": "rebellious", "grain_days": 3,
		"policies": {"patrols": "heavy", "taverns": "closed"}}
	population.apply_status(crisis)
	t.check_eq(_active(population, "guard"), 2, "heavy patrol adds guards without replacing the ordinary watch")
	t.check_eq(_active(population, "patron"), 0, "closing the tavern clears its patrons")
	t.check_eq(_active(population, "merchant"), 1, "closure does not erase unrelated trade")
	t.check_eq(_active(population, "protester"), 4, "severe unrest produces the full authored protest group")
	t.check_eq(_active(population, "grain_queue"), 1, "funded grain makes the distribution line visible")
	var picked := population.nearest_person(Vector3(8, 0, 0), 0.5)
	t.check_eq(picked.get("id", ""), "extra_00", "new patrol is immediately located at its authored anchor")
	t.check_eq(picked.get("text_key", ""), "city.dialogue.guard.rebellious", "dialogue reports the current mood with a content key")
	t.check(population.nearest_person(Vector3(12, 0, 0), 0.5).is_empty(), "closed tavern patrons are no longer interactive")
	population.free()

func test_city_animation_never_changes_campaign_status_or_layout(t) -> void:
	var game := Game.new_campaign("senate", 42, "medium", "long", false)
	RomaCityRules.ensure_city(game.data, game.state, "latium")
	var status: Dictionary = game.city_status("latium")
	var layout := _layout()
	var before_state := JSON.stringify(game.state)
	var before_status := JSON.stringify(status)
	var before_layout := JSON.stringify(layout)
	var population := RomaCityPeople.new()
	population.build(layout)
	population.apply_status(status)
	var first_position: Vector3 = population.people[0].node.position
	for frame in range(60):
		population._process(1.0 / 30.0)
	t.check(not first_position.is_equal_approx(population.people[0].node.position), "the presentation actually walks while the campaign remains unchanged")
	t.check_eq(JSON.stringify(game.state), before_state, "citizen frames cannot spend money, advance days, move forces, or draw campaign RNG")
	t.check_eq(JSON.stringify(status), before_status, "presentation does not mutate its source civic status")
	t.check_eq(JSON.stringify(layout), before_layout, "path construction does not mutate authored layout arrays")
	var walking: Node3D = population.people[0].node
	t.check_near(walking.position.z, 0.0, 0.0001, "walking follows the first authored street segment")
	t.check(walking.position.x > 20.0 and walking.position.x < 25.0, "walking stays within segment endpoints")
	population.free()

func test_city_authored_routes_clear_building_footprints(t) -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/roma_city.json"))
	var population := RomaCityPeople.new()
	var conflicts: Array[String] = []
	for route in layout.get("citizen_routes", []):
		var path := population._path(route.points, bool(route.get("loop", true)))
		var points: Array = path.get("vertices", [])
		for index in range(points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			var steps := maxi(1, ceili(a.distance_to(b) * 4))
			for step in range(steps + 1):
				var sample := a.lerp(b, float(step) / steps)
				for building in layout.get("buildings", []):
					var center := Vector2(float(building.position[0]), float(building.position[1]))
					var footprint := Vector2(float(building.size[0]), float(building.size[1]))
					if Rect2(center - footprint * 0.5, footprint).grow(0.35).has_point(Vector2(sample.x, sample.z)):
						var conflict := "%s / %s" % [route.id, building.id]
						if not conflicts.has(conflict):
							conflicts.append(conflict)
	t.check(conflicts.is_empty(), "authored walking loops and their closing segments clear solid buildings: %s" % str(conflicts))
	var retrace := population._path([[0, 0], [5, 0], [5, 5]], false)
	t.check_eq(retrace.vertices.size(), 5, "an open route retraces each authored leg")
	t.check_eq(retrace.vertices[3], Vector3(5, 0.025, 0), "the return leg never cuts diagonally through a block")
	population.free()
