extends SceneTree
const Fabric=preload("res://src/fabric.gd")
var app
var checks:int=0
var failures:int=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func run() -> void:
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	await process_frame
	check(app.ready_for_capture,"app loaded")
	var w=app.world
	for stop in app.data.stops:
		check(not w.blocked(Vector3(stop.at[0],0,stop.at[1])),"safe stop "+stop.id)
	for b in w.buildings:
		var start:Vector3=w.building_position(b,Vector3(0,1.68,float(b.size[1])*.5+1.2))
		var target:Vector3=w.building_position(b,Vector3(0,1.68,float(b.size[1])*.5-.65))
		check(not w.blocked(start),"door approach "+b.id)
		var reached:Vector3=w.walk(start,target-start)
		check(Vector2(reached.x-target.x,reached.z-target.z).length()<.05,"enter "+b.id)
		var exit_:Vector3=w.walk(reached,start-reached)
		check(Vector2(exit_.x-start.x,exit_.z-start.z).length()<.05,"exit "+b.id)
		var wall_start:Vector3=w.building_position(b,Vector3(-float(b.size[0])*.5-1,1.68,0))
		var wall_end:Vector3=w.building_position(b,Vector3(float(b.size[0])*.5+1,1.68,0))
		var hit:Vector3=w.walk(wall_start,wall_end-wall_start)
		check(hit.distance_to(wall_start)<1.5,"high displacement cannot tunnel "+b.id)
		var ray:Dictionary=w.pick(wall_start,(wall_end-wall_start).normalized())
		check(not ray.id.is_empty(),"picking shares physical wall "+b.id)
	# A continuous ground route visits every required use without teleporting.
	var route:Array=[[1,42],[1,32],[0,21],[-3,13],[-10,13]]
	var b0:Dictionary=w.buildings[0]
	var door:Vector3=w.building_position(b0,Vector3(0,0,1.8))
	var door_out:Vector3=w.building_position(b0,Vector3(0,0,float(b0.size[1])*.5+1.2))
	route.append([door_out.x,door_out.z]);route.append([door.x,door.z]);route.append([door_out.x,door_out.z]);route.append([-10,15])
	route.append_array([[-21,16],[-28,16],[-28,3],[-26,-3]])
	var craft:Vector3=w.building_position(w.buildings[5],Vector3(0,0,1.4))
	var craft_out:Vector3=w.building_position(w.buildings[5],Vector3(0,0,3.3))
	route.append([craft_out.x,craft_out.z]);route.append([craft.x,craft.z]);route.append([craft_out.x,craft_out.z]);route.append_array([[-26,-3],[-28,3],[-28,16],[-21,16],[-10,18],[-7,26],[-4,31]])
	var store:Vector3=w.building_position(w.buildings[8],Vector3(0,0,1.2))
	var store_out:Vector3=w.building_position(w.buildings[8],Vector3(0,0,3.1))
	route.append([store_out.x,store_out.z]);route.append([store.x,store.z]);route.append([store_out.x,store_out.z]);route.append_array([[-4,31],[3,36],[4,23],[12,14],[24,14],[24,29],[40,29]])
	var p:=Vector3(route[0][0],0,route[0][1])
	p.y=w.floor_height(p.x,p.z)+1.68
	for target_ in route.slice(1):
		var target:=Vector3(target_[0],p.y,target_[1])
		p=w.walk(p,target-p)
		check(Vector2(p.x-target.x,p.z-target.z).length()<.08,"continuous route to "+str(target_))
	# Every rendered footpath is walkable along its actual curved centerline.
	for path in app.data.objects:
		if path.kind!="path":continue
		var points:Array=path.points
		var walker:=Vector3(points[0][0],0,points[0][1])
		walker.y=w.floor_height(walker.x,walker.z)+1.68
		var passable:bool=true
		for i in range(points.size()-1):
			var a:=Vector2(points[i][0],points[i][1])
			var b:=Vector2(points[i+1][0],points[i+1][1])
			var before_:=Vector2(points[maxi(0,i-1)][0],points[maxi(0,i-1)][1])
			var after_:=Vector2(points[mini(points.size()-1,i+2)][0],points[mini(points.size()-1,i+2)][1])
			for j in range(1,41):
				var target_:Vector2=a.cubic_interpolate(b,before_,after_,float(j)/40)
				walker=w.walk(walker,Vector3(target_.x-walker.x,0,target_.y-walker.z))
				if Vector2(walker.x-target_.x,walker.z-target_.y).length()>.08:
					if passable:printerr("Blocked path ",path.id," near ",target_)
					passable=false
		check(passable,"curved footpath "+path.id)
	# Production surface interpolation must match the actual indexed mesh.
	var mesh:ArrayMesh=w.object_nodes.landscape.mesh
	for surface in range(mesh.get_surface_count()):
		var arrays:Array=mesh.surface_get_arrays(surface)
		var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var fine_count:int=6*int(2*app.data.terrain.extent/app.data.terrain.grid)*int(2*app.data.terrain.extent/app.data.terrain.grid)
		for i in range(0,mini(fine_count,indices.size()),maxi(3,int(fine_count/180.0)/3*3)):
			if i+2>=indices.size():continue
			var a:Vector3=verts[indices[i]]
			var b:Vector3=verts[indices[i+1]]
			var c:Vector3=verts[indices[i+2]]
			var midpoint:Vector3=(a+b+c)/3
			if absf(midpoint.x)>238 or absf(midpoint.z)>238:continue
			check(absf(w.surface_height(midpoint.x,midpoint.z)-midpoint.y)<.002,"rendered triangle walking agreement")
	# Repeat generation includes furniture/material surface assignment and collisions.
	var fingerprint:String=mesh_hash(w)
	var other=load("res://src/village.gd").new()
	other.build(app.data)
	check(mesh_hash(other)==fingerprint,"repeatable geometry bytes")
	check(var_to_bytes(other.solids)==var_to_bytes(w.solids),"repeatable collision")
	other.free()
	_lineage()
	_saves()
	# Exercise actual input handler, view selection, and safe flight-to-walk.
	var event:=InputEventKey.new();event.pressed=true;event.keycode=KEY_F
	app.visit(0);app._unhandled_input(event);check(app.flying,"F enters flight")
	app._unhandled_input(event);check(not app.flying,"F returns to walk")
	app.set_view(Vector3(70,70,150),Vector3(0,0,0));app.set_flying(false)
	check(not app.flying and not w.blocked(app.camera.position),"safe walking recovery over sea")
	app.visit(0)
	var walk_start:Vector3=app.camera.position
	var held:=InputEventKey.new();held.keycode=KEY_W;held.pressed=true
	Input.parse_input_event(held)
	await process_frame
	app._process(.1)
	held.pressed=false;Input.parse_input_event(held)
	await process_frame
	check(app.camera.position.distance_to(walk_start)>.2,"actual W key moves walker")
	app.set_flying(true)
	var fly_start:Vector3=app.camera.position
	held.keycode=KEY_E;held.pressed=true;Input.parse_input_event(held)
	await process_frame
	app._process(.1)
	held.pressed=false;Input.parse_input_event(held)
	await process_frame
	check(app.camera.position.y>fly_start.y+1,"actual E key rises in flight")
	check(ProjectSettings.get_setting("application/config/custom_user_dir_name")=="Roman War Yenikapi Early Settlement","save namespace separate")
	print("VILLAGE CHECKS: ",checks," checks, ",failures," failures; mesh ",fingerprint)
	quit(1 if failures else 0)
