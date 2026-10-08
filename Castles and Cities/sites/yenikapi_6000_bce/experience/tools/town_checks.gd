extends "res://tools/lifecycle_checks.gd"
const TownDriver=preload("res://tools/town_driver.gd")
const Presentation=preload("res://src/project_presentation.gd")
var entry: Dictionary={}
var entry_recipe: Array=[]
var fixtures: Dictionary={}

func run() -> void:
	out_dir="/tmp/yenikapi-town-checks"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	rules=TownDriver.rules()
	check(rules.lifecycle.definition_hash=="a4694114cc755d8f5a2113daabf71370a8b85824acc1317dbe973c3555f1fe35","published 0.11 semantic hash remains identical")
	var old: Dictionary=Saves.read("res://tools/fixtures/lifecycle-0.11-paid.json",rules)
	check(not old.is_empty(),"load actual frozen 0.11 wrapper8 paused paid project")
	var adopted: Dictionary=command(old,{"kind":"lifecycle_town_begin"})
	for key in old:
		if key not in ["lifecycle","history"]:check(adopted[key]==old[key],"explicit extension retains old "+key)
	check(adopted.lifecycle.definition_hash==old.lifecycle.definition_hash,"extension retains base profile")
	check(Saves.read("res://tools/fixtures/lifecycle-0.11-paid.json",rules)==old,"adoption never rewrites original save")
	saved(adopted,"adopted-old-paid")
	var outcomes: Array=[]
	for compact in [true,false]:
		var s: Dictionary=TownDriver.initial(rules)
		var replay: Dictionary=s.duplicate(true)
		var transcript: Array=[]
		var milestones: Dictionary={}
		var captured: Dictionary={}
		var prefix: String="compact" if compact else "outward"
		for season in range(100):
			for order in range(24):
				var action: Dictionary=TownDriver.town_action(rules,s,compact)
				if action.is_empty():break
				var before: Dictionary=s.duplicate(true)
				if action.get("id")=="town_civic" and action.kind=="commission":
					check(rules.lifecycle.status(s,rules).ready,"town quote meets shared sustained support")
					fixture(s,prefix+"-town-ready",transcript)
					if compact:blocked_readiness(s,transcript)
				s=command(s,action);replay=command(replay,action)
				transcript.append({"turn":before.turn,"action":action})
				check(s==replay,"town command deterministic replay")
				if action.kind=="commission" and rules.lifecycle.town_projects.has(action.id):
					check(s.wood==before.wood-int(rules.projects[action.id].wood),"town purchase pays once")
					check(s.food==before.food and s.citizens==before.citizens,"purchase creates no supplies or people")
					var unchanged: Dictionary=s.duplicate(true)
					check(not rules.command(s,action).has("state") and unchanged==s,"repeated commission cannot charge again")
					fixture(s,prefix+"-"+action.id+"-paid",transcript)
			check(rules.validate_state(s),"valid town pre-season "+prefix+str(season))
			var forecast: Dictionary=rules.forecast(s)
			check(forecast.unfed==0,"ordinary strategy keeps meals covered")
			var workers: Array=[]
			for task in rules.assignments(s,forecast.plan):
				check(task.id not in workers,"one finite adult assignment");workers.append(task.id)
			var before: Dictionary=s.duplicate(true)
			s=rules.advance(s).state;replay=rules.advance(replay).state
			transcript.append({"turn":before.turn,"action":{"kind":"advance"}})
			check(s==replay and rules.validate_state(s),"closing town state valid and replayable")
			check(s.food==forecast.food,"operational service forecast equals actual provisions")
			for item in s.queue:
				if rules.lifecycle.town_projects.has(item.id) and item.progress>0 and not captured.has(item.id):
					captured[item.id]=true;partial_contract(s,item.id)
					fixture(s,prefix+"-"+item.id+"-partial",transcript)
			for item in s.completed:
				if not rules.lifecycle.town_projects.has(item.id) or milestones.has(item.id):continue
				milestones[item.id]=s.turn
				if item.id=="town_provision" and compact:public_stress(s,transcript)
				if item.id=="town_civic":
					check(rules.lifecycle.stage(s,rules)=="town","paid civic completion earns town")
					check(not rules.has_project(s,"town_preparation") and not rules.has_project(s,"town_provision"),"rank unlocks purchases without free facilities")
					check(s.lifecycle.readiness.seasons==0,"promotion resets readiness")
					if compact:entry=s.duplicate(true);entry_recipe=transcript.duplicate(true)
					fixture(s,prefix+"-town-entry",transcript)
			if season in [20,45,75]:replay=saved(replay,prefix+"-resume-"+str(season))
		check(TownDriver.finished_town(rules,s),"both paid investments reachable "+prefix)
		check(rules.lifecycle.stage(s,rules)=="town" and rules.town_conditions(s),"town stays supported at season100")
		var op: Dictionary=rules.forecast(s).town
		check(op.wanted==2 and op.filled==2,"town duty replaces one worker with total2")
		var civic_count: int=0
		for req in rules.assets.allocation(s,rules).requests:
			if req.id=="lifecycle_civic":civic_count+=1
		check(civic_count==1,"no duplicate civic duty")
		operational_checks(s)
		if compact:legacy_support_contraction(s)
		fixture(s,prefix+"-town-invested",transcript)
		outcomes.append({"compact":compact,"milestones":milestones,"food":s.food,"wood":s.wood,"work_places":rules.land.totals(s,rules).work,"population":rules.people(s).size(),"sha256":JSON.stringify(s).sha256_text()})
	legacy_town()
	contacts_and_incidents()
	FileAccess.open(out_dir.path_join("fixtures.json"),FileAccess.WRITE).store_string(JSON.stringify(fixtures,"  "))
	FileAccess.open(out_dir.path_join("strategies.json"),FileAccess.WRITE).store_string(JSON.stringify(outcomes,"  "))
	print("TOWN STRATEGIES ",JSON.stringify(outcomes));finish()

