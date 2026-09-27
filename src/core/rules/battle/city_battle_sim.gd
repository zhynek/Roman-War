class_name CityBattleSim
## Fixed-quantum battle engine. Integer positions, health and clocks persist.
## A runtime host supplies ticks; drawing and animation only read snapshots.

static func rules(data: GameData) -> Dictionary:
	return data.balance["city_battle"]["realtime"]

static func role(data: GameData, template: String) -> String:
	return String(rules(data)["roles"].get(data.units.get(template,{}).get("class","infantry"),"soldier"))

static func navigation(data: GameData) -> Dictionary:
	return data.city_battle_navigation

static func initialize(data: GameData, battle: Dictionary) -> void:
	var tuning := rules(data)
	battle["model_version"] = 2
	battle["paused"] = true
	battle["speed"] = 1
	battle["elapsed_ms"] = 0
	battle["capture_ms"] = 0
	battle["events"] = []
	battle["event_seq"] = 0
	battle["layout_signature"] = JSON.stringify(data.roma_city)
	var counts := {"attacker":0,"defender":0}
	for f in battle["formations"]:
		var side := String(f["side"])
		var index := int(counts[side])
		counts[side] += 1
		var spatial: Dictionary = data.roma_city["battle"]["spatial"]
		var columns := int(spatial["deployment_columns"])
		var origin := CityBattleNavigation.point(spatial[side+"_origin_cm"])
		if side=="attacker" and battle["initial_attackers"].size()>columns*2:
			columns=int(spatial["attacker_max_columns"])
			origin.x=-(columns-1)*int(spatial["deployment_spacing_cm"])*0.5
		var position := origin+Vector2(index%columns,(index/columns)*(1 if side=="attacker" else -1))*int(spatial["deployment_spacing_cm"])
		var context: Dictionary = battle["context"].duplicate(true)
		# Urban manoeuvre uses the explicit tactical counter cycle below. Quality
		# still comes from the common estimator: experience, kit and commanders.
		context["wall_level"] = 0
		var profile := BattleResolver.side_estimate(data,[f["unit"]],{},context,side=="attacker")
		f.merge({"position":CityBattleNavigation.packed(position),"destination":CityBattleNavigation.packed(position),
			"goal":CityBattleNavigation.packed(position),"path":[],"role":role(data,f["template"]),"order":"attack_move" if side=="attacker" else "hold",
			"target_id":"","fire_at_will":true,"hp":int(f["unit"]["strength_pct"])*1000,"soldiers":int(data.units[f["template"]]["soldiers"]),"revealed":side=="defender",
			"cooldown_ms":0,"charge_cooldown_ms":0,"runup_cm":0,"facing":[0,-1000] if side=="attacker" else [0,1000],
			"morale":100,"routed":false,"engaged":false,"moving":false,
			"power":maxi(1,roundi(float(profile["strength"]))),"attack_seq":0})
		if side=="attacker":
			f["destination"] = data.roma_city["battle"]["spatial"]["objective_cm"].duplicate()
			f["goal"]=f["destination"].duplicate()
			f["path"] = CityBattleNavigation.route(navigation(data),position,CityBattleNavigation.point(data.roma_city["battle"]["spatial"]["objective_cm"]))

