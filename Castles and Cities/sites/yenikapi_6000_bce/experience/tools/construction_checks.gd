extends SceneTree
const ReadModel=preload("res://src/project_presentation.gd")
const Saves=preload("res://src/campaign_save.gd")
var checks: int=0
var failures: int=0
var r
var model=ReadModel.new()
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var result: Dictionary=r.command(s,a);check(result.has("state"),str(a)+" "+str(result.get("error","")));return result.get("state",s)
func staffing(s: Dictionary,id: String,crew: int=1,paused: bool=false) -> Dictionary:return cmd(s,{"kind":"asset_project","id":id,"crew":crew,"priority":1,"paused":paused})
func run() -> void:
	var app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	r=app.campaign.rules
	var s: Dictionary=preload("res://tools/living_driver.gd").initial(r)
	var path: String="/tmp/yenikapi-construction-checks-"+str(OS.get_process_id())+".json"
	s=cmd(s,{"kind":"commission","id":"care_shelter"});s=staffing(s,"care_shelter")
	var seen: Array=[]
	for i in range(8):
		var d: Dictionary=model.describe(s,r,"care_shelter",r.forecast(s),true)
		if d.stage not in seen:seen.append(d.stage)
		var frozen: String=JSON.stringify(s)
		app.campaign.state=s;app.show_campaign(s,r);app.visual_commands.open();app.visual_commands.show_project("care_shelter")
		var world_id: int=app.world.get_instance_id()
		var solids: int=app.world.solids.size()
		app.visual_commands.enter_room();app.visual_commands.room().choose("care_shelter");app.visual_commands.show_project("care_shelter");app.visual_commands.close_sheet()
		check(JSON.stringify(s)==frozen,"site/room/easel/overview are pure")
		app.show_campaign(s,r)
		check(app.world.solids.size()==solids and app.world.get_instance_id()==world_id,"unchanged views retain world and collision")
		check(app.campaign_view.life.unreachable.is_empty(),"all workers have routes at stage "+str(d.stage))
		for routine in app.campaign_view.life.routines:
			for j in range(1,routine.route.size()):
				var from: Vector3=routine.route[j-1]+Vector3.UP*1.68;var to: Vector3=routine.route[j]+Vector3.UP*1.68
				var reached: Vector3=app.world.walk(from,to-from)
				check(Vector2(reached.x-to.x,reached.z-to.z).length()<.1,"every construction stage leaves actual citizen route walkable "+str(d.stage)+" "+routine.id)
		if d.queued:
			check(app.campaign_view.construction_view.sites.care_shelter.stage==d.stage,"scene stage agrees with read model")
			check(d.crew==d.assigned.size(),"displayed workers are the actual allocated citizens")
		check(Saves.write(path,s,r),"save intermediate construction")
		check(Saves.read(path,r)==s,"intermediate work, investment and relationships roundtrip")
		if d.complete:break
		var next: Dictionary=r.advance(s).state
		var expected: int=mini(d.total,d.progress+d.work)
		check(model.describe(next,r,"care_shelter").progress==expected,"next-season forecast agrees with exact progress")
		s=next
	check(seen==[0,1,2,3,4],"all visible construction stages reached through finite public work")
	var cold=preload("res://src/village.gd").new();root.add_child(cold);cold.build(app.world.data)
	check(app.world.object_nodes.landscape.mesh.get_faces()==cold.object_nodes.landscape.mesh.get_faces(),"incremental terrace triangles equal a fresh complete build")
	for id in cold.object_nodes:
		check(app.world.object_nodes.has(id) and app.world.object_nodes[id].mesh.get_faces()==cold.object_nodes[id].mesh.get_faces(),"retained/rebuilt physical geometry equals cold source "+id)
	cold.free()
	var old_world: int=app.world.get_instance_id()
	s=cmd(s,{"kind":"commission","id":"land_adapt_workroom"});s=staffing(s,"land_adapt_workroom",4)
	s=r.advance(s).state;app.show_campaign(s,r)
	check(app.world.get_instance_id()==old_world,"adaptation with numeric-equivalent footprint retains world")
	# Exact navigation checks include every new planning-room collision.
	var life=app.campaign_view.life
	for routine in life.routines:
		for j in range(1,routine.route.size()):
			var start: Vector3=routine.route[j-1]+Vector3.UP*1.68;var target: Vector3=routine.route[j]+Vector3.UP*1.68
			var reached: Vector3=app.world.walk(start,target-start)
			check(Vector2(reached.x-target.x,reached.z-target.z).length()<.1,"cached citizen route remains walkable "+routine.id)

	# The original occupied store itself selects its ongoing adaptation.
	var adapted: Dictionary=preload("res://tools/living_driver.gd").initial(r)
	adapted=cmd(adapted,{"kind":"commission","id":"shared_store"})
	app.campaign.state=adapted;app.show_campaign(adapted,r);app.visual_commands.open()
	var store_record: Dictionary={}
	for b in app.world.buildings:
		if b.id=="yk_store_01":store_record=b;break
	var target: Vector3=app.world.building_position(store_record,Vector3(0,1,0))
	var origin: Vector3=target+Vector3(0,10,12)
	check(app.visual_commands.pick(origin,(target-origin).normalized()) and app.visual_commands.detail.get("id")=="shared_store","occupied building opens its exact adaptation project")
	# Competing paid projects, pause, exact refund, no duplicate credit.
	s=preload("res://tools/living_driver.gd").initial(r)
	for id in ["shared_store","care_shelter"]:s=cmd(s,{"kind":"commission","id":id});s=staffing(s,id,4)
	check(s.wood==2,"two projects spend the real opening stock once")
	var f: Dictionary=r.forecast(s);var sum_: int=0
	for project in f.assets.projects.values():sum_+=int(project.crew)
	check(sum_<=r.people(s,true).size() and sum_<=r.land.totals(s,r).work,"projects compete for finite adults and places")
	s=r.advance(s).state
	var before: Dictionary=model.describe(s,r,"care_shelter")
	s=staffing(s,"care_shelter",4,true)
	for i in range(2):s=r.advance(s).state
	var paused: Dictionary=model.describe(s,r,"care_shelter")
	check(paused.progress==before.progress and paused.paid_wood==before.paid_wood and paused.stage==before.stage,"paused partial site retains work and payment")
	check(paused.work==0 and paused.crew==0 and paused.cause=="paused","paused site has no false activity")
	var wood: int=s.wood;s=cmd(s,{"kind":"cancel","id":"care_shelter"})
	check(s.wood==wood+paused.refund_wood,"cancellation uses exact unused fraction")
	check(r.command(s,{"kind":"cancel","id":"care_shelter"}).has("error"),"no duplicate refund")
	# Approach wear and waterside attempted taking preserve active AND paused sites.
	for incident in ["approach_01","stores_01"]:
		s=preload("res://tools/incident_driver.gd").initial(r)
		s=cmd(s,{"kind":"asset_principle","id":"reserve","value":1})
		s=cmd(s,{"kind":"living_order","id":"prepare","value":1})
		for i in range(65):
			var e: Dictionary=r.incidents.current(s)
			if not e.is_empty() and e.id==incident and int(s.turn)==int(e.due)-2:break
			if not e.is_empty() and not e.outcome.is_empty() and e.recovered<0:
				var repair: String=r.incidents.specs[e.id].repair
				if not r.land.committed(s,repair,r):s=cmd(s,{"kind":"commission","id":repair})
			s=r.advance(s).state
		var e: Dictionary=r.incidents.current(s)
		check(e.id==incident and int(s.turn)==int(e.due)-2,"normal-stock incident boundary "+incident)
		for id in ["care_shelter","council_ground"]:s=cmd(s,{"kind":"commission","id":id});s=staffing(s,id,1)
		s=r.advance(s).state;s=staffing(s,"council_ground",1,true)
		var original: Dictionary=s.duplicate(true)
		check(Saves.write(path,s,r) and Saves.read(path,r)==s,"save before incident retains both sites")
		var loaded: Dictionary=Saves.read(path,r)
		var forecast: Dictionary=r.forecast(s)
		s=r.advance(s).state;loaded=r.advance(loaded).state
		check(s==loaded,"incident replay is deterministic")
		check(not r.incidents.current(s).outcome.is_empty(),"incident actually resolves "+incident)
		for id in ["care_shelter","council_ground"]:
			var a: Dictionary=model.describe(original,r,id);var b: Dictionary=model.describe(s,r,id)
			check(b.queued and b.paid_wood==a.paid_wood and b.paid_blanks==a.paid_blanks,"incident preserves site identity and commitments "+id)
			check(b.progress==a.progress+forecast.assets.projects[id].work,"only ordinary seasonal work changes progress "+id)
			check(a.affected==b.affected,"incident cannot relocate project")
		check(Saves.write(path,s,r) and Saves.read(path,r)==s,"save after incident retains both sites")
	# Authority and all wrappers remain at the existing command boundary.
	s=cmd(s,{"kind":"role","role":"watch"})
	check(r.command(s,{"kind":"cancel","id":"care_shelter"}).get("error")=="authority","site governance cannot bypass office")
	var old: Dictionary=r.new_state();var old_copy: String=JSON.stringify(old)
	for id in r.projects:model.describe(old,r,id)
	check(JSON.stringify(old)==old_copy,"legacy inspection adopts no chapters")
	old=cmd(old,{"kind":"commission","id":"care_shelter"})
	old=cmd(old,{"kind":"plan","plan":r.suggested_plan(old)})
	var manual: Dictionary=model.describe(old,r,"care_shelter")
	check(manual.work>0 and manual.work==mini(manual.remaining,r.forecast(old).work),"legacy plan reports actual manual seasonal work")
	check(manual.progress+manual.work==model.describe(r.advance(old).state,r,"care_shelter").progress,"legacy forecast matches next saved work")
	s=preload("res://tools/living_driver.gd").initial(r)
	check(model.describe(s,r,"land_outer_west").refusal=="prerequisite","missing earlier connection is an actual prerequisite")
	s=cmd(s,{"kind":"commission","id":"land_outer_access"})
	for i in range(10):
		if r.has_project(s,"land_outer_access"):break
		s=r.advance(s).state
	s=cmd(s,{"kind":"commission","id":"land_outer_west"})
	s=cmd(s,{"kind":"land_access","enabled":false})
	check(model.describe(s,r,"land_outer_west").cause=="access_disabled","blocked site names disabled upkeep instead of generic warning")
	s=staffing(s,"land_outer_west",0)
	check(model.describe(s,r,"land_outer_west").cause=="crew","zero crew is distinguished from unavailable adults")
	DirAccess.remove_absolute(path)
	app.queue_free();await process_frame
	print("CONSTRUCTION CHECKS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
