extends RefCounted
## Retained UI regressions: render the live shared state after seasons, loads
## and defeat, and do not replay a journal when no new season was resolved.


func _session(name: String, game: Game = null) -> CampaignSession:
	if game == null:
		game = Game.new_campaign("senate", 42, "medium", "long", false)
	var session := CampaignSession.create(game, "city", "user://roma-regression-%s.json" % name)
	(Engine.get_main_loop() as SceneTree).root.add_child(session)
	return session


func _texts(node: Node) -> Array:
	var texts: Array = []
	if node is Label:
		texts.append((node as Label).text)
	elif node is RichTextLabel:
		texts.append((node as RichTextLabel).text)
	elif node is Button:
		texts.append((node as Button).text)
	for child in node.get_children():
		texts.append_array(_texts(child))
	return texts


func _canon(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))


func _open_troops(city: RomaCityScreen) -> void:
	city.open_drawer("barracks")
	city._choose_dossier_tab("troops")


func _queue_line(city: RomaCityScreen, days: int) -> String:
	return city.w("troops_city_queue") % [city.game.data.units["roman_allied_bowmen"]["name"], days]


func test_return_from_map_refreshes_open_troop_queue_and_completed_garrison(t) -> void:
	var session := _session("season-drawer")
	var city := session.city
	t.check(session.game.city_queue_unit("latium", "roman_allied_bowmen", true), "bowmen enter the actual civic training queue")
	_open_troops(city)
	var queued := _queue_line(city, 3)
	var unit_name: String = session.game.data.units["roman_allied_bowmen"]["name"]
	var shown_before := _texts(city.drawer_body).count(unit_name)
	t.check(_texts(city.drawer_body).has(queued), "open barracks shows the pending three-day training job")
	session.show_campaign()
	session.campaign.playback_enabled = false
	session.campaign._end_turn()
	t.check(session.game.state["settlements"]["latium"]["recruitment_queue"].is_empty(), "the strategic season completes the real job")
	session.show_city()
	t.check(session.city == city and city.drawer.visible, "return retains the same open barracks drawer")
	var displayed := _texts(city.drawer_body)
	t.check(not displayed.has(queued), "return removes the stale pending-job label")
	t.check_eq(displayed.count(unit_name), shown_before + 1, "return renders the newly trained bowmen in the actual garrison")
	session.free()


func test_map_load_refreshes_the_hidden_city_drawer_before_reentry(t) -> void:
	var session := _session("loaded-drawer")
	var city := session.city
	t.check(session.game.city_queue_unit("latium", "roman_allied_bowmen", true), "training job can be saved mid-progress")
	_open_troops(city)
	t.check(session.game.save_to(session.save_path), "shared save retains the original three-day job")
	t.check(session.game.city_advance_day("latium"), "one real civic day progresses training")
	city.refresh_city()
	city._refresh_drawer()
	t.check(_texts(city.drawer_body).has(_queue_line(city, 2)), "drawer displays the more recent two-day progress before load")
	session.show_campaign()
	session.campaign._load_game()
	var displayed := _texts(city.drawer_body)
	t.check(not city.visible and city.drawer.visible, "loaded city remains suspended with its retained drawer")
	t.check(displayed.has(_queue_line(city, 3)), "map load refreshes the hidden drawer from the restored save")
	t.check(not displayed.has(_queue_line(city, 2)), "map load removes progress belonging to the replaced state")
	t.check_eq(session.game.state["settlements"]["latium"]["recruitment_queue"][0]["city_days_left"], 3, "visible restored queue agrees with the shared model")
	session.free()


func test_foreign_city_construction_panel_never_renders_enemy_queue(t) -> void:
	var session := _session("foreign-construction")
	var city := session.city
	var settlement: Dictionary = session.game.state["settlements"]["latium"]
	# Retained city presentation can outlive conquest. Vary the foreign data
	# behind that view: neither its contents nor its length may be disclosed.
	settlement["owner"] = "gaul"
	settlement["construction_queue"] = [{"chain": "roman_government", "target_level": 2, "turns_left": 47}]
	city.campaign_panel.tab = "build"
	city.campaign_panel.present()
	var first := _texts(city.campaign_panel.body)
	var secret := city.w("calendar_job") % [session.game.data.chains["roman_government"]["name"], 47]
	t.check(first.has(city.w("calendar_lost")), "former owner is told that civic command was lost")
	t.check(not first.has(secret), "foreign construction name and remaining time are never rendered")
	settlement["construction_queue"] = []
	city.campaign_panel.present()
	t.check_eq(_texts(city.campaign_panel.body), first, "foreign queue contents and emptiness produce the same public panel")
	session.free()


