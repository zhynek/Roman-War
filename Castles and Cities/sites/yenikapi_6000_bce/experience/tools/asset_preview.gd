extends "res://tools/household_preview.gd"
var timings: Dictionary={}
func _initialize() -> void:
	out_dir="/tmp/yenikapi-assets-qa"
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
	p.save_path=out_dir.path_join("asset-test.json")
	p.open()
	await click_button("BeginAssetGovernance")
	timings.open_ready_ms=Time.get_ticks_msec()-start
	check(p.rules.assets.active(p.state),"begin assets through actual interface")
	await click_button("GuideInspect")
	check(p.asset_panel.selected=="stores" and p.tabs.current_tab==1,"guide uses asset selection")
	await shot("01-store-management")
	p.tabs.current_tab=0;await click_button("ReviewAssetStep")
	p.tabs.current_tab=4;await click_button("Principle_reserve_0")
	await shot("02-standing-principles")
	p.tabs.current_tab=0;await click_button("ReviewAssetStep")
	await click_button("GuideInspect")
	await click_button("AssetCommission_field_extension")
	check(p.state.wood==18,"actual commission spends same wood ledger")
	p.tabs.current_tab=0;await click_button("ReviewAssetStep")
	await click_button("GuideInspect")
	p.tabs.current_tab=0;await click_button("ReviewAssetStep")
	var forecast: Dictionary=p.rules.forecast(p.state)
	await click_button("ResolveSeason")
	check(p.state.report==forecast,"actual UI forecast equals season report")
	await click_button("ReviewAssetStep")
	p.hide();app.hud.hide()
	app.set_view(Vector3(146,118,194),Vector3(-5,2,5));await shot("03-ordinary-landscape")
	app.overview();await shot("04-construction-aerial")
	app.visit(1);await shot("05-ordinary-street")
	await interior("yk_store_01","06-store-interior")
	validate_routes("ordinary asset duties")
	app.hud.show();p.show();p.tabs.current_tab=0
	await click_button("AssetPressure")
	p.tabs.current_tab=4;await click_button("Principle_watch_0");await click_button("Principle_watch_1")
	p.tabs.current_tab=0;await click_button("ReviewAssetStep")
	# Complete useful store/care preparations with the actual asset controls.
	for spec in [["stores","secure_stores"],["homes","refuge"],["watch","safe_routes"]]:
		p.asset_panel.inspect(spec[0]);await click_button("AssetOrder_"+spec[1])
	for i in range(2):await click_button("ResolveSeason")
	check(p.rules.households.stage(p.state)=="danger","pressure has authored timing")
	validate_routes("danger asset duties")
	p.asset_panel.inspect("watch");await shot("07-pressure-priorities")
	p.hide();app.hud.hide();await interior("yk_house_01","08-pressure-care-interior")
	await interior("yk_store_01","09-pressure-store-interior")
	var before: String=JSON.stringify(p.state)
	for delta in [.008,.016,.033,.1]:
		app.campaign_view.life._process(delta)
		app.set_view(Vector3(90,60,90),Vector3.ZERO)
	check(JSON.stringify(p.state)==before,"frame rates and camera positions cannot mutate rules")
	app.hud.show();p.show()
	for i in range(2):await click_button("ResolveSeason")
	p.asset_panel.inspect("workroom")
	await click_button("AssetOrder_learning")
	await click_button("ResolveSeason")
	p.tabs.current_tab=0;await click_button("ReviewAssetStep")
	check(p.state.assets.tutorial==7,"real guided recovery and learning complete")
	validate_routes("recovery asset duties")
	p.hide();app.hud.hide();await interior("yk_house_06","10-recovery-learning-interior")
	# Coordinate housing using its own target-asset action, with no free stocks.
	app.hud.show();p.show();p.asset_panel.inspect("yard")
	await click_button("HousingCoordination")
	for season in range(30):
		p.asset_panel.inspect("yard")
		var quote: Dictionary=p.rules.command(p.state,{"kind":"asset_housing_step"})
		if quote.has("state"):await click_button("HousingNextStep")
		if p.rules.assets.housing_next(p.state,p.rules)=="" and p.rules.has_project(p.state,"east_home"):break
		await click_button("ResolveSeason")
	check(p.rules.has_project(p.state,"north_home") and p.rules.has_project(p.state,"east_home"),"coordinated access and two homes completed through real controls")
	p.tabs.current_tab=0
	if p.rules.assets.tutorial_ready(p.state,p.rules):await click_button("ReviewAssetStep")
	check(p.state.assets.tutorial==8,"guide finishes with playable growth readiness")
	await shot("11-growth-readiness")
	validate_routes("grown asset duties")
	check(p.save_campaign(),"save exact interface settlement")
	before=JSON.stringify(p.state);p.resolve_season()
	check(p.load_campaign() and JSON.stringify(p.state)==before,"save resumes all decisions and memories")
	# World picking uses actual triangles, then the same inspect command as the list.
	p.hide();app.hud.hide()
	for b in app.world.buildings:
		if b.id!="yk_store_01":continue
		var target: Vector3=app.world.building_position(b,Vector3(0,1,0))
		var eye: Vector3=target+Vector3(0,10,10)
		app.set_view(eye,target)
		check(app.pick_asset(eye,(target-eye).normalized())=="stores","mesh picking matches store drawing")
		app.hud.show()
		var at: Vector2=root.get_visible_rect().size*.5
		var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
			await process_frame
		check(p.visible and p.tabs.current_tab==1 and p.asset_panel.selected=="stores","actual world selection opens asset management")
	root.size=Vector2i(1280,800)
	p.asset_panel.inspect("homes")
	await shot("12-small-window-assets")
	check(p.get_global_rect().position.x>=0 and p.get_global_rect().end.y<=root.get_visible_rect().size.y,"asset controls fit smaller window")
	# Keep navigation and collision checks on the production controller.
	var retained: Dictionary=p.state.duplicate(true)
	start=Time.get_ticks_msec();p.dispatch({"kind":"asset_principle","id":"reserve","value":2});timings.change_order_ms=Time.get_ticks_msec()-start
	start=Time.get_ticks_msec();app.show_campaign(p.state,p.rules);timings.unchanged_refresh_ms=Time.get_ticks_msec()-start
	start=Time.get_ticks_msec();app.campaign_view.life._routes.clear();app.campaign_view.life._signature="";app.show_campaign(p.state,p.rules);timings.route_rebuild_ms=Time.get_ticks_msec()-start
	check(app.campaign_view.life.unreachable.is_empty(),"rebuilt routes remain accessible")
	app.show_reference();check(app.world.buildings.size()==9,"dated reference retained")
	p.state=retained;p.open()
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"timings":timings,"turn":p.state.turn},"  "))
	print("ASSET RENDER: ",captures.size()," captures; ",checks," checks, ",failures," failures; timings ",timings)
	quit(1 if failures else 0)
