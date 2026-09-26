extends SceneTree
## Full playable-route QA: actions use the campaign facade/buttons. Only visual
## playback is scrubbed for repeatable screenshots. No state moves in frames.
var screen: CampaignScreen
var failed := false
var output := "/tmp/roman-campaign-route-qa"

func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War Route QA/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			output = arg.trim_prefix("out_dir=")
	_run.call_deferred()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 1000)
	root.grab_focus()
	DirAccess.make_dir_recursive_absolute(output)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	screen = CampaignScreen.create(CampaignRoute.build())
	holder.add_child(screen)
	screen.playback_enabled = false
	var game := screen.game
	var config: Dictionary = game.data.terrain_content["development_route"]
	var army := ""
	var enemy := ""
	for id in game.state["armies"]:
		if game.state["armies"][id]["owner"] == config["player"]:
			army = id
		if game.state["armies"][id]["owner"] == config["contact_owner"] and game.state["armies"][id]["region"] == config["contact_region"]:
			enemy = id
	screen.select_force("army", army)
	var view := screen.map_view
	view.set_zoom_level(7)
	view.focus_force()
	await shot("01-forest-column")
	check(game.visible_regions().has(config["contact_region"]) and not game.army_is_visible(enemy), "charted forest conceals the real enemy sentry")
	check(not view.army_visuals.has(enemy) and not view.landscape.armies.has(enemy), "no hidden enemy mesh or miniature is constructed")
	var same_state := JSON.stringify(game.state)
	view.set_realism_enabled(false)
	await shot("02-classic-same-column")
	view.set_realism_enabled(true)
	check(JSON.stringify(game.state) == same_state, "classic comparison preserves the same state and RNG")
	var route: Array = config["regions"]
	for i in range(1, route.size()):
		var destination := String(route[i])
		var origin := String(game.state["armies"][army]["region"])
		if MovementRules.step_cost(game.data, game.state, destination, origin) > float(game.state["armies"][army]["movement_left"]):
			var saved := SaveGame.from_json(SaveGame.to_json(game.state))
			game.end_turn()
			TurnEngine.end_turn(game.data, saved, AutoResolver.new())
			check(JSON.stringify(JSON.parse_string(JSON.stringify(game.state))) == JSON.stringify(JSON.parse_string(JSON.stringify(saved))), "season and save replay stay identical")
			screen.refresh()
			screen.select_force("army", army)
		view.set_zoom_level(4.5)
		var midpoint := (view.world_pos(game.data.regions[origin]) + view.world_pos(game.data.regions[destination])) * 0.5
		view._camera_offset = -midpoint + view.size / (2 * view._zoom)
		screen._planning_order = true
		screen._pinned_target = destination
		var before := JSON.stringify(game.state)
		screen._preview_destination(destination)
		var cost := float(game.army_order_preview(army, destination)["cost"])
		check(JSON.stringify(game.state) == before, "waypoint planning does not mutate state")
		await shot("%02d-plan-%s" % [i * 3, destination])
		var movement := float(game.state["armies"][army]["movement_left"])
		screen.command_bar.issue.pressed.emit()
		check(game.state["armies"][army]["region"] == destination, "issue order reaches " + destination)
		check(is_equal_approx(movement - float(game.state["armies"][army]["movement_left"]), cost), "actual cost equals the displayed quote")
		var after := JSON.stringify(game.state)
		if view._marches.has(army):
			var march: Dictionary = view._marches[army]
			# Freeze only the presentation sampler at the actual crossing.
			var center := midpoint
			for site in view.landscape.crossing_sites:
				if site.key == TerrainRules.edge_key(origin, destination):
					center = site.center
					print("crossing site ", site.key, " ", site.kind, " center ", center, " ground ", view.landscape.ground(center))
			var distance := 0.0
			var best_distance := 0.0
			var nearest := INF
			var points: PackedVector2Array = march["points"]
			for j in range(points.size() - 1):
				var p := Geometry2D.get_closest_point_to_segment(center, points[j], points[j + 1])
				if p.distance_to(center) < nearest:
					nearest = p.distance_to(center)
					best_distance = distance + points[j].distance_to(p)
				distance += points[j].distance_to(points[j + 1])
			march["distance"] = best_distance
			march["speed"] = 0.0
			var sample := MapView.sample_route(points, best_distance)
			march["position"] = sample["position"]
			march["direction"] = sample["direction"]
			view.set_zoom_level(9)
			view.focus_force()
			await shot("%02d-crossing-%s" % [i * 3 + 1, destination])
			check(JSON.stringify(game.state) == after, "crossing playback and maximum zoom preserve full state and RNG")
		view.finish_marches()
		view.set_zoom_level(7)
		view.focus_force()
		await shot("%02d-arrival-%s" % [i * 3 + 2, destination])
		check(view.landscape.pick_region(view.to_screen(view.world_pos(game.data.regions[destination]))) == destination, "rendered terrain picking matches " + destination)
		if destination == "noricum":
			check(not game.army_is_visible(enemy), "forest sentry is still hidden before the patrol")
			view.center_on(config["contact_region"])
			await shot("15-concealed-forest")
			if ReconRules.patrol_quote(game.data, game.state, army)["ok"]:
				screen.command_bar.patrol.pressed.emit()
			else:
				game.end_turn()
				screen.refresh()
				screen.command_bar.patrol.pressed.emit()
			check(game.army_is_visible(enemy) and view.landscape.armies.has(enemy), "paid patrol reveals a generic enemy formation in the live map")
			check(view.army_visuals.get(enemy, {}).get("classes", []).is_empty(), "revealed enemy representation never reads its hidden roster")
			await shot("16-patrol-reveal")
			view.set_realism_enabled(false)
			await shot("17-classic-reveal")
			view.set_realism_enabled(true)
	view.set_zoom_level(MapView.ZOOM_MAX)
	view.focus_force()
	await shot("18-final-maximum-detail")
	print("campaign route playtest: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	failed = failed or not ok

func shot(name: String) -> void:
	for i in range(8):
		await process_frame
		RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
	print("saved ", name)
