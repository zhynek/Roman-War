class_name RomaCityScreen
extends Control
## Street exploration is presentation. Only explicit commands enter Game's
## deterministic civic-day rules; camera and citizen animation never do.
signal main_menu_requested
signal state_loaded
signal campaign_requested
signal campaign_zoom_requested

const REGION := "latium"
const SURVEY_MIN := 24.0
const SURVEY_MAX := 260.0
var game: Game
var standalone := true
var shared_session := false
var save_path := "user://roma_city_save.json"
var layout: Dictionary
var words: Dictionary
var world: RomaCityWorld
var garrison_view: RomaCityBattleForces
var citizens: RomaCityPeople
var viewport: SubViewport
var player: CharacterBody3D
var camera: Camera3D
var survey_camera: Camera3D
var status: Dictionary = {}
var overview := false
var destination := ""
var drawer: PanelContainer
var drawer_body: VBoxContainer
var stats_label: Label
var location_label: Label
var prompt_label: Label
var toast_label: Label
var guide_label: Label
var mini_map: Control
var day_button: Button
var govern_button: Button
var inspect_button: Button
var walk_button: Button
var command_bar: PanelContainer
var view_container: SubViewportContainer
var selected_site := ""
var selected_building := ""
var selection_label: Label
var _govern_tab := "policies"
var _drawer_building := ""
var _pitch := 0.0
var _ui_tick := 0.0
var _hud_panels: Array[Control] = []
var _drawer_site := ""
var _dossier_tab := "orders"
var _preview_stage := ""
var _building_preview: SubViewportContainer
var _preview_description: Label
var _stage_buttons: Dictionary = {}
var dawn: RomaCityDawn
var report_button: Button
var battle_panel: RomaCityBattlePanel
var battle_button: Button
var season_button: Button
var campaign_panel: RomaCityCampaignPanel
var _survey_dragging := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.build_theme()
	if game == null:
		game = Game.new_campaign("senate", 42, "medium", "long", false)
	words = game.data.effects_glossary.get("city_view", {})
	layout = game.data.roma_city
	if standalone and FileAccess.file_exists(save_path):
		var saved := SaveGame.read_file(save_path)
		if saved.get("player_faction", "") == "senate" and saved.get("settlements", {}).get(REGION, {}).get("owner", "") == "senate":
			game.load_from(save_path)
	RomaCityRules.ensure_city(game.data, game.state, REGION)
	if shared_session:
		game.city_campaign_enter(REGION)
	_build_view()
	_build_hud()
	dawn = RomaCityDawn.new()
	add_child(dawn)
	dawn.dismissed.connect(_dawn_dismissed)
	battle_panel = RomaCityBattlePanel.new()
	add_child(battle_panel)
	battle_panel.configure(self)
	campaign_panel = RomaCityCampaignPanel.new()
	add_child(campaign_panel)
	campaign_panel.configure(self)
	refresh_city()
	show_message(w("welcome"))
	if game.city_battle_status(REGION).get("active", false):
		battle_panel.open()

func w(key: String) -> String:
	return String(words.get(key, key))

func _build_view() -> void:
	var container := SubViewportContainer.new()
	view_container = container
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	add_child(container)
	container.gui_input.connect(_view_input)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	world = RomaCityWorld.new()
	viewport.add_child(world)
	world.build(layout)
	citizens = RomaCityPeople.new()
	world.add_child(citizens)
	citizens.build(layout)
	garrison_view=RomaCityBattleForces.new()
	garrison_view.soldiers_per_model=int(CityBattleSim.rules(game.data)["display_soldiers_per_model"])
	world.add_child(garrison_view)
	# The world is all at street grade. Collision uses the same geometry as
	# the future tactical surface, including real gaps for doors and gates.
	player = CharacterBody3D.new()
	player.name = "Governor"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.75
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.90
	player.add_child(shape)
	world.add_child(player)
	var spawn: Array = layout.get("spawn", [0, 0, 45])
	player.position = Vector3(spawn[0], 0.08, spawn[2])
	camera = Camera3D.new()
	camera.position.y = 1.68
	camera.fov = 73
	camera.near = 0.08
	camera.far = 450
	player.add_child(camera)
	camera.current = true
	survey_camera = Camera3D.new()
	world.add_child(survey_camera)
	survey_camera.position = Vector3(0, 125, 88)
	survey_camera.look_at(Vector3.ZERO)
	survey_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	survey_camera.size = 176
	survey_camera.far = 500