static func command(data: GameData, battle: Dictionary, ids: Array, action: String, at: Array = [], target_id: String = "") -> String:
	if not action in ["move","attack_move","attack","charge","hold","retreat","fire","attack_engine","fire_arrows","ability"] or ids.is_empty():
		return "invalid_order"
	var selected: Array = []
	var target: Dictionary = {}
	for f in battle["formations"]:
		if ids.has(f["id"]):
			if f["side"]!="defender" or not active(f):
				return "invalid_formation"
			selected.append(f)
		if f["id"]==target_id:
			target=f
	if selected.size()!=ids.size():
		return "invalid_formation"
	if action=="ability":
		return CityBattleSpecialists.command(data,battle,selected)
	if action in ["attack_engine","fire_arrows"]:
		return CitySiegeRules.command(data,battle,selected,action)
	if action in ["attack","charge"] and (target.is_empty() or target["side"]=="defender" or not active(target)):
		return "invalid_formation"
	if action=="charge":
		for f in selected:
			if f["role"]!="cavalry":
				return "invalid_order"
	if battle["phase"]=="deployment" and action not in ["move","hold","fire"]:
		return "wrong_phase"
	var positions: Array = []
	var paths: Array = []
	for index in range(selected.size()):
		var f: Dictionary = selected[index]
		var p := CityBattleNavigation.point(f["position"])
		var dest := p
		if action in ["move","attack_move","retreat"]:
			if at.size()!=2 or not SaveGame._number(at[0]) or not SaveGame._number(at[1]):
				return "invalid_position"
			dest=CityBattleNavigation.point(at)
			if index>0:
				var columns := int(rules(data)["group_columns"])
				var offset := Vector2(index%columns,index/columns)*int(rules(data)["group_spacing_cm"])
				if CityBattleNavigation.clear(data.roma_city,rules(data),dest+offset):
					dest+=offset
		elif not target.is_empty():
			dest=CityBattleNavigation.point(target["position"])
		if not CityBattleNavigation.clear(data.roma_city,rules(data),dest) or (battle["phase"]=="deployment" and dest.y>=int(rules(data)["deployment_limit_cm"])):
			return "invalid_position"
		var path := CityBattleNavigation.route(navigation(data),p,dest)
		if path.is_empty() and dest.distance_to(p)>int(rules(data)["waypoint_tolerance_cm"]):
			return "no_path"
		positions.append(CityBattleNavigation.packed(dest))
		paths.append(path)
	for index in range(selected.size()):
		var f: Dictionary = selected[index]
		if action=="fire":
			f["fire_at_will"]=not f["fire_at_will"]
			continue
		f["order"]=action
		f["runup_cm"]=0
		f["target_id"]=target_id
		f["destination"]=positions[index]
		f["goal"]=positions[index].duplicate()
		f["path"]=paths[index] if action!="hold" else []
		if battle["phase"]=="deployment":
			f["position"]=positions[index]
			f["path"]=[]
			f["order"]="hold"
	return ""

static func active(f: Dictionary) -> bool:
	return int(f["unit"]["strength_pct"])>0 and not f.get("routed",false)

static func multiplier(data: GameData, attacker_role: String, defender_role: String) -> float:
	var tuning := rules(data)
	if tuning["beats"][attacker_role]==defender_role:
		return float(tuning["counter_multiplier"])
	if tuning["beats"][defender_role]==attacker_role:
		return float(tuning["disadvantage_multiplier"])
	return 1.0

