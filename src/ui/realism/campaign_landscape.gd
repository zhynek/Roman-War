class_name CampaignLandscape
extends SubViewportContainer
## Live campaign renderer. The MapView owns commands and visual march positions;
## this surface only projects its filtered caches, with the identical X/Z map
## coordinates and an orthographic camera. No simulation or hidden roster reads.
const PITCH := 0.9599310886 # 55-degree campaign camera
var view: MapView
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var regions := {}
var armies := {}
var settlements := {}
var settlement_material: ShaderMaterial
var routes: Node3D
var noise := FastNoiseLite.new()
var tree_meshes: Array = []
var infantry_meshes := {}
var _frame := Rect2()
var bridges: Array = []
var water_material: ShaderMaterial
var terrain_sources: Array = []
var crossing_sites: Array = []
var track_grid := {}
var _ground_cache := {}
var _cache_ground := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	noise.seed = 270
	noise.frequency = 0.016
	noise.fractal_octaves = 3
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.rotation = Vector3(-PITCH, 0, 0)
	camera.near = 1
	camera.far = 1800
	world.add_child(camera)
	var environment := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = UiStyle.BG_DARK
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("#a7bcc1")
	atmosphere.ambient_light_energy = 0.85
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	atmosphere.tonemap_exposure = 1.05
	environment.environment = atmosphere
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-39, -33, 0)
	sun.light_color = Color("#ffedc7")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1200
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.025
	world.add_child(sun)
	water_material = ShaderMaterial.new()
	water_material.shader = preload("res://src/ui/realism/water.gdshader")
	settlement_material = _vertex_material()
	for id in view.game.data.regions:
		var r: Dictionary = view.game.data.regions[id]
		terrain_sources.append({"at": view.world_pos(r), "relief": float(view.game.data.terrain_content["terrains"][r["terrain"]]["relief"])})
	for key in view.geometry.edges:
		var ends := String(key).split("|")
		if TerrainRules.land_connection(view.game.data, ends[0], ends[1], view.game.state):
			var track: PackedVector2Array = view.geometry.edges[key]
			for j in range(track.size() - 1):
				var box := Rect2(track[j], Vector2.ZERO).expand(track[j + 1]).grow(16)
				for x in range(floori(box.position.x / 32), floori(box.end.x / 32) + 1):
					for y in range(floori(box.position.y / 32), floori(box.end.y / 32) + 1):
						var cell := Vector2i(x, y)
						if not track_grid.has(cell):
							track_grid[cell] = []
						track_grid[cell].append([track[j], track[j + 1]])
		var kind := TerrainRules.crossing_kind(view.game.data, ends[0], ends[1], view.game.state)
		if kind == "":
			continue
		var path: PackedVector2Array = view.geometry.edges[key]
		var length := 0.0
		for j in range(path.size() - 1):
			length += path[j].distance_to(path[j + 1])
		var sample := MapView.sample_route(path, length * 0.5 + 0.1)
		if kind == "causeway":
			# Place the causeway inside its marsh endpoint, not at the arbitrary
			# midpoint of a long province edge that may still be wooded hills.
			var closest := INF
			for j in range(1, 100):
				var candidate := MapView.sample_route(path, length * j / 100.0)
				var id := view.geometry.region_at_world(candidate["position"])
				if view.game.data.regions.get(id, {}).get("terrain", "") == "marsh" and absf(j - 50) < closest:
					sample = candidate
					closest = absf(j - 50)
		var tangent: Vector2 = sample["direction"]
		crossing_sites.append({"key": key, "kind": kind, "center": sample["position"], "tangent": tangent, "cross": Vector2(-tangent.y, tangent.x)})
	for i in range(3):
		tree_meshes.append(RealismModels.tree(i))
	routes = Node3D.new()
	world.add_child(routes)

func project(point: Vector2) -> Vector2:
	var at := (point + view._camera_offset) * view._zoom
	at.y = (at.y - view.size.y * 0.5) * sin(PITCH) + view.size.y * 0.5 - _troop_ground(point).y * cos(PITCH) * view._zoom
	return at