func fixture(s: Dictionary,id: String,commands: Array) -> void:
	saved(s,id)
	var replay: Dictionary=TownDriver.initial(rules)
	for item in commands:
		check(replay.turn==item.turn,"fixture command turn "+id)
		var result: Dictionary=rules.advance(replay) if item.action.kind=="advance" else rules.command(replay,item.action)
		check(result.has("state"),"fixture public command "+id)
		if not result.has("state"):return
		replay=result.state
	check(replay==s,"fixture recipe reproduces exact state "+id)
	var recipe: Dictionary={"profile":rules.lifecycle.town.profile,"definition_hash":rules.lifecycle.town_hash,"commands":commands.duplicate(true),"sha256":JSON.stringify(s).sha256_text(),"turn":s.turn}
	fixtures[id]={"sha256":recipe.sha256,"turn":s.turn}
	FileAccess.open(out_dir.path_join(id+"-recipe.json"),FileAccess.WRITE).store_string(JSON.stringify(recipe,"  "))

func operational_checks(s: Dictionary) -> void:
	var preparing: Dictionary=command(s,{"kind":"living_order","id":"prepare","value":1})
	var forecast: Dictionary=rules.forecast(preparing)
	check(forecast.town.prepared==int(rules.lifecycle.town_balance.preparation_bonus),"paid preparation produces actual extra sets")
	check(forecast.living.prepare_wood==int(rules.living.balance.prepare_wood)+int(rules.lifecycle.town_balance.preparation_wood),"extra output pays extra timber")
	var advanced: Dictionary=rules.advance(preparing).state
	check(advanced.living.blanks==preparing.living.blanks+forecast.living.prepared-forecast.living.repaired,"preparation is actual seasonal output")
	check(forecast.town.saved==mini(int(rules.lifecycle.town_balance.spoil_reduction),int(preparing.food)*int(rules.balance.spoil_percent)/100),"service only saves actual spoilage")
	var before: Dictionary=preparing.duplicate(true)
	for i in range(10):
		rules.forecast(preparing);rules.lifecycle.status(preparing,rules);Presentation.new().describe(preparing,rules,"town_preparation")
	check(preparing==before,"queries cannot create payment work or production")
	# Civic and service adults are care-class work: their social contribution is
	# shown under its own factor and never credited to household care.
	var civic_adults: int=0
	for req in forecast.assets.requests:
		if req.id in ["lifecycle_civic","town_service"]:civic_adults+=int(req.filled)
	var seen: Dictionary={"wellbeing":{},"cooperation":{}}
	for key in seen:
		for factor in forecast.factors[key]:seen[key][factor.id]=int(factor.value)
	check(civic_adults==int(rules.lifecycle.town_balance.civic_workers)+int(rules.lifecycle.town_balance.service_workers),"town staffs civic duty and the service")
	check(seen.wellbeing.get("civic",-1)==civic_adults*int(rules.balance.wellbeing_care) and seen.cooperation.get("civic",-1)==civic_adults*int(rules.balance.cooperation_care),"civic and service adults appear under their own social factor")
	check(seen.wellbeing.get("care",-1)==(int(forecast.plan.care)-civic_adults)*int(rules.balance.wellbeing_care),"household care factor excludes civic staff")
	check(forecast.factors.wellbeing[1].id=="care" and forecast.factors.wellbeing[2].id=="civic","civic factor follows care without displacing later named factors")
	var damaged: Dictionary=preparing.duplicate(true);damaged.assets.conditions.stores=0
	var disabled: Dictionary=rules.forecast(damaged)
	check(disabled.town.prepared==0 and disabled.town.saved==0,"neglected stores suspend both new benefits")
	check(rules.lifecycle.stage(damaged,rules)=="town","impaired service preserves earned rank")
	for malformed in ["null","orphan","base_turn"]:
		var bad: Dictionary=s.duplicate(true)
		if malformed=="null":bad.lifecycle.town=null
		elif malformed=="orphan":bad.lifecycle.erase("town")
		else:bad.lifecycle.started={}
		check(not rules.validate_state(bad),"reject malformed town adoption "+malformed)
	var adopted_only: Dictionary=command(command(TownDriver.initial(rules),{"kind":"lifecycle_begin"}),{"kind":"lifecycle_town_begin"})
	adopted_only.lifecycle.erase("town")
	check(not rules.validate_state(adopted_only),"reject orphan adoption before any town projects")
	adopted_only.lifecycle={}
	check(not rules.validate_state(adopted_only),"reject erased lifecycle with retained adoption history")
	var broken_history: Dictionary=s.duplicate(true);broken_history.history=null
	check(not rules.validate_state(broken_history),"malformed town history rejected without script error")
	for key in ["definition_hash","profile","started"]:
		var invalid: Dictionary=s.duplicate(true)
		invalid.lifecycle.town[key]=999 if key=="started" else "changed"
		check(not rules.validate_state(invalid),"reject changed town save "+key)
	for field in ["maintenance","equivalents"]:
		var balance_: Dictionary=TownDriver.read("balance")
		var land_: Dictionary=TownDriver.read("land")
		if field=="maintenance":balance_.assets.condition_threshold+=1
		else:land_.alternatives.north_home=[]
		var retuned=TownDriver.Rules.new(TownDriver.read("governance"),balance_,TownDriver.read("neighbors"),TownDriver.read("households"),TownDriver.read("assets"),land_,TownDriver.read("living"),TownDriver.read("incidents"),TownDriver.read("lifecycle"),TownDriver.read("settlement"))
		check(retuned.lifecycle.definition_hash==rules.lifecycle.definition_hash,"dependent town data does not replace the base profile")
		check(not retuned.validate_state(s),"town semantic hash pins referenced "+field)

