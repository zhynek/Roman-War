class_name RomaCityBattlePanel
extends Control
## Commands resolve only in the Game facade. This overlay, its camera and its
## representative troops read the same authored coordinates as Roma's city.
signal closed
var screen: RomaCityScreen
var words: Dictionary = {}
var snapshot: Dictionary = {}
var selected := ""
var selected_ids: Array = []
var order_mode := "move"
var host := CityBattleHost.new()
var speed_button: Button
var order_buttons: Dictionary = {}
var ability_button: Button
var _roster_rows: Dictionary = {}
var _poll := 0.0
var _view_tick := -1
var forces: RomaCityBattleForces
var plan: Control
var roster_scroll: ScrollContainer
var roster: VBoxContainer
var heading: Label
var summary: Label
var phase_label: Label
var help_label: Label
var message_label: Label
var objective_label: Label
var practice_button: Button
var defend_button: Button
var start_button: Button
var step_button: Button
var hold_button: Button
var close_button: Button
var return_button: Button
var campaign_map_button: Button
var save_button: Button
var inspect_button: Button
var inspecting := false
var camera_rig := RomaCityBattleCamera.new()
var overview_button: Button
var follow_button: Button
var tilt_button: Button
const DRAG_THRESHOLD := 6.0
var _selection_press := false
var _marquee := false
var _gesture_additive := false
var _gesture_double := false
var _press_point := Vector2.ZERO
var _drag_point := Vector2.ZERO
var _camera_drag := ""
var _camera_pointer := Vector2.ZERO
var _auto_select := true
var _saved_view: Dictionary = {}
var _built := false
var _node_rects: Dictionary = {}
var _formation_rects: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()
	resized.connect(queue_redraw)

func configure(city: RomaCityScreen) -> void:
	screen = city
	host.attach(screen.game,RomaCityScreen.REGION)
	words = screen.game.data.effects_glossary.get("city_battle", {})
	forces = RomaCityBattleForces.new()
	forces.soldiers_per_model=int(CityBattleSim.rules(screen.game.data)["display_soldiers_per_model"])
	screen.world.add_child(forces)
	forces.hide()
	_build()
	forces.presentation_changed.connect(func():
		queue_redraw()
		plan.queue_redraw())

func w(key: String) -> String:
	return String(words.get(key, key))

