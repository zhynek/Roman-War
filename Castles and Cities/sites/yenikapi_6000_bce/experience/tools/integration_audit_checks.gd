extends SceneTree
## Reproducible integration measurements. Never edits stocks, citizens, ranks,
## skills, condition or saved ledgers to manufacture a strategy or an outcome.
const Driver=preload("res://tools/integration_audit_driver.gd")
const Saves=preload("res://src/campaign_save.gd")
const View=preload("res://src/campaign_view.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Director=preload("res://src/core/battle_director.gd")
var r
var checks: int=0
var failures: int=0
var out_dir: String="/tmp/yenikapi-integration-audit"
var evidence: Dictionary={"progression":[],"incidents":[],"warfare":[],"legacy":[],"recovery":[]}
var town: Dictionary={}
var town_recipe: Array=[]
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func write(name_: String,value: Variant) -> void:
	FileAccess.open(out_dir.path_join(name_+".json"),FileAccess.WRITE).store_string(JSON.stringify(value,"  "))
func saved(s: Dictionary,name_: String) -> Dictionary:
	var path: String=out_dir.path_join(name_+"-save.json")
	check(Saves.write(path,s,r),name_+" atomic save")
	var loaded: Dictionary=Saves.read(path,r)
	check(loaded==s,name_+" exact resume")
	return loaded
func cmd(s: Dictionary,a: Dictionary,recipe: Array=[],errors: Array=[]) -> Dictionary:
	var before: int=errors.size();var result: Dictionary=Driver.command(r,s,a,recipe,errors)
	check(errors.size()==before,"public command accepted "+str(a.get("kind"))+" "+str(a.get("id","")))
	return result
func progression() -> void:
	var variants: Array=[{"id":"compact"},{"id":"outward","layout":"outward"},{"id":"mixed","layout":"mixed"},{"id":"reserve1","reserve":1},{"id":"reserve3","reserve":3},{"id":"prepare_off","prepare":false},{"id":"maintenance_off","maintenance":false},{"id":"welcome_off","welcome":false},{"id":"civic_only","facilities":false}]
	for options in variants:
		var result: Dictionary=Driver.trace(r,options,120 if options.id=="welcome_off" else 100)
		check(result.errors.is_empty() and result.valid,"all public progression commands valid "+options.id)
		check(Driver.replay(r,r.new_state(),result.commands)==result.state,"full ordinary recipe replay "+options.id)
		var s: Dictionary=result.state
		var unchanged: Dictionary=s.duplicate(true);var metrics: Dictionary=Driver.snapshot(r,s)
		check(s==unchanged,"all measurement queries pure "+options.id)
		var min_food: int=100000;var unfed: int=0
		for row in result.rows:min_food=mini(min_food,int(row.food));unfed+=int(row.unfed)
		var summary: Dictionary={"id":options.id,"options":options,"milestones":result.milestones,"final":metrics,"min_food":min_food,"unfed_forecast_total":unfed,"digest":result.digest}
		evidence.progression.append(summary)
		write(options.id+"-trace",{"commands":result.commands,"rows":result.rows,"summary":summary})
		saved(s,options.id)
		print("PROGRESSION ",options.id," large=",result.milestones.get("lifecycle_assembly",-1)," town=",result.milestones.get("town_civic",-1)," people=",metrics.people," food=",metrics.food," wood=",metrics.wood," places=",metrics.places," shaping=",metrics.shaping)
		if options.id=="compact":
			for entry in result.commands:
				if int(entry.turn)<60:town_recipe.append(entry)
			town=Driver.replay(r,r.new_state(),town_recipe)
			check(int(town.turn)==60 and r.lifecycle.stage(town,r)=="town","matched public town branch at season60")
		if options.id=="maintenance_off":
			var before: Dictionary=Driver.snapshot(r,s);var recipe: Array=[]
			s=cmd(s,{"kind":"asset_maintenance","id":"stores","enabled":true},recipe)
			for season in range(12):s=cmd(s,{"kind":"advance"},recipe)
			check(r.lifecycle.stage(s,r)=="town" and s.assets.conditions.stores>=r.assets.balance.condition_threshold,"ordinary store maintenance restores operations without losing rank")
			evidence.recovery.append({"id":"maintenance","before":before,"after":Driver.snapshot(r,s),"commands":recipe})
		if options.id=="prepare_off":
			var before: Dictionary=Driver.snapshot(r,s);var recipe: Array=[]
			s=cmd(s,{"kind":"living_order","id":"prepare","value":1},recipe)
			for season in range(10):s=cmd(s,{"kind":"advance"},recipe)
			check(Driver.shaping(s)>=int(r.lifecycle.balance.readiness.shaping),"ordinary preparation recovers the knowledge gate")
			evidence.recovery.append({"id":"preparation","before":before,"after":Driver.snapshot(r,s),"commands":recipe})
func legacy() -> void:
	var path: String="res://tools/fixtures/lifecycle-0.11-paid.json"
	var bytes: String=FileAccess.get_file_as_string(path);var s: Dictionary=Saves.read(path,r)
	check(not s.is_empty(),"actual frozen legacy paid save loads")
	var before: Dictionary=s.duplicate(true);var recipe: Array=[]
	for kind in ["lifecycle_town_begin","warfare_begin"]:s=cmd(s,{"kind":kind},recipe)
	for key in ["food","wood","queue","completed","citizens","households","living","land","assets","contacts"]:check(s[key]==before[key],"legacy adoption preserves "+key)
	check(FileAccess.get_file_as_string(path)==bytes,"frozen legacy fixture remains byte-identical")
	saved(s,"legacy-paid-adopted")
	evidence.legacy.append({"id":"frozen-paid","before_turn":before.turn,"queue":s.queue,"commands":recipe,"digest":Driver.digest(r,s)})
	# Reproduce the original tutorial route without activating later systems.
	s=r.new_state();recipe=[]
	for season in range(21):
		s=cmd(s,{"kind":"role","role":"god"},recipe)
		s=cmd(s,{"kind":"policy","welcome":true,"tight_rations":false},recipe)
		if s.queue.is_empty():
			for id in r.content.tutorial_projects:
				if r.has_project(s,id):continue
				var a: Dictionary=Driver.project_order(r,s,id)
				if not a.is_empty():s=cmd(s,a,recipe)
				break
		s=cmd(s,{"kind":"plan","plan":r.suggested_plan(s)},recipe)
		s=cmd(s,{"kind":"advance"},recipe)
	before=s.duplicate(true)
	for kind in ["asset_begin","land_begin","living_begin","lifecycle_begin","lifecycle_town_begin","warfare_begin"]:s=cmd(s,{"kind":kind},recipe)
	for key in ["food","wood","queue","completed","citizens","leaders"]:check(s[key]==before[key],"tutorial adoption preserves "+key)
	check(Driver.replay(r,r.new_state(),recipe)==s,"legacy tutorial adoption recipe replay")
	saved(s,"legacy-tutorial-adopted")
	evidence.legacy.append({"id":"tutorial","turn":s.turn,"stage":r.lifecycle.stage(s,r),"stocks":{"food":s.food,"wood":s.wood},"completed":s.completed,"digest":Driver.digest(r,s)})
	write("legacy-tutorial-recipe",recipe)
func incidents() -> void:
	for prepared in [false,true]:
		var s: Dictionary=town.duplicate(true);var recipe: Array=[];var errors: Array=[];var rows: Array=[]
		s=cmd(s,{"kind":"incident_begin"},recipe,errors)
		for season in range(45):
			s=Driver.incident_orders(r,s,prepared,recipe,errors)
			rows.append(Driver.snapshot(r,s))
			s=cmd(s,{"kind":"advance"},recipe,errors)
			check(r.validate_state(s),"incident continuing state validates")
			if s.incidents.records.size()==2 and s.incidents.records[-1].recovered>=0:break
		check(errors.is_empty(),"all incident preparation/recovery commands valid")
		check(s.incidents.records.size()==2 and s.incidents.records[-1].recovered>=0,"both incidents receive ordinary paid recovery")
		check(Driver.replay(r,town,recipe)==s,"incident ordinary recipe replay")
		for item in town.completed:check(item in s.completed,"incidents preserve paid town fabric")
		var id: String="prepared" if prepared else "neglected"
		saved(s,"incidents-"+id)
		var summary: Dictionary={"id":id,"records":s.incidents.records,"before":Driver.snapshot(r,town),"after":Driver.snapshot(r,s),"commands":recipe,"rows":rows}
		evidence.incidents.append(summary);write("incidents-"+id,summary)
		print("INCIDENT ",id," ",JSON.stringify(s.incidents.records))
func battlefield(s: Dictionary) -> Dictionary:
	var world=preload("res://src/village.gd").new();root.add_child(world)
	world.build(View.snapshot(Driver.Base.read("settlement"),s,r));world.set_meta("project_presentation",true)
	var view=View.new();root.add_child(view);view.refresh(s,r,world)
	var nav: Dictionary=Adapter.capture(world,r.defense)
	view.free();world.free()
	return nav
func warfare() -> void:
	var comparison_ids: Array=[]
	for options in [{"id":"untrained","equipped":false},{"id":"equipped","equipped":true},{"id":"fortified","equipped":true,"fortified":true},{"id":"neglected_fort","equipped":true,"fortified":true,"maintained":false}]:
		var s: Dictionary=town.duplicate(true);var recipe: Array=[];var errors: Array=[];var preparation_rows: Array=[]
		for season in range(40):
			s=Driver.battle_preparation(r,s,options,recipe,errors)
			preparation_rows.append(Driver.snapshot(r,s));s=cmd(s,{"kind":"advance"},recipe,errors)
		check(errors.is_empty() and r.validate_state(s),"ordinary battle preparation valid "+options.id)
		if not bool(options.get("maintained",true)):check(s.assets.conditions.watch<r.assets.balance.condition_threshold,"neglect actually crosses the defense maintenance threshold")
		# Pause optional workshop work through the same controls in every branch;
		# otherwise its current repair crew changes which named adults can muster.
		for a in [{"kind":"living_order","id":"prepare","value":0},{"kind":"living_order","id":"training","value":false},{"kind":"living_order","id":"repair","value":false}]:s=cmd(s,a,recipe,errors)
		s=cmd(s,{"kind":"warfare_muster","value":4},recipe,errors)
		check(Driver.replay(r,town,recipe)==s,"battle preparation exact recipe replay "+options.id)
		var preparation_recipe: Array=recipe.duplicate(true)
		var before: Dictionary=s.duplicate(true);var quote: Dictionary=r.defense.quote(s,r)
		if comparison_ids.is_empty():comparison_ids=quote.ids.duplicate()
		check(quote.ids==comparison_ids,"same named watch after common stop-work orders "+options.id)
		var nav: Dictionary=battlefield(s)
		s=cmd(s,{"kind":"defense_begin","nav":nav},recipe,errors)
		if not r.defense.locked(s):continue
		check(r.validate_state(s),"actual village battlefield and roster validate "+options.id)
		s=cmd(s,{"kind":"defense_mode","mode":"delegated"},recipe,errors)
		for action in Director.deployment_orders(s.defense.battle,r.defense.battle_tuning(s.defense.battle),r):s=cmd(s,action,recipe,errors)
		s=cmd(s,{"kind":"defense_start"},recipe,errors)
		var resumed: Dictionary={};var started: int=Time.get_ticks_msec()
		for tick in range(5000):
			r.defense.step(s.defense.battle,r)
			if tick==50:resumed=saved(s,"active-"+options.id)
			elif not resumed.is_empty():
				r.defense.step(resumed.defense.battle,r)
				check(resumed==s,"battle save/resume equivalence "+options.id)
			if s.defense.battle.phase=="ended":break
		check(s.defense.battle.phase=="ended","bounded battle "+options.id)
		var duration: int=Time.get_ticks_msec()-started
		var b: Dictionary=s.defense.battle.duplicate(true)
		saved(s,"pending-"+options.id)
		s=cmd(s,{"kind":"defense_commit"})
		check(r.command(s,{"kind":"defense_commit"}).has("error"),"aftermath applies exactly once "+options.id)
		for key in ["completed","queue","lifecycle","land","contacts"]:check(s[key]==before[key],"battle preserves town "+key)
		var accepted: Dictionary=s.duplicate(true)
		var after: Dictionary=Driver.snapshot(r,s);var recovery_rows: Array=[];var recovery_recipe: Array=[]
		for season in range(8):
			s=Driver.battle_preparation(r,s,{"equipped":true,"maintained":true},recovery_recipe,errors)
			s=cmd(s,{"kind":"warfare_muster","value":0},recovery_recipe,errors)
			var forecast: Dictionary=Driver.snapshot(r,s)
			s=cmd(s,{"kind":"advance"},recovery_recipe,errors)
			var row: Dictionary=Driver.snapshot(r,s);row.resolved_forecast=forecast;recovery_rows.append(row)
		check(r.validate_state(s) and s.defense.recovery.is_empty(),"ordinary care restores named residents "+options.id)
		check(Driver.replay(r,accepted,recovery_recipe)==s,"post-battle recovery exact recipe replay "+options.id)
		saved(s,"recovered-"+options.id)
		var summary: Dictionary={"id":options.id,"options":options,"quote":quote,"before":Driver.snapshot(r,before),"outcome":b.outcome,"reason":b.reason,"ticks":b.tick,"elapsed_with_resume_ms":duration,"report":s.defense.reports[-1],"after_acceptance":after,"after_recovery":Driver.snapshot(r,s),"preparation_rows":preparation_rows,"recovery_rows":recovery_rows,"commands":b.commands,"preparation_recipe":preparation_recipe,"recovery_recipe":recovery_recipe}
		evidence.warfare.append(summary);write("warfare-"+options.id,summary)
		print("WARFARE ",options.id," watch=",quote.count," kits=",quote.kits," readiness=",quote.readiness," watch_condition=",before.assets.conditions.watch," ",b.outcome,"/",b.reason," ticks=",b.tick," wounded=",s.defense.reports[-1].wounded.size())
func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir);r=Driver.rules()
	var fixture_digest: String=FileAccess.get_file_as_string("res://tools/fixtures/lifecycle-0.11-paid.json").sha256_text()
	progression();legacy();incidents();warfare()
	check(FileAccess.get_file_as_string("res://tools/fixtures/lifecycle-0.11-paid.json").sha256_text()==fixture_digest,"frozen paid fixture invariant after all runs")
	evidence.checks=checks;evidence.failures=failures;evidence.legacy_fixture_sha256=fixture_digest
	write("report",evidence)
	print("INTEGRATION AUDIT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