func unproject(point: Vector2) -> Vector2:
	var base := Vector2(point.x, (point.y - view.size.y * 0.5) / sin(PITCH) + view.size.y * 0.5) / view._zoom - view._camera_offset
	var at := base
	for i in range(8):
		at.y = base.y + ground(at).y / tan(PITCH)
	return at

func pick_region(point: Vector2) -> String:
	var base := Vector2(point.x, (point.y - view.size.y * 0.5) / sin(PITCH) + view.size.y * 0.5) / view._zoom - view._camera_offset
	# Traverse from the eye toward the ground. The first height-field crossing
	# is visible; a farther province cannot be picked through an intervening ridge.
	var upper := 100.0
	var previous := upper
	for i in range(201):
		var altitude := upper - i * 0.5
		var at := base + Vector2(0, altitude / tan(PITCH))
		var region := view.geometry.region_at_world(at)
		if not view.known_cache.has(region):
			previous = altitude
			continue
		if altitude <= ground(at, region).y:
			var low := altitude
			var high := previous
			for j in range(8):
				var middle := (low + high) * 0.5
				var candidate := base + Vector2(0, middle / tan(PITCH))
				if middle > ground(candidate).y:
					high = middle
				else:
					low = middle
			var hit := base + Vector2(0, (low + high) * 0.5 / tan(PITCH))
			return view.geometry.region_at_world(hit)
		previous = altitude
	return ""

func _sync_camera() -> void:
	var center := -view._camera_offset + view.size / (2 * view._zoom)
	camera.position = Vector3(center.x, 900 * sin(PITCH), center.y + 900 * cos(PITCH))
	camera.size = view.size.y / view._zoom

func ground(point: Vector2, region: String = "") -> Vector3:
	if not _cache_ground:
		return _ground(point, region)
	if not _ground_cache.has(region):
		_ground_cache[region] = {}
	if not _ground_cache[region].has(point):
		_ground_cache[region][point] = _ground(point, region)
	return _ground_cache[region][point]

func _ground(point: Vector2, region: String = "") -> Vector3:
	var id := region if region != "" else view.geometry.region_at_world(point)
	if not view.game.data.regions.has(id):
		return Vector3(point.x, 0.5, point.y)
	var terrain := String(view.game.data.regions[id]["terrain"])
	# A continuous relief field removes cliffs at province borders. Terrain
	# identity still comes from the authored province; roads cut broad valleys.
	var weight := 0.0
	var relief := 0.0
	for source in terrain_sources:
		var w := 1.0 / pow(maxf(point.distance_squared_to(source.at), 64.0), 2.0)
		weight += w
		relief += source.relief * w
	relief /= maxf(weight, 0.00000001)
	var n := noise.get_noise_2d(point.x, point.y)
	var h := 1.0 + pow(clampf(n + 0.55, 0, 1), 2.0) * relief
	# One global corridor field on both sides of every province boundary.
	# Region-local distance tests used to tear the mesh at shared borders.
	var distance_to_track := _track_distance(point, id)
	for source in terrain_sources:
		distance_to_track = minf(distance_to_track, maxf(0, point.distance_to(source.at) - 18.0))
	h = lerpf(0.95, h, smoothstep(2.1, 15.0, distance_to_track))
	for site in crossing_sites:
		if not site.kind in ["river", "bridge"]:
			continue
		var relative: Vector2 = point - site.center
		var across := relative.dot(site.cross)
		var along := relative.dot(site.tangent) - sin(across * 0.13) * 1.1
		if absf(across) < 28:
			h = lerpf(0.30, h, smoothstep(3.0, 6.0, absf(along)))
	return Vector3(point.x, h, point.y)

