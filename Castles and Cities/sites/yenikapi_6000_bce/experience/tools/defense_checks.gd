extends SceneTree
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const View=preload("res://src/campaign_view.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Nav=preload("res://src/core/defense_navigation.gd")
const Sim=preload("res://src/core/defense_sim.gd")
const Saves=preload("res://src/campaign_save.gd")
const Host=preload("res://src/defense_host.gd")
var r
var failures: int=0
var checks: int=0
var nav: Dictionary
var world
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var result: Dictionary=r.command(s,a);check(result.has("state"),str(a.get("kind"))+": "+str(result.get("error","")));return result.get("state",s)
func run() -> void:
	r=Driver.rules()
	var base: Dictionary=Living.at_season(r,12,true)
	world=preload("res://src/village.gd").new();root.add_child(world)
	world.build(View.snapshot(Driver.read("settlement"),base,r))
	var presentation=View.new();root.add_child(presentation);world.set_meta("project_presentation",true);presentation.refresh(base,r,world)
	nav=Adapter.capture(world,r.defense)
	check(Nav.valid(nav,r),"captured navigation valid")
	var s:=cmd(base,{"kind":"defense_begin","nav":nav})
	if not r.defense.locked(s):quit(1);return
	print("INITIAL ",s.defense.battle.keys()," GROUP ",s.defense.battle.groups[0].keys()," QUOTE ",r.defense.quote(base,r))
	check(r.validate_state(s),"mobilization valid")
	check(base.defense.is_empty(),"input untouched")
	check(s.food==base.food-r.defense.quote(base,r).food,"rations paid exactly once")
	var expected: Array=r.defense.candidates(base,r);var actual: Array=[]
	for f in s.defense.battle.groups:
		if f.side=="watch":actual.append_array(f.members)
	check(actual==expected,"only actual home watch members, no civilians")
	for action in [{"kind":"asset_principle","id":"watch","value":0},{"kind":"living_order","id":"training","value":true},{"kind":"commission","id":"care_shelter"}]:check(r.command(s,action).get("error")=="blocked","workforce lock")
	check(r.advance(s).get("error")=="blocked","season lock")
	check(r.command(s,{"kind":"defense_begin","nav":nav}).has("error"),"duplicate mobilization rejected")
	var ids: Array=[]
	for f in s.defense.battle.groups:
		if f.side=="watch":ids.append(f.id)
	s=cmd(s,{"kind":"defense_order","ids":ids,"order":"defend","at":nav.places.stores})
	check(r.command(s,{"kind":"defense_order","ids":ids,"order":"move","at":[-99999,0]}).has("error"),"invalid multigroup order rejected")
	s=cmd(s,{"kind":"defense_order","ids":ids,"order":"face","at":[2000,-4500]})
	var path: String="/tmp/village-defense-check.json"
	check(Saves.write(path,s,r),"deployment save")
	check(Saves.read(path,r)==s,"deployment exact round trip")
	s=cmd(s,{"kind":"defense_start"})
	var b: Dictionary=s.defense.battle
	for i in range(120):Sim.tick(b,r.defense.tuning)
	check(r.validate_state(s),"live valid")
	check(Saves.write(path,s,r),"active save")
	var loaded: Dictionary=Saves.read(path,r)
	if loaded.is_empty():quit(1);return
	var replay: Dictionary=loaded.defense.battle
	for i in range(3000):
		Sim.tick(b,r.defense.tuning);Sim.tick(replay,r.defense.tuning)
		check(b==replay,"save replay tick "+str(i))
		if b.phase=="ended":break
	check(b.phase=="ended","bounded outcome")
	print("DEFENDED OUTCOME ",r.defense.outcome(b))
	check(r.validate_state(s),"ended valid")
	check(Saves.write(path,s,r) and Saves.read(path,r)==s,"uncommitted ended report resumes exactly")
	var outcome: Dictionary=r.defense.outcome(b)
	var committed:=cmd(s,{"kind":"defense_commit"})
	check(r.validate_state(committed),"committed valid")
	for key in ["citizens","completed","queue","households","lifecycle","land","contacts"]:check(committed[key]==base[key],"preserved "+key)
	check(committed.defense.reports.size()==1 and not r.defense.locked(committed),"one report and unlocked")
	check(r.command(committed,{"kind":"defense_commit"}).has("error"),"commit twice rejected")
	check(r.command(committed,{"kind":"defense_begin","nav":nav}).has("error"),"no repeat reward encounter")
	check(Saves.write(path,committed,r) and Saves.read(path,r)==committed,"outcome save exactly once")
	# Withdrawal, unopposed loss, and recovery use the same public commands.
	for withdraw in [true,false]:
		var branch:=cmd(base,{"kind":"defense_begin","nav":nav})
		branch=cmd(branch,{"kind":"defense_order","ids":ids,"order":"move","at":nav.places.refuge})
		branch=cmd(branch,{"kind":"defense_start"})
		if withdraw:branch=cmd(branch,{"kind":"defense_order","ids":ids,"order":"withdraw","at":nav.places.refuge})
		for i in range(3100):
			Sim.tick(branch.defense.battle,r.defense.tuning)
			if branch.defense.battle.phase=="ended":break
		print("BRANCH ",withdraw," ",r.defense.outcome(branch.defense.battle))
		check(branch.defense.battle.outcome==("withdrawal" if withdraw else "defeat"),"withdrawal / undefended defeat")
		branch=cmd(branch,{"kind":"defense_commit"});check(r.validate_state(branch),"branch commit valid")
		check(branch.food==base.food-int(branch.defense.reports[0].cost)-int(branch.defense.reports[0].lost),"actual supplies ledger")
		check(r.advance(branch).has("state"),"village continues after battle")
	var roster_report: Dictionary=r.defense.outcome({"groups":[{"side":"watch","initial":2,"hp":1000,"kits":1,"members":["first","second"]}],"outcome":"victory","reason":"enemy_routed","cost":2,"tick":10})
	check(roster_report.wounded==["second"] and roster_report.kits==0,"survivor prefix retains its actual equipped kit")
	# Positioning, equipment and facing have actual combat consequences.
	var arena: Dictionary=cmd(base,{"kind":"defense_begin","nav":nav}).defense.battle
	var own: Dictionary=arena.groups[0];var enemy: Dictionary=arena.groups[2]
	var center: Array=nav.places.refuge
	own.position=center.duplicate();own.goal=center.duplicate();own.order="hold";own.facing=[1000,0]
	enemy.position=[center[0]+100,center[1]];enemy.goal=enemy.position.duplicate();enemy.order="hold";enemy.revealed=true
	for f in arena.groups:
		if f.id not in [own.id,enemy.id]:f.exited=true
	arena.phase="fighting";arena.paused=false
	var front: Dictionary=arena.duplicate(true);front.groups[2].facing=[-1000,0]
	var rear: Dictionary=arena.duplicate(true);rear.groups[2].facing=[1000,0]
	Sim.tick(front,r.defense.tuning);Sim.tick(rear,r.defense.tuning)
	check(rear.groups[2].hp<front.groups[2].hp,"rear exposure changes damage")
	var bare: Dictionary=front.duplicate(true);bare.groups[0].kits=0;bare.groups[0].readiness=0;bare.groups[0].cooldown=0
	var equipped: Dictionary=front.duplicate(true);equipped.groups[0].cooldown=0
	Sim.tick(bare,r.defense.tuning);Sim.tick(equipped,r.defense.tuning)
	check(equipped.groups[2].hp<bare.groups[2].hp,"actual kit/readiness increases effect")
	var distant: Dictionary=arena.duplicate(true);distant.groups[2].position=nav.places.north.duplicate();distant.groups[2].goal=distant.groups[2].position.duplicate()
	var hp: int=distant.groups[2].hp;Sim.tick(distant,r.defense.tuning);check(distant.groups[2].hp==hp,"range prevents distant damage")
	var hidden: Dictionary=cmd(base,{"kind":"defense_begin","nav":nav})
	check(r.command(hidden,{"kind":"defense_order","ids":ids,"order":"attack","target":"raider_1"}).has("error"),"unseen enemy cannot be targeted")
	var original: Dictionary=hidden.duplicate(true)
	check(r.command(hidden,{"kind":"defense_order","ids":[ids[0],"missing"],"order":"move","at":nav.places.stores}).has("error") and hidden==original,"multigroup failure is atomic")
	# Bounded stalemate and incapacitation adapter fixtures.
	var injury:=cmd(base,{"kind":"defense_begin","nav":nav})
	injury.defense.battle.groups[0].hp=0
	Sim.finish(injury.defense.battle,"defeat","watch_lost")
	injury=cmd(injury,{"kind":"defense_commit"})
	check(r.people(injury,true).size()==r.people(base,true).size()-injury.defense.recovery.size(),"wounded removed from available workers")
	for i in range(4):injury=r.advance(injury).state
	check(injury.defense.recovery.is_empty(),"fed ordinary care restores workforce")
	check(r.validate_state(injury),"recovered save valid")
	var stuck:=cmd(base,{"kind":"defense_begin","nav":nav})
	stuck=cmd(stuck,{"kind":"defense_start"});stuck.defense.battle.tick=int(r.defense.tuning.limit_ticks)-1
	Sim.tick(stuck.defense.battle,r.defense.tuning);check(stuck.defense.battle.reason=="time_limit","cannot run forever")
	# Worker continues independently of rendering/main-thread blocking; pause pure.
	var live:=cmd(base,{"kind":"defense_begin","nav":nav})
	var host:=Host.new();host.attach(r,live.defense.battle);host.run()
	host.invoke({"kind":"defense_start"});OS.delay_msec(360)
	check(host.snapshot().tick>1,"worker ticks while main thread blocked")
	host.pause();var snapshot: Dictionary=host.snapshot();OS.delay_msec(230)
	check(host.snapshot()==snapshot,"pause prevents wall-time authority");host.stop()
	var bad: Dictionary=s.duplicate(true);bad.defense.battle.groups[0].hp=-1;check(not r.validate_state(bad),"negative HP rejected")
	bad=s.duplicate(true);bad.defense.battle.nav.rows[0]="x";check(not r.validate_state(bad),"bad navigation rejected")
	bad=s.duplicate(true);bad.defense.profile="changed";check(not r.validate_state(bad),"semantic profile rejected")
	for invalid in [7,"bad",[],{"recovery":"bad"},{"recovery":{base.citizens[0].id:"bad"}}]:
		bad=base.duplicate(true);bad.defense=invalid
		check(not r.validate_state(bad),"malformed extension rejects without typed access")
	print("VILLAGE DEFENSE: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
