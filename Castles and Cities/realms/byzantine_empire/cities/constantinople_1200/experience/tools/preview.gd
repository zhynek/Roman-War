extends SceneTree
## Real-render QA. Images and timing reports remain outside game assets.
var app: Node3D
var out_dir := "/tmp/constantinople-qa"
var captures: Array[String] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): out_dir=arg.trim_prefix("out_dir=")
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	var deadline:=Time.get_ticks_msec()+120000
	while not app.ready_for_capture:
		if Time.get_ticks_msec()>deadline:
			push_error("City failed to reach render readiness")
			quit(1)
			return
		await process_frame
	await _capture("01-hagia-sophia")
	app.overview()
	await _capture("02-peninsula")
	app.plan_view()
	await _capture("03-plan")
	app.focus_landmark("hippodrome")
	await _capture("04-hippodrome")
	app.focus_landmark("golden_gate")
	await _capture("05-golden-gate")
	app.set_camera_view(Vector3(-680,12,-1710),310,125,26)
	await _capture("06-golden-horn")
	app.focus_landmark("basilica_cistern")
	await _capture("07-cistern-cutaway")
	app.interior_view("basilica_cistern")
	await _capture("08-cistern-interior")
	app.interior_view("hagia_sophia")
	await _capture("09-hagia-interior")
	app.set_camera_view(Vector3(-1850,55,100),95,25,20)
	await _capture("10-neighborhood")
	app.set_stage("expanded")
	app.overview()
	app.set_daytime(17.0)
	await _capture("11-creative-expansion")
	app.set_stage("reference_1200")
	app.set_daytime(12.0)
	app.home_view()
	app._toggle_editor()
	app.add_design_object("tower",Vector2(-5860,-400),0,1.0)
	app.set_camera_view(Vector3(-5860,12,400),150,35,25)
	await _capture("12-creative-workshop")
	app._toggle_editor()
	app.clear_design()
	app.focus_landmark("aetius_reservoir")
	await _capture("13-open-reservoir")
	app.focus_landmark("valens_aqueduct")
	await _capture("14-aqueduct")
	app.home_view()
	var samples:Array[float]=[]
	for i in range(90):
		var start:=Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec()-start)/1000.0)
	samples.sort()
	var report={"captures":captures,"stats":app.stats,"median_frame_ms":samples[45],"p95_frame_ms":samples[85],"renderer":RenderingServer.get_video_adapter_name()}
	var file:=FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("CITY_RENDER_QA ",JSON.stringify(report))
	quit(0)

func _capture(label:String) -> void:
	for i in range(24): await process_frame
	await RenderingServer.frame_post_draw
	var screenshot:=root.get_texture().get_image()
	var result:=screenshot.save_png(out_dir.path_join(label+".png"))
	if result!=OK:
		push_error("Capture failed: "+label)
		quit(1)
	captures.append(label)
	print("CAPTURE ",label)
