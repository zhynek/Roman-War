extends RefCounted
## Explicitly adopted village tactics. Integer state; no scene or clock authority.
## All movement, observation, combat and recovery below occurs on fixed ticks.
const Nav=preload("res://src/core/defense_navigation.gd")
const ORDERS=["move","attack","advance","hold","defend","withdraw","face","width"]

static func active(f: Dictionary) -> bool:
	return int(f.hp)>0 and not f.routed and not f.exited

static func standing(f: Dictionary,t: Dictionary) -> int:
	return ceili(float(f.hp)/int(t.hp_per_person))

static func find(b: Dictionary,id: String) -> Dictionary:
	for f in b.groups:
		if f.id==id:return f
	return {}

static func enhance(b: Dictionary,t: Dictionary) -> void:
	if b.has("tactics"):return
	var enemy_hp: int=0
	for f in b.groups:
		if f.side=="raider":enemy_hp+=int(f.hp)
		f.tactical={"version":1,"width":1,"effective_width":1,"fatigue":0,
			"face":f.facing.duplicate(),"face_locked":false,"wait":0,"contacts":{},
			"path_goal":[],"next_repath":0,"blocked":"","skill":0,"leadership":0,
			"condition":int(t.maximum_stat),"initial_morale":int(f.morale),
			"local_friends":0,"local_enemies":0,"terrain_percent":int(t.maximum_stat),
			"cover_percent":int(t.maximum_stat),"yield_goal":[],"yield_for":"","yield_origin":[]}
	b.tactics={"version":1,"objective":b.nav.places.stores.duplicate(),
		"enemy_initial_hp":enemy_hp,"enemy_retreat":false,"defenses":[],"ground":[]}
	# Deployment is the only time positions can be arranged without walking.
	# Existing v1 formations can start at the same nearest clear cell.
	var occupied: Array=[]
	for f in b.groups:
		var placed: Array=_slot(b,f.position,occupied,[],f,t)
		if not placed.is_empty() and b.phase=="deployment":
			f.position=placed;f.goal=placed.duplicate() if f.side=="watch" else f.goal
		occupied.append({"position":f.position,"width":int(f.tactical.effective_width),"count":int(f.initial)})
	_observe(b,t)

static func visible(b: Dictionary,side: String,enemy: Dictionary,t: Dictionary) -> bool:
	if enemy.exited:return false
	for own in b.groups:
		if own.side==side and active(own) and _sees(b,own,enemy,t):return true
	return false

static func _sees(b: Dictionary,f: Dictionary,enemy: Dictionary,t: Dictionary) -> bool:
	return Nav.point(f.position).distance_squared_to(Nav.point(enemy.position))<=pow(int(t.reveal_cm),2) and Nav.line(b.nav,f.position,enemy.position)

static func _observe(b: Dictionary,t: Dictionary) -> void:
	for f in b.groups:
		if f.side=="raider":f.revealed=visible(b,"watch",f,t)
		if not active(f):continue
		for enemy in b.groups:
			if enemy.side==f.side or not active(enemy):continue
			if _sees(b,f,enemy,t):f.tactical.contacts[enemy.id]={"position":enemy.position.duplicate(),"tick":int(b.tick)}
		var ids: Array=f.tactical.contacts.keys();ids.sort()
		for id in ids:
			if int(b.tick)-int(f.tactical.contacts[id].tick)>int(t.contact_ticks):f.tactical.contacts.erase(id)

static func _radius(count: int,width: int,t: Dictionary) -> int:
	var lateral: float=float(mini(width,count)-1)*float(t.person_spacing_cm)*.5
	var depth: float=float(ceili(float(count)/width)-1)*float(t.person_spacing_cm)*.5
	var bodies: int=ceili(sqrt(lateral*lateral+depth*depth))+int(t.person_radius_cm)
	return maxi(int(t.spacing_cm)/2+(width-1)*int(t.wide_extra_cm),bodies)

static func _separation(f: Dictionary,other_width: int,t: Dictionary,other_count: int=1) -> int:
	return _radius(int(f.initial),int(f.tactical.effective_width),t)+_radius(other_count,other_width,t)

static func _effective_width(b: Dictionary,f: Dictionary,t: Dictionary) -> int:
	if int(f.tactical.width)==1 or not _room(b,f.position,f.facing):return 1
	for other in b.groups:
		if other.id==f.id or int(other.hp)<=0 or other.exited:continue
		var clearance: int=_radius(int(f.initial),2,t)+_radius(int(other.initial),int(other.tactical.width),t)
		if Nav.point(f.position).distance_to(Nav.point(other.position))<clearance:return 1
	return 2

static func _room(b: Dictionary,p: Array,face: Array) -> bool:
	var c:=Nav.cell(b.nav,p)
	# A spread pair needs a neighboring clear cell on both sides. It files
	# into a column automatically through a one-cell passage.
	var lateral:=Vector2i(0,1) if abs(int(face[0]))>abs(int(face[1])) else Vector2i(1,0)
	return Nav.clear_cell(b.nav,c+lateral) and Nav.clear_cell(b.nav,c-lateral)

