extends SceneTree
## Phase-three acceptance: model previews, predictions, dawn and real troops.
var city: RomaCityScreen
var failed := false
var out := "/tmp/roman-war-roma-phase3"

func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War Evolution QA/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			out = arg.trim_prefix("out_dir=")
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out)
	city = RomaCityScreen.new()
	root.add_child(city)
	await _frames(12)
	await _shot("01-street-detail")
	city.select_target("tavern", "tavern")
	city.open_drawer("tavern")
	await _click_button(city.w("tab_building_development"))
	var initial := JSON.stringify(city.game.state)
	await _click_button(city.w("preview_improved"))
	_check(city._building_preview.get("stage") == "improved", "development button shows the real future building model")
	_check(not city.world.project_improvements["improve_tavern"].visible, "preview does not refurbish the live city")
	await _shot("02-future-building-model")
	await _click_button(city.w("preview_construction"))
	_check(JSON.stringify(city.game.state) == initial, "preview stage changes spend no funds or time")
	await _shot("03-construction-model")
	city.open_drawer("forum")
	await _click_button(city.w("action_workforce_paid"))
	await _click_button(city.w("action_repair_streets"))
	_check(int(city.status["work_rate"]) == 2, "paid labor order changes real construction speed")
	city._open_governance()
	city._choose_govern_tab("policies")
	await _frames(5)
	var tax := _find_button(city, city.w("action_tax_high"))
	var preview := _find_button(tax.get_parent(), city.w("preview_consequences"))
	var before_prediction := JSON.stringify(city.game.state)
	await _click_control(preview)
	_check(JSON.stringify(city.game.state) == before_prediction, "order forecast is read-only")
	await _shot("04-governing-consequences-preview")
	city.drawer.hide()
	var prediction := city.game.city_day_forecast("latium")
	await _click_control(city.day_button)
	_check(city.dawn.visible and int(city.status["day"]) == 2, "next-day click resolves once and opens morning ceremony")
	_check(city.dawn.audio.stream is AudioStreamWAV, "the new day plays an original synthesized gong")
	_check(_canon(city.status["last_day_report"]["after"]) == _canon(prediction["next_day"]), "morning consequences match the exact prior forecast")
	var resolved := JSON.stringify(city.game.state)
	city.advance_day()
	_check(JSON.stringify(city.game.state) == resolved, "morning report prevents duplicate day advancement")
	await create_timer(1.2).timeout
	await _shot("05-new-day-consequences")
	await _click_control(city.dawn.sound_button)
	_check(not city.dawn.sound_enabled and not city.dawn.audio.playing, "gong mute responds to real pointer input")
	await _click_control(city.dawn.continue_button)
	_check(not city.dawn.visible, "morning acknowledgment returns to the city")
	await _day()
	_check(city.status["projects"]["repair_streets"]["completed"], "paid crews complete three units of road work in two days")
	await _click_control(city.report_button)
	await _shot("06-completed-works-report")
	await _click_control(city.dawn.continue_button)
	city.select_target("barracks", "barracks")
	city.open_drawer("barracks")
	await _click_button(city.w("tab_building_troops"))
	_check(_find_button(city, city.w("action_drill_maniples")).disabled, "drill programme displays its real barracks prerequisite")
	await _shot("07-barracks-programmes")
	await _click_button(city.w("tab_building_orders"))
	await _click_button(city.w("action_improve_barracks"))
	city.drawer.hide()
	await _day()
	await _day()
	_check(city.status["projects"]["improve_barracks"]["completed"], "barracks refit finishes under the paid work rate")
	city.open_drawer("barracks")
	await _click_button(city.w("tab_building_troops"))
	var old_troops: Array = city.game.city_troop_status("latium")["garrison"].duplicate(true)
	await _click_button(city.w("action_drill_maniples"))
	city.drawer.hide()
	await _day()
	await _day()
	_check(not city.status["projects"]["drill_maniples"]["completed"], "extra builders do not instantly train soldiers")
	await _day()
	var trained: Array = city.game.city_troop_status("latium")["garrison"]
	_check(int(trained[0]["experience"]) > int(old_troops[0]["experience"]), "programme upgrades the actual campaign garrison")
	city.open_drawer("barracks")
	await _click_button(city.w("tab_building_troops"))
	await _click_button(city.w("action_equip_maniples"))
	city.drawer.hide()
	for i in range(4):
		await _day()
	var equipped := city.game.city_troop_status("latium")
	_check(int(equipped["garrison"][0]["weapon"]) > int(old_troops[0]["weapon"]), "equipment programme improves real garrison weapons")
	_check(int(equipped["recruitable"][0]["profile"]["armor"]) > 0, "future troop profiles inherit completed equipment standards")
	city.open_drawer("barracks")
	await _click_button(city.w("tab_building_troops"))
	city.drawer.get_child(0).scroll_vertical = int(city.drawer.get_child(0).get_v_scroll_bar().max_value)
	await _shot("08-troop-types-and-quality")
	city.drawer.hide()
	city.save_city()
	var saved := _canon(city.game.state)
	await _day()
	city.load_city()
	_check(_canon(city.game.state) == saved, "dawn history and military progression survive save/load")
	root.size = Vector2i(1600, 1000)
	await _frames(8)
	await _click_control(city.report_button)
	await _shot("09-resized-morning-report")
	_check(Rect2(Vector2.ZERO, city.size).encloses(city.dawn.continue_button.get_global_rect()), "morning acknowledgment fits the resized viewport")
	await _click_control(city.dawn.continue_button)
	city.quick_jump(Vector3(-40, 0, 17), "tavern", "tavern")
	city.player.position = Vector3(-40, 0.1, 5)
	city.player.rotation.y = 0.35
	await _shot("10-tavern-people-detail")
	city.queue_free()
	await _frames(3)
	print("Roma evolution and aftermath: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func _day() -> void:
	await _click_control(city.day_button)
	_check(city.dawn.visible, "explicit day opens its aftermath")
	await _click_control(city.dawn.continue_button)

func _click_control(control: Control) -> void:
	if control == null:
		_check(false, "required control exists")
		return
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
			break
		parent = parent.get_parent()
	await _frames(4)
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * control.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(5)

func _click_button(text: String) -> void:
	await _click_control(_find_button(city, text))

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null

func _shot(name: String) -> void:
	await _frames(8)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _canon(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))

func _check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	failed = failed or not ok
