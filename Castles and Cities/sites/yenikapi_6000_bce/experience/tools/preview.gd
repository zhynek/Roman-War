extends SceneTree
var app
var out_dir:="/tmp/yenikapi-qa"
var captures:Array=[]
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000)
	root.always_on_top=true
	root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await shot("01-arrival-controls")
	app.hud.hide()
	app.set_view(Vector3(146,118,194),Vector3(-5,2,5))
	await shot("02-landscape")
	app.overview()
	await shot("03-aerial")
	app.set_view(Vector3(-8,124,30),Vector3(-8,0,0))
	await shot("04-plan")
	app.visit(1)
	await shot("05-shared-yard")
	for spec in [[0,"06-home-interior"],[5,"07-working-interior"],[8,"08-storage-interior"],[7,"09-round-interior"]]:
		var b:Dictionary=app.world.buildings[spec[0]]
		var start:Vector3=app.world.building_position(b,Vector3(0,1.68,float(b.size[1])*.5+1.4))
		var target:Vector3=app.world.building_position(b,Vector3(0,1.68,float(b.size[1])*.5-.6))
		var reached:Vector3=app.world.walk(start,target-start)
		if Vector2(reached.x-target.x,reached.z-target.z).length()>.1:
			push_error("Rendered entry failed: "+b.id);quit(1);return
		app.set_view(reached,app.world.building_position(b,Vector3(-.1,1.1,-float(b.size[1])*.3)),false)
		await shot(spec[1])
	app.visit(5);await shot("10-stream-landing")
	app.visit(6);await shot("11-cultivation")
	app.set_view(Vector3(-31,10,38),Vector3(-20,4,14));await shot("12-roof-construction")
	app.hud.show();app.visit(0);app.info.show();await shot("13-evidence")
	app.info.hide()
	root.size=Vector2i(1280,800)
	await shot("14-small-window")
	FileAccess.open(out_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"stats":app.world.stats,"gpu":RenderingServer.get_video_adapter_name()},"  "))
	print("VILLAGE RENDER PASS: ",captures.size()," captures")
	quit()
func shot(label:String) -> void:
	for i in range(25):await process_frame
	RenderingServer.force_draw(false)
	if root.get_texture().get_image().save_png(out_dir.path_join(label+".png"))!=OK:
		push_error("Capture failed "+label);quit(1);return
	captures.append(label)
	print("CAPTURE ",label)
