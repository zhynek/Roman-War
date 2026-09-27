extends SceneTree
## Rendered integration of the continuing Roma campaign and live command view.
## Uses isolated storage and writes screenshots only outside the repository.
var session: CampaignSession
var failed := false
var out := "/tmp/roman-war-roma-campaign"


func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War Roma Session QA/%d" % OS.get_process_id())
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
	var game := Game.new_campaign("senate", 42, "medium", "long", false)
	session = CampaignSession.create(game, "city", "user://roma-session-render.json")
	root.add_child(session)
	await _frames(12)
	var city := session.city
	_check(city.game == game and city.shared_session, "Roma begins in the ongoing campaign")
	await _shot("00-roma-campaign-city")
	var city_identity := city.get_instance_id()
	var position := city.player.position
	await _click_text(city.command_bar, city.w("campaign_map"))
	_check(session.active_view == "campaign" and session.campaign.game == game, "actual map button enters the same campaign")
	await _shot("01-strategic-map")
	session.show_city()
	await _frames(8)
	_check(session.city.get_instance_id() == city_identity and city.player.position == position, "city and walking position survive map roundtrip")

	# Recruit from the actual barracks; a campaign season must finish civic
	# training once, then include that real formation in the city and battle.
	var initial_garrison: int = game.state["settlements"]["latium"]["garrison"].size()
	city.open_drawer("barracks")
	city._choose_dossier_tab("troops")
	var recruit := _find_button(city.drawer_body, city.w("troops_recruit") % game.data.units["roman_allied_bowmen"]["name"])
	_check(recruit != null and not recruit.disabled, "actual barracks offers eligible bowmen")
	if recruit != null:
		await city._scroll_to_control(recruit)
		await _click(recruit)
	city.drawer.hide()
	var turn := int(game.state["turn"])
	await _click(city.season_button)
	_check(int(game.state["turn"]) == turn + 1, "city season button runs the actual campaign calendar")
	_check(game.state["settlements"]["latium"]["garrison"].size() == initial_garrison + 1, "season finishes real civic training exactly once")
	_check(city.campaign_panel.visible and game.city_campaign_status("latium")["history"].size() >= 2, "timeline exposes the actual historical campaign")
	await _shot("02-campaign-calendar")
	await _click_text(city.campaign_panel, city.w("calendar_tab_history"))
	await _shot("03-campaign-history")
	await _click_text(city.campaign_panel, city.w("calendar_resume"))
	city.save_city()
	var saved := _canon(SaveGame.read_file(session.save_path))
	session.show_campaign()
	game.city_advance_day("latium")
	session.campaign._load_game()
	_check(_canon(game.state) == saved, "map loads the common save written inside Roma")
	session.show_city()
	await _frames(8)
	_check(city.garrison_view.groups.size() == initial_garrison + 1, "retained city displays the loaded trained army")

	# Exercise live pointer selection and camera transforms over the shared
	# rendered city. The battle host owns Game while running; use snapshots.
	await _click(city.battle_button)
	var panel := city.battle_panel
	await _click(panel.practice_button)
	await _frames(10)
	var rectangle := _defender_rectangle(panel)
	_check(rectangle.size.x > 6 and rectangle.size.y > 6, "drawn defender anchors are inside the command viewport")
	await _drag(rectangle.position, rectangle.end, MOUSE_BUTTON_LEFT, false, "04-marquee-held")
	var selected := panel._selection()
	_check(selected.size() >= 2, "real drag marquee selects multiple friendly formations")
	for id in selected:
		_check(String(id).begins_with("defender_"), "marquee never selects enemy roster")
	await _shot("04-marquee-deployment")
	var span := panel.camera_rig.target_span
	var camera_at := panel.battle_rect().get_center()
	await _click_point(camera_at, MOUSE_BUTTON_WHEEL_UP)
	_check(panel.camera_rig.target_span < span, "wheel zoom changes the actual tactical camera")
	var focus := panel.camera_rig.target_focus
	await _drag(camera_at, camera_at + Vector2(72, 28), MOUSE_BUTTON_MIDDLE)
	_check(panel.camera_rig.target_focus != focus, "middle drag pans actual city camera")
	var yaw := panel.camera_rig.target_yaw
	await _drag(camera_at, camera_at + Vector2(72, 28), MOUSE_BUTTON_MIDDLE, true)
	_check(not is_equal_approx(panel.camera_rig.target_yaw, yaw), "Alt-middle drag orbits actual city camera")
	await _frames(14)
	await _shot("05-camera-orbit-zoom")
	await _click(panel.inspect_button)
	await _frames(20)
	await _shot("05-camera-close-1280")
	root.size = Vector2i(1600, 900)
	await _frames(20)
	await _shot("05-camera-close-1600")
	root.size = Vector2i(1280, 800)
	await _frames(10)
	panel.show_overview()
	await _frames(16)
	await _click(panel.start_button)
	await create_timer(0.45).timeout
	panel.refresh()
	_check(int(panel.host.snapshot()["tick"]) > 0, "battle runs continuously in the command view")
	rectangle = _defender_rectangle(panel)
	await _drag(rectangle.position, rectangle.end)
	_check(panel._selection().size() >= 2, "marquee also works during live simulation")
	await _click(panel.order_buttons["attack_move"])
	await _click_point(panel.plan.global_position + panel.plan.map_point(Vector2(0, 59)), MOUSE_BUTTON_RIGHT)
	var commanded := panel.host.snapshot()
	for formation in commanded["formations"]:
		if panel._selection().has(formation["id"]):
			_check(formation["order"] == "attack_move", "group ground gesture issues a live formation order")
	await _shot("06-live-group-command")
	await _click(panel.campaign_map_button)
	var paused := panel.host.snapshot()
	var paused_state := _canon(game.state)
	await create_timer(0.25).timeout
	_check(paused["paused"] and _canon(game.state) == paused_state, "map transition joins the battle worker and prevents hidden simulation")
	await _shot("07-map-with-paused-battle")
	session.show_city()
	await _frames(8)
	_check(panel.visible and panel.host.snapshot()["tick"] == paused["tick"], "city returns to the exact suspended battle")
	await _click(panel.save_button)
	city.load_city()
	await _frames(8)
	_check(panel.visible and panel.host.snapshot()["paused"] and panel.host.snapshot()["tick"] == paused["tick"], "common save restores the exact paused live battle")
	panel.dismiss_session()
	await _frames(8)
	_check(not game.city_battle_status("latium")["active"], "practice closes without changing campaign troops")

	# A real siege fixture exercises shared routing and the ordinary capture
	# resolver. Advance the deterministic engine with its worker stopped so
	# this regression does not need six minutes of wall-clock battle time.
	_install_real_siege(game)
	session.show_campaign()
	session.campaign._end_turn()
	await _frames(8)
	_check(session.active_view == "city" and panel.visible, "real ready siege interrupts campaign season and opens command")
	await _click(panel.defend_button)
	await _click(panel.start_button)
	panel.host.stop()
	var battle_limit := int(CityBattleSim.rules(game.data)["maximum_ms"]) / int(CityBattleSim.rules(game.data)["tick_ms"]) + 1
	var captured_street := false
	for index in range(battle_limit):
		if game.city_battle_status("latium").get("phase", "") == "finished":
			break
		game.city_battle_step("latium")
		if not captured_street and game.state["city_battles"]["latium"]["gate_integrity"] <= 0:
			panel.refresh()
			await _frames(4)
			await _shot("08-real-gate-breach")
			captured_street = true
	panel.refresh()
	_check(game.state["city_battles"]["latium"]["committed"], "real battle applies ordinary campaign aftermath")
	_check(game.state["settlements"]["latium"]["owner"] == "gaul", "actual defense loss transfers Roma")
	var committed := _canon(game.state)
	game.city_battle_step("latium")
	_check(_canon(game.state) == committed, "finished result applies casualties and capture only once")
	await _shot("09-real-battle-report")
	await _click(panel.return_button)
	_check(session.active_view == "campaign", "closing the defeat report returns directly to the surviving campaign")
	await _frames(8)
	await _shot("10-campaign-after-roma-loss")
	_check(session.campaign.visible and game.state["settlements"]["campania"]["owner"] == "senate", "surviving campaign remains accessible after loss")
	print("ROMA CAMPAIGN PLAYTEST ", "FAILED" if failed else "PASSED", " · ", out)
	session.free()
	quit(1 if failed else 0)