func _build_hud() -> void:
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 58
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	top.add_child(row)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	titles.add_child(_label(w("title"), 22))
	location_label = _label(w("subtitle"), 12)
	location_label.modulate = UiStyle.TEXT_DIM
	titles.add_child(location_label)
	stats_label = _label("", 13)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(stats_label)
	_hud_panels.append(top)
	var wayfinding := PanelContainer.new()
	wayfinding.position = Vector2(18, 76)
	wayfinding.custom_minimum_size = Vector2(300, 0)
	add_child(wayfinding)
	var wayfinding_box := VBoxContainer.new()
	wayfinding.add_child(wayfinding_box)
	selection_label = _label(w("select_hint"), 15)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_label.custom_minimum_size.x = 280
	wayfinding_box.add_child(selection_label)
	guide_label = _label(w("map_hint"), 12)
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_label.custom_minimum_size.x = 280
	guide_label.modulate = UiStyle.TEXT_DIM
	wayfinding_box.add_child(guide_label)
	_hud_panels.append(wayfinding)
	mini_map = load("res://src/ui/city/city_minimap.gd").new()
	mini_map.screen = self
	mini_map.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mini_map.offset_left = -228
	mini_map.offset_right = -18
	mini_map.offset_top = 76
	mini_map.offset_bottom = 286
	add_child(mini_map)
	_hud_panels.append(mini_map)
	# Always available, even when H hides the nonessential overlays.
	command_bar = PanelContainer.new()
	command_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	command_bar.offset_top = -112
	add_child(command_bar)
	var foot_box := VBoxContainer.new()
	foot_box.add_theme_constant_override("separation", 6)
	command_bar.add_child(foot_box)
	var commands := HFlowContainer.new()
	commands.add_theme_constant_override("h_separation", 8)
	commands.add_theme_constant_override("v_separation", 4)
	foot_box.add_child(commands)
	govern_button = _button(w("bottom_govern"), _open_governance)
	govern_button.theme_type_variation = "EndTurnButton"
	commands.add_child(govern_button)
	inspect_button = _button(w("bottom_inspect"), inspect_selection)
	commands.add_child(inspect_button)
	commands.add_child(_button(w("defense_inspect"), open_defenses))
	commands.add_child(_button(w("map"), toggle_overview))
	walk_button = _button(w("walk_mode"), toggle_walk)
	commands.add_child(walk_button)
	battle_button = _button(String(game.data.effects_glossary.get("city_battle", {}).get("entry", "")), open_battle)
	commands.add_child(battle_button)
	report_button = _button(w("dawn_report"), show_day_report.bind(false))
	commands.add_child(report_button)
	day_button = _button("", advance_day)
	commands.add_child(day_button)
	if shared_session:
		season_button = _button(w("next_season"), advance_season)
		commands.add_child(season_button)
		commands.add_child(_button(w("campaign_ledger"), open_campaign_ledger))
		commands.add_child(_button(w("campaign_map"), _request_campaign))
	for command in [["save", save_city], ["load", load_city], ["leave", leave_city]]:
		commands.add_child(_button(w(command[0]), command[1]))
	prompt_label = _label(w("cursor_controls"), 13)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot_box.add_child(prompt_label)
	toast_label = _label("", 12)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.modulate = UiStyle.TEXT_DIM
	foot_box.add_child(toast_label)
	drawer = PanelContainer.new()
	add_child(drawer)
	_layout_drawer(false)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	drawer.add_child(scroll)
	drawer_body = VBoxContainer.new()
	drawer_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_body.add_theme_constant_override("separation", 10)
	scroll.add_child(drawer_body)
	drawer.hide()

func _layout_drawer(building: bool) -> void:
	if building:
		drawer.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		drawer.offset_left = -444
		drawer.offset_right = -18
		drawer.offset_top = 76
		drawer.offset_bottom = -126
	else:
		drawer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		drawer.offset_left = 18
		drawer.offset_right = -18
		drawer.offset_top = -472
		drawer.offset_bottom = -126

