extends RefCounted


func test_city_and_country_presets_preserve_campaign_and_pick_positions(t) -> void:
	var screen := _screen()
	var view := screen.map_view
	var region := String(screen.game.state["armies"][screen.selected_army]["region"])
	var before := screen.game.state.duplicate(true)
	view.focus_settlement(region)
	t.check_eq(screen.selected_army, "", "focusing a city cancels force selection instead of issuing a march")
	t.check_eq(view._zoom, MapView.CITY_ZOOM, "city focus opens the architectural scale")
	var anchor := view.world_pos(screen.game.data.regions[region])
	t.check_near(view.to_screen(anchor).distance_to(view.size * 0.5), 0, 0.01, "settlement is centered at architectural scale")
	for zoom in [1.0, 3.5, 12.0, 24.0, MapView.ZOOM_MAX]:
		view.set_zoom_level(zoom)
		t.check_eq(view._region_at(view.to_screen(anchor)), region, "the drawn city remains pickable at every scale")
	view.apply_zoom_preset("country")
	t.check(view._zoom <= 1.2, "country scale fits the known atlas")
	for known in view.known_cache:
		if view.geometry.cells.has(known):
			var bounds: Rect2 = view.geometry.cells[known]["bounds"]
			t.check(Rect2(Vector2.ZERO, view.size).has_point(view.to_screen(bounds.position)), "northwestern charted boundary fits country view")
			t.check(Rect2(Vector2.ZERO, view.size).has_point(view.to_screen(bounds.end)), "southeastern charted boundary fits country view")
	view.apply_zoom_preset("city")
	t.check_eq(view.selected_region, region, "city scale returns to the inspected settlement")
	t.check_eq(screen.game.state, before, "zooming and inspecting cannot advance rules, movement, time or RNG")
	screen.free()


func test_city_entry_is_explicit_and_only_available_for_owned_roma(t) -> void:
	var screen := _screen()
	var view := screen.map_view
	view.selected_region = "latium"
	t.check(not view.city_entry_button.visible, "foreign Roma does not offer street-level entry")
	var requested := []
	view.city_enter_requested.connect(func(): requested.append(true))
	view._request_city_entry()
	t.check(requested.is_empty(), "hidden entry command cannot request a foreign city")
	view.set_zoom_level(MapView.ZOOM_MAX)
	t.check(requested.is_empty(), "zooming inward never switches into another scene")
	view._zoom_at(Vector2(100, 100), -1)
	t.check_eq(view._zoom, MapView.ZOOM_MAX, "invalid gesture factors cannot corrupt the camera")
	screen.free()


func test_architectural_picking_uses_figures_and_camera_buttons_respect_modals(t) -> void:
	var screen := _screen()
	var view := screen.map_view
	var id := screen.selected_army
	view.set_zoom_level(MapView.ZOOM_MAX)
	var scale_by := float(view.army_visuals[id].get("scale", 1))
	var anchor := view.force_world_position(id)
	var figure := CampaignMiniatures.soldier_offset(0, view._visual_clock, false, Vector2.RIGHT)
	t.check(view._force_contains_point(id, view.to_screen(anchor + (figure + Vector2(0, -3)) * scale_by)), "a rendered figure can be picked at maximum zoom")
	t.check(not view._force_contains_point(id, view.to_screen(anchor + Vector2(14, 5) * scale_by)), "empty space beside the figures no longer selects a distant army")
	var before := screen.game.state.duplicate(true)
	var zoom := view._zoom
	var offset := view._camera_offset
	var button := view._camera_button("+", "", 12, func(): view.zoom_by(0.5))
	view.camera_input_enabled = false
	button.pressed.emit()
	view.apply_zoom_preset("country")
	var overview_click := InputEventMouseButton.new()
	overview_click.button_index = MOUSE_BUTTON_LEFT
	overview_click.pressed = true
	overview_click.position = Vector2(90, 55)
	view._overview._gui_input(overview_click)
	t.check_eq(view._zoom, zoom, "modal input barriers also cover camera buttons and scale presets")
	t.check_eq(view._camera_offset, offset, "the overview cannot pan through a modal input barrier")
	t.check_eq(screen.game.state, before, "blocked navigation cannot change the simulation")
	button.free()
	screen.free()


func _screen() -> CampaignScreen:
	var screen := CampaignScreen.create(Game.new_campaign("julii", 42))
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	screen.playback_enabled = false
	screen.map_view.size = Vector2(900, 600)
	var ids: Array = screen.game.state["armies"].keys()
	ids.sort()
	for id in ids:
		if screen.game.state["armies"][id]["owner"] == "julii":
			screen.select_force("army", id)
			break
	return screen


