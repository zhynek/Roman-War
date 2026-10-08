extends SceneTree
## Named consequences, finite treatment, paid repair, old saves and commit-once.
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const View=preload("res://src/campaign_view.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Saves=preload("res://src/campaign_save.gd")
var r
var checks: int=0
var failures: int=0
var save_path: String="/tmp/village-aftermath-"+str(OS.get_process_id())+".json"
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var result: Dictionary=r.command(s,a)
	check(result.has("state"),str(a)+" "+str(result.get("error","")))
	return result.get("state",s)
func roundtrip(s: Dictionary,label: String) -> Dictionary:
	check(Saves.write(save_path,s,r),label+" atomic write")
	var loaded: Dictionary=Saves.read(save_path,r)
	check(not loaded.is_empty() and loaded==s,label+" raw JSON validation and exact resume")
	return loaded
func treatment(f: Dictionary) -> int:
	for request in f.assets.requests:
		if request.id=="warfare_care":return int(request.filled)
	return 0
func severity(s: Dictionary) -> Dictionary:
	var n: Dictionary=s.duplicate(true);var b: Dictionary=n.defense.battle
	b.phase="ended";b.paused=true;b.outcome="defeat";b.reason="watch_lost";b.tick=10
	var index: int=0
	for f in b.groups:
		if f.side!="watch":continue
		if index==0:f.hp=0;f.hit_seq=2;f.attack_seq=1
		elif index==1:f.hp=int(f.initial)*int(r.defense.tuning.hp_per_person)-int(r.warfare.aftermath.tuning.mild_injury_hp_loss);f.hit_seq=1;f.attack_seq=1
		index+=1
	return n
func run() -> void:
	r=Driver.rules()
	var base: Dictionary=Living.at_season(r,12,true)
	# A separate paid, paused project must survive every battle consequence.
	base=cmd(base,{"kind":"commission","id":"care_shelter"})
	base=cmd(base,{"kind":"asset_project","id":"care_shelter","priority":1,"crew":1,"paused":true})
	base=r.advance(base).state
	check(base.living.kits==r.living.balance.kit_capacity,"ordinary paid repair prepares the full kit pool")
	var adopted: Dictionary=cmd(base,{"kind":"warfare_begin"})
	check(adopted.warfare.aftermath.people.is_empty() and adopted.warfare.aftermath.equipment_condition==100,"explicit adoption adds no experience or equipment")
	for key in ["citizens","completed","queue","wood","food","households","contacts","lifecycle"]:check(adopted[key]==base[key],"adoption preserves "+key)
	adopted=cmd(adopted,{"kind":"warfare_muster","value":4})
	var world=preload("res://src/village.gd").new();root.add_child(world)
	world.build(View.snapshot(Driver.read("settlement"),adopted,r));world.set_meta("project_presentation",true)
	var presentation=View.new();root.add_child(presentation);presentation.refresh(adopted,r,world)
	var nav: Dictionary=Adapter.capture(world,r.defense)
	var source: Dictionary=cmd(adopted,{"kind":"defense_begin","nav":nav})
	check(r.validate_state(source),"actual resident deployment valid")
	for key in ["skill","leadership","condition"]:
		var unsupported: Dictionary=source.duplicate(true)
		unsupported.defense.battle.groups[1 if key=="leadership" else 0].tactical[key]+=1 if key!="condition" else -1
		check(not r.validate_state(unsupported),"unsupported battle "+key+" rejected")
	var actual: Dictionary=source.duplicate(true)
	actual=cmd(actual,{"kind":"defense_mode","mode":"delegated"});r.defense.prepare_delegated(actual.defense.battle,r)
	actual=cmd(actual,{"kind":"defense_start"})
	for i in range(3101):
		r.defense.step(actual.defense.battle,r)
		if actual.defense.battle.phase=="ended":break
	check(actual.defense.battle.phase=="ended","actual battle ends before acceptance")
	var actual_before: Dictionary=actual.duplicate(true)
	var actual_preview: Dictionary=r.defense.outcome(actual.defense.battle,r)
	actual=cmd(actual,{"kind":"defense_commit"})
	check(r.validate_state(actual),"actual aftermath validates")
	check(actual.defense.reports.back().aftermath.participants.size()==r.defense.quote(adopted,r).count,"actual named participation complete")
	check(actual.defense.reports.back().wounded==actual_preview.wounded,"preview and accepted injury mapping agree")
	check(actual.citizens==actual_before.citizens,"actual combat does not delete or deactivate residents")
	roundtrip(actual,"actual accepted aftermath")
	# Controlled aggregate HP boundaries use the same adapter as actual battle.
	var ended: Dictionary=severity(source)
	check(r.validate_state(ended),"controlled severe pending outcome valid")
	var pending: Dictionary=roundtrip(ended,"ended awaiting acceptance")
	check(r.advance(ended).get("error")=="blocked","season remains locked until severe report accepted")
	for action in [{"kind":"warfare_care","enabled":false},{"kind":"warfare_muster","value":0},{"kind":"living_order","id":"repair","value":false}]:check(r.command(ended,action).get("error")=="blocked","unresolved battle locks "+action.kind)
	var preview: Dictionary=r.defense.outcome(ended.defense.battle,r)
	var cold: Dictionary=r.defense.outcome(ended.defense.battle,r)
	check(preview==cold and ended==pending,"outcome preview pure and deterministic")
	check(preview.wounded.size()==3,"two incapacitated and one wounded member need care")
	check(preview.kits==2 and preview.aftermath.condition_after==70,"actual lost kits and engaged equipment wear")
	var accepted: Dictionary=cmd(ended,{"kind":"defense_commit"})
	var resumed: Dictionary=cmd(pending,{"kind":"defense_commit"})
	check(accepted==resumed,"pending save commits identical consequences")
	check(r.validate_state(accepted),"severe accepted consequences validate")
	var report: Dictionary=accepted.defense.reports.back()
	check(report.aftermath.turn==ended.turn and report.aftermath.participants.size()==6,"report records actual season and all six named participants")
	var incapacitated: Array=[];var mild: Array=[];var untouched: Array=[]
	for row in report.aftermath.participants:
		check(row.name==r.person_by_id(ended,row.id).name and row.household==r.person_by_id(ended,row.id).household,"frozen name and household "+row.id)
		check(accepted.warfare.aftermath.people[row.id].battles==1,"participation exactly once "+row.id)
		if row.injury=="incapacitated":incapacitated.append(row.id);check(accepted.defense.recovery[row.id]==3,"incapacitation requires three treated seasons")
		elif row.injury=="wounded":mild.append(row.id);check(accepted.defense.recovery[row.id]==1,"minor injury requires one treated season")
		else:untouched.append(row.id)
		check(accepted.warfare.aftermath.people[row.id].experience==(1 if row.engaged else 0),"experience requires actual group engagement "+row.id)
	check(incapacitated.size()==2 and mild.size()==1 and untouched.size()==3,"stable group member allocation")
	check(accepted.living.kits==int(ended.living.kits)-2,"lost equipment deducted once")
	check(accepted.food==maxi(0,int(ended.food)-int(report.lost)),"supply loss deducted once")
	check(accepted.warfare.aftermath.equipment_condition==70,"pooled condition persists")
	for key in ["citizens","completed","queue","lifecycle","land","contacts"]:check(accepted[key]==ended[key],"acceptance preserves unrelated "+key)
	check(accepted.assets.initiatives==ended.assets.initiatives,"paid project responsibility preserved")
	for home in accepted.households.homes:
		var added: int=0
		for row in report.aftermath.participants:
			if row.household==home:added+=int(row.stress)
		check(int(accepted.households.homes[home].stress)==int(ended.households.homes[home].stress)+added,"bounded household strain "+home)
		check(accepted.households.homes[home].practice==ended.households.homes[home].practice,"household learning history retained "+home)
	check(r.command(accepted,{"kind":"defense_commit"}).has("error"),"second acceptance cannot spend or award again")
	var idempotent: Dictionary=accepted.duplicate(true);var same_report: Dictionary=idempotent.defense.reports.back()
	r.warfare.aftermath.accept(idempotent,ended,same_report,r)
	check(idempotent==accepted,"consequence helper itself is idempotent against same before state")
	roundtrip(accepted,"persistent injured households")
	for task in r.assignments(accepted,r.effective_plan(accepted)):check(task.id not in report.wounded,"recovering resident unavailable for ordinary workforce "+task.id)
	# Care is finite, allocated alongside food and paid crews, and requires food.
	var f: Dictionary=r.forecast(accepted)
	check(f.covered and treatment(f)>0 and int(f.plan.food)>0,"real finite treatment and food allocation")
	var limited: Dictionary=f.duplicate(true)
	for request in limited.assets.requests:
		if request.id=="warfare_care":request.filled=1
	var n: Dictionary=accepted.duplicate(true);r.warfare.aftermath.recover(n,accepted,limited,r)
	check(n.defense.recovery[incapacitated[0]]==2 and n.defense.recovery[incapacitated[1]]==2 and n.defense.recovery[mild[0]]==1,"one carer treats two severe patients without free overflow")
	limited.covered=false;n=accepted.duplicate(true);r.warfare.aftermath.recover(n,accepted,limited,r)
	check(n.defense.recovery==accepted.defense.recovery,"unfed treatment does not progress")
	var paused: Dictionary=cmd(accepted,{"kind":"warfare_care","enabled":false})
	check(treatment(r.forecast(paused))==0,"care toggle releases its finite workers")
	var advanced: Dictionary=r.advance(paused).state
	check(advanced.defense.recovery==paused.defense.recovery,"ordinary care alone does not invent dedicated treatment")
	var recovering: Dictionary=cmd(paused,{"kind":"warfare_care","enabled":true})
	recovering=cmd(recovering,{"kind":"warfare_muster","value":0})
	var report_frozen: Dictionary=report.duplicate(true)
	for i in range(5):
		if recovering.defense.recovery.is_empty():break
		var forecast: Dictionary=r.forecast(recovering);var result: Dictionary=r.advance(recovering)
		check(result.has("state"),"ordinary recovery season")
		if not result.has("state"):break
		recovering=result.state
		check(recovering.report==forecast and r.validate_state(recovering),"recovery forecast exact and save valid")
	check(recovering.defense.recovery.is_empty(),"finite ordinary treatment returns every survivor to work")
	check(recovering.defense.reports.back()==report_frozen,"historical participation persists after healing")
	for id in report.wounded:check(recovering.warfare.aftermath.people[id].injury=="none" and r.person_by_id(recovering,id).active,"named resident fully recovered "+id)
	check(recovering.queue==accepted.queue,"unrelated paused paid project survives recovery")
	roundtrip(recovering,"recovered village continuation")
	# Full kits can still be worn: ordinary repair spends existing wood/blanks.
	var worn: Dictionary=source.duplicate(true);var battle: Dictionary=worn.defense.battle
	battle.phase="ended";battle.paused=true;battle.outcome="victory";battle.reason="enemy_routed";battle.tick=10
	for group in battle.groups:
		if group.side=="watch":group.attack_seq=1
	worn=cmd(worn,{"kind":"defense_commit"})
	check(worn.living.kits==r.living.balance.kit_capacity and r.warfare.aftermath.needs_repair(worn),"damaged full kit pool requests repair")
	var repair_forecast: Dictionary=r.forecast(worn)
	check(repair_forecast.living.repaired==1 and repair_forecast.living.repair_wood>0,"repair uses actual labor and material forecast")
	var repaired: Dictionary=r.advance(worn).state
	check(repaired.warfare.aftermath.equipment_condition==100,"paid ordinary work restores pooled condition")
	check(repaired.living.blanks==int(worn.living.blanks)+int(repair_forecast.living.prepared)-1,"repair consumes an actual prepared blank")
	check(repaired.wood==int(worn.wood)+int(repair_forecast.wood)-int(repair_forecast.assets.repair_cost)-int(repair_forecast.living.fuel)-int(repair_forecast.living.prepare_wood)-int(repair_forecast.living.support)-int(repair_forecast.living.repair_wood),"repair wood reconciles with ordinary village accounts")
	var no_material: Dictionary=worn.duplicate(true);no_material.living.blanks=0
	check(r.forecast(no_material).living.repaired==0,"no free repair without prepared materials")
	var repair_off: Dictionary=cmd(worn,{"kind":"living_order","id":"repair","value":false})
	check(r.advance(repair_off).state.warfare.aftermath.equipment_condition==worn.warfare.aftermath.equipment_condition,"disabling paid repair preserves damage")
	# Legacy recovery is adopted without rewriting old reports or residents.
	var legacy: Dictionary=cmd(base,{"kind":"defense_begin","nav":nav})
	legacy.defense.battle.phase="ended";legacy.defense.battle.paused=true;legacy.defense.battle.outcome="defeat";legacy.defense.battle.reason="watch_lost"
	for group in legacy.defense.battle.groups:
		if group.side=="watch":group.hp=0
	legacy=cmd(legacy,{"kind":"defense_commit"})
	var old_report: Dictionary=legacy.defense.reports[0].duplicate(true)
	var upgraded: Dictionary=cmd(legacy,{"kind":"warfare_begin"})
	check(upgraded.defense==legacy.defense and upgraded.defense.reports[0]==old_report,"adoption retains legacy8 report and recovery contract")
	for id in legacy.defense.recovery:check(upgraded.warfare.aftermath.people[id].battles==0 and upgraded.warfare.aftermath.people[id].experience==0,"old wound creates no invented experience")
	roundtrip(upgraded,"legacy accepted battle adoption")
	var fixture: Dictionary=Saves.read("res://tools/fixtures/lifecycle-0.11-paid.json",r)
	check(not fixture.is_empty() and fixture.warfare.is_empty(),"older independent village still loads unadopted")
	# Natural lifecycle departure clears only work exclusion, retaining memory.
	var elder: Dictionary=accepted.duplicate(true);var departed: String=incapacitated[0]
	r.person_by_id(elder,departed).age=int(r.balance.death_age)-1
	var elder_before: Dictionary=elder.duplicate(true)
	var elder_result: Dictionary=r.advance(elder)
	check(elder_result.has("state"),"natural lifecycle can advance during recovery")
	if elder_result.has("state"):
		elder=elder_result.state
		check(not r.person_by_id(elder,departed).active and not elder.defense.recovery.has(departed),"natural death clears only workforce unavailability")
		check(elder.warfare.aftermath.people[departed].battles==elder_before.warfare.aftermath.people[departed].battles and elder.defense.reports==elder_before.defense.reports,"natural lifecycle retains participation and household history")
		check(r.validate_state(elder),"natural lifecycle and recovery remain compatible")
	# Public repeated warnings/acceptance accumulate only explicitly recorded
	# engagement experience. Controlled no-injury endings isolate progression.
	var experienced: Dictionary=cmd(worn,{"kind":"warfare_muster","value":4})
	experienced=cmd(experienced,{"kind":"warfare_threats"})
	for cycle in range(6):
		for season in range(50):
			if r.warfare.threats.ready(experienced,r):break
			experienced=Living.orders(r,experienced,true)
			var next: Dictionary=r.advance(experienced)
			check(next.has("state"),"ordinary development before experience cycle")
			if not next.has("state"):break
			experienced=next.state
		check(r.warfare.threats.ready(experienced,r),"later warning becomes ready after recovery interval")
		experienced=cmd(experienced,{"kind":"defense_begin","nav":nav})
		var next_battle: Dictionary=experienced.defense.battle
		for group in next_battle.groups:
			if group.side=="watch":group.attack_seq=1
		next_battle.phase="ended";next_battle.paused=true;next_battle.outcome="victory";next_battle.reason="enemy_routed";next_battle.tick=10
		experienced=cmd(experienced,{"kind":"defense_commit"})
		check(r.validate_state(experienced),"history-derived experience validates across encounter cycles")
	var developed: bool=false
	for id in experienced.warfare.aftermath.people:
		var record: Dictionary=experienced.warfare.aftermath.people[id]
		var expected: int=mini(int(r.defense.tactical_tuning.max_skill),int(r.person_by_id(experienced,id).watch)+int(record.experience)/int(r.warfare.aftermath.tuning.experience_per_skill))
		check(r.warfare.aftermath.skill(experienced,id,r)==expected,"defined aptitude plus earned experience "+id)
		developed=developed or int(record.experience)>=int(r.warfare.aftermath.tuning.experience_per_skill)
	check(developed,"rotating actual watch eventually earns a bounded skill increment across repeat encounters")
	roundtrip(experienced,"multiple participation records and skill progress")
	# Corruption cannot manufacture skill, duplicate casualties or hide rows.
	for key in ["people","care","equipment_condition"]:
		var bad: Dictionary=accepted.duplicate(true);bad.warfare.aftermath[key]=[]
		check(not r.validate_state(bad),"malformed aftermath "+key)
	for value in [null,[],{"reports":null},{"recovery":[]}]:
		var bad: Dictionary=adopted.duplicate(true);bad.defense=value
		check(not r.validate_state(bad),"malformed defense rejected before aftermath access")
	var sample: String=report.aftermath.participants[0].id
	var bad: Dictionary=accepted.duplicate(true);bad.warfare.aftermath.people[sample].experience+=1;check(not r.validate_state(bad),"unearned experience rejected against history")
	bad=accepted.duplicate(true);bad.warfare.aftermath.people.erase(sample);check(not r.validate_state(bad),"missing participation ledger rejected")
	bad=accepted.duplicate(true);bad.defense.reports[0].wounded.append(sample);check(not r.validate_state(bad),"duplicate casualty rejected")
	bad=accepted.duplicate(true);bad.defense.reports[0].aftermath.participants.append(bad.defense.reports[0].aftermath.participants[0].duplicate(true));check(not r.validate_state(bad),"duplicate named participant rejected")
	bad=accepted.duplicate(true);bad.defense.reports[0].aftermath.condition_after+=1;check(not r.validate_state(bad),"unreconciled condition report rejected")
	bad=accepted.duplicate(true);bad.defense.reports.append(bad.defense.reports[0].duplicate(true));check(not r.validate_state(bad),"repeated encounter serial rejected")
	print("AFTERMATH CHECKS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
