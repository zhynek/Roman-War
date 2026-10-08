extends SceneTree
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const View=preload("res://src/campaign_view.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Sim=preload("res://src/core/defense_sim.gd")
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
func rejected_save(state: Dictionary,label: String) -> void:
	check(not r.validate_state(state),label+" state rejected")
	var path: String="/tmp/village-warfare-corrupt-"+str(OS.get_process_id())+".json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"format":"yenikapi_seasons","version":10,"state":state}))
	check(Saves.read(path,r).is_empty(),label+" raw save rejected")
func mobilization_integrity(base: Dictionary,nav: Dictionary) -> void:
	var prepared: Dictionary=cmd(cmd(base,{"kind":"warfare_begin"}),{"kind":"warfare_muster","value":4})
	var source: Dictionary=cmd(prepared,{"kind":"defense_begin","nav":nav})
	check(r.validate_state(source),"six-person original allocation validates")
	var bad: Dictionary=source.duplicate(true);bad.defense.battle.tactics.enemy_initial_hp=1000000
	rejected_save(bad,"forged immediate enemy retreat denominator")
	for place in source.defense.battle.nav.places:
		bad=source.duplicate(true)
		var destination: Array=bad.defense.battle.nav.places.refuge if place!="refuge" else bad.defense.battle.nav.places.stores
		bad.defense.battle.nav.places[place]=destination.duplicate()
		if place=="stores":bad.defense.battle.tactics.objective=destination.duplicate()
		check(bad.defense.battle.nav.signature==source.defense.battle.nav.signature,"place mutation leaves terrain signature unchanged")
		rejected_save(bad,"relocated authored "+place)
		check(r.command(prepared,{"kind":"defense_begin","nav":bad.defense.battle.nav}).has("error"),"mobilization rejects relocated "+place)
	bad=source.duplicate(true);bad.defense.battle.deploy_limit-=100
	rejected_save(bad,"expanded deployment beyond authored boundary")
	bad=source.duplicate(true);bad.defense.battle.groups[2].kits+=1
	rejected_save(bad,"equipment beyond actual kit pool")
	bad=source.duplicate(true);bad.defense.battle.groups[0].kits-=1;bad.defense.battle.groups[2].kits+=1
	rejected_save(bad,"equipment moved between original formations")
	bad=source.duplicate(true);bad.defense.battle.groups[0].readiness-=1
	rejected_save(bad,"readiness diverges from continuing village")
	bad=source.duplicate(true);bad.defense.battle.cost=0
	rejected_save(bad,"missing paid mobilization cost")
	bad=source.duplicate(true);bad.defense.battle.groups[0].tactical.initial_morale-=1
	rejected_save(bad,"unsupported original watch morale")
	for key in ["kits","readiness"]:
		bad=source.duplicate(true);bad.defense.battle.groups[-1][key]=1
		rejected_save(bad,"unsupported raider "+key)
	for key in ["skill","leadership"]:
		bad=source.duplicate(true);bad.defense.battle.groups[-1].tactical[key]=1
		rejected_save(bad,"unsupported raider "+key)
	bad=source.duplicate(true);bad.defense.battle.groups[-1].initial+=1;bad.defense.battle.groups[-1].members.append("raider_extra")
	bad.defense.battle.tactics.enemy_initial_hp+=int(r.defense.tuning.hp_per_person)
	rejected_save(bad,"extra hostile roster and matching forged denominator")
	var participants: Array=[]
	for group in source.defense.battle.groups:
		if group.side=="watch":participants.append_array(group.members)
	for person in r.people(prepared,true):
		if person.id in participants:continue
		bad=source.duplicate(true);var group: Dictionary=bad.defense.battle.groups[0]
		group.members[0]=person.id
		var skill: int=0;var leadership: int=0
		for id in group.members:
			skill+=r.warfare.aftermath.skill(bad,id,r)
			if id==bad.leaders.watch.id:leadership=mini(4,int(r.person_by_id(bad,id).watch))
		group.tactical.skill=skill/group.members.size();group.tactical.leadership=leadership
		rejected_save(bad,"unallocated adult substituted with valid aptitude")
		break
	# Existing wrapper9 state is outside the explicitly adopted validation.
	var legacy: Dictionary=cmd(base,{"kind":"defense_begin","nav":nav})
	var legacy_path: String="/tmp/village-warfare-legacy-"+str(OS.get_process_id())+".json"
	check(Saves.write(legacy_path,legacy,r) and Saves.read(legacy_path,r)==legacy,"legacy active battle keeps its original save contract")
func run() -> void:
	r=Driver.rules()
	var base: Dictionary=Living.at_season(r,12,true)
	var older: Dictionary=base.duplicate(true);older.erase("warfare")
	r.ensure_state_keys(older)
	check(older==base and r.validate_state(older),"older village receives inactive extension only")
	var world=preload("res://src/village.gd").new();root.add_child(world)
	world.build(View.snapshot(Driver.read("settlement"),base,r))
	var presentation=View.new();root.add_child(presentation);world.set_meta("project_presentation",true);presentation.refresh(base,r,world)
	var nav: Dictionary=Adapter.capture(world,r.defense)
	mobilization_integrity(base,nav)
	var legacy:=cmd(base,{"kind":"defense_begin","nav":nav})
	check(not legacy.defense.battle.has("tactics"),"old defense profile retains original battle")
	check(r.command(legacy,{"kind":"warfare_begin"}).has("error"),"no adoption during unresolved legacy battle")
	var s:=cmd(base,{"kind":"warfare_begin"})
	check(r.validate_state(s),"adoption valid without a defense battle")
	for key in base:
		if key not in ["warfare","history"]:check(s[key]==base[key],"adoption preserves "+key)
	var path: String="/tmp/village-warfare-check.json"
	check(Saves.write(path,s,r) and Saves.read(path,r)==s,"preparation wrapper10 roundtrip")
	var wrapper: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(wrapper.version==10,"adopted wrapper10")
	s=cmd(s,{"kind":"defense_begin","nav":nav})
	check(r.validate_state(s) and s.defense.battle.has("tactics"),"tactical mobilization validates")
	var ids: Array=[]
	for f in s.defense.battle.groups:
		if f.side=="watch":ids.append(f.id)
	s=cmd(s,{"kind":"defense_order","order":"width","width":1,"ids":ids})
	s=cmd(s,{"kind":"defense_order","order":"defend","at":nav.places.stores,"ids":ids})
	check(Saves.write(path,s,r) and Saves.read(path,r)==s,"deployment roundtrip")
	s=cmd(s,{"kind":"defense_start"})
	for i in range(125):Sim.tick(s.defense.battle,r.defense.battle_tuning(s.defense.battle))
	check(r.validate_state(s),"live tactical fields validate")
	check(Saves.write(path,s,r),"active tactical save")
	var loaded: Dictionary=Saves.read(path,r)
	if loaded.is_empty() or not r.defense.locked(loaded):quit(1);return
	for i in range(3100):
		Sim.tick(s.defense.battle,r.defense.battle_tuning(s.defense.battle))
		Sim.tick(loaded.defense.battle,r.defense.battle_tuning(loaded.defense.battle))
		check(s==loaded,"exact tactical replay "+str(i))
		if s.defense.battle.phase=="ended":break
	check(s.defense.battle.phase=="ended" and r.validate_state(s),"bounded ended tactical battle validates")
	check(Saves.write(path,s,r) and Saves.read(path,r)==s,"pending outcome persists")
	print("TACTICAL OUTCOME ",r.defense.outcome(s.defense.battle))
	s=cmd(s,{"kind":"defense_commit"})
	check(r.validate_state(s),"accepted tactical outcome validates")
	check(r.command(s,{"kind":"defense_commit"}).has("error"),"commit once")
	check(r.advance(s).has("state"),"ordinary life continues")
	for value in [null,1,[],{"version":1},{"profile":"bad"}]:
		var bad: Dictionary=base.duplicate(true);bad.warfare=value
		check(not r.validate_state(bad),"malformed warfare safely rejected")
	print("VILLAGE WARFARE: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
