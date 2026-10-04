extends SceneTree
## Exercises the production walking mover, actual shell cutouts and save baseline.
var app
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/custom_user_dir_name","Constantinople Neighborhood QA")
	call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)
func run() -> void:
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	while not app.ready_for_capture:await process_frame
	var n=app.world.neighborhood
	check(n.parcels.size()>=90,"Substantial occupied district")
	check(n.suppressed_ids.size()>0,"Legacy presentations replaced locally")
	check(app.world._layout.buildings.size()==17561,"Reference generator retained all 17,561 stable plot records")
	var original:Dictionary=app.world._layout.duplicate(true)
	var parcel_bytes:=var_to_bytes(n.parcels)
	var mesh_hashes:Array=[]
	for child in n.get_children():
		if child is MeshInstance3D:
			mesh_hashes.append(hash(var_to_bytes(child.mesh.get_faces())))
			check(child.visibility_range_end==0,"Interior details do not disappear with distance from batch origin")
	var again=load("res://src/neighborhood.gd").new()
	app.world.add_child(again)
	again.configure(app.world)
	check(var_to_bytes(again.parcels)==parcel_bytes,"Repeated district generation is byte-identical")
	var repeated_hashes:Array=[]
	for child in again.get_children():
		if child is MeshInstance3D:repeated_hashes.append(hash(var_to_bytes(child.mesh.get_faces())))
	check(repeated_hashes==mesh_hashes,"Repeated visible geometry is byte-identical")
	again.free()
	var ids:Array=n.parcels.keys()
	for i in range(ids.size()):
		var a:Dictionary=n.parcels[ids[i]]
		check(a.polygon.size()==4,"Parcel has four explicit boundary vertices")
		for j in range(i+1,ids.size()):
			var b:Dictionary=n.parcels[ids[j]]
			for poly in Geometry2D.intersect_polygons(a.polygon,b.polygon):
				var area:=0.0
				for k in range(poly.size()):area+=poly[k].cross(poly[(k+1)%poly.size()])
				check(absf(area)*0.5<0.025,"Parcel interiors overlap: "+ids[i]+" / "+ids[j])
		var front:Vector2=a.front
		var inward:Vector2=a.inward
		var eye:Vector3=n.point(front-inward*2.1,n.ground(front-inward*2.1)+n.config.dimensions.eye_height_m)
		# Ground floor access in both directions, through every actual wall cutout.
		var goal:Vector3=n.point(front+inward*1.0,a.floor_y+n.config.dimensions.eye_height_m)
		var arrived:Vector3=n.move_walk(eye,goal-eye)
		for attempt in range(4):arrived=n.move_walk(arrived,goal-arrived)
		check(Vector2(arrived.x-goal.x,arrived.z-goal.z).length()<0.18,"Entrance cannot be crossed: "+ids[i])
		# A deliberately oversized displacement must stop at a side wall.
		var side_goal:Vector3=n.point((a.polygon[0]+a.polygon[3])*0.5,a.floor_y+n.config.dimensions.eye_height_m)
		var from:Vector3=n.point((Vector2(a.front)+Vector2(a.back))*0.5,a.floor_y+n.config.dimensions.eye_height_m)
		var blocked:Vector3=n.move_walk(from,(side_goal-from)*1.6)
		check(blocked.distance_to(from+(side_goal-from)*1.6)>0.25,"High-delta walk tunneled through wall: "+ids[i])
	app.walk_neighborhood(0)
	# This continuous walk follows the authored road from the entry, through the
	# home and back out, then to the workshop and store without teleporting.
	for p in [Vector2(87,-28),Vector2(4,-11),Vector2(-22,-21),Vector2(-55.45,-24)]:walk_to(p,"street")
	for index in [1,2,3]:
		var stop:Dictionary=n.config.stops[index]
		var r:Dictionary=n.parcels[stop.parcel_id]
		if index==2:
			for p in [Vector2(-55,-24),Vector2(-22,-21),Vector2(4,-11)]:walk_to(p,"workshop approach")
		if index==3:
			for p in [Vector2(4,-11),Vector2(44,-18)]:walk_to(p,"store approach")
		var outside:Vector2=Vector2(r.front)-Vector2(r.inward)*2.1
		walk_to(outside,stop.id+" threshold")
		walk_to(Vector2(r.front).lerp(r.back,0.52),stop.id+" furnished interior")
		walk_to(outside,stop.id+" exit")
	# Gallery and home room connect at the upper doorway; walk both ways on stairs.
	app.walk_neighborhood(1)
	var home:Dictionary=n.parcels["north_west_e0_p3"]
	walk_to(Vector2(home.front).lerp(home.back,0.6),"home to court")
	walk_to(Vector2(home.back)+Vector2(0,2.2),"rear door")
	walk_to(Vector2(-55,3),"court around stairs")
	walk_to(Vector2(-52.4,3),"stair foot approach")
	walk_to(Vector2(-52.0,-5.6),"stair ascent")
	check(app.camera.position.y>float(home.floor_y)+4.7,"Gallery reached at upper-storey height")
	walk_to(Vector2(-55.4,-6.7),"gallery landing")
	walk_to(Vector2(-55.4,-10),"upper home entrance")
	walk_to(Vector2(-55.4,-6.7),"upper home exit")
	walk_to(Vector2(-52.0,-5.6),"gallery to stair")
	walk_to(Vector2(-52.4,3),"stair descent")
	check(app.camera.position.y<float(home.floor_y)+2.0,"Stair returns to court ground")
	# Rebuilding presentation stages never changes authored district topology.
	app.set_stage("expanded")
	check(var_to_bytes(n.parcels)==parcel_bytes,"Creative stage changed district identities")
	app.set_stage("reference_1200")
	check(app.world._layout==original,"Stage return altered protected baseline")
	app.world.set_neighborhood_enabled(false)
	check(app.world._architecture_placements.size()==17561,"Legacy presentation restores all reference buildings")
	check(not n.visible,"Legacy mode hides district geometry")
	app.world.set_neighborhood_enabled(true)
	check(var_to_bytes(n.parcels)==parcel_bytes,"Legacy toggle mutated authored district")
	# A real v1 creative save in the migrated area keeps IDs and coordinates and
	# automatically selects its previous presentation. No user save is touched.
	app._variant_path="/tmp/constantinople-neighborhood-save-%d.json"%OS.get_process_id()
	app.add_design_object("house",Vector2(-2710,1110),33,1.15)
	var saved: Array=app.design_objects.duplicate(true)
	check(app.save_variant(),"Creative v1 save writes")
	app.clear_design()
	check(app.load_variant(),"Creative v1 save loads")
	check(app.design_objects==saved,"Creative object coordinates, scale and IDs are preserved")
	check(not n.active and app._legacy_neighborhood.button_pressed,"Old design selects legacy fabric coherently")
	app.clear_design()
	DirAccess.remove_absolute(app._variant_path)
	app.neighborhood_overview()
	check(n.active and not app._legacy_neighborhood.button_pressed,"District entry restores detailed fabric and control state")
	app.walk_neighborhood(2)
	var return_pose:Vector3=app.camera.position
	app.camera.position+=Vector3(10,0,0)
	app._approach_selection()
	check(app.camera.position.distance_to(return_pose)<0.01,"Inspector approach returns to the displayed neighborhood stop")
	app.focus_landmark("hagia_sophia")
	check(not app._interior_button.disabled and app._selected_neighborhood_stop==-1,"Landmark interiors remain usable after neighborhood walking")
	app.set_flight_speed(1000.0)
	app.jump_to_district(3)
	check(app._fly_speed==1000.0,"District walking altered faster flight presets")
	for message in failures:printerr("NEIGHBORHOOD_FAILURE: ",message)
	print("NEIGHBORHOOD_CHECKS checks=%d failures=%d parcels=%d masked=%d"%[checks,failures.size(),n.parcels.size(),n.suppressed_ids.size()])
	app.free()
	quit(0 if failures.is_empty() else 1)
func walk_to(p:Vector2,label:String) -> void:
	var n=app.world.neighborhood
	var target:Vector3=n.point(p)
	for i in range(500):
		var delta:Vector3=target-app.camera.position
		delta.y=0
		if delta.length()<0.12:break
		app.camera.look_at(app.camera.position+delta,Vector3.UP)
		app._move_camera(Vector3.FORWARD,minf(0.035,delta.length()/5.0),false)
	var error:=Vector2(target.x-app.camera.position.x,target.z-app.camera.position.z).length()
	check(error<0.25,"Continuous route blocked at %s (%s, error %.2f m)"%[label,p,error])
