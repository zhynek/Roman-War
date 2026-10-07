extends "res://tools/visual_preview.gd"
func _initialize() -> void:
	out_dir="/tmp/yenikapi-construction-qa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;var ui=app.visual_commands;p.save_path=out_dir.path_join("construction-save.json")
	app.hud.show();ui.open()
	await shot("00-construction-welcome")
	await click_button("VisualNew")
	await click_button("VisualOversight");await shot("01-central-project-overview")
	await click_button("EnterPlanningRoom");await shot("02-planning-room-board")
	check(not app.world.blocked(app.camera.position),"planning viewpoint is physically accessible")
	await pick_plan("care_shelter")
	check(ui.room().selected=="care_shelter" and ui.detail.is_empty(),"physical board selects easel without opening separate controls")
	await shot("03-selected-easel")
	await pick_plan("easel")
	check(ui.detail.get("id")=="care_shelter","easel opens correct shared project interface")
	await shot("04-easel-enlarged-plan")
	await click_button("VisualCommission")
	check(p.state.wood==18 and ui.queued("care_shelter").progress==0,"easel commissions through ordinary payment")
	await spin("Visual_crew",1)
	await spin("Visual_priority",1)
	await click_button("VisualClose")
	check(ui.room_mode,"close enlarged view returns naturally to room")
	await shot("05-room-with-active-plan")
	await click_button("PlanningLeave")
	await click_button("VisualOversight");await click_button("VisualProject_care_shelter")
	await shot("05a-overview-reopened")
	check(ui.find_child("Visual_crew",true,false)!=null,"overview exposes shared controls")
	if ui.find_child("Visual_crew",true,false)==null:quit(1);return
	check(ui.find_child("Visual_crew",true,false).value==1,"overview sees room staffing")
	await click_button("VisualVisitProject")
	await site_shot("care_shelter","06-site-preparation")
	await pick_site("care_shelter")
	check(ui.detail.get("id")=="care_shelter","click actual partial structure opens same project")
	await shot("07-site-material-worker-result")
	await click_button("VisualClose")
	await click_button("VisualSeason")
	await site_shot("care_shelter","08-support-stage")
	await pick_site("care_shelter");await click_button("VisualPause")
	var paused: Dictionary=ui.projects.describe(p.state,p.rules,"care_shelter")
	await shot("09-paused-site-review")
	await click_button("VisualSave");await click_button("VisualClose");await click_button("VisualSeason")
	check(ui.projects.describe(p.state,p.rules,"care_shelter").progress==paused.progress,"paused work remains still through a season")
	await click_button("VisualLoad")
	check(ui.projects.describe(p.state,p.rules,"care_shelter").stage==paused.stage,"save restores partial structure")
	await click_button("VisualOversight");await click_button("EnterPlanningRoom");await pick_plan("care_shelter");await pick_plan("easel")
	check(ui.find_child("VisualPause",true,false).text==ui.w("unpause"),"room sees site pause")
	await click_button("VisualPause");await click_button("VisualClose");await click_button("PlanningLeave")
	for step in range(2):
		await click_button("VisualSeason")
		await site_shot("care_shelter",["10-frame-stage","11-roof-stage"][step])
	if p.rules.forecast(p.state).assets.projects.care_shelter.work==0:
		await pick_site("care_shelter");await shot("11a-actual-labor-shortage");await click_button("VisualClose")
	for i in range(8):
		if p.rules.has_project(p.state,"care_shelter"):break
		await click_button("VisualSeason")
	await site_shot("care_shelter","12-completed-use")
	check(p.rules.has_project(p.state,"care_shelter"),"normal crews finish paid building")
	validate_routes("construction completion")
	# Real competing crews and a legitimate partial cancellation.
	await build_review("shared_store")
	await click_button("VisualCommission");await spin("Visual_crew",1);await click_button("VisualClose")
	await build_review("council_ground")
	await click_button("VisualCommission");await spin("Visual_crew",4);await click_button("VisualClose")
	await click_button("VisualOversight");await shot("13-competing-projects")
	await click_button("VisualClose");await click_button("VisualSeason")
	await build_review("shared_store")
	var refund: Dictionary=ui.projects.describe(p.state,p.rules,"shared_store")
	var wood: int=p.state.wood
	await shot("14-partial-adaptation-refund")
	await click_button("VisualCancel")
	check(p.state.wood==wood+refund.refund_wood,"shared controls refund only unused commitment")
	await click_button("VisualClose")
	# Locked prerequisite and an existing working room remain honest.
	await build_review("land_outer_west");await shot("15-required-access")
	check(ui.find_child("VisualCommission",true,false).disabled,"missing northern access is shown")
	await click_button("VisualClose")
	root.size=Vector2i(1024,768)
	await click_button("VisualOversight");await shot("16-small-overview")
	await click_button("EnterPlanningRoom");await shot("17-small-room")
	await pick_plan("council_ground");await pick_plan("easel");await shot("18-small-enlarged-plan")
	check(ui.sheet.get_global_rect().end.y<=ui.dock.get_global_rect().position.y,"small enlarged review fits between header and dock")
	var stable: String=JSON.stringify(p.state)
	for i in range(30):await process_frame
	ui.refresh();ui.close_sheet();ui.look_at_board()
	check(JSON.stringify(p.state)==stable,"inspection and animation produce no work or supplies")
	await click_button("PlanningLeave")
	root.size=Vector2i(1600,1000)
	await incident_preservation()
	app.hud.hide();app.set_view(Vector3(90,68,118),Vector3(-9,2,8));await shot("19-landscape")
	app.overview();await shot("20-aerial")
	app.visit(1);await shot("21-street")
	await interior("yk_house_06","22-working-room-interior")
	validate_routes("planning room final")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures},"  "))
	print("CONSTRUCTION RENDER: %d captures; %d checks, %d failures"%[captures.size(),checks,failures]);quit(1 if failures else 0)