func _paragraph(text: String, parent: Control, font_size: int = 13) -> Label:
	var label := _label(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _label(text: String, font_size: int = 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	button.focus_mode = Control.FOCUS_NONE
	return button

func _view_input(event: InputEvent) -> void:
	if (battle_panel != null and battle_panel.visible) or (campaign_panel != null and campaign_panel.visible) or (dawn != null and dawn.visible):
		return
	if event is InputEventMagnifyGesture:
		zoom_city(event.factor, event.position)
		view_container.accept_event()
		return
	if event is InputEventPanGesture and overview:
		_pan_survey(event.delta * 12.0)
		view_container.accept_event()
		return
	if event is InputEventMouseMotion and overview and _survey_dragging and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_pan_survey(-event.relative)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_survey_dragging = event.pressed and overview
		return
	if event is not InputEventMouseButton or not event.pressed:
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		zoom_city(pow(MapView.ZOOM_STEP, direction * maxf(event.factor, 0.1)), event.position)
		view_container.accept_event()
		return
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	var point: Vector2 = view_container.size * 0.5 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else event.position
	var picked := pick_at(point)
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		if picked.get("hit", false):
			quick_jump(picked["position"], String(picked.get("site_id", "")), String(picked.get("building_id", "")))
		return
	select_target(String(picked.get("building_id", "")), String(picked.get("site_id", "")))
	if event.button_index == MOUSE_BUTTON_RIGHT:
		inspect_selection()

func pick_at(point: Vector2) -> Dictionary:
	if view_container.size.x <= 0 or view_container.size.y <= 0:
		return {"hit": false}
	var viewport_point := point * Vector2(viewport.size) / view_container.size
	return RomaCityNavigation.pick(world, survey_camera if overview else camera, viewport_point, player)

func select_target(building_id: String, site_id: String) -> void:
	selected_building = building_id
	selected_site = site_id
	destination = site_id
	world.set_selection(building_id, site_id)
	_refresh_position()

func selected_name() -> String:
	if selected_site != "":
		return w("site_" + selected_site)
	if selected_building != "":
		return residence_name(selected_building)
	return w("select_hint")

func residence_name(building_id: String) -> String:
	for i in range(layout["buildings"].size()):
		if layout["buildings"][i]["id"] == building_id:
			return w("residence_title") % (i + 1)
	return w("select_hint")

func inspect_selection() -> void:
	if selected_site != "":
		open_drawer(selected_site)
	elif selected_building != "":
		open_residence(selected_building)

func quick_jump(requested: Vector3, site_id: String = "", building_id: String = "") -> bool:
	var landing := RomaCityNavigation.landing(world, player, requested, site_id, building_id)
	if not landing.get("ok", false):
		show_message(w(String(landing.get("reason", "jump_blocked"))))
		return false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	drawer.hide()
	player.position = landing["position"]
	player.velocity = Vector3.ZERO
	_pitch = 0
	camera.rotation.x = 0
	var target: Dictionary = site_by_id(site_id)
	if not target.is_empty():
		var p: Array = target["position"]
		var direction := Vector2(float(p[0]) - player.position.x, float(p[1]) - player.position.z)
		if direction.length() > 0.5:
			player.rotation.y = atan2(-direction.x, -direction.y)
	overview = false
	camera.current = true
	survey_camera.current = false
	select_target(building_id, site_id)
	show_message(w("jump_arrived"))
	return true

func toggle_walk() -> void:
	if overview:
		toggle_overview()
	drawer.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	_refresh_position()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_survey_dragging = false
	if battle_panel != null and battle_panel.visible:
		return
	if campaign_panel != null and campaign_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			campaign_panel.hide()
			get_viewport().set_input_as_handled()
		return
	if dawn != null and dawn.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
			dawn.dismiss()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not overview and not drawer.visible:
		player.rotation.y -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.15, 1.15)
		camera.rotation.x = _pitch
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				drawer.hide()
			KEY_TAB:
				toggle_walk()
			KEY_H:
				for panel in _hud_panels:
					panel.visible = not panel.visible
			KEY_G:
				_open_governance()
			KEY_M:
				toggle_overview()
			KEY_E:
				interact()

func _physics_process(delta: float) -> void:
	if battle_panel != null and battle_panel.visible:
		return
	if campaign_panel != null and campaign_panel.visible:
		return
	if player == null:
		return
	var direction := Vector3.ZERO
	if not drawer.visible and not overview and not (dawn != null and dawn.visible) and get_window().has_focus():
		var x := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		var z := float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		direction = player.basis * Vector3(x, 0, z).normalized()
		player.rotation.y += (float(Input.is_physical_key_pressed(KEY_LEFT)) - float(Input.is_physical_key_pressed(KEY_RIGHT))) * delta * 1.7
	var speed := 6.4 if Input.is_physical_key_pressed(KEY_SHIFT) else 3.4
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
	player.velocity.y = -2.0
	player.move_and_slide()
	_ui_tick += delta
	if _ui_tick > 0.15:
		_ui_tick = 0
		_refresh_position()

func _refresh_position() -> void:
	if mini_map != null:
		mini_map.queue_redraw()
	var site := nearest_site()
	location_label.text = w("subtitle") + ("  /  " + w("site_" + String(site["id"])) if not site.is_empty() else "")
	var person := citizens.nearest_person(player.position, 2.8)
	if drawer.visible:
		prompt_label.text = w("esc_close")
	elif not person.is_empty():
		prompt_label.text = w("speak") + " · " + w("role_" + String(person["role"]))
	elif not site.is_empty():
		prompt_label.text = w("interact") + " · " + w("site_" + String(site["id"]))
	else:
		prompt_label.text = w("overview_help") if overview else w("cursor_controls") if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED else w("walking")
	selection_label.text = selected_name()
	inspect_button.disabled = selected_building == "" and selected_site == ""
	walk_button.text = w("cursor_mode") if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else w("walk_mode")
	if destination != "":
		var target := site_by_id(destination)
		var pos: Array = target.get("approach", target["position"])
		var distance := Vector2(player.position.x, player.position.z).distance_to(Vector2(pos[0], pos[1]))
		guide_label.text = w("destination") % [w("site_" + destination), roundi(distance)]
	else:
		guide_label.text = String(game.data.effects_glossary.get("map_commands", {}).get("city_zoom_help", "")) if overview else w("map_hint")

func site_by_id(id: String) -> Dictionary:
	for site in layout.get("sites", []):
		if site["id"] == id:
			return site
	return {}

func nearest_site() -> Dictionary:
	var nearest: Dictionary = {}
	var best := INF
	for site in layout.get("sites", []):
		var p: Array = site["position"]
		var distance := Vector2(player.position.x, player.position.z).distance_to(Vector2(p[0], p[1]))
		if distance < float(site.get("radius", 13.0)) and distance < best:
			best = distance
			nearest = site
	return nearest

func interact() -> void:
	if drawer.visible:
		return
	var person := citizens.nearest_person(player.position, 2.8)
	if not person.is_empty():
		show_message(w("role_" + String(person["role"])) + ": “" + w(person["text_key"]) + "”")
		return
	var site := nearest_site()
	if not site.is_empty():
		open_drawer(String(site["id"]))

func _open_governance() -> void:
	if drawer.visible and _drawer_site == "" and _drawer_building == "":
		drawer.hide()
	else:
		open_drawer("")

func _clear_drawer() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	drawer.show()
	_building_preview = null
	_preview_description = null
	_stage_buttons.clear()
	for child in drawer_body.get_children():
		drawer_body.remove_child(child)
		child.queue_free()

func _drawer_heading(title: String) -> void:
	var row := HBoxContainer.new()
	drawer_body.add_child(row)
	var label := _label(title, 21)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(_button(w("panel_close"), drawer.hide))

func open_drawer(site_id: String = "") -> void:
	if site_id == "defenses":
		open_defenses()
		return
	if site_id != _drawer_site:
		_dossier_tab = "orders"
		_preview_stage = ""
		drawer.get_child(0).scroll_vertical = 0
	_drawer_site = site_id
	_drawer_building = ""
	_layout_drawer(site_id != "")
	_clear_drawer()
	_drawer_heading(w("govern_title") if site_id == "" else w("site_" + site_id))
	if site_id != "":
		_build_site_dossier(site_id)
		return
	var tabs := HBoxContainer.new()
	drawer_body.add_child(tabs)
	for category in ["policies", "works", "report"]:
		var tab := _button(w("tab_" + category), _choose_govern_tab.bind(category))
		tab.disabled = _govern_tab == category
		tabs.add_child(tab)
	if _govern_tab == "report":
		_build_city_report()
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	drawer_body.add_child(grid)
	for action in status.get("actions", []):
		if (action["kind"] == "project") != (_govern_tab == "works"):
			continue
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.x = maxf(260, (size.x - 112) / 3)
		grid.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 6)
		card.add_child(body)
		_action_card(action, body)