static func _slot(b: Dictionary,wanted: Array,occupied: Array,excluded: Array,f: Dictionary,t: Dictionary) -> Array:
	var origin:=Nav.cell(b.nav,wanted)
	for radius in range(int(t.slot_radius_cells)+1):
		var options: Array=[]
		for y in range(origin.y-radius,origin.y+radius+1):
			for x in range(origin.x-radius,origin.x+radius+1):
				if radius>0 and abs(x-origin.x)!=radius and abs(y-origin.y)!=radius:continue
				var c:=Vector2i(x,y)
				if not Nav.clear_cell(b.nav,c):continue
				var p: Array=Nav.at(b.nav,c)
				if p in excluded:continue
				if b.phase=="deployment" and f.side=="watch" and int(p[1])<int(b.deploy_limit):continue
				var clear: bool=true
				for other in occupied:
					if Nav.point(p).distance_squared_to(Nav.point(other.position))<pow(_separation(f,int(other.width),t,int(other.count)),2):clear=false;break
				if clear:options.append(p)
		options.sort_custom(func(a,b_):
			var da: float=Nav.point(a).distance_squared_to(Nav.point(wanted));var db: float=Nav.point(b_).distance_squared_to(Nav.point(wanted))
			return da<db if da!=db else (a[1]<b_[1] if a[1]!=b_[1] else a[0]<b_[0]))
		for p in options:
			if not Nav.route(b.nav,f.position,p).is_empty():return p
	return []

static func order(b: Dictionary,a: Dictionary,t: Dictionary,r) -> String:
	if b.get("phase") not in ["deployment","fighting"] or a.get("order") not in ORDERS or not a.get("ids") is Array or a.ids.is_empty():return "bad_order"
	var selected: Array=[];var selected_ids: Array=[]
	for id in a.ids:
		if not id is String or id in selected_ids:return "bad_order"
		var f:=find(b,id)
		if f.is_empty() or f.side!="watch" or not active(f):return "bad_order"
		selected.append(f);selected_ids.append(id)
	if a.order=="width":
		if not r.whole(a.get("width"),1,2):return "invalid_width"
		for f in selected:
			if int(a.width)==2 and b.phase=="deployment" and not _room(b,f.position,f.facing):return "no_formation_room"
		for f in selected:f.tactical.width=int(a.width)
		for f in selected:f.tactical.effective_width=_effective_width(b,f,t)
		return ""
	var target: Dictionary={}
	if a.order=="attack":
		target=find(b,str(a.get("target","")))
		if target.is_empty() or target.side=="watch" or not active(target):return "bad_order"
		if b.phase=="deployment":return "bad_order"
		if not visible(b,"watch",target,t):return "target_not_visible"
	elif a.order!="hold" and not Nav.position(a.get("at"),r):return "bad_order"
	var destinations: Array=[];var paths: Array=[]
	var occupied: Array=[]
	for f in b.groups:
		if int(f.hp)>0 and not f.exited and f.id not in selected_ids:occupied.append({"position":f.position,"width":int(f.tactical.effective_width),"count":int(f.initial)})
	for i in range(selected.size()):
		var f: Dictionary=selected[i]
		var destination: Array=f.position.duplicate()
		if a.order=="face":
			if a.at==f.position:return "invalid_facing"
			destinations.append(a.at.duplicate());paths.append([]);continue
		if a.order=="attack":destination=target.position.duplicate()
		elif a.order!="hold":
			if not Nav.clear(b.nav,a.at):return "blocked_destination"
			if b.phase=="deployment" and int(a.at[1])<int(b.deploy_limit):return "blocked_destination"
			var requested: Array=Nav.at(b.nav,Nav.cell(b.nav,a.at))
			# Slots are centered around the requested point and face the approach.
			var direction: Vector2=(Nav.point(requested)-Nav.point(f.position)).normalized()
			if direction==Vector2.ZERO:direction=Nav.point(f.facing).normalized()
			var lateral:=Vector2(-direction.y,direction.x)
			var offset: float=(float(i)-float(selected.size()-1)*.5)*float(t.group_spacing_cm)
			var wanted: Array=Nav.packed(Nav.point(requested)+lateral*offset)
			destination=_slot(b,wanted,occupied,[],f,t)
			if destination.is_empty():return "no_formation_room"
		var path: Array=Nav.route(b.nav,f.position,destination)
		if path.is_empty():return "unreachable_destination"
		destinations.append(destination);paths.append(path)
		if a.order!="attack":occupied.append({"position":destination,"width":int(f.tactical.effective_width),"count":int(f.initial)})
	# Validate the entire batch before mutating any authoritative field.
	for i in range(selected.size()):
		var f: Dictionary=selected[i];var destination: Array=destinations[i]
		if a.order=="face":
			f.tactical.face=Nav.packed((Nav.point(destination)-Nav.point(f.position)).normalized()*int(t.vector_scale));f.tactical.face_locked=true
			if b.phase=="deployment":f.facing=f.tactical.face.duplicate()
			continue
		f.order=a.order;f.goal=destination.duplicate();f.target=str(a.get("target",""))
		f.path=paths[i] if a.order!="hold" else []
		f.tactical.path_goal=destination.duplicate();f.tactical.wait=0;f.tactical.blocked="";f.tactical.yield_goal=[];f.tactical.yield_for="";f.tactical.yield_origin=[]
		f.tactical.next_repath=int(b.tick)+int(t.repath_ticks)
		if a.order=="attack":f.tactical.contacts[target.id]={"position":target.position.duplicate(),"tick":int(b.tick)}
		if b.phase=="deployment":f.position=destination.duplicate();f.path=[]
	return ""

