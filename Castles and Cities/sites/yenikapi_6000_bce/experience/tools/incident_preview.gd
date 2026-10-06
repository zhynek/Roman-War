extends "res://tools/land_preview.gd"
const IncidentDriver=preload("res://tools/incident_driver.gd")
func shot(name_: String) -> void:
	await super.shot(name_)
	if name_.ends_with("household-recovery") or name_.ends_with("repaired-materials") or name_=="09-prepared-store-interior":
		# Detect the black-material rebuild failure that geometry/input checks miss.
		# These fixed, HUD-free interior cameras must retain visible lit furnishings.
		var pixels: Image=root.get_texture().get_image()
		var luminance: float=0.0
		for y in range(8):
			for x in range(8):
				var c: Color=pixels.get_pixel(pixels.get_width()*(x+4)/16,pixels.get_height()*(y+4)/16)
				luminance+=(c.r+c.g+c.b)/3.0
		check(luminance/64.0>.12,"lit material interiors survive rebuild: "+name_)
func _initialize() -> void:
	out_dir="/tmp/yenikapi-incident-qa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;p.save_path=out_dir.path_join("incident-test.json")
	p.open();await click_button("BeginIncidents")
	check(p.rules.incidents.active(p.state) and p.state.food==100 and p.state.wood==30,"real input begins from normal stocks")
	await shot("01-exposure-overview")
	# Early ordinary material preparation through the actual Village controls.
	await click_button("VillageTab");await click_button("LivingOrder_prepare_1")
	for i in range(4):await click_button("ResolveSeason")
	p.hide();app.hud.hide()
	var e: Dictionary=p.rules.incidents.current(p.state)
	var target:=Vector3(-42,app.world.floor_height(-42,-82),-82)
	var eye: Vector3=target+Vector3(0,22,6)
	app.set_view(eye,target)
	var expected: Dictionary=p.rules.command(p.state,{"kind":"living_inspect","id":"north_wood"}).state
	expected=p.rules.command(expected,{"kind":"incident_inspect","id":"north_wood"}).state
	await world_click()
	check(p.visible and p.tabs.current_tab==9 and p.state==expected,"world and targeted local knowledge agree")
	await shot("02-local-warning")
	p.tabs.current_tab=0;await click_button("ReviewIncidentStep");await click_button("ReviewIncidentStep")
	await click_button("IncidentsTab");await click_button("RestrictIncident")
	await click_button("AssetCommission_incident_approach_prepare")
	check(p.rules.land.committed(p.state,"incident_approach_prepare",p.rules),"paid preparation through real UI")
	await shot("03-paid-response")
	p.tabs.current_tab=0;await click_button("ReviewIncidentStep")
	for i in range(4):await click_button("ResolveSeason")
	await click_button("IncidentsTab");await shot("04-approach-outcome")
	validate_routes("damaged approach");validate_paths("damaged approach")
	p.hide();app.hud.hide();app.set_view(target+Vector3(10,5,12),target);await shot("05-approach-repair-site")
	app.hud.show();p.show();p.tabs.current_tab=0;await click_button("ReviewIncidentStep")
	await click_button("IncidentsTab");await click_button("AssetCommission_incident_approach_repair")
	p.tabs.current_tab=0;await click_button("ReviewIncidentStep")
	await click_button("IncidentsTab");await click_button("AssetPause_incident_approach_repair")
	var paid: Dictionary=p.state.duplicate(true)
	check(p.rules.forecast(p.state).assets.projects.incident_approach_repair.crew==0,"paused recovery frees labor")
	await shot("06-recovery-overcommitment")
	p.tabs.current_tab=0;await click_button("ReviewIncidentStep")
	await click_button("IncidentsTab");await click_button("AssetPause_incident_approach_repair")
	await click_button("VillageTab");await click_button("LivingOrder_prepare_0")
	for i in range(3):await click_button("ResolveSeason")
	check(p.state.incidents.records[0].recovered>=0,"real seasonal repair restores access")
	p.tabs.current_tab=0;await click_button("ReviewIncidentStep")
	check(p.state.incidents.tutorial==7,"complete connected guide using ordinary controls")
	await shot("07-guide-and-restored-place")
	# A second public-command path exercises watch focus, equipment and stores.
	while p.state.turn<26:
		p.state=IncidentDriver.orders(p.rules,p.state,"overview");app.show_campaign(p.state,p.rules);p.refresh()
		if p.state.turn==24:
			p.tabs.current_tab=9;await shot("08-store-warning-options")
			await click_button("InspectIncident")
			p.hide();app.hud.hide();target=Vector3(40,app.world.floor_height(40,21),21)
			app.set_view(target+Vector3(10,7,12),target);await shot("08b-waterside-warning")
			target=Vector3(27,app.world.floor_height(27,-8),-8)
			app.set_view(target+Vector3(6,4,8),target);await shot("09b-watch-post")
			p.hide();app.hud.hide();await interior("yk_store_01","09-prepared-store-interior")
			app.hud.show();p.show()
		await click_button("ResolveSeason")
	p.tabs.current_tab=9;await shot("10-watch-outcome")
	validate_routes("watch and response");validate_paths("watch and response")
	p.hide();app.hud.hide();target=Vector3(40,app.world.floor_height(40,21),21)
	app.set_view(target+Vector3(10,6,12),target);await shot("10b-waterside-recovery")
	app.hud.show();p.show()
	check(p.save_campaign(),"save resolved incident")
	var saved: Dictionary=p.state.duplicate(true);p.resolve_season();check(p.load_campaign() and p.state==saved,"exact load preserves outcome and recovery")
	var invariant: Dictionary=p.state.duplicate(true)
	for delta in [.001,.008,.016,.1,1.0]:
		for i in range(60):app.campaign_view.life.step(delta)
		app.overview()
	check(p.state==invariant,"camera animation and frame rates have no authority")
	# Both grown layouts are obtained by public commands, then explicitly adopt.
	for compact in [true,false]:
		p.state=preload("res://tools/living_driver.gd").initial(p.rules)
		for i in range(48):
			p.state=Driver.orders(p.rules,p.state,compact)
			p.state=preload("res://tools/living_driver.gd").orders(p.rules,p.state,true)
			p.state=p.rules.advance(p.state).state
		p.state=p.rules.command(p.state,{"kind":"incident_begin"}).state
		for i in range(8):p.state=p.rules.advance(p.state).state
		app.show_campaign(p.state,p.rules,true);p.refresh();p.hide();app.hud.hide()
		var prefix: String="compact" if compact else "outward"
		validate_routes(prefix+" disruption");validate_paths(prefix+" disruption")
		app.set_view(Vector3(95,115,130),Vector3(-25,2,-32));await shot(prefix+"-11-landscape")
		app.set_view(Vector3(10,72,34),Vector3(-20,2,-28));await shot(prefix+"-12-aerial")
		app.set_view(Vector3(-8,5,-40),Vector3(-23,3,-57));await shot(prefix+"-13-street")
		await interior("yk_house_01",prefix+"-14-household-recovery")
		check(p.state.report.unfed==0,prefix+" remains fed after damage")
		if not compact:check(not p.rules.forecast(p.state).land.access,"outward loaded access impaired")
		app.hud.show();p.show();p.tabs.current_tab=9
		await click_button("AssetCommission_incident_approach_repair")
		for i in range(4):await click_button("ResolveSeason")
		check(p.state.incidents.records[0].recovered>=0,prefix+" restores paid access")
		p.hide();app.hud.hide();await interior("yk_house_06",prefix+"-15-repaired-materials")
	root.size=Vector2i(1280,800);app.hud.show();p.show();p.tabs.current_tab=9
	await shot("16-small-window-record")
	check(p.get_global_rect().position.x>=0 and p.get_global_rect().end.y<=root.get_visible_rect().size.y,"small window fits")
	await click_button("VillageTab");await click_button("LivingOrder_training_1");await click_button("LivingOrder_training_0")
	await shot("17-small-window-orders")
	app.show_reference();check(app.world.buildings.size()==9,"dated reference intact")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"timings":timings},"  "))
	print("INCIDENT RENDER: %d captures; %d checks, %d failures"%[captures.size(),checks,failures]);quit(1 if failures else 0)
func world_click() -> void:
	var mouse: Vector2=root.get_visible_rect().size*.5
	var motion:=InputEventMouseMotion.new();motion.position=mouse;motion.global_position=mouse;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=mouse;event.global_position=mouse;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true);await process_frame