func _choose_govern_tab(category: String) -> void:
	_govern_tab = category
	open_drawer("")

func _action_card(action: Dictionary, parent: Control) -> void:
	var id := String(action["id"])
	var button := _button(w("action_" + id), perform_action.bind(id))
	button.disabled = not action.get("available", false)
	parent.add_child(button)
	var terms := w("cost") % int(action.get("cost", 0))
	if int(action.get("days", 0)) > 0:
		terms += " · " + w("duration") % int(action["days"])
	var upkeep := int(game.data.balance["city"].get("project_maintenance", {}).get(id, 0))
	if upkeep > 0:
		terms += " · " + w("upkeep_day") % upkeep
	_paragraph(terms, parent, 12).modulate = UiStyle.ACCENT
	_paragraph(w("help_" + id), parent, 12).modulate = UiStyle.TEXT_DIM
	if button.disabled:
		_paragraph(w("reason_" + String(action.get("reason", ""))), parent, 12)
	else:
		var forecast_box := VBoxContainer.new()
		var forecast_button := _button(w("preview_consequences"), func():
			if forecast_box.get_child_count() == 0:
				_build_forecast(game.city_action_forecast(REGION, id), forecast_box)
			forecast_box.visible = not forecast_box.visible
			if forecast_box.visible:
				_scroll_to_control(forecast_box))
		parent.add_child(forecast_button)
		parent.add_child(forecast_box)
		forecast_box.hide()

func _scroll_to_control(control: Control) -> void:
	# Forecasts often expand a card below the fold; reveal the answer after layout.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		return
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
			return
		parent = parent.get_parent()

func _build_forecast(forecast: Dictionary, parent: Control) -> void:
	if not forecast.get("available", false):
		_paragraph(w("reason_" + String(forecast.get("reason", "unknown_action"))), parent, 12)
		return
	var immediate: Dictionary = forecast.get("immediate_delta", {})
	var next: Dictionary = forecast.get("next_day_delta", {})
	_paragraph(w("forecast_immediate") % [float(immediate.get("unrest", 0)), float(immediate.get("treasury", 0))], parent, 12).modulate = UiStyle.ACCENT
	if forecast.get("next_day_available", false):
		_paragraph(w("forecast_next_day") % [float(next.get("grievance", 0)), float(next.get("legitimacy", 0)), float(next.get("unrest", 0))], parent, 12)
		_paragraph(w("forecast_daily_cost") % int(forecast.get("immediate", {}).get("daily_cost", 0)), parent, 12)
		for event in forecast.get("events", []):
			_paragraph(RomaCityDawn.event_text(event, words), parent, 12)
	else:
		_paragraph(w("forecast_blocked") % w("reason_" + String(forecast.get("next_day_reason", "insufficient_funds"))), parent, 12)
	_paragraph(w("forecast_note"), parent, 12).modulate = UiStyle.TEXT_DIM

