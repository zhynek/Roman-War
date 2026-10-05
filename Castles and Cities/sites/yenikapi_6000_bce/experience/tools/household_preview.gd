extends SceneTree
var app
var out_dir:String="/tmp/yenikapi-household-qa"
var captures:Array=[]
var failures:int=0
var checks:int=0
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app)
	await process_frame
	var panel=app.campaign
	panel.save_path=out_dir.path_join("household-test.json")
	panel.begin();panel.open();panel.tabs.current_tab=6
	await shot("01-household-introduction")
	await click_button("BeginHouseholds")
	check(panel.rules.households.active(panel.state),"begin from village through real input")
	await click_button("HouseholdSuggestedWorkforce")
	for id in ["secure_stores","refuge","safe_routes","learning"]:await click_button("Order_"+id)
	check(panel.state.wood==12,"preparations debit finite wood once")
	panel.tabs.get_child(6).scroll_vertical=0
	await shot("02-warning-preparations")
	validate_routes("warning")
	await click_button("ResolveSeason");await click_button("ResolveSeason")
	check(panel.rules.households.stage(panel.state)=="danger","explicit seasonal danger transition")
	check(panel.save_campaign(),"save active household memories")
	var saved:String=JSON.stringify(panel.state)
	panel.resolve_season()
	check(panel.load_campaign() and JSON.stringify(panel.state)==saved,"exact household resume through UI")
	validate_routes("danger")
	panel.hide();app.hud.hide()
	app.set_view(Vector3(90,68,118),Vector3(-9,2,8));await shot("03-danger-landscape")
	app.overview();await shot("04-danger-aerial")
	app.visit(1);await shot("05-danger-street")
	await interior("yk_house_01","06-shared-care-interior")
	await interior("yk_store_01","07-provisioning-interior")
	await interior("yk_house_06","08-working-interior")
	var before:String=JSON.stringify(panel.state)
	for i in range(90):await process_frame
	check(JSON.stringify(panel.state)==before,"walking and routines cannot mutate season or household memories")
	var count:int=app.world.solids.size()
	panel.refresh();app.show_campaign(panel.state,panel.rules)
	check(app.world.solids.size()==count,"repeated overlay refresh does not accumulate collision")
	panel.resolve_season();panel.resolve_season()
	check(panel.rules.households.stage(panel.state)=="recovery","recovery follows explicit seasons")
	validate_routes("recovery")
	app.hud.show();panel.open();panel.tabs.current_tab=6;await shot("09-recovery-decisions")
	panel.resolve_season();panel.resolve_season()
	check(panel.rules.households.stage(panel.state)=="renewal","learning chapter reached")
	validate_routes("renewal")
	panel.hide();app.hud.hide();await interior("yk_house_06","10-learning-circle-interior")
	panel.resolve_season();panel.resolve_season()
	check(panel.rules.households.stage(panel.state)=="settled","scripted danger ends without another automatic threat")
	validate_routes("settled")
	var scores:Dictionary={}
	for memory in panel.state.households.homes.values():scores[memory.practice]=true
	check(scores.size()>1,"households retain uneven practice uptake")
	app.hud.show();panel.open();panel.tabs.current_tab=6;root.size=Vector2i(1280,800)
	for i in range(3):await process_frame
	panel.tabs.get_child(6).ensure_control_visible(panel.find_child("HouseholdResident",true,false))
	await shot("11-household-memories-small-window")
	check(panel.get_global_rect().position.x>=0 and panel.get_global_rect().end.y<=root.get_visible_rect().size.y,"household panel fits small window")
	await click_button("FollowResident")
	check(not panel.visible and not app.flying and not app.world.blocked(app.camera.position),"resident visit arrives at passable walking station")
	await shot("12-resident-follow")
	await inspect_visible_resident()
	app.show_reference();check(app.world.buildings.size()==9,"original dated buildings preserved")
	check(not is_instance_valid(app.campaign_view),"reference has no scenario figures or overlays")
	panel.open();check(is_instance_valid(app.campaign_view.life),"saved household presentation restored")
	var retained:Dictionary=panel.state.duplicate(true)
	var grown:Dictionary=preload("res://tools/neighbor_driver.gd").foundation(panel.rules)
	grown=panel.rules.command(grown,{"kind":"household_begin"}).state
	grown=panel.rules.command(grown,{"kind":"neighbor_begin"}).state
	panel.state=grown;app.show_campaign(grown,panel.rules,true)
	validate_routes("grown with contacts")
	panel.state=retained;app.show_campaign(retained,panel.rules,true)
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"turn":panel.state.turn,"stats":app.world.stats},"  "))
	print("HOUSEHOLD RENDER: ",captures.size()," captures; ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func interior(id:String,capture:String) -> void:
	for b in app.world.buildings:
		if b.id!=id:continue
		var eye:Vector3=app.world.building_position(b,Vector3(0,1.68,float(b.size[1])*.5-.65))
		app.set_view(eye,app.world.building_position(b,Vector3(0,.85,-.7)),false)
		await shot(capture)
func validate_routes(phase:String) -> void:
	var view=app.campaign_view.life
	check(view.unreachable.is_empty(),phase+" all citizen routes planned")
	var indexed:bool=true
	for x in range(-36,22,2):
		for z in range(-26,34,2):
			var point:=Vector3(x+.17,0,z+.31)
			if view._nav_blocked(point)!=app.world.blocked(point):indexed=false
	check(indexed,phase+" indexed collision agrees with walking")
	var ids:Dictionary={}
	for routine in view.routines:
		check(not ids.has(routine.id),phase+" unique citizen "+routine.id);ids[routine.id]=true
		var route:Array=routine.route
		check(not route.is_empty(),phase+" nonempty route "+routine.id)
		var accessible:bool=true
		for i in range(1,route.size()):
			var target:Vector3=route[i]+Vector3.UP*1.68
			var reached:Vector3=app.world.walk(route[i-1]+Vector3.UP*1.68,target-(route[i-1]+Vector3.UP*1.68))
			if Vector2(reached.x-target.x,reached.z-target.z).length()>.1:accessible=false
		check(accessible,phase+" continuous route "+routine.id)
	check(ids.size()==app.campaign.rules.people(app.campaign.state).size(),phase+" every living citizen represented")
	for b in app.world.buildings:
		var start:Vector3=app.world.building_position(b,Vector3(0,1.68,float(b.size[1])*.5+1.4))
		var end:Vector3=app.world.building_position(b,Vector3(0,1.68,float(b.size[1])*.5-.6))
		var reached:Vector3=app.world.walk(start,end-start)
		check(Vector2(reached.x-end.x,reached.z-end.z).length()<.1,phase+" door "+b.id)
func click_button(id:String) -> void:
	# Native macOS input may arrive between synthetic pointer motion and press.
	# Retry only when no state/visibility transition occurred, never double-order.
	for attempt in range(3):
		for i in range(6):await process_frame
		var button:Button=app.campaign.find_child(id,true,false)
		if button==null:check(false,"missing button "+id);return
		var parent:Node=button.get_parent()
		while parent!=null:
			if parent is ScrollContainer:parent.ensure_control_visible(button)
			parent=parent.get_parent()
		for i in range(6):await process_frame
		var at:Vector2=button.get_global_rect().get_center()
		var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
		for i in range(3):await process_frame
		at=button.get_global_rect().get_center()
		var before:String=JSON.stringify(app.campaign.state)
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
			root.push_input(event,true)
			for i in range(6):await process_frame
		if JSON.stringify(app.campaign.state)!=before or (id=="FollowResident" and not app.campaign.visible):
			check(true,"real control responds "+id);return
	check(false,"real control did not respond "+id)
func shot(name_:String) -> void:
	for i in range(12):
		await process_frame
		RenderingServer.force_draw(true)
	check(root.get_texture().get_image().save_png(out_dir.path_join(name_+".png"))==OK,"capture "+name_)
	captures.append(name_);print("CAPTURE ",name_)

func inspect_visible_resident() -> void:
	var view=app.campaign_view.life
	var selected:String=""
	for routine in view.routines:
		var station:Dictionary=view.stations[routine.station]
		var eye:Vector3=station.get("viewpoint",station.position)+Vector3.UP*1.68
		var target:Vector3=routine.node.global_transform*Vector3(0,.95,0)
		if Vector2(eye.x-target.x,eye.z-target.z).length()<.4:continue
		app.set_view(eye,target,false)
		var id:String=app.pick_resident(eye,(target-eye).normalized())
		if not id.is_empty():selected=id;break
	check(not selected.is_empty(),"resident is selectable from a passable activity viewpoint")
	if selected.is_empty():return
	var before:String=JSON.stringify(app.campaign.state)
	var at:Vector2=root.get_visible_rect().size*.5
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true)
		for i in range(3):await process_frame
	check(app.campaign.visible and app.campaign.tabs.current_tab==6 and app.campaign.household_panel.selected==selected,"actual world click opens the correct citizen routine")
	check(JSON.stringify(app.campaign.state)==before,"citizen inspection cannot issue orders or change state")