func sync_state() -> void:
	if not is_node_ready() or view.geometry == null:
		return
	_cache_ground = true
	for id in regions.keys():
		if not view.known_cache.has(id):
			regions[id].queue_free()
			regions.erase(id)
	for id in view.known_cache:
		if view.geometry.cells.has(id) and not regions.has(id):
			_build_region(id)
	_sync_settlements()
	for id in armies.keys():
		if not view.army_visuals.has(id):
			armies[id].node.queue_free()
			armies.erase(id)
	for id in view.army_visuals:
		var looks: Array = view.troop_looks.get(id, [{}])
		var classes: Array = view.army_visuals[id].get("classes", [])
		var key := JSON.stringify(looks) + str(classes)
		if armies.has(id) and armies[id].key == key:
			continue
		if armies.has(id):
			armies[id].node.queue_free()
		var root := Node3D.new()
		world.add_child(root)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://src/ui/realism/soldier.gdshader")
		var groups := {}
		for i in range(24):
			var kind := String(classes[i % classes.size()]) if not classes.is_empty() else "infantry"
			var look: Dictionary = looks[i % looks.size()]
			var tint := Color.html(look.get("tunic", "#8c6b51"))
			var model_key := kind + JSON.stringify(look)
			if not infantry_meshes.has(model_key):
				infantry_meshes[model_key] = RealismUnitModels.build(tint, kind, look)
			if not groups.has(model_key):
				groups[model_key] = {"indices": [], "kind": kind}
			groups[model_key].indices.append(i)
		for model_key in groups:
			var poses: Array[Transform3D] = []
			poses.resize(groups[model_key].indices.size())
			poses.fill(Transform3D.IDENTITY)
			groups[model_key]["node"] = _batch(root, infantry_meshes[model_key], mat, poses)
		armies[id] = {"node": root, "groups": groups, "material": mat, "key": key}

	_build_routes()
	_cache_ground = false
	_ground_cache.clear()
	sync_frame()

func sync_frame() -> void:
	if camera == null or view.size.y < 1:
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible and view.is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if not visible:
		return
	_sync_camera()
	water_material.set_shader_parameter("clock_time", view._visual_clock)
	_frame = Rect2(-view._camera_offset, view.size / view._zoom).grow(40)
	for id in regions:
		regions[id].visible = _frame.intersects(view.geometry.cells[id]["bounds"])
	for id in settlements:
		var entry: Dictionary = settlements[id]
		entry.node.visible = _frame.grow(24).has_point(view.world_pos(view.game.data.regions[id]))
		var close_detail: bool = entry.node.visible and view._zoom >= 7.0
		if close_detail and entry.detail == null:
			var detail_mesh := CampaignCityModel.build(entry.plan, view.world_pos(view.game.data.regions[id]), ground, true)
			if detail_mesh != null:
				entry.detail = _mesh(entry.node, detail_mesh, settlement_material)
		if entry.detail != null:
			entry.detail.visible = close_detail
	for id in armies:
		var node: Node3D = armies[id].node
		var at := view.force_world_position(id)
		node.visible = _frame.has_point(at)
		if not node.visible:
			continue
		var walking := view._marches.has(id)
		var direction: Vector2 = view._marches.get(id, {}).get("direction", Vector2.UP)
		var right := Vector2(-direction.y, direction.x)
		for group in armies[id].groups.values():
			var miniature: MultiMeshInstance3D = group.node
			var scale_by := float(view.army_visuals[id].get("scale", 1.0)) * (0.78 if group.kind in ["elephant", "chariot"] else 1.0)
			var basis := Basis(Vector3.UP, atan2(-direction.x, -direction.y)).scaled(Vector3.ONE * scale_by)
			for j in range(miniature.multimesh.instance_count):
				var i := int(group.indices[j])
				var p := at + right * ((i % 4) - 1.5) * 1.7 + direction * (float(i / 4) - 2.5) * 1.7
				var facing := basis
				if walking:
					var march: Dictionary = view._marches[id]
					var sample := MapView.sample_route(march["points"], float(march["distance"]) - (float(i / 4) - 2.5) * 1.7)
					var heading: Vector2 = sample["direction"]
					p = sample["position"] + Vector2(-heading.y, heading.x) * ((i % 4) - 1.5) * 0.7
					facing = Basis(Vector3.UP, atan2(-heading.x, -heading.y)).scaled(Vector3.ONE * scale_by)
				miniature.multimesh.set_instance_transform(j, Transform3D(facing, _troop_ground(p) + Vector3.UP * 0.05))
		armies[id].material.set_shader_parameter("walking", 1.0 if walking else 0.0)
		armies[id].material.set_shader_parameter("clock_time", view._visual_clock)