func _build_site_dossier(site_id: String) -> void:
	var info := game.city_building_info(REGION, site_id)
	if not info.get("available", false):
		_paragraph(w("reason_" + String(info.get("reason", "unknown_site"))), drawer_body)
		return
	var tabs := HBoxContainer.new()
	drawer_body.add_child(tabs)
	var categories := ["orders", "development"]
	if site_id == "barracks":
		categories.append("troops")
	for category in categories:
		var tab := _button(w("tab_building_" + category), _choose_dossier_tab.bind(category))
		tab.disabled = category == _dossier_tab
		tabs.add_child(tab)
	var project: Dictionary = info.get("project", {})
	var stage := String(info.get("stage", "current"))
	var status_line := w("stage_status_" + stage)
	if stage == "construction":
		status_line += " · " + w("days_remaining") % int(project.get("estimated_days_remaining", project.get("remaining", 0)))
	_paragraph(status_line, drawer_body, 16).modulate = UiStyle.ACCENT
	if int(project.get("completion_day", 0)) > 0:
		_paragraph(w("completion_done" if stage == "improved" else "completion_due") % int(project["completion_day"]), drawer_body, 12)
	if stage == "construction":
		var progress := ProgressBar.new()
		progress.max_value = maxi(1, int(project.get("days", 1)))
		progress.value = int(project.get("elapsed", 0))
		progress.custom_minimum_size.y = 16
		drawer_body.add_child(progress)
	if _dossier_tab == "troops" and site_id == "barracks":
		_build_troops()
		return
	if _dossier_tab == "development":
		_build_development(info)
		return
	_paragraph(w("about_" + site_id), drawer_body)
	for action in info.get("actions", []):
		_action_card(action, drawer_body)
	drawer_body.add_child(_button(w("visit_entrance"), _jump_site.bind(site_id)))

func _choose_dossier_tab(category: String) -> void:
	_dossier_tab = category
	drawer.get_child(0).scroll_vertical = 0
	open_drawer(_drawer_site)

func _build_development(info: Dictionary) -> void:
	var site_id := String(info["site"])
	if _preview_stage == "":
		_preview_stage = String(info["stage"])
	var stages := HBoxContainer.new()
	drawer_body.add_child(stages)
	for stage in ["current", "construction", "improved"]:
		var button := _button(w("preview_" + stage), _set_preview_stage.bind(stage))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stages.add_child(button)
		_stage_buttons[stage] = button
	_building_preview = load("res://src/ui/city/building_preview.gd").new()
	_building_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_body.add_child(_building_preview)
	_building_preview.call("show_building", layout, site_id, status, _preview_stage)
	_paragraph(w("preview_notice"), drawer_body, 12).modulate = UiStyle.TEXT_DIM
	_preview_description = _paragraph("", drawer_body)
	_set_preview_stage(_preview_stage)
	var project: Dictionary = info["project"]
	drawer_body.add_child(_label(w("building_tradeoffs"), 15))
	_paragraph(w("project_terms") % [int(project.get("cost", 0)), int(project.get("duration", project.get("days", 0))), int(project.get("maintenance", 0))], drawer_body, 12)
	_paragraph(w("work_rate") % int(status.get("work_rate", 1)), drawer_body, 12)
	for stock in ["grievance", "legitimacy"]:
		var value := 0.0
		for factor in info.get("effects", {}).get(stock, []):
			value += float(factor.get("value", 0))
		_paragraph(w("flow_" + stock) + "  %+.2f" % value, drawer_body, 12)
	for action in info.get("actions", []):
		if action["id"] == project["id"]:
			_action_card(action, drawer_body)
	drawer_body.add_child(_button(w("visit_entrance"), _jump_site.bind(site_id)))

func _set_preview_stage(stage: String) -> void:
	_preview_stage = stage
	if is_instance_valid(_building_preview):
		_building_preview.call("set_stage", stage)
	if is_instance_valid(_preview_description):
		_preview_description.text = w("stage_" + _drawer_site + "_" + stage)
	for id in _stage_buttons:
		_stage_buttons[id].disabled = id == stage

