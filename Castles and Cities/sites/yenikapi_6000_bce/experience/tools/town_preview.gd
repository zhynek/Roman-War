extends "res://tools/lifecycle_preview.gd"
const TownDriver=preload("res://tools/town_driver.gd")
var town_seen: Dictionary={}
var public_trace: Array=[]
var saved_trace: Array=[]
var trace_initial: Dictionary={}
func _initialize() -> void:
	out_dir="/tmp/yenikapi-town-render"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,800);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;var ui=app.visual_commands
	p.save_path=out_dir.path_join("town-ui-save.json")
	if FileAccess.file_exists(p.save_path):DirAccess.remove_absolute(p.save_path)
	app.hud.show();ui.open();await click_button("VisualNew")
	trace_initial=p.state.duplicate(true)
	ui.command_applied.connect(func(action):public_trace.append(action.duplicate(true)))
	ui.save_finished.connect(func(writing):
		if writing:saved_trace=public_trace.duplicate(true)
		else:public_trace=saved_trace.duplicate(true))
	await lifecycle_input({"kind":"lifecycle_begin"})
	await click_button("VisualLifecycle");await shot("00-explicit-town-extension")
	await lifecycle_input({"kind":"lifecycle_town_begin"})
	await click_button("VisualLifecycle");await shot("01-small-village-blocked")
	await click_button("VisualClose")
	for step in range(360):
		if TownDriver.finished_town(p.rules,p.state):break
		var action: Dictionary=TownDriver.town_action(p.rules,p.state,true)
		if not action.is_empty():
			if action.kind=="commission" and String(action.id).begins_with("town_"):
				await before_town_commission(action.id)
			await lifecycle_input(action)
		else:
			if p.state.turn>=100:break
			var expected: Dictionary=p.rules.advance(p.state).state
			transcript.append({"turn":p.state.turn,"action":{"kind":"advance"}})
			await click_button("VisualSeason")
			check(p.state==expected,"actual seasonal town progression equals public rules")
		await capture_milestones()
		await town_milestones()
		if failures>0:break
	check(TownDriver.finished_town(p.rules,p.state),"small village continues through paid town and both facilities")
	if TownDriver.finished_town(p.rules,p.state):
		await lifecycle_input({"kind":"living_order","id":"prepare","value":1})
		for i in range(8):
			var f: Dictionary=p.rules.forecast(p.state)
			if f.town.prepared>0 and f.town.saved>0:break
			await click_button("VisualSeason")
		await click_button("VisualLifecycle");await shot("20-town-operation-and-responsibilities")
		check(ui.forecast.town.prepared>0 and ui.forecast.town.saved>0,"both facility benefits active")
		await click_button("VisualClose")
		await input_stress()
		app.hud.hide();app.set_view(Vector3(90,68,118),Vector3(-9,2,8));await shot("30-town-landscape")
		app.overview();await shot("31-town-aerial")
		app.visit(1);await shot("32-town-street")
		await interior("lifecycle_assembly_shelter","33-civic-interior-retained-mat")
		await interior("yk_house_04","34-material-preparation-use")
		await interior("growth_care_shelter","35-local-provision-use")
		app.hud.show();await click_button("VisualOversight");await click_button("EnterPlanningRoom");await shot("36-retained-planning-room")
		await pick_plan("town_civic");await pick_plan("easel");await shot("37-civic-completed-plan")
		await click_button("VisualClose");await click_button("PlanningLeave")
		root.size=Vector2i(1024,768)
		await click_button("VisualLifecycle");await shot("38-small-town-interface")
		check(is_instance_valid(ui.sheet) and ui.sheet.get_global_rect().end.y<=ui.dock.get_global_rect().position.y,"town controls fit small window")
		await click_button("VisualClose")
		validate_routes("town and specialist destinations")
		var cold=preload("res://src/village.gd").new();root.add_child(cold);cold.build(app.world.data)
		for id in cold.object_nodes:
			check(app.world.object_nodes.has(id) and app.world.object_nodes[id].mesh.get_faces()==cold.object_nodes[id].mesh.get_faces(),"town retained/adapted geometry equals cold build "+id)
		cold.free()
		var saved: Dictionary=p.state.duplicate(true)
		await click_button("VisualSave");await click_button("VisualSeason");await click_button("VisualLoad")
		check(p.state==saved,"completed town save restores exact obligations and projects")
		for i in range(30):await process_frame
		ui.refresh();check(p.state==saved,"animation and repeated inspection do not mutate state")
		await double_season()
	var replay: Dictionary=trace_initial
	for action in public_trace:
		var result: Dictionary=p.rules.advance(replay) if action.kind=="advance" else p.rules.command(replay,action)
		check(result.has("state"),"recorded actual UI command replays")
		if not result.has("state"):break
		replay=result.state
	check(replay==p.state,"full UI progression agrees exactly with replayed public-command recipe")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"commands":public_trace,"sha256":JSON.stringify(p.state).sha256_text(),"turn":p.state.turn,"ui_timings":ui.timings},"  "))
	print("TOWN RENDER: %d captures; %d checks, %d failures"%[captures.size(),checks,failures]);quit(1 if failures else 0)

