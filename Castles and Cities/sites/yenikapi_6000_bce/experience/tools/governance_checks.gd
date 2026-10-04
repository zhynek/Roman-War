extends SceneTree
const Rules=preload("res://src/core/settlement_rules.gd")
const Saves=preload("res://src/campaign_save.gd")
const View=preload("res://src/campaign_view.gd")
const Driver=preload("res://tools/tutorial_driver.gd")
var rules
var checks:int=0
var failures:int=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func run() -> void:
	rules=Rules.new(read("governance"),read("balance"))
	var initial:Dictionary=rules.new_state()
	check(rules.validate_state(initial),"initial save valid")
	check(rules.people(initial).size()==30,"population explicitly modeled")
	var copy_before:String=JSON.stringify(initial)
	var f:Dictionary=rules.forecast(initial)
	check(JSON.stringify(initial)==copy_before,"forecast is pure")
	var rejection:Dictionary=rules.command(initial,{"kind":"plan","plan":{"food":19,"care":2,"timber":4,"watch":2,"building":3}})
	check(rejection.has("error") and JSON.stringify(initial)==copy_before,"reject oversubscribed workforce atomically")
	var watch:Dictionary=rules.command(initial,{"kind":"role","role":"watch"}).state
	check(rules.command(watch,{"kind":"commission","id":"field_extension"}).get("error")=="authority","watch cannot spend civic resources")
	check(rules.command(watch,{"kind":"policy","welcome":true,"tight_rations":false}).get("error")=="authority","watch cannot set household policy")
	check(rules.command(watch,{"kind":"commission","id":"watch_shelter"}).has("state"),"watch commands defense")
	check(rules.command(initial,{"kind":"commission","id":"north_home"}).get("error")=="prerequisite","housing needs access first")
	var ordered:Dictionary=rules.command(initial,{"kind":"commission","id":"field_extension"}).state
	check(ordered.wood==initial.wood-12 and ordered.queue.size()==1,"commission charges materials exactly once")
	check(rules.command(ordered,{"kind":"commission","id":"field_extension"}).get("error")=="already_ordered","no duplicate work")
	ordered=rules.advance(ordered).state
	check(ordered.queue.size()==1 and ordered.queue[0].progress>0 and ordered.completed.is_empty(),"multi-season construction")
	var material:int=ordered.wood
	var refund:int=12*(20-int(ordered.queue[0].progress))/20
	ordered=rules.command(ordered,{"kind":"cancel","id":"field_extension"}).state
	check(ordered.queue.is_empty() and ordered.wood==material+refund,"partial cancellation only refunds unspent work share")
	var state:Dictionary=initial.duplicate(true)
	var replay:Dictionary=initial.duplicate(true)
	var town_turn:int=-1
	var initial_leader:String=state.leaders.steward.id
	var path:String="/tmp/yenikapi-campaign-check-"+str(OS.get_process_id())+".json"
	for turn in range(160):
		state=Driver.orders(rules,state)
		replay=Driver.orders(rules,replay)
		var before:Dictionary=rules.forecast(state)
		state=rules.advance(state).state
		replay=rules.advance(replay).state
		check(JSON.stringify(state)==JSON.stringify(replay),"deterministic turn "+str(turn))
		check(state.food==before.food and state.security==before.stocks.security,"forecast matches season "+str(turn))
		check(rules.validate_state(state),"valid state at turn "+str(turn))
		var unique:Dictionary={}
		for task in state.assignments:unique[task.id]=true
		check(unique.size()==state.assignments.size(),"each citizen assigned once "+str(turn))
		if turn==15:check(state.leaders.steward.id!=initial_leader,"four-year leadership succession")
		if turn==9:
			check(Saves.write(path,state,rules),"real campaign write")
			replay=Saves.read(path,rules)
			check(not replay.is_empty(),"real campaign read")
		if state.phase=="town" and town_turn<0:town_turn=int(state.turn);print("TOWN at season ",town_turn," population ",rules.people(state).size())
		if turn<32 and turn%4==3:print("Year ",state.turn/4," food ",state.food," wood ",state.wood," pop ",rules.people(state).size()," projects ",state.completed.size()," stocks ",[state.wellbeing,state.cooperation,state.security])
	check(town_turn>0 and town_turn<=40,"tutorial reaches town within ten years")
	check(state.town_achieved,"milestone survives continued play")
	check(state.citizens[0].age==initial.citizens[0].age+160,"leaders and citizens age through decades")
	var births:int=0;var succession:int=0;var deaths:int=0
	for event in state.history:
		if event.kind=="birth":births+=1
		if event.kind=="death":deaths+=1
		if event.kind=="succession":succession+=1
	check(births>0 and succession>=10 and deaths>0,"births mortality and leadership continue")
	var household_counts:Dictionary={}
	for person in rules.people(state):household_counts[person.household]=int(household_counts.get(person.household,0))+1
	for count_ in household_counts.values():check(count_<=rules.balance.people_per_dwelling,"real household occupancy stays within capacity")
	var other_config:Dictionary=read("governance");other_config.settlement_id="another_tutorial_town"
	var independent=Rules.new(other_config,read("balance"))
	var other:Dictionary=independent.new_state()
	check(other.turn==0 and other.leaders.steward.since==0,"each settlement owns independent leaders and seasons")
	check(not independent.validate_state(state),"settlement saves cannot cross identities")
	var no_growth:Dictionary=initial.duplicate(true);no_growth.welcome=false
	no_growth=rules.advance(no_growth).state
	check(rules.people(no_growth).size()==30,"newcomers need explicit welcome")
	var rationed:Dictionary=initial.duplicate(true);rationed.tight_rations=true
	var ration_report:Dictionary=rules.forecast(rationed)
	check(ration_report.used<f.used and ration_report.stocks.wellbeing<f.stocks.wellbeing,"tight rations have a cost")
	var empty:Dictionary=initial.duplicate(true);empty.food=0;empty.plan={"food":0,"care":0,"watch":0,"building":0,"timber":rules.people(empty,true).size()}
	var hungry:Dictionary=rules.forecast(empty)
	check(hungry.used==0 and hungry.unfed==30,"unavailable food is never consumed")
	var full:Dictionary=initial.duplicate(true);full.food=rules.storage(full)
	var overflowing:Dictionary=rules.forecast(full)
	check(overflowing.overflow>0 and overflowing.food_delta==overflowing.gathered-overflowing.used-overflowing.spoil-overflowing.losses-overflowing.overflow,"food factor list balances at full storage")

	var before_base:Dictionary=read("settlement")
	var base_hash:String=JSON.stringify(before_base)
	var developed:Dictionary=View.snapshot(before_base,state,rules)
	check(JSON.stringify(before_base)==base_hash,"growth preserves dated reference")
	var retained:bool=false;var altered:bool=false;var added:bool=false
	for object in developed.objects:
		if object.id=="yk_house_01":retained=object.revision==1
		if object.id=="yk_store_01":altered=object.revision==2 and object.change.predecessors==["yk_store_01@1"]
		if object.id=="growth_home_north":added=object.change.kind=="added"
	check(retained and altered and added,"visible fabric has explicit stable lineage")
	# Persistent shortages cause contraction and departures, not an irreversible victory.
	state.food=0;state.plan={"food":0,"timber":rules.people(state,true).size(),"care":0,"watch":0,"building":0}
	var count:int=rules.people(state).size()
	state=rules.advance(state).state
	check(state.phase=="village" and rules.people(state).size()<count,"scarcity causes contraction")
	# Save corruption rejection never returns a partial live state.
	var valid:Dictionary=rules.new_state()
	for key in valid:
		var broken:Dictionary=valid.duplicate(true);broken[key]=["bad"]
		check(not rules.validate_state(broken),"reject malformed "+key)
	var broken:Dictionary=valid.duplicate(true);broken.citizens[1].id=broken.citizens[0].id
	check(not rules.validate_state(broken),"reject duplicate citizen IDs")
	broken=valid.duplicate(true);broken.completed=[{"id":"north_home","turn":0}]
	check(not rules.validate_state(broken),"reject missing saved project prerequisite")
	FileAccess.open(path,FileAccess.WRITE).store_string('{"format":"yenikapi_view","version":1}')
	check(Saves.read(path,rules).is_empty(),"view bookmark cannot become campaign")
	DirAccess.remove_absolute(path)
	print("GOVERNANCE CHECKS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func read(name:String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://data/"+name+".json"))