func _build_troops() -> void:
	var military := game.city_troop_status(REGION)
	_paragraph(w("troops_help"), drawer_body, 13)
	_paragraph(w("troops_counters"),drawer_body,13).modulate=UiStyle.ACCENT
	drawer_body.add_child(_label(w("troops_programs"), 16))
	for programme in military.get("programs", []):
		var effects: Dictionary = programme.get("effects", {})
		_paragraph(w("troops_requires") % w("project_" + String(programme.get("requires_project", "improve_barracks"))), drawer_body, 12).modulate = UiStyle.ACCENT
		_paragraph(w("troops_gain") % [int(effects.get("experience", 0)), int(effects.get("weapon", 0)), int(effects.get("armor", 0))], drawer_body, 12)
		for action in status.get("actions", []):
			if action["id"] == programme["id"]:
				_action_card(action, drawer_body)
		if int(programme.get("remaining", 0)) > 0:
			_paragraph(w("days_remaining") % int(programme["remaining"]), drawer_body, 12)
	drawer_body.add_child(HSeparator.new())
	drawer_body.add_child(_label(w("troops_garrison"), 16))
	var garrison: Array = military.get("garrison", [])
	if garrison.is_empty():
		_paragraph(w("troops_none"), drawer_body, 12)
	for unit in garrison:
		_paragraph(String(unit.get("name", unit.get("template", ""))), drawer_body, 14).modulate = UiStyle.ACCENT
		_paragraph(_troop_profile(unit), drawer_body, 12)
	drawer_body.add_child(HSeparator.new())
	drawer_body.add_child(_label(w("troops_types"), 16))
	_paragraph(w("troops_standalone" if standalone else "troops_season_note"), drawer_body, 12)
	for unit in military.get("recruitable", []):
		_paragraph(String(unit["name"]), drawer_body, 15).modulate = UiStyle.ACCENT
		var template: Dictionary = game.data.units.get(unit["id"], {})
		_paragraph(String(template.get("description", "")), drawer_body, 12).modulate = UiStyle.TEXT_DIM
		_paragraph(w("troops_base_stats") % [int(template.get("attack", 0)), int(template.get("defense", 0)), int(template.get("morale", 0))], drawer_body, 12)
		_paragraph(w("troops_unit_terms") % [int(unit.get("soldiers", 0)), int(unit.get("cost", 0)), int(unit.get("upkeep", 0))], drawer_body, 12)
		_paragraph(_troop_profile(unit.get("profile", {})), drawer_body, 12)
		var button := _button(w("troops_recruit") % String(unit["name"]), _queue_city_unit.bind(String(unit["id"])))
		button.disabled = not unit.get("available", false)
		drawer_body.add_child(button)
		if button.disabled:
			_paragraph(w("reason_" + String(unit.get("reason", "unit_unavailable"))), drawer_body, 12)
	if not military.get("queue", []).is_empty():
		drawer_body.add_child(_label(w("troops_queue"), 16))
		for job in military["queue"]:
			var template := String(job["template"])
			_paragraph(w("troops_city_queue" if job.has("city_days_left") else "troops_queue_entry") % [String(game.data.units.get(template, {}).get("name", template)), int(job.get("city_days_left",job.get("turns_left",0)))], drawer_body, 12)

func _troop_profile(profile: Dictionary) -> String:
	return w("troops_unit_profile") % [int(profile.get("experience", 0)), int(profile.get("weapon", 0)), int(profile.get("armor", 0))]

func _queue_city_unit(template: String) -> void:
	var ok := game.city_queue_unit(REGION, template, standalone or shared_session)
	refresh_city()
	_refresh_drawer()
	show_message(w("troops_queued") % String(game.data.units.get(template, {}).get("name", template)) if ok else w("refused"))

func _jump_site(site_id: String) -> void:
	var site := site_by_id(site_id)
	var p: Array = site.get("approach", site.get("position", [0, 0]))
	quick_jump(Vector3(p[0], 0, p[1]), site_id, site_id if site_id in ["tavern", "barracks", "curia"] else "")

func open_residence(building_id: String) -> void:
	_drawer_site = ""
	_drawer_building = building_id
	_layout_drawer(true)
	_clear_drawer()
	_drawer_heading(residence_name(building_id))
	_paragraph(w("residence_about"), drawer_body)
	_paragraph(w("residence_evolution"), drawer_body)
	for action in status.get("actions", []):
		if action["id"] in ["repair_streets", "clean_water", "tax_low"]:
			_action_card(action, drawer_body)
	var block: Dictionary = {}
	for entry in layout.get("buildings", []):
		if entry["id"] == building_id:
			block = entry
	if not block.is_empty():
		_paragraph(w("building_dimensions") % [float(block["size"][0]), float(block["size"][1]), float(block["height"])], drawer_body, 12)

func _build_city_report() -> void:
	_paragraph(w("govern_help"), drawer_body)
	var forecast := VBoxContainer.new()
	drawer_body.add_child(_button(w("forecast_show"), func():
		if forecast.get_child_count() == 0:
			_build_forecast(game.city_day_forecast(REGION), forecast)
		forecast.visible = not forecast.visible
		if forecast.visible:
			_scroll_to_control(forecast)))
	drawer_body.add_child(forecast)
	forecast.hide()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	drawer_body.add_child(columns)
	for key in ["unrest", "projects"]:
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(body)
		body.add_child(_label(w("factors_title") if key == "unrest" else w("works_title"), 16))
		if key == "unrest":
			for factor in status.get("factors", []):
				_paragraph(w("factor_" + String(factor.get("label", ""))) + "  %+.1f" % float(factor.get("value", 0)), body, 12)
		else:
			for id in status.get("projects", {}):
				var project: Dictionary = status["projects"][id]
				if not project.get("completed", false) and int(project.get("remaining", 0)) == 0:
					continue
				_paragraph(w("project_" + String(id)) + " · " + (w("complete") if project.get("completed", false) else w("days_remaining") % int(project.get("estimated_days_remaining", project.get("remaining", 0)))), body, 12)

func _refresh_drawer() -> void:
	if not drawer.visible:
		return
	if _drawer_building != "":
		open_residence(_drawer_building)
	else:
		open_drawer(_drawer_site)

func perform_action(id: String) -> void:
	var ok := game.city_action(REGION, id)
	refresh_city()
	show_message(w("issued") % w("action_" + id) if ok else w("refused"))
	if drawer.visible:
		_refresh_drawer()