static func tick(data: GameData, state: Dictionary, battle: Dictionary) -> void:
	var tuning := rules(data)
	var dt := int(tuning["tick_ms"])
	var layout := data.roma_city
	var formations: Array = battle["formations"]
	var breached := int(battle["gate_integrity"])<=0
	var damage := {}
	var positions := {}
	CityBattleSpecialists.prepare(data,battle)
	battle["events"]=battle["events"].filter(func(e):return int(battle["elapsed_ms"])-int(e.get("time_ms",-100000))<=int(CitySiegeRules.tuning(data)["event_retention_ms"]))
	for f in formations:
		f["moving"]=false
		f["engaged"]=false
		if not active(f):
			continue
		f["cooldown_ms"]=maxi(0,int(f["cooldown_ms"])-dt)
		f["charge_cooldown_ms"]=maxi(0,int(f["charge_cooldown_ms"])-dt)
		var p := CityBattleNavigation.point(f["position"])
		if f["side"]=="attacker" and not f.get("revealed",false):
			for own in formations:
				if own["side"]=="defender" and active(own) and p.distance_to(CityBattleNavigation.point(own["position"]))<=int(tuning["acquire_range_cm"]) and CityBattleNavigation.line_clear(layout,tuning,p,CityBattleNavigation.point(own["position"]),breached):
					f["revealed"]=true
		var profile: Dictionary = tuning["profiles"][f["role"]]
		var firing_at_engine := CitySiegeRules.archer_shot(data,battle,f)
		var target := {} if firing_at_engine else _target(data,battle,f)
		var distance := INF if target.is_empty() else p.distance_to(CityBattleNavigation.point(target["position"]))
		var reach := int(profile["range_cm"])
		var can_hit := not target.is_empty() and distance<=reach and CityBattleNavigation.line_clear(layout,tuning,p,CityBattleNavigation.point(target["position"]),breached)
		if f["role"]=="archer" and not f["fire_at_will"] and distance>int(tuning["melee_range_cm"]):
			can_hit=false
		# A ranged cohort holds its firing line; melee and charge orders close.
		var stop_for_fire: bool = firing_at_engine or (can_hit and f["order"] not in ["move","retreat"])
		if can_hit and distance<=int(tuning["melee_range_cm"]):
			f["engaged"]=true
			if f["order"]!="retreat":
				stop_for_fire=true
		if not target.is_empty() and f["order"] in ["attack","charge","attack_move"] and not stop_for_fire:
			if int(battle["tick"])%int(tuning["repath_ticks"])==0 or f["path"].is_empty():
				f["destination"]=target["position"].duplicate()
				f["path"]=CityBattleNavigation.route(navigation(data),p,CityBattleNavigation.point(target["position"]))
		elif target.is_empty() and (f["order"]=="attack_move" or f["side"]=="attacker"):
			if f["destination"]!=f["goal"] or f["path"].is_empty():
				f["destination"]=f["goal"].duplicate()
				f["path"]=CityBattleNavigation.route(navigation(data),p,CityBattleNavigation.point(f["goal"]))
		# The closed gate is a physical choke point. Damage is resolved by ticks.
		var at_gate: bool = f["side"]=="attacker" and not breached and p.distance_to(CityBattleNavigation.point(data.roma_city["battle"]["spatial"]["gate_cm"]))<int(tuning["gate_attack_radius_cm"])
		if at_gate:
			stop_for_fire=true
			if int(battle["tick"])%(1000/dt)==0:
				battle["gate_integrity"]=maxi(0,int(battle["gate_integrity"])-int(CitySiegeRules.tuning(data)["infantry_gate_damage"] if battle.has("siege_engine") else tuning["gate_damage_per_second"]))
		if not stop_for_fire and not f["path"].is_empty() and f["order"]!="hold":
			var next := CityBattleNavigation.point(f["path"][0])
			if p==next:
				f["path"].pop_front()
				if not f["path"].is_empty():next=CityBattleNavigation.point(f["path"][0])
			var speed := float(profile["speed_cm_s"])*CityBattleSpecialists.speed_multiplier(data,f)
			if f["order"]=="charge" and int(f["charge_cooldown_ms"])==0:speed*=float(tuning["charge_speed_multiplier"])
			if f["engaged"]:speed*=float(tuning["engaged_speed_multiplier"])
			var moved := p.move_toward(next,speed*dt/1000.0)
			if CityBattleNavigation.clear(layout,tuning,moved,breached):
				var blocked := false
				for enemy in formations:
					if not active(enemy) or enemy["id"]==f["id"]:continue
					var other := CityBattleNavigation.point(enemy["position"])
					if moved.distance_to(other)<float(tuning["formation_separation_cm"]) and moved.distance_to(other)<p.distance_to(other):
						if enemy["side"]!=f["side"] or p.distance_to(CityBattleNavigation.point(f["destination"]))>other.distance_to(CityBattleNavigation.point(f["destination"])):
							blocked=true
				if not blocked:
					positions[f["id"]]=CityBattleNavigation.packed(moved)
					f["moving"]=moved.distance_to(p)>0
					f["runup_cm"]=int(f["runup_cm"])+roundi(moved.distance_to(p)) if f["order"]=="charge" else 0
					if moved!=p:f["facing"]=CityBattleNavigation.packed((moved-p).normalized()*1000)
		if can_hit and int(f["cooldown_ms"])==0:
			var ratio := clampf(float(f["power"])/maxf(1,float(target["power"])),float(tuning["power_ratio_min"]),float(tuning["power_ratio_max"]))
			var hit := float(tuning["base_damage_per_second"])*float(profile["attack_ms"])/1000.0*ratio*multiplier(data,f["role"],target["role"])
			hit*=float(f["unit"]["strength_pct"])/maxf(1,float(f["initial_strength"]))
			if f["role"]=="archer" and distance<int(tuning["melee_range_cm"]):hit*=float(tuning["archer_melee_multiplier"])
			var charging: bool=f["order"]=="charge" and f["role"]=="cavalry" and int(f["runup_cm"])>=int(tuning["charge_runup_cm"]) and int(f["charge_cooldown_ms"])==0
			if charging:
				hit*=float(tuning["charge_multiplier"])
				f["charge_cooldown_ms"]=int(tuning["charge_recovery_ms"])
				f["runup_cm"]=0
			hit*=CityBattleSpecialists.damage_multiplier(data,battle,f,target,charging)
			damage[target["id"]]=int(damage.get(target["id"],0))+maxi(1,roundi(hit))
			f["cooldown_ms"]=int(profile["attack_ms"])
			f["attack_seq"]=int(f["attack_seq"])+1
			f["facing"]=CityBattleNavigation.packed((CityBattleNavigation.point(target["position"])-p).normalized()*1000)
			CitySiegeRules.event(data,battle,"volley" if f["role"]=="archer" and distance>int(tuning["melee_range_cm"]) else "clash",f["position"],target["position"],{"source":f["id"],"target":target["id"],"arc_cm":500})
	CitySiegeRules.tick(data,battle)
	var attackers := false
	var defenders := false
	var occupy := false
	var contest := false
	for f in formations:
		if positions.has(f["id"]):f["position"]=positions[f["id"]]
		f["hp"]=maxi(0,int(f["hp"])-int(damage.get(f["id"],0)))
		f["unit"]["strength_pct"]=ceili(float(f["hp"])/1000.0)
	# Resolve all health before auras/morale, so a fallen commander cannot help
	# cohorts earlier in array order for one extra tick.
	for f in formations:
		f["morale"]=clampi(int(f["unit"]["strength_pct"])+int(f["unit"]["experience"])*int(tuning["morale_per_experience"])+CityBattleSpecialists.morale_bonus(data,battle,f),0,100)
		# Broken cohorts leave the fight with their survivors; only campaign
		# aftermath decides occupation. No renderer removes authoritative troops.
		if int(f["morale"])<=int(tuning["rout_threshold"]):f["routed"]=true
		if not active(f):continue
		var at_objective := CityBattleNavigation.point(f["position"]).distance_to(CityBattleNavigation.point(data.roma_city["battle"]["spatial"]["objective_cm"]))<=int(tuning["objective_radius_cm"])
		if f["side"]=="attacker":
			attackers=true
			occupy=occupy or at_objective
		else:
			defenders=true
			contest=contest or at_objective
	CityBattleSpecialists.elapse(battle,dt)
	battle["tick"]=int(battle["tick"])+1
	battle["elapsed_ms"]=int(battle["elapsed_ms"])+dt
	battle["capture_ms"]=int(battle["capture_ms"])+dt if occupy and not contest else 0
	battle["objective_progress"]=int(battle["capture_ms"])/1000
	if not attackers:CityBattleRules._finish(data,state,battle,"defender","attackers_defeated")
	elif not defenders:CityBattleRules._finish(data,state,battle,"attacker","defenders_defeated")
	elif int(battle["capture_ms"])>=int(tuning["objective_hold_ms"]):CityBattleRules._finish(data,state,battle,"attacker","forum_captured")
	elif int(battle["elapsed_ms"])>=int(tuning["maximum_ms"]):CityBattleRules._finish(data,state,battle,"defender","assault_exhausted")