static func _target(b: Dictionary,f: Dictionary,t: Dictionary) -> Dictionary:
	if f.routed:return {}
	if f.order=="attack":
		var selected:=find(b,f.target)
		if not selected.is_empty() and selected.side!=f.side and active(selected) and _sees(b,f,selected,t):return selected
	var chosen: Dictionary={};var best: float=INF
	for enemy in b.groups:
		if enemy.side==f.side or not active(enemy) or not _sees(b,f,enemy,t):continue
		var distance: float=Nav.point(f.position).distance_to(Nav.point(enemy.position))
		var limit: int=int(t.range_cm) if f.order in ["hold","move","withdraw","attack"] else int(t.acquire_cm)
		if f.order=="defend" and Nav.point(f.goal).distance_to(Nav.point(enemy.position))>int(t.defend_cm):continue
		if distance<=limit and distance<best:chosen=enemy;best=distance
	return chosen

static func _route(b: Dictionary,f: Dictionary,to: Array,avoid: bool,t: Dictionary) -> Array:
	if not avoid:return Nav.route(b.nav,f.position,to)
	var nav: Dictionary=b.nav.duplicate(true)
	var start:=Nav.cell(nav,f.position);var end:=Nav.cell(nav,to)
	for other in b.groups:
		if other.id==f.id or int(other.hp)<=0 or other.exited:continue
		var center:=Nav.cell(nav,other.position)
		# Pursuit must reach attack distance from its target. Reserving the
		# target's entire footprint would seal every approach to the goal cell.
		# Movement still checks exact separation and stops at melee range.
		if other.side!=f.side and center==end:continue
		var clearance: int=_separation(f,int(other.tactical.effective_width),t,int(other.initial))
		var radius: int=ceili(float(clearance)/int(nav.cell))
		for y in range(maxi(0,center.y-radius),mini(int(nav.height),center.y+radius+1)):
			for x in range(maxi(0,center.x-radius),mini(int(nav.width),center.x+radius+1)):
				var c:=Vector2i(x,y)
				if c==start or c==end or Nav.point(Nav.at(nav,c)).distance_to(Nav.point(other.position))>=clearance:continue
				var row: String=nav.rows[y];nav.rows[y]=row.substr(0,x)+"#"+row.substr(x+1)
	return Nav.route(nav,f.position,to)

static func _free_step(b: Dictionary,f: Dictionary,next: Array,positions: Dictionary,t: Dictionary) -> bool:
	if not Nav.line(b.nav,f.position,next):return false
	for other in b.groups:
		if other.id==f.id or int(other.hp)<=0 or other.exited:continue
		var position: Array=positions.get(other.id,other.position)
		var distance: float=Nav.point(next).distance_squared_to(Nav.point(position))
		var before: float=Nav.point(f.position).distance_squared_to(Nav.point(position))
		# A pre-existing crowded deployment can separate, but never crowd further.
		if distance<pow(_separation(f,int(other.tactical.effective_width),t,int(other.initial)),2) and distance<=before:return false
	return true

static func _yield(b: Dictionary,f: Dictionary,priority: Dictionary,t: Dictionary) -> Array:
	var start:=Nav.cell(b.nav,f.position);var options: Array=[]
	for radius in range(1,int(t.yield_radius_cells)+1):
		for y in range(start.y-radius,start.y+radius+1):
			for x in range(start.x-radius,start.x+radius+1):
				if abs(x-start.x)!=radius and abs(y-start.y)!=radius:continue
				var c:=Vector2i(x,y)
				if not Nav.clear_cell(b.nav,c):continue
				var p: Array=Nav.at(b.nav,c)
				var occupied: bool=false
				for other in b.groups:
					if other.id!=f.id and int(other.hp)>0 and not other.exited and Nav.point(other.position).distance_to(Nav.point(p))<int(t.group_spacing_cm):occupied=true;break
				if occupied:continue
				var axis: Vector2=(Nav.point(f.goal)-Nav.point(f.position)).normalized()
				# A passing place must be beside this route. Backing repeatedly
				# along the same corridor merely trades a deadlock for jitter.
				if absf((Nav.point(p)-Nav.point(f.position)).cross(axis))<int(t.spacing_cm):continue
				var path:=_route(b,f,p,true,t)
				if not path.is_empty():options.append({"point":p,"path":path})
		if not options.is_empty():break
	if options.is_empty():return []
	options.sort_custom(func(a,c):
		# Step aside preferably away from the original route, not forward into it.
		var da: float=Nav.point(a.point).distance_squared_to(Nav.point(f.goal));var dc: float=Nav.point(c.point).distance_squared_to(Nav.point(f.goal))
		return da>dc if da!=dc else (a.point[1]<c.point[1] if a.point[1]!=c.point[1] else a.point[0]<c.point[0]))
	f.tactical.yield_goal=options[0].point.duplicate()
	f.tactical.yield_for=priority.id;f.tactical.yield_origin=f.position.duplicate()
	return options[0].path

