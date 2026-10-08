extends SceneTree
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const Neighbor=preload("res://tools/neighbor_driver.gd")
const View=preload("res://src/campaign_view.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Saves=preload("res://src/campaign_save.gd")
var r
var threats
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
func clock_step(s: Dictionary) -> Dictionary:
	# Scheduler unit fixture: ordinary-world stepping is verified separately below.
	var n: Dictionary=s.duplicate(true);n.turn+=1
	threats.advance(n,s,{},r)
	return n
func run() -> void:
	r=Driver.rules();threats=r.warfare.threats
	var base: Dictionary=Living.at_season(r,12,true)
	check(not threats.enabled(base),"older villages have no recurring threat frequency")
	base=cmd(base,{"kind":"warfare_begin"})
	check(base.warfare.threats.is_empty() and not threats.enabled(base),"warfare adoption alone does not enable threats")
	var s:=cmd(base,{"kind":"warfare_threats"})
	check(r.validate_state(s) and threats.validate(s,r),"explicit activation validates")
	check(threats.begin(s,r).has("error"),"duplicate activation rejected")
	for key in base:
		if key!="warfare":check(s[key]==base[key],"activation preserves "+key)
	var start: int=int(s.turn)
	for season in range(1,9):
		s=clock_step(s)
		check(s.food==base.food and s.wood==base.wood,"scheduler never charges stocks")
		check(s.warfare.threats.pending.is_empty()==(season<8),"eight full quiet seasons before warning "+str(season))
	check(s.warfare.threats.pending.announced==start+8 and s.warfare.threats.pending.due==start+10,"two full seasons warning")
	check(not threats.ready(s,r),"warning start not ready")
	var repeated: Dictionary=s.duplicate(true);threats.advance(repeated,base,{},r)
	check(repeated==s,"repeated or nonsequential seasonal hook does not duplicate warning")
	s=clock_step(s);check(not threats.ready(s,r),"one warning season remains")
	s=clock_step(s);check(threats.ready(s,r),"ready after two complete seasons")
	var frozen: Dictionary=s.duplicate(true)
	for i in range(10):check(threats.ready(s,r) and threats.spec(s).id=="stores","pure readiness and specification")
	check(s==frozen,"queries do not advance state")
	for reason in ["food","recovery","incident"]:
		var deferred: Dictionary=s.duplicate(true)
		if reason=="food":deferred.food=0
		if reason=="recovery":deferred.defense={"recovery":{"resident":1}}
		if reason=="incident":deferred.incidents={"records":[{"id":"test","recovered":-1,"outcome":{},"warning":0,"known":0}]}
		check(threats.reason(deferred,r)=="threat_"+reason and not threats.ready(deferred,r),"defers mature warning for "+reason)
		var prior: Dictionary=deferred.warfare.threats.pending.duplicate(true)
		deferred=clock_step(deferred)
		check(deferred.warfare.threats.pending==prior,"deferral keeps pending stakes and serial")
	var sped_up: Dictionary=s.duplicate(true);sped_up.warfare.threats.next_turn-=1
	check(not threats.validate(sped_up,r),"shortened quiet interval rejected")
	var false_acceptance: Dictionary=s.duplicate(true);false_acceptance.warfare.threats.last_accepted=s.turn
	check(not threats.validate(false_acceptance,r),"invented acceptance clock rejected")
	for value in [null,[],1,{"version":1}]:
		var bad: Dictionary=s.duplicate(true);bad.warfare.threats=value
		check(not threats.validate(bad,r),"malformed scheduler rejected "+str(value))
	for key in ["cycle","next_turn","last_turn","started"]:
		var bad: Dictionary=s.duplicate(true);bad.warfare.threats[key]=-1
		check(not threats.validate(bad,r),"bad scheduler clock "+key)
	for key in ["serial","announced","due","id","contact"]:
		var bad: Dictionary=s.duplicate(true);bad.warfare.threats.pending[key]=null
		check(not threats.validate(bad,r),"bad warning "+key)
	for value in [null,[],1,{"reports":null},{"reports":{}}]:
		var bad: Dictionary=s.duplicate(true);bad.defense=value
		check(not threats.validate(bad,r) and not r.validate_state(bad),"malformed defense before defense validation")
	var phantom: Dictionary=s.duplicate(true);phantom.warfare.threats.pending.contact="invented";phantom.warfare.threats.pending.due+=1
	check(not threats.validate(phantom,r),"no invented contact bonus")
	var neighbor: Dictionary=Neighbor.foundation(r)
	for i in range(8):
		neighbor=Neighbor.orders(r,neighbor)
		neighbor=r.advance(neighbor).state
		if not threats._contact(neighbor,r).is_empty():break
	check(not threats._contact(neighbor,r).is_empty(),"actual completed trade or aid provides contact adapter")
	var informed: Dictionary=base.duplicate(true);informed.contacts=neighbor.contacts.duplicate(true)
	informed=threats.begin(informed,r).state
	for i in range(8):informed=clock_step(informed)
	check(not informed.warfare.threats.pending.contact.is_empty() and informed.warfare.threats.pending.due-informed.turn==3,"friendly completed contact gives one additional warning season")
	check(threats.validate(informed,r),"contact-backed warning validates")
	var never_traded: Dictionary=informed.duplicate(true)
	for local in never_traded.contacts.neighbors.values():local.trades=0;local.aid=0
	check(threats._contact(never_traded,r).is_empty() and not threats.validate(never_traded,r),"initial friendly trust alone does not manufacture intelligence")
	var horizon: Dictionary=base.duplicate(true);horizon.turn=int(r.balance.max_turns)-5
	check(threats.begin(horizon,r).get("error")=="threat_horizon","no warning truncated at chapter horizon")
	# Real seasonal advances, mobilization, delegated combat, acceptance and recovery.
	s=cmd(base,{"kind":"warfare_threats"})
	var world=preload("res://src/village.gd").new();root.add_child(world)
	world.build(View.snapshot(Driver.read("settlement"),s,r))
	var presentation=View.new();root.add_child(presentation);world.set_meta("project_presentation",true);presentation.refresh(s,r,world)
	var nav: Dictionary=Adapter.capture(world,r.defense)
	var path: String="/tmp/village-threat-check.json"
	for cycle in range(3):
		var seasons: int=0
		while not threats.ready(s,r) and seasons<30:
			var next: Dictionary=r.advance(Living.orders(r,s,true))
			check(next.has("state"),"ordinary life until next warning")
			if not next.has("state"):break
			s=next.state;seasons+=1
			check(r.validate_state(s),"seasonal scheduler state validates")
		check(threats.ready(s,r),"cycle ready "+str(cycle))
		if not threats.ready(s,r):break
		check(threats.spec(s).id==["stores","landing","probe"][cycle],"three different objective cycle")
		check(r.advance(s).get("error")=="threat_ready","mature warning blocks conflicting seasonal changes")
		check(Saves.write(path,s,r) and Saves.read(path,r)==s,"warning save/resume")
		s=cmd(s,{"kind":"defense_begin","nav":nav})
		if not r.defense.locked(s):break
		s=cmd(s,{"kind":"defense_mode","mode":"delegated"});s=cmd(s,{"kind":"defense_start"})
		for tick in range(int(r.defense.tuning.limit_ticks)+1):
			r.defense.step(s.defense.battle,r)
			if s.defense.battle.phase=="ended":break
		check(s.defense.battle.phase=="ended" and r.validate_state(s),"bounded scheduled encounter")
		check(Saves.write(path,s,r) and Saves.read(path,r)==s,"ended scheduled battle awaiting acceptance resumes")
		var ended: Dictionary=s.duplicate(true)
		s=cmd(s,{"kind":"defense_commit"})
		check(s.warfare.threats.cycle==cycle+1 and s.warfare.threats.pending.is_empty(),"acceptance advances cycle once")
		check(s.warfare.threats.next_turn==s.turn+8 and r.validate_state(s),"eight-season recovery interval and valid accepted state")
		var accepted: Dictionary=s.duplicate(true);threats.accepted(s,ended,{},r)
		check(s==accepted and r.command(s,{"kind":"defense_commit"}).has("error"),"duplicate acceptance cannot advance or apply consequences")
		print("THREAT CYCLE ",cycle+1," turn=",s.turn," outcome=",s.defense.reports[-1].outcome," next=",s.warfare.threats.next_turn)
	check(s.warfare.threats.cycle==3,"three full recurring encounters accepted")
	check(Saves.write(path,s,r) and Saves.read(path,r)==s,"accepted recurring history save/resume")
	check(r.advance(s).has("state"),"ordinary village continues after third encounter")
	world.free();presentation.free()
	print("VILLAGE THREATS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
