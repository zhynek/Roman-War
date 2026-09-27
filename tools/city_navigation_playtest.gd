extends SceneTree
## Physics acceptance for actual Roma geometry, including roofs, furniture,
## doorway occlusion and safe mouse travel. No player save is ever used.
var city: RomaCityScreen
var failed := false

func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War City Navigation QA/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	_run.call_deferred()

func _run() -> void:
	city = RomaCityScreen.new()
	root.add_child(city)
	city.set_physics_process(false)
	await physics_frame
	await physics_frame
	var unchanged := JSON.stringify(city.game.state)
	var camera := Camera3D.new()
	camera.far = 450
	city.world.add_child(camera)
	var center := Vector2(city.viewport.size) * 0.5
	# The same ray sees the solid near wall and cannot select the house behind.
	camera.position = Vector3(-34, 1.68, 20)
	camera.look_at(Vector3(-34, 1.68, -50))
	var wall := RomaCityNavigation.pick(city.world, camera, center, city.player)
	_check(wall.hit and wall.building_id == "tavern", "nearest tavern wall occludes the distant residential block")
	_check(wall.position.z > 10, "wall selection uses actual collision surface")
	# An actual doorway remains open to the ray: the selected surface is inside.
	camera.position = Vector3(-40, 1.68, 20)
	camera.look_at(Vector3(-40, 1.68, -50))
	var doorway := RomaCityNavigation.pick(city.world, camera, center, city.player)
	_check(doorway.hit and doorway.building_id == "tavern" and doorway.position.z < 0, "doorway picking reaches the interior instead of a filled footprint proxy")
	camera.far = 2
	_check(not RomaCityNavigation.pick(city.world, camera, center, city.player).hit, "pick never reaches farther than the camera's visible range")
	camera.far = 450
	camera.position = Vector3(-40, 28, 0)
	camera.look_at(Vector3(-40, 0, 0), Vector3.FORWARD)
	var roof := RomaCityNavigation.pick(city.world, camera, center, city.player)
	_check(roof.hit and roof.building_id == "tavern" and roof.position.y > 4, "overview roof selects the visible building")
	var roof_landing := RomaCityNavigation.landing(city.world, city.player, roof.position, str(roof.site_id), str(roof.building_id))
	_check(roof_landing.ok and roof_landing.position.z > 11 and roof_landing.position.y < 0.2, "roof travel arrives at the tavern street approach")
	for site in city.layout.sites:
		var result := RomaCityNavigation.landing(city.world, city.player, Vector3.ZERO, str(site.id))
		_check(result.ok, str(site.id) + " has a capsule-clear route from its arrival point to the city street")
	var table := RomaCityNavigation.landing(city.world, city.player, Vector3(-35, 0, 3))
	_check(table.ok and table.position.distance_to(Vector3(-35, 0.08, 3)) > 0.6, "furniture travel finds nearby walkable floor")
	var house := RomaCityNavigation.landing(city.world, city.player, Vector3(-20, 0, 41))
	_check(not house.ok, "a raw click deep inside a solid house cannot become a landing")
	var outside := RomaCityNavigation.landing(city.world, city.player, Vector3(0, 0, 85))
	_check(not outside.ok and outside.reason == "jump_outside", "outside the closed city is rejected without clamping to a street")
	# The fountain has empty floor inside its solid basin but no capsule route.
	var basin := RomaCityNavigation.landing(city.world, city.player, Vector3(-14, 0, 5))
	_check(not basin.ok or absf(basin.position.x + 14) > 1.45 or absf(basin.position.z - 5) > 1.25, "clear but enclosed fountain basin never accepts the governor")
	var timings: Array[float] = []
	for target in [Vector3(-73, 0, -63), Vector3(75, 0, 74), Vector3(75.5, 0, -74.5), Vector3(-35, 0, 3), Vector3(46, 0, -20), Vector3(-14, 0, 5)]:
		for key in ["roma_connected_street_cells", "roma_clear_street_cells", "roma_disconnected_street_cells"]:
			city.world.remove_meta(key)
		var started := Time.get_ticks_usec()
		var result := RomaCityNavigation.landing(city.world, city.player, target)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		timings.append(elapsed)
		print("Uncached Roma jump ", target, ": ", elapsed, " ms; accepted=", result.ok)
	timings.sort()
	print("Uncached Roma jump samples: median ", timings[timings.size() / 2], " ms; max ", timings.back(), " ms")
	_check(JSON.stringify(city.game.state) == unchanged, "all pick and landing queries preserve campaign state and RNG")
	city.queue_free()
	await process_frame
	await process_frame
	print("Roma navigation physics: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func _check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	failed = failed or not ok