func advance_day() -> void:
	if battle_panel != null and battle_panel.visible:
		return
	if dawn.visible:
		return
	if game.city_advance_day(REGION):
		refresh_city()
		show_message(w("day_passed"))
		if drawer.visible:
			_refresh_drawer()
		show_day_report(true)
	else:
		show_message(w("refused"))

func show_day_report(ceremonial: bool = false) -> void:
	var report: Dictionary = status.get("last_day_report", {})
	if report.is_empty():
		show_message(w("dawn_no_report"))
		return
	dawn.present(report, words, ceremonial)
	day_button.disabled = true

func _dawn_dismissed() -> void:
	day_button.disabled = not status.get("can_advance", false)
	_refresh_position()

func refresh_city() -> void:
	status = game.city_status(REGION)
	world.apply_status(status)
	citizens.apply_status(status)
	_sync_garrison()
	day_button.text = w("bottom_next_day") + " · " + w("cost") % int(status.get("daily_cost", 0))
	day_button.disabled = not status.get("can_advance", false)
	report_button.disabled = status.get("last_day_report", {}).is_empty()
	stats_label.text = w("stats_compact") % [int(status.get("day", 0)), int(status.get("treasury", 0)), w("mood_" + String(status.get("mood", "calm"))), int(status.get("unrest", 0))]
	if shared_session:
		stats_label.text = campaign_date() + "\n" + stats_label.text
		season_button.disabled = not game.city_campaign_status(REGION).get("can_advance", false)
	_refresh_position()

func toggle_overview() -> void:
	overview = not overview
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	survey_camera.current = overview
	camera.current = not overview
	_refresh_position()


func show_city_overview() -> void:
	if not overview:
		toggle_overview()
	survey_camera.size = 176.0
	survey_camera.position = Vector3(0, 125, 88)
	survey_camera.look_at(Vector3.ZERO)
	_refresh_position()


func zoom_city(factor: float, point: Vector2) -> void:
	## The survey and street cameras change presentation only. Town commands
	## still require an explicit action; the campaign scale opens via a signal.
	if not is_finite(factor) or factor <= 0 or (battle_panel != null and battle_panel.visible) or (campaign_panel != null and campaign_panel.visible) or (dawn != null and dawn.visible):
		return
	if not overview:
		if factor >= 1.0:
			return
		toggle_overview()
		survey_camera.size = 48.0
		survey_camera.position = player.position + Vector3(0, 125, 88)
		survey_camera.look_at(player.position)
	var next_size := survey_camera.size / factor
	if next_size > SURVEY_MAX and not standalone:
		_survey_dragging = false
		campaign_zoom_requested.emit()
		return
	var before := _survey_ground(point)
	survey_camera.size = clampf(next_size, SURVEY_MIN, SURVEY_MAX)
	var after := _survey_ground(point)
	survey_camera.position += before - after


func _survey_ground(point: Vector2) -> Vector3:
	if view_container.size.x <= 0 or view_container.size.y <= 0:
		return Vector3.ZERO
	var screen_point := point * Vector2(viewport.size) / view_container.size
	var origin := survey_camera.project_ray_origin(screen_point)
	var ray := survey_camera.project_ray_normal(screen_point)
	return origin - ray * origin.y / minf(ray.y, -0.001)


func _pan_survey(delta: Vector2) -> void:
	var center := view_container.size * 0.5
	survey_camera.position += _survey_ground(center + delta) - _survey_ground(center)

func show_message(message: String) -> void:
	toast_label.text = message

func save_city() -> void:
	battle_panel.host.stop()
	show_message(w("saved") if game.save_to(save_path) else w("save_failed"))

func load_city() -> void:
	battle_panel.host.stop()
	var loaded := SaveGame.read_file(save_path)
	if loaded.is_empty() or (not shared_session and (loaded.get("player_faction", "") != game.state["player_faction"] or loaded.get("settlements", {}).get(REGION, {}).get("owner", "") != game.state["player_faction"])):
		show_message(w("load_failed"))
		return
	if game.load_from(save_path):
		RomaCityRules.ensure_city(game.data, game.state, REGION)
		refresh_city()
		state_loaded.emit()
		if shared_session and game.state["settlements"][REGION]["owner"] != game.state["player_faction"] and not game.city_battle_status(REGION).get("active", false):
			campaign_requested.emit()
			return
		if game.city_battle_status(REGION).get("active", false):
			battle_panel.open()
		if drawer.visible:
			_refresh_drawer()
		show_message(w("loaded"))
	else:
		show_message(w("load_failed"))

func leave_city() -> void:
	battle_panel.host.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if standalone and not game.save_to(save_path):
		show_message(w("save_failed"))
		return
	main_menu_requested.emit()

func _exit_tree() -> void:
	if battle_panel != null: battle_panel.host.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func open_battle() -> void:
	if campaign_panel != null:
		campaign_panel.hide()
	if dawn != null and dawn.visible:
		dawn.dismiss()
	battle_panel.open()


func campaign_date() -> String:
	var year := int(game.state["year"])
	return w("calendar_date") % [w("calendar_bc") % -year if year < 0 else w("calendar_ad") % year, w("calendar_" + String(game.state["season"])), int(game.state["turn"]) + 1]


