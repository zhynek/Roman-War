extends SceneTree
## Focused spatial invariants, state replay, orders and tactical decisions.
const Driver=preload("res://tools/lifecycle_driver.gd")
const Tactical=preload("res://src/core/tactical_sim.gd")
const Legacy=preload("res://src/core/defense_sim.gd")
const Nav=preload("res://src/core/defense_navigation.gd")
var r
var t: Dictionary
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func arena() -> Dictionary:
	var nav: Dictionary={"origin":[-2000,-2000],"width":41,"height":41,"cell":100,"rows":[],"places":{"stores":[0,0],"north":[0,-1700],"landing":[1700,0],"refuge":[0,1700]},"signature":""}
	for y in range(41):nav.rows.append(".".repeat(41))
	nav.signature=JSON.stringify(nav.rows).sha256_text()
	var b: Dictionary={"version":1,"phase":"deployment","paused":true,"speed":1,"tick":0,"resolution_ticks":0,"capture":0,"idle":0,"nav":nav,"groups":[],"commands":[],"cost":2,"committed":false,"outcome":"","reason":"","deploy_limit":-1800,"exits":{"watch":[0,1700],"raider":[0,-1700]}}
	b.groups.append(Legacy.formation("watch_1","watch",[-300,500],["one"],1,3,t))
	b.groups.append(Legacy.formation("watch_2","watch",[300,500],["two"],1,3,t))
	b.groups.append(Legacy.formation("raider_1","raider",[-300,-500],["enemy_one"],0,0,t))
	b.groups.append(Legacy.formation("raider_2","raider",[300,-500],["enemy_two"],0,0,t))
	for f in b.groups:
		if f.side=="raider":f.order="advance";f.goal=nav.places.stores.duplicate()
	Tactical.enhance(b,t)
	return b
func start(b: Dictionary) -> void:b.phase="fighting";b.paused=false
func command(b: Dictionary,order: String,ids: Array,at: Array=[]) -> String:
	var a: Dictionary={"kind":"defense_order","order":order,"ids":ids}
	if not at.is_empty():a.at=at
	return Tactical.order(b,a,t,r)
func empty_enemy_orders(b: Dictionary) -> void:
	for f in b.groups:
		if f.side=="raider":f.order="hold";f.position=[-1700+int(f.id.trim_prefix("raider_"))*300,-1700];f.goal=f.position.duplicate()
func wall(b: Dictionary,x: int,gap_y: int=-1) -> void:
	for y in range(int(b.nav.height)):
		if y==gap_y:continue
		var row: String=b.nav.rows[y];b.nav.rows[y]=row.substr(0,x)+"#"+row.substr(x+1)
	b.nav.signature=JSON.stringify(b.nav.rows).sha256_text()
func separation(b: Dictionary) -> bool:
	for i in range(b.groups.size()):
		var f: Dictionary=b.groups[i]
		if int(f.hp)<=0 or f.exited:continue
		for j in range(i+1,b.groups.size()):
			var other: Dictionary=b.groups[j]
			if int(other.hp)<=0 or other.exited:continue
			if Nav.point(f.position).distance_to(Nav.point(other.position))<int(t.spacing_cm)-1:return false
	return true
