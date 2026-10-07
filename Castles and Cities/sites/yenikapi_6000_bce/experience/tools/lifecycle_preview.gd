extends "res://tools/construction_preview.gd"
## Every gameplay action enters through the ordinary controls using real input.
## The driver chooses commands, but never injects stock, work, people or stage.
const LifecycleDriver=preload("res://tools/lifecycle_driver.gd")
var seen: Dictionary={}
var transcript: Array=[]
func _initialize() -> void:
	out_dir="/tmp/yenikapi-lifecycle-qa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,800);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;var ui=app.visual_commands
	p.save_path=out_dir.path_join("lifecycle-render-save.json")
	if FileAccess.file_exists(p.save_path):DirAccess.remove_absolute(p.save_path)
	app.hud.show();ui.open();await click_button("VisualNew")
	check(not p.rules.lifecycle.active(p.state),"ordinary village does not silently adopt lifecycle")
	await click_button("VisualLifecycle")
	var pristine: Dictionary=p.state.duplicate(true)
	await shot("00-explicit-adoption")
	check(p.state==pristine,"opening lifecycle does not adopt or create practice")
	await lifecycle_input({"kind":"lifecycle_begin"})
	await click_button("VisualLifecycle");await shot("01-named-missing-requirements")
	check(ui.find_child("VisualProject_lifecycle_store",true,false)!=null,"locked individual improvement remains reviewable")
	await click_button("VisualProject_lifecycle_store")
	check(ui.find_child("VisualCommission",true,false).disabled,"civic achievement gates individual payment")
	await shot("02-locked-store-improvement");await click_button("VisualClose")
	for step in range(300):
		if LifecycleDriver.finished(p.rules,p.state):break
		var action: Dictionary=LifecycleDriver.next_action(p.rules,p.state,true)
		if not action.is_empty():
			if action.kind=="commission" and action.id.begins_with("lifecycle_"):
				await before_lifecycle_commission(action.id)
			await lifecycle_input(action)
		else:
			if p.state.turn>=80:break
			var expected: Dictionary=p.rules.advance(p.state).state
			await click_button("VisualSeason")
			check(p.state==expected,"actual season control matches deterministic public advance")
			transcript.append({"turn":p.state.turn,"action":{"kind":"advance"}})
		await capture_milestones()
		if failures>0:break
	check(LifecycleDriver.finished(p.rules,p.state),"civic shelter and both separately paid improvements finish through actual inputs")
	if LifecycleDriver.finished(p.rules,p.state):
		await click_button("VisualLifecycle");await shot("20-complete-lifecycle-and-planned-ladder")
		check(ui.sheet.get_global_rect().end.y<=ui.dock.get_global_rect().position.y,"lifecycle review fits 1280 by 800")
		await click_button("VisualClose")
		await site_shot("lifecycle_store","21-store-retained-after-individual-upgrade")
		app.hud.hide()
		await interior("yk_store_01","22-retained-store-furnishings")
		await interior("yk_house_06","23-retained-working-room")
		validate_routes("lifecycle completed village")
		app.hud.show()
		await click_button("VisualSave")
		var saved: Dictionary=p.state.duplicate(true)
		await click_button("VisualSeason");await click_button("VisualLoad")
		check(p.state==saved,"completed civic and building revisions resume exactly")
		await click_button("Visual_report")
		var passive: Dictionary=p.state.duplicate(true)
		for i in range(30):await process_frame
		ui.refresh();await process_frame
		check(p.state==passive,"idle frames and report replay do not change lifecycle or economy")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"turn":p.state.turn,"commands":transcript,"ui_timings":ui.timings},"  "))
	print("LIFECYCLE RENDER: %d captures; %d checks, %d failures"%[captures.size(),checks,failures]);quit(1 if failures else 0)

func lifecycle_input(action: Dictionary) -> void:
	var p=app.campaign;var ui=app.visual_commands
	var expected: Dictionary=p.rules.command(p.state,action)
	check(expected.has("state"),"driver command accepted "+JSON.stringify(action))
	if not expected.has("state"):return
	match action.kind:
		"lifecycle_begin":
			await click_button("VisualLifecycle");await click_button("VisualBeginLifecycle")
		"commission":
			await build_review(action.id);await click_button("VisualCommission")
		"asset_principle":
			var spec: Dictionary=p.asset_panel.copy.principles.filter(func(a):return a.id==action.id)[0]
			await click_button("VisualPlace_"+spec.asset)
			if ui.page!="orders":await click_button("VisualPage_orders")
			await click_button("VisualPrinciple_"+action.id);await click_button("VisualChoice_"+str(action.value))
		"living_order":
			var spec: Dictionary=ui.copy.living_orders.filter(func(a):return a.id==action.id)[0]
			await click_button("VisualPlace_"+spec.asset)
			if ui.page!="orders":await click_button("VisualPage_orders")
			await click_button("VisualOrder_"+action.id);await click_button("VisualChoice_"+str(spec.values.find(action.value)))
		_:check(false,"unmapped actual-input command "+action.kind);return
	check(p.state==expected.state,"actual input matches public command "+JSON.stringify(action))
	transcript.append({"turn":p.state.turn,"action":action.duplicate(true)})
	if is_instance_valid(ui.find_child("VisualClose",true,false)):await click_button("VisualClose")

