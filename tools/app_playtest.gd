extends SceneTree
## Exercise the exported campaign menu and persistent save across two processes.
## Run -- phase=save then -- phase=load with the same qa_id and out_dir.
## QA storage is separate from every playable app's save directory.
var phase := "save"
var qa_id := ""
var output := "/tmp/roman-war-app-playtest"
var failed := false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("phase="):
			phase = arg.trim_prefix("phase=")
		elif arg.begins_with("qa_id="):
			qa_id = arg.trim_prefix("qa_id=")
		elif arg.begins_with("out_dir="):
			output = arg.trim_prefix("out_dir=")
	if not phase in ["save", "load"] or qa_id.is_empty() or not qa_id.is_valid_identifier():
		push_error("app playtest requires phase=save|load and a simple qa_id")
		quit(1)
		return
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War App QA/" + qa_id)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	_run.call_deferred()


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	DirAccess.make_dir_recursive_absolute(output)
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await _shot("%s-menu" % phase)
	_check(main.status_label.text.contains(str(ProjectSettings.get_setting("application/config/version"))), "menu shows this package's version")
	main.faction_options.selected = main._faction_ids.find("julii")
	main.seed_spin.value = 42
	main.get_node("Center/Menu/Start").pressed.emit()
	var screen: CampaignScreen
	for child in main.get_children():
		if child is CampaignScreen:
			screen = child
	_check(screen != null, "Begin campaign opens the actual campaign screen")
	if screen == null:
		quit(1)
		return
	screen.playback_enabled = false
	if phase == "save":
		screen._end_turn()
		screen._save_game()
		var saved := SaveGame.read_file(screen.save_path)
		_check(not saved.is_empty() and _canon(saved) == _canon(screen.game.state), "UI Save persists the campaign after a real end turn")
		var expected := FileAccess.open("user://expected_state.json", FileAccess.WRITE)
		expected.store_string(_canon(screen.game.state))
		expected.close()
	else:
		screen._load_game()
		var expected := FileAccess.get_file_as_string("user://expected_state.json")
		_check(not expected.is_empty() and _canon(screen.game.state) == expected, "UI Load restores the prior process's exact campaign")
	await _shot("%s-campaign" % phase)
	var campaign_bytes := FileAccess.get_file_as_string(screen.save_path)
	await _return_via_options(main, screen)
	main.get_node("Center/Menu/Alpine").pressed.emit()
	var route = main.active_session
	screen = route.screen
	_check(screen.save_path == "user://alpine_route_save.json", "Alpine QA uses a separate slot inside isolated storage")
	screen.playback_enabled = false
	if phase == "save":
		screen._end_turn()
		screen._save_game()
		var expected := FileAccess.open("user://expected_route.json", FileAccess.WRITE)
		expected.store_string(_canon(screen.game.state))
		expected.close()
	else:
		screen._load_game()
		_check(_canon(screen.game.state) == FileAccess.get_file_as_string("user://expected_route.json"), "Alpine Load restores the prior process's exact route")
	_check(FileAccess.get_file_as_string(CampaignScreen.SAVE_PATH) == campaign_bytes, "Alpine saves leave the full campaign unchanged")
	await _shot("%s-alpine" % phase)
	route.start_route()
	screen = route.screen
	screen._load_game()
	_check(_canon(screen.game.state) == FileAccess.get_file_as_string("user://expected_route.json"), "restart keeps the Alpine save slot")
	await _return_via_options(main, screen)
	main.get_node("Center/Menu/Start").pressed.emit()
	screen = main.active_session
	screen._load_game()
	_check(_canon(screen.game.state) == FileAccess.get_file_as_string("user://expected_state.json"), "switching back restores the full campaign")
	print("app playtest ", phase, ": ", "FAIL" if failed else "PASS", " storage ", OS.get_user_data_dir())
	quit(1 if failed else 0)


func _canon(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))


func _check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	failed = failed or not ok


func _shot(name: String) -> void:
	for i in range(10):
		await process_frame
		RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))


func _return_via_options(main, screen: CampaignScreen) -> void:
	screen.options_menu.get_popup().id_pressed.emit(CampaignScreen.OPTION_MAIN_MENU)
	var dialog: ConfirmationDialog
	for child in screen.get_children():
		if child is ConfirmationDialog:
			dialog = child
	_check(dialog != null and dialog.visible, "return to menu asks before discarding progress")
	if dialog == null:
		return
	var before := _canon(screen.game.state)
	dialog.hide()
	dialog.canceled.emit()
	for i in range(2):
		await process_frame
	_check(main.active_session != null and _canon(screen.game.state) == before, "canceling return keeps the current game unchanged")
	screen.options_menu.get_popup().id_pressed.emit(CampaignScreen.OPTION_MAIN_MENU)
	for child in screen.get_children():
		if child is ConfirmationDialog:
			dialog = child
	dialog.confirmed.emit()
	for i in range(3):
		await process_frame
	_check(main.active_session == null and main.get_node("Center").visible, "return to menu removes the active session")
