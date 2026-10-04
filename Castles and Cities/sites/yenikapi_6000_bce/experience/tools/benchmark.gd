extends SceneTree
var campaign_mode:bool=false
var out_dir:="/tmp/yenikapi-benchmark"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="campaign":campaign_mode=true
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000)
	root.always_on_top=true
	root.grab_focus()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var begin:int=Time.get_ticks_msec()
	var app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var report:Dictionary={"startup_ms":Time.get_ticks_msec()-begin,"viewport":[root.size.x,root.size.y],"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"method":"120 warmup + 180 process-frame samples; vsync disabled; screenshots excluded; run alone","views":{}}
	if campaign_mode:
		var state:Dictionary=app.campaign.rules.new_state()
		for i in range(40):
			state=preload("res://tools/tutorial_driver.gd").orders(app.campaign.rules,state)
			state=app.campaign.rules.advance(state).state
			if state.phase=="town":break
		app.campaign.state=state
		app.show_campaign(state,app.campaign.rules,true)
		report.campaign_ready_ms=Time.get_ticks_msec()-begin
		report.citizens=app.campaign.rules.people(state).size()
		report.animated_workers=app.campaign_view.actors.size()
		report.hypothetical_turn=state.turn
	app.hud.hide()
	app.set_process(false)
	for label in ["landscape","aerial","street","interior"]:
		if label=="landscape":app.set_view(Vector3(146,118,194),Vector3(-5,2,5))
		elif label=="aerial":app.overview()
		elif label=="street":app.visit(1)
		else:app.visit(2)
		if campaign_mode and label=="interior":
			for building in app.world.buildings:
				if building.id=="growth_home_north":
					var at:Vector3=app.world.building_position(building,Vector3(0,1.68,1.7))
					app.set_view(at,app.world.building_position(building,Vector3(0,1.2,-1)),false)
		for i in range(120):await process_frame
		var samples:Array[float]=[]
		for i in range(180):
			var start:int=Time.get_ticks_usec()
			await process_frame
			samples.append((Time.get_ticks_usec()-start)/1000.0)
		samples.sort()
		report.views[label]={"median_ms":samples[90],"p95_ms":samples[171],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	FileAccess.open(out_dir.path_join("benchmark.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("VILLAGE BENCHMARK ",JSON.stringify(report))
	quit()
