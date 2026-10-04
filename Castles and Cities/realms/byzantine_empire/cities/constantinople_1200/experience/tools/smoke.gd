extends SceneTree
## Headless release gate for the actual standalone scene, geometry and editor.
## Run: godot --headless --path <experience> --script res://tools/smoke.gd
## All persistence probes use a unique /tmp folder, never the user's variant.

var _app: Node3D
var _checks := 0
var _failures: Array[String] = []
var _temporary_dir := ""
var _finished := false


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: " + description)


func _run() -> void:
	var scene = load("res://main.tscn")
	if not scene is PackedScene:
		_check(false, "main.tscn loads as the real standalone scene")
		_finish()
		return
	_app = scene.instantiate()
	root.add_child(_app)
	var watchdog := create_timer(240.0)
	watchdog.timeout.connect(_timeout)
	await _app.city_ready
	_check(bool(_app.ready_for_capture), "city reports readiness after synchronous geometry and UI setup")
	_check(_app.world != null and _app.camera != null, "actual scene owns world and camera")
	if _app.world == null or _app.camera == null:
		_finish()
		return
	var input_snapshot := var_to_bytes(_app.data)
	_test_world()
	_test_geometry()
	load("res://tools/architecture_checks.gd").run(_app.world, _check)
	_test_reservoir_ground()
	await _test_camera_and_stages()
	await _test_editor()
	_check(var_to_bytes(_app.data) == input_snapshot, "camera, stages and editor leave historical source data unchanged")
	_finish()


func _test_world() -> void:
	var stats: Dictionary = _app.world.stats
	_check(int(stats.get("landmark_count", 0)) == _app.data.get("landmarks", []).size(), "every configured landmark has a scene assembly")
	_check(int(stats.get("building_count", 0)) > 1000, "city has populated urban wards, not only landmark proxies")
	_check(int(stats.get("building_count", 0)) <= int(_app.data.site.generation.max_buildings), "generated urban population respects the configured geometry budget")
	_check(int(stats.get("tree_count", 0)) > 0 and int(stats.get("wall_towers", 0)) > 0 and int(stats.get("road_segments", 0)) > 0, "vegetation, defenses and circulation are assembled")
	_check(_app.world.landmark_nodes.size() == _app.data.landmarks.size(), "landmark picking/index references every assembly")
	for item: Dictionary in _app.data.landmarks:
		var node: Node3D = _app.world.landmark_nodes.get(str(item.id))
		_check(node != null and node.is_inside_tree(), "landmark is attached: " + str(item.id))
		if node == null:
			continue
		_check(_transform_finite(node.global_transform), "landmark transform is finite: " + str(item.id))
		_check(node.has_meta("interior_anchor") and node.get_meta("interior_anchor") is Vector3, "landmark has an addressable inspection anchor: " + str(item.id))
	var materials: Dictionary = _app.world.materials
	_check(materials.has("stone") and materials.has("roof") and materials.has("water"), "architecture and water material families are present")
	for key in materials:
		var material = materials[key]
		_check(material is ShaderMaterial and material.shader != null and not material.shader.code.is_empty(), "procedural material has shader source: " + str(key))
		if material is ShaderMaterial:
			var tint = material.get_shader_parameter("tint")
			if tint is Color:
				_check(is_finite(tint.r) and is_finite(tint.g) and is_finite(tint.b) and is_finite(tint.a), "material tint is finite: " + str(key))