func before_lifecycle_commission(id: String) -> void:
	var p=app.campaign;var ui=app.visual_commands
	if id=="lifecycle_assembly":
		await click_button("VisualLifecycle");await shot("03-sustained-readiness-and-civic-quote")
		await click_button("VisualClose")
		await site_shot("lifecycle_store","04-store-before-civic-work")
	await build_review(id)
	var stable: Dictionary=p.state.duplicate(true)
	await click_button("VisualStage_current");await shot("05-"+id+"-current-model")
	await click_button("VisualStage_planned");await rotate_model();await shot("06-"+id+"-planned-model")
	var confirm: Control=ui.find_child("VisualCommission",true,false)
	var scroll: Node=confirm.get_parent()
	while scroll!=null:
		if scroll is ScrollContainer:scroll.ensure_control_visible(confirm)
		scroll=scroll.get_parent()
	await shot("06a-"+id+"-reserve-lineage-and-confirmation")
	check(p.state==stable,"current/future models and rotation are pure "+id)
	check(not ui.find_child("VisualCommission",true,false).disabled,"eligible project offers explicit paid commission "+id)
	await click_button("VisualClose")

func capture_milestones() -> void:
	var p=app.campaign;var ui=app.visual_commands
	for id in ["lifecycle_assembly","lifecycle_store","lifecycle_workroom"]:
		var queue: Dictionary=ui.queued(id)
		if not queue.is_empty() and int(queue.progress)>0 and not seen.has(id+"_work"):
			seen[id+"_work"]=true
			await site_shot(id,"07-"+id+"-real-seasonal-work")
			await build_review(id);await shot("08-"+id+"-paid-progress")
			await click_button("VisualPause");await click_button("VisualSave")
			var saved: Dictionary=p.state.duplicate(true)
			var paid: Dictionary=ui.projects.describe(p.state,p.rules,id)
			await click_button("VisualClose");await click_button("VisualSeason")
			check(ui.queued(id).progress==paid.progress,"paid pause retains work across a season "+id)
			await click_button("VisualLoad")
			check(p.state==saved,"partial payment, work and pause resume exactly "+id)
			await build_review(id);await click_button("VisualPause");await click_button("VisualClose")
		if p.rules.has_project(p.state,id) and not seen.has(id+"_done"):
			seen[id+"_done"]=true
			await site_shot(id,"09-"+id+"-completed-fabric")
			if id=="lifecycle_assembly":
				check(not p.rules.has_project(p.state,"lifecycle_store") and not p.rules.has_project(p.state,"lifecycle_workroom"),"civic achievement never grants free improvements")
				await site_shot("lifecycle_store","10-same-store-after-civic-achievement")
				await click_button("VisualLifecycle");await shot("11-achievement-with-individual-offers");await click_button("VisualClose")

func rotate_model() -> void:
	var model: Control=app.find_child("ProjectModel",true,false)
	if model==null:return
	var at: Vector2=model.get_global_rect().get_center()
	var press:=InputEventMouseButton.new();press.position=at;press.global_position=at;press.button_index=MOUSE_BUTTON_LEFT;press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.pressed=true;root.push_input(press,true)
	var motion:=InputEventMouseMotion.new();motion.position=at+Vector2(50,0);motion.global_position=motion.position;motion.relative=Vector2(50,0);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	var release:=InputEventMouseButton.new();release.position=motion.position;release.global_position=motion.position;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;root.push_input(release,true)
	for i in range(3):await process_frame

func site_shot(id: String,name_: String) -> void:
	var at: Array=app.campaign.rules.projects[id].at
	var building: Dictionary=preload("res://src/construction_view.gd").building_record(id,app.campaign.rules)
	if not building.is_empty():at=building.at
	var center:=Vector3(at[0],app.world.floor_height(at[0],at[1]),at[1])
	app.set_view(center+Vector3(8,7,11),center+Vector3.UP*1.5)
	app.visual_commands.close_sheet();app.hud.hide();await shot(name_);app.hud.show()