func build_review(id: String) -> void:
	await click_button("VisualOversight");await click_button("VisualProject_"+id)
func spin(id: String,value: int) -> void:
	var control: SpinBox=app.find_child(id,true,false)
	check(control!=null,"staffing control exists "+id)
	if control==null:return
	var parent: Node=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer:parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await process_frame
	var edit: LineEdit=control.get_line_edit();await click_at(edit.get_global_rect().get_center());edit.select_all()
	for character in str(value):
		var key:=InputEventKey.new();key.unicode=character.unicode_at(0);key.pressed=true;root.push_input(key)
	var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=true;root.push_input(enter)
	for i in range(3):await process_frame
func pick_plan(id: String) -> void:
	var room=app.visual_commands.room()
	if id!="easel":
		for i in range(8):
			if id in room.page_ids():break
			await click_button("PlanningNext")
		await click_button("PlanningBoard")
	for target in room.targets:
		if target.id!=id:continue
		for i in range(3):await process_frame
		var point: Vector2=app.camera.unproject_position(target.at)
		check(root.get_visible_rect().has_point(point),"plan target visible "+id)
		await click_at(point);return
	check(false,"missing physical plan "+id)
func site_shot(id: String,name_: String) -> void:
	var at: Array=app.campaign.rules.projects[id].at
	var b: Dictionary=preload("res://src/construction_view.gd").building_record(id,app.campaign.rules)
	if not b.is_empty():at=b.at
	var center:=Vector3(at[0],app.world.floor_height(at[0],at[1]),at[1])
	app.set_view(center+Vector3(8,7,11),center+Vector3.UP*1.5)
	app.visual_commands.close_sheet();await shot(name_)
func pick_site(id: String) -> void:
	var view=app.campaign_view.construction_view
	check(view.sites.has(id),"site exists "+id)
	if not view.sites.has(id):return
	var site: Dictionary=view.sites[id]
	# Aim at actual paid material geometry, not a synthetic project callback.
	var target: Vector3=site.at+Basis(Vector3.UP,float(site.yaw))*Vector3(site.half.x-.28,.22,-site.half.y+.8)
	await click_at(app.camera.unproject_position(target))

