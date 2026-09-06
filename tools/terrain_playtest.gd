extends SceneTree
## Expanded terrain/UX review. All captures and save slots live outside the repo.
var screen: CampaignScreen
var failed := false
var output := "/tmp/roman-terrain-review"

func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War Terrain QA/%d" % OS.get_process_id())
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
	screen = CampaignScreen.create(Game.new_campaign("julii", 42))
	holder.add_child(screen)
	screen.playback_enabled = false
	await frames(15)
	var view := screen.map_view
	check(view.landscape != null and view.realism_enabled, "live 3D terrain is the campaign default")
	var id := ""
	for army in screen.game.state["armies"]:
		if screen.game.state["armies"][army]["owner"] == "julii":
			id = army
			break
	screen.select_force("army", id)
	view.set_zoom_level(4.0)
	view.center_on("umbria")
	await frames(5)
	var before := JSON.stringify(screen.game.state)
	var landmark := view.world_pos(screen.game.data.regions["umbria"])
	check(view.to_screen(landmark).distance_to(view.landscape.camera.unproject_position(view.landscape.ground(landmark))) < 1.0, "labels use the actual terrain camera projection")
	check(view.landscape.pick_region(view.to_screen(landmark)) == "umbria", "surface picking selects the rendered region")
	await capture("01-live-campaign")
	check(JSON.stringify(screen.game.state) == before, "drawing and camera movement preserve the full simulation and RNG")
	view.set_realism_enabled(false)
	await capture("02-classic-comparison")
	view.set_realism_enabled(true)
	screen._pinned_target = "latium"
	screen._planning_order = true
	screen._preview_destination("latium")
	await capture("03-bridge-order")
	# Buying maps reveals geography, not live Egyptian armies.
	var dialog := NegotiationDialog.new()
	dialog.theme = UiStyle.build_theme()
	screen.add_child(dialog)
	DiplomacyRules.set_stance(screen.game.state, "julii", "egypt", "alliance")
	dialog.open_for(screen.game, "egypt")
	await capture("04-map-access-negotiation")
	dialog.hide()
	dialog.queue_free()
	var observation := screen.game.visible_regions()
	DiplomacyRules.apply_offer(screen.game.data, screen.game.state, {"from": "julii", "to": "egypt", "ask_map_access": true})
	check(screen.game.known_regions().has("aegyptus"), "accepted map access adds their geography")
	check(screen.game.visible_regions() == observation, "map rights do not reveal live military positions")
	screen.refresh()
	view.set_zoom_level(1.2)
	view.center_on("aegyptus")
	await capture("05-shared-atlas")
	# Review the authored physical features on a QA atlas; this is not a new
	# game cheat or an unseen-state renderer input in the shipped campaign.
	for region in screen.game.data.regions:
		screen.game.state["cartography"]["julii"][region] = 0
	screen.refresh()
	view.set_zoom_level(4.0)
	view.center_on("venetia")
	await capture("06-marsh-and-passes")
	view.center_on("etruria")
	screen._cancel_map_order()
	screen._clear_force_selection()
	screen._on_region_clicked("etruria")
	screen.open_drawer("units")
	await capture("07-recruitment-art")
	screen.close_drawer()
	screen.open_drawer("construction")
	await capture("08-construction-art")
	screen.close_drawer()
	print("terrain playtest: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	failed = failed or not ok

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func capture(name: String) -> void:
	await frames(12)
	for i in range(6):
		await process_frame
		RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
	print("saved ", name)
