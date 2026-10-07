extends "res://tools/household_preview.gd"
var timings: Dictionary={}
func _initialize() -> void:
	out_dir="/tmp/yenikapi-visual-qa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;var ui=app.visual_commands;p.save_path=out_dir.path_join("visual-save.json")
	if FileAccess.file_exists(p.save_path):DirAccess.remove_absolute(p.save_path)
	await shot("01-visual-welcome")
	await click_button("VisualNew")
	check(p.state.food==100 and p.state.wood==30 and p.rules.living.active(p.state),"visual start uses ordinary resources and rules")
	check(not p.rules.incidents.active(p.state),"incidents remain explicit")
	await shot("02-building-dock")
	await click_button("VisualPlace_fields");await click_button("VisualProject_land_cultivate")
	check(p.state.wood==30 and p.state.queue.is_empty(),"preview does not spend or queue")
	await shot("03-project-review")
	await click_button("VisualCommission")
	check(p.state.wood==18 and p.state.queue.size()==1,"commission pays real timber exactly once")
	await shot("04-work-underway")
	await click_button("VisualPause");check(p.state.assets.initiatives.land_cultivate.paused,"pause real project")
	await click_button("VisualPause");check(not p.state.assets.initiatives.land_cultivate.paused,"resume real project")
	await click_button("VisualClose")
	await click_button("VisualPlace_stores");await click_button("VisualPage_orders");await click_button("VisualPrinciple_reserve");await click_button("VisualChoice_0")
	check(p.state.assets.reserve==1,"icon order uses ordinary reserve command")
	await shot("05-standing-choice")
	await click_button("VisualClose")
	var expected: Dictionary=p.rules.forecast(p.state)
	await click_button("VisualSeason")
	check(p.state.report==expected,"visual season equals authoritative forecast")
	await click_button("VisualSeason")
	check(p.rules.has_project(p.state,"land_cultivate"),"finite crews finish cultivation")
	await click_button("Visual_report");await shot("06-season-report");await click_button("VisualClose")
	await click_button("Visual_growth");await shot("07-connected-growth-guide")
	await click_button("VisualProject_land_outer_west")
	check(ui.find_child("VisualCommission",true,false)!=null and ui.find_child("VisualCommission",true,false).disabled,"outer home visibly needs its connection")
	await shot("08-locked-outer-home")
	var model_before: String=JSON.stringify(p.state)
	await click_button("VisualStage_current");await shot("08a-unbuilt-current-site")
	check(ui.preview_mesh("land_outer_west",false)==null,"current unbuilt site has no unrelated house")
	await click_button("VisualStage_planned");check(JSON.stringify(p.state)==model_before,"unbuilt model comparison is pure")
	await click_button("VisualClose")
	await click_button("VisualPlace_workroom");await click_button("VisualPage_orders");await click_button("VisualOrder_prepare");await click_button("VisualChoice_1")
	check(p.state.living.prepare==1,"material order dispatched")
	await click_button("VisualClose");await click_button("VisualSeason")
	check(p.state.living.blanks>0,"ordinary paid labor prepares material")
	check(ui.find_child("VisualOrder_prepare",true,false).get_child(0).get_child(2).text==ui.copy.living_orders[1].labels[1],"ordinary preparation label agrees with actual order")
	await click_button("VisualInspect");await shot("09-local-knowledge")
	var before: String=JSON.stringify(p.state)
	for i in range(3):ui.refresh()
	for delta in [.008,.016,.033,.1]:app.campaign_view.life._process(delta)
	check(JSON.stringify(p.state)==before,"redraw and frame rates cannot change state")
	await click_button("VisualClose");await click_button("VisualVisit");await shot("10-workshop-interior")
	await click_button("VisualSave");var saved: String=JSON.stringify(p.state)
	await click_button("VisualSeason");var loaded: bool=p.load_campaign()
	FileAccess.open(out_dir.path_join("save-before.json"),FileAccess.WRITE).store_string(saved)
	FileAccess.open(out_dir.path_join("save-after.json"),FileAccess.WRITE).store_string(JSON.stringify(p.state))
	check(loaded and JSON.stringify(p.state)==saved,"visual save uses unchanged additive save contract")
	ui.open();await click_button("Visual_incident");await click_button("VisualBeginIncidents")
	check(p.rules.incidents.active(p.state),"incident adoption uses public command")
	await click_button("VisualClose")
	for i in range(6):await click_button("VisualSeason")
	check(ui.find_child("VisualWarning",true,false)!=null,"overview warning remains prominent")
	await click_button("VisualWarning");await shot("11-warning-response")
	await click_button("VisualProject_incident_approach_prepare");await click_button("VisualCommission")
	await click_button("VisualClose")
	for i in range(2):await click_button("VisualSeason")
	await click_button("VisualWarning");await shot("12-incident-outcome")
	await click_button("VisualProject_incident_approach_repair");await click_button("VisualCommission")
	await click_button("VisualPause");await shot("13-recovery-paused");await click_button("VisualPause");await click_button("VisualClose")
	for i in range(5):
		if p.rules.has_project(p.state,"incident_approach_repair"):break
		await click_button("VisualSeason")
	check(p.rules.has_project(p.state,"incident_approach_repair"),"recovery commissioned and finished through dock")
	await shot("14-recovered-village")
	root.size=Vector2i(1024,768)
	await click_button("Visual_growth");await shot("15-small-growth")
	await click_button("VisualProject_land_court_home");await shot("16-small-project")
	check(ui.dock.get_global_rect().end.x<=root.get_visible_rect().size.x and ui.sheet.get_global_rect().end.y<=ui.dock.get_global_rect().position.y,"dock and detail fit smaller window")
	await click_button("VisualClose")
	await click_button("VisualPlace_stores");await click_button("VisualVisit");await shot("17-small-store-interior")
	await click_button("Visual_help");await shot("18-connected-lesson")

	await click_button("VisualClose")
	root.size=Vector2i(1600,1000)
	# Resume the real pre-incident save; complete both choices using real controls.
	for layout in ["compact","outward"]:
		await click_button("VisualLoad")
		check(not p.rules.incidents.active(p.state),"saved pre-incident rules retained "+layout)
		var projects: Array=["land_court_home","land_adapt_workroom","land_hearth_home"] if layout=="compact" else ["land_outer_access","land_outer_west","land_outer_east"]
		for id in projects:await build_project(id)
		check(p.rules.capacity(p.state)>=48,"real additional housing "+layout)
		await click_button("VisualAerial");await shot("19-"+layout+"-growth")
		validate_routes(layout+" visual commands")
		await click_button("Visual_growth");await shot("20-"+layout+"-completed-guide");await click_button("VisualClose")
	# Real geometry selection changes the building context without issuing work.
	for b in app.world.buildings:
		if b.id!="yk_store_01":continue
		var target: Vector3=app.world.building_position(b,Vector3(0,1,0))
		app.set_view(target+Vector3(0,10,12),target)
		await process_frame
		var stable: String=JSON.stringify(p.state)
		await click_at(root.get_visible_rect().size*.5)
		check(ui.selected=="stores" and JSON.stringify(p.state)==stable,"world picking selects real store without spending")
		await shot("21-world-building-selection")
	await click_button("VisualProject_shared_store")
	var preview_state: String=JSON.stringify(p.state)
	await click_button("VisualStage_current");await shot("22-current-store-model")
	await click_button("VisualStage_planned");await shot("23-planned-store-model")
	check(JSON.stringify(p.state)==preview_state,"model comparison cannot commission or advance")
	await click_button("VisualClose")
	await click_button("VisualMenu");await click_button("VisualNew")
	check(JSON.stringify(p.state)==preview_state,"new settlement requires explicit UI confirmation")
	await click_button("VisualConfirmNew")
	check(p.state.turn==0 and p.state.wood==30,"confirmed new village uses real starting stocks")
	check(preload("res://src/campaign_save.gd").read(p.save_path,p.rules).turn==3,"new game leaves existing save untouched")
	check(p.rules.validate_state(p.state),"final state validates")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"timings":timings,"ui_timings":ui.timings},"  "))
	print("VISUAL RENDER: ",captures.size()," captures; ",checks," checks, ",failures," failures; timings ",JSON.stringify(timings));quit(1 if failures else 0)