static func _ground(b: Dictionary,f: Dictionary,t: Dictionary) -> int:
	var percent: int=int(t.maximum_stat)
	for ground in b.tactics.ground:
		if Nav.point(f.position).distance_to(Nav.point(ground.at))<=int(ground.radius):percent=mini(percent,int(ground.move_percent))
	return maxi(int(t.terrain_min_percent),percent)

static func _cover(b: Dictionary,f: Dictionary,t: Dictionary) -> int:
	var percent: int=int(t.maximum_stat)
	if f.order not in ["hold","defend"]:return percent
	for defense in b.tactics.defenses:
		if defense.side==f.side and Nav.point(f.position).distance_to(Nav.point(defense.at))<=int(defense.radius):percent=mini(percent,int(defense.protection))
	# A constricted position reduces simultaneous exposure. This is read from
	# actual blocked navigation; a drawing cannot award the protection.
	if not _room(b,f.position,f.facing):percent=mini(percent,int(t.edge_cover_percent))
	return maxi(int(t.cover_min_percent),percent)

static func _local(b: Dictionary,f: Dictionary,t: Dictionary) -> void:
	var friends: int=0;var enemies: int=0
	for other in b.groups:
		if not active(other) or Nav.point(f.position).distance_to(Nav.point(other.position))>int(t.support_cm) or not Nav.line(b.nav,f.position,other.position):continue
		if other.side==f.side:friends+=standing(other,t)
		else:enemies+=standing(other,t)
	f.tactical.local_friends=friends;f.tactical.local_enemies=enemies
	f.tactical.terrain_percent=_ground(b,f,t);f.tactical.cover_percent=_cover(b,f,t)

static func _turn(f: Dictionary,wanted: Array,t: Dictionary) -> void:
	if wanted==[0,0]:return
	var current: float=atan2(float(f.facing[1]),float(f.facing[0]))
	var target: float=atan2(float(wanted[1]),float(wanted[0]))
	var angle: float=current+clampf(wrapf(target-current,-PI,PI),-deg_to_rad(float(t.turn_degrees)),deg_to_rad(float(t.turn_degrees)))
	f.facing=Nav.packed(Vector2(cos(angle),sin(angle))*int(t.vector_scale))

static func _power(b: Dictionary,f: Dictionary,target: Dictionary,t: Dictionary) -> int:
	var count: int=standing(f,t)
	var power: int=count*int(t.enemy_damage if f.side=="raider" else t.damage)
	if f.side=="watch":power+=mini(count,int(f.kits))*int(t.kit_damage)*int(f.tactical.condition)/int(t.maximum_stat)+count*int(f.readiness)*int(t.readiness_damage)
	power+=count*int(f.tactical.skill)*int(t.skill_damage)
	var percent: int=int(t.maximum_stat)-int(f.tactical.fatigue)*(int(t.maximum_stat)-int(t.fatigue_damage_percent))/int(t.maximum_stat)
	power=power*percent/int(t.maximum_stat)
	var toward: Vector2=(Nav.point(target.position)-Nav.point(f.position)).normalized()
	var own_front: bool=toward.dot(Nav.point(f.facing).normalized())*int(t.vector_scale)>=int(t.front_dot)
	if not own_front:power=power*int(t.side_attack_percent)/int(t.maximum_stat)
	elif int(f.tactical.effective_width)==2 and count>1:power=power*int(t.wide_front_percent)/int(t.maximum_stat)
	var incoming: float=(-toward).dot(Nav.point(target.facing).normalized())*int(t.vector_scale)
	if incoming<0:power=power*int(t.rear_percent)/int(t.maximum_stat)
	elif incoming>=int(t.front_dot):
		if target.order in ["hold","defend"]:power=power*int(t.hold_percent)/int(t.maximum_stat)
		power=power*int(target.tactical.cover_percent)/int(t.maximum_stat)
	return maxi(1,power)

static func _encounter_orders(b: Dictionary) -> void:
	if not b.tactics.has("encounter"):return
	var encounter: Dictionary=b.tactics.encounter
	if encounter.kind!="snatch" or encounter.stage!="carrying":return
	var carrier:=find(b,encounter.carrier)
	if carrier.is_empty() or not active(carrier):return
	for f in b.groups:
		if f.side!="raider" or not active(f) or f.id==carrier.id:continue
		# Escorts know their own carrier, but still acquire opponents only by
		# their ordinary local sight. The carrier itself keeps withdrawing.
		f.order="defend";f.goal=carrier.position.duplicate()

