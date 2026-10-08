extends SceneTree
## Objectives and delegated command share one deterministic tick/order boundary.
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const View=preload("res://src/campaign_view.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Tactical=preload("res://src/core/tactical_sim.gd")
const Director=preload("res://src/core/battle_director.gd")
const Legacy=preload("res://src/core/defense_sim.gd")
const Nav=preload("res://src/core/defense_navigation.gd")
const Saves=preload("res://src/campaign_save.gd")
var r
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func control(b: Dictionary,a: Dictionary) -> void:
	check(r.defense.control(b,a,r).is_empty(),"accepted serialized "+str(a))
func tune(b: Dictionary) -> Dictionary:return r.defense.battle_tuning(b)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var result: Dictionary=r.command(s,a)
	check(result.has("state"),"public preparation "+str(a)+" "+str(result.get("error","")))
	return result.get("state",s)
func paid_preparation(s: Dictionary) -> Dictionary:
	for i in range(50):
		var done: bool=true
		for id in ["warfare_store_screen","warfare_landing_screen"]:
			if r.has_project(s,id):continue
			done=false
			var queued: bool=false
			for item in s.queue:
				if item.id==id:queued=true
			if not queued and r.quote(s,{"kind":"commission","id":id}).has("state"):
				s=cmd(s,{"kind":"commission","id":id})
				s=cmd(s,{"kind":"asset_project","id":id,"priority":1,"crew":2,"paused":false})
		if done:break
		s=r.advance(Living.orders(r,s,true)).state
	for id in ["warfare_store_screen","warfare_landing_screen"]:check(r.has_project(s,id),"finite ordinary work completes "+id)
	s=cmd(s,{"kind":"warfare_muster","value":4})
	check(r.validate_state(s),"paid prepared and mustered village validates")
	return s
func arena(id: String) -> Dictionary:
	var nav: Dictionary={"origin":[-2000,-2000],"width":41,"height":41,"cell":100,"rows":[],"places":{"stores":[0,0],"north":[0,-900],"landing":[900,0],"refuge":[-1600,1500]},"signature":""}
	for y in range(41):nav.rows.append(".".repeat(41))
	nav.signature=JSON.stringify(nav.rows).sha256_text()
	var b: Dictionary={"version":1,"phase":"deployment","paused":true,"speed":1,"tick":0,"resolution_ticks":0,"capture":0,"idle":0,"nav":nav,"groups":[],"commands":[],"cost":2,"committed":false,"outcome":"","reason":"","deploy_limit":-1800,"exits":{"watch":nav.places.refuge.duplicate(),"raider":[0,-1700]}}
	var t: Dictionary=r.defense.battle_tuning({"tactics":{}})
	b.groups.append(Legacy.formation("watch_1","watch",[-1600,1500],["one"],1,3,t))
	b.groups.append(Legacy.formation("watch_2","watch",[-1300,1500],["two"],1,3,t))
	b.groups.append(Legacy.formation("raider_1","raider",[-1200,-1000],["enemy_one"],0,0,t))
	b.groups.append(Legacy.formation("raider_2","raider",[1200,-1000],["enemy_two"],0,0,t))
	Tactical.enhance(b,t)
	var spec: Dictionary=r.warfare.threats.encounters[id].duplicate(true);spec.origins=[[-12,-10],[12,-10]]
	check(Director.configure(b,spec,0,t).is_empty(),"configure "+id)
	return b
func at_objective(b: Dictionary,contested: bool) -> void:
	for f in b.groups:f.order="hold";f.path=[];f.cooldown=10000
	b.groups[2].position=b.tactics.objective.duplicate();b.groups[2].goal=b.groups[2].position.duplicate()
	b.groups[3].exited=true
	if contested:
		b.groups[0].position=[int(b.tactics.objective[0])+100,int(b.tactics.objective[1])];b.groups[0].goal=b.groups[0].position.duplicate()
	b.phase="fighting";b.paused=false
func finish(b: Dictionary,batched: bool=false) -> int:
	var began: int=Time.get_ticks_usec()
	for outer in range(3101):
		for inner in range(37 if batched else 1):
			if b.phase=="ended":return Time.get_ticks_usec()-began
			r.defense.step(b,r)
	return Time.get_ticks_usec()-began
func run() -> void:
	r=Driver.rules()
	var b:=arena("stores");at_objective(b,true)
	for i in range(30):Tactical.tick(b,tune(b))
	check(b.capture==0 and b.phase=="fighting","occupation requires an uncontested objective")
	b.groups[0].position=b.nav.places.refuge.duplicate();b.groups[0].goal=b.groups[0].position.duplicate()
	for i in range(int(tune(b).capture_ticks)):Tactical.tick(b,tune(b))
	check(b.phase=="ended" and b.reason=="stores_taken","uncontested occupation defeats")
	b=arena("probe");at_objective(b,true)
	for i in range(int(tune(b).capture_ticks)):Tactical.tick(b,tune(b))
	check(b.phase=="ended" and b.reason=="objective_held","probe measures sustained contested presence")
	b=arena("landing");at_objective(b,false)
	for i in range(int(tune(b).capture_ticks)):Tactical.tick(b,tune(b))
	check(b.phase=="fighting" and b.tactics.encounter.stage=="carrying" and b.tactics.encounter.carrier=="raider_1","snatch requires a real carrier and does not end at pickup")
	check(b.groups[2].order=="withdraw" and b.groups[2].goal==b.exits.raider,"carrier uses ordinary withdrawal navigation")
	check(Tactical.validate(b,r),"carrying state validates")
	var carrying: Dictionary=b.duplicate(true);var resumed: Dictionary=r.canonical(JSON.parse_string(JSON.stringify(carrying)))
	for i in range(1500):
		Tactical.tick(b,tune(b));Tactical.tick(resumed,tune(resumed))
		check(b==resumed,"carrying save replay "+str(i))
		if b.phase=="ended":break
	check(b.reason=="supplies_escaped" and b.outcome=="defeat","supplies lost only after actual carrier escape")
	b=carrying.duplicate(true);b.groups[2].hp=0
	for i in range(int(tune(b).rout_ticks)+2):Tactical.tick(b,tune(b))
	check(b.reason=="supplies_recovered" and b.outcome=="victory","incapacitated carrier drops supplies")
	b=carrying.duplicate(true);b.groups[2].routed=true
	for i in range(int(tune(b).rout_ticks)+2):Tactical.tick(b,tune(b))
	check(b.reason=="supplies_recovered","routed carrier abandons payload")
	for id in ["stores","landing","probe"]:
		b=arena(id);b.phase="fighting";b.paused=false;b.tick=int(tune(b).deadline_ticks)-1
		for f in b.groups:f.order="hold"
		# The objective's deadline is independent of the earlier generic AI
		# loss-budget retreat timer; keep a live force for this exact boundary.
		var t: Dictionary=tune(b).duplicate(true);t.enemy_objective_ticks=int(t.deadline_ticks)+1
		Tactical.tick(b,t)
		check(b.reason=="deadline_held" and b.outcome=="victory",id+" objective deadline repels")
	# Delegation is a command source; paused/direct queries are entirely pure.
	b=arena("stores");var frozen: Dictionary=b.duplicate(true)
	check(Director.orders(b,tune(b),r).is_empty() and b==frozen,"deployment query does not advance AI")
	b.phase="fighting";b.paused=false;frozen=b.duplicate(true)
	check(Director.orders(b,tune(b),r).is_empty() and b==frozen,"direct command disables delegated decisions")
	control(b,{"kind":"defense_mode","mode":"delegated"});b.paused=true;frozen=b.duplicate(true)
	check(Director.orders(b,tune(b),r).is_empty() and b==frozen,"paused commander does not mutate next decision")
	b.paused=false
	var actions: Array=Director.orders(b,tune(b),r)
	check(not actions.is_empty(),"delegate proposes defensive orders")
	for action in actions:control(b,action)
	check(b.commands.size()>=2,"delegate orders appear in ordinary command log")
	var next: int=int(b.tactics.encounter.next_decision)
	check(next==int(b.tick)+int(tune(b).director_decision_ticks),"decision cadence serialized")
	control(b,{"kind":"defense_mode","mode":"direct"});frozen=b.duplicate(true)
	check(Director.orders(b,tune(b),r).is_empty() and b==frozen,"taking control back stops decisions")
	control(b,{"kind":"defense_mode","mode":"delegated"});b.groups[0].tactical.fatigue=100
	actions=Director.orders(b,tune(b),r)
	var withdrawing: bool=false
	for action in actions:
		if action.order=="withdraw" and "watch_1" in action.ids:withdrawing=true
		control(b,action)
	check(withdrawing,"exhausted actual defenders receive valid fallback withdrawal")
	# Hidden enemy position/health changes cannot affect a defensive decision.
	b=arena("stores");b.phase="fighting";b.paused=false;control(b,{"kind":"defense_mode","mode":"delegated"})
	var hidden: Dictionary=b.duplicate(true)
	for sample in [b,hidden]:
		for f in sample.groups:
			if f.side=="watch":f.position=[-1800,1800];f.goal=f.position.duplicate()
			else:f.position=[1800,-1800];f.goal=f.position.duplicate();f.revealed=false
	hidden.groups[2].hp=123;hidden.groups[2].position=[1500,-1800]
	check(Director.orders(b,tune(b),r)==Director.orders(hidden,tune(hidden),r),"commander ignores unseen enemy detail")
	# Metadata and source restrictions fail safely, including raw JSON numbers.
	for key in ["id","mode","kind","stage","carrier","held","next_decision","serial"]:
		b=arena("stores");b.tactics.encounter[key]=[];check(not Tactical.validate(b,r),"malformed encounter "+key)
	b=arena("stores");b.tactics.encounter=[];check(not Tactical.validate(b,r),"malformed encounter object")
	b=arena("landing");b.tactics.encounter.stage="carrying";b.tactics.encounter.carrier="watch_1";b.tactics.encounter.held=int(tune(b).capture_ticks);b.capture=b.tactics.encounter.held
	check(not Tactical.validate(b,r),"friendly carrier rejected")
	b=arena("stores");b.tactics.encounter.extra=true;check(not Tactical.validate(b,r),"unknown encounter metadata rejected")
	b=arena("stores");frozen=b.duplicate(true)
	check(not Director.configure(b,r.warfare.threats.encounters.stores,0,tune(b)).is_empty() and b==frozen,"cannot reset configured objective")
	# Public mobilization from the real village, equipment and resident records.
	var base: Dictionary=Living.at_season(r,12,true)
	var adopted: Dictionary=r.command(base,{"kind":"warfare_begin"}).state
	var world=preload("res://src/village.gd").new();root.add_child(world)
	world.build(View.snapshot(Driver.read("settlement"),adopted,r));world.set_meta("project_presentation",true)
	var presentation=View.new();root.add_child(presentation);presentation.refresh(adopted,r,world)
	var nav: Dictionary=Adapter.capture(world,r.defense)
	var source_result: Dictionary=r.command(adopted,{"kind":"defense_begin","nav":nav})
	check(source_result.has("state"),"actual prepared village mobilizes")
	if not source_result.has("state"):quit(1);return
	var source: Dictionary=source_result.state;var actual: Dictionary=source.defense.battle
	check(r.validate_state(source),"actual configured battle validates")
	print("ACTUAL DEPLOYMENT ",actual.deploy_limit," ",actual.groups[0].position)
	for id in ["stores","landing","probe"]:
		var configured: Dictionary=actual.duplicate(true);configured.tactics.erase("encounter")
		check(Director.configure(configured,r.warfare.threats.encounters[id],0,r.defense.battle_tuning(configured)).is_empty(),"actual terrain configured "+id)
		check(Tactical.validate(configured,r),"actual variant validates "+id)
		var path: Array=Nav.route(nav,configured.groups[0].position,configured.tactics.objective)
		print("APPROACH ",id," ",path.size(),"m-grid legs; capture ",tune(configured).capture_ticks)
		var manual: Dictionary=configured.duplicate(true)
		control(manual,{"kind":"defense_start"})
		var ids: Array=[]
		for f in manual.groups:
			if f.side=="watch":ids.append(f.id)
		control(manual,{"kind":"defense_order","order":"advance","ids":ids,"at":manual.tactics.objective})
		var engaged: bool=false
		for i in range(3101):
			r.defense.step(manual,r)
			for f in manual.groups:
				if f.side=="watch":engaged=engaged or int(f.attack_seq)>0
			if manual.phase=="ended":break
		check(manual.phase=="ended",id+" actual direct run bounded")
		if id!="stores":check(engaged,id+" default watch can reach and contest the objective")
		else:check(manual.outcome=="defeat","leaving a distant two-person watch in assembly concedes stores")
		var normal: Dictionary=configured.duplicate(true)
		control(normal,{"kind":"defense_mode","mode":"delegated"});r.defense.prepare_delegated(normal,r);control(normal,{"kind":"defense_start"})
		var accelerated: Dictionary=normal.duplicate(true)
		var elapsed: int=finish(normal);var batched_elapsed: int=finish(accelerated,true)
		check(normal==accelerated,id+" identical outcomes and commands in single/batched ticks")
		check(normal.phase=="ended",id+" delegated/quick run bounded")
		print("ACTUAL ENCOUNTER ",id," direct ",manual.outcome,"/",manual.reason," tick ",manual.tick," engaged ",engaged," delegated ",normal.outcome,"/",normal.reason," tick ",normal.tick," command_count ",normal.commands.size()," single_ms ",elapsed/1000.0," batched_ms ",batched_elapsed/1000.0)
	# Real paid protection, trained kits and additional finite watch allocation.
	var prepared: Dictionary=paid_preparation(adopted.duplicate(true))
	world.build(View.snapshot(Driver.read("settlement"),prepared,r));presentation.refresh(prepared,r,world)
	var prepared_nav: Dictionary=Adapter.capture(world,r.defense)
	var prepared_state: Dictionary=cmd(prepared,{"kind":"defense_begin","nav":prepared_nav})
	var prepared_battle: Dictionary=prepared_state.defense.battle
	var count: int=0
	for f in prepared_battle.groups:
		if f.side=="watch":count+=int(f.initial)
	check(count>2,"muster allocates additional actual residents")
	print("PREPARED VILLAGE season ",prepared.turn," watch ",count," kits ",prepared.living.kits," readiness ",prepared.living.readiness," zones ",prepared_battle.tactics.defenses.size()," food ",prepared.food," wood ",prepared.wood)
	for id in ["stores","landing","probe"]:
		var configured: Dictionary=prepared_battle.duplicate(true);configured.tactics.erase("encounter")
		check(Director.configure(configured,r.warfare.threats.encounters[id],0,r.defense.battle_tuning(configured)).is_empty(),"prepared variant "+id)
		var customized: Dictionary=configured.duplicate(true)
		control(customized,{"kind":"defense_order","order":"hold","ids":[customized.groups[0].id]})
		control(customized,{"kind":"defense_mode","mode":"delegated"})
		var held_position: Array=customized.groups[0].position.duplicate();r.defense.prepare_delegated(customized,r)
		check(customized.groups[0].position==held_position and customized.groups[0].order=="hold","delegated deployment preserves customized hold "+id)
		control(configured,{"kind":"defense_mode","mode":"delegated"});r.defense.prepare_delegated(configured,r)
		check(configured.commands.back().action.order=="defend","delegated deployment is logged ordinary order "+id)
		check(Tactical.validate(configured,r),"delegated deployment validates "+id)
		var manual: Dictionary=configured.duplicate(true)
		control(manual,{"kind":"defense_mode","mode":"direct"});control(manual,{"kind":"defense_start"})
		var ids: Array=[]
		for f in manual.groups:
			if f.side=="watch":ids.append(f.id)
		control(manual,{"kind":"defense_order","order":"defend","ids":ids,"at":Director._prepared_position(manual,tune(manual))})
		finish(manual)
		check(manual.outcome=="victory","paid prepared direct defense can repel "+id)
		control(configured,{"kind":"defense_start"})
		var accelerated: Dictionary=configured.duplicate(true)
		var elapsed: int=finish(configured);finish(accelerated,true)
		check(configured==accelerated,"prepared "+id+" modes equivalent")
		check(configured.phase=="ended","prepared "+id+" bounded")
		check(configured.outcome=="victory","paid prepared delegated defense can repel "+id)
		print("PREPARED ENCOUNTER ",id," direct ",manual.outcome,"/",manual.reason," tick ",manual.tick," delegated ",configured.outcome,"/",configured.reason," ticks ",configured.tick," ms ",elapsed/1000.0)
		FileAccess.open("/tmp/village-encounter-"+id+".json",FileAccess.WRITE).store_string(JSON.stringify(configured,"  "))
	# Real atomic village writer validates raw JSON before canonicalizing it.
	control(actual,{"kind":"defense_mode","mode":"delegated"});control(actual,{"kind":"defense_start"})
	for i in range(125):r.defense.step(actual,r)
	var save_path: String="/tmp/village-encounter-check-"+str(OS.get_process_id())+".json"
	check(Saves.write(save_path,source,r),"delegated active battle writes through real atomic save")
	var loaded: Dictionary=Saves.read(save_path,r)
	check(not loaded.is_empty() and loaded==source,"delegated active battle raw-save read exact")
	if not loaded.is_empty():
		finish(actual);finish(loaded.defense.battle,true)
		check(loaded==source,"delegated live/save-resume/batched state and command log identical")
	check(adopted.defense.is_empty() and base.warfare.is_empty(),"isolated scenario branches preserve continuing source")
	print("ENCOUNTER CHECKS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