func run() -> void:
	r=Driver.rules();t=r.defense.battle_tuning({"tactics":{}})
	var b:=arena();check(Tactical.validate(b,r),"enhanced state valid")
	var original: Dictionary=b.duplicate(true);Tactical.enhance(b,t);check(b==original,"adoption idempotent")
	check(command(b,"move",["watch_1","watch_2"],[0,100])=="","batch deployment")
	check(b.groups[0].position!=b.groups[1].position and separation(b),"distinct reachable deployment slots")
	original=b.duplicate(true)
	check(command(b,"move",["watch_1","missing"],[0,100])!="" and b==original,"rejected batch atomic")
	check(Tactical.order(b,{"order":"width","ids":["watch_1"],"width":3},t,r)=="invalid_width" and b==original,"width validation atomic")
	check(Tactical.order(b,{"order":"width","ids":["watch_1"],"width":2},t,r)=="","spread formation available")
	check(command(b,"face",["watch_1"],[1000,100])=="" and b.groups[0].tactical.face_locked,"facing intent stored")
	check(Tactical.validate(b,r),"orders remain valid")
	start(b);b.paused=true;original=b.duplicate(true);Tactical.tick(b,t);check(b==original,"pause pure")
	check(command(b,"hold",["watch_1"])=="","orders during pause")
	b.paused=false
	var first: Dictionary=b.duplicate(true);var replay: Dictionary=r.canonical(JSON.parse_string(JSON.stringify(b)))
	for i in range(1600):
		Tactical.tick(first,t);Tactical.tick(replay,t)
		check(first==replay,"JSON replay tick "+str(i))
		check(Tactical.validate(first,r),"valid state tick "+str(i))
		check(separation(first),"spatial separation tick "+str(i))
		if first.phase=="ended":break
	check(first.phase=="ended","normal battle terminates")
	# A stopped ally forces a true side route around its occupancy.
	b=arena();empty_enemy_orders(b)
	b.groups[0].position=[-700,500];b.groups[0].goal=b.groups[0].position.duplicate()
	b.groups[1].position=[0,500];b.groups[1].goal=b.groups[1].position.duplicate()
	start(b);check(command(b,"move",["watch_1"],[700,500])=="","crossing move accepted")
	var went_around: bool=false
	for i in range(300):
		var old: Array=b.groups[0].position.duplicate();Tactical.tick(b,t)
		check(Nav.point(old).distance_to(Nav.point(b.groups[0].position))<=int(t.withdraw_step_cm)+1,"no teleport")
		check(separation(b),"stopped group avoidance")
		went_around=went_around or b.groups[0].position[1]!=500
		if b.groups[0].position==b.groups[0].goal:break
	check(went_around and b.groups[0].position==b.groups[0].goal,"route around stopped ally reaches destination")
	# A one-cell gap requires a queue; spread intent remains saved.
	b=arena();empty_enemy_orders(b);wall(b,20,25)
	b.groups[0].position=[-700,500];b.groups[0].goal=b.groups[0].position.duplicate()
	b.groups[1].position=[-1000,500];b.groups[1].goal=b.groups[1].position.duplicate()
	for f in b.groups.slice(0,2):f.tactical.width=2
	start(b);check(command(b,"move",["watch_1","watch_2"],[700,500])=="","narrow route command")
	var narrowed: bool=false
	for i in range(400):
		Tactical.tick(b,t);check(separation(b),"narrow queue spacing")
		for f in b.groups.slice(0,2):narrowed=narrowed or int(f.tactical.effective_width)==1
		if b.groups[0].position==b.groups[0].goal and b.groups[1].position==b.groups[1].goal:break
	check(narrowed,"automatic column through passage")
	check(b.groups[0].position==b.groups[0].goal and b.groups[1].position==b.groups[1].goal,"both groups clear narrow gap")
	# Opposing traffic through a narrow lane yields into its passing place.
	b=arena();empty_enemy_orders(b)
	for y in range(41):b.nav.rows[y]=".".repeat(41) if y==25 else "#".repeat(41)
	for y in [26,27]:b.nav.rows[y]="#".repeat(20)+".."+"#".repeat(19)
	for p in b.nav.places.values()+[b.groups[2].position,b.groups[3].position]:
		var c:=Nav.cell(b.nav,p);var row: String=b.nav.rows[c.y];b.nav.rows[c.y]=row.substr(0,c.x)+"."+row.substr(c.x+1)
	b.nav.signature=JSON.stringify(b.nav.rows).sha256_text()
	b.groups[0].position=[-600,500];b.groups[0].goal=b.groups[0].position.duplicate()
	b.groups[1].position=[600,500];b.groups[1].goal=b.groups[1].position.duplicate()
	start(b)
	check(command(b,"move",["watch_1"],[1100,500])=="","eastbound lane order")
	check(command(b,"move",["watch_2"],[-1100,500])=="","westbound lane order")
	var yielded: bool=false
	for i in range(500):
		Tactical.tick(b,t);check(separation(b),"head-on lane separation")
		yielded=yielded or not b.groups[1].tactical.yield_goal.is_empty()
		if b.groups[0].position==b.groups[0].goal and b.groups[1].position==b.groups[1].goal:break
	check(yielded,"head-on traffic uses passing place")
	check(b.groups[0].position==b.groups[0].goal and b.groups[1].position==b.groups[1].goal,"opposing groups clear lane "+str([b.groups[0].position,b.groups[1].position,b.groups[1].tactical]))
	# In open ground the same crossing must not produce mirrored detours.
	b=arena();empty_enemy_orders(b)
	b.groups[0].position=[-600,500];b.groups[0].goal=b.groups[0].position.duplicate()
	b.groups[1].position=[600,500];b.groups[1].goal=b.groups[1].position.duplicate()
	start(b);check(command(b,"move",["watch_1"],[1100,500])=="" and command(b,"move",["watch_2"],[-1100,500])=="","open opposing orders")
	for i in range(400):
		Tactical.tick(b,t);check(separation(b),"open crossing separation")
		if b.groups[0].position==b.groups[0].goal and b.groups[1].position==b.groups[1].goal:break
	check(b.groups[0].position==b.groups[0].goal and b.groups[1].position==b.groups[1].goal,"open crossing avoids symmetric detour loop")
	# Routed groups remain physical traffic. An advancing ally must let them
	# pass instead of ignoring their retreat and trapping both in place.
	b=arena();empty_enemy_orders(b)
	b.groups[0].position=[-600,500];b.groups[0].goal=[-1100,500]
	b.groups[1].position=[600,500];b.groups[1].goal=b.groups[1].position.duplicate()
	b.exits.watch=[1100,500];b.groups[0].routed=true
	start(b);check(command(b,"move",["watch_2"],[-1100,500])=="","advance past routed ally")
	for i in range(500):
		Tactical.tick(b,t);check(separation(b),"routed traffic keeps spacing")
		if b.groups[0].exited and b.groups[1].position==b.groups[1].goal:break
	check(b.groups[0].exited and b.groups[1].position==b.groups[1].goal,"routed group escapes through opposing allied traffic")
	# Dynamic avoidance must not surround a hostile target with an impassable
	# reservation ring: physical separation still stops approach at melee.
	b=arena();start(b)
	for index in [1,3]:b.groups[index].exited=true
	b.groups[0].position=[-700,500];b.groups[0].goal=[700,500];b.groups[0].order="advance"
	b.groups[0].tactical.wait=int(t.blocked_repath_ticks)
	b.groups[2].position=[700,500];b.groups[2].goal=[700,500];b.groups[2].order="hold"
	check(not Tactical._route(b,b.groups[0],b.groups[2].position,true,t).is_empty(),"dynamic route can approach an occupied hostile destination")
	for i in range(200):
		Tactical.tick(b,t);check(separation(b),"pursuit keeps physical separation")
		if int(b.groups[0].attack_seq)>0:break
	check(int(b.groups[0].attack_seq)>0,"blocked pursuit eventually engages the target")
	# Unreachable orders fail before changing any group.
	b=arena();wall(b,20)
	b.groups[0].position=[-500,500];b.groups[0].goal=b.groups[0].position.duplicate()
	b.groups[1].position=[-700,500];b.groups[1].goal=b.groups[1].position.duplicate()
	original=b.duplicate(true)
	check(command(b,"move",["watch_1","watch_2"],[900,500])!="" and b==original,"disconnected target atomic rejection")
	# Observations expire. A previously seen enemy does not remain an exact target.
	b=arena();start(b)
	b.groups[1].exited=true
	check(Tactical.order(b,{"order":"attack","ids":["watch_1"],"target":"raider_1"},t,r)=="","observed targeted attack")
	b.groups[2].position=[1500,-500];b.groups[2].goal=b.groups[2].position.duplicate();b.groups[2].order="hold"
	wall(b,20)
	for i in range(int(t.contact_ticks)+2):Tactical.tick(b,t)
	check(not b.groups[2].revealed,"enemy hidden again behind obstruction")
	check(not b.groups[0].tactical.contacts.has("raider_1"),"last observation expires")
	check(Tactical.order(b,{"order":"attack","ids":["watch_1"],"target":"raider_1"},t,r)=="target_not_visible","hidden target refused")
	# Rest and terrain affect movement through the same tick path.
	b=arena();empty_enemy_orders(b);start(b);b.groups[0].tactical.fatigue=80
	var rested: Dictionary=b.duplicate(true)
	for i in range(40):Tactical.tick(rested,t)
	check(int(rested.groups[0].tactical.fatigue)<80,"rest recovers fatigue")
	var normal:=arena();empty_enemy_orders(normal);start(normal)
	var tired: Dictionary=normal.duplicate(true);tired.groups[0].tactical.fatigue=100
	var rough: Dictionary=normal.duplicate(true);rough.tactics.ground=[{"at":[-300,500],"radius":900,"move_percent":50}]
	for sample in [normal,tired,rough]:check(command(sample,"move",["watch_1"],[1000,500])=="","movement comparison command")
	var initial: Vector2=Nav.point(normal.groups[0].position)
	for i in range(10):
		for sample in [normal,tired,rough]:Tactical.tick(sample,t)
	check(initial.distance_to(Nav.point(tired.groups[0].position))<initial.distance_to(Nav.point(normal.groups[0].position)),"fatigue slows movement")
	check(initial.distance_to(Nav.point(rough.groups[0].position))<initial.distance_to(Nav.point(normal.groups[0].position)),"rough ground slows movement")
	# Facing is gradual and defensible cover changes actual received damage.
	b=arena();start(b)
	b.groups[0].position=[0,400];b.groups[0].goal=[0,400];b.groups[0].facing=[1000,0]
	b.groups[2].position=[150,400];b.groups[2].goal=[150,400];b.groups[2].order="hold";b.groups[2].facing=[-1000,0]
	for index in [1,3]:b.groups[index].exited=true
	var covered: Dictionary=b.duplicate(true);covered.tactics.defenses=[{"at":[0,400],"radius":200,"protection":60,"side":"watch"}]
	Tactical.tick(b,t);Tactical.tick(covered,t)
	check(covered.groups[0].hp>b.groups[0].hp,"actual defended position reduces frontal damage")
	var turn:=arena();empty_enemy_orders(turn);start(turn);turn.groups[0].facing=[0,-1000]
	check(command(turn,"face",["watch_1"],[-300,1500])=="","reverse face accepted")
	Tactical.tick(turn,t);check(turn.groups[0].facing!=[0,1000] and turn.groups[0].facing!=[0,-1000],"turning gradual")
	# Objective loss tolerance and bounded unreachable/time-limit resolutions.
	b=arena();start(b)
	for f in b.groups:
		if f.side=="raider":f.hp=100
	Tactical.tick(b,t);check(b.tactics.enemy_retreat and b.groups[2].routed,"raiders abandon costly objective")
	var retreat_start: Array=b.groups[2].position.duplicate()
	for i in range(15):Tactical.tick(b,t)
	check(Nav.point(retreat_start).distance_to(Nav.point(b.groups[2].position))>int(t.cell_cm),"routed enemy actually retreats each tick")
	check(b.groups[2].revealed,"observed retreat remains visible")
	b=arena();start(b);b.tick=int(t.limit_ticks)-1
	var bounded: Dictionary=t.duplicate(true);bounded.enemy_objective_ticks=int(t.limit_ticks)+1
	Tactical.tick(b,bounded);check(b.reason=="time_limit","bounded time termination")
	b=arena();start(b);b.idle=int(t.idle_ticks)-1
	for f in b.groups:f.order="hold"
	Tactical.tick(b,t);check(b.reason=="unreachable","bounded stalled termination")
	# Malformed optional metadata never reaches a typed unsafe operation.
	for key in ["width","fatigue","contacts","face","path_goal","condition","leadership"]:
		b=arena();b.groups[0].tactical[key]="bad";check(not Tactical.validate(b,r),"malformed "+key)
	b=arena();b.tactics.ground=[{"at":[],"radius":1,"move_percent":100}];check(not Tactical.validate(b,r),"malformed ground")
	b=arena();b.groups[0].tactical.contacts["watch_2"]={"position":b.groups[1].position.duplicate(),"tick":0};check(not Tactical.validate(b,r),"friendly contact malformed")
	b=arena();b.groups[0].tactical.unrecognized=1;check(not Tactical.validate(b,r),"unknown tactical key rejected")
	b=arena();start(b);b.groups[0].order="attack";b.groups[0].target="watch_2";b.groups[1].position=[-200,500];b.groups[1].goal=b.groups[1].position.duplicate()
	var friendly_hp: int=int(b.groups[1].hp);Tactical.tick(b,t);check(b.groups[1].hp==friendly_hp,"malformed target never causes friendly fire")
	print("TACTICAL CHECKS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