func _install_real_siege(game: Game) -> void:
	game.state["settlements"]["campania"]["owner"] = "senate"
	game.state["settlements"]["latium"]["garrison"] = [{"template": "roman_town_watch", "experience": 0, "strength_pct": 10, "weapon": 0, "armor": 0}]
	var troops: Array = []
	for index in range(4):
		troops.append({"template": "gallic_long_swords", "experience": 0, "strength_pct": 100, "weapon": 0, "armor": 0})
	game.state["armies"]["army_roma_render_invader"] = {"owner": "gaul", "region": "latium", "general": null, "movement_left": 0.0, "forced_march": false, "units": troops}
	DiplomacyRules.declare_war(game.data, game.state, "gaul", "senate")
	game.state["settlements"]["latium"]["siege"] = {"besieger": "army_roma_render_invader", "turns": 3, "equipment_ready": true}


func _defender_rectangle(panel: RomaCityBattlePanel) -> Rect2:
	var result := Rect2()
	var first := true
	for formation in panel.snapshot.get("formations", []):
		if formation["side"] != "defender" or not CityBattleSim.active(formation):
			continue
		var point := panel.formation_screen_point(formation["id"])
		if not panel.battle_rect().grow(-12).has_point(point):
			continue
		if first:
			result = Rect2(point, Vector2.ZERO)
			first = false
		else:
			result = result.expand(point)
	return result.grow(9).intersection(panel.battle_rect().grow(-1))


func _find_button(node: Node, label: String) -> Button:
	if node is Button and node.text == label:
		return node
	for child in node.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _click_text(node: Node, label: String) -> void:
	var button := _find_button(node, label)
	_check(button != null, "visible command exists: " + label)
	if button != null:
		await _click(button)


func _click(control: Control) -> void:
	await _frames(2)
	_check(control.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(control.get_global_rect()), "command fits window: " + str(control.get("text")))
	await _click_point(control.get_global_rect().get_center())


func _click_point(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event)
		await _frames(2)
	await _frames(4)


func _drag(from: Vector2, to: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, alt: bool = false, held_capture: String = "") -> void:
	Input.warp_mouse(from)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.alt_pressed = alt
	press.position = from
	press.global_position = from
	root.push_input(press)
	await _frames(2)
	var previous := from
	for step in range(1, 5):
		var at := from.lerp(to, float(step) / 4.0)
		Input.warp_mouse(at)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.relative = at - previous
		motion.alt_pressed = alt
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
		root.push_input(motion)
		previous = at
		await _frames(2)
	if held_capture != "":
		await _shot(held_capture)
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.alt_pressed = alt
	release.position = to
	release.global_position = to
	root.push_input(release)
	await _frames(5)


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	failed = failed or not ok


func _canon(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))