static func tick(b: Dictionary,t: Dictionary) -> void:
	if b.phase!="fighting" or b.paused:return
	b.tick+=1
	_observe(b,t)
	_encounter_orders(b)
	var enemy_hp: int=0
	for f in b.groups:
		if f.side=="raider" and not f.exited:enemy_hp+=int(f.hp)
	if enemy_hp*int(t.maximum_stat)<=int(b.tactics.enemy_initial_hp)*int(t.enemy_retreat_percent) or int(b.tick)>=int(t.enemy_objective_ticks):b.tactics.enemy_retreat=true
	for f in b.groups:
		f.moving=false;f.engaged=false;f.tactical.blocked=""
		f.cooldown=maxi(0,int(f.cooldown)-1)
		if f.side=="raider" and b.tactics.enemy_retreat and int(f.hp)>0 and not f.exited and not f.routed:f.routed=true;f.path=[];f.tactical.next_repath=int(b.tick)
		f.tactical.effective_width=_effective_width(b,f,t)
		if int(f.tactical.effective_width)<int(f.tactical.width):f.tactical.blocked="formation_narrow"
		_local(b,f,t)
	var damage: Dictionary={};var positions: Dictionary={};var turns: Dictionary={};var desired: Dictionary={}
	var progress: bool=false
	# Damage and target decisions read one pre-movement state.
	for f in b.groups:
		if int(f.hp)<=0 or f.exited:continue
		var target:=_target(b,f,t)
		var hit: bool=not target.is_empty() and Nav.point(f.position).distance_to(Nav.point(target.position))<=int(t.range_cm)
		if hit:
			f.engaged=true
			if f.order not in ["move","withdraw"] and int(f.cooldown)==0:
				damage[target.id]=int(damage.get(target.id,0))+_power(b,f,target,t)
				f.cooldown=int(t.attack_ticks);f.attack_seq+=1;f.tactical.fatigue=mini(int(t.maximum_stat),int(f.tactical.fatigue)+int(t.fatigue_attack));progress=true
		var destination: Array=f.goal.duplicate()
		if f.side=="raider" and f.order=="advance":destination=b.tactics.objective.duplicate()
		if f.order=="attack":
			if f.tactical.contacts.has(f.target):destination=f.tactical.contacts[f.target].position.duplicate()
			else:destination=f.position.duplicate();f.tactical.blocked="target_lost"
		if not target.is_empty() and f.order in ["advance","defend","attack"]:destination=target.position.duplicate()
		if f.routed:destination=b.exits[f.side].duplicate()
		if not f.tactical.yield_goal.is_empty():
			var priority:=find(b,f.tactical.yield_for)
			# Routed residents and raiders still occupy and traverse the lane.
			# Let their retreat pass before reclaiming a yielded position.
			var passed: bool=priority.is_empty() or int(priority.hp)<=0 or priority.exited
			if not passed:
				var priority_goal: Array=b.exits[priority.side] if priority.routed else priority.goal
				var axis: Vector2=(Nav.point(priority_goal)-Nav.point(f.tactical.yield_origin)).normalized()
				passed=(Nav.point(priority.position)-Nav.point(f.tactical.yield_origin)).dot(axis)>=int(t.group_spacing_cm) or priority.position==priority_goal
			if passed or f.routed:
				f.tactical.yield_goal=[];f.tactical.yield_for="";f.tactical.yield_origin=[];f.path=[];f.tactical.next_repath=int(b.tick)
			else:destination=f.tactical.yield_goal.duplicate()
		var moving: bool=f.routed or f.order!="hold" and (not hit or f.order in ["move","withdraw"])
		if moving and destination!=f.position:desired[f.id]=destination
		if not target.is_empty() and not f.tactical.face_locked:turns[f.id]=Nav.packed((Nav.point(target.position)-Nav.point(f.position)).normalized()*int(t.vector_scale))
		elif f.tactical.face_locked:turns[f.id]=f.tactical.face.duplicate()
	# Frontmost arrivals move first; remaining ties use the persistent id.
	# A blocked pair explicitly yields to a passing place through normal paths.
	var movers: Array=[]
	for f in b.groups:
		if desired.has(f.id):movers.append(f)
	movers.sort_custom(func(a,c):
		var da: float=Nav.point(a.position).distance_squared_to(Nav.point(desired[a.id]));var dc: float=Nav.point(c.position).distance_squared_to(Nav.point(desired[c.id]))
		return da<dc if da!=dc else str(a.id)<str(c.id))
	for f in movers:
		var destination: Array=desired[f.id]
		var repath: bool=f.tactical.path_goal.is_empty() or Nav.cell(b.nav,destination)!=Nav.cell(b.nav,f.tactical.path_goal) and int(b.tick)>=int(f.tactical.next_repath)
		if repath or f.path.is_empty() and int(b.tick)>=int(f.tactical.next_repath):
			f.path=_route(b,f,destination,int(f.tactical.wait)>=int(t.blocked_repath_ticks),t)
			f.tactical.path_goal=destination.duplicate();f.tactical.next_repath=int(b.tick)+int(t.repath_ticks)
		if not f.path.is_empty():
			while not f.path.is_empty() and f.path[0]==f.position:f.path.pop_front()
		if not f.path.is_empty():
			var speed: int=int(t.withdraw_step_cm if f.routed or f.order=="withdraw" else t.step_cm)
			if b.tactics.has("encounter") and b.tactics.encounter.kind=="snatch" and b.tactics.encounter.stage=="carrying" and f.id==b.tactics.encounter.carrier:speed=maxi(1,speed*int(t.carrier_speed_percent)/int(t.maximum_stat))
			var percent: int=int(t.maximum_stat)-int(f.tactical.fatigue)*(int(t.maximum_stat)-int(t.fatigue_speed_percent))/int(t.maximum_stat)
			speed=maxi(1,speed*percent/int(t.maximum_stat)*int(f.tactical.terrain_percent)/int(t.maximum_stat))
			var next: Array=Nav.packed(Nav.point(f.position).move_toward(Nav.point(f.path[0]),speed))
			# A route may begin by centering within its current grid cell. When
			# traffic occupies that center, take the already-clear adjacent turn
			# directly if its first step separates safely. This lets a retreating
			# column enter a passing place without moving into its pursuer first.
			if not _free_step(b,f,next,positions,t) and f.path.size()>1 and f.path[0]==Nav.at(b.nav,Nav.cell(b.nav,f.position)) and Nav.line(b.nav,f.position,f.path[1]):
				var turn_step: Array=Nav.packed(Nav.point(f.position).move_toward(Nav.point(f.path[1]),speed))
				if _free_step(b,f,turn_step,positions,t):f.path.pop_front();next=turn_step
			if _free_step(b,f,next,positions,t):
				positions[f.id]=next;f.moving=next!=f.position
				if f.moving:
					turns[f.id]=Nav.packed((Nav.point(next)-Nav.point(f.position)).normalized()*int(t.vector_scale));progress=true;f.tactical.wait=0
				if next==f.path[0]:f.path.pop_front()
			else:f.tactical.wait+=1;f.tactical.blocked="congestion"
		else:f.tactical.wait+=1;f.tactical.blocked="no_route"
		if int(f.tactical.wait)>0 and int(f.tactical.wait)%int(t.blocked_repath_ticks)==0:
			var traffic: Dictionary={}
			for other in b.groups:
				if other.id==f.id or other.side!=f.side or int(other.hp)<=0 or other.exited or not desired.has(other.id):continue
				if Nav.point(f.position).distance_to(Nav.point(other.position))>int(t.group_spacing_cm):continue
				var direction: Vector2=(Nav.point(destination)-Nav.point(f.position)).normalized()
				var other_direction: Vector2=(Nav.point(desired[other.id])-Nav.point(other.position)).normalized()
				if direction.dot(other_direction)<=0:traffic=other;break
			var alternative: Array=[]
			if not traffic.is_empty():
				if str(f.id)>str(traffic.id):
					if f.tactical.yield_goal.is_empty():alternative=_yield(b,f,traffic,t)
					if alternative.is_empty():alternative=_route(b,f,destination,true,t)
				# The priority group keeps its original route while the other
				# steps aside, avoiding symmetric detours that repeat forever.
			else:alternative=_route(b,f,destination,true,t)
			if not alternative.is_empty():f.path=alternative
		if int(f.tactical.wait)>=int(t.yield_ticks) and int(f.tactical.wait)%int(t.yield_ticks)==0:
			# Only one of a mutually blocked pair yields, chosen by stable id.
			var priority: Dictionary={}
			for other in b.groups:
				if other.id!=f.id and other.side==f.side and int(other.hp)>0 and not other.exited and int(other.tactical.wait)>0 and str(f.id)>str(other.id) and Nav.point(f.position).distance_to(Nav.point(other.position))<=int(t.group_spacing_cm):priority=other;break
			if not priority.is_empty() and f.tactical.yield_goal.is_empty():
				var alternate:=_yield(b,f,priority,t)
				if not alternate.is_empty():f.path=alternate
	for f in b.groups:
		if positions.has(f.id):f.position=positions[f.id]
		if turns.has(f.id):_turn(f,turns[f.id],t)
		if int(f.hp)<=0 or f.exited:continue
		if (f.routed or f.order=="withdraw") and Nav.point(f.position).distance_to(Nav.point(b.exits[f.side] if f.routed else f.goal))<=int(t.cell_cm):f.exited=true;progress=true
		if damage.has(f.id):
			var before: int=standing(f,t);f.hp=maxi(0,int(f.hp)-int(damage[f.id]));f.hit_seq+=1
			var loss: int=maxi(1,int(damage[f.id])/int(t.morale_damage_divisor))+(before-standing(f,t))*int(t.morale_loss)
			loss+=maxi(0,int(f.tactical.local_enemies)-int(f.tactical.local_friends))*int(t.outnumber_morale)
			loss-=maxi(0,int(f.tactical.local_friends)-1)*int(t.support_morale)+int(f.tactical.leadership)*int(t.leadership_morale)
			f.morale=maxi(0,int(f.morale)-maxi(1,loss))
			if f.morale<=int(t.route_morale):f.routed=true;f.path=[];f.tactical.yield_goal=[];f.tactical.yield_for="";f.tactical.yield_origin=[];f.tactical.next_repath=int(b.tick)
		if f.moving and int(b.tick)%int(t.fatigue_period_ticks)==0:f.tactical.fatigue=mini(int(t.maximum_stat),int(f.tactical.fatigue)+int(t.fatigue_move))
		elif not f.moving and not f.engaged:
			if int(b.tick)%int(t.fatigue_rest_ticks)==0:f.tactical.fatigue=maxi(0,int(f.tactical.fatigue)-int(t.fatigue_rest))
			var danger: bool=false
			for enemy in b.groups:
				if enemy.side!=f.side and active(enemy) and Nav.point(f.position).distance_to(Nav.point(enemy.position))<int(t.morale_rest_cm) and _sees(b,f,enemy,t):danger=true;break
			if not danger and not f.routed and int(b.tick)%int(t.morale_rest_ticks)==0:f.morale=mini(int(f.tactical.initial_morale),int(f.morale)+int(t.morale_rest))
	_outcome(b,t,progress)

