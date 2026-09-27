extends RefCounted
## Integration contracts for the retained city, strategic map and battle host.
## The runner isolates user://; each test also uses its own save filename.

func _session(name: String, game: Game = null, view: String = "city") -> CampaignSession:
	if game == null:
		game = Game.new_campaign("senate", 42, "medium", "long", false)
	var session := CampaignSession.create(game, view, "user://roma-session-%s.json" % name)
	(Engine.get_main_loop() as SceneTree).root.add_child(session)
	return session


func _canon(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))


func _synchronous_signal(object: Object, signal_name: String) -> void:
	# Test methods execute inside one frame. Use the production callback now
	# rather than leave its deferred signal queued after fixture destruction.
	for connection in object.get_signal_connection_list(signal_name):
		var callback: Callable = connection["callable"]
		object.disconnect(signal_name, callback)
		object.connect(signal_name, callback)


func _ready_siege() -> Game:
	var game := Game.new_campaign("senate", 42, "medium", "long", false)
	game.state["armies"]["army_roma_session_invader"] = {
		"owner": "gaul", "region": "latium", "general": null,
		"movement_left": 0.0, "forced_march": false,
		"units": [{"template": "tribal_warband", "experience": 0,
			"strength_pct": 100, "weapon": 0, "armor": 0}],
	}
	DiplomacyRules.declare_war(game.data, game.state, "gaul", "senate")
	game.state["settlements"]["latium"]["siege"] = {
		"besieger": "army_roma_session_invader", "turns": 3, "equipment_ready": true,
	}
	return game


func test_city_map_roundtrip_retains_one_game_and_city_presentation(t) -> void:
	var session := _session("roundtrip")
	var game := session.game
	var city := session.city
	city.player.position = Vector3(2, 1, 24)
	city.survey_camera.position = Vector3(18, 44, 36)
	var player_position := city.player.position
	var camera_transform := city.survey_camera.transform
	var garrison_count := city.garrison_view.groups.size()
	var before := _canon(game.state)
	session.show_campaign()
	var campaign := session.campaign
	t.check(campaign.game == game and city.game == game, "both views borrow the exact same game")
	t.check_eq(campaign.save_path, city.save_path, "both views use the same save slot")
	t.check(not city.visible and city.process_mode == Node.PROCESS_MODE_DISABLED, "hidden city stops processing")
	t.check(campaign.visible and campaign.process_mode == Node.PROCESS_MODE_INHERIT, "strategic map owns the visible view")
	session.show_city()
	t.check(session.city == city and session.campaign == campaign, "roundtrip retains both existing scenes")
	t.check_eq(city.player.position, player_position, "walking position survives strategic view")
	t.check_eq(city.survey_camera.transform, camera_transform, "city camera survives strategic view")
	t.check_eq(city.garrison_view.groups.size(), garrison_count, "actual garrison remains visible on return")
	t.check_eq(_canon(game.state), before, "view switching changes no treasury, calendar, troops or RNG")
	session.free()


func test_switching_from_live_battle_joins_worker_and_preserves_pending_orders(t) -> void:
	var session := _session("live-switch")
	var panel := session.city.battle_panel
	panel.open()
	panel.begin(true)
	panel.start()
	OS.delay_msec(250)
	session.show_campaign()
	var paused := panel.host.snapshot()
	t.check(int(paused["tick"]) > 0, "runtime was advancing before leaving command")
	t.check(paused["paused"], "view switch pauses the battle before map reads shared state")
	var stopped := _canon(session.game.state)
	OS.delay_msec(150)
	t.check_eq(_canon(session.game.state), stopped, "hidden battle cannot advance a tick or RNG")
	var turn := int(session.game.state["turn"])
	session.game.end_turn()
	t.check_eq(int(session.game.state["turn"]), turn, "hidden unfinished battle still blocks campaign season")
	session.show_city()
	t.check(panel.visible and panel.host.snapshot()["paused"], "return reopens the same paused battle")
	t.check_eq(panel.host.snapshot()["tick"], paused["tick"], "reentry does not replay or catch up hidden time")
	panel.dismiss_session()
	session.free()


