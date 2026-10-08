extends SceneTree
## Public finite-labor muster orders, existing residents and paid-work tradeoffs.
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const View=preload("res://src/campaign_view.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Saves=preload("res://src/campaign_save.gd")
var r
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var result: Dictionary=r.command(s,a)
	check(result.has("state"),str(a)+": "+str(result.get("error","")))
	return result.get("state",s)
func request(s: Dictionary,id: String) -> Dictionary:
	for item in r.assets.allocation(s,r).requests:
		if item.id==id:return item
	return {"filled":0,"wanted":0}
func finite(s: Dictionary,label: String) -> void:
	var ids: Dictionary={};var extra: int=0;var all_watch: Array=[]
	for task in r.assignments(s,r.effective_plan(s)):
		check(not ids.has(task.id),label+" named resident assigned once "+task.id);ids[task.id]=true
		var person: Dictionary=r.person_by_id(s,task.id)
		check(not person.is_empty() and int(person.age)>=int(r.balance.adult_age),label+" actual adult "+task.id)
		if task.get("duty","")=="warfare_muster":extra+=1;check(task.job=="watch",label+" additional duty is actual watch")
		if task.job=="watch":all_watch.append(task.id)
	check(ids.size()<=r.people(s,true).size(),label+" workforce remains finite")
	check(extra==int(request(s,"warfare_muster").filled) and extra<=int(s.warfare.muster),label+" requests equal named allocation")
	for id in r.defense.candidates(s,r):check(id in all_watch,label+" mobilization uses an actual watch assignment")
func run() -> void:
	r=Driver.rules()
	var base: Dictionary=Living.at_season(r,12,true)
	check(r.command(base,{"kind":"warfare_muster","value":4}).has("error"),"additional watch requires explicit warfare adoption")
	base=cmd(base,{"kind":"warfare_begin"})
	check(base.warfare.muster==0 and request(base,"warfare_muster").filled==0,"adoption grants no extra workers")
	var baseline: Dictionary=r.defense.quote(base,r)
	var s: Dictionary=base
	var path: String="/tmp/village-muster-check.json"
	for value in [0,2,4]:
		s=cmd(base,{"kind":"warfare_muster","value":value})
		check(s.warfare.muster==value and r.validate_state(s),"saved requested muster "+str(value))
		finite(s,"muster "+str(value))
		for key in ["citizens","food","wood","turn","completed","queue","contacts","households","lifecycle"]:check(s[key]==base[key],"muster grants or spends nothing: "+key)
		check(s.living.kits==base.living.kits and s.living.readiness==base.living.readiness,"additional watch creates no equipment or training")
		for duty in ["food","care","refuge"]:check(request(s,duty).filled==request(base,duty).filled,"essential allocation preserved: "+duty)
		check(Saves.write(path,s,r) and Saves.read(path,r)==s,"preparation muster save/resume "+str(value))
		print("MUSTER requested=",value," assigned=",request(s,"warfare_muster").filled," mobilizable=",r.defense.quote(s,r).count," adults=",r.people(s,true).size())
	check(r.defense.quote(s,r).count>=4 and r.defense.quote(s,r).count>baseline.count,"real additional watch makes at least four residents mobilizable")
	for value in [-1,5,1.5,null,"4",true]:check(r.command(base,{"kind":"warfare_muster","value":value}).has("error"),"invalid muster value refused "+str(value))
	for value in [-1,5,null,{},true]:
		var bad: Dictionary=s.duplicate(true);bad.warfare.muster=value
		check(not r.validate_state(bad),"invalid saved muster refused "+str(value))
	# An oversized ordinary paid crew makes its competition with the muster visible.
	var paid: Dictionary=base.duplicate(true)
	for i in range(12):
		if r.quote(paid,{"kind":"commission","id":"warfare_store_screen"}).has("state"):break
		paid=r.advance(Living.orders(r,paid,true)).state
	paid=cmd(paid,{"kind":"commission","id":"warfare_store_screen"})
	paid=cmd(paid,{"kind":"asset_project","id":"warfare_store_screen","priority":2,"crew":8,"paused":false})
	var working: Dictionary=r.assets.allocation(paid,r)
	var prepared:=cmd(paid,{"kind":"warfare_muster","value":4})
	var diverted: Dictionary=r.assets.allocation(prepared,r)
	finite(prepared,"paid work and muster")
	check(prepared.queue==paid.queue and prepared.wood==paid.wood,"muster preserves paid commitment and progress")
	check(int(diverted.projects.warfare_store_screen.crew)<=int(working.projects.warfare_store_screen.crew),"extra watch cannot manufacture a parallel building crew")
	var reduced: bool=false
	for prior in working.requests:
		if prior.id!="warfare_muster" and int(request(prepared,prior.id).filled)<int(prior.filled):reduced=true
	check(reduced,"additional watch displaces finite ordinary work")
	check(int(diverted.plan.food)>0 and int(diverted.plan.care)>0,"food and care retain real workers beside paid work")
	print("MUSTER PAID WORK crew before=",working.projects.warfare_store_screen.crew," after=",diverted.projects.warfare_store_screen.crew," extra=",request(prepared,"warfare_muster").filled)
	var next: Dictionary=r.advance(prepared)
	check(next.has("state") and r.validate_state(next.get("state",{})),"ordinary seasonal work with muster validates")
	if next.has("state"):check(Saves.write(path,next.state,r) and Saves.read(path,r)==next.state,"paid work and muster report resumes")
	var world=preload("res://src/village.gd").new();root.add_child(world)
	world.build(View.snapshot(Driver.read("settlement"),s,r))
	var presentation=View.new();root.add_child(presentation);world.set_meta("project_presentation",true);presentation.refresh(s,r,world)
	var nav: Dictionary=Adapter.capture(world,r.defense)
	var battle:=cmd(s,{"kind":"defense_begin","nav":nav})
	check(r.defense.locked(battle),"additional actual watch mobilizes")
	if r.defense.locked(battle):
		var named: Array=[]
		for group in battle.defense.battle.groups:
			if group.side=="watch":named.append_array(group.members)
		named.sort();var quoted: Array=r.defense.candidates(s,r);quoted.sort()
		check(named==quoted and named.size()>=4,"battle contains exact paid-duty resident roster")
		check(int(s.food)-int(battle.food)==named.size()*int(r.defense.tuning.rations_per_person),"each mobilized resident pays ordinary ration cost")
		check(r.command(battle,{"kind":"warfare_muster","value":0}).get("error")=="blocked","unresolved deployment rejects workforce changes")
		check(Saves.write(path,battle,r) and Saves.read(path,r)==battle,"muster deployment saves exact assignments and roster")
		battle=cmd(battle,{"kind":"defense_start"})
		check(r.command(battle,{"kind":"warfare_muster","value":2}).get("error")=="blocked","live battle rejects workforce changes")
	var released:=cmd(s,{"kind":"warfare_muster","value":0})
	check(r.defense.quote(released,r).count==baseline.count and request(released,"warfare_muster").filled==0,"release returns adults to ordinary allocator")
	world.free();presentation.free()
	print("VILLAGE MUSTER: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
