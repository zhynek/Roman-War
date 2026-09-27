extends SceneTree
## Actual pointer-driven acceptance at two window sizes, with disposable saves.
var city: RomaCityScreen
var failed := false
var out := "/tmp/roman-war-roma-phase2"

func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War City Controls QA/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			out = arg.trim_prefix("out_dir=")
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out)
	city = RomaCityScreen.new()
	root.add_child(city)
	await _frames(12)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "city opens with a free pointer")
	_check(city.command_bar.get_global_rect().has_point(city.govern_button.get_global_rect().get_center()), "govern button lives in the persistent bottom bar")
	await _shot("01-streets-bottom-commands")
	var unchanged := JSON.stringify(city.game.state)
	await _click(city.govern_button.get_global_rect().get_center())
	_check(city.drawer.visible and city._drawer_site == "", "real bottom-bar click opens city command panel")
	await _click_button(city.w("tab_works"))
	_check(city._govern_tab == "works", "public works category responds to pointer")
	await _shot("02-public-works-menu")
	_check(JSON.stringify(city.game.state) == unchanged, "browsing commands does not advance state or spend money")
	await _click_button(city.w("panel_close"))
	await _click_button(city.w("map"))
	_check(city.overview, "bottom map button opens city plan")
	# A point on the actual near roof face, including its physical occlusion.
	var tavern_point := _world_point(Vector3(-40, 5.3, 3))
	await _click(tavern_point)
	_check(city.selected_building == "tavern", "single click selects rendered tavern roof")
	await _shot("03-building-selection")
	await _click(tavern_point, MOUSE_BUTTON_RIGHT)
	_check(city.drawer.visible and city._drawer_site == "tavern", "right click opens that building's contextual dossier")
	_check(city.game.city_building_info("latium", "tavern").stage == "current", "dossier begins at existing building stage")
	await _shot("04-building-dossier")
	await _click_button(city.w("action_improve_tavern"))
	_check(city.game.city_building_info("latium", "tavern").stage == "construction", "contextual action funds a real time-based building upgrade")
	await _shot("05-construction-progress")
	await _click_button(city.w("panel_close"))
	# Double-click is issued through the same actual viewport GUI pipeline.
	var before_jump := JSON.stringify(city.game.state)
	await _click(tavern_point, MOUSE_BUTTON_LEFT, true)
	_check(not city.overview and city.player.position.distance_to(Vector3(-40, 0.08, 17)) < 2.0, "double clicking the distant building arrives at its clear entrance")
	_check(JSON.stringify(city.game.state) == before_jump, "quick jumping changes no campaign rules, budget, or RNG")
	await _shot("06-arrival-at-tavern-works")
	for day in range(3):
		await _click(city.day_button.get_global_rect().get_center())
		await _click(city.dawn.continue_button.get_global_rect().get_center())
	_check(city.game.city_building_info("latium", "tavern").stage == "improved", "three explicit days finish the funded tavern works")
	_check(city.world.project_improvements["improve_tavern"].visible and not city.world.project_scaffolds["improve_tavern"].visible, "completed architecture replaces construction scaffolds")
	await _shot("07-improved-tavern")
	var saved := _canon(city.game.state)
	await _click_button(city.w("save"))
	await _click(city.day_button.get_global_rect().get_center())
	await _click(city.dawn.continue_button.get_global_rect().get_center())
	await _click_button(city.w("load"))
	_check(_canon(city.game.state) == saved, "mouse-driven save/load retains development stage and timing")
	# Minimap dispatch, and screen scaling after a real window resize.
	root.size = Vector2i(1600, 1000)
	await _frames(10)
	var mini: Control = city.mini_map
	var marker: Vector2 = mini.call("_map", [46, -23])
	await _click(mini.global_position + marker, MOUSE_BUTTON_LEFT, true)
	_check(city.player.position.distance_to(Vector3(46, 0.08, 0)) < 2.0, "double clicking the resized minimap visits the barracks approach")
	await _shot("08-barracks-arrival")
	await _click_button(city.w("map"))
	await _click(_world_point(Vector3(0, 8.4, -40)), MOUSE_BUTTON_RIGHT)
	_check(city.drawer.visible and city._drawer_site == "curia", "3D building picking stays aligned after viewport resizing")
	await _shot("09-resized-council-dossier")
	var button_rect := city.day_button.get_global_rect()
	_check(Rect2(Vector2.ZERO, city.size).encloses(button_rect), "day and governing controls fit the resized viewport")
	_check(city.drawer.get_rect().end.y < city.command_bar.position.y, "context panel never covers the bottom command bar")
	await _click_button(city.w("panel_close"))
	await _click_button(city.w("map"))
	city.player.position = Vector3(-40, 0.1, 5)
	city.player.rotation.y = 0.35
	await _shot("10-tavern-interior")
	city.queue_free()
	await _frames(3)
	print("Roma pointer controls: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func _world_point(at: Vector3) -> Vector2:
	var camera := city.survey_camera if city.overview else city.camera
	return camera.unproject_position(at) * city.view_container.size / Vector2(city.viewport.size) + city.view_container.global_position

func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, double_click: bool = false) -> void:
	var event := InputEventMouseButton.new()
	# Native input arrives in window pixels; Controls report canvas coordinates.
	# Exercise the real stretch transform after resizing the window.
	event.position = root.get_final_transform() * point
	event.button_index = button
	event.pressed = true
	event.double_click = double_click
	Input.parse_input_event(event)
	await _frames(2)
	event.pressed = false
	event.double_click = false
	Input.parse_input_event(event)
	await _frames(3)

func _click_button(text: String) -> void:
	var button := _find_button(city, text)
	if button == null:
		_check(false, "button exists: " + text)
		return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			await _frames(3)
			break
		parent = parent.get_parent()
	await _click(button.get_global_rect().get_center())

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null

func _shot(name: String) -> void:
	city._refresh_position()
	await _frames(4)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _canon(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))

func _check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	failed = failed or not ok
