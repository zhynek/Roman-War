extends SceneTree
## Rendered Roma acceptance test. QA images stay outside the repository.
var city: RomaCityScreen
var failed := false
var out := "/tmp/roman-war-roma-qa"

func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War City QA/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			out = arg.trim_prefix("out_dir=")
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out)
	city = RomaCityScreen.new()
	root.add_child(city)
	await _frames(10)
	var unchanged := JSON.stringify(city.game.state)
	var start_position := city.player.position
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(root.size) * 0.5
	Input.parse_input_event(click)
	await _frames(2)
	click.pressed = false
	Input.parse_input_event(click)
	var walk := InputEventKey.new()
	walk.physical_keycode = KEY_W
	walk.keycode = KEY_W
	walk.pressed = true
	Input.parse_input_event(walk)
	await _frames(30)
	walk.pressed = false
	Input.parse_input_event(walk)
	_check(city.player.position.z < start_position.z - 0.3, "real click and W input move the governor along the street")
	city.toggle_walk()
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "walk mode captures the mouse explicitly")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await _frames(2)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases the captured mouse")
	city.player.position = start_position
	await _frames(20)
	_check(JSON.stringify(city.game.state) == unchanged, "walking presentation never advances rules or RNG")
	await _shot("01-arrival")
	city.player.position = Vector3(0, 0.1, 17)
	await _shot("02-forum-unrest")
	city.toggle_overview()
	await _shot("03-city-plan")
	city.toggle_overview()
	city.set_physics_process(false)
	# Continuous capsule sweeps through the real doors, not teleports as proof
	# of accessibility. Furniture is off each building's central passage.
	await _passage("tavern", Vector3(-40, 0.12, 16), Vector3(-40, 0.12, 2))
	city.player.position = Vector3(-40, 0.1, 5)
	city.player.rotation.y = 0.35
	await _shot("04-tavern-interior")
	await _passage("barracks", Vector3(46, 0.12, -6), Vector3(46, 0.12, -20))
	city.player.position = Vector3(46, 0.1, -14)
	city.player.rotation.y = -0.55
	await _shot("05-barracks-interior")
	await _passage("curia", Vector3(0, 0.12, -27), Vector3(0, 0.12, -39))
	# A collidable exterior must stop the same capsule away from its doorway.
	var wall_transform := Transform3D(Basis.IDENTITY, Vector3(-34, 0.12, 15))
	_check(city.player.test_move(wall_transform, Vector3(0, 0, -8)), "tavern walls block the governor")
	city.perform_action("repair_streets")
	city.perform_action("clean_water")
	city.perform_action("grain_relief")
	city.perform_action("tax_low")
	city.player.position = Vector3(-6, 0.1, 20)
	city.player.rotation.y = -0.2
	city.open_drawer("curia")
	await _shot("06-governing-orders")
	city.drawer.hide()
	for i in range(4):
		city.advance_day()
		city.dawn.dismiss()
	_check(city.status["projects"]["repair_streets"]["completed"], "street repair completes after explicit days")
	_check(city.status["projects"]["clean_water"]["completed"], "water restoration completes after explicit days")
	await _shot("07-improved-forum")
	city.perform_action("close_taverns")
	city.player.position = Vector3(-40, 0.1, 21)
	city.player.rotation.y = 0
	await _shot("08-tavern-closed")
	city.save_city()
	var saved := JSON.stringify(JSON.parse_string(JSON.stringify(city.game.state)))
	city.advance_day()
	city.dawn.dismiss()
	city.load_city()
	_check(JSON.stringify(JSON.parse_string(JSON.stringify(city.game.state))) == saved, "Roma saves and restores its governed state")
	_check(city.save_path != CampaignScreen.SAVE_PATH, "Roma save slot is isolated")
	_check(city.drawer.get_rect().end.y <= city.size.y - 70, "governance fits the viewport")
	var frames: Array[float] = []
	await _frames(15)
	for sample in range(60):
		var started := Time.get_ticks_usec()
		await process_frame
		frames.append(float(Time.get_ticks_usec() - started) / 1000.0)
	frames.sort()
	print("Roma render frame sample: median ", frames[30], " ms; p95 ", frames[57], " ms at ", root.size)
	city.queue_free()
	await _frames(3)
	print("Roma rendered playtest: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func _passage(label: String, start: Vector3, finish: Vector3) -> void:
	city.player.position = start
	await physics_frame
	var motion := finish - start
	_check(not city.player.test_move(city.player.global_transform, motion), label + " doorway admits the player capsule")

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	city._refresh_position()
	await _frames(5)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))

func _check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	failed = failed or not ok
