extends SceneTree
const Rules=preload("res://src/core/settlement_rules.gd")
const Saves=preload("res://src/campaign_save.gd")
const Driver=preload("res://tools/neighbor_driver.gd")
var checks:int=0
var failures:int=0
var rules
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func read(name:String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://data/"+name+".json"))
func run() -> void:
	rules=Rules.new(read("governance"),read("balance"),read("neighbors"))
	var initial:Dictionary=rules.new_state()
	check(rules.command(initial,{"kind":"neighbor_begin"}).get("error")=="contact_locked","chapter gated by town and meeting room")
	var legacy:Dictionary=initial.duplicate(true);legacy.erase("contacts")
	var path:String="/tmp/yenikapi-neighbor-check-"+str(OS.get_process_id())+".json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"format":"yenikapi_seasons","version":1,"state":legacy}))
	check(Saves.read(path,rules)==initial,"old campaign gets inactive contacts without altering any other field")
	var state:Dictionary=Driver.foundation(rules)
	check(state.town_achieved and rules.has_project(state,"exchange_place"),"meeting room can be completed normally")
	state=rules.command(state,{"kind":"neighbor_begin"}).state
	check(rules.validate_state(state),"activated contacts save valid")
	check(rules.command(state,{"kind":"neighbor_begin"}).get("error")=="contact_started","no reset of neighbors")
	var snapshot:String=JSON.stringify(state)
	var q:Dictionary=rules.neighbors.quote(state,"oakrise","trade",rules)
	check(not q.has("error") and JSON.stringify(state)==snapshot,"offers are pure")
	var sent:Dictionary=rules.command(state,{"kind":"neighbor_send","neighbor":"oakrise","mission":"trade"}).state
	check(sent.food==state.food-18 and sent.contacts.neighbors.oakrise.wood==state.contacts.neighbors.oakrise.wood-10,"both cargos reserved exactly once")
	check(rules.command(sent,{"kind":"neighbor_send","neighbor":"oakrise","mission":"trade"}).get("error")=="contact_busy","no duplicate escrow")
	check(rules.validate_state(sent),"in-flight save validates")
	var cancelled:Dictionary=rules.command(sent,{"kind":"neighbor_cancel"}).state
	check(cancelled.food==state.food and cancelled.contacts.neighbors==state.contacts.neighbors and cancelled.contacts.mission.is_empty(),"pre-departure cancellation restores both cargo stores")
	var f:Dictionary=rules.forecast(sent)
	var home:Dictionary=rules.forecast(state)
	check(f.gathered==home.gathered-2*(int(rules.balance.food_yields[int(state.turn)%4])+rules.effect(state,"food_yield")),"carriers reduce home food production")
	check(f.factors.security[1].value==home.factors.security[1].value-int(rules.balance.security_worker),"escort reduces watch contribution at home")
	var tasks:Array=rules.assignments(sent,sent.plan);var travelers:int=0;var ids:Dictionary={}
	for task in tasks:
		ids[task.id]=true
		if task.job=="travel":travelers+=1
	check(travelers==3 and ids.size()==tasks.size() and tasks.size()==rules.people(sent,true).size(),"one job per adult including committed crew")
	var paused:Dictionary=sent.duplicate(true);paused.plan.food+=paused.plan.watch;paused.plan.watch=0
	paused=rules.advance(paused).state
	check(paused.contacts.mission.remaining==2 and not paused.contacts.mission.started,"understaffed party waits without losing cargo or progressing")
	check(rules.validate_state(paused),"paused workforce plan can be saved")
	var first:Dictionary=rules.advance(sent).state
	check(first.contacts.mission.remaining==1 and first.contacts.mission.started,"two-season journey remains committed")
	check(rules.command(first,{"kind":"neighbor_cancel"}).get("error")=="contact_transit","departed party cannot teleport home")
	check(Saves.write(path,first,rules),"save in-flight mission")
	var loaded:Dictionary=Saves.read(path,rules)
	check(JSON.stringify(loaded)==JSON.stringify(first),"load preserves escrow and remaining journey")
	check(JSON.parse_string(FileAccess.get_file_as_string(path)).version==2,"active contact save uses version two wrapper")
	check(rules.advance(first)==rules.advance(loaded),"save/resume next season identical")
	var arrival:Dictionary=rules.forecast(first);var returned:Dictionary=rules.advance(first).state
	check(returned.wood==first.wood+arrival.wood and returned.food==arrival.food and returned.contacts.mission.is_empty(),"delivery credited exactly once and forecast matches")
	check(returned.contacts.neighbors.oakrise.trades==1,"community remembers completed exchange")
	for role in ["steward","watch"]:
		var office:Dictionary=rules.command(state,{"kind":"role","role":role}).state
		check(rules.command(office,{"kind":"neighbor_escort","escorts":2}).has("state")== (role=="watch"),"escort authority "+role)
		check(rules.command(office,{"kind":"neighbor_send","neighbor":"oakrise","mission":"trade"}).has("state")== (role=="steward"),"dispatch authority "+role)
	var depleted:Dictionary=state.duplicate(true);depleted.contacts.neighbors.oakrise.wood=20
	check(rules.neighbors.quote(depleted,"oakrise","trade",rules).get("error")=="contact_reserve","finite stocks protect neighbor reserves")
	depleted=state.duplicate(true);depleted.food=rules.people(state).size()
	check(rules.neighbors.quote(depleted,"oakrise","trade",rules).get("error")=="contact_stock","exchange cannot spend home food reserve")
	var unguarded:Dictionary=rules.command(state,{"kind":"neighbor_escort","escorts":0}).state
	check(rules.neighbors.quote(unguarded,"oakrise","trade",rules).loss>=q.loss,"escorts reduce deterministic allowance")
	var replay:Dictionary=state.duplicate(true)
	for turn in range(80):
		state=Driver.orders(rules,state);replay=Driver.orders(rules,replay)
		var forecast:Dictionary=rules.forecast(state)
		state=rules.advance(state).state;replay=rules.advance(replay).state
		check(state==replay,"deterministic contact season "+str(turn))
		check(state.food==forecast.food,"food arrival forecast season "+str(turn))
		check(rules.validate_state(state),"valid contact season "+str(turn))
		if turn==10:
			check(Saves.write(path,state,rules),"continuing chapter save")
			replay=Saves.read(path,rules)
		if state.contacts.chapter_complete and turn<15:print("CONTACT COMPLETE turn ",state.turn)
	check(state.contacts.chapter_complete,"guided orders complete contact chapter")
	check(state.contacts.neighbors.reedbank.leader_serial>=5 and state.contacts.neighbors.oakrise.leader_serial>=5,"both communities change speakers across decades")
	for key in state.contacts:
		var broken:Dictionary=state.duplicate(true);broken.contacts[key]=["bad"]
		check(not rules.validate_state(broken),"reject malformed contact field "+key)
	for key in sent.contacts.mission:
		var broken:Dictionary=sent.duplicate(true);broken.contacts.mission[key]=["bad"]
		check(not rules.validate_state(broken),"reject malformed mission field "+key)
	for key in state.contacts.neighbors.reedbank:
		var broken:Dictionary=state.duplicate(true);broken.contacts.neighbors.reedbank[key]=["bad"]
		check(not rules.validate_state(broken),"reject malformed community field "+key)
	DirAccess.remove_absolute(path)
	print("NEIGHBOR CHECKS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