func mesh_hash(world) -> String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256)
	var ids:Array=world.object_nodes.keys();ids.sort()
	for id in ids:
		h.update(id.to_utf8_buffer())
		var mesh:ArrayMesh=world.object_nodes[id].mesh
		for i in range(mesh.get_surface_count()):
			var arrays:Array=mesh.surface_get_arrays(i)
			h.update(var_to_bytes(arrays[Mesh.ARRAY_VERTEX]));h.update(var_to_bytes(arrays[Mesh.ARRAY_INDEX]))
	return h.finish().hex_encode()
func _lineage() -> void:
	var base:Dictionary=app.data
	var before:String=JSON.stringify(base)
	var first:Dictionary=base.objects[0]
	var altered:Dictionary=first.duplicate(true);altered.use="storage"
	var added:Dictionary=first.duplicate(true);added.id="new_house"
	var scenario:Dictionary={"id":"test_only","kind":"hypothetical","base_snapshot_id":base.snapshot_id,"changes":[{"kind":"altered","before":[first.id],"after":[altered]},{"kind":"added","before":[],"after":[added]},{"kind":"abandoned","before":[base.objects[1].id],"after":[]}]}
	var result:Dictionary=Fabric.resolve(base,scenario)
	check(not result.has("error"),"explicit alteration addition and abandonment")
	for record in result.get("objects",[]):
		if record.id==first.id:check(record.revision==2 and record.change.predecessors==[first.id+"@1"],"stable revision ancestry")
		if record.id==base.objects[1].id:check(not record.active,"abandoned fabric preserved")
	check(JSON.stringify(base)==before,"scenario cannot mutate dated snapshot")
	var invalid:Dictionary=scenario.duplicate(true);invalid.base_snapshot_id="reference_1200"
	check(Fabric.resolve(base,invalid).has("error"),"cannot apply village changes to medieval snapshot")
	invalid=scenario.duplicate(true);invalid.changes[1].after[0].id=first.id
	check(Fabric.resolve(base,invalid).has("error"),"reject identity collision")
	var child1:Dictionary=first.duplicate(true);child1.id="split_a"
	var child2:Dictionary=first.duplicate(true);child2.id="split_b"
	var split:Dictionary={"id":"split_fixture","kind":"hypothetical","base_snapshot_id":base.snapshot_id,"changes":[{"kind":"subdivided","before":[first.id],"after":[child1,child2]}]}
	result=Fabric.resolve(base,split)
	check(not result.has("error"),"explicit subdivision")
	for record in result.get("objects",[]):
		if record.id==first.id:check(not record.active,"subdivision retains retired parent")
		if record.id in ["split_a","split_b"]:check(record.change.predecessors==[first.id+"@1"],"children trace parent")
	for kind in ["retained","removed","replaced"]:
		split.changes=[{"kind":kind,"before":[first.id],"after":[child1] if kind=="replaced" else []}]
		check(not Fabric.resolve(base,split).has("error"),"relationship "+kind)
func _saves() -> void:
	var path:String="/tmp/yenikapi-view-test-"+str(OS.get_process_id())+".json"
	app.visit(0)
	var at:Vector3=app.camera.position
	check(app.save_view(path),"real view write")
	app.overview()
	check(app.load_view(path),"real view read")
	check(app.camera.position.distance_to(at)<.001 and not app.flying,"view round trip")
	var valid:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	for key in ["snapshot_id","position","version","navigation","flight_speed","format"]:
		var bad:Dictionary=valid.duplicate(true);bad[key]=["invalid"]
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(bad))
		check(not app.load_view(path),"reject malformed save "+key)
		check(app.camera.position.distance_to(at)<.001,"rejected save preserves view")
	FileAccess.open(path,FileAccess.WRITE).store_string('{"version":1,"stage":"reference_1200","objects":[]}')
	check(not app.load_view(path),"medieval creative format rejected without migration")
	DirAccess.remove_absolute(path)