func test_city_and_map_seasons_share_training_calendar_and_chronicle(t) -> void:
	var city_session := _session("city-season")
	var map_session := _session("map-season")
	for session in [city_session, map_session]:
		t.check(session.game.city_queue_unit("latium", "roman_allied_bowmen", true), "actual bowmen enter the civic training queue")
	var initial_turn := int(city_session.game.state["turn"])
	city_session.city.advance_season()
	map_session.show_campaign()
	map_session.campaign.playback_enabled = false
	map_session.campaign._end_turn()
	t.check_eq(int(city_session.game.state["turn"]), initial_turn + 1, "city advances the actual campaign season")
	t.check_eq(_canon(city_session.game.state), _canon(map_session.game.state), "either view advances identical civic work, training, AI, calendar, RNG and history")
	t.check_eq(_canon(city_session.game.city_campaign_status("latium")), _canon(map_session.game.city_campaign_status("latium")), "timeline is a view of the shared historical state")
	city_session.free()
	map_session.free()


func test_cross_view_save_load_replaces_shared_state_and_clears_stale_presentations(t) -> void:
	var session := _session("cross-save")
	var game := session.game
	session.city.perform_action("repair_streets")
	session.city.save_city()
	var saved := _canon(SaveGame.read_file(session.save_path))
	session.show_campaign()
	session.campaign.selected_agent = "obsolete-agent"
	session.campaign._day_beats = [{"kind": "obsolete-event"}]
	session.campaign._treasury_ticking = true
	game.city_advance_day("latium")
	session.campaign._load_game()
	t.check_eq(_canon(game.state), saved, "campaign loads the exact city save into the shared facade")
	t.check_eq(session.campaign.selected_agent, "", "shared load clears obsolete campaign selection")
	t.check(not session.campaign._treasury_ticking, "shared load clears obsolete treasury animation")
	t.check(session.city.game == game and session.campaign.game == game, "load never creates a competing game")
	session.campaign._save_game()
	session.show_city()
	game.city_advance_day("latium")
	session.city.load_city()
	t.check_eq(_canon(game.state), saved, "city loads the campaign's common save")
	t.check_eq(_canon(session.campaign._day_beats), _canon(game.day_beats()), "inactive campaign presentation also sees the loaded journal")
	session.free()


func test_ready_siege_routes_through_session_and_commits_real_casualties_once(t) -> void:
	var game := _ready_siege()
	game.state["settlements"]["campania"]["owner"] = "senate"
	game.state["settlements"]["latium"]["garrison"] = [{"template": "roman_town_watch",
		"experience": 0, "strength_pct": 10, "weapon": 0, "armor": 0}]
	game.state["armies"]["army_roma_session_invader"]["units"] = []
	for card in range(4):
		game.state["armies"]["army_roma_session_invader"]["units"].append({"template": "gallic_long_swords",
			"experience": 0, "strength_pct": 100, "weapon": 0, "armor": 0})
	var session := _session("real-siege", game, "campaign")
	_synchronous_signal(session.campaign, "city_requested")
	var turn := int(game.state["turn"])
	session.campaign._end_turn()
	t.check_eq(session.active_view, "city", "map season action routes the awaited siege into the same session")
	t.check(session.city.battle_panel.visible, "ready siege opens real command surface")
	t.check_eq(int(game.state["turn"]), turn, "routing defense cannot advance the calendar")
	t.check(game.city_battle_begin("latium", false)["ok"], "actual campaign siege begins with existing rosters")
	t.check(game.city_battle_start("latium")["ok"], "actual campaign siege starts")
	for tick in range(int(CityBattleSim.rules(game.data)["maximum_ms"]) / int(CityBattleSim.rules(game.data)["tick_ms"]) + 1):
		if game.city_battle_status("latium").get("phase", "") == "finished":
			break
		game.city_battle_step("latium")
	t.check(game.state["city_battles"]["latium"]["committed"], "real battle passes its result through the campaign resolver")
	t.check_eq(game.state["settlements"]["latium"]["owner"], "gaul", "real defense loss transfers ownership")
	var result := _canon(game.state)
	game.city_battle_step("latium")
	t.check_eq(_canon(game.state), result, "repeated finished step cannot reapply casualties or capture")
	session.show_campaign()
	session.campaign._save_game()
	session.show_city()
	game.state["factions"]["senate"]["treasury"] += 37
	session.city.load_city()
	t.check_eq(_canon(game.state), _canon(SaveGame.read_file(session.save_path)), "foreign-owned Roma's retained report still loads the continuing campaign")
	t.check_eq(game.city_battle_status("latium")["phase"], "finished", "save/load retains the readable defeat report")
	session.show_campaign()
	t.check(session.campaign.visible, "loss can return to the surviving campaign")
	var completed_turn := int(game.state["turn"])
	game.end_turn()
	t.check_eq(int(game.state["turn"]), completed_turn + 1, "finished loss report cannot lock the campaign calendar")
	session.free()