func _destination(screen: CampaignScreen) -> String:
	for id in screen.game.reachable_regions(screen.selected_army)["reach"]:
		var quote := screen.game.army_order_preview(screen.selected_army, id)
		if not quote.is_empty() and quote["action"] == "march" and quote["turns"] == 1:
			return id
	return ""


func test_click_plan_pin_cancel_and_issue(t) -> void:
	var screen := _screen()
	var game := screen.game
	var id := screen.selected_army
	var target := _destination(screen)
	t.check(target != "", "a march is available")
	var before := game.state.duplicate(true)
	screen.command_bar.choose.pressed.emit()
	screen._on_region_clicked(target)
	t.check_eq(screen.selected_army, id, "planning a destination retains the commander")
	t.check_eq(screen._pinned_target, target, "click pins the intended province")
	t.check_eq(game.state, before, "pinning moves no troops")
	screen._on_region_hovered("")
	t.check_eq(screen._pinned_target, target, "the quote survives moving to the order button")
	screen.deselect()
	t.check(not screen._planning_order, "Escape cancels planning")
	t.check_eq(screen.selected_army, id, "Escape retains the army")
	t.check_eq(game.state, before, "cancelling is inert")
	screen._begin_map_order()
	screen._on_region_clicked(target)
	screen.command_bar.issue.pressed.emit()
	t.check_eq(game.state["armies"][id]["region"], target, "issuing executes the route")
	var general = game.state["armies"][id]["general"]
	if general != null:
		t.check_eq(game.state["characters"][general]["location"], target, "the commander travels with his army")
	t.check(not screen._planning_order, "the command mode closes")
	screen.free()


func test_marching_positions_are_presentation_only_and_pickable(t) -> void:
	var screen := _screen()
	var view := screen.map_view
	view.set_zoom_level(3.5)
	var id := screen.selected_army
	var target := _destination(screen)
	t.check(target != "", "the army has somewhere to march")
	var start := view.force_world_position(id)
	screen._army_order(target)
	var after_order := screen.game.state.duplicate(true)
	t.check(view._marches.has(id), "a real move starts a column animation")
	t.check_eq(view.force_world_position(id), start, "the column starts at its previous position")
	view._advance_marches(0.3)
	var mid := view.force_world_position(id)
	t.check(mid.distance_to(start) > 1, "the formation moves along the road")
	t.check_eq(view._pick(view.to_screen(mid))["id"], id, "the animated formation can be selected where it is drawn")
	view._advance_marches(10)
	t.check(not view._marches.has(id), "the animation finishes")
	t.check_eq(screen.game.state, after_order, "rendering cannot alter campaign state or RNG")
	t.check_eq(view.geometry.region_at_world(view.force_world_position(id)), target, "the arriving camp sits on land in its destination")
	screen.free()


func test_reduced_motion_has_identical_rules_and_no_pending_animation(t) -> void:
	var screen := _screen()
	var id := screen.selected_army
	var target := _destination(screen)
	t.check(target != "", "a destination exists")
	screen.map_view.motion_enabled = false
	screen._army_order(target)
	t.check_eq(screen.game.state["armies"][id]["region"], target, "the move still executes")
	t.check(screen.map_view._marches.is_empty(), "reduced motion never starts playback")
	screen.free()


func test_pinch_zooms_about_the_fingers_and_manual_pan_releases_follow(t) -> void:
	var screen := _screen()
	var view := screen.map_view
	var gesture := InputEventMagnifyGesture.new()
	gesture.position = Vector2(250, 180)
	gesture.factor = 1.5
	var world := gesture.position / view._zoom - view._camera_offset
	view._gui_input(gesture)
	t.check_near(view.to_screen(world).distance_to(gesture.position), 0, 0.01, "pinch preserves the world beneath the fingers")
	view._follow_force = screen.selected_army
	view.pan_by(Vector2(20, 0))
	t.check_eq(view._follow_force, "", "manual navigation releases camera follow")
	screen.free()


func test_camera_motion_clears_stale_province_tooltip(t) -> void:
	var screen := _screen()
	var view := screen.map_view
	view._process(0.0)
	var before := screen.game.state.duplicate(true)
	view.hover_region = "etruria"
	view._show_tooltip()
	t.check(view.tooltip.visible, "a province tooltip is displayed before camera motion")
	view.center_on("apulia")
	view._process(0.5)
	t.check_eq(view.hover_region, "", "programmatic camera motion discards the old province")
	t.check(not view.tooltip.visible, "the old tooltip cannot remain over different ground")
	view._process(0.5)
	t.check(not view.tooltip.visible, "a stationary pointer does not reopen the stale tooltip")
	view._update_hover(view.to_screen(view.world_pos(screen.game.data.regions["apulia"])))
	view._process(0.5)
	t.check(view.tooltip.visible, "new pointer motion permits a fresh tooltip")
	t.check_eq(screen.game.state, before, "hover invalidation does not alter campaign state or RNG")
	screen.free()