static func _target(data: GameData, battle: Dictionary, f: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var score := INF
	var p := CityBattleNavigation.point(f["position"])
	for enemy in battle["formations"]:
		if enemy["side"]==f["side"] or not active(enemy):continue
		var distance := p.distance_to(CityBattleNavigation.point(enemy["position"]))
		if f["target_id"]==enemy["id"]:return enemy
		if distance>float(rules(data)["acquire_range_cm"]):continue
		var value := distance
		# Opposing commanders prefer favourable matchups without knowing hidden
		# campaign units. These formations are physically in this battle.
		if f["side"]=="attacker":value/=multiplier(data,f["role"],enemy["role"])
		if value<score:
			score=value
			best=enemy
	return best

static func upgrade(data: GameData, battle: Dictionary) -> void:
	## Old tactical saves retain their casualties, objective and campaign source.
	## Only compatible authored graphs migrate; changed graphs remain recoverable
	## through the existing stale-session discard command.
	if battle.has("model_version"):return
	var graph = JSON.parse_string(battle.get("graph_signature",""))
	if not graph is Dictionary or JSON.stringify(graph.get("nodes",[]))!=JSON.stringify(data.roma_city["battle"]["nodes"]):return
	for f in battle["formations"]:
		if not data.units.has(f["template"]):return
	if data.city_battle_navigation.is_empty():
		data.city_battle_navigation=CityBattleNavigation.build(data.roma_city,rules(data))
	initialize(data,battle)
	battle["elapsed_ms"]=int(battle["tick"])*int(rules(data)["tick_ms"])
	battle["capture_ms"]=int(battle["objective_progress"])*1000
	battle["graph_signature"]=JSON.stringify(data.roma_city["battle"])
	var nodes:=CityBattleRules._nodes(data)
	for f in battle["formations"]:
		f["position"]=CityBattleNavigation.packed(CityBattleNavigation.point(nodes[f["node"]]["position"])*100)
		f["destination"]=CityBattleNavigation.packed(CityBattleNavigation.point(nodes[f["target"]]["position"])*100)
		f["goal"]=f["destination"].duplicate()
		f["order"]="hold" if f["node"]==f["target"] else "attack_move"
		f["path"]=CityBattleNavigation.route(navigation(data),CityBattleNavigation.point(f["position"]),CityBattleNavigation.point(f["destination"])) if f["order"]!="hold" else []