func legacy_support_contraction(invested: Dictionary) -> void:
	# The reversible legacy support milestone and the earned civic rank are
	# distinct: an ordinary policy can lose support while rank, duty and paid
	# facility output continue, and ordinary seasons recover it.
	var s: Dictionary=command(invested,{"kind":"policy","welcome":invested.welcome,"tight_rations":true})
	var contracted: bool=false
	for i in range(12):
		s=rules.advance(s).state
		if s.phase=="village":contracted=true;break
	check(contracted,"tight rations contract the legacy support milestone at civic town")
	check(rules.lifecycle.stage(s,rules)=="town" and s.town_achieved and rules.validate_state(s),"earned civic rank and achievement survive support contraction")
	var f: Dictionary=rules.forecast(s)
	check(f.town.filled==int(rules.lifecycle.town_balance.civic_workers) and f.town.saved>0,"civic duty and provision output continue without legacy support")
	s=command(s,{"kind":"policy","welcome":s.welcome,"tight_rations":false})
	for i in range(8):s=rules.advance(s).state
	check(s.phase=="town" and rules.lifecycle.stage(s,rules)=="town","restoring rations recovers legacy support within eight seasons")

func legacy_town() -> void:
	var s: Dictionary=preload("res://tools/land_driver.gd").at_season(rules,true,28)
	check(s.town_achieved,"legacy rank earned through ordinary commands")
	for kind in ["living_begin","lifecycle_begin","lifecycle_town_begin"]:s=command(s,{"kind":kind})
	check(rules.lifecycle.stage(s,rules)=="town" and not rules.has_project(s,"lifecycle_assembly"),"recognized town retains rank without invented fabric")
	for i in range(80):
		if rules.has_project(s,"town_civic"):break
		if s.queue.is_empty():
			var id: String="council_ground" if not rules.has_project(s,"council_ground") else rules.lifecycle.status(s,rules).project
			if not id.is_empty() and not rules.quote(s,{"kind":"commission","id":id}).has("error"):s=command(s,{"kind":"commission","id":id})
		s=rules.advance(s).state
		check(rules.lifecycle.stage(s,rules)=="town" and rules.validate_state(s),"recognized town fabric replay preserves rank")
	check(rules.has_project(s,"town_civic"),"recognized town has legitimate paid civic fabric route")
	check(s.history.filter(func(e):return e.kind=="town_promoted").is_empty(),"recognized rank receives no duplicate promotion event")
	saved(s,"recognized-town-with-paid-fabric")

