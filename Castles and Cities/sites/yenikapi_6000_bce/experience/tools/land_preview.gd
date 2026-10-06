extends "res://tools/household_preview.gd"
const Driver=preload("res://tools/land_driver.gd")
var timings: Dictionary={}
func _initialize() -> void:
	out_dir="/tmp/yenikapi-land-qa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var start: int=Time.get_ticks_msec()
	app=load("res://main.tscn").instantiate();root.add_child(app)
	await process_frame
	var p=app.campaign
	p.save_path=out_dir.path_join("land-test.json")
	p.open();await click_button("BeginLandPlanning")
	timings.open_ready_ms=Time.get_ticks_msec()-start
	check(p.rules.land.active(p.state),"land chapter begins through actual input")
	var initial: Dictionary=p.state.duplicate(true)
	await shot("01-land-proposals")
	start=Time.get_ticks_msec();p.land_panel.inspect("north_west");timings.compare_ms=Time.get_ticks_msec()-start
	check(p.state.food==initial.food and p.state.wood==initial.wood and p.state.turn==0,"comparison grants no supplies or work")
	await shot("02-outer-blocked")
	# Both selection surfaces dispatch the identical land_inspect command.
	p.land_panel.inspect("clay_court")
	var expected: Dictionary=p.rules.command(p.state,{"kind":"land_inspect","id":"north_west"}).state
	p.hide();app.hud.hide()
	var center:=Vector3(-22,app.world.floor_height(-22,-59),-59)
	var eye: Vector3=center+Vector3(0,18,5)
	app.set_view(eye,center)
	check(app.campaign_view.land_view.pick(eye,(center-eye).normalized())=="north_west","land picking shares drawn footprint")
	var at: Vector2=root.get_visible_rect().size*.5
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
		await process_frame
	check(p.visible and p.land_panel.selected=="north_west" and p.state==expected,"actual world and overview selection equivalent")
	app.hud.show();p.tabs.current_tab=0
	await click_button("ReviewLandStep")
	p.asset_panel.inspect("workroom")
	await click_button("AssetLand_land_adapt_workroom")
	check(p.land_panel.selected=="workroom","asset overview opens identical land proposal")
	var quote: Dictionary=p.rules.command(p.state,{"kind":"commission","id":"land_adapt_workroom"}).state
	start=Time.get_ticks_msec();await click_button("AssetCommission_land_adapt_workroom");timings.commission_input_ms=Time.get_ticks_msec()-start
	check(p.state==quote,"UI commission equals authoritative quotation")
	await click_button("AssetPause_land_adapt_workroom")
	check(p.rules.forecast(p.state).assets.projects.land_adapt_workroom.work==0,"actual pause releases crew")
	await click_button("AssetPause_land_adapt_workroom")
	p.tabs.current_tab=0;await click_button("ReviewLandStep")
	p.land_panel.inspect("clay_court");await click_button("AssetCommission_land_court_home")
	p.tabs.current_tab=0;await click_button("ReviewLandStep")
	var f: Dictionary=p.rules.forecast(p.state)
	start=Time.get_ticks_msec();p.resolve_season();timings.season_ms=Time.get_ticks_msec()-start
	check(p.state.report==f,"spatial forecast equals UI seasonal outcome")
	p.tabs.current_tab=0;await click_button("ReviewLandStep")
	validate_routes("paid construction and adaptation");validate_paths("staging")
	p.hide();app.hud.hide();app.set_view(Vector3(-48,20,22),Vector3(-26,2,-4));await shot("03-paid-construction")
	await interior("yk_house_06","04-workroom-adaptation")
	# Retain the illustrative partially built state, then demonstrate two full
	# strategies from the exact same initial state through the public commands.
	for compact in [true,false]:
		p.state=initial.duplicate(true)
		for season in range(32):
			p.state=Driver.orders(p.rules,p.state,compact)
			p.state=p.rules.advance(p.state).state
		app.show_campaign(p.state,p.rules,true);p.refresh();p.hide();app.hud.hide()
		var prefix: String="compact" if compact else "outward"
		check(p.state.phase=="town" and p.rules.capacity(p.state)==48,prefix+" sustainable original town milestone")
		validate_routes(prefix+" ordinary life");validate_paths(prefix)
		app.set_view(Vector3(106,102,145),Vector3(-18,2,-12));await shot(prefix+"-05-landscape")
		app.set_view(Vector3(20,70,48),Vector3(-20,1,-20));await shot(prefix+"-06-aerial")
		if compact:app.set_view(Vector3(-20,5,12),Vector3(-32,3,-3))
		else:app.set_view(Vector3(-10,5,-40),Vector3(-22,3,-59))
		await shot(prefix+"-07-street")
		await interior("land_court_home_building" if compact else "land_outer_west_building",prefix+"-08-interior")
		if compact:await interior("yk_house_06","compact-09-retained-workroom")
		check(p.save_campaign(),prefix+" saves exact built layout")
		var saved: String=JSON.stringify(p.state);p.resolve_season()
		check(p.load_campaign() and JSON.stringify(p.state)==saved,prefix+" exact household and land resume")
		var invariant: String=JSON.stringify(p.state)
		for delta in [.008,.016,.033,.1]:app.campaign_view.life._process(delta);app.overview()
		check(JSON.stringify(p.state)==invariant,prefix+" camera and frame independence")
		if not compact:
			start=Time.get_ticks_msec();p.land_panel.inspect("north_west");timings.compare_grown_ms=Time.get_ticks_msec()-start
			start=Time.get_ticks_msec();p.dispatch({"kind":"asset_principle","id":"reserve","value":2});timings.change_order_ms=Time.get_ticks_msec()-start
			start=Time.get_ticks_msec();app.show_campaign(p.state,p.rules);timings.unchanged_refresh_ms=Time.get_ticks_msec()-start
			start=Time.get_ticks_msec();app.campaign_view.life._routes.clear();app.campaign_view.life._signature="";app.show_campaign(p.state,p.rules);timings.route_rebuild_ms=Time.get_ticks_msec()-start
	# Existing care, pressure, recovery and learning continue in the outward layout.
	p.dispatch({"kind":"asset_pressure"})
	for id in ["secure_stores","refuge","safe_routes","learning"]:p.dispatch({"kind":"household_order","id":id,"enabled":true})
	for i in range(2):p.resolve_season()
	validate_routes("outward pressure");p.hide();app.hud.hide();await interior("yk_house_01","10-pressure-care")
	for i in range(4):p.resolve_season()
	validate_routes("outward recovery");p.hide();app.hud.hide();await interior("yk_house_06","11-recovery-learning")
	app.hud.show();p.show();root.size=Vector2i(1280,800);p.land_panel.inspect("north_west")
	await shot("12-small-window-planning")
	check(p.get_global_rect().position.x>=0 and p.get_global_rect().end.x<=root.get_visible_rect().size.x and p.get_global_rect().end.y<=root.get_visible_rect().size.y,"planning fits smaller window")
	await click_button("LandAccess")
	check(not p.rules.forecast(p.state).land.access,"small-window upkeep changes real authority")
	await shot("13-access-consequences")
	await click_button("LandAccess")
	check(p.rules.forecast(p.state).land.access,"upkeep recovery uses real adults and timber")
	p.state=Driver.initial(p.rules);app.show_campaign(p.state,p.rules);p.refresh()
	p.dispatch({"kind":"commission","id":"land_provisioning"})
	for i in range(3):p.resolve_season()
	check(p.rules.land.totals(p.state,p.rules).food==-8,"provisioning conversion loses actual productive ground")
	validate_routes("provisioning yard");validate_paths("provisioning yard")
	p.hide();app.hud.hide();root.size=Vector2i(1600,1000)
	app.set_view(Vector3(-80,22,37),Vector3(-59,2,12));await shot("14-provisioning-conversion")
	p.dispatch({"kind":"asset_principle","id":"reserve","value":2})
	p.dispatch({"kind":"commission","id":"field_extension"})
	for i in range(16):p.state=p.rules.advance(p.state).state
	app.show_campaign(p.state,p.rules);p.refresh();app.hud.show();p.land_panel.inspect("west_field")
	check(p.state.food>=p.rules.people(p.state).size()*2,"poor decision recovers through real reserves and cultivation")
	await shot("15-recovered-food-margin")
	app.show_reference();check(app.world.buildings.size()==9,"dated reference unchanged")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"timings":timings},"  "))
	print("LAND RENDER: ",captures.size()," captures; ",checks," checks, ",failures," failures; timings ",timings)
	quit(1 if failures else 0)

func validate_paths(phase: String) -> void:
	for path in app.data.objects:
		if path.kind!="path":continue
		var points: Array=path.points
		var walker:=Vector3(points[0][0],0,points[0][1]);walker.y=app.world.floor_height(walker.x,walker.z)+1.68
		var passable: bool=true
		for i in range(points.size()-1):
			var a:=Vector2(points[i][0],points[i][1]);var b:=Vector2(points[i+1][0],points[i+1][1]);var prior:=Vector2(points[maxi(0,i-1)][0],points[maxi(0,i-1)][1]);var after:=Vector2(points[mini(points.size()-1,i+2)][0],points[mini(points.size()-1,i+2)][1])
			for j in range(1,41):
				var point: Vector2=a.cubic_interpolate(b,prior,after,float(j)/40)
				walker=app.world.walk(walker,Vector3(point.x-walker.x,0,point.y-walker.z))
				if Vector2(walker.x-point.x,walker.z-point.y).length()>.1:passable=false
		check(passable,phase+" drawn path "+path.id)
