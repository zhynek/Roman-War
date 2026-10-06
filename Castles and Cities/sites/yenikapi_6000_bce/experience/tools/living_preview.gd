extends "res://tools/land_preview.gd"
const LivingDriver=preload("res://tools/living_driver.gd")
func _initialize() -> void:
	out_dir="/tmp/yenikapi-living-qa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;p.save_path=out_dir.path_join("living-test.json")
	p.open();await click_button("BeginLiving")
	check(p.rules.living.active(p.state),"actual input starts living village")
	var initial: Dictionary=p.state.duplicate(true)
	await shot("01-overview")
	p.living_panel.inspect("west_wood");p.hide();app.hud.hide()
	var center:=Vector3(-88,app.world.floor_height(-88,-28),-28)
	app.set_view(center+Vector3(9,7,13),center);await shot("02-wood-workers")
	var expected: Dictionary=p.rules.command(p.state,{"kind":"living_inspect","id":"north_wood"}).state
	center=Vector3(-42,app.world.floor_height(-42,-82),-82)
	var eye: Vector3=center+Vector3(0,20,6)
	app.set_view(eye,center)
	check(app.campaign_view.living_view.pick(eye,(center-eye).normalized())=="north_wood","drawn woodland pick")
	var mouse: Vector2=root.get_visible_rect().size*.5
	var motion:=InputEventMouseMotion.new();motion.position=mouse;motion.global_position=mouse;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=mouse;event.global_position=mouse;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true);await process_frame
	check(p.visible and p.living_panel.selected=="north_wood" and p.state==expected,"world/overview discovery identity")
	await shot("03-discovery")
	p.hide();app.hud.show()
	# A real public-command playthrough: no injected supplies, completion or knowledge.
	p.state=initial.duplicate(true)
	for i in range(20):
		p.state=LivingDriver.orders(p.rules,p.state,true)
		app.show_campaign(p.state,p.rules);p.refresh()
		if i==5:
			p.hide();app.hud.hide();await interior("yk_house_06","04-shared-work")
		var f: Dictionary=p.rules.forecast(p.state)
		p.resolve_season();check(p.state.report==f,"forecast after actual seasonal command")
	check(p.state.living.discoveries.has("cooperation") and p.state.living.practice==2,"recognized and sustained cooperation")
	check(p.state.living.kits>0 and p.state.living.readiness>0,"finite equipment used with practice")
	validate_routes("living work");validate_paths("living paths")
	p.living_panel.inspect("landing_post");await shot("05-preparedness-and-journal")
	p.hide();app.hud.hide();center=Vector3(-32,app.world.floor_height(-32,-48),-48)
	app.set_view(center+Vector3(5,3,7),center+Vector3.UP*.8);await shot("06-watch-kits")
	await interior("yk_house_06","07-prepared-materials")
	p.living_panel.inspect("store");await shot("08-forecast-results")
	check(p.save_campaign(),"living save");var saved: Dictionary=p.state.duplicate(true)
	p.resolve_season();check(p.load_campaign() and p.state==saved,"living save restores materials/knowledge")
	p.living_panel.inspect("store")
	p.tabs.current_tab=0
	for step in range(6):await click_button("ReviewLivingStep")
	p.dispatch({"kind":"living_order","id":"prepare","value":1})
	p.resolve_season()
	p.dispatch({"kind":"living_order","id":"prepare","value":0})
	p.tabs.current_tab=0;await click_button("ReviewLivingStep")
	check(p.state.living.tutorial==7,"complete connected guide through actual review controls")
	await shot("guide-complete")
	p.hide();app.hud.hide()
	var invariant: Dictionary=p.state.duplicate(true)
	for delta in [.001,.008,.016,.1,1.0]:
		for i in range(60):app.campaign_view.life.step(delta)
		app.overview()
	check(p.state==invariant,"idle time, camera and frame rate cannot produce anything")
	for compact in [true,false]:
		p.state=initial.duplicate(true)
		for i in range(48):
			p.state=Driver.orders(p.rules,p.state,compact)
			p.state=LivingDriver.orders(p.rules,p.state,true)
			p.state=p.rules.advance(p.state).state
		app.show_campaign(p.state,p.rules,true);p.refresh();p.hide();app.hud.hide()
		var prefix: String="compact" if compact else "outward"
		validate_routes(prefix);validate_paths(prefix)
		app.set_view(Vector3(95,115,130),Vector3(-25,2,-32));await shot(prefix+"-09-landscape")
		app.set_view(Vector3(10,72,34),Vector3(-20,2,-28));await shot(prefix+"-10-aerial")
		app.set_view(Vector3(-8,5,-40),Vector3(-23,3,-57));await shot(prefix+"-11-street")
		await interior("yk_house_06",prefix+"-12-interior")
		check(p.state.report.unfed==0,prefix+" remains fed")
	p.dispatch({"kind":"asset_pressure"})
	for i in range(3):p.resolve_season()
	validate_routes("pressure");p.hide();app.hud.hide();await interior("yk_house_01","13-pressure")
	p.dispatch({"kind":"living_order","id":"prepare","value":0});p.dispatch({"kind":"living_order","id":"training","value":false})
	p.dispatch({"kind":"asset_principle","id":"reserve","value":2})
	for i in range(6):p.resolve_season()
	validate_routes("recovery");p.hide();app.hud.hide();await interior("yk_house_06","14-recovery")
	root.size=Vector2i(1280,800);app.hud.show();p.living_panel.inspect("workroom")
	await shot("15-small-window")
	await click_button("LivingOrder_prepare_1")
	check(p.state.living.prepare==1,"small-window controls remain usable")
	await click_button("LivingOrder_prepare_0")
	await shot("16-small-recovery")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"timings":timings},"  "))
	print("LIVING RENDER: %d captures; %d checks, %d failures"%[captures.size(),checks,failures]);quit(1 if failures else 0)