func _troop_ground(point: Vector2) -> Vector3:
	var at := ground(point)
	for bridge in bridges:
		var relative: Vector2 = point - bridge.center
		var along := absf(relative.dot(bridge.tangent))
		if along < float(bridge.length) + 4 and absf(relative.dot(bridge.cross)) < 1.5:
			at.y = lerpf(float(bridge.deck), 1.03, clampf((along - float(bridge.length)) / 4, 0, 1))
	return at

func _build_region(id: String) -> void:
	var root := Node3D.new()
	world.add_child(root)
	regions[id] = root
	var region: Dictionary = view.game.data.regions[id]
	var profile: Dictionary = view.game.data.terrain_content["terrains"][region["terrain"]]
	var terrain_material := ShaderMaterial.new()
	terrain_material.shader = preload("res://src/ui/realism/campaign_ground.gdshader")
	terrain_material.set_shader_parameter("ground_color", Color.html(profile.color))
	terrain_material.set_shader_parameter("marsh", region["terrain"] == "marsh")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for polygon in view.geometry.cells[id]["fills"]:
		for i in range(1, polygon.size() - 1):
			_triangle(st, id, polygon[0], polygon[i], polygon[i + 1], 0)
	st.generate_normals()
	_mesh(root, st.commit(), terrain_material)
	var tree_material := ShaderMaterial.new()
	tree_material.shader = preload("res://src/ui/realism/foliage.gdshader")
	var groups: Array = [[], [], []]
	var bounds: Rect2 = view.geometry.cells[id]["bounds"]
	var anchor := view.world_pos(region)
	for i in range(int(profile.trees) * 3):
		var key := id + "/" + str(i)
		var at := bounds.position + bounds.size * Vector2(RealismModels.scatter(key, 0), RealismModels.scatter(key, 1))
		if view.geometry.region_at_world(at) != id or at.distance_to(anchor) < 24:
			continue
		var p := ground(at, id)
		if _track_distance(at, id) < 6.5:
			continue
		var scale_by := 0.65 + RealismModels.scatter(key, 3) * 0.65
		groups[i % 3].append(Transform3D(Basis(Vector3.UP, RealismModels.scatter(key, 2) * TAU).scaled(Vector3.ONE * scale_by), p))
		if groups[0].size() + groups[1].size() + groups[2].size() >= int(profile.trees):
			break
	for i in range(3):
		var poses: Array[Transform3D] = []
		poses.assign(groups[i])
		if not poses.is_empty():
			_batch(root, tree_meshes[i], tree_material, poses)
	# Reeds, scrub and stones break up the banks and forest floor. One mesh
	# per material, deterministic scatter, no individual scene-tree foliage.
	var undergrowth: Array[Transform3D] = []
	var stones := RealismModels.new()
	var pools := RealismModels.new()
	for i in range(700 if region["terrain"] in ["marsh", "forest"] else 180):
		var key := id + "/ground/" + str(i)
		var at := bounds.position + bounds.size * Vector2(RealismModels.scatter(key, 0), RealismModels.scatter(key, 1))
		if view.geometry.region_at_world(at) != id or at.distance_to(anchor) < 24 or _track_distance(at, id) < 2.4:
			continue
		var p := ground(at, id)
		var scale_by := 0.6 + RealismModels.scatter(key, 2) * 1.0
		undergrowth.append(Transform3D(Basis(Vector3.UP, RealismModels.scatter(key, 3) * TAU).scaled(Vector3.ONE * scale_by), p))
		if i % 13 == 0:
			stones.ellipsoid(p, Vector3(0.5, 0.3, 0.7) * scale_by, RealismModels.pigment("#696b5e"))
		if region["terrain"] == "marsh" and i % 11 == 0:
			# Flat, irregular pools, with reeds rooted in their shallow margins.
			for j in range(12):
				var a := Vector3(cos(j * TAU / 12), 0, sin(j * TAU / 12)) * (1.4 + RealismModels.scatter(key, j + 10))
				var b := Vector3(cos((j + 1) * TAU / 12), 0, sin((j + 1) * TAU / 12)) * (1.4 + RealismModels.scatter(key, (j + 1) % 12 + 10))
				p.y = ground(at, id).y + 0.09
				pools.triangle(p, p + a, p + b, Color.WHITE)
	if not undergrowth.is_empty():
		_batch(root, RealismModels.grass(region["terrain"] == "marsh"), tree_material, undergrowth)
	if stones.vertex_count > 0:
		_mesh(root, stones.finish(), _vertex_material())
	if pools.vertex_count > 0:
		_mesh(root, pools.finish(), water_material)

