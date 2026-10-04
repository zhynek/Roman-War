extends SceneTree
## Same cameras and sampling method can run against the frozen v0.2 project.
## Run alone: 120 warm-up frames, 180 measured frames; excludes PNG readback.
var app
var out_dir:="/tmp/constantinople-benchmark"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.always_on_top=true
	root.grab_focus()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var begin:=Time.get_ticks_msec()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	while not app.ready_for_capture:await process_frame
	var report:={"startup_ms":Time.get_ticks_msec()-begin,"viewport":str(root.size),"gpu":RenderingServer.get_video_adapter_name(),"method":"120 warmup + 180 process-frame samples per fixed camera, vsync disabled, screenshots excluded","views":{}}
	app._hud.hide()
	app.set_daytime(14)
	for label in ["city","district","street"]:
		root.grab_focus()
		if label=="city":app.overview()
		elif label=="district":app.set_camera_view(Vector3(-2710,app.world._surface_height(-2710,1135),-1135),290,28,55)
		else:
			app._set_navigation(app.Navigation.FLY)
			app.camera.position=Vector3(-2620,app.world._surface_height(-2620,1081)+1.92,-1081)
			app.camera.look_at(Vector3(-2706,app.camera.position.y,-1099),Vector3.UP)
		for i in range(120):await process_frame
		var samples:Array[float]=[]
		for i in range(180):
			var start:=Time.get_ticks_usec()
			await process_frame
			samples.append((Time.get_ticks_usec()-start)/1000.0)
		samples.sort()
		report.views[label]={"median_ms":samples[90],"p95_ms":samples[171],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(out_dir.path_join(label+".png"))
	FileAccess.open(out_dir.path_join("benchmark.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("BENCHMARK ",JSON.stringify(report))
	quit()
