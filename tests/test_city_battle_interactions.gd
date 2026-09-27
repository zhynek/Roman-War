extends RefCounted

func _city() -> RomaCityScreen:
	var city := RomaCityScreen.new()
	city.standalone = false
	city.game = Game.new_campaign("senate", 42, "medium", "long", false)
	(Engine.get_main_loop() as SceneTree).root.add_child(city)
	city.battle_panel.open()
	city.battle_panel.begin(true)
	return city

func _press(view: RomaCityBattlePanel, point: Vector2, additive: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	event.shift_pressed = additive
	view._gui_input(event)

func _release(view: RomaCityBattlePanel, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	view._gui_input(event)

func test_drag_marquee_adds_defenders_without_issuing_orders(t) -> void:
	var city := _city()
	var view := city.battle_panel
	var original := JSON.stringify(city.game.state)
	view.clear_selection()
	var area := view.battle_rect().grow(-12)
	_press(view, area.position)
	view._gesture_motion(area.end)
	t.check(view._marquee, "a deliberate drag crosses the selection threshold")
	t.check(view._selection().is_empty(), "marquee does not change selection before release")
	_release(view, area.end)
	t.check(view._selection().size() > 1, "dragging over the visible ranks selects multiple defenders")
	for id in view._selection():
		t.check(view._is_defender(String(id)), "marquee cannot select enemy troops")
	var chosen := view._selection().duplicate()
	view.select_formation(String(chosen[0]))
	var second := view.formation_screen_point(String(chosen[1]))
	_press(view, second - Vector2(7, 7), true)
	view._gesture_motion(second + Vector2(7, 7))
	_release(view, second + Vector2(7, 7))
	t.check(view._selection().has(chosen[0]) and view._selection().has(chosen[1]), "Shift marquee adds its defenders to the previous selection")
	t.check_eq(JSON.stringify(city.game.state), original, "all selection gestures are detached presentation and issue no simulation commands")
	city.free()

func test_click_threshold_and_hud_release_prevent_accidental_orders(t) -> void:
	var city := _city()
	var view := city.battle_panel
	var id := view.selected
	var point := view.formation_screen_point(id)
	var original := JSON.stringify(city.game.state)
	_press(view, point)
	view._gesture_motion(point + Vector2(2, 1))
	t.check(not view._marquee, "small pointer jitter remains a click")
	_release(view, point + Vector2(2, 1))
	t.check_eq(view.selected, id, "clicking a visible defender selects its exact drawn marker")
	var prior := view._selection().duplicate()
	_press(view, view.battle_rect().get_center())
	view._gesture_motion(Vector2(35, 140))
	_release(view, Vector2(35, 140))
	t.check_eq(view._selection(), prior, "release on the roster cancels a world marquee")
	t.check(not view._selection_press and not view._marquee, "cancelled input leaves no stuck drag")
	t.check_eq(JSON.stringify(city.game.state), original, "clicks and cancelled drags cannot move formations")
	city.free()

func test_camera_transitions_and_plan_navigation_do_not_touch_battle(t) -> void:
	var city := _city()
	var view := city.battle_panel
	var original := JSON.stringify(city.game.state)
	var from := city.survey_camera.transform
	view.follow_selection()
	view.camera_rig.update(0.016, view._selection_center())
	t.check(city.survey_camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "the live city supports a perspective close view")
	t.check(view.camera_rig.span > view.camera_rig.target_span, "aerial-to-close framing interpolates instead of snapping")
	t.check(city.survey_camera.transform != from, "the close-view transition moves the actual city camera")
	view.camera_rig.orbit(Vector2(90, -35))
	view.camera_rig.pan_view(Vector2(1, -1), 0.25)
	view.camera_rig.zoom(0.65)
	view.camera_rig.update(0.1)
	t.check(not view.camera_rig.following, "manual camera input releases selection follow")
	view.plan.size = Vector2(250, 320)
	var map_at: Vector2 = view.plan.map_point(Vector2(30, -40))
	view.plan.center_camera(map_at)
	t.check(view.camera_rig.target_focus.distance_to(Vector3(30, 0.6, -40)) < 0.001, "the plan uses the exact authored world coordinates for navigation")
	view.show_overview()
	t.check_eq(view.camera_rig.target_span, 114.0, "aerial view always provides a reliable way back from close inspection")
	t.check_eq(JSON.stringify(city.game.state), original, "zoom, orbit, follow and plan navigation change no battle state")
	view.close()
	t.check(city.survey_camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "returning to town restores its original camera projection")
	city.free()

func test_multi_selection_ground_commands_use_one_serialized_host_call(t) -> void:
	var city := _city()
	var view := city.battle_panel
	view.select_rectangle(view.battle_rect())
	var selected_before := view._selection().duplicate()
	t.check(selected_before.size() > 1, "the test exercises a real group order")
	view.command_ground(Vector2(0, 45))
	var arrived := 0
	for formation in view.snapshot["formations"]:
		if selected_before.has(formation["id"]):
			arrived += 1
			t.check_eq(formation["order"], "hold", "group deployment remains paused and ready for live battle")
			t.check(Vector2(formation["position"][0], formation["position"][1]).distance_to(Vector2(0, 4500)) < 1800, "all selected formations deploy in the commanded area")
	t.check_eq(arrived, selected_before.size(), "one group command handles the full selected platoon set")
	city.free()