static func _outcome(b: Dictionary,t: Dictionary,progress: bool) -> void:
	var watch: int=0;var enemies: int=0;var occupied: bool=false;var guarded: bool=false
	for f in b.groups:
		if not active(f):continue
		if f.side=="watch":watch+=1
		else:enemies+=1
		if Nav.point(f.position).distance_to(Nav.point(b.tactics.objective))<=int(t.capture_radius_cm):
			if f.side=="watch":guarded=true
			else:occupied=true
	if b.tactics.has("encounter"):
		progress=_encounter_progress(b,t,occupied,guarded) or progress
		if b.phase=="ended":return
	else:
		if occupied and not guarded:b.capture+=1;progress=true
		else:b.capture=maxi(0,int(b.capture)-1)
	b.idle=0 if progress else int(b.idle)+1
	if enemies==0:
		b.resolution_ticks+=1
		var recovered: bool=b.tactics.has("encounter") and b.tactics.encounter.kind=="snatch" and b.tactics.encounter.stage=="secured" and not b.tactics.encounter.carrier.is_empty()
		if b.resolution_ticks>=int(t.rout_ticks):_finish(b,"victory","supplies_recovered" if recovered else "enemy_routed")
	elif watch==0:
		var withdrawal: bool=false
		for f in b.groups:
			if f.side=="watch" and f.order=="withdraw":withdrawal=true
		_finish(b,"withdrawal" if withdrawal else "defeat","withdrawn" if withdrawal else "watch_lost")
	elif b.tactics.has("encounter") and int(b.tick)>=int(t.deadline_ticks):_finish(b,"victory","deadline_held")
	elif not b.tactics.has("encounter") and int(b.capture)>=int(t.capture_ticks):_finish(b,"defeat","stores_taken")
	elif int(b.idle)>=int(t.idle_ticks):_finish(b,"stalemate","unreachable")
	elif int(b.tick)>=int(t.limit_ticks):_finish(b,"stalemate","time_limit")