func lifecycle_input(action: Dictionary) -> void:
	if action.kind=="commission" and action.id=="town_civic":
		var p=app.campaign
		var expected: Dictionary=p.rules.command(p.state,action)
		await click_button("VisualOversight");await click_button("EnterPlanningRoom")
		await pick_plan(action.id);await pick_plan("easel");await click_button("VisualCommission")
		check(p.state==expected.state,"physical easel commissions the same paid civic contract")
		await click_button("VisualClose");await click_button("PlanningLeave");return
	if action.kind!="lifecycle_town_begin":await super.lifecycle_input(action);return
	var expected: Dictionary=app.campaign.rules.command(app.campaign.state,action)
	await click_button("VisualLifecycle");await click_button("VisualBeginTown")
	check(expected.get("state",{})==app.campaign.state,"actual explicit town adoption")
	transcript.append({"turn":app.campaign.state.turn,"action":action})
	await click_button("VisualClose")

func before_town_commission(id: String) -> void:
	var p=app.campaign
	if id=="town_civic":
		await click_button("VisualLifecycle");await shot("02-sustained-town-readiness")
		await click_button("VisualSave")
		await click_button("VisualClose")
		await site_shot(id,"03-same-assembly-before-town")
	await click_button("VisualOversight");await click_button("EnterPlanningRoom")
	await pick_plan(id);await shot("04-"+id+"-board")
	await pick_plan("easel");await shot("05-"+id+"-shared-quote")
	check(not app.visual_commands.find_child("VisualCommission",true,false).disabled,"planning room has usable town quote")
	await click_button("VisualStage_current");await shot("05a-"+id+"-existing-fabric")
	await click_button("VisualStage_planned");await rotate_model();await shot("06-"+id+"-planned-use")
	var reserves: Label=app.visual_commands.find_child("ProjectReserves",true,false)
	var paid: Dictionary=p.rules.command(p.state,{"kind":"commission","id":id}).state
	check(reserves.text==app.visual_commands.lw("stocks_after").format({"food":paid.food,"wood":paid.wood}),"visible remaining reserves agree with actual public payment "+id)
	var scroll: Node=reserves.get_parent()
	while scroll!=null:
		if scroll is ScrollContainer:scroll.ensure_control_visible(reserves)
		scroll=scroll.get_parent()
	await shot("06a-"+id+"-payment-and-reserves")
	await click_button("VisualClose");await click_button("PlanningLeave")