func contacts_and_incidents() -> void:
	var d=preload("res://tools/neighbor_driver.gd")
	var s: Dictionary=d.orders(rules,d.foundation(rules))
	for kind in ["asset_begin","land_begin","living_begin","lifecycle_begin"]:s=command(s,{"kind":kind})
	var cargo: Dictionary=s.contacts.duplicate(true)
	s=command(s,{"kind":"lifecycle_town_begin"})
	check(s.contacts==cargo,"explicit town extension preserves active contact escrow")
	var replay: Dictionary=saved(s,"town-active-contact")
	for i in range(8):
		s=rules.advance(s).state;replay=rules.advance(replay).state
		check(s==replay and rules.validate_state(s),"contact journey continues after town adoption")
	s=command(entry,{"kind":"incident_begin"})
	for id in ["town_preparation","town_provision"]:
		s=command(s,{"kind":"commission","id":id})
		s=command(s,{"kind":"asset_project","id":id,"crew":0,"priority":2,"paused":id=="town_provision"})
	var resolved: int=0
	for i in range(60):
		var incident: Dictionary=rules.incidents.current(s)
		if not incident.is_empty() and not incident.outcome.is_empty():
			var repair: String=rules.incidents.specs[incident.id].repair
			if not rules.quote(s,{"kind":"commission","id":repair}).has("error"):s=command(s,{"kind":"commission","id":repair})
		var f: Dictionary=rules.forecast(s)
		if f.incidents.get("resolves",false):
			s=command(s,{"kind":"asset_project","id":"town_preparation","crew":1,"priority":1,"paused":false})
			f=rules.forecast(s)
			var before: Dictionary=s.duplicate(true)
			replay=saved(s,"town-incident-"+str(resolved))
			s=rules.advance(s).state;replay=rules.advance(replay).state
			check(s==replay,"incident exact save replay")
			for j in range(before.queue.size()):
				var item: Dictionary=before.queue[j]
				var after: Array=s.queue.filter(func(q):return q.id==item.id)
				check(after.size()==1 and int(after[0].progress)==int(item.progress)+int(f.assets.projects[item.id].work),"incident preserves partial paid work "+item.id)
			resolved+=1
			s=command(s,{"kind":"asset_project","id":"town_preparation","crew":0,"priority":2,"paused":false})
		else:s=rules.advance(s).state
		check(rules.validate_state(s),"incident town state valid")
	check(resolved==2,"both incidents resolve with active and paused town sites")