static func _encounter_progress(b: Dictionary,t: Dictionary,occupied: bool,guarded: bool) -> bool:
	var encounter: Dictionary=b.tactics.encounter
	if encounter.kind=="snatch" and encounter.stage=="carrying":
		var carrier:=find(b,encounter.carrier)
		if carrier.is_empty() or int(carrier.hp)<=0 or carrier.routed:
			encounter.stage="secured";b.tactics.enemy_retreat=true
			return true
		if carrier.exited:
			encounter.stage="secured";_finish(b,"defeat","supplies_escaped")
		return false
	if encounter.stage=="secured":return false
	var before: int=int(encounter.held)
	if occupied and (not guarded or encounter.kind=="probe"):encounter.held=mini(int(t.capture_ticks),before+1)
	else:encounter.held=maxi(0,before-1)
	b.capture=int(encounter.held)
	if int(encounter.held)<int(t.capture_ticks):return before!=int(encounter.held)
	if encounter.kind=="occupy":
		encounter.stage="secured";_finish(b,"defeat","stores_taken")
	elif encounter.kind=="probe":
		encounter.stage="secured";_finish(b,"defeat","objective_held")
	else:
		var candidates: Array=[]
		for f in b.groups:
			if f.side=="raider" and active(f) and Nav.point(f.position).distance_to(Nav.point(b.tactics.objective))<=int(t.capture_radius_cm):candidates.append(f)
		candidates.sort_custom(func(a,c):return str(a.id)<str(c.id))
		if candidates.is_empty():return before!=int(encounter.held)
		var carrier: Dictionary=candidates[0]
		encounter.stage="carrying";encounter.carrier=carrier.id
		carrier.order="withdraw";carrier.goal=b.exits.raider.duplicate();carrier.path=[];carrier.target=""
		carrier.tactical.path_goal=[];carrier.tactical.next_repath=int(b.tick);carrier.tactical.yield_goal=[];carrier.tactical.yield_for="";carrier.tactical.yield_origin=[]
	return true

static func _finish(b: Dictionary,outcome: String,reason: String) -> void:
	b.phase="ended";b.paused=true;b.outcome=outcome;b.reason=reason