func _test_geometry() -> void:
	var mesh_nodes := 0
	var batches := 0
	var sampled_vertices := 0
	var collision_shapes := 0
	var mesh_ids := {}
	var stack: Array[Node] = [_app.world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is CollisionShape3D:
			collision_shapes += 1
			_check(node.shape != null and _transform_finite(node.transform), "architectural collision has a finite transform and shape")
		var mesh: Mesh = null
		if node is MeshInstance3D:
			mesh_nodes += 1
			mesh = node.mesh
		elif node is MultiMeshInstance3D:
			batches += 1
			var multimesh: MultiMesh = node.multimesh
			_check(multimesh != null and multimesh.instance_count > 0, "instanced urban batch has actual instances")
			if multimesh == null:
				continue
			mesh = multimesh.mesh
			var finite_transforms := true
			for index in [0, multimesh.instance_count / 2, multimesh.instance_count - 1]:
				finite_transforms = finite_transforms and _transform_finite(multimesh.get_instance_transform(int(index)))
			_check(finite_transforms, "representative instance transforms are finite")
		if mesh == null or mesh_ids.has(mesh.get_instance_id()):
			continue
		mesh_ids[mesh.get_instance_id()] = true
		_check(mesh.get_surface_count() > 0, "generated mesh contains geometry surfaces")
		var bounds := mesh.get_aabb()
		_check(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length() > 0.0, "generated mesh bounds are finite and nonempty")
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				_check(false, "mesh surface exposes its generated vertex arrays")
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var stride := maxi(1, vertices.size() / 240)
			var finite := true
			for index in range(0, vertices.size(), stride):
				finite = finite and vertices[index].is_finite()
				sampled_vertices += 1
				if not normals.is_empty():
					finite = finite and normals[index].is_finite()
			_check(vertices.size() >= 3 and finite, "representative surface vertices and normals are finite")
	_check(mesh_nodes > 30 and batches > 0, "scene includes distinct architecture and batched city geometry")
	_check(collision_shapes > 100, "landmark architecture includes structural collision, not just visual shells")
	_check(sampled_vertices > 1000, "finite-geometry checks cover substantial assembled geometry")
	print("GEOMETRY: %d mesh nodes, %d batches, %d unique meshes, %d sampled vertices, %d collision shapes" % [mesh_nodes, batches, mesh_ids.size(), sampled_vertices, collision_shapes])


func _test_reservoir_ground() -> void:
	# Check the assembled surfaces, not the clipping helper's returned polygons.
	# A coarse missing terrain cell can leave the interior clear and still expose
	# the ocean outside a basin, so exclusion and surrounding coverage both matter.
	var basins: Array[Dictionary] = []
	for item: Dictionary in _app.data.landmarks:
		if str(item.kind) != "cistern":
			continue
		var half := Vector2(float(item.dimensions.width_m), float(item.dimensions.depth_m)) * 0.5
		var node: Node3D = _app.world.landmark_nodes[item.id]
		var radius := half.length() + 12.0
		var center := Vector2(node.global_position.x, node.global_position.z)
		basins.append({"id": str(item.id), "half": half, "inverse": node.global_transform.affine_inverse(), "bounds": Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), "terrain": [], "road": []})
	_check(basins.size() == 4, "reservoir surface regression covers the four authored basins")
	# These two scene branches contain the terrain and arterial/local roads.
	# Avoid traversing millions of architectural and instanced urban vertices.
	var candidates: Array[Node] = []
	candidates.append_array(_app.world.get_children())
	candidates.append_array(_app.world.urban.get_children())
	for candidate: Node in candidates:
		if not candidate is MeshInstance3D or candidate.mesh == null:
			continue
		var is_terrain := str(candidate.name) == "HistoricPeninsulaInterpretiveRelief"
		for surface in range(candidate.mesh.get_surface_count()):
			var is_road: bool = candidate.mesh.surface_get_material(surface) == _app.world.materials.road
			if not is_terrain and not is_road:
				continue
			var arrays: Array = candidate.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for index in range(0, count, 3):
				var points := PackedVector3Array()
				for offset in range(3):
					var vertex: Vector3 = vertices[indices[index + offset] if not indices.is_empty() else index + offset]
					points.append(candidate.global_transform * vertex)
				var bounds := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
				bounds = bounds.expand(Vector2(points[1].x, points[1].z)).expand(Vector2(points[2].x, points[2].z))
				for basin: Dictionary in basins:
					if not bounds.intersects(basin.bounds):
						continue
					var local := PackedVector2Array()
					for point: Vector3 in points:
						var p: Vector3 = basin.inverse * point
						local.append(Vector2(p.x, p.z))
					basin["terrain" if is_terrain else "road"].append(local)
	for basin: Dictionary in basins:
		var half: Vector2 = basin.half
		# A small inset tolerates triangulation rounding at the masonry boundary.
		var inner := half - Vector2.ONE * 0.25
		var interior := PackedVector2Array([Vector2(-inner.x, -inner.y), Vector2(inner.x, -inner.y), Vector2(inner.x, inner.y), Vector2(-inner.x, inner.y)])
		for kind: String in ["terrain", "road"]:
			var triangles: Array = basin[kind]
			_check(not triangles.is_empty(), "%s has nearby %s geometry to inspect" % [basin.id, kind])
			var encroaching := 0
			for triangle: PackedVector2Array in triangles:
				for overlap: PackedVector2Array in Geometry2D.intersect_polygons(triangle, interior):
					var twice_area := 0.0
					for index in range(overlap.size()):
						twice_area += overlap[index].cross(overlap[(index + 1) % overlap.size()])
					if absf(twice_area) > 0.02:
						encroaching += 1
			_check(encroaching == 0, "%s %s triangles leave the reservoir interior clear (%d overlaps)" % [basin.id, kind, encroaching])
		var missing := 0
		for fraction in [-0.9, -0.6, -0.3, 0.0, 0.3, 0.6, 0.9]:
			for sample: Vector2 in [Vector2(-half.x - 0.75, half.y * fraction), Vector2(half.x + 0.75, half.y * fraction), Vector2(half.x * fraction, -half.y - 0.75), Vector2(half.x * fraction, half.y + 0.75)]:
				var covered := false
				for triangle: PackedVector2Array in basin.terrain:
					if Geometry2D.is_point_in_polygon(sample, triangle):
						covered = true
						break
				if not covered:
					missing += 1
		_check(missing == 0, "%s has continuous terrain immediately outside all four basin edges (%d gaps of 28 samples)" % [basin.id, missing])
	print("RESERVOIR GROUND: %d basins checked for terrain/road exclusion and edge coverage" % basins.size())


