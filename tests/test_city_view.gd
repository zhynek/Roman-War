extends RefCounted

func test_inspected_building_and_selection_remain_consistent(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var city := RomaCityScreen.new()
	city.standalone = false
	city.game = Game.new_campaign("senate", 42, "medium", "long", false)
	tree.root.add_child(city)
	var state_before := JSON.stringify(city.game.state)
	city.select_target("tavern", "tavern")
	t.check_eq(city.destination, "tavern", "selected civic site becomes the compass destination")
	var house := ""
	for building in city.layout["buildings"]:
		if city.site_by_id(building["id"]).is_empty():
			house = building["id"]
			break
	city.select_target(house, "")
	t.check_eq(city.destination, "", "residential selection clears the old civic waypoint")
	city.inspect_selection()
	city.select_target("curia", "curia")
	city._refresh_drawer()
	t.check_eq(city.drawer_body.get_child(0).get_child(0).text, city.residence_name(house), "open dossier remains bound to its inspected building when selection changes")
	city.select_target("", "")
	t.check(city.inspect_button.disabled and city.destination == "", "empty street clears selection and the old destination")
	var hide := InputEventKey.new()
	hide.keycode = KEY_H
	hide.pressed = true
	city._input(hide)
	t.check(city.command_bar.visible and city.govern_button.is_visible_in_tree(), "hide overlays preserves the governing controls")
	t.check_eq(JSON.stringify(city.game.state), state_before, "inspection and HUD changes are presentation only")
	city.free()

func test_city_entry_borrows_campaign_without_changing_global_storage(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var original_directory := OS.get_user_data_dir()
	var game := Game.new_campaign("senate", 42, "medium", "long", false)
	var screen := CampaignScreen.create(game)
	var holder := Control.new()
	tree.root.add_child(holder)
	holder.add_child(screen)
	screen._enter_roma()
	t.check_eq(holder.get_child_count(), 2, "city opens beside suspended campaign")
	var city := holder.get_child(1) as RomaCityScreen
	t.check(city.game == game, "city retains the exact campaign facade")
	t.check_eq(city.save_path, screen.save_path, "embedded city saves the owning campaign")
	t.check_eq(screen.process_mode, Node.PROCESS_MODE_DISABLED, "campaign cannot receive input behind the city")
	t.check_eq(OS.get_user_data_dir(), original_directory, "entering never rewrites global storage")
	var treasury := int(game.state["factions"]["senate"]["treasury"])
	city.perform_action("repair_streets")
	t.check(int(game.state["factions"]["senate"]["treasury"]) < treasury, "city command spends actual shared treasury")
	city.save_city()
	screen.selected_agent = "stale_agent"
	screen._day_beats = [{"kind": "stale"}]
	screen._treasury_ticking = true
	city.load_city()
	t.check_eq(screen.selected_agent, "", "embedded load clears old campaign selection")
	t.check_eq(screen._day_beats, game.day_beats(), "embedded load replaces dispatch with loaded journal")
	t.check(not screen._treasury_ticking, "embedded load stops old treasury animation")
	holder.free()

func test_foreign_roma_cannot_open_and_menu_can_start_focused_city(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Control.new()
	tree.root.add_child(holder)
	var screen := CampaignScreen.create(Game.new_campaign("julii", 42))
	holder.add_child(screen)
	screen._enter_roma()
	t.check_eq(holder.get_child_count(), 1, "foreign city rejected without scene change")
	holder.free()
	var menu = load("res://src/ui/main.tscn").instantiate()
	tree.root.add_child(menu)
	menu._on_roma_pressed()
	t.check(menu.active_session is CampaignSession, "start menu enters the ongoing campaign session")
	var session: CampaignSession = menu.active_session
	t.check_eq(session.active_view, "city", "Roma menu entry begins inside the city")
	t.check_eq(session.save_path, CampaignScreen.SAVE_PATH, "city and campaign share one save slot")
	t.check(session.city.game == session.game, "city uses the session's actual campaign")
	t.check_eq(session.game.state["settlements"]["latium"]["owner"], "senate", "focused mode uses Roma's actual owner")
	menu.free()