func _track_distance(point: Vector2, id: String) -> float:
	var distance_to_track := INF
	for segment in track_grid.get(Vector2i(floori(point.x / 32), floori(point.y / 32)), []):
		distance_to_track = minf(distance_to_track, point.distance_to(Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])))
	return distance_to_track

func settlement_radius(id: String) -> float:
	return float(settlements.get(id, {}).get("plan", {}).get("radius", 8.0))

func settlement_anchor(id: String) -> Vector3:
	return ground(view.world_pos(view.game.data.regions[id]), id)

func force_contains_point(id: String, point: Vector2) -> bool:
	## Pick the rendered instances, including marching poses and mount size.
	## At architectural zoom a generous campaign-radius circle would swallow
	## streets hundreds of pixels away from any visible soldier.
	if not armies.has(id) or not armies[id].node.visible or viewport.size.x <= 0 or viewport.size.y <= 0:
		return false
	var screen_scale := view.size / Vector2(viewport.size)
	for group in armies[id].groups.values():
		var miniature: MultiMeshInstance3D = group.node
		var mesh_bounds: AABB = miniature.multimesh.mesh.get_aabb()
		for i in range(miniature.multimesh.instance_count):
			var pose := miniature.global_transform * miniature.multimesh.get_instance_transform(i)
			var rectangle := Rect2()
			for corner in range(8):
				var projected := camera.unproject_position(pose * mesh_bounds.get_endpoint(corner)) * screen_scale
				rectangle = Rect2(projected, Vector2.ZERO) if corner == 0 else rectangle.expand(projected)
			if rectangle.grow(3).has_point(point):
				return true
	return false

func _sync_settlements() -> void:
	for id in settlements.keys():
		if not view.known_cache.has(id) or view.settlement_reports.get(id, {}).is_empty():
			settlements[id].node.queue_free()
			settlements.erase(id)
	for id in view.settlement_reports:
		if not view.known_cache.has(id) or not regions.has(id):
			continue
		var report: Dictionary = view.settlement_reports[id]
		var key := CampaignCityModel.appearance_key(report)
		if key == "" or (settlements.has(id) and settlements[id].key == key):
			continue
		if settlements.has(id):
			settlements[id].node.queue_free()
		var approaches: Array = []
		var anchor := view.world_pos(view.game.data.regions[id])
		for edge_key in view.geometry.edges:
			var endpoints := String(edge_key).split("|")
			if not id in endpoints or not TerrainRules.land_connection(view.game.data, endpoints[0], endpoints[1], view.game.state):
				continue
			var local_path := PackedVector2Array()
			for point in view.geometry.edges[edge_key]:
				local_path.append(point - anchor)
			approaches.append(local_path)
		var spec := CampaignCityModel.plan(view.game.data, id, report, approaches)
		var root := Node3D.new()
		root.name = "Settlement_" + String(id)
		world.add_child(root)
		var shell := CampaignCityModel.build(spec, view.world_pos(view.game.data.regions[id]), ground)
		if shell != null:
			_mesh(root, shell, settlement_material)
		settlements[id] = {"node": root, "key": key, "plan": spec, "detail": null}

