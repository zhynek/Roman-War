extends Control
## Shared Alpine route, embedded in the main app or run as a developer entry.
signal main_menu_requested
var embedded := false
var screen: CampaignScreen
var route_panel: PanelContainer

func _enter_tree() -> void:
	if embedded:
		return
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War Route App QA/%d" % OS.get_process_id() if OS.get_cmdline_user_args().has("route-qa") else "Roman War Campaign Route Development")
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_route()

func start_route() -> void:
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	screen = CampaignScreen.create(CampaignRoute.build())
	if embedded:
		screen.save_path = embedded_save_path()
		DirAccess.make_dir_recursive_absolute(screen.save_path.get_base_dir())
		screen.main_menu_enabled = true
		screen.main_menu_requested.connect(func(): main_menu_requested.emit())
	add_child(screen)
	for id in screen.game.state["armies"]:
		if screen.game.state["armies"][id]["owner"] == screen.game.state["player_faction"]:
			screen.select_force("army", id)
			break
	screen.map_view.set_zoom_level(5.5)
	screen.map_view.center_on(screen.game.state["armies"][screen.selected_army]["region"])
	_focus_start.call_deferred()
	var words: Dictionary = screen.game.data.effects_glossary["map_commands"]
	route_panel = PanelContainer.new()
	route_panel.position = Vector2(16, 58)
	route_panel.custom_minimum_size.x = 390
	route_panel.add_theme_stylebox_override("panel", UiStyle._flat(Color(0.045, 0.065, 0.057, 0.95), 7))
	screen.map_view.add_child(route_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	route_panel.add_child(column)
	var toggle := Button.new()
	toggle.text = words["route_title"]
	toggle.focus_mode = Control.FOCUS_NONE
	column.add_child(toggle)
	var body := VBoxContainer.new()
	column.add_child(body)
	toggle.pressed.connect(func(): body.visible = not body.visible)
	var brief := Label.new()
	brief.text = words["route_brief"]
	brief.custom_minimum_size.x = 390
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.add_theme_font_size_override("font_size", 12)
	body.add_child(brief)
	var route: Array = screen.game.data.terrain_content["development_route"]["regions"]
	var waypoints := HFlowContainer.new()
	body.add_child(waypoints)
	for i in range(route.size()):
		var region := String(route[i])
		var button := Button.new()
		button.text = "%d · %s" % [i + 1, screen.game.data.regions[region]["name"]]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.x = 190
		button.pressed.connect(func():
			screen.map_view.center_on(region)
			if screen.selected_army != "":
				screen._planning_order = true
				screen._pinned_target = region
				screen._preview_destination(region)
			body.hide())
		waypoints.add_child(button)
	var comparison := CheckButton.new()
	comparison.text = words["route_compare"]
	comparison.toggled.connect(func(on): screen.map_view.set_realism_enabled(not on))
	body.add_child(comparison)
	var restart := Button.new()
	restart.text = words["route_reset"]
	restart.pressed.connect(start_route)
	body.add_child(restart)
	var storage := Label.new()
	storage.text = words["route_saved"]
	storage.add_theme_font_size_override("font_size", 11)
	body.add_child(storage)


func _focus_start() -> void:
	# The campaign's initial resize completes after _ready; focus then so
	# its pending capital centering cannot override the selected route army.
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(screen):
		screen.map_view.focus_force()


static func embedded_save_path() -> String:
	# Keep the published 0.14.1 Mac route slot, including its .bak recovery.
	# Custom storage (tests and previews) must never reach production saves.
	if OS.get_name() == "macOS" and not ProjectSettings.get_setting("application/config/use_custom_user_dir", false) and ProjectSettings.get_setting("application/config/name", "") == "Roman War":
		return OS.get_data_dir().path_join("Roman War Alpine Route/roman_war_save.json")
	return "user://alpine_route_save.json"
