extends SceneTree
const Rules=preload("res://src/core/settlement_rules.gd")
const Saves=preload("res://src/campaign_save.gd")
const NeighborDriver=preload("res://tools/neighbor_driver.gd")
var checks: int = 0
var failures: int = 0
var rules
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: ",message)
func read(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/"+name+".json"))
func order(state: Dictionary, id: String, enabled: bool = true) -> Dictionary:
	return rules.command(state,{"kind":"household_order","id":id,"enabled":enabled})
func run() -> void:
	rules=Rules.new(read("governance"),read("balance"),read("neighbors"),read("households"))
	var initial: Dictionary = rules.new_state()
	var legacy_rules = Rules.new(read("governance"),read("balance"),read("neighbors"))
	check(rules.forecast(initial)==legacy_rules.forecast(legacy_rules.new_state()),"inactive chapter leaves original forecast unchanged")
	check(rules.households.stage(initial)=="inactive","original tutorial has no danger")
	check(order(initial,"refuge").get("error")=="household_missing","orders cannot silently activate chapter")
	for role in ["steward","watch"]:
		var office: Dictionary=rules.command(initial,{"kind":"role","role":role}).state
		check(rules.command(office,{"kind":"household_begin"}).get("error")=="authority","only God starts hypothetical scenario: "+role)
	var path: String="/tmp/yenikapi-household-check-"+str(OS.get_process_id())+".json"
	var old: Dictionary=initial.duplicate(true);old.erase("households");old.erase("contacts")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"format":"yenikapi_seasons","version":1,"state":old}))
	check(Saves.read(path,rules)==initial,"version-one old save gains inactive extensions only")
	var state: Dictionary=rules.command(initial,{"kind":"household_begin"}).state
	check(rules.validate_state(state),"begun household chapter validates")
	check(state.households.homes.size()==6,"six occupied initial households receive stable memories")
	check(rules.command(state,{"kind":"household_begin"}).get("error")=="household_started","no restart clears household memory")
	check(rules.households.stage(state)=="warning","chapter starts at warning")
	var untouched: String=JSON.stringify(state)
	var baseline: Dictionary=rules.households.forecast(state,rules)
	check(JSON.stringify(state)==untouched and baseline.food_penalty==4,"warning forecast pure and finite")
	for id in rules.households.ORDER_IDS:
		for role in ["steward","watch"]:
			var office: Dictionary=rules.command(state,{"kind":"role","role":role}).state
			check(order(office,id).has("state")== (rules.households.orders[id].role==role),"role owns only its household duties: "+role+" / "+id)
	var empty: Dictionary=state.duplicate(true);empty.wood=0
	check(order(empty,"refuge").get("error")=="household_stock" and empty.wood==0,"finite wood cannot go negative")
	check(order(state,"missing").get("error")=="household_unknown","unknown action rejected")
	check(rules.command(state,{"kind":"household_order","id":"refuge","enabled":1}).get("error")=="household_unknown","boolean order type enforced")
	var wood: int=int(state.wood)
	for id in rules.households.ORDER_IDS:
		state=order(state,id).state
	check(state.wood==wood-18,"four preparations spend finite wood exactly once")
	var paid: int=int(state.wood)
	state=order(state,"refuge",false).state;state=order(state,"refuge").state
	check(state.wood==paid,"turning retained preparation off and on never pays twice")
	check(state.households.investments.refuge and state.households.orders.refuge,"retained investment separate from active order")
	var prepared: Dictionary=rules.households.forecast(state,rules)
	check(prepared.food_penalty==0 and prepared.security>baseline.security,"store and route preparation reduce warning disruption")
	check(not prepared.learning_ready,"paid learning waits until recovery")
	var no_care: Dictionary=state.duplicate(true)
	no_care.plan.food+=no_care.plan.care;no_care.plan.care=0
	check(not rules.households.forecast(no_care,rules).care_ready,"paid care preparation stops helping without care workers")
	check(order(no_care,"refuge").get("error")=="household_labor","cannot enable unstaffed care")
	check(order(no_care,"refuge",false).has("state"),"understaffed order can always be disabled")
	var no_watch: Dictionary=state.duplicate(true)
	no_watch.plan.food+=no_watch.plan.watch;no_watch.plan.watch=0
	check(not rules.households.forecast(no_watch,rules).watch_ready,"paid routes stop helping without watch workers")
	check(order(no_watch,"safe_routes").get("error")=="household_labor","cannot enable unstaffed routes")
	var low_gathering: Dictionary=state.duplicate(true)
	for season in range(4):low_gathering=rules.advance(low_gathering).state
	low_gathering.plan.timber+=low_gathering.plan.food+low_gathering.plan.building
	low_gathering.plan.food=0;low_gathering.plan.building=0
	check(not rules.households.ready(low_gathering,"learning",rules),"no food production cannot fund learning")
	var no_output: Dictionary=rules.advance(low_gathering).state
	for id in low_gathering.households.homes:
		check(no_output.households.homes[id].practice==low_gathering.households.homes[id].practice,"unfunded learning earns no adoption: "+id)
	low_gathering.plan.food=1;low_gathering.plan.timber-=1
	check(not rules.households.ready(low_gathering,"learning",rules),"five gathered food cannot cover two disruption plus four learning")
	low_gathering.plan.food=2;low_gathering.plan.timber-=1
	check(rules.households.ready(low_gathering,"learning",rules),"ten gathered food covers learning plus disruption")
	var sequence: Array=["warning","warning","danger","danger","recovery","recovery","renewal","renewal","settled"]
	var replay: Dictionary=state.duplicate(true)
	var remembered_danger: int=0
	for season in range(40):
		if season<sequence.size():check(rules.households.stage(state)==sequence[season],"authored phase "+str(season))
		var quote: Dictionary=rules.forecast(state)
		var before: Dictionary=state.duplicate(true)
		state=rules.advance(state).state
		replay=rules.advance(replay).state
		check(state==replay,"deterministic household replay "+str(season))
		check(state.food==quote.food,"food opportunity cost matches resolved food "+str(season))
		check(rules.validate_state(state),"valid household chapter season "+str(season))
		check(state.households.elapsed==state.turn-state.households.started,"elapsed anchored to exact turn "+str(season))
		if season==3:
			remembered_danger=state.households.homes.sim_household_01.stress
			check(remembered_danger>0,"danger leaves stress rather than instant reset")
		if season==4:
			check(state.households.homes.sim_household_01.stress<remembered_danger,"care supports gradual recovery")
			var values: Dictionary={}
			for memory in state.households.homes.values():values[memory.practice]=true
			check(values.size()>1,"shared practice adoption differs among households")
			check(state.households.report.learning_ready and state.households.report.food_penalty==6,"learning consumes output during recovery")
		if season==5:
			check(Saves.write(path,state,rules),"save an active household chapter")
			check(JSON.parse_string(FileAccess.get_file_as_string(path)).version==3,"household extension uses version-three wrapper")
			replay=Saves.read(path,rules)
			check(replay==state,"save preserves memories, orders and phase exactly")
		if season==8:
			var halted: Dictionary=order(state,"learning",false).state
			var after: Dictionary=rules.advance(halted).state
			for id in halted.households.homes:
				check(after.households.homes[id].practice==halted.households.homes[id].practice,"learned practice persists after lessons stop: "+id)
			check(rules.households.forecast(halted,rules).food_penalty==0,"inactive learning consumes no output")
	check(state.households.homes.sim_household_01.stress==0,"recovered households eventually release stress")
	check(rules.households.stage(state)=="settled","chapter does not automatically repeat danger")
	var cold: Dictionary=rules.command(initial,{"kind":"household_begin"}).state
	for season in range(4):cold=rules.advance(cold).state
	check(cold.households.homes.sim_household_01.stress>remembered_danger,"unprepared household keeps more danger stress")
	var contraction: Dictionary=state.duplicate(true)
	for citizen in contraction.citizens:
		if citizen.household=="sim_household_06":citizen.active=false
	contraction.plan=rules.normalize_plan(contraction,contraction.plan)
	var retained: Dictionary=contraction.households.homes.sim_household_06.duplicate()
	contraction=rules.advance(contraction).state
	check(contraction.households.homes.sim_household_06==retained,"empty household retains prior memory through contraction")
	for field in state.households:
		var malformed: Dictionary=state.duplicate(true);malformed.households[field]=["bad"]
		check(not rules.validate_state(malformed),"reject malformed extension field "+field)
	for field in state.households.report:
		var malformed: Dictionary=state.duplicate(true);malformed.households.report[field]=["bad"]
		check(not rules.validate_state(malformed),"reject malformed household report "+field)
	for field in ["stress","practice"]:
		for bad in [-1,101,0.5,"bad",null,[],{},true]:
			var malformed: Dictionary=state.duplicate(true);malformed.households.homes.sim_household_01[field]=bad
			check(not rules.validate_state(malformed),"reject malformed household memory "+field+str(bad))
	for field in ["orders","investments"]:
		for id in rules.households.ORDER_IDS:
			var malformed: Dictionary=state.duplicate(true);malformed.households[field][id]=0
			check(not rules.validate_state(malformed),"reject nonboolean household policy "+field+id)
	var malformed: Dictionary=state.duplicate(true);malformed.households.elapsed-=1
	check(not rules.validate_state(malformed),"reject phase drift in save")
	malformed=state.duplicate(true);malformed.households.homes.erase("sim_household_01")
	check(not rules.validate_state(malformed),"cannot omit an occupied household memory")
	malformed=state.duplicate(true);malformed.households.homes.unknown={"stress":0,"practice":0}
	check(not rules.validate_state(malformed),"unknown household memory rejected")
	malformed=state.duplicate(true);malformed.households.investments.refuge=false
	check(not rules.validate_state(malformed),"enabled preparation must have been paid")
	malformed=state.duplicate(true);malformed.households.extra=true
	check(not rules.validate_state(malformed),"unknown extension keys rejected")
	malformed=state.duplicate(true);malformed.households.homes.sim_household_01.extra=true
	check(not rules.validate_state(malformed),"unknown memory keys rejected")
	var town: Dictionary=NeighborDriver.foundation(rules)
	town=rules.command(town,{"kind":"neighbor_begin"}).state
	var contact_legacy: Dictionary=town.duplicate(true);contact_legacy.erase("households")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"format":"yenikapi_seasons","version":2,"state":contact_legacy}))
	check(Saves.read(path,rules)==town,"old contact wrapper-two gains only inactive household extension")
	var combined: Dictionary=rules.command(town,{"kind":"household_begin"}).state
	combined=order(combined,"safe_routes").state
	check(rules.households.ready(combined,"safe_routes",rules),"home watch staffs safe routes before travel")
	var before_mission: Dictionary=rules.households.forecast(combined,rules)
	combined=rules.command(combined,{"kind":"neighbor_send","neighbor":"oakrise","mission":"trade"}).state
	check(not rules.households.ready(combined,"safe_routes",rules),"one watch escort cannot also staff home safe routes")
	check(rules.households.forecast(combined,rules).food_penalty>before_mission.food_penalty,"escort departure removes route gathering mitigation")
	check(order(combined,"safe_routes").get("error")=="household_labor","re-enabling routes cannot double count away escorts")
	check(Saves.write(path,combined,rules),"combined active contact and household save")
	check(JSON.parse_string(FileAccess.get_file_as_string(path)).version==3,"households dominate save wrapper even with active contact")
	var combined_replay: Dictionary=Saves.read(path,rules)
	for season in range(12):
		combined=rules.advance(combined).state;combined_replay=rules.advance(combined_replay).state
		check(combined==combined_replay,"combined chapter save/replay "+str(season))
		check(rules.validate_state(combined),"combined chapter remains valid "+str(season))
	check(combined.contacts.neighbors.oakrise.trades==1,"neighbor cargo still arrives exactly once during danger")
	check(rules.households.ready(combined,"safe_routes",rules),"returned watch can support standing route order again")
	var incompatible: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));incompatible.version=2
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(incompatible))
	check(Saves.read(path,rules).is_empty(),"active household extension cannot hide in an older wrapper")
	check(JSON.stringify(initial)==JSON.stringify(rules.new_state()),"commands and forecasts never mutate source state")
	DirAccess.remove_absolute(path)
	print("HOUSEHOLD CHECKS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
