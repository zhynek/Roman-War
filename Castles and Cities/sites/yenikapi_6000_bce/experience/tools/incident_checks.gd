extends SceneTree
const Rules=preload("res://src/core/settlement_rules.gd")
const Driver=preload("res://tools/incident_driver.gd")
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
	rules=Rules.new(read("governance"),read("balance"),read("neighbors"),read("households"),read("assets"),read("land"),read("living"),read("incidents"))
	var path: String="/tmp/yenikapi-incident-test-"+str(OS.get_process_id())+".json"
	var original: Dictionary=Driver.initial(rules)
	check(rules.validate_state(original),"new incident state valid")
	var pure: Dictionary=original.duplicate(true)
	for i in range(20):rules.forecast(original);rules.quote(original,{"kind":"incident_inspect","id":"north_wood"})
	check(original==pure,"queries have no authority")
	var legacy: Dictionary=preload("res://tools/living_driver.gd").at_season(rules,12)
	var old: Dictionary=legacy.duplicate(true);old.erase("incidents")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"format":"yenikapi_seasons","version":6,"state":old}))
	check(Saves.read(path,rules)==legacy,"wrapper 6 only adds inactive incidents")
	var adopted: Dictionary=cmd(legacy,{"kind":"incident_begin"})
	for key in ["wood","food","completed","queue","citizens","households","living","land","assets","contacts","leaders"]:check(adopted[key]==legacy[key],"adoption retains "+key)
	check(adopted.incidents.records[0].signs==legacy.turn+rules.incidents.balance.grace,"adoption grace")
	check(rules.command(adopted,{"kind":"asset_pressure"}).get("error")=="incident_lesson","teaching pressure cannot overlap")
	var results: Array=[]
	for strategy in ["overview","attentive","underprepared"]:
		var s: Dictionary=original.duplicate(true)
		var replay: Dictionary=s.duplicate(true)
		var hungry: int=0
		for season in range(64):
			s=Driver.orders(rules,s,strategy);replay=Driver.orders(rules,replay,strategy)
			check(rules.validate_state(s),"valid orders "+strategy+" "+str(season))
			var f: Dictionary=rules.forecast(s)
			var before: Dictionary=s.duplicate(true)
			var ids: Array=[]
			for task in rules.assignments(s,f.plan):
				check(task.id not in ids and rules.person_by_id(s,task.id).age>=rules.balance.adult_age,"single adult assignment");ids.append(task.id)
			s=rules.advance(s).state;replay=rules.advance(replay).state
			check(s==replay,"season replay "+strategy)
			check(rules.validate_state(s),"valid resolved "+strategy+" "+str(season))
			check(s.food==f.food and s.report==f,"forecast equals actual")
			check(s.wood==before.wood+f.wood-f.assets.repair_cost-f.assets.access_cost-f.living.fuel-f.living.prepare_wood-f.living.support-f.living.repair_wood,"single material ledger")
			hungry+=int(f.unfed)
			check(Saves.write(path,s,rules),"save at every lifecycle stage "+str(season))
			var loaded: Dictionary=Saves.read(path,rules)
			check(loaded==s,"warning/response/recovery commitments roundtrip")
			if not loaded.is_empty():replay=loaded
			var active: int=0
			for e in s.incidents.records:
				if e.recovered<0:active+=1
			check(active<=1,"bounded overlap")
		check(s.incidents.records.size()==2,"both incidents reached "+strategy)
		check(hungry==0,"strategy remains fed "+strategy)
		for e in s.incidents.records:check(e.recovered>=0,"legitimate paid recovery "+strategy)
		results.append({"strategy":strategy,"food":s.food,"wood":s.wood,"unfed":hungry,"records":s.incidents.records,"leaders":s.leaders})
	print("INCIDENT STRATEGIES ",JSON.stringify(results))
	for i in range(2):check(results[1].records[i].outcome.severity<=results[0].records[i].outcome.severity,"relevant paid attentive advantage "+str(i))
	check(results[1].records[0].outcome.severity<results[0].records[0].outcome.severity,"clear informed approach advantage")
	check(results[2].records[1].outcome.lost>results[0].records[1].outcome.lost,"underprepared loses more stores")
	check(results[1].records[0].known<results[0].records[0].known,"early local information")
	# Negative load cases and stable inspection. Inspections may record information only.
	var s: Dictionary=Driver.at_season(rules,6)
	s=cmd(s,{"kind":"incident_inspect","id":"north_wood"})
	var same: Dictionary=s.duplicate(true)
	for i in range(20):s=cmd(s,{"kind":"incident_inspect","id":"north_wood"})
	check(s==same,"no repeat inspection effects")
	for key in ["due","warning","signs","id","known","recovered"]:
		var bad: Dictionary=s.duplicate(true);bad.incidents.records[0][key]="bad"
		check(not rules.validate_state(bad),"reject invalid incident "+key)
	var resolved: Dictionary=Driver.at_season(rules,8)
	check(rules.validate_state(JSON.parse_string(JSON.stringify(resolved))),"integral JSON factor values remain valid")
	for key in ["turn","severity","lost","factors"]:
		var bad: Dictionary=resolved.duplicate(true);bad.incidents.records[0].outcome[key]="bad"
		check(not rules.validate_state(bad),"reject invalid outcome "+key)
	var w: Dictionary=cmd(s,{"kind":"role","role":"watch"})
	check(rules.command(w,{"kind":"incident_restrict","enabled":true}).get("error")=="authority","office authority")
	# Cancelling returns only unused preparation materials; duplicate commissions refuse.
	s=Driver.at_season(rules,6,"underprepared")
	s=cmd(s,{"kind":"commission","id":"incident_approach_prepare"})
	var paid: Dictionary=s.duplicate(true)
	check(rules.command(s,{"kind":"commission","id":"incident_approach_prepare"}).has("error"),"duplicate cost blocked")
	check(s==paid,"duplicate cannot mutate state")
	s=cmd(s,{"kind":"cancel","id":"incident_approach_prepare"})
	check(s.living.blanks==paid.living.blanks+1 and s.wood==paid.wood+3,"unused paid materials returned exactly once")
	check(rules.command(s,{"kind":"cancel","id":"incident_approach_prepare"}).has("error"),"double refund blocked")
	# Extra preparedness has real allocation costs even during a quiet interval.
	s=Driver.at_season(rules,48)
	var ordinary: Dictionary=rules.forecast(s)
	s=cmd(s,{"kind":"living_order","id":"training","value":true})
	s=cmd(s,{"kind":"living_order","id":"prepare","value":1})
	check(rules.forecast(s).plan.food<ordinary.plan.food,"excess preparedness displaces gathering")
	# Different relevant factors: northern attention cannot guard the landing.
	s=Driver.at_season(rules,24,"overview")
	s=cmd(s,{"kind":"living_order","id":"patrol","value":"landing_post"})
	var local: Dictionary=rules.forecast(s).incidents
	s=cmd(s,{"kind":"living_order","id":"patrol","value":"north_post"})
	check(rules.forecast(s).incidents.severity>local.severity,"wrong focus loses local coverage/equipment response")
	# Adoption timed so leadership changes at the resolution boundary.
	s=preload("res://tools/living_driver.gd").at_season(rules,8)
	s=cmd(s,{"kind":"incident_begin"})
	var previous_leader: String=s.leaders.steward.id
	for i in range(10):s=rules.advance(Driver.orders(rules,s,"overview")).state
	check(s.leaders.steward.id!=previous_leader and s.incidents.records[0].recovered>=0,"commitments survive succession during incident")
	# Repair work benefits only from established, supported household cooperation.
	s=preload("res://tools/living_driver.gd").at_season(rules,32)
	s=cmd(s,{"kind":"incident_begin"})
	for i in range(8):s=rules.advance(s).state
	s=cmd(s,{"kind":"commission","id":"incident_approach_repair"})
	var supported: int=rules.forecast(s).assets.projects.incident_approach_repair.work
	s=cmd(s,{"kind":"living_order","id":"cooperate","value":false})
	check(supported>rules.forecast(s).assets.projects.incident_approach_repair.work,"established household cooperation helps finite repair crew")
	# Ignoring damage never repairs it and never spawns a second concurrent event.
	s=Driver.initial(rules)
	for i in range(40):s=rules.advance(s).state
	check(s.incidents.records.size()==1 and s.incidents.records[0].recovered<0,"no automatic recovery or failure cascade")
	# Compact and outward fabric remains intact; loaded approach dependence differs.
	var layouts: Array=[]
	for compact in [true,false]:
		s=preload("res://tools/living_driver.gd").initial(rules)
		for i in range(48):
			s=preload("res://tools/land_driver.gd").orders(rules,s,compact)
			s=preload("res://tools/living_driver.gd").orders(rules,s,true)
			s=rules.advance(s).state
		s=cmd(s,{"kind":"incident_begin"})
		var fabric: Array=s.completed.duplicate(true)
		for i in range(8):s=rules.advance(s).state
		for item in fabric:check(item in s.completed,"damage preserves older fabric")
		check(rules.validate_state(s),"layout incident state valid")
		layouts.append({"compact":compact,"severity":s.incidents.records[0].outcome.severity,"places":rules.land.totals(s,rules).work,"outer":rules.land.occupied_outer(s,rules),"access":rules.forecast(s).land.access})
	check(layouts[1].severity>layouts[0].severity and layouts[1].outer and not layouts[1].access,"outward approach dependence is consequential")
	print("INCIDENT LAYOUTS ",JSON.stringify(layouts))
	DirAccess.remove_absolute(path)
	print("INCIDENT CHECKS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