func _triangle(st: SurfaceTool, id: String, a: Vector2, b: Vector2, c: Vector2, depth: int) -> void:
	var spacing := 16.0
	var center := (a + b + c) / 3
	for site in crossing_sites:
		if center.distance_squared_to(site.center) < 900 and site.kind in ["river", "bridge", "causeway"]:
			spacing = 1.0
	if depth < 10 and maxf(a.distance_squared_to(b), maxf(b.distance_squared_to(c), c.distance_squared_to(a))) > spacing:
		var ab := (a + b) * 0.5
		var bc := (b + c) * 0.5
		var ca := (c + a) * 0.5
		_triangle(st, id, a, ab, ca, depth + 1)
		_triangle(st, id, ab, b, bc, depth + 1)
		_triangle(st, id, ca, bc, c, depth + 1)
		_triangle(st, id, ab, bc, ca, depth + 1)
		return
	# Map polygons have mixed winding; the material is double sided.
	for p in ([a, c, b] if (b - a).cross(c - a) > 0 else [a, b, c]):
		st.set_uv(p)
		st.add_vertex(ground(p, id))

func _build_routes() -> void:
	bridges.clear()
	for child in routes.get_children():
		routes.remove_child(child)
		child.queue_free()
	var road := RealismModels.new()
	var water := RealismModels.new()
	var structures := RealismModels.new()
	for key in view.geometry.edges:
		var ends := String(key).split("|")
		if not view.known_cache.has(ends[0]) or not view.known_cache.has(ends[1]) or not TerrainRules.land_connection(view.game.data, ends[0], ends[1], view.game.state):
			continue
		var path: PackedVector2Array = view.geometry.edges[key]
		var width := 0.7 + float(view.road_levels.get(key, 0)) * 0.12
		for i in range(path.size() - 1):
			var segments := maxi(1, ceili(path[i].distance_to(path[i + 1]) / 1.0))
			var direction := (path[i + 1] - path[i]).normalized()
			var normal := Vector2(-direction.y, direction.x) * width
			for j in range(segments):
				var a := path[i].lerp(path[i + 1], float(j) / segments)
				var b := path[i].lerp(path[i + 1], float(j + 1) / segments)
				var tint := RealismModels.pigment("#81765e").darkened(RealismModels.scatter(String(key), j) * 0.08)
				_quad(road, ground(a - normal) + Vector3.UP * 0.08, ground(a + normal) + Vector3.UP * 0.08, ground(b - normal) + Vector3.UP * 0.08, ground(b + normal) + Vector3.UP * 0.08, tint)
	for site in crossing_sites:
		var ends := String(site.key).split("|")
		if not view.known_cache.has(ends[0]) or not view.known_cache.has(ends[1]):
			continue
		var middle: Vector2 = site.center
		var tangent: Vector2 = site.tangent
		var cross: Vector2 = site.cross
		var kind := TerrainRules.crossing_kind(view.game.data, ends[0], ends[1], view.game.state)
		if kind in ["river", "bridge"]:
			for i in range(56):
				var a := middle + cross * (i - 28.0) + tangent * sin((i - 28.0) * 0.13) * 1.1
				var b := middle + cross * (i - 27.0) + tangent * sin((i - 27.0) * 0.13) * 1.1
				if not view.known_cache.has(view.geometry.region_at_world(a)) or not view.known_cache.has(view.geometry.region_at_world(b)):
					continue
				var n := tangent * 3.1
				_quad(water, Vector3(a.x - n.x, 0.83, a.y - n.y), Vector3(a.x + n.x, 0.83, a.y + n.y), Vector3(b.x - n.x, 0.83, b.y - n.y), Vector3(b.x + n.x, 0.83, b.y + n.y), Color.WHITE)
		if kind in ["bridge", "causeway"]:
			var half_length := 6.0 if kind == "bridge" else 9.0
			var deck := 1.65 if kind == "bridge" else 1.25
			bridges.append({"center": middle, "tangent": tangent, "cross": cross, "deck": deck, "length": half_length})
			var rot := Vector3(0, atan2(-tangent.x, -tangent.y), 0)
			var center := Vector3(middle.x, deck - 0.22, middle.y)
			structures.box(center, Vector3(3.1, 0.44, half_length * 2), RealismModels.pigment("#8b806c"), rot)
			var along3 := Vector3(tangent.x, 0, tangent.y) * half_length
			var across3 := Vector3(cross.x, 0, cross.y) * 1.5
			var top := Vector3(middle.x, deck + 0.015, middle.y)
			_quad(structures, top - along3 - across3, top - along3 + across3, top + along3 - across3, top + along3 + across3, RealismModels.pigment("#9a8e75"))
			for joint in range(int(half_length * 2)):
				var at := top + Vector3(tangent.x, 0, tangent.y) * (joint - half_length)
				structures.rod(at - across3, at + across3, 0.022, RealismModels.pigment("#5c584b"))
			for side in [-1.0, 1.0]:
				var n: Vector3 = Vector3(cross.x, 0, cross.y) * float(side) * 1.5
				var along := Vector3(tangent.x, 0, tangent.y)
				if kind == "bridge":
					structures.box(center + n + Vector3.UP * 0.5, Vector3(0.22, 0.8, half_length * 2), RealismModels.pigment("#847b68"), rot)
					for j in [-2.8, 0, 2.8]:
						structures.box(Vector3(middle.x, 0.75, middle.y) + along * j + n * 0.7, Vector3(0.45, 1.5, 0.65), RealismModels.pigment("#77715f"), rot)
				# Sloping approaches meet the actual deck, not the river bed.
				var end: Vector2 = middle + tangent * half_length * float(side)
				var approach: Vector2 = middle + tangent * (half_length + 4) * float(side)
				var edge := cross * 1.5
				_quad(structures, Vector3(end.x - edge.x, deck, end.y - edge.y), Vector3(end.x + edge.x, deck, end.y + edge.y), Vector3(approach.x - edge.x, 1.03, approach.y - edge.y), Vector3(approach.x + edge.x, 1.03, approach.y + edge.y), RealismModels.pigment("#84785e"))
		elif kind in ["ridge", "pass"]:
			# Broken outcrops leave the same traversable corridor as the graph.
			for i in range(13):
				if kind == "pass" and i in [5, 6, 7]:
					continue
				var p := ground(middle + cross * (i * 3.5 - 21))
				structures.ellipsoid(p + Vector3.UP, Vector3(2.4, 2.5 + i % 3, 2.0), RealismModels.pigment("#747769"))
	if road.vertex_count > 0:
		_mesh(routes, road.finish(), _vertex_material())
	if water.vertex_count > 0:
		_mesh(routes, water.finish(), water_material)
	if structures.vertex_count > 0:
		_mesh(routes, structures.finish(), _vertex_material())

func _quad(model: RealismModels, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	model.triangle(a, c, b, tint)
	model.triangle(b, c, d, tint)

func _vertex_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/ui/realism/campaign_solid.gdshader")
	return mat

func _mesh(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	return node

func _batch(parent: Node3D, mesh: Mesh, material: Material, poses: Array[Transform3D]) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = poses.size()
	for i in range(poses.size()):
		mm.set_instance_transform(i, poses[i])
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, Color(fmod(i * 0.618, 1.0), 0, 0, 1))
	node.multimesh = mm
	node.material_override = material
	parent.add_child(node)
	return node
