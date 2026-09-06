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
var routes: Node3D
var noise := FastNoiseLite.new()
var tree_meshes: Array = []
var infantry_meshes := {}
var _frame := Rect2()
var bridges: Array = []

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
	noise.frequency = 0.047
	noise.fractal_octaves = 5
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
	atmosphere.ambient_light_energy = 0.72
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	atmosphere.tonemap_exposure = 1.2
	environment.environment = atmosphere
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-39, -33, 0)
	sun.light_color = Color("#ffedc7")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1200
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.025
	world.add_child(sun)
	for i in range(3):
		tree_meshes.append(RealismModels.tree(i))
	routes = Node3D.new()
	world.add_child(routes)

func project(point: Vector2) -> Vector2:
	var at := (point + view._camera_offset) * view._zoom
	at.y = (at.y - view.size.y * 0.5) * sin(PITCH) + view.size.y * 0.5 - ground(point).y * cos(PITCH) * view._zoom
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
	var id := region if region != "" else view.geometry.region_at_world(point)
	if not view.game.data.regions.has(id):
		return Vector3(point.x, 0.5, point.y)
	var terrain := String(view.game.data.regions[id]["terrain"])
	var relief := float(view.game.data.terrain_content.get("terrains", {}).get(terrain, {}).get("relief", 3.0))
	var n := noise.get_noise_2d(point.x, point.y)
	var h := 1.0 + pow(absf(n) * 1.8, 1.5) * relief
	if terrain == "marsh":
		h = 0.6 + n * 0.45
	# Same authored tracks that armies follow cut through the relief.
	var anchor := view.world_pos(view.game.data.regions[id])
	var distance_to_track := maxf(0.0, point.distance_to(anchor) - 10.0)
	for neighbor in view.game.data.regions[id].get("adjacent", []):
		if not TerrainRules.land_connection(view.game.data, id, neighbor):
			continue
		var path := view.geometry.edge_path(id, neighbor)
		for j in range(path.size() - 1):
			distance_to_track = minf(distance_to_track, point.distance_to(Geometry2D.get_closest_point_to_segment(point, path[j], path[j + 1])))
	h = lerpf(0.95, h, smoothstep(2.1, 6.0, distance_to_track))
	return Vector3(point.x, h, point.y)

func sync_state() -> void:
	if not is_node_ready() or view.geometry == null:
		return
	for id in regions.keys():
		if not view.known_cache.has(id):
			regions[id].queue_free()
			regions.erase(id)
	for id in view.known_cache:
		if view.geometry.cells.has(id) and not regions.has(id):
			_build_region(id)
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
	sync_frame()

func sync_frame() -> void:
	if camera == null or view.size.y < 1:
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible and view.is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if not visible:
		return
	_sync_camera()
	_frame = Rect2(-view._camera_offset, view.size / view._zoom).grow(40)
	for id in regions:
		regions[id].visible = _frame.intersects(view.geometry.cells[id]["bounds"])
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
			var scale_by := 0.7 if group.kind in ["cavalry", "horse_archer", "general_bodyguard", "chariot", "elephant"] else 1.15
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
		if absf(relative.dot(bridge.tangent)) < 3.2 and absf(relative.dot(bridge.cross)) < 1.5:
			at.y = float(bridge.deck)
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
		if view.geometry.region_at_world(at) != id or at.distance_to(anchor) < 16:
			continue
		var p := ground(at, id)
		if absf(p.y - 0.95) < 0.12:
			continue
		var scale_by := 0.32 + RealismModels.scatter(key, 3) * 0.22
		groups[i % 3].append(Transform3D(Basis(Vector3.UP, RealismModels.scatter(key, 2) * TAU).scaled(Vector3.ONE * scale_by), p))
		if groups[0].size() + groups[1].size() + groups[2].size() >= int(profile.trees):
			break
	for i in range(3):
		var poses: Array[Transform3D] = []
		poses.assign(groups[i])
		if not poses.is_empty():
			_batch(root, tree_meshes[i], tree_material, poses)
	# A geographically known town is a silhouette only; owner flags and live
	# garrisons are the filtered 2D information layer above this surface.
	var town := RealismModels.new()
	var stone := RealismModels.pigment("#a49879")
	var roof := RealismModels.pigment("#774936")
	for i in range(16):
		var at := ground(anchor + Vector2((i % 4) * 2.6 - 4.4, (i / 4) * 2.8 - 2.7), id)
		var high := 1.3 + RealismModels.scatter(id, i) * 1.0
		var tint := stone.lerp(RealismModels.pigment("#827c69"), RealismModels.scatter(id, i + 30) * 0.3)
		town.box(at + Vector3.UP * high * 0.5, Vector3(1.8, high, 2.1), tint)
		var a := at + Vector3(-1.05, high, -1.2)
		var b := at + Vector3(1.05, high, -1.2)
		var c := at + Vector3(0, high + 0.65, -1.2)
		town.triangle(a, b, c, roof)
		town.triangle(a, c, a + Vector3.BACK * 2.4, roof)
		town.triangle(c, c + Vector3.BACK * 2.4, a + Vector3.BACK * 2.4, roof)
		town.triangle(b, b + Vector3.BACK * 2.4, c, roof)
		town.triangle(c, b + Vector3.BACK * 2.4, c + Vector3.BACK * 2.4, roof)
		town.box(at + Vector3(0, 0.4, -1.06), Vector3(0.4, 0.8, 0.04), RealismModels.pigment("#3e382e"))
		for side in [-0.55, 0.55]:
			town.box(at + Vector3(side, high * 0.65, -1.06), Vector3(0.3, 0.3, 0.04), RealismModels.pigment("#4e483b"))
	var civic := ground(anchor + Vector2(-6, -5), id)
	town.box(civic, Vector3(5, 0.4, 3), stone)
	for i in range(6):
		var at := civic + Vector3(i * 0.8 - 2, 0.2, -1.1)
		town.rod(at, at + Vector3.UP * 2.6, 0.17, stone)
	town.box(civic + Vector3.UP * 2.9, Vector3(5.3, 0.5, 3.2), roof)
	for i in range(4):
		var at := ground(anchor + Vector2(-8 if i % 2 == 0 else 8, -8 if i < 2 else 8), id)
		town.box(at + Vector3.UP * 1.8, Vector3(1.5, 3.6, 1.5), stone)
		for j in range(3):
			town.box(at + Vector3(j * 0.55 - 0.55, 3.8, -0.6), Vector3(0.3, 0.5, 0.3), stone)

	_mesh(root, town.finish(), _vertex_material())

