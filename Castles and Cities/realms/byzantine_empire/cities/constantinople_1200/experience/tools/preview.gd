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
	root.always_on_top=true
	root.grab_focus()
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
	app.focus_landmark("sergius_bacchus")
	await _capture("15-octagonal-church")
	app.focus_landmark("pantokrator")
	await _capture("16-adjoining-churches")
	app.focus_landmark("holy_apostles")
	await _capture("17-five-domed-church")
	app.jump_to_district(0)
	app.set_flight_speed(400.0)
	app._set_navigation(app.Navigation.FLY)
	await _capture("18-district-flight")
	await _architecture_catalog()
	app.interior_view("sergius_bacchus")
	await _capture("21-octagonal-interior")
	app.interior_view("pantokrator")
	await _capture("22-pantokrator-chapel")
	app.interior_view("holy_apostles")
	await _capture("23-apostles-crossing")
	await _neighborhood()
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

func _architecture_catalog() -> void:
	# An inspection sheet of real production prototypes, not an artist's mockup.
	app.world.hide()
	app._hud.hide()
	var gallery:=Node3D.new()
	app.add_child(gallery)
	var records:Array=app.world.architecture.config["types"]
	for index in range(records.size()):
		var record:Dictionary=records[index]
		var node:=MeshInstance3D.new()
		node.mesh=app.world.architecture.mesh(record.id,true,2)
		node.position=Vector3((index%4-1.5)*22.0,0,(index/4-1.5)*26.0)
		gallery.add_child(node)
		var label:=Label3D.new()
		label.text=str(record.label).replace(" with ","\nwith ").replace(" and ","\nand ")
		label.font_size=44
		label.pixel_size=0.030
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.position=node.position+Vector3(0,1,9)
		label.modulate=Color("f0e0be")
		gallery.add_child(label)
	var floor_node:=MeshInstance3D.new()
	var floor_mesh:=PlaneMesh.new()
	floor_mesh.size=Vector2(130,145)
	floor_node.mesh=floor_mesh
	floor_node.position.y=-0.02
	floor_node.material_override=app.world.materials["ground"]
	gallery.add_child(floor_node)
	app.set_daytime(14.0)
	app.set_camera_view(Vector3(0,1,0),126,12,56)
	await _capture("19-architecture-catalog")
	app.set_camera_view(Vector3(0,2,13),70,16,42)
	await _capture("20-craft-courts")
	gallery.free()
	app.world.show()
	app._hud.show()

func _capture(label:String) -> void:
	for i in range(24): await process_frame
	RenderingServer.force_draw(false)
	var screenshot:=root.get_texture().get_image()
	var result:=screenshot.save_png(out_dir.path_join(label+".png"))
	if result!=OK:
		push_error("Capture failed: "+label)
		quit(1)
	captures.append(label)
	print("CAPTURE ",label)


func _neighborhood() -> void:
	app._hud.hide()
	app.set_daytime(14.0)
	app.neighborhood_overview()
	await _capture("24-pantokrator-neighborhood")
	app.walk_neighborhood(0)
	await _capture("25-connected-street")
	for i in [1,2,3]:
		app.walk_neighborhood(i)
		var n=app.world.neighborhood
		var record:Dictionary=n.parcels[n.config.stops[i].parcel_id]
		var target:Vector3=n.point(Vector2(record.front).lerp(record.back,0.3),record.floor_y+1.68)
		# Use the production swept mover to enter, retaining collision during QA.
		app.camera.position=n.move_walk(app.camera.position,target-app.camera.position)
		app.camera.look_at(n.point(Vector2(record.front).lerp(record.back,0.67),record.floor_y+1.2),Vector3.UP)
		await _capture(["","26-home-interior","27-baking-workshop","28-store-room"][i])
	app.walk_neighborhood(4)
	await _capture("29-garden-court")
	var n=app.world.neighborhood
	var home:Dictionary=n.parcels["north_west_e0_p3"]
	app.camera.position=n.point(Vector2(-55,-5.9),home.floor_y+n.config.dimensions.storey_m+1.68)
	app.camera.look_at(n.point(Vector2(-42,14),home.floor_y+3.5),Vector3.UP)
	await _capture("30-upper-gallery")
	app.camera.position=n.point(Vector2(home.front).lerp(home.back,0.64),home.floor_y+n.config.dimensions.storey_m+1.68)
	app.camera.look_at(n.point(Vector2(home.front).lerp(home.back,0.35)+Vector2(2,0),home.floor_y+4),Vector3.UP)
	await _capture("31-upper-room-roof")
	app._hud.show()
	app.walk_neighborhood(0)
	await _capture("32-walking-controls")