func _test_camera_and_stages() -> void:
	_app.focus_landmark("hagia_sophia")
	_check(_app.camera.position.is_finite() and _transform_finite(_app.camera.transform), "landmark focus produces a finite camera")
	_app.set_camera_view(Vector3(0, 20, 0), 150.0, 30.0, 25.0)
	var first_camera: Transform3D = _app.camera.transform
	_app.set_camera_view(Vector3(0, 20, 0), 150.0, 30.0, 25.0)
	_check(first_camera.is_equal_approx(_app.camera.transform), "exact camera helper is repeatable")
	_app.set_daytime(7.0)
	_app.set_daytime(18.0)
	_check(is_finite(float(_app.get("_daytime"))), "daylight inspection stays finite across the supported range")
	_app.interior_view("hagia_sophia")
	var cathedral: Node3D = _app.world.landmark_nodes.hagia_sophia
	_check(_app.camera.position.distance_to(cathedral.to_global(cathedral.get_meta("interior_anchor"))) < 0.1, "interior control enters the actual architectural anchor")
	var underground_id := ""
	for item: Dictionary in _app.data.landmarks:
		if str(item.kind) == "cistern" and float(item.dimensions.get("underground", 0)) > 0.5:
			underground_id = str(item.id)
			break
	_check(not underground_id.is_empty(), "data supplies a covered reservoir inspection target")
	if not underground_id.is_empty():
		_app.focus_landmark(underground_id)
		var caps: Array = _app.world.get("_cutaway_caps")
		_check(not caps.is_empty(), "underground reservoirs have covering geometry")
		var hidden := true
		for cap in caps:
			hidden = hidden and not cap.visible
		_check(hidden, "covered-reservoir focus exposes the cutaway")
		_app.interior_view(underground_id)
		var reservoir: Node3D = _app.world.landmark_nodes[underground_id]
		_check(_app.camera.position.y < reservoir.global_position.y, "underground inspection camera remains below ground")
		if reservoir.has_meta("enclosure_node"):
			var roof: Node3D = reservoir.get_node(reservoir.get_meta("enclosure_node"))
			_check(roof.visible, "interior inspection restores the reservoir's enclosing roof")
		_app.focus_landmark("hagia_sophia")
		var restored := true
		for cap in caps:
			restored = restored and cap.visible
		_check(restored, "leaving reservoir inspection restores historical covering ground")
	var baseline: Dictionary = _app.world.get("_layout").duplicate(true)
	var reference_id := str(_app.data.stages[0].id)
	for stage: Dictionary in _app.data.stages:
		if str(stage.id) == reference_id:
			continue
		_app.set_stage(str(stage.id))
		await process_frame
		var expanded: Dictionary = _app.world.get("_layout")
		var objects := {}
		for item: Dictionary in expanded.buildings:
			objects[item.id] = item
		var retained := true
		for item: Dictionary in baseline.buildings:
			retained = retained and objects.has(item.id) and objects[item.id] == item
		_check(retained, "creative growth retains reference building identities and geometry: " + str(stage.id))
		_check(expanded.buildings.size() >= baseline.buildings.size(), "creative growth adds or retains urban plots: " + str(stage.id))
	_app.set_stage(reference_id)
	await process_frame
	_check(_app.world.get("_layout") == baseline, "returning to the reference regenerates the identical city layout")
	_app.set_daytime(15.0)
	_app.home_view()


