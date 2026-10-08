extends RefCounted
## Fixed ticks and simultaneous damage. Runtime clock is outside this module.
const Tactical=preload("res://src/core/tactical_sim.gd")
const Nav=preload("res://src/core/defense_navigation.gd")
const ORDERS=["move","attack","advance","hold","defend","withdraw","face"]
static func active(f: Dictionary) -> bool:return int(f.hp)>0 and not f.routed and not f.exited
static func standing(f: Dictionary,t: Dictionary) -> int:return ceili(float(f.hp)/int(t.hp_per_person))
static func formation(id: String,side: String,at: Array,members: Array,kits: int,readiness: int,t: Dictionary) -> Dictionary:
	return {"id":id,"side":side,"members":members,"kits":kits,"readiness":readiness,"hp":members.size()*int(t.hp_per_person),"initial":members.size(),"morale":100 if side=="watch" else int(t.enemy_morale),"position":at.duplicate(),"goal":at.duplicate(),"path":[],"order":"hold","target":"","facing":[0,-1000] if side=="watch" else [0,1000],"routed":false,"exited":false,"revealed":side=="watch","moving":false,"engaged":false,"attack_seq":0,"hit_seq":0,"cooldown":0}
static func find(b: Dictionary,id: String) -> Dictionary:
	for f in b.groups:
		if f.id==id:return f
	return {}
static func order(b: Dictionary,a: Dictionary,t: Dictionary,r) -> String:
	if b.has("tactics"):return Tactical.order(b,a,t,r)
	if b.phase not in ["deployment","fighting"] or not a.get("order") in ORDERS or not a.get("ids") is Array or a.ids.is_empty():return "bad_order"
	var selected: Array=[]
	for id in a.ids:
		if not id is String:return "bad_order"
		var f:=find(b,id)
		if f.is_empty() or f.side!="watch" or not active(f) or f in selected:return "bad_order"
		selected.append(f)
	var target:=find(b,str(a.get("target","")))
	if a.order=="attack" and (target.is_empty() or target.side=="watch" or not target.revealed or not active(target)):return "bad_order"
	var destinations: Array=[];var paths: Array=[]
	for i in range(selected.size()):
		var f: Dictionary=selected[i]
		var dest: Array=f.position
		if a.order=="attack":dest=target.position
		elif a.order!="hold":
			if not Nav.position(a.get("at"),r):return "bad_order"
			dest=a.at.duplicate()
			if a.order!="face":
				if not Nav.clear(b.nav,dest):return "bad_order"
				dest=Nav.at(b.nav,Nav.cell(b.nav,dest))
				if selected.size()>1:
					var offset: Array=[dest[0]+i*int(t.group_spacing_cm),dest[1]]
					if Nav.clear(b.nav,offset):dest=offset
		if a.order=="face":
			if dest==f.position:return "bad_order"
			destinations.append(dest);paths.append([]);continue
		var path: Array=Nav.route(b.nav,f.position,dest)
		if path.is_empty():return "bad_order"
		if b.phase=="deployment" and (a.order=="attack" or int(dest[1])<int(b.deploy_limit)):return "bad_order"
		destinations.append(dest);paths.append(path)
	# All-or-nothing multi-group orders.
	for i in range(selected.size()):
		var f: Dictionary=selected[i]
		if a.order=="face":f.facing=Nav.packed((Nav.point(destinations[i])-Nav.point(f.position)).normalized()*1000);continue
		f.order=a.order;f.goal=destinations[i].duplicate();f.target=a.get("target","");f.path=paths[i] if a.order!="hold" else []
		if b.phase=="deployment":f.position=destinations[i].duplicate();f.path=[]
	return ""