func finish() -> void:
	print("TOWN CHECKS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func public_stress(initial: Dictionary,recipe: Array) -> void:
	var s: Dictionary=initial.duplicate(true)
	var transcript: Array=recipe.duplicate(true)
	for season in range(16):
		var action: Dictionary={"kind":"commission","id":"exchange_place"}
		var result: Dictionary=rules.command(s,action)
		if result.has("state"):
			var crew: Dictionary={"kind":"asset_project","id":"exchange_place","crew":3,"priority":1,"paused":false}
			var stressed: Dictionary=rules.command(result.state,crew).state
			if rules.forecast(stressed).town.filled<rules.forecast(stressed).town.wanted:
				transcript.append({"turn":s.turn,"action":action});transcript.append({"turn":s.turn,"action":crew.duplicate(true)})
				fixture(stressed,"stressed-town",transcript)
				var f: Dictionary=rules.forecast(stressed)
				check(f.town.saved==0,"unstaffed civic duty suspends service")
				var next: Dictionary=rules.advance(stressed).state
				transcript.append({"turn":stressed.turn,"action":{"kind":"advance"}})
				check(rules.lifecycle.stage(next,rules)=="town" and next.queue.size()==1,"struggling town keeps rank and paid project")
				crew.paused=true;next=command(next,crew)
				transcript.append({"turn":next.turn,"action":crew.duplicate(true)})
				check(rules.forecast(next).town.civic and rules.forecast(next).town.saved>0,"pause optional work restores town operation")
				fixture(next,"recovered-town",transcript)
				return
		transcript.append({"turn":s.turn,"action":{"kind":"advance"}});s=rules.advance(s).state
	check(false,"ordinary public command stress fixture is attainable")

func blocked_readiness(_initial: Dictionary,_recipe: Array) -> void:
	var s: Dictionary=TownDriver.initial(rules)
	var transcript: Array=[]
	for i in range(200):
		if rules.lifecycle.active(s) and rules.lifecycle.stage(s,rules)=="village_established":break
		var action: Dictionary=TownDriver.town_action(rules,s,true)
		if action.is_empty():action={"kind":"advance"}
		transcript.append({"turn":s.turn,"action":action.duplicate(true)})
		s=rules.advance(s).state if action.kind=="advance" else command(s,action)
	var status: Dictionary=rules.lifecycle.status(s,rules)
	check(status.project=="town_civic" and not status.ready and status.seasons==0,"large village still needs sustained town support")
	check(rules.quote(s,{"kind":"commission","id":"town_civic"}).get("error")=="lifecycle_readiness","insufficient sustained readiness blocks civic purchase")
	fixture(s,"town-readiness-blocked",transcript)
	for i in range(24):
		transcript.append({"turn":s.turn,"action":{"kind":"advance"}});s=rules.advance(s).state
		if rules.lifecycle.status(s,rules).ready:break
	check(rules.lifecycle.status(s,rules).ready,"ordinary seasons rebuild sustained town support")
	fixture(s,"town-readiness-recovered",transcript)
	# Counter reset is a separate rule boundary check, not a staged playthrough.
	var shortage: Dictionary=s.duplicate(true);shortage.food=0
	shortage=rules.advance(shortage).state
	check(not rules.lifecycle.status(shortage,rules).ready and shortage.lifecycle.readiness.seasons==0,"an actual failed support season clears the readiness counter")
