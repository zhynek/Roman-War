extends SceneTree
const Rules=preload("res://src/core/settlement_rules.gd")
const Saves=preload("res://src/campaign_save.gd")
const Driver=preload("res://tools/land_driver.gd")
const View=preload("res://src/campaign_view.gd")
var checks: int=0
var failures: int=0
var rules
func _initialize() -> void:call_deferred("run")
func read(id: String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://data/"+id+".json"))
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func command(s: Dictionary,a: Dictionary) -> Dictionary:
	var response: Dictionary=rules.command(s,a)
	check(response.has("state"),"accepted "+JSON.stringify(a)+" "+str(response.get("error","")))
	return response.get("state",s)
func run() -> void:
	rules=Rules.new(read("governance"),read("balance"),read("neighbors"),read("households"),read("assets"),read("land"))
	var old=Rules.new(read("governance"),read("balance"),read("neighbors"),read("households"),read("assets"))
	var legacy: Dictionary=preload("res://tools/asset_driver.gd").at_season(old,10)
	check(rules.forecast(legacy)==old.forecast(legacy),"inactive new semantics preserve old forecast")
	var path: String="/tmp/yenikapi-land-"+str(OS.get_process_id())+".json"
	var older: Dictionary=legacy.duplicate(true);older.erase("land")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"format":"yenikapi_seasons","version":4,"state":older}))
	check(Saves.read(path,rules)==legacy,"wrapper 4 gains only inactive land")
	var adopted: Dictionary=command(legacy,{"kind":"land_begin"})
	for key in ["queue","completed","food","wood","citizens","households","contacts","leaders"]:check(adopted[key]==legacy[key],"adoption retains "+key)
	check(View.snapshot(read("settlement"),adopted,rules)==View.snapshot(read("settlement"),legacy,old),"adoption does not relocate fixed fabric")
	var s: Dictionary=Driver.initial(rules)
	check(rules.validate_state(s),"initial spatial state valid")
	check(s.food==100 and s.wood==30 and s.turn==0,"no adoption grants")
	check(rules.command(s,{"kind":"commission","id":"north_home"}).get("error") in ["prerequisite","land_choice"],"new mode requires deliberate spatial choice")
	check(rules.command(s,{"kind":"commission","id":"land_outer_west"}).get("error")=="prerequisite","outer home requires access project")
	var watched: Dictionary=command(s,{"kind":"role","role":"watch"})
	check(rules.command(watched,{"kind":"commission","id":"land_court_home"}).get("error")=="authority","watch cannot commission civic land")
	s=command(s,{"kind":"commission","id":"land_provisioning"})
	check(rules.land.totals(s,rules).food==-8,"staging closes productive ground")
	check(rules.command(s,{"kind":"commission","id":"land_cultivate"}).get("error")=="land_conflict","incompatible use blocked")
	s=command(s,{"kind":"asset_project","id":"land_provisioning","priority":1,"crew":8,"paused":true})
	var f: Dictionary=rules.forecast(s)
	check(f.assets.projects.land_provisioning.work==0,"paused work preserved without crew")
	var canceled: Dictionary=command(s,{"kind":"cancel","id":"land_provisioning"})
	check(canceled.wood==30 and rules.land.totals(canceled,rules).food==0,"unused staging releases ground and exact unused timber")
	s=command(canceled,{"kind":"commission","id":"land_court_home"})
	check(rules.command(s,{"kind":"commission","id":"land_outer_west"}).has("error"),"alternate household cannot be doubled")
	s=command(s,{"kind":"commission","id":"land_adapt_workroom"})
	for id in ["land_court_home","land_adapt_workroom"]:s=command(s,{"kind":"asset_project","id":id,"priority":1,"crew":8,"paused":false})
	f=rules.forecast(s)
	var crews: int=0
	for value in f.assets.projects.values():crews+=int(value.crew)
	check(crews<=rules.land.totals(s,rules).work,"competing crews share actual working ground")
	var seen: Array=[]
	for task in rules.assignments(s,f.plan):
		check(task.id not in seen and rules.person_by_id(s,task.id).age>=rules.balance.adult_age,"exclusive adult allocation")
		seen.append(task.id)
	check(seen.size()==rules.people(s,true).size(),"finite adult pool fully allocated")
	var snapshot: String=JSON.stringify(s)
	for site in rules.land.content.sites:rules.quote(s,{"kind":"land_inspect","id":site.id})
	check(JSON.stringify(s)==snapshot,"land comparison is pure")
	var strategies: Array=[]
	for compact in [true,false]:
		s=Driver.initial(rules)
		var replay: Dictionary=s.duplicate(true)
		var reached: int=-1
		for season in range(80):
			s=Driver.orders(rules,s,compact)
			replay=Driver.orders(rules,replay,compact)
			f=rules.forecast(s)
			var wood_before: int=s.wood
			s=rules.advance(s).state;replay=rules.advance(rules.canonical(JSON.parse_string(JSON.stringify(replay)))).state
			check(s==replay,"deterministic seasonal replay "+str(compact)+" "+str(season))
			check(s.report==f and s.food==f.food and s.wood==wood_before+int(f.wood)-int(f.assets.repair_cost)-int(f.assets.access_cost),"forecast matches finite stores "+str(season))
			check(rules.validate_state(s),"valid spatial save "+str(season))
			check(f.covered,"sustainable strategy feeds everyone "+str(compact)+" "+str(season))
			if s.phase=="town" and reached<0:reached=s.turn
		check(reached>0 and s.phase=="town","strategy reaches and sustains original town milestone")
		check(rules.capacity(s)==48 and rules.people(s).size()==48,"two new occupied households")
		check(Saves.write(path,s,rules) and Saves.read(path,rules)==s,"wrapper 5 exact save")
		check(JSON.parse_string(FileAccess.get_file_as_string(path)).version==5 and Saves.read(path,old).is_empty(),"older rules reject active land semantics")
		strategies.append(s)
		print("LAND STRATEGY ","compact" if compact else "outward"," town ",reached," season ",s.turn," people ",rules.people(s).size()," food ",s.food," timber ",s.wood," land ",rules.land.totals(s,rules))
	check(View.snapshot(read("settlement"),strategies[0],rules)!=View.snapshot(read("settlement"),strategies[1],rules),"strategies leave different visible fabric")
	check(strategies[0].wood!=strategies[1].wood and rules.land.totals(strategies[0],rules).work!=rules.land.totals(strategies[1],rules).work,"strategies leave different sustainable obligations")
	s=command(strategies[1],{"kind":"land_access","enabled":false})
	f=rules.forecast(s)
	check(not f.land.access and f.assets.access_cost==0,"unsupported access does not spend")
	check(f.factors.wellbeing[-1].value==-8 and rules.capacity(s)==48,"occupied homes retained with named access penalty")
	s=command(s,{"kind":"land_access","enabled":true})
	check(rules.forecast(s).land.access,"legitimate upkeep restores operation")
	# Poor but legal irreversible conversion: recover with food priorities and
	# the retained cultivation extension, not fabricated supplies or demolition.
	s=Driver.initial(rules);s=command(s,{"kind":"commission","id":"land_provisioning"})
	for i in range(3):s=rules.advance(s).state
	check(rules.has_project(s,"land_provisioning"),"poor decision completes normally")
	s=command(s,{"kind":"asset_principle","id":"reserve","value":2})
	s=command(s,{"kind":"commission","id":"field_extension"})
	for i in range(16):s=rules.advance(s).state
	check(s.food>=rules.people(s).size()*2 and s.wellbeing>=60 and rules.has_project(s,"field_extension"),"recover poor conversion with real cultivation and reserves")
	check(rules.land.totals(s,rules).food==-8,"recovery retains lasting conversion cost")
	var broken: Dictionary=strategies[0].duplicate(true);broken.completed.append({"id":"land_outer_west","turn":1});broken.plan=rules.effective_plan(broken)
	check(not rules.validate_state(broken),"save refuses incompatible double household choice")
	# Named leaders retain institutions and the author's saved decision record.
	s=Driver.initial(rules);s=command(s,{"kind":"commission","id":"land_adapt_workroom"})
	s=rules.advance(s).state
	var paid: Dictionary=s.duplicate(true)
	var replacement: String=""
	for person in rules.people(s,true):
		if p_eligible(person,s):replacement=person.id;break
	s=command(s,{"kind":"appoint","role":"steward","id":replacement})
	check(s.queue==paid.queue and s.wood==paid.wood and s.land==paid.land and s.assets.initiatives==paid.assets.initiatives,"succession retains spatial obligations, author and paid work")
	var progress: int=s.queue[0].progress
	var refund: int=int(rules.projects.land_adapt_workroom.wood)*(int(rules.projects.land_adapt_workroom.work)-progress)/int(rules.projects.land_adapt_workroom.work)
	s=command(s,{"kind":"cancel","id":"land_adapt_workroom"})
	check(s.wood==paid.wood+refund and not rules.has_project(s,"land_adapt_workroom"),"partial cancellation refunds only unused timber and preserves old room")
	# Missing access resources cannot be borrowed from later seasonal output.
	s=command(Driver.initial(rules),{"kind":"commission","id":"land_outer_access"})
	for i in range(8):
		if rules.has_project(s,"land_outer_access"):break
		s=rules.advance(s).state
	check(rules.has_project(s,"land_outer_access"),"access fixture completed through paid seasons")
	s=command(s,{"kind":"land_access","enabled":false})
	check(rules.command(s,{"kind":"commission","id":"land_outer_east"}).get("error")=="land_access","disabled upkeep refuses dependent commission")
	s=command(s,{"kind":"land_access","enabled":true})
	s=command(s,{"kind":"commission","id":"land_outer_west"})
	check(not s.queue.is_empty() and s.queue[0].id=="land_outer_west","dependent project exists before unsupported-work check")
	var unserved: Dictionary=s.duplicate(true);unserved.wood=0;unserved.land.access_enabled=true;unserved.plan=rules.effective_plan(unserved)
	f=rules.forecast(unserved)
	check(f.assets.access_cost==0 and not f.land.access,"zero opening timber cannot service access")
	for item in unserved.queue:
		if rules.land.proposals.get(item.id,{}).get("requires_access",false):check(f.assets.projects[item.id].work==0,"access blocks existing dependent work")
	# No invalid residential removal can pass the normal land commission seam.
	var original_changes: Array=rules.projects.land_adapt_workroom.changes
	rules.projects.land_adapt_workroom.changes=[{"kind":"removed","before":["yk_house_01"],"after":[]}]
	check(rules.command(Driver.initial(rules),{"kind":"commission","id":"land_adapt_workroom"}).get("error")=="land_accommodation","occupied home needs an accommodation workflow")
	rules.projects.land_adapt_workroom.changes=original_changes
	# A neighbor party competes with spatial construction and home upkeep.
	s=strategies[1].duplicate(true);s=command(s,{"kind":"commission","id":"exchange_place"})
	for i in range(3):s=rules.advance(s).state
	s=command(s,{"kind":"neighbor_begin"})
	s=command(s,{"kind":"neighbor_send","neighbor":"oakrise","mission":"trade"})
	f=rules.forecast(s);seen.clear();var travel: int=0
	for task in rules.assignments(s,f.plan):
		check(task.id not in seen,"neighbor and home assignments exclusive");seen.append(task.id)
		if task.job=="travel":travel+=1
	check(travel==3 and f.crew.carriers==2 and f.crew.escorts==1,"carriers and escorts unavailable to home initiatives")
	check(Saves.write(path,s,rules) and Saves.read(path,rules)==s,"land, household and in-flight contacts resume together")
	DirAccess.remove_absolute(path)
	print("LAND CHECKS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func p_eligible(person: Dictionary,state: Dictionary) -> bool:
	return rules.eligible(person) and person.id!=state.leaders.steward.id and person.id!=state.leaders.watch.id