static func tick(b: Dictionary,t: Dictionary) -> void:
	if b.has("tactics"):
		Tactical.tick(b,t);return
	if b.phase!="fighting" or b.paused:return
	b.tick+=1
	var damage: Dictionary={};var moved: Dictionary={};var facing: Dictionary={}
	var progress: bool=false
	for f in b.groups:
		f.moving=false;f.engaged=false
		if f.hp<=0 or f.exited:continue
		f.cooldown=maxi(0,int(f.cooldown)-1)
		var p:=Nav.point(f.position)
		if f.side=="raider" and not f.revealed:
			for own in b.groups:
				if own.side=="watch" and active(own) and p.distance_to(Nav.point(own.position))<=int(t.reveal_cm) and Nav.line(b.nav,f.position,own.position):f.revealed=true
		var target: Dictionary={};var best: float=INF
		for enemy in b.groups:
			if enemy.side==f.side or not active(enemy):continue
			var distance: float=p.distance_to(Nav.point(enemy.position))
			var visible: bool=Nav.line(b.nav,f.position,enemy.position)
			var limit: int=int(t.acquire_cm)
			if f.order in ["hold","move","withdraw"]:limit=int(t.range_cm)
			if f.order=="defend" and Nav.point(f.goal).distance_to(Nav.point(enemy.position))>int(t.defend_cm):continue
			if f.order=="attack" and enemy.id==f.target and enemy.revealed:limit=100000
			if not f.routed and distance<best and distance<=limit and (visible or f.order=="attack"):
				target=enemy;best=distance
		var hit: bool=not target.is_empty() and best<=int(t.range_cm) and Nav.line(b.nav,f.position,target.position)
		if hit:
			f.engaged=true
			if f.order not in ["withdraw","move"] and f.cooldown==0:
				var count: int=standing(f,t)
				var power: int=count*int(t.enemy_damage if f.side=="raider" else t.damage)
				if f.side=="watch":power+=mini(count,int(f.kits))*int(t.kit_damage)+count*int(f.readiness)*int(t.readiness_damage)
				var incoming: Vector2=(p-Nav.point(target.position)).normalized()
				if incoming.dot(Nav.point(target.facing).normalized())<0:power=power*int(t.rear_percent)/100
				elif target.order in ["hold","defend"]:power=power*int(t.hold_percent)/100
				damage[target.id]=int(damage.get(target.id,0))+power
				f.cooldown=int(t.attack_ticks);f.attack_seq+=1;progress=true
		var dest: Array=f.goal
		if not target.is_empty() and f.order in ["advance","attack","defend"]:dest=target.position
		if f.routed:dest=b.exits[f.side]
		var can_move: bool=f.routed or f.order!="hold" and (not hit or f.order in ["move","withdraw"])
		if can_move:
			if (int(b.tick)%int(t.repath_ticks)==0 and not target.is_empty()) or f.path.is_empty():f.path=Nav.route(b.nav,f.position,dest)
			if not f.path.is_empty():
				var q:=Nav.point(f.path[0]);var speed: int=int(t.withdraw_step_cm if f.routed or f.order=="withdraw" else t.step_cm)
				var next: Array=Nav.packed(p.move_toward(q,speed))
				if Nav.line(b.nav,f.position,next):
					moved[f.id]=next;f.moving=next!=f.position
					if f.moving:facing[f.id]=Nav.packed((Nav.point(next)-p).normalized()*1000);progress=true
				if next==f.path[0]:f.path.pop_front()
			if (f.routed or f.order=="withdraw") and p.distance_to(Nav.point(dest))<=int(t.cell_cm):f.exited=true;progress=true
		if hit and not f.moving:facing[f.id]=Nav.packed((Nav.point(target.position)-p).normalized()*1000)
	for f in b.groups:
		if moved.has(f.id):f.position=moved[f.id]
		if facing.has(f.id):f.facing=facing[f.id]
		if damage.has(f.id):
			var before: int=standing(f,t);f.hp=maxi(0,int(f.hp)-int(damage[f.id]));f.hit_seq+=1
			f.morale=maxi(0,int(f.morale)-maxi(1,int(damage[f.id])/int(t.morale_damage_divisor))-(before-standing(f,t))*int(t.morale_loss))
			if f.morale<=int(t.route_morale):f.routed=true;f.path=[]
	var watch: int=0;var raiders: int=0;var occupied: bool=false;var guarded: bool=false
	for f in b.groups:
		if not active(f):continue
		if f.side=="watch":watch+=1
		else:raiders+=1
		if Nav.point(f.position).distance_to(Nav.point(b.nav.places.stores))<=int(t.capture_radius_cm):
			if f.side=="watch":guarded=true
			else:occupied=true
	if occupied and not guarded:b.capture+=1;progress=true
	else:b.capture=maxi(0,int(b.capture)-1)
	b.idle=0 if progress else int(b.idle)+1
	if raiders==0:
		b.resolution_ticks+=1
		if b.resolution_ticks>=int(t.rout_ticks):finish(b,"victory","enemy_routed")
	elif watch==0:
		var withdrawing: bool=false
		for f in b.groups:
			if f.side=="watch" and f.order=="withdraw":withdrawing=true
		finish(b,"withdrawal" if withdrawing else "defeat","withdrawn" if withdrawing else "watch_lost")
	elif int(b.capture)>=int(t.capture_ticks):finish(b,"defeat","stores_taken")
	elif int(b.idle)>=int(t.idle_ticks):finish(b,"stalemate","unreachable")
	elif int(b.tick)>=int(t.limit_ticks):finish(b,"stalemate","time_limit")
static func finish(b: Dictionary,outcome: String,reason: String) -> void:
	b.phase="ended";b.paused=true;b.outcome=outcome;b.reason=reason