func _triangle(st: SurfaceTool, id: String, a: Vector2, b: Vector2, c: Vector2, depth: int) -> void:
	if depth < 7 and maxf(a.distance_squared_to(b), maxf(b.distance_squared_to(c), c.distance_squared_to(a))) > 16:
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
		if not view.known_cache.has(ends[0]) or not view.known_cache.has(ends[1]):
			continue
		var path: PackedVector2Array = view.geometry.edges[key]
		var kind := TerrainRules.crossing_kind(view.game.data, ends[0], ends[1])
		if TerrainRules.land_connection(view.game.data, ends[0], ends[1]):
			for i in range(path.size() - 1):
				var segments := maxi(1, ceili(path[i].distance_to(path[i + 1]) / 2))
				for j in range(segments):
					var a := ground(path[i].lerp(path[i + 1], float(j) / segments)) + Vector3.UP * 0.15
					var b := ground(path[i].lerp(path[i + 1], float(j + 1) / segments)) + Vector3.UP * 0.15
					road.rod(a, b, 0.42 + float(view.road_levels.get(key, 0)) * 0.12, RealismModels.pigment("#b4a17b"))
		if kind in ["bridge", "river", "causeway", "ridge", "pass"]:
			var middle := path[path.size() / 2]
			var tangent := (path[-1] - path[0]).normalized()
			var cross := Vector2(-tangent.y, tangent.x)
			if kind in ["river", "bridge", "causeway"]:
				for i in range(18):
					var a := middle + cross * (i * 2.0 - 18) + tangent * sin(i * 0.55) * 1.1
					var b := middle + cross * ((i + 1) * 2.0 - 18) + tangent * sin((i + 1) * 0.55) * 1.1
					water.rod(ground(a) + Vector3.UP * 0.55, ground(b) + Vector3.UP * 0.55, 1.1, Color.WHITE)
				if kind != "river":
					var a := ground(middle - tangent * 3) + Vector3.UP * 1.5
					var b := ground(middle + tangent * 3) + Vector3.UP * 1.5
					a.y = maxf(a.y, b.y)
					b.y = a.y
					bridges.append({"center": middle, "tangent": tangent, "cross": cross, "deck": a.y + 0.18})
					structures.box((a + b) * 0.5, Vector3(2.8, 0.35, a.distance_to(b)), RealismModels.pigment("#b9ad8e"), Vector3(0, atan2(-tangent.x, -tangent.y), 0))
					for side in [-1.0, 1.0]:
						var offset: Vector3 = Vector3(cross.x, 0.5, cross.y) * float(side)
						structures.rod(a + offset, b + offset, 0.15, RealismModels.pigment("#8e826c"))
			else:
				for i in range(9):
					if kind == "pass" and i in [3, 4, 5]:
						continue
					var p := ground(middle + cross * (i * 3 - 12))
					structures.ellipsoid(p + Vector3.UP * 3, Vector3(3, 6 + i % 3, 2.5), RealismModels.pigment("#75766b"))
	for region in view.visible_cache:
		var post: Dictionary = view.game.state.get("watchposts", {}).get(region, {})
		if post.is_empty() or not ReconRules.post_active(view.game.state, region, post):
			continue
		var at := ground(view.world_pos(view.game.data.regions[region]) + Vector2(-14, 10))
		structures.box(at + Vector3.UP * 3, Vector3(2.2, 6, 2.2), RealismModels.pigment("#8b8771"))
		for i in range(4):
			structures.box(at + Vector3(-0.85 + i * 0.57, 6.2, -0.95), Vector3(0.35, 0.6, 0.35), RealismModels.pigment("#a99e83"))
	if road.vertex_count > 0:
		_mesh(routes, road.finish(), _vertex_material())
	if water.vertex_count > 0:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#346b72")
		mat.metallic = 0.45
		mat.roughness = 0.25
		_mesh(routes, water.finish(), mat)
	if structures.vertex_count > 0:
		_mesh(routes, structures.finish(), _vertex_material())

func _vertex_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.87
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