func test_closing_actual_defeat_report_returns_to_shared_campaign(t) -> void:
	var game := Game.new_campaign("senate", 42, "medium", "long", false)
	game.state["settlements"]["campania"]["owner"] = "senate"
	game.state["settlements"]["latium"]["garrison"] = [{"template": "roman_town_watch", "experience": 0, "strength_pct": 10, "weapon": 0, "armor": 0}]
	game.state["armies"]["roma_regression_invader"] = {"owner": "gaul", "region": "latium", "general": null,
		"movement_left": 0.0, "forced_march": false, "units": []}
	for card in range(4):
		game.state["armies"]["roma_regression_invader"]["units"].append({"template": "gallic_long_swords", "experience": 0, "strength_pct": 100, "weapon": 0, "armor": 0})
	DiplomacyRules.declare_war(game.data, game.state, "gaul", "senate")
	game.state["settlements"]["latium"]["siege"] = {"besieger": "roma_regression_invader", "turns": 3, "equipment_ready": true}
	var session := _session("defeat-close", game)
	var panel := session.city.battle_panel
	t.check(panel.visible, "shared city opens the pending defense")
	t.check(game.city_battle_begin("latium", false)["ok"], "defense reserves the real rosters")
	t.check(game.city_battle_start("latium")["ok"], "defense starts through the campaign protocol")
	# Do not start a presentation worker: this fixture resolves exact fixed
	# steps synchronously and tests the UI path only after real capture.
	for tick in range(int(CityBattleSim.rules(game.data)["maximum_ms"]) / int(CityBattleSim.rules(game.data)["tick_ms"]) + 1):
		if game.city_battle_status("latium").get("phase", "") == "finished":
			break
		game.city_battle_step("latium")
	panel.refresh()
	t.check_eq(game.state["settlements"]["latium"]["owner"], "gaul", "the tactical result actually transfers Roma")
	t.check_eq(panel.snapshot["phase"], "finished", "the city displays its completed defeat report")
	panel.host.stop()
	var before := _canon(game.state)
	# All tests execute in one frame; invoke the same production callback now
	# so no deferred callback outlives this fixture.
	for connection in panel.get_signal_connection_list("closed"):
		var callback: Callable = connection["callable"]
		panel.closed.disconnect(callback)
		panel.closed.connect(callback)
	panel.close()
	t.check_eq(session.active_view, "campaign", "closing defeat returns directly to the surviving campaign")
	t.check(session.campaign.visible and not session.city.visible, "lost city cannot remain the command surface")
	t.check(session.campaign.game == game, "return keeps the same campaign facade and aftermath")
	t.check_eq(_canon(game.state), before, "closing a report cannot resolve capture or casualties again")
	session.free()


func test_refused_campaign_season_cannot_replay_previous_journal(t) -> void:
	var session := _session("refused-replay")
	session.game.end_turn()
	t.check(not session.game.day_beats().is_empty(), "fixture has a genuine completed season journal to accidentally replay")
	session.show_campaign()
	var campaign := session.campaign
	campaign.playback_enabled = true
	session.game.state["winner"] = "senate"
	campaign._victory_shown = true
	var before := _canon(session.game.state)
	var log_before := campaign.report_log.get_parsed_text()
	campaign._end_turn()
	t.check_eq(_canon(session.game.state), before, "refused season leaves the finished campaign unchanged")
	t.check(not campaign.turn_sequence.is_playing(), "refused season cannot replay the previous journal as a new day")
	t.check(not campaign.dispatch_panel.visible, "refused season cannot reopen yesterday's dispatch")
	var refusal: String = session.game.data.effects_glossary["city_view"]["reason_campaign_finished"]
	t.check_eq(campaign.report_log.get_parsed_text(), log_before + refusal + "\n", "only the refusal is logged, without duplicate season history")
	session.free()
