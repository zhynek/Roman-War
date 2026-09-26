extends RefCounted

func test_switching_modes_keeps_independent_saves_and_storage(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var directory := OS.get_user_data_dir()
	var main = load("res://src/ui/main.tscn").instantiate()
	tree.root.add_child(main)
	main._on_start_pressed()
	var campaign: CampaignScreen = main.active_session
	campaign._save_game()
	var saved := FileAccess.get_file_as_string(campaign.save_path)
	main._return_to_menu()
	main._on_alpine_pressed()
	var route = main.active_session
	t.check_eq(OS.get_user_data_dir(), directory, "embedding Alpine never changes global storage")
	t.check_eq(route.screen.save_path, "user://alpine_route_save.json", "QA route storage stays isolated")
	t.check(route.screen.main_menu_enabled, "route offers return to menu")
	route.screen._save_game()
	t.check_eq(FileAccess.get_file_as_string(CampaignScreen.SAVE_PATH), saved, "route save cannot overwrite campaign")
	var route_saved := FileAccess.get_file_as_string(route.screen.save_path)
	route.start_route()
	t.check_eq(route.screen.save_path, "user://alpine_route_save.json", "restart preserves route slot")
	t.check_eq(FileAccess.get_file_as_string(route.screen.save_path), route_saved, "restart does not erase save")
	main._return_to_menu()
	main._on_start_pressed()
	campaign = main.active_session
	campaign._load_game()
	t.check_eq(JSON.stringify(SaveGame.read_file(campaign.save_path)), JSON.stringify(campaign.game.state), "campaign reloads its own save after route play")
	t.check(campaign.main_menu_enabled, "campaign offers return to menu")
	main.free()


func test_production_mac_route_retains_previous_app_slot(t) -> void:
	var script = load("res://src/ui/realism/development_main.gd")
	var custom = ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	var name = ProjectSettings.get_setting("application/config/name", "")
	ProjectSettings.set_setting("application/config/use_custom_user_dir", false)
	ProjectSettings.set_setting("application/config/name", "Roman War")
	var production: String = script.embedded_save_path()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", custom)
	ProjectSettings.set_setting("application/config/name", name)
	var expected := OS.get_data_dir().path_join("Roman War Alpine Route/roman_war_save.json") if OS.get_name() == "macOS" else "user://alpine_route_save.json"
	t.check_eq(production, expected, "published Mac route saves and backups remain accessible")
	t.check_eq(script.embedded_save_path(), "user://alpine_route_save.json", "test storage never reaches the production slot")