func _test_editor() -> void:
	_temporary_dir = "/tmp/constantinople-smoke-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(DirAccess.make_dir_recursive_absolute(_temporary_dir) == OK, "create unique external persistence probe folder")
	var variant_path := _temporary_dir + "/creative_variant.json"
	_app.set("_variant_path", variant_path)
	var original := {"schema_version": 1, "city_id": str(_app.data.id), "historical_status": "creative", "objects": [{"id": "design_000002", "kind": "house", "position_m": [15, 20], "rotation_deg": -15.0, "scale": 4.0}]}
	var normalized: Dictionary = _app.validate_variant(original)
	_check(normalized.valid and normalized.clamped, "valid variant normalizes bounded design controls")
	_check(float(normalized.objects[0].scale) == 3.0 and float(normalized.objects[0].rotation_deg) == 345.0, "scale and rotation clamp without changing source input")
	for key in ["city_id", "historical_status", "schema_version"]:
		var wrong := original.duplicate(true)
		wrong[key] = "incorrect"
		_check(not _app.validate_variant(wrong).valid, "reject wrong variant field: " + key)
	var extra := original.duplicate(true)
	extra["gameplay_binding"] = "roma"
	_check(not _app.validate_variant(extra).valid, "reject unknown top-level and game-binding fields")
	var keys := ["kind", "id", "position_m", "scale", "rotation_deg"]
	var values := ["unknown_kit", "../../escape", [20000000, 0], INF, NAN]
	for index in range(keys.size()):
		var invalid := original.duplicate(true)
		invalid.objects[0][keys[index]] = values[index]
		_check(not _app.validate_variant(invalid).valid, "reject invalid design field: " + str(keys[index]))
	var outside := original.duplicate(true)
	outside.objects[0].position_m = [12000, 12000]
	_check(not _app.validate_variant(outside).valid, "reject finite position outside the actual city polygon")
	var unknown := original.duplicate(true)
	unknown.objects[0].attack_bonus = 10
	_check(not _app.validate_variant(unknown).valid, "reject numerical game stats in a design object")
	var duplicate := original.duplicate(true)
	duplicate.objects.append(duplicate.objects[0].duplicate(true))
	_check(not _app.validate_variant(duplicate).valid, "reject duplicate design IDs")
	var huge := original.duplicate(true)
	for index in range(501):
		huge.objects.append(original.objects[0].duplicate(true))
	_check(not _app.validate_variant(huge).valid, "reject excessive design object counts")
	_check(not _app.validate_variant(null).valid, "reject null payload")
	_check(not _app.load_variant(), "missing variant is reported without replacing the design")
	for index in range(4):
		_check(_app.add_design_object(["house", "workshop", "church", "tower"][index], Vector2(120 + index * 40, 100)), "creative kit generates a real scene object: " + str(index))
	await process_frame
	_check(_app.world.additions.get_child_count() == 4, "all four kit objects appear in the actual creative scene branch")
	_check(not _app.add_design_object("house", Vector2(12000, 12000)), "interactive placement rejects outside terrain")
	_app.call("_on_scale_changed", 1.5)
	_check(float(_app.design_objects[-1].scale) == 1.5 and _app.world.additions.get_child(3).scale.is_equal_approx(Vector3.ONE * 1.5), "scale control updates both design data and rendered object")
	_app.undo_edit()
	_check(float(_app.design_objects[-1].scale) == 1.0, "undo restores pre-scale geometry")
	_app.set("_selected_design", str(_app.design_objects[-1].id))
	_app.rotate_selected()
	_check(float(_app.design_objects[-1].rotation_deg) == 15.0, "rotate changes the selected design object")
	_app.undo_edit()
	_check(float(_app.design_objects[-1].rotation_deg) == 0.0, "undo restores pre-rotation geometry")
	_app.set("_selected_design", str(_app.design_objects[-1].id))
	_app.delete_selected()
	_check(_app.design_objects.size() == 3 and _app.world.additions.get_child_count() == 3, "delete removes the selected addition from data and scene")
	_app.undo_edit()
	_check(_app.design_objects.size() == 4 and _app.world.additions.get_child_count() == 4, "undo restores a deleted addition")
	_check(_app.save_variant(), "save succeeds in the unique QA folder")
	var saved: Array = _app.design_objects.duplicate(true)
	_app.clear_design()
	_check(_app.design_objects.is_empty() and _app.world.additions.get_child_count() == 0, "clear removes only the creative branch")
	_check(_app.world.landmark_nodes.size() == _app.data.landmarks.size(), "clear retains historical landmark assemblies")
	_check(_app.load_variant() and _app.design_objects == saved, "save/load round trip preserves design geometry")
	_write_text(variant_path, JSON.stringify(original))
	_check(_app.load_variant(), "load accepts a valid noncontiguous design ID")
	_check(_app.add_design_object("workshop", Vector2(170, 120)), "placement finds the first unused ID after load")
	_check(_app.add_design_object("church", Vector2(210, 120)), "subsequent placement skips an existing higher ID")
	var ids := {}
	for item: Dictionary in _app.design_objects:
		ids[item.id] = true
	_check(ids.size() == _app.design_objects.size(), "loaded and newly authored IDs remain unique")
	var before: Array = _app.design_objects.duplicate(true)
	_write_text(variant_path, "{broken")
	_check(not _app.load_variant(), "malformed save is rejected without engine errors")
	_check(_app.design_objects == before, "rejected load preserves the current design")
	_app.set("_variant_path", _temporary_dir + "/missing-parent/variant.json")
	_check(not _app.save_variant(), "unwritable save path reports failure")
	_app.set("_variant_path", variant_path)
	_app.clear_design()
	await process_frame
	_check(_app.world.additions.get_child_count() == 0, "editor cleanup releases creative scene objects")
	_cleanup_temporary_files()


func _write_text(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "open isolated probe file")
	if file != null:
		file.store_string(contents)
		file.close()


func _transform_finite(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite()


func _cleanup_temporary_files() -> void:
	if _temporary_dir.is_empty():
		return
	for name in ["creative_variant.json", "creative_variant.json.tmp"]:
		var path: String = _temporary_dir + "/" + str(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_temporary_dir)


func _timeout() -> void:
	if not _finished:
		_check(false, "standalone scene and release probes complete within 240 seconds")
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_temporary_files()
	print("CONSTANTINOPLE SMOKE: %d checks, %d failures" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("CITY SMOKE PASS")
	if is_instance_valid(_app):
		_app.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
