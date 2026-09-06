class_name RealismPlateCache
extends RefCounted
## Original 3D illustrations, rendered once and cached in memory. No image
## assets, save writes, or continuing viewport cost after the portrait is ready.
static var textures := {}
static var pending := {}

static func request(canvas: CanvasItem, spec: Dictionary) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var key := String(spec.get("key", spec.get("id", ""))) + "|" + String(spec.get("kind", "portrait"))
	if not spec.has("parts"):
		key += "|" + str(spec.get("age", 30)) + "|" + str(spec.get("cape", ""))
	if textures.has(key):
		return textures[key]
	if not pending.has(key):
		pending[key] = []
		_render.call_deferred(key, spec.duplicate(true), weakref(canvas))
	pending[key].append(weakref(canvas))
	return null

static func _render(key: String, spec: Dictionary, target: WeakRef) -> void:
	var canvas = target.get_ref()
	if canvas == null or not canvas.is_inside_tree():
		pending.erase(key)
		return
	var viewport := SubViewport.new()
	var portrait := not spec.has("parts")
	viewport.size = Vector2i(256, 256) if portrait else Vector2i(512, 320)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas.get_tree().root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("#192725")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("#bdced1")
	atmosphere.ambient_light_energy = 0.75
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = atmosphere
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-33, -37, 0)
	sun.light_color = Color("#ffe6bc")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22, 145, 0)
	fill.light_color = Color("#d7e1e3")
	fill.light_energy = 1.8
	world.add_child(fill)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 34
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/ui/realism/soldier.gdshader")
	if portrait:
		var tint: Color = spec.get("cape", Color("#89523d"))
		var model := RealismModels.soldier(tint, spec.get("culture", "roman") != "roman", true, spec)
		_add(world, model, material)
		camera.position = Vector3(0.55, 1.75, -2.2)
		camera.look_at(Vector3(0, 1.49, 0))
	elif spec.get("kind", "") == "unit":
		var tint := Color("#9a6c4a")
		for part in spec.get("parts", []):
			if part["part"] == "figure":
				tint = part.get("shade", {}).get("mid", tint)
		var kind := String(spec.get("unit_class", "infantry"))
		var large := kind in ["elephant", "ship", "siege", "chariot"]
		var model := RealismUnitModels.build(tint, kind, spec.get("look", {}))
		for i in range(1 if large else 5):
			var node := _add(world, model, material)
			node.position = Vector3((i % 3) * 0.85 - 0.85, 0, (i / 3) * 1.2) if not large else Vector3.ZERO
		camera.position = Vector3(4.5, 3.8, -8.3) if large else Vector3(3.5, 3.0, -6.3)
		camera.look_at(Vector3(0, 1.25, 0.3))

	else:
		var model := RealismModels.new()
		for part in spec.get("parts", []):
			var rect: Rect2 = part.get("rect", Rect2(0.3, 0.4, 0.4, 0.4))
			var color: Color = part.get("shade", {}).get("mid", Color("#a49b82"))
			color.a = 0.0
			var params: Dictionary = part.get("p", {})
			var width := maxf(0.08, rect.size.x * 8)
			var height := maxf(0.08, rect.size.y * 7)
			var at := Vector3((rect.get_center().x - 0.5) * 8, (0.88 - rect.end.y) * 7, 0)
			match String(part.get("part", "box")):
				"column_row", "posts", "arcade":
					var count := clampi(int(params.get("columns", params.get("count", 5))), 1, 14)
					for j in range(count):
						var p := at + Vector3((float(j) / maxf(count - 1, 1) - 0.5) * width, 0, -0.65)
						model.rod(p, p + Vector3.UP * height, 0.12, color)
						model.box(p + Vector3.UP * height, Vector3(0.36, 0.12, 0.36), color)
				"roof", "pediment":
					var a := at + Vector3(-width * 0.5, 0, -0.8)
					var b := at + Vector3(width * 0.5, 0, -0.8)
					var c := at + Vector3(0, height, -0.8)
					model.triangle(a, b, c, color)
					model.triangle(a, c, a + Vector3.BACK * 1.6, color)
					model.triangle(c, c + Vector3.BACK * 1.6, a + Vector3.BACK * 1.6, color)
					model.triangle(b, b + Vector3.BACK * 1.6, c, color)
					model.triangle(c, b + Vector3.BACK * 1.6, c + Vector3.BACK * 1.6, color)
				"figure", "crowd", "smoke", "chevrons":
					continue
				_:
					model.box(at + Vector3.UP * height * 0.5, Vector3(width, height, maxf(0.35, width * 0.4)), color)
		if model.vertex_count > 0:
			_add(world, model.finish(), material)
		camera.position = Vector3(5.8, 4.5, -10)
		camera.look_at(Vector3(0, 1.8, 0))
	if not portrait:
		var floor_mesh := PlaneMesh.new()
		floor_mesh.size = Vector2(200, 200)
		floor_mesh.subdivide_width = 2
		floor_mesh.subdivide_depth = 2
		var floor_material := ShaderMaterial.new()
		floor_material.shader = preload("res://src/ui/realism/campaign_ground.gdshader")
		floor_material.set_shader_parameter("ground_color", Color("#50543a"))
		floor_material.set_shader_parameter("world_uv", true)
		_add(world, floor_mesh, floor_material).position.y = -0.02
		if spec.get("unit_class", "") != "ship":
			var foliage := ShaderMaterial.new()
			foliage.shader = preload("res://src/ui/realism/foliage.gdshader")
			for i in range(5):
				var tree := _add(world, RealismModels.tree(i % 3), foliage)
				tree.scale = Vector3.ONE * (0.45 + i * 0.04)
				tree.position = Vector3(-7 + i * 3.5, 0, 6 + (i % 2) * 2)
			var grass := RealismModels.grass()
			for i in range(45):
				var p := Vector3((RealismModels.scatter(key, i * 3) - 0.5) * 18, 0, (RealismModels.scatter(key, i * 3 + 1) - 0.5) * 14)
				if absf(p.x) < 3 and absf(p.z) < 3:
					continue
				var tuft := _add(world, grass, foliage)
				tuft.scale = Vector3.ONE * 0.55
				tuft.position = p
		else:
			floor_material.shader = preload("res://src/ui/realism/water.gdshader")
		atmosphere.fog_enabled = true
		atmosphere.fog_density = 0.023
		atmosphere.fog_light_color = Color("#34483e")

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if textures.size() >= 128:
		textures.clear()
	textures[key] = ImageTexture.create_from_image(viewport.get_texture().get_image())
	viewport.queue_free()
	for ref in pending.get(key, []):
		var owner = ref.get_ref()
		if owner != null:
			owner.queue_redraw()
	pending.erase(key)

static func _add(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	return node