func town_milestones() -> void:
	var p=app.campaign;var ui=app.visual_commands
	for id in ["town_civic","town_preparation","town_provision"]:
		var q: Dictionary=ui.queued(id)
		if not q.is_empty() and q.progress>0 and not town_seen.has(id+"work"):
			town_seen[id+"work"]=true
			validate_routes(id+" partial paid work")
			await site_shot(id,"07-"+id+"-partial")
			await pick_site(id);check(ui.detail.get("id")==id,"actual town site selects shared review")
			await shot("08-"+id+"-paid-materials-and-work")
			await click_button("VisualPause");await click_button("VisualSave")
			var saved: Dictionary=p.state.duplicate(true)
			await click_button("VisualClose");await click_button("VisualSeason")
			check(ui.queued(id).progress==q.progress,"town pause retains investment")
			await click_button("VisualLoad");check(p.state==saved,"town partial save exact")
			await build_review(id)
			if id=="town_civic":
				var refund: int=ui.projects.describe(p.state,p.rules,id).refund_wood
				await click_button("VisualCancel")
				check(p.state.wood==saved.wood+refund and ui.queued(id).is_empty(),"actual cancellation refunds only unworked paid share")
				await shot("08a-civic-cancel-refund")
				await click_button("VisualLoad");check(p.state==saved,"load restores cancelled branch to saved partial civic contract")
				await build_review(id)
			await click_button("VisualPause");await click_button("VisualClose")
		if p.rules.has_project(p.state,id) and not town_seen.has(id+"done"):
			town_seen[id+"done"]=true
			validate_routes(id+" finished use")
			await site_shot(id,"09-"+id+"-complete")
			if id=="town_civic":
				check(p.rules.lifecycle.stage(p.state,p.rules)=="town","civic paid work earns town")
				check(not p.rules.has_project(p.state,"town_preparation") and not p.rules.has_project(p.state,"town_provision"),"promotion grants no free investment")
				await click_button("VisualLifecycle");await shot("10-town-earned-options-unpurchased");await click_button("VisualClose")

func input_stress() -> void:
	var p=app.campaign;var ui=app.visual_commands
	# Ordinary additional construction can compete with civic duty. Search only
	# pure quotes/forecasts; commit the selected public command through controls.
	await lifecycle_input({"kind":"living_order","id":"prepare","value":0})
	await lifecycle_input({"kind":"asset_principle","id":"learning","value":1})
	for i in range(16):
		var result: Dictionary=p.rules.command(p.state,{"kind":"commission","id":"exchange_place"})
		if result.has("state"):
			var plan: Dictionary=p.rules.command(result.state,{"kind":"asset_project","id":"exchange_place","crew":3,"priority":1,"paused":false}).state
			if not p.rules.forecast(plan).town.civic:
				await lifecycle_input({"kind":"commission","id":"exchange_place"})
				await build_review("exchange_place");await spin("Visual_crew",3);await spin("Visual_priority",1)
				await click_button("VisualClose");await click_button("VisualLifecycle");await shot("21-stressed-town-same-rank")
				check(p.rules.lifecycle.stage(p.state,p.rules)=="town" and ui.forecast.town.saved==0,"understaffing loses service while rank remains")
				await click_button("VisualClose");await click_button("VisualSeason")
				await build_review("exchange_place");await click_button("VisualPause")
				await click_button("VisualClose");await click_button("VisualLifecycle");await shot("22-recovery-by-pausing-optional-work")
				check(ui.forecast.town.civic and ui.forecast.town.saved>0,"attainable operational recovery")
				await click_button("VisualClose");return
		await click_button("VisualSeason")
	check(false,"actual UI stress case reached")

func pick_site(id: String) -> void:
	var view=app.campaign_view.construction_view
	check(view.sites.has(id),"town site exists "+id)
	if not view.sites.has(id):return
	var site: Dictionary=view.sites[id]
	var basis:=Basis(Vector3.UP,float(site.yaw))
	var target: Vector3=site.at+basis*Vector3(site.half.x-.28,.22,-site.half.y+.8)
	# Move the camera so the actual material pile is above the ordinary dock.
	# Do not click through a UI panel or bypass the rendered mesh's hit test.
	app.set_view(target+basis*Vector3(5,5,5),target-Vector3.UP)
	for i in range(3):await process_frame
	var point: Vector2=app.camera.unproject_position(target)
	check(view.pick(app.camera.project_ray_origin(point),app.camera.project_ray_normal(point))==id,"visible paid material mesh picks town site")
	await click_at(point)

func double_season() -> void:
	var turn: int=app.campaign.state.turn
	var button_: Control=app.visual_commands.find_child("VisualSeason",true,false)
	var at: Vector2=button_.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
	for i in range(2):
		var press:=InputEventMouseButton.new();press.position=at;press.global_position=at;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
		var release:=InputEventMouseButton.new();release.position=at;release.global_position=at;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;root.push_input(release,true)
	for i in range(3):await process_frame
	check(app.campaign.state.turn==turn+1,"two real-input season clicks in one frame resolve only once")
