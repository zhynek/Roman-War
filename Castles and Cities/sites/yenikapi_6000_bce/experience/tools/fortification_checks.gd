extends SceneTree
## Paid defense projects, persisted plans, actual collision and ordinary access.
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const Land=preload("res://tools/land_driver.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Nav=preload("res://src/core/defense_navigation.gd")
const Saves=preload("res://src/campaign_save.gd")
var r
var app
var checks: int=0
var failures: int=0
var save_path: String="/tmp/village-fortification-check-"+str(OS.get_process_id())+".json"
const PROJECTS=["warfare_store_screen","warfare_landing_screen"]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var response: Dictionary=r.command(s,a)
	check(response.has("state"),str(a)+" "+str(response.get("error","")))
	return response.get("state",s)
func queued(s: Dictionary,id: String) -> Dictionary:
	for item in s.queue:
		if item.id==id:return item
	return {}
func staffing(s: Dictionary,id: String,crew: int=1,paused: bool=false) -> Dictionary:
	return cmd(s,{"kind":"asset_project","id":id,"priority":1,"crew":crew,"paused":paused})
func season(s: Dictionary) -> Dictionary:
	var f: Dictionary=r.forecast(s)
	var result: Dictionary=r.advance(s)
	check(result.has("state"),"ordinary paid-work season")
	if not result.has("state"):return s
	var n: Dictionary=result.state
	check(n.report==f,"forecast and resolved allocation agree")
	check(r.validate_state(n),"resolved village validates")
	return n
func affordable(s: Dictionary,id: String) -> Dictionary:
	for i in range(40):
		if r.quote(s,{"kind":"commission","id":id}).has("state"):return s
		s=season(s)
	check(false,"ordinary economy can afford "+id)
	return s
func finish_projects(s: Dictionary) -> Dictionary:
	for i in range(50):
		var done: bool=true
		for id in PROJECTS:
			if r.has_project(s,id):continue
			done=false
			if queued(s,id).is_empty():
				if r.quote(s,{"kind":"commission","id":id}).has("state"):
					s=cmd(s,{"kind":"commission","id":id});s=staffing(s,id,2)
		if done:return s
		s=season(s)
	check(false,"finite public crews complete both defense screens")
	return s
func show(s: Dictionary) -> Dictionary:
	app.campaign.state=s;app.show_campaign(s,r)
	return Adapter.capture(app.world,r.defense)
func civilian_access(s: Dictionary,label: String) -> void:
	var life=app.campaign_view.life
	check(life.unreachable.is_empty(),label+" all residents have planned routes")
	var ids: Dictionary={}
	for routine in life.routines:
		check(not ids.has(routine.id),label+" unique resident "+routine.id);ids[routine.id]=true
		check(not routine.route.is_empty(),label+" actual route "+routine.id)
		for i in range(1,routine.route.size()):
			var from: Vector3=routine.route[i-1]+Vector3.UP*1.68;var to: Vector3=routine.route[i]+Vector3.UP*1.68
			var reached: Vector3=app.world.walk(from,to-from)
			check(Vector2(reached.x-to.x,reached.z-to.z).length()<.1,label+" continuous resident route "+routine.id)
	check(ids.size()==r.people(s).size(),label+" every living resident represented")
	for building in app.world.buildings:
		var from: Vector3=app.world.building_position(building,Vector3(0,1.68,float(building.size[1])*.5+1.4))
		var to: Vector3=app.world.building_position(building,Vector3(0,1.68,float(building.size[1])*.5-.6))
		var reached: Vector3=app.world.walk(from,to-from)
		check(Vector2(reached.x-to.x,reached.z-to.z).length()<.1,label+" ordinary doorway "+building.id)
	for path in app.world.data.objects:
		if path.kind!="path":continue
		var points: Array=path.points
		var walker:=Vector3(points[0][0],0,points[0][1]);walker.y=app.world.floor_height(walker.x,walker.z)+1.68
		var passable: bool=true
		for i in range(points.size()-1):
			var a:=Vector2(points[i][0],points[i][1]);var b:=Vector2(points[i+1][0],points[i+1][1])
			var prior:=Vector2(points[maxi(0,i-1)][0],points[maxi(0,i-1)][1]);var after:=Vector2(points[mini(points.size()-1,i+2)][0],points[mini(points.size()-1,i+2)][1])
			for j in range(1,41):
				var point: Vector2=a.cubic_interpolate(b,prior,after,float(j)/40)
				walker=app.world.walk(walker,Vector3(point.x-walker.x,0,point.y-walker.z))
				if Vector2(walker.x-point.x,walker.z-point.y).length()>.1:passable=false
		check(passable,label+" authored ordinary path "+path.id)
func tactical_access(nav: Dictionary,label: String) -> void:
	check(Nav.valid(nav,r),label+" captured collision grid valid")
	var positions: Dictionary=r.warfare.forts.plan_locations(nav)
	for id in positions:
		check(Nav.clear(nav,positions[id]),label+" plan position clear "+id)
		check(not Nav.route(nav,positions[id],nav.places.refuge).is_empty(),label+" plan position reaches refuge "+id)
	for pair in [["store_gate","store_stand"],["landing_gate","landing_stand"],["north","stores"],["landing","stores"]]:
		var route: Array=Nav.route(nav,positions[pair[0]],positions[pair[1]])
		check(not route.is_empty(),label+" controlled approach remains open "+str(pair))
		var from: Array=positions[pair[0]]
		for at in route:
			check(Nav.line(nav,from,at),label+" route stays collision-clear "+str(pair));from=at
func screen_collision(nav: Dictionary,label: String) -> void:
	for id in PROJECTS:
		for change in r.projects[id].changes:
			for record in change.after:
				check(app.world.object_nodes.has(record.id),label+" original procedural screen exists "+record.id)
				var from:=Vector2(record.points[0][0],record.points[0][1]);var to:=Vector2(record.points[-1][0],record.points[-1][1])
				var center: Vector2=(from+to)*.5
				check(app.world.blocked(Vector3(center.x,0,center.y)),label+" completed screen blocks actual walking "+record.id)
				check(not Nav.clear(nav,[roundi(center.x*100),roundi(center.y*100)]),label+" completed screen blocks tactical grid "+record.id)
	for location in r.warfare.forts.content.positions:
		if location.id not in ["store_gate","landing_gate"]:continue
		var point:=Vector3(location.at[0],0,location.at[1]);point.y=app.world.floor_height(point.x,point.z)+1.68
		check(not app.world.blocked(point),label+" authored entrance remains clear "+location.id)
		check(Nav.clear(nav,[roundi(point.x*100),roundi(point.z*100)]),label+" tactical entrance remains at authored position "+location.id)
		var from: Vector3=point+Vector3(-2,0,0);var to: Vector3=point+Vector3(2,0,0)
		var reached: Vector3=app.world.walk(from,to-from)
		check(Vector2(reached.x-to.x,reached.z-to.z).length()<.1,label+" citizen crosses open entrance "+location.id)
func battle(s: Dictionary,nav: Dictionary) -> Dictionary:
	var mobilized: Dictionary=r.command(s,{"kind":"defense_begin","nav":nav})
	check(mobilized.has("state"),"paid actual watch mobilization")
	return mobilized.state.defense.battle if mobilized.has("state") else {}
func finite_work(s: Dictionary,label: String) -> void:
	var f: Dictionary=r.forecast(s);var ids: Dictionary={};var builders: int=0
	for task in r.assignments(s,f.plan):
		check(not ids.has(task.id),label+" adult assigned once "+task.id);ids[task.id]=true
		check(int(r.person_by_id(s,task.id).age)>=int(r.balance.adult_age),label+" adult-only work "+task.id)
		if task.job=="building":builders+=1
	check(ids.size()==r.people(s,true).size(),label+" finite home workforce")
	var project_crews: int=0
	for allocation in f.assets.projects.values():project_crews+=int(allocation.crew)
	check(project_crews<=builders and project_crews<=int(r.land.totals(s,r).work),label+" paid projects share finite work places")
	check(int(f.plan.food)>0 and int(f.plan.care)>0,label+" ordinary food and care retain workers")
func run() -> void:
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	r=app.campaign.rules;app.campaign.save_path=save_path
	var fixture: String="res://tools/fixtures/lifecycle-0.11-paid.json"
	check(FileAccess.get_sha256(fixture)=="b0e0af7a47ffe5febe15d189bce0d4ffcb988180112dbf0412da293d607ae872","frozen paid fixture bytes unchanged")
	check(r.lifecycle.definition_hash=="a4694114cc755d8f5a2113daabf71370a8b85824acc1317dbe973c3555f1fe35","legacy lifecycle semantics retained")
	var legacy: Dictionary=Saves.read(fixture,r)
	check(not legacy.is_empty() and legacy.warfare.is_empty(),"older paid save reads with inactive warfare")
	if not legacy.is_empty():
		var adopted_legacy:=cmd(legacy,{"kind":"warfare_begin"})
		for key in legacy:
			if key not in ["warfare","history"]:check(adopted_legacy[key]==legacy[key],"old paid adoption retains "+key)
		check(Saves.write(save_path,adopted_legacy,r) and Saves.read(save_path,r)==adopted_legacy,"original paused paid contract survives wrapper10 adoption")
	var base: Dictionary=Living.at_season(r,12,true)
	check(r.command(base,{"kind":"commission","id":PROJECTS[0]}).has("error"),"unadopted project refused")
	var s:=cmd(base,{"kind":"warfare_begin"})
	for key in ["wood","food","turn","citizens","completed","queue","contacts","households","lifecycle"]:check(s[key]==base[key],"adoption does not grant or replace "+key)
	var bare_nav: Dictionary=show(s);var bare_battle: Dictionary=battle(s,bare_nav)
	check(not bare_battle.is_empty() and bare_battle.tactics.defenses.is_empty(),"adoption provides no free fortifications")
	var forged: Dictionary=r.command(s,{"kind":"defense_begin","nav":bare_nav}).state
	forged.defense.battle.tactics.defenses.append({"at":bare_nav.places.stores.duplicate(),"radius":350,"protection":80,"side":"watch"})
	check(not r.validate_state(forged),"save rejects cover unsupported by paid completed defenses")
	forged=s.duplicate(true);forged.warfare.plans.assembly="north"
	check(not r.validate_state(forged),"save rejects assembly outside allowed deployment")
	s=affordable(s,PROJECTS[0]);var wood: int=int(s.wood);var before: Dictionary=s.duplicate(true)
	s=cmd(s,{"kind":"commission","id":PROJECTS[0]})
	check(int(s.wood)==wood-int(r.projects[PROJECTS[0]].wood),"full real material price paid at commission")
	check(queued(s,PROJECTS[0]).progress==0 and not r.has_project(s,PROJECTS[0]),"payment does not complete structure")
	check(s.completed==before.completed and s.citizens==before.citizens,"commission preserves existing fabric and residents")
	s=staffing(s,PROJECTS[0],0);finite_work(s,"zero-crew site")
	var waiting:=season(s)
	check(queued(waiting,PROJECTS[0]).progress==0,"zero finite labor means no construction")
	check(Saves.write(save_path,waiting,r) and Saves.read(save_path,r)==waiting,"paid zero-crew site roundtrips")
	wood=int(waiting.wood);var cancelled:=cmd(waiting,{"kind":"cancel","id":PROJECTS[0]})
	check(int(cancelled.wood)==wood+int(r.projects[PROJECTS[0]].wood),"unworked cancellation exact refund")
	check(cancelled.assets.initiatives.has(PROJECTS[0]),"cancelled paid responsibility remains in history")
	check(r.command(cancelled,{"kind":"cancel","id":PROJECTS[0]}).has("error"),"cancel twice refuses duplicate refund")
	s=cmd(cancelled,{"kind":"commission","id":PROJECTS[0]});s=staffing(s,PROJECTS[0],1)
	var f: Dictionary=r.forecast(s);var expected_work: int=int(f.assets.projects[PROJECTS[0]].work)
	finite_work(s,"paid defense labor")
	s=season(s)
	check(not queued(s,PROJECTS[0]).is_empty() and int(queued(s,PROJECTS[0]).progress)==expected_work,"one seasonal crew applies exact forecast work")
	var progress: int=int(queued(s,PROJECTS[0]).progress)
	s=staffing(s,PROJECTS[0],1,true);s=season(s)
	check(int(queued(s,PROJECTS[0]).progress)==progress,"paused defense retains paid progress")
	var partial_nav: Dictionary=show(s);var partial_battle: Dictionary=battle(s,partial_nav)
	check(not partial_battle.is_empty() and partial_battle.tactics.defenses.is_empty(),"unfinished paid defense provides no tactical cover")
	civilian_access(s,"paused screen work")
	check(Saves.write(save_path,s,r) and Saves.read(save_path,r)==s,"partly built paused project save exact")
	wood=int(s.wood);var partial_refund: int=int(r.projects[PROJECTS[0]].wood)*(int(r.projects[PROJECTS[0]].work)-progress)/int(r.projects[PROJECTS[0]].work)
	var refund:=cmd(s,{"kind":"cancel","id":PROJECTS[0]})
	check(int(refund.wood)==wood+partial_refund,"partial cancellation refunds only unspent material")
	s=staffing(s,PROJECTS[0],2,false);s=finish_projects(s)
	check(r.has_project(s,PROJECTS[0]) and r.has_project(s,PROJECTS[1]),"both paid projects completed")
	check(r.command(s,{"kind":"commission","id":PROJECTS[0]}).has("error"),"completed defense cannot be bought twice")
	var concurrent:=cmd(base,{"kind":"warfare_begin"})
	concurrent=affordable(concurrent,"care_shelter");concurrent=cmd(concurrent,{"kind":"commission","id":"care_shelter"});concurrent=staffing(concurrent,"care_shelter",1)
	concurrent=season(concurrent);concurrent=staffing(concurrent,"care_shelter",1,true)
	var retained_contract: Dictionary=queued(concurrent,"care_shelter").duplicate(true)
	var retained_author: Dictionary=concurrent.assets.initiatives.care_shelter.duplicate(true)
	concurrent=finish_projects(concurrent)
	check(queued(concurrent,"care_shelter")==retained_contract and concurrent.assets.initiatives.care_shelter==retained_author,"defenses preserve unrelated paused paid work and its responsible author")
	check(Saves.write(save_path,concurrent,r) and Saves.read(save_path,r)==concurrent,"completed defenses coexist with original paid paused project")
	var finished_nav: Dictionary=show(s);tactical_access(finished_nav,"prepared completed defenses");civilian_access(s,"prepared completed defenses");screen_collision(finished_nav,"prepared completed defenses")
	check(finished_nav.signature!=bare_nav.signature,"completed screens change actual navigation")
	var prepared_battle: Dictionary=battle(s,finished_nav)
	check(not prepared_battle.is_empty() and prepared_battle.tactics.defenses.size()==2,"maintained paid screens supply actual defended positions")
	for slot in s.warfare.plans:
		var place: String="store_stand" if slot in ["assembly","important"] else "landing_stand" if slot=="approach" else "refuge"
		s=cmd(s,{"kind":"warfare_plan","slot":slot,"place":place})
		check(s.warfare.plans[slot]==place,"persisted defense plan "+slot)
	before=s.duplicate(true)
	check(r.command(s,{"kind":"warfare_plan","slot":"unknown","place":"refuge"}).has("error") and s==before,"unknown plan slot rejected atomically")
	check(r.command(s,{"kind":"warfare_plan","slot":"assembly","place":"unknown"}).has("error") and s==before,"unknown plan location rejected atomically")
	check(Saves.write(save_path,s,r) and Saves.read(save_path,r)==s,"completed paid defenses and plans resume exactly")
	# Neglect and maintenance use the ordinary watch condition/repair allocator.
	var neglected:=cmd(s,{"kind":"asset_maintenance","id":"watch","enabled":false})
	for i in range(60):
		if int(neglected.assets.conditions.watch)<int(r.assets.balance.condition_threshold):break
		neglected=season(neglected)
	check(int(neglected.assets.conditions.watch)<int(r.assets.balance.condition_threshold),"ordinary neglected condition crosses service threshold")
	var neglected_nav: Dictionary=show(neglected);var neglected_battle: Dictionary=battle(neglected,neglected_nav)
	check(not neglected_battle.is_empty() and neglected_battle.tactics.defenses.is_empty(),"neglected screens lose protection")
	check(r.has_project(neglected,PROJECTS[0]) and r.has_project(neglected,PROJECTS[1]),"condition loss preserves paid completed ledger")
	civilian_access(neglected,"neglected completed defenses");tactical_access(neglected_nav,"neglected completed defenses");screen_collision(neglected_nav,"neglected completed defenses")
	neglected=cmd(neglected,{"kind":"asset_maintenance","id":"watch","enabled":true})
	var repaired: bool=false
	for i in range(40):
		var forecast: Dictionary=r.forecast(neglected)
		if forecast.assets.repair=="watch":
			check(int(forecast.assets.repair_cost)>0 and int(forecast.assets.repair_workers)>0,"watch restoration spends real timber and finite labor")
			repaired=true
		neglected=season(neglected)
		if int(neglected.assets.conditions.watch)>=int(r.assets.balance.condition_threshold):break
	check(repaired and int(neglected.assets.conditions.watch)>=int(r.assets.balance.condition_threshold),"ordinary maintenance restores condition")
	var repaired_nav: Dictionary=show(neglected);var repaired_battle: Dictionary=battle(neglected,repaired_nav)
	check(not repaired_battle.is_empty() and repaired_battle.tactics.defenses.size()==2,"repaired completed defenses regain protection")
	check(Saves.write(save_path,neglected,r) and Saves.read(save_path,r)==neglected,"condition recovery save exact")
	# The actual compact and outward layouts retain all public walking routes.
	for compact in [true,false]:
		var developed: Dictionary=Land.at_season(r,compact,32)
		developed=cmd(developed,{"kind":"living_begin"});developed=cmd(developed,{"kind":"warfare_begin"});developed=finish_projects(developed)
		var label: String="compact" if compact else "outward"
		var nav: Dictionary=show(developed);civilian_access(developed,label+" completed defenses");tactical_access(nav,label+" completed defenses");screen_collision(nav,label+" completed defenses")
		check(Saves.write(save_path,developed,r) and Saves.read(save_path,r)==developed,label+" defensive village save exact")
	check(FileAccess.get_sha256(fixture)=="b0e0af7a47ffe5febe15d189bce0d4ffcb988180112dbf0412da293d607ae872","legacy paid fixture remains byte-identical")
	print("FORTIFICATION CHECKS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