func _request_campaign() -> void:
	battle_panel.host.stop()
	campaign_panel.hide()
	if dawn.visible:
		dawn.dismiss()
	campaign_requested.emit()


func open_campaign_ledger() -> void:
	if battle_panel.visible:
		return
	battle_panel.host.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	drawer.hide()
	if dawn.visible:
		dawn.dismiss()
	campaign_panel.present()


func advance_season(count: int = 1) -> void:
	if battle_panel.visible:
		return
	battle_panel.host.stop()
	var result := game.city_campaign_advance(REGION, count)
	refresh_city()
	_refresh_drawer()
	var message := w("calendar_passed") % [int(result.get("seasons_advanced", 0)), int(result.get("civic_days_advanced", 0))]
	var reason := String(result.get("stop_reason", result.get("reason", "")))
	if reason != "":
		message += " " + w("calendar_stop") % w("reason_" + reason)
	for report in result.get("reports", []):
		if int(report.get("unfunded_civic_days", 0)) > 0:
			message += " " + w("calendar_unfunded")
			break
	show_message(message)
	campaign_panel.last_message = message
	var battle := game.city_battle_status(REGION)
	if battle.get("can_defend", false) or battle.get("active", false):
		open_battle()
	elif game.state["settlements"][REGION]["owner"] != game.state["player_faction"]:
		show_message(w("calendar_lost"))
		campaign_requested.emit()
	else:
		campaign_panel.present()


func _sync_garrison() -> void:
	if garrison_view==null:return
	var settlement:Dictionary=game.state["settlements"][REGION]
	var formations:Array=[]
	var muster:Dictionary=layout["battle"]["garrison_muster"]
	if settlement["owner"]==game.state["player_faction"]:
		for index in range(settlement["garrison"].size()):
			var unit:Dictionary=settlement["garrison"][index]
			var at:Vector2=Vector2(muster["origin"][0],muster["origin"][1])+Vector2((index%int(muster["columns"]))*muster["spacing"][0],(index/int(muster["columns"]))*muster["spacing"][1])
			formations.append({"id":"garrison_%d"%index,"side":"defender","unit":unit.duplicate(true),"role":CityBattleSim.role(game.data,unit["template"]),"specialty":CityBattleSpecialists.specialty(game.data,unit["template"]),"soldiers":game.data.units[unit["template"]]["soldiers"],"position":[roundi(at.x*100),roundi(at.y*100)],"facing":[0,1000],"moving":false,"engaged":false})
	garrison_view.sync(layout,{"phase":"garrison","active":true,"formations":formations})
	garrison_view.visible=not (battle_panel!=null and battle_panel.visible)

func open_defenses() -> void:
	if battle_panel != null and battle_panel.visible:return
	_drawer_site = "defenses"
	_drawer_building = ""
	_layout_drawer(true)
	_clear_drawer()
	_drawer_heading(w("defense_title"))
	_paragraph(w("defense_help"),drawer_body,13)
	var defense := CitySiegeRules.defenses(game.data,game.state,REGION)
	_paragraph(w("defense_integrity") % int(defense["gate_integrity"]),drawer_body,16).modulate=UiStyle.ACCENT
	var archers := 0
	for unit in game.state["settlements"][REGION]["garrison"]:
		if CityBattleSim.role(game.data,unit["template"])=="archer" and int(unit["strength_pct"])>0:archers+=1
	_paragraph(w("defense_archers") % archers,drawer_body,14)
	for point in game.data.city_governance["defense_inspections"]:
		drawer_body.add_child(HSeparator.new())
		drawer_body.add_child(_label(w("defense_"+point["id"]),17))
		var help := w("defense_"+point["id"]+"_help")
		if point["id"]=="gate":help=help % int(CitySiegeRules.tuning(game.data)["gate_bonus"])
		_paragraph(help,drawer_body,13)
		drawer_body.add_child(_button(w("defense_visit"),visit_defense.bind(point)))
		for id in point["projects"]:
			var project: Dictionary=status.get("projects",{}).get(id,{})
			if project.get("completed",false):
				_paragraph(w("project_"+id)+" · "+w("defense_ready"),drawer_body,13).modulate=UiStyle.ACCENT
			elif int(project.get("remaining",0))>0:
				_paragraph(w("project_"+id)+" · "+w("defense_working") % int(project.get("estimated_days_remaining",project["remaining"])),drawer_body,13)
			else:
				for action in status.get("actions",[]):
					if action["id"]==id:_action_card(action,drawer_body)
		if point["id"]=="barracks":drawer_body.add_child(_button(w("defense_troops"),func():open_drawer("barracks");_choose_dossier_tab("troops")))

func visit_defense(point: Dictionary) -> void:
	if battle_panel != null and battle_panel.visible:return
	var at := Vector3(float(point["position"][0]),0.1,float(point["position"][1]))
	if not quick_jump(at):return
	drawer.hide()
	var target := Vector3(float(point["look_at"][0]),player.position.y,float(point["look_at"][1]))
	player.look_at(target)
	_pitch=0.10
	camera.rotation.x=_pitch
	destination=""
	selection_label.text=w("defense_"+point["id"])
	show_message(w("defense_help"))
