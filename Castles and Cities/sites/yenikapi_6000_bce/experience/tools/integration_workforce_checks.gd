extends SceneTree
## The combined civic/watch allocator and honest factor presentation, without rebalance.
const Town=preload("res://tools/town_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const Saves=preload("res://src/campaign_save.gd")
var r
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var out: Dictionary=r.command(s,a)
	check(out.has("state"),str(a)+": "+str(out.get("error","")))
	return out.get("state",s)
func amount(f: Dictionary,id: String) -> int:
	for row in f.factors.security:
		if row.id==id:return int(row.value)
	return 0
func request(f: Dictionary,id: String) -> Dictionary:
	for row in f.assets.requests:
		if row.id==id:return row
	return {"filled":0,"wanted":0,"priority":-1}
func verify(s: Dictionary,label: String) -> void:
	var before: Dictionary=s.duplicate(true)
	var f: Dictionary=r.forecast(s)
	var training: int=int(request(f,"living_training").filled)
	var muster: int=int(request(f,"warfare_muster").filled)
	var old_watch: int=(int(f.plan.watch)-int(f.crew.escorts))*int(r.balance.security_worker)
	check(amount(f,"watch")+amount(f,"living_training")+amount(f,"warfare_muster")==old_watch,label+" split preserves security total")
	check(amount(f,"living_training")==training*int(r.balance.security_worker),label+" practice names exactly its allocated adults")
	check(amount(f,"warfare_muster")==muster*int(r.balance.security_worker),label+" extra watch names exactly its allocated adults")
	var unique: Dictionary={};var jobs: Dictionary={"food":0,"timber":0,"care":0,"watch":0,"building":0}
	var candidate_ids: Array=r.defense.candidates(s,r)
	for task in r.assignments(s,f.plan):
		check(not unique.has(task.id),label+" no double assignment "+task.id)
		unique[task.id]=true
		if jobs.has(task.job):jobs[task.job]+=1
		if task.get("duty","") in ["lifecycle_civic","town_service","care","warfare_care"]:check(task.id not in candidate_ids,label+" civic/care adult cannot mobilize")
	check(unique.size()==r.people(s,true).size(),label+" entire available adult pool assigned once")
	check(jobs==f.plan,label+" job totals equal named assignments")
	check(s==before,label+" forecast and assignment queries are pure")
	if r.lifecycle.town_active(s):
		check(request(f,"lifecycle_civic").priority==6,label+" town duty retains priority six")
		check(request(f,"town_service").priority==7,label+" provision service retains priority seven")
		var civic: int=int(request(f,"lifecycle_civic").filled)+int(request(f,"town_service").filled)
		for stat in ["wellbeing","cooperation"]:
			var care_value: int=0;var civic_value: int=0
			for row in f.factors[stat]:
				if row.id=="care":care_value=int(row.value)
				elif row.id=="civic":civic_value=int(row.value)
			check(civic_value==civic*int(r.balance[stat+"_care"]),label+" civic contribution named "+stat)
			check(care_value+civic_value==int(f.plan.care)*int(r.balance[stat+"_care"]),label+" civic social total unchanged "+stat)
func run() -> void:
	r=Town.rules()
	var no_lifecycle: Dictionary=cmd(Living.at_season(r,12,true),{"kind":"warfare_begin"})
	check(not r.lifecycle.active(no_lifecycle) and r.warfare.active(no_lifecycle),"warfare works without city lifecycle")
	verify(no_lifecycle,"independent warfare")
	var trace: Dictionary=Town.town_trace(r,true,60)
	check(not trace.has("error"),"public-command Town progression succeeds")
	var base: Dictionary=cmd(trace.state,{"kind":"warfare_begin"})
	check(r.lifecycle.stage(base,r)=="town", "earned Town preserved on warfare adoption")
	for training in [false,true]:
		for extra in [0,2,4]:
			var s:=cmd(base,{"kind":"living_order","id":"training","value":training})
			s=cmd(s,{"kind":"warfare_muster","value":extra})
			verify(s,"training="+str(training)+" muster="+str(extra))
			var next: Dictionary=r.advance(s)
			check(next.has("state") and r.validate_state(next.get("state",{})),"split-factor report validates after season")
			var path: String="/tmp/village-integration-workforce-"+str(OS.get_process_id())+".json"
			check(Saves.write(path,next.state,r) and Saves.read(path,r)==next.state,"split-factor report saves and resumes exactly")
	# A paid crew shares the pool with civic duty, service, training and additional watch.
	var working:=cmd(base,{"kind":"commission","id":"warfare_store_screen"})
	working=cmd(working,{"kind":"asset_project","id":"warfare_store_screen","priority":1,"crew":8,"paused":false})
	working=cmd(working,{"kind":"living_order","id":"training","value":true})
	working=cmd(working,{"kind":"warfare_muster","value":4})
	verify(working,"paid work competes with civic and watch")
	var f: Dictionary=r.forecast(working)
	check(request(f,"warfare_muster").priority==4 and request(f,"living_training").priority==4,"watch practice and extra watch retain explicit priority four")
	check(int(f.assets.projects.warfare_store_screen.crew)+int(f.plan.watch)+int(f.plan.care)+int(f.plan.food)+int(f.plan.timber)<=r.people(working,true).size(),"paid crew cannot create extra adults")
	# JSON profile validation rejects unsupported extra labor rather than backfilling it.
	for invalid in [-1,5,"4",true]:
		var bad: Dictionary=working.duplicate(true);bad.warfare.muster=invalid
		check(not r.validate_state(bad),"malformed additional watch rejected "+str(invalid))
	print("CITY WARFARE WORKFORCE: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