func incident_preservation() -> void:
	var ui=app.visual_commands;var p=app.campaign
	await click_button("VisualMenu");await click_button("VisualNew");await click_button("VisualConfirmNew")
	await click_button("VisualPlace_stores");await click_button("VisualPage_orders");await click_button("VisualPrinciple_reserve");await click_button("VisualChoice_0");await click_button("VisualClose")
	await click_button("VisualPlace_workroom")
	if ui.page!="orders":await click_button("VisualPage_orders")
	await click_button("VisualOrder_prepare");await click_button("VisualChoice_1");await click_button("VisualClose")
	await click_button("Visual_incident");await click_button("VisualBeginIncidents");await click_button("VisualClose")
	for incident in ["approach_01","stores_01"]:
		for i in range(65):
			var e: Dictionary=p.rules.incidents.current(p.state)
			if not e.is_empty() and e.id==incident and p.state.turn==int(e.due)-2:break
			if not e.is_empty() and not e.outcome.is_empty() and e.recovered<0:
				var repair: String=p.rules.incidents.specs[e.id].repair
				if not p.rules.land.committed(p.state,repair,p.rules):
					await build_review(repair);await click_button("VisualCommission");await click_button("VisualClose")
			await click_button("VisualSeason")
		var ids: Array=["care_shelter","council_ground"] if incident=="approach_01" else ["shared_store","land_adapt_workroom"]
		for id in ids:
			await build_review(id);await click_button("VisualCommission");await spin("Visual_crew",1);await spin("Visual_priority",1);await click_button("VisualClose")
		await click_button("VisualSeason")
		await build_review(ids[1]);await click_button("VisualPause");await shot("incident-"+incident+"-paused-investment");await click_button("VisualClose")
		p.save_path=out_dir.path_join(incident+"-before.json");await click_button("VisualSave")
		var before: Dictionary=p.state.duplicate(true)
		var expected: Dictionary=p.rules.forecast(p.state)
		var meshes: Dictionary={}
		for id in ids:meshes[id]=hash(app.world.object_nodes[ui.construction().sites[id].owner].mesh.get_faces())
		await site_shot(ids[1],"incident-"+incident+"-site-before")
		await click_button("VisualSeason")
		check(not p.rules.incidents.current(p.state).outcome.is_empty(),"real incident resolution "+incident)
		var after: Dictionary=p.state.duplicate(true)
		for id in ids:
			var a: Dictionary=ui.projects.describe(before,p.rules,id);var b: Dictionary=ui.projects.describe(after,p.rules,id)
			check(b.queued and b.paid_wood==a.paid_wood and b.paid_blanks==a.paid_blanks,"incident retains paid site "+id)
			check(b.progress==a.progress+expected.assets.projects[id].work,"incident never resets or grants work "+id)
		check(hash(app.world.object_nodes[ui.construction().sites[ids[1]].owner].mesh.get_faces())==meshes[ids[1]],"paused partial geometry survives incident exactly")
		await site_shot(ids[1],"incident-"+incident+"-site-after")
		p.save_path=out_dir.path_join(incident+"-after.json");await click_button("VisualSave")
		p.save_path=out_dir.path_join(incident+"-before.json");await click_button("VisualLoad")
		check(p.state==before,"pre-incident UI load preserves accumulated investment")
		await click_button("VisualSeason");check(p.state==after,"loaded incident replay agrees exactly")
		p.save_path=out_dir.path_join(incident+"-after.json");await click_button("VisualLoad")
		check(p.state==after,"post-incident UI load preserves accumulated investment")
		await click_button("VisualWarning");await shot("incident-"+incident+"-outcome");await click_button("VisualClose")
		validate_routes("retained sites "+incident)