static func validate(b: Dictionary,r) -> bool:
	if not b.get("tactics") is Dictionary or not b.get("groups") is Array or not b.get("nav") is Dictionary:return false
	if not Nav.valid(b.nav,r) or not r.whole(b.get("tick"),0,100000):return false
	var meta: Dictionary=b.tactics
	var tuning: Dictionary=r.defense.battle_tuning(b)
	if meta.size()!=6+int(meta.has("plan"))+int(meta.has("encounter")) or meta.get("version")!=1 or not Nav.position(meta.get("objective"),r) or not Nav.clear(b.nav,meta.objective):return false
	if meta.has("plan"):
		if not meta.plan is Dictionary or meta.plan.size()!=5:return false
		for slot in ["assembly","approach","important","reserve","fallback"]:
			if not Nav.position(meta.plan.get(slot),r) or not Nav.clear(b.nav,meta.plan[slot]):return false
	if not r.whole(meta.get("enemy_initial_hp"),1,1000000) or not meta.get("enemy_retreat") is bool:return false
	if not meta.get("defenses") is Array or meta.defenses.size()>64 or not meta.get("ground") is Array or meta.ground.size()>256:return false
	for defense in meta.defenses:
		if not defense is Dictionary or defense.size()!=4 or not Nav.position(defense.get("at"),r) or not r.whole(defense.get("radius"),1,30000) or not r.whole(defense.get("protection"),1,100) or defense.get("side") not in ["watch","raider"]:return false
	for ground in meta.ground:
		if not ground is Dictionary or ground.size()!=3 or not Nav.position(ground.get("at"),r) or not r.whole(ground.get("radius"),1,30000) or not r.whole(ground.get("move_percent"),1,100):return false
	var ids: Array=[]
	for f in b.groups:
		if not f is Dictionary or not f.get("id") is String or f.id in ids:return false
		ids.append(f.id)
	if meta.has("encounter"):
		var encounter: Variant=meta.encounter
		if not encounter is Dictionary or encounter.size()!=8:return false
		if not encounter.get("id") is String or encounter.id.is_empty() or encounter.id.length()>64:return false
		if not r.whole(encounter.get("serial"),0,100000) or encounter.get("kind") not in ["occupy","snatch","probe"] or encounter.get("mode") not in ["direct","delegated"]:return false
		if not r.whole(encounter.get("next_decision"),0,int(b.tick)+int(tuning.director_decision_ticks)):return false
		if encounter.get("stage") not in ["approach","carrying","secured"] or not encounter.get("carrier") is String:return false
		if not r.whole(encounter.get("held"),0,int(tuning.capture_ticks)) or not r.whole(b.get("capture"),0,int(tuning.capture_ticks)) or int(encounter.held)!=int(b.capture):return false
		if encounter.carrier!="":
			if encounter.carrier not in ids or find(b,encounter.carrier).side!="raider" or encounter.kind!="snatch" or encounter.stage=="approach":return false
		if encounter.stage=="carrying" and (encounter.kind!="snatch" or encounter.carrier=="" or int(encounter.held)!=int(tuning.capture_ticks)):return false
		if encounter.stage=="approach" and encounter.carrier!="":return false
	for f in b.groups:
		if not f.get("tactical") is Dictionary:return false
		var q: Dictionary=f.tactical
		if q.size()!=22 or q.get("version")!=1 or not r.whole(q.get("width"),1,2) or not r.whole(q.get("effective_width"),1,2) or int(q.effective_width)>int(q.width):return false
		if not Nav.position(q.get("face"),r) or int(q.face[0])==0 and int(q.face[1])==0 or not q.get("face_locked") is bool:return false
		if absi(int(q.face[0]))>int(tuning.vector_scale) or absi(int(q.face[1]))>int(tuning.vector_scale):return false
		for key in ["fatigue","condition","initial_morale"]:
			if not r.whole(q.get(key),0,100):return false
		for key in ["wait","next_repath"]:
			if not r.whole(q.get(key),0,100000):return false
		for key in ["local_friends","local_enemies"]:
			if not r.whole(q.get(key),0,100):return false
		for key in ["terrain_percent","cover_percent"]:
			if not r.whole(q.get(key),1,100):return false
		if not r.whole(q.get("skill"),0,int(tuning.max_skill)) or not r.whole(q.get("leadership"),0,int(tuning.max_leadership)):return false
		if q.get("blocked") not in ["","congestion","no_route","target_lost","formation_narrow","exhausted"]:return false
		for key in ["path_goal","yield_goal","yield_origin"]:
			if not q.get(key) is Array or not q[key].is_empty() and (not Nav.position(q[key],r) or not Nav.clear(b.nav,q[key])):return false
		if not q.get("yield_for") is String or q.yield_for!="" and (q.yield_for not in ids or q.yield_for==f.id):return false
		if q.yield_goal.is_empty():
			if q.yield_for!="" or not q.yield_origin.is_empty():return false
		elif q.yield_for=="" or q.yield_origin.is_empty():return false
		if not q.get("contacts") is Dictionary or q.contacts.size()>b.groups.size():return false
		for id in q.contacts:
			var contact: Variant=q.contacts[id]
			if id not in ids or id==f.id or not contact is Dictionary or contact.size()!=2:return false
			if find(b,id).side==f.side:return false
			if not Nav.position(contact.get("position"),r) or not Nav.clear(b.nav,contact.position) or not r.whole(contact.get("tick"),0,int(b.tick)):return false
	return true