func test_route_sampling_handles_bends_and_zero_length_segments(t) -> void:
	var points := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2(10, 0), Vector2(10, 20)])
	var sample := MapView.sample_route(points, 15)
	t.check_eq(sample["position"], Vector2(10, 5), "distance follows the corner, not a straight teleport")
	t.check_eq(sample["direction"], Vector2.DOWN, "the column faces down the second leg")
	t.check_eq(MapView.sample_route(points, 100)["position"], Vector2(10, 20), "overshoot clamps to arrival")


func test_planning_bar_fits_the_map_and_hidden_armies_have_no_miniatures(t) -> void:
	var screen := _screen()
	screen.command_bar.fit_to(Vector2(600, 400))
	t.check(screen.command_bar.size.x >= 500, "the command strip uses the available width")
	t.check(screen.command_bar.position.x + screen.command_bar.size.x <= 600, "it fits beside camera controls")
	for id in screen.map_view.army_visuals:
		t.check(screen.map_view.visible_cache.has(screen.game.state["armies"][id]["region"]), "no hidden army gets a miniature")
	for id in screen.map_view.army_visuals:
		if screen.game.state["armies"][id]["owner"] != "julii":
			t.check(screen.map_view.army_visuals[id]["classes"].is_empty(), "enemy composition stays private")
	screen.free()


func test_stale_pinned_quote_is_updated_before_execution(t) -> void:
	var screen := _screen()
	var id := screen.selected_army
	var target := _destination(screen)
	screen._begin_map_order()
	screen._on_region_clicked(target)
	var origin: String = screen.game.state["armies"][id]["region"]
	screen.game.state["armies"][id]["movement_left"] = 0.0
	screen._issue_map_order()
	t.check_eq(screen.game.state["armies"][id]["region"], origin, "a changed quote is not executed")
	t.check(screen._planning_order, "the updated quote remains available to review")
	t.check_eq(screen._order_preview["turns"], 2, "it now shows departure next season")
	t.check(not screen.game.state["armies"][id].has("march_path"), "no march has been silently queued")
	screen.free()


func test_arriving_armies_do_not_overlap_allied_coastal_forces(t) -> void:
	var screen := _screen()
	var id := screen.selected_army
	var target := _destination(screen)
	screen._army_order(target)
	screen.map_view.finish_marches()
	var at := screen.map_view.force_world_position(id)
	var others := 0
	for other in ForceRules.armies_in(screen.game.state, target):
		if other == id:
			continue
		others += 1
		t.check(at.distance_to(screen.map_view.force_world_position(other)) >= 25, "the visiting and resident formations have separate positions")
	t.check(others > 0, "the coastal playtest actually encounters a resident army")
	screen.free()


func test_map_orders_invest_neighbouring_walls_and_confirm_the_assault(t) -> void:
	var screen := _screen()
	var game := screen.game
	var id := screen.selected_army
	var origin: String = game.state["armies"][id]["region"]
	var target := ""
	for neighbour in game.data.regions[origin]["adjacent"]:
		var owner := String(game.state["settlements"][neighbour]["owner"])
		if owner == "senate" or game.data.factions[owner].get("is_roman_house", false):
			continue
		if ForceRules.armies_in(game.state, neighbour).is_empty():
			target = neighbour
			game.declare_war(owner)
			break
	t.check(target != "", "the real campaign has neighbouring foreign walls")
	if target == "":
		screen.free()
		return
	screen.refresh()
	screen.command_bar.choose.pressed.emit()
	screen._on_region_clicked(target)
	t.check_eq(screen._order_preview["action"], "siege", "planning identifies the walls")
	t.check(game.state["settlements"][target]["siege"] == null, "pinning has not invested them")
	screen.command_bar.issue.pressed.emit()
	t.check_eq(game.state["settlements"][target]["siege"]["besieger"], id, "issuing establishes the quoted siege")
	game.state["settlements"][target]["siege"]["equipment_ready"] = true
	MovementRules.reset_movement(game.data, game.state)
	screen.refresh()
	screen.command_bar.choose.pressed.emit()
	screen._on_region_clicked(target)
	t.check_eq(screen._order_preview["action"], "assault", "the map offers a ready assault in the same province")
	var before := game.state.duplicate(true)
	screen.command_bar.issue.pressed.emit()
	var confirmation: ConfirmationDialog
	for child in screen.get_children():
		if child is ConfirmationDialog:
			confirmation = child
	t.check(confirmation != null, "issuing opens the battle confirmation")
	t.check_eq(game.state, before, "battle waits for confirmation, preserving RNG")
	if confirmation != null:
		confirmation.confirmed.emit()
		t.check(screen.report_log.get_parsed_text().contains("Assault on"), "confirmed map orders resolve through the existing battle system")
	screen.free()