func click_button(id: String) -> void:
	for i in range(3):await process_frame
	var button: Button=app.find_child(id,true,false)
	if button==null:check(false,"missing control "+id);return
	var parent: Node=button.get_parent()
	while parent!=null:
		if parent is ScrollContainer:parent.ensure_control_visible(button)
		parent=parent.get_parent()
	for i in range(3):await process_frame
	check(button.is_visible_in_tree() and not button.disabled,"available control "+id)
	if button.disabled:return
	var window: Window=button.get_window()
	if window!=root:window.grab_focus()
	var at: Vector2=button.get_global_rect().get_center();window.warp_mouse(at)
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;window.push_input(motion,true)
	await process_frame
	var start: int=Time.get_ticks_usec()
	for pressed in [true,false]:
		window.warp_mouse(at)
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;window.push_input(event,true)
		await process_frame
	timings[id]=Time.get_ticks_usec()-start

func build_project(id: String) -> void:
	var ui=app.visual_commands;var p=app.campaign
	await click_button("VisualPlace_"+p.rules.assets.project_assets[id])
	if ui.page!="projects":await click_button("VisualPage_projects")
	await click_button("VisualProject_"+id)
	await click_button("VisualCommission");await click_button("VisualClose")
	for season in range(12):
		if p.rules.has_project(p.state,id):break
		await click_button("VisualSeason")
	check(p.rules.has_project(p.state,id),"completed from ordinary stocks "+id)
func click_at(at: Vector2) -> void:
	root.warp_mouse(at)
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true);await process_frame
	for pressed in [true,false]:
		root.warp_mouse(at)
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;root.push_input(e,true);await process_frame
