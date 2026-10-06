extends SceneTree
const Rules=preload("res://src/core/settlement_rules.gd")
const Driver=preload("res://tools/living_driver.gd")
const Saves=preload("res://src/campaign_save.gd")
var checks: int=0
var failures: int=0
var rules
func _initialize() -> void:call_deferred("run")
func read(id: String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://data/"+id+".json"))
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var result: Dictionary=rules.command(s,a);check(result.has("state"),JSON.stringify(a)+" "+str(result.get("error","")));return result.get("state",s)
func run() -> void:
	rules=Rules.new(read("governance"),read("balance"),read("neighbors"),read("households"),read("assets"),read("land"),read("living"))
	var s: Dictionary=Driver.initial(rules)
	check(rules.validate_state(s),"initial state valid "+str(s.living.keys()))
	var untouched: Dictionary=s.duplicate(true)
	for i in range(20):rules.forecast(s);rules.quote(s,{"kind":"living_inspect","id":"west_wood"})
	check(s==untouched,"pure forecasts/quotes, no idle authority")
	for i in range(10):s=cmd(s,{"kind":"living_inspect","id":"west_wood"})
	check(s.living.discoveries.size()==1 and s.food==100 and s.wood==30 and s.turn==0,"inspection idempotent, no reward")
	var w: Dictionary=cmd(s,{"kind":"role","role":"watch"})
	check(rules.command(w,{"kind":"living_order","id":"prepare","value":1}).get("error")=="authority","watch cannot assign civic preparation")
	check(rules.command(s,{"kind":"living_order","id":"cooperate","value":true}).get("error")=="living_discovery","observation required, not a free boost")
	var legacy: Dictionary=preload("res://tools/land_driver.gd").at_season(rules,true,12)
	var path: String="/tmp/yenikapi-living-test-"+str(OS.get_process_id())+".json"
	var old: Dictionary=legacy.duplicate(true);old.erase("living")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"format":"yenikapi_seasons","version":5,"state":old}))
	check(Saves.read(path,rules)==legacy,"wrapper 5 only backfills inactive extension")
	var adopted: Dictionary=cmd(legacy,{"kind":"living_begin"})
	for key in ["wood","food","queue","completed","citizens","households","assets","land","contacts","leaders"]:check(adopted[key]==legacy[key],"adoption preserves "+key)
	var outcomes: Array=[]
	for attentive in [false,true]:
		s=Driver.initial(rules)
		var replay: Dictionary=s.duplicate(true)
		for season in range(40):
			s=Driver.orders(rules,s,attentive);replay=Driver.orders(rules,replay,attentive)
			check(rules.validate_state(s),"valid orders "+str(attentive)+" season "+str(season))
			var f: Dictionary=rules.forecast(s)
			var before: Dictionary=s.duplicate(true)
			var assigned: Array=rules.assignments(s,f.plan);var ids: Array=[]
			for task in assigned:
				check(task.id not in ids and rules.person_by_id(s,task.id).age>=rules.balance.adult_age,"one adult duty");ids.append(task.id)
			check(ids.size()==rules.people(s,true).size(),"all adults accounted")
			s=rules.advance(s).state;replay=rules.advance(replay).state
			check(s.food==f.food and s.report.living==f.living,"forecast actual identity")
			check(s.wood==before.wood+f.wood-f.assets.repair_cost-f.assets.access_cost-f.living.fuel-f.living.prepare_wood-f.living.support-f.living.repair_wood,"one wood ledger")
			check(s==replay,"deterministic strategy replay")
			check(rules.validate_state(s),"valid resolved "+str(attentive)+" season "+str(season))
			check(f.unfed==0,"viable overview/attentive meals")
			if season in [4,15,25]:
				check(Saves.write(path,replay,rules),"atomic wrapper 6 save")
				replay=Saves.read(path,rules);check(replay==s,"exact reload with knowledge and commitments")
				if replay.is_empty():quit(1);return
		outcomes.append({"attentive":attentive,"food":s.food,"wood":s.wood,"kits":s.living.kits,"prepared":s.living.blanks,"readiness":s.living.readiness,"practice":s.living.practice,"meetings":s.living.meetings,"security":s.security,"leader":s.leaders})
	print("LIVING STRATEGIES ",JSON.stringify(outcomes))
	check(outcomes[1].wood>outcomes[0].wood,"paid informed strategy earns material advantage")
	check(outcomes[1].practice==rules.living.balance.practice_needed,"cooperation develops through work")
	# Overcommitment is reversible before resolution, without refunding completed fabric.
	s=cmd(s,{"kind":"living_order","id":"prepare","value":0})
	s=cmd(s,{"kind":"living_order","id":"training","value":false})
	check(rules.forecast(s).assets.living.prepared==0,"disable preparation releases its labor/cost")
	var malformed: Dictionary=s.duplicate(true);malformed.living.kits=999
	check(not rules.validate_state(malformed),"reject impossible inventory")
	DirAccess.remove_absolute(path)
	print("LIVING CHECKS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
