extends SceneTree
const Rules=preload("res://src/core/settlement_rules.gd")
const Saves=preload("res://src/campaign_save.gd")
const Driver=preload("res://tools/asset_driver.gd")
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
	rules=Rules.new(read("governance"),read("balance"),read("neighbors"),read("households"),read("assets"))
	var initial: Dictionary=rules.new_state()
	var legacy=Rules.new(read("governance"),read("balance"),read("neighbors"),read("households"))
	check(rules.forecast(initial)==legacy.forecast(legacy.new_state()),"optional mode does not alter legacy forecast")
	var path: String="/tmp/yenikapi-assets-"+str(OS.get_process_id())+".json"
	var old: Dictionary=initial.duplicate(true);old.erase("assets")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"format":"yenikapi_seasons","version":1,"state":old}))
	check(Saves.read(path,rules)==initial,"old manual save gains inactive assets only")
	var s: Dictionary=command(initial,{"kind":"asset_begin"})
	check(s.food==initial.food and s.wood==initial.wood and s.turn==initial.turn,"activation grants no resources or seasons")
	check(s.assets.manual_plan==initial.plan,"explicit adoption preserves manual strategy")
	check(rules.households.stage(s)=="settled","new governance starts with ordinary life")
	check(rules.validate_state(s),"active initial state validates")
	check(rules.command(s,{"kind":"plan","plan":s.plan}).get("error")=="asset_managed","no competing manual allocator")
	var snapshot: String=JSON.stringify(s)
	for p in rules.assets.content.principles:
		for role in ["steward","watch"]:
			var office: Dictionary=rules.command(s,{"kind":"role","role":role}).state
			var response: Dictionary=rules.command(office,{"kind":"asset_principle","id":p.id,"value":1})
			check(response.has("state")== (role==p.role),"principle authority "+p.id+role)
	check(JSON.stringify(s)==snapshot,"quotes and rejected commands pure")
	for id in ["field_extension","shared_store"]:s=command(s,{"kind":"commission","id":id})
	var committed: int=s.wood
	check(committed==2,"one construction ledger commits 28 timber")
	s=command(s,{"kind":"asset_project","id":"field_extension","priority":1,"crew":3,"paused":true})
	var f: Dictionary=rules.forecast(s)
	check(f.assets.projects.field_extension.work==0,"paused construction has no work")
	var paused: Dictionary=rules.advance(s).state
	check(paused.queue[0].progress==0 and paused.queue[1].progress>0,"one paused initiative does not block another")
	s=command(paused,{"kind":"cancel","id":"field_extension"})
	check(s.wood==paused.wood+12,"unworked cancellation returns exactly unspent materials")
	check(s.assets.initiatives.has("field_extension"),"cancelled decision retains author responsibility")
	var survivor: String=JSON.stringify(s.queue)
	var candidate: String=""
	for person in rules.people(s,true):
		if rules.eligible(person) and person.id not in [s.leaders.steward.id,s.leaders.watch.id]:candidate=person.id;break
	var before_wood: int=s.wood
	s=command(s,{"kind":"appoint","role":"steward","id":candidate})
	check(JSON.stringify(s.queue)==survivor and s.wood==before_wood,"succession retains project progress and materials")
	check(s.assets.initiatives.shared_store.author!=candidate,"commission remembers original author")
	for id in ["secure_stores","refuge","learning"]:s=command(s,{"kind":"household_order","id":id,"enabled":true})
	f=rules.forecast(s)
	var work_ids: Dictionary={}
	for task in rules.assignments(s,f.plan):
		check(not work_ids.has(task.id),"exclusive adult assignment "+task.id);work_ids[task.id]=true
		check(rules.person_by_id(s,task.id).age>=rules.balance.adult_age,"children excluded")
	check(work_ids.size()==rules.people(s,true).size(),"all adults allocated once")
	check(int(f.assets.orders.get("refuge",0))+int(f.assets.orders.get("secure_stores",0))+int(f.assets.orders.get("learning",0))<=int(f.plan.care),"care duties have disjoint crews")
	check(Saves.write(path,s,rules),"wrapper 4 write")
	check(JSON.parse_string(FileAccess.get_file_as_string(path)).version==4,"explicit wrapper version")
	check(Saves.read(path,rules)==s,"exact active save resume")
	check(Saves.read(path,legacy).is_empty(),"older rules refuse active extension")
	for key in ["reserve","watch","tutorial"]:
		var broken: Dictionary=s.duplicate(true);broken.assets[key]=-2
		check(not rules.validate_state(broken),"malformed extension rejected "+key)
	var broken: Dictionary=s.duplicate(true);broken.assets.initiatives.shared_store.author="not_a_person"
	check(not rules.validate_state(broken),"unknown author refused")
	var poor: Dictionary=rules.command(initial,{"kind":"asset_begin"}).state
	poor.food=0;poor.wood=0
	for id in poor.assets.conditions:poor.assets.conditions[id]=30
	poor.plan=rules.effective_plan(poor)
	f=rules.forecast(poor)
	check(f.assets.repair_cost==0,"unfunded repairs do not spend future timber")
	check(rules.storage(poor)<rules.storage(initial),"neglected stores reduce capacity")
	check(rules.assets.food_penalty(poor)>0,"neglected productive access reduces food")
	for i in range(24):poor=rules.advance(poor).state
	check(poor.food>0 and poor.assets.conditions.stores>30,"can recover from empty reserves and neglect")
	var competition: Dictionary=rules.command(initial,{"kind":"asset_begin"}).state
	competition.food=30;competition.wood=200
	for id in ["field_extension","shared_store","care_shelter"]:
		competition=command(competition,{"kind":"commission","id":id})
		competition=command(competition,{"kind":"asset_project","id":id,"priority":1,"crew":8,"paused":false})
	var cautious: Dictionary=command(competition,{"kind":"asset_principle","id":"reserve","value":2})
	var expansion: Dictionary=command(competition,{"kind":"asset_principle","id":"reserve","value":0})
	check(rules.forecast(cautious).gathered>rules.forecast(expansion).gathered,"reserve principle trades construction for food")
	check(rules.forecast(cautious).work<rules.forecast(expansion).work,"expansion principle creates a distinct viable allocation")
	var shortage: Dictionary=rules.command(initial,{"kind":"asset_begin"}).state;shortage.turn=3;shortage.food=0
	for id in shortage.assets.conditions:shortage.assets.conditions[id]=0
	check(rules.forecast(shortage).unfed>0,"reserve objective cannot guarantee winter food")
	var live: Dictionary=initial
	var town: bool=false
	for turn in range(100):
		live=Driver.orders(rules,live)
		check(rules.validate_state(live),"valid ordered season "+str(turn))
		var replay: Dictionary=rules.canonical(JSON.parse_string(JSON.stringify(live)))
		f=rules.forecast(live)
		var wood: int=live.wood
		var next: Dictionary=rules.advance(live).state
		check(next==rules.advance(replay).state,"deterministic replay "+str(turn))
		check(next.food==f.food and next.wood==wood+int(f.wood)-int(f.assets.repair_cost),"forecast exact finite ledgers "+str(turn))
		check(rules.validate_state(next),"valid resolved season "+str(turn))
		check(next.report==f,"actual report preserves exact forecast "+str(turn))
		if next.phase=="town":town=true
		if turn in [3,5,8,12,20,40,99]:print("ASSET SEASON ",next.turn," food ",next.food," wood ",next.wood," pop ",rules.people(next).size()," projects ",next.completed.size()," queued ",next.queue," plan ",next.plan," stage ",rules.households.stage(next))
		live=next
	check(town,"automatic governance can reach the existing town milestone")
	check(live.assets.learning_seasons>0,"recovery supports persistent learning")
	check(live.households.homes.sim_household_01.practice!=live.households.homes.sim_household_02.practice or live.households.homes.sim_household_01.practice==100,"household learning retained")
	# Contacts commit capacity within the new allocator, including during danger.
	var contact: Dictionary=preload("res://tools/neighbor_driver.gd").foundation(legacy)
	contact=command(contact,{"kind":"asset_begin"})
	contact=command(contact,{"kind":"neighbor_begin"})
	contact=command(contact,{"kind":"neighbor_send","neighbor":"oakrise","mission":"trade"})
	f=rules.forecast(contact)
	check(f.crew.carriers==2 and f.crew.escorts==1,"committed journey reduces available home duties")
	var travel: int=0
	for task in rules.assignments(contact,f.plan):
		if task.job=="travel":travel+=1
	check(travel==3,"one assignment per carrier and escort")
	check(Saves.write(path,contact,rules) and Saves.read(path,rules)==contact,"active contacts and assets resume together")
	DirAccess.remove_absolute(path)
	print("ASSET CHECKS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