func _label(text: String, font_size: int = 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _paragraph(text: String, font_size: int = 13) -> Label:
	var label := _label(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(key: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = w(key)
	button.custom_minimum_size.y = 38
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle._flat(Color(0.045, 0.063, 0.065, 0.95), 6))
	add_child(panel)
	return panel

func _box(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	parent.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)
	return box

func _build() -> void:
	if _built:
		return
	_built = true
	var top := _panel()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 78
	var top_box := _box(top)
	var top_row := HBoxContainer.new()
	top_box.add_child(top_row)
	heading = _label(w("title"), 23)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(heading)
	phase_label = _label("", 15)
	phase_label.modulate = UiStyle.ACCENT
	top_row.add_theme_constant_override("separation", 16)
	inspect_button = _button("inspect_troops", toggle_inspect)
	top_row.add_child(inspect_button)
	overview_button = _button("camera_overview", show_overview)
	top_row.add_child(overview_button)
	tilt_button = _button("camera_tilt", tilt_camera)
	top_row.add_child(tilt_button)
	follow_button = _button("camera_follow", follow_selection)
	top_row.add_child(follow_button)
	top_row.add_child(phase_label)
	summary = _label("", 13)
	top_box.add_child(summary)
	var left := _panel()
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 16
	left.offset_right = 278
	left.offset_top = 92
	left.offset_bottom = -205
	var left_box := _box(left)
	left_box.add_child(_label(w("defenders"), 17))
	var scroll := ScrollContainer.new()
	roster_scroll=scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_box.add_child(scroll)
	roster = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 10)
	scroll.add_child(roster)
	var right := _panel()
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -298
	right.offset_right = -16
	right.offset_top = 92
	right.offset_bottom = -205
	var right_box := _box(right)
	right_box.add_child(_label(w("plan"), 17))
	plan = BattlePlan.new()
	plan.panel = self
	plan.custom_minimum_size = Vector2(250, 285)
	plan.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(plan)
	objective_label = _paragraph("", 13)
	right_box.add_child(objective_label)
	var bottom := _panel()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -190
	var bottom_box := _box(bottom)
	help_label = _paragraph("", 14)
	bottom_box.add_child(help_label)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	bottom_box.add_child(buttons)
	practice_button = _button("practice", begin.bind(true))
	buttons.add_child(practice_button)
	defend_button = _button("defend", begin.bind(false))
	buttons.add_child(defend_button)
	start_button = _button("start", start)
	start_button.theme_type_variation = "EndTurnButton"
	buttons.add_child(start_button)
	step_button = _button("pause", step)
	step_button.theme_type_variation = "EndTurnButton"
	buttons.add_child(step_button)
	hold_button = _button("hold", hold)
	buttons.add_child(hold_button)
	speed_button = _button("speed",func():_action(host.invoke("control",["speed"])))
	buttons.add_child(speed_button)
	for action in ["move","attack_move","charge","retreat","fire","attack_engine","fire_arrows"]:
		var order_button := _button(action,_choose_order.bind(action))
		buttons.add_child(order_button)
		order_buttons[action]=order_button
	ability_button=_button("ability",func():_issue("ability"))
	buttons.add_child(ability_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	save_button = _button("save", save)
	buttons.add_child(save_button)
	close_button = _button("end_practice", dismiss_session)
	buttons.add_child(close_button)
	return_button = _button("return_city", close)
	buttons.add_child(return_button)
	if screen.shared_session:
		campaign_map_button = _button("campaign_map", screen._request_campaign)
		buttons.add_child(campaign_map_button)
	message_label = _paragraph(w("mode_note"), 12)
	message_label.modulate = UiStyle.TEXT_DIM
	bottom_box.add_child(message_label)

func open() -> void:
	if screen == null:
		return
	if not visible:
		_saved_view = {"overview": screen.overview, "transform": screen.survey_camera.transform, "size": screen.survey_camera.size, "citizens": screen.citizens.visible, "drawer": screen.drawer.visible, "hud": [], "projection": screen.survey_camera.projection, "fov": screen.survey_camera.fov, "near": screen.survey_camera.near}
		for panel in screen._hud_panels:
			_saved_view["hud"].append(panel.visible)
			panel.hide()
		screen.command_bar.hide()
		screen.drawer.hide()
		screen.citizens.hide()
		screen.garrison_view.hide()
		screen.overview = true
		screen.camera.current = false
		screen.survey_camera.current = true
		inspecting = false
		camera_rig.attach(screen.survey_camera, float(screen.layout.get("extent", 180)))
		_frame_battle()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		show()
		move_to_front()
	refresh()

func toggle_inspect() -> void:
	if inspecting:
		show_overview()
	else:
		inspecting = true
		_frame_battle()
	queue_redraw()

func show_overview() -> void:
	inspecting = false
	camera_rig.overview()
	inspect_button.text = w("inspect_troops")
	queue_redraw()

func follow_selection() -> void:
	if _selection().is_empty():
		message_label.text = w("selection_empty")
		return
	inspecting = true
	camera_rig.inspect(_selection_center())
	camera_rig.update(0)
	inspect_button.text = w("battle_overview")

func tilt_camera() -> void:
	camera_rig.tilt()

func _selection_center() -> Vector3:
	var center := Vector3.ZERO
	var count := 0
	for id in _selection():
		if forces.anchors.has(id):
			center += Vector3(forces.anchors[id])
			count += 1
	return center / count if count > 0 else camera_rig.target_focus

func _frame_battle() -> void:
	if inspecting and not selected_formation().is_empty():
		camera_rig.inspect(_selection_center())
	else:
		inspecting = false
		camera_rig.overview()
	camera_rig.update(0)
	inspect_button.text = w("battle_overview" if inspecting else "inspect_troops")

func close() -> void:
	host.stop()
	if not visible:
		return
	_cancel_gesture()
	hide()
	forces.hide()
	screen.world.set_battle_gate_breached(false)
	if not _saved_view.is_empty():
		screen.overview = bool(_saved_view["overview"])
		screen.survey_camera.transform = _saved_view["transform"]
		screen.survey_camera.size = float(_saved_view["size"])
		screen.survey_camera.projection = int(_saved_view["projection"])
		screen.survey_camera.fov = float(_saved_view["fov"])
		screen.survey_camera.near = float(_saved_view["near"])
		screen.survey_camera.current = screen.overview
		screen.camera.current = not screen.overview
		screen.citizens.visible = bool(_saved_view["citizens"])
		for index in range(screen._hud_panels.size()):
			screen._hud_panels[index].visible = bool(_saved_view["hud"][index])
		screen.command_bar.show()
		screen.drawer.visible = bool(_saved_view["drawer"])
	screen.refresh_city()
	closed.emit()

func refresh() -> void:
	if screen == null:
		return
	snapshot = host.snapshot()
	var active := bool(snapshot.get("active", false))
	var phase := String(snapshot.get("phase", "ready")) if active else "ready"
	var practice := bool(snapshot.get("practice", false))
	var stale := String(snapshot.get("reason", "")) == "stale_battle"
	phase_label.text = w("phase_" + phase)
	summary.text = (w("practice_mode") if practice else w("live_mode")) + " · " + w("turn_status") % [int(snapshot.get("elapsed_ms", 0))/60000, (int(snapshot.get("elapsed_ms",0))/1000)%60, int(snapshot.get("gate_integrity", 100)), int(snapshot.get("objective_progress", 0))] if active else w("subtitle")
	_reconcile_selection()
	_refresh_roster()
	practice_button.visible = not active
	practice_button.disabled = not bool(snapshot.get("can_practice", false))
	defend_button.visible = not active
	defend_button.disabled = not bool(snapshot.get("can_defend", false))
	defend_button.tooltip_text = _reason(String(snapshot.get("reason", "unavailable")))
	start_button.visible = active and phase == "deployment"
	step_button.visible = active and phase == "fighting"
	step_button.text = w("resume" if snapshot.get("paused",true) else "pause")
	if phase=="fighting": phase_label.text=w("paused" if snapshot.get("paused",true) else "running")
	speed_button.visible = active and phase=="fighting"
	speed_button.text = w("speed") % int(snapshot.get("speed",1))
	for action in order_buttons:
		order_buttons[action].visible=active and phase in ["deployment","fighting"]
		order_buttons[action].disabled=stale or (phase=="deployment" and action not in ["move","fire","attack_engine","fire_arrows"])
		order_buttons[action].modulate=UiStyle.ACCENT if action==order_mode else Color.WHITE
		if action=="fire":order_buttons[action].text=w("cease" if selected_formation().get("fire_at_will",true) else "fire")
		if action in ["attack_engine","fire_arrows"]:
			var archers_only := not _selection().is_empty()
			for f in snapshot.get("formations",[]):
				if _selection().has(f["id"]) and f.get("role","")!="archer":archers_only=false
			order_buttons[action].disabled=stale or not archers_only or (action=="fire_arrows" and not snapshot.get("fire_prepared",false)) or (action=="attack_engine" and int(snapshot.get("siege_engine",{}).get("hp",0))<=0)
			order_buttons[action].tooltip_text=w("siege_help")
			if action=="fire_arrows":order_buttons[action].text=w("normal_arrows" if selected_formation().get("incendiary",false) else "fire_arrows")
	var chosen := selected_formation()
	var specialty := String(chosen.get("specialty",""))
	ability_button.visible=active and phase in ["deployment","fighting"]
	ability_button.disabled=stale or phase!="fighting" or specialty=="" or _selection().size()!=1 or int(chosen.get("ability_cooldown_ms",0))>0 or not CityBattleSim.active(chosen) if not chosen.is_empty() else true
	ability_button.text=w("ability_"+specialty)+" · "+_ability_state(chosen) if specialty!="" else w("ability")
	ability_button.tooltip_text=_ability_help(chosen) if specialty!="" else w("ability_help" if snapshot.has("specialists_version") else "ability_legacy")
	hold_button.visible = active and phase in ["deployment", "fighting"]
	hold_button.disabled = selected == "" or stale
	start_button.disabled = stale
	step_button.disabled = stale
	save_button.visible = active
	close_button.visible = active and (practice or phase == "finished" or stale)
	close_button.text = w("discard_stale" if stale else "finish" if phase == "finished" else "end_practice")
	help_label.text = w("selection_help") + "\n" + w("camera_help") if active else w("briefing")
	objective_label.text = w("objective") + "\n" + w("objective_help") % [int(CityBattleSim.rules(screen.game.data)["objective_hold_ms"])/1000, int(CityBattleSim.rules(screen.game.data)["maximum_ms"])/1000]
	var engine: Dictionary=snapshot.get("siege_engine",{})
	if not engine.is_empty():
		var condition := "siege_destroyed" if int(engine["hp"])<=0 else ("siege_burning" if engine["burning"] else ("siege_approaching" if engine["crewed"] else "siege_abandoned"))
		objective_label.text += "\n\n"+w("siege_status") % [roundi(100.0*int(engine["hp"])/int(engine["max_hp"])),w(condition)]
	if active and phase == "finished":
		var result: Dictionary = snapshot.get("result", {})
		var winner := String(result.get("winner", "defender"))
		help_label.text = w("result_" + winner)
		objective_label.text = help_label.text + "\n" + w("result_detail") % [int(result.get("defender_casualty_pct", 0)), int(result.get("attacker_casualty_pct", 0))] + "\n" + (w("practice_result") if practice else w("committed"))
	if stale:
		help_label.text = _reason("stale_battle")
	forces.visible = visible and active
	forces.sync(screen.layout, snapshot, selected, selected_ids)
	inspect_button.visible = active
	inspect_button.disabled = selected == ""
	for button in [overview_button, follow_button, tilt_button]:
		button.visible = active
	follow_button.disabled = _selection().is_empty()
	if inspecting and _view_tick < 0:
		_frame_battle()
	screen.world.set_battle_gate_breached(active and int(snapshot.get("gate_integrity", 100)) <= 0)
	_view_tick=int(snapshot.get("tick",-1))
	plan.queue_redraw()
	queue_redraw()

func _refresh_roster() -> void:
	var signature := ""
	for f in snapshot.get("formations",[]):
		if f["side"]=="defender":signature+=String(f["id"])+";"
	if String(roster.get_meta("signature","none"))!=signature:
		for child in roster.get_children():
			roster.remove_child(child)
			child.queue_free()
		_roster_rows.clear()
		roster.set_meta("signature",signature)
		if signature=="":
			roster.add_child(_paragraph(w("practice_help")))
			roster.add_child(_paragraph(w("counters")))
		for f in snapshot.get("formations",[]):
			if f["side"]!="defender":continue
			var id:=String(f["id"])
			var button:=Button.new()
			button.text=formation_name(f)
			button.set_meta("formation_id",id)
			button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size=Vector2(225,36)
			button.toggle_mode=true
			button.focus_mode=Control.FOCUS_NONE
			button.pressed.connect(select_formation.bind(id))
			roster.add_child(button)
			var detail:=_paragraph("",12)
			roster.add_child(detail)
			var bar:=ProgressBar.new()
			bar.custom_minimum_size.y=6
			bar.show_percentage=false
			roster.add_child(bar)
			_roster_rows[id]={"button":button,"detail":detail,"bar":bar}
	for f in snapshot.get("formations",[]):
		if not _roster_rows.has(f["id"]):continue
		var row:Dictionary=_roster_rows[f["id"]]
		row["button"].button_pressed=f["id"]==selected or selected_ids.has(f["id"])
		row["button"].disabled=not CityBattleSim.active(f)
		var soldiers:=ceili(float(f.get("soldiers",screen.game.data.units.get(f["template"],{}).get("soldiers",120)))*float(f["unit"]["strength_pct"])/100.0)
		row["detail"].text=w("formation_live") % [w("role_"+String(f.get("role","soldier"))),soldiers,int(f["unit"]["experience"]),w("order_routed" if f.get("routed",false) else "order_"+String(f.get("order","hold")))]
		if f.get("specialty","")!="":
			row["detail"].text+="\n"+w("specialty_"+String(f["specialty"]))+" · "+_ability_state(f)
			row["button"].tooltip_text=_ability_help(f)
		row["bar"].value=int(f["unit"]["strength_pct"])

func _ability_state(f: Dictionary) -> String:
	if int(f.get("ability_remaining_ms",0))>0:return w("ability_active") % ceili(float(f["ability_remaining_ms"])/1000)
	if int(f.get("ability_cooldown_ms",0))>0:return w("ability_recovery") % ceili(float(f["ability_cooldown_ms"])/1000)
	return w("ability_ready")

func _ability_help(f: Dictionary) -> String:
	var p := CityBattleSpecialists.profile(screen.game.data,f)
	if p.is_empty():return w("ability_help")
	var duration := int(p["duration_ms"])/1000
	var recovery := int(p["cooldown_ms"])/1000
	var text := ""
	match f["specialty"]:
		"commander":text=w("ability_commander_help") % [duration,int(p["radius_cm"])/100,int(p["morale_bonus"]),roundi((1-float(p["active_resistance"]))*100),roundi((float(p["active_damage"])-1)*100),recovery]
		"veteran":text=w("ability_veteran_help") % [duration,roundi((float(p["active_damage"])-1)*100),int(p["morale_bonus"]),recovery]
		"spear_guard":text=w("ability_spear_guard_help") % [duration,roundi((1-float(p["active_resistance"]))*100),int(p["morale_bonus"]),roundi(float(p["active_speed"])*100),recovery]
	return text+"\n"+w("specialist_passive") % [roundi((float(p["damage"])-1)*100),roundi((1-float(p["resistance"]))*100)]

func formation_name(formation: Dictionary) -> String:
	if formation.get("side", "") != "defender":
		return w("attacker")
	var template := String(formation.get("template", formation.get("unit", {}).get("template", "")))
	return String(screen.game.data.units.get(template, {}).get("name", template))

func selected_formation() -> Dictionary:
	for formation in snapshot.get("formations", []):
		if formation.get("id", "") == selected and formation.get("side", "") == "defender" and CityBattleSim.active(formation):
			return formation
	return {}

func _reconcile_selection() -> void:
	var living: Array = []
	for formation in snapshot.get("formations", []):
		if formation.get("side", "") == "defender" and CityBattleSim.active(formation):
			living.append(String(formation["id"]))
	selected_ids = selected_ids.filter(func(id): return living.has(id))
	if not living.has(selected):
		selected = String(selected_ids[0]) if not selected_ids.is_empty() else ""
	if _auto_select and selected == "" and not living.is_empty():
		selected = String(living[0])
		selected_ids = [selected]
		_auto_select = false
	if selected != "" and not selected_ids.has(selected):
		selected_ids.append(selected)

func select_formation(id: String, additive: bool = false) -> void:
	if not _is_defender(id):
		return
	if not additive and not Input.is_key_pressed(KEY_SHIFT):
		selected_ids.clear()
	if not selected_ids.has(id):
		selected_ids.append(id)
	selected = id
	_auto_select = false
	refresh()
	if _roster_rows.has(id):
		roster_scroll.ensure_control_visible(_roster_rows[id]["button"])
	message_label.text = w("selection_count") % selected_ids.size()

func _is_defender(id: String) -> bool:
	for formation in snapshot.get("formations", []):
		if formation.get("id", "") == id:
			return formation.get("side", "") == "defender" and CityBattleSim.active(formation)
	return false

func clear_selection() -> void:
	selected_ids.clear()
	selected = ""
	_auto_select = false
	refresh()
	message_label.text = w("selection_empty")

func select_rectangle(rectangle: Rect2, additive: bool = false) -> void:
	var selection_rect := rectangle.abs().intersection(battle_rect())
	var chosen: Array = selected_ids.duplicate() if additive else []
	for formation in snapshot.get("formations", []):
		var id := String(formation["id"])
		if not _is_defender(id) or not forces.anchors.has(id):
			continue
		var at := formation_screen_point(id)
		if battle_rect().has_point(at) and selection_rect.has_point(at) and not chosen.has(id):
			chosen.append(id)
	selected_ids = chosen
	selected = String(chosen[0]) if not chosen.is_empty() else ""
	_auto_select = false
	refresh()
	message_label.text = w("selection_count") % chosen.size() if not chosen.is_empty() else w("selection_empty")

func begin(practice: bool) -> void:
	selected_ids.clear()
	selected = ""
	_auto_select = true
	_action(host.invoke("begin",[practice]))

func start() -> void:
	_action(host.invoke("start"))

func step() -> void:
	_action(host.invoke("control",["resume" if snapshot.get("paused",true) else "pause"]))

func hold() -> void:
	_issue("hold")

func _choose_order(action: String) -> void:
	if action in ["fire","fire_arrows","attack_engine"]:
		_issue(action)
	else:
		order_mode=action
		message_label.text=w(action)+" · "+w("command_help")
		refresh()

func _selection() -> Array:
	var result:Array=[]
	for f in snapshot.get("formations",[]):
		if f["side"]=="defender" and CityBattleSim.active(f) and (f["id"]==selected or selected_ids.has(f["id"])):
			result.append(f["id"])
	return result

func _issue(action: String, at: Array = [], target: String = "") -> void:
	var ids := _selection()
	if ids.is_empty():
		message_label.text = w("selection_empty")
		return
	var result := host.invoke("order", [ids, action, at, target])
	_action(result)
	if result.get("ok", false):
		message_label.text = w("command_selection") % [w(action), ids.size()]

func order_to(node_id: String) -> void:
	var p:=node_position(node_id)
	_issue("move" if snapshot.get("phase","")=="deployment" else order_mode,[roundi(p.x*100),roundi(p.z*100)])

func dismiss_session() -> void:
	var result:=host.invoke("close")
	_action(result)
	if result.get("ok",false):close()

func save() -> void:
	var result:=host.invoke("save",[screen.save_path])
	refresh()
	message_label.text=w("saved" if result.get("ok",false) else "save_failed")

func _action(result: Dictionary) -> void:
	message_label.text=w("mode_note") if result.get("ok",false) else _reason(String(result.get("reason","unavailable")))
	refresh()
	if snapshot.get("phase","")=="fighting":host.run()

func _exit_tree() -> void:
	host.stop()

func _reason(reason: String) -> String:
	return w("reason_" + reason) if words.has("reason_" + reason) else w("reason_unavailable")

func node_position(id: String) -> Vector3:
	for node in screen.layout.get("battle", {}).get("nodes", []):
		if node["id"] == id:
			return Vector3(float(node["position"][0]), 0.2, float(node["position"][1]))
	return Vector3.ZERO

func _project(point: Vector3) -> Vector2:
	if screen.survey_camera.is_position_behind(point):
		return Vector2(-100000, -100000)
	return screen.survey_camera.unproject_position(point) * screen.view_container.size / Vector2(screen.viewport.size)

func battle_rect() -> Rect2:
	return Rect2(286, 94, maxf(0, size.x - 592), maxf(0, size.y - 299))

func formation_screen_point(id: String) -> Vector2:
	return _project(Vector3(forces.anchors[id]) + Vector3.UP * 4.0)

func _draw() -> void:
	_node_rects.clear()
	_formation_rects.clear()
	if screen == null or not visible or not bool(snapshot.get("active", false)):
		return
	var central := battle_rect()
	var font := ThemeDB.fallback_font
	for node in screen.layout.get("battle", {}).get("nodes", []):
		var id := String(node["id"])
		var at := _project(node_position(id))
		if not central.has_point(at):
			continue
		var color := UiStyle.ACCENT if id == String(screen.layout.get("battle", {}).get("objective", "")) else Color(0.87, 0.89, 0.78, 0.85)
		draw_circle(at, 8, Color(0.04, 0.06, 0.06, 0.85))
		draw_arc(at, 8, 0, TAU, 24, color, 2, true)
		var caption := w("node_" + id)
		var text_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var label_at := at + Vector2(13, 3)
		draw_style_box(UiStyle._flat(Color(0.035, 0.045, 0.045, 0.87), 3), Rect2(label_at + Vector2(-4, -13), Vector2(text_width + 8, 19)))
		draw_string(font, label_at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
		_node_rects[id] = Rect2(at - Vector2(12, 12), Vector2(24 + text_width, 27))
	for formation in snapshot.get("formations", []):
		var id := String(formation["id"])
		if not forces.anchors.has(id):
			continue
		var at := formation_screen_point(id)
		if not central.has_point(at):
			continue
		var defender: bool = formation.get("side", "") == "defender"
		var color := RomaCityBattleForces.DEFENDER_COLOR if defender else RomaCityBattleForces.ATTACKER_COLOR
		draw_circle(at, 4, color)
		if id == selected or selected_ids.has(id):
			draw_arc(at, 6, 0, TAU, 24, UiStyle.ACCENT, 1.5, true)
		_formation_rects[id] = Rect2(at - Vector2(11, 11), Vector2(22, 22))
		if defender and (id==selected or selected_ids.has(id)) and not formation.get("path",[]).is_empty():
			var dest:Array=formation["destination"]
			var goal:=_project(Vector3(dest[0]/100.0,0.3,dest[1]/100.0))
			if central.has_point(goal):
				draw_dashed_line(at,goal,UiStyle.ACCENT,1.5,5)
				draw_arc(goal,7,0,TAU,20,UiStyle.ACCENT,2,true)

	if _selection_press and _marquee:
		var rectangle := Rect2(_press_point, _drag_point - _press_point).abs().intersection(central)
		draw_rect(rectangle, Color(0.35, 0.68, 0.80, 0.14), true)
		draw_rect(rectangle, UiStyle.ACCENT, false, 1.5)
		for formation in snapshot.get("formations", []):
			var id := String(formation["id"])
			if _is_defender(id) and forces.anchors.has(id) and rectangle.has_point(formation_screen_point(id)):
				draw_arc(formation_screen_point(id), 9, 0, TAU, 20, UiStyle.ACCENT, 1.5, true)

func _cancel_gesture() -> void:
	_selection_press = false
	_marquee = false
	_camera_drag = ""
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_gesture()

func _input(event: InputEvent) -> void:
	if not visible or (not _selection_press and _camera_drag == ""):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_gesture()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_gesture_motion(event.position - global_position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed:
		if _selection_press and event.button_index == MOUSE_BUTTON_LEFT:
			_finish_selection(event.position - global_position)
			get_viewport().set_input_as_handled()
		elif _camera_drag != "" and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_cancel_gesture()
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (_selection_press or _camera_drag != ""):
		_gesture_motion(event.position)
		accept_event()
		return
	if event is InputEventMagnifyGesture:
		camera_rig.zoom(1.0 / maxf(0.1, event.factor), _ground_at(event.position))
		accept_event()
		return
	if event is InputEventPanGesture:
		camera_rig.pan_view(event.delta, 0.08)
		accept_event()
		return
	if event is not InputEventMouseButton:
		return
	if not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _selection_press:
			_finish_selection(event.position)
		elif _camera_drag != "":
			_cancel_gesture()
		return
	if not battle_rect().has_point(event.position):
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.zoom(0.86 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.86, _ground_at(event.position))
		MOUSE_BUTTON_MIDDLE:
			_camera_drag = "orbit" if event.alt_pressed else "pan"
			_camera_pointer = event.position
		MOUSE_BUTTON_LEFT:
			if event.alt_pressed:
				_camera_drag = "orbit"
				_camera_pointer = event.position
			else:
				_selection_press = true
				_marquee = false
				_gesture_additive = event.shift_pressed
				_gesture_double = event.double_click
				_press_point = event.position
				_drag_point = event.position
		MOUSE_BUTTON_RIGHT:
			_cancel_gesture()
			command_at(event.position)
	accept_event()

func _ground_at(point: Vector2) -> Variant:
	return camera_rig.ground_at(point * Vector2(screen.viewport.size) / screen.view_container.size)

func _gesture_motion(point: Vector2) -> void:
	if _camera_drag != "":
		if _camera_drag == "orbit":
			camera_rig.orbit(point - _camera_pointer)
		else:
			var before: Variant = _ground_at(_camera_pointer)
			var after: Variant = _ground_at(point)
			if before is Vector3 and after is Vector3:
				camera_rig.pan_ground(before - after)
		_camera_pointer = point
	elif _selection_press:
		_drag_point = point
		_marquee = _marquee or _press_point.distance_to(point) >= DRAG_THRESHOLD
	queue_redraw()

func _finish_selection(point: Vector2) -> void:
	var was_marquee := _marquee or _press_point.distance_to(point) >= DRAG_THRESHOLD
	_selection_press = false
	_marquee = false
	# A release over a HUD panel cancels the gesture rather than sending an
	# accidental ground command through that panel.
	if not battle_rect().has_point(point):
		queue_redraw()
		return
	if was_marquee:
		select_rectangle(Rect2(_press_point, point - _press_point), _gesture_additive)
	else:
		var id := _hit_formation(point)
		if id != "" and _is_defender(id):
			select_formation(id, _gesture_additive)
			if _gesture_double:
				follow_selection()
		else:
			if not _gesture_additive:
				clear_selection()
	queue_redraw()

func _hit_formation(point: Vector2, side: String = "") -> String:
	var nearest := 12.0
	var chosen := ""
	for formation in snapshot.get("formations", []):
		var id := String(formation["id"])
		if not forces.anchors.has(id) or (side != "" and formation["side"] != side):
			continue
		var at := formation_screen_point(id)
		if not battle_rect().has_point(at):
			continue
		var distance := point.distance_to(at)
		if distance < nearest:
			nearest = distance
			chosen = id
	return chosen

func command_at(point: Vector2) -> void:
	var target := _hit_formation(point, "attacker")
	if target != "" and snapshot.get("phase", "") != "deployment":
		_issue("charge" if order_mode == "charge" else "attack", [], target)
		return
	var at: Variant = _ground_at(point)
	if at is Vector3:
		command_ground(Vector2(at.x, at.z))

func command_ground(at: Vector2) -> void:
	var action := "move" if snapshot.get("phase", "") == "deployment" else ("attack_move" if order_mode == "charge" else order_mode)
	_issue(action, [roundi(at.x * 100), roundi(at.y * 100)])

func _process(delta: float) -> void:
	if not visible:
		return
	_poll += delta
	if _poll >= 0.05:
		_poll = 0
		var latest := host.snapshot()
		if int(latest.get("tick", -1)) != _view_tick or latest.get("phase", "") != snapshot.get("phase", ""):
			refresh()
	if get_window().has_focus() and not _selection_press and _camera_drag == "":
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is not LineEdit and focus_owner is not TextEdit and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META):
			var movement := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
			if movement != Vector2.ZERO:
				camera_rig.pan_view(movement.normalized(), delta)
			var orbit_input := Vector2(float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)), float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
			if orbit_input != Vector2.ZERO:
				camera_rig.orbit(orbit_input * delta * 85.0)
	camera_rig.update(delta, _selection_center() if not _selection().is_empty() else null)
	follow_button.modulate = UiStyle.ACCENT if camera_rig.following else Color.WHITE
	queue_redraw()
	plan.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or event is not InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			if _selection_press or _camera_drag != "":
				_cancel_gesture()
			else:
				close()
		KEY_SPACE:
			if snapshot.get("phase", "") == "fighting":
				step()
		KEY_F:
			follow_selection()
		KEY_V:
			show_overview()
		KEY_H:
			hold()
		KEY_A:
			if not event.ctrl_pressed and not event.meta_pressed:
				return
			selected_ids.clear()
			for formation in snapshot.get("formations", []):
				if _is_defender(String(formation["id"])):
					selected_ids.append(String(formation["id"]))
			selected = String(selected_ids[0]) if not selected_ids.is_empty() else ""
			_auto_select = false
			refresh()
		_:
			return
	get_viewport().set_input_as_handled()

class BattlePlan extends Control:
	var panel: RomaCityBattlePanel
	var node_points: Dictionary = {}
	var formation_points: Dictionary = {}
	var _panning := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		tooltip_text = panel.w("camera_plan_help")

	func map_scale() -> float:
		var extent := float(panel.screen.layout.get("extent", 180)) + 8.0
		return minf((size.x - 20) / extent, (size.y - 20) / extent)

	func map_point(point: Vector2) -> Vector2:
		return size * 0.5 + point * map_scale()

	func ground_point(point: Vector2) -> Vector2:
		return (point - size * 0.5) / maxf(0.01, map_scale())

	func center_camera(point: Vector2) -> void:
		var ground := ground_point(point)
		panel.camera_rig.center(Vector3(ground.x, 0.6, ground.y))
		queue_redraw()

	func _draw() -> void:
		node_points.clear()
		formation_points.clear()
		if panel == null:
			return
		draw_style_box(UiStyle._flat(Color("#172020"), 4), Rect2(Vector2.ZERO, size))
		var scale_by := map_scale()
		for building in panel.screen.layout.get("buildings", []):
			var center := map_point(Vector2(building["position"][0], building["position"][1]))
			var footprint := Vector2(building["size"][0], building["size"][1]) * scale_by
			draw_rect(Rect2(center - footprint * 0.5, footprint), Color("#4c5048"))
		for road in panel.screen.layout.get("roads", []):
			var points: Array = road.get("points", [])
			for index in range(points.size() - 1):
				draw_line(map_point(Vector2(points[index][0], points[index][1])), map_point(Vector2(points[index+1][0], points[index+1][1])), Color("#777563"), maxf(1, float(road.get("width", 4)) * scale_by))
		for node in panel.screen.layout.get("battle", {}).get("nodes", []):
			var id := String(node["id"])
			var world_at := panel.node_position(id)
			var at := map_point(Vector2(world_at.x, world_at.z))
			node_points[id] = at
			for neighbor in node.get("neighbors", []):
				var other := panel.node_position(String(neighbor))
				draw_line(at, map_point(Vector2(other.x, other.z)), Color(0.85, 0.79, 0.57, 0.45), 1, true)
			draw_circle(at, 3.5, UiStyle.ACCENT if node["role"] == "objective" else Color("#d4c8a4"))
			var caption := panel.w("node_" + id)
			var text_width := ThemeDB.fallback_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var text_at := at + Vector2(9, -7)
			if node.get("role", "") == "reserve":
				text_at = Vector2(5 if world_at.x < 0 else size.x - text_width - 5, at.y - 14)
			elif node.get("neighbors", []).size() > 2:
				text_at = at + Vector2(-text_width * 0.5, 18)
			if node.get("role", "") in ["objective", "gate"]:
				draw_string(ThemeDB.fallback_font, text_at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiStyle.TEXT)
		for formation in panel.snapshot.get("formations", []):
			var id := String(formation["id"])
			if not panel.forces.anchors.has(id):
				continue
			var world_at: Vector3 = panel.forces.anchors[id]
			var at := map_point(Vector2(world_at.x, world_at.z))
			var defender: bool = formation.get("side", "") == "defender"
			draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), RomaCityBattleForces.DEFENDER_COLOR if defender else RomaCityBattleForces.ATTACKER_COLOR)
			formation_points[id] = at
			if id == panel.selected or panel.selected_ids.has(id):
				draw_arc(at, 6, 0, TAU, 18, UiStyle.ACCENT, 1.5, true)

		var view := panel.battle_rect()
		var outline := PackedVector2Array()
		for point in [view.position, Vector2(view.end.x, view.position.y), view.end, Vector2(view.position.x, view.end.y)]:
			var ground: Variant = panel._ground_at(point)
			if ground is Vector3:
				outline.append(map_point(Vector2(ground.x, ground.z)))
		if outline.size() == 4:
			outline.append(outline[0])
			draw_polyline(outline, Color(0.81, 0.91, 0.96, 0.65), 1.0, true)
		var camera_at := map_point(Vector2(panel.camera_rig.focus.x, panel.camera_rig.focus.z))
		draw_line(camera_at - Vector2(4, 0), camera_at + Vector2(4, 0), Color.WHITE, 1.0)
		draw_line(camera_at - Vector2(0, 4), camera_at + Vector2(0, 4), Color.WHITE, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			if _panning:
				if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
					center_camera(event.position)
				else:
					_panning = false
				accept_event()
			return
		if event is not InputEventMouseButton:
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			if _panning:
				center_camera(event.position)
			accept_event()
			return
		if not event.pressed:
			return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var ground := ground_point(event.position)
			panel.camera_rig.zoom(0.86 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.86, Vector3(ground.x, 0, ground.y))
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			center_camera(event.position)
			accept_event()
			return
		var nearest := 3.0 if event.button_index == MOUSE_BUTTON_LEFT else 7.0
		var picked := ""
		for id in formation_points:
			var distance: float = event.position.distance_to(formation_points[id])
			if distance < nearest:
				nearest = distance
				picked = String(id)
		if picked != "":
			if panel._is_defender(picked) and event.button_index == MOUSE_BUTTON_LEFT:
				panel.select_formation(picked, event.shift_pressed)
				accept_event()
				return
			if not panel._is_defender(picked) and event.button_index == MOUSE_BUTTON_RIGHT:
				panel._issue("charge" if panel.order_mode == "charge" else "attack", [], picked)
				accept_event()
				return
		if event.button_index == MOUSE_BUTTON_LEFT:
			center_camera(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			panel.command_ground(ground_point(event.position))
		accept_event()
