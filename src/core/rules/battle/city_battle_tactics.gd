class_name CityBattleTactics
## Optional deterministic command extension. No time or scene APIs.
## Platoons keep health in their original battalion's strength units.

static func rules(data: GameData) -> Dictionary:
	return data.balance["city_battle"]["tactics"]

static func initialize(battle: Dictionary) -> void:
	battle["tactics_version"]=1
	for f in battle["formations"]:
		f.merge({"source_id":f["id"],"source_strength":f["initial_strength"],"platoon":0,
			"formation":"line","reform_ms":0,"ai_reform_ms":0,"facing_goal":f["facing"].duplicate(),"facing_locked":false})

static func phalanx_eligible(data: GameData, f: Dictionary) -> bool:
	return data.units.get(f["template"],{}).get("attributes",[]).has(rules(data)["phalanx_attribute"]) and int(f["unit"]["experience"])>=int(rules(data)["phalanx_experience"])

static func room(data: GameData, at: Vector2, facing: Vector2, breached: bool = true) -> bool:
	var width := int(rules(data)["phalanx_half_width_cm"])
	var lateral := Vector2(facing.y,-facing.x).normalized()*width
	for p in [at,at+lateral,at-lateral]:
		if not CityBattleNavigation.clear(data.roma_city,CityBattleSim.rules(data),p,breached):return false
	return true

static func command(data: GameData, battle: Dictionary, selected: Array, action: String, at: Array, intent: String = "") -> String:
	if not battle.has("tactics_version"):return "no_tactics"
	if action=="split":return split(data,battle,selected)
	if action=="assault_line":return frontage(data,battle,selected,at,intent)
	if action=="face":
		if not SaveGame._battle_point(at):return "invalid_position"
		for f in selected:
			if CityBattleNavigation.point(at)==CityBattleNavigation.point(f["position"]):return "invalid_position"
			if battle["phase"]=="deployment" and f["formation"]=="phalanx" and not room(data,CityBattleNavigation.point(f["position"]),CityBattleNavigation.point(at)-CityBattleNavigation.point(f["position"]),int(battle["gate_integrity"])<=0):return "formation_space"
		for f in selected:
			f["facing_goal"]=CityBattleNavigation.packed((CityBattleNavigation.point(at)-CityBattleNavigation.point(f["position"])).normalized()*1000)
			f["facing_locked"]=true
			if battle["phase"]=="deployment":f["facing"]=f["facing_goal"].duplicate()
		return ""
	for f in selected:
		if int(f["reform_ms"])>0:return "reforming"
		if action=="phalanx":
			if not phalanx_eligible(data,f):return "phalanx_training"
			if not room(data,CityBattleNavigation.point(f["position"]),CityBattleNavigation.point(f["facing"]),int(battle["gate_integrity"])<=0):return "formation_space"
	for f in selected:
		if f["formation"]==action:continue
		f["formation"]=action
		f["reform_ms"]=0 if battle["phase"]=="deployment" else int(rules(data)["reform_ms"])
		f["runup_cm"]=0
	return ""

static func split(data: GameData, battle: Dictionary, selected: Array) -> String:
	if selected.size()!=1:return "cannot_split"
	var f: Dictionary=selected[0]
	var count := int(rules(data)["platoons"])
	if int(f["platoon"])!=0 or f.get("specialty","")=="commander" or int(f["reform_ms"])>0 or int(f["hp"])<count*int(rules(data)["minimum_platoon_strength"])*1000:return "cannot_split"
	for enemy in battle["formations"]:
		if enemy["side"]!=f["side"] and CityBattleSim.active(enemy) and CityBattleNavigation.point(enemy["position"]).distance_to(CityBattleNavigation.point(f["position"]))<=int(CityBattleSim.rules(data)["melee_range_cm"]):return "cannot_split"
	var copies: Array=[]
	var health_left := int(f["hp"])
	var capacity_left := int(f["initial_strength"])
	for index in range(count):
		var part: Dictionary=f.duplicate(true)
		part["id"]=f["id"] if index==0 else String(f["source_id"])+"_p"+str(index+1)
		part["platoon"]=index+1
		part["initial_strength"]=capacity_left/(count-index)
		# Proportional health preserves both total health and capacity exactly.
		part["hp"]=mini(int(part["initial_strength"])*1000,health_left*int(part["initial_strength"])/capacity_left)
		capacity_left-=int(part["initial_strength"]);health_left-=int(part["hp"])
		part["unit"]["strength_pct"]=ceili(float(part["hp"])/1000)
		part["path"]=[];part["order"]="hold";part["target_id"]=""
		part["goal"]=part["position"].duplicate();part["destination"]=part["position"].duplicate()
		part["moving"]=false;part["runup_cm"]=0
		copies.append(part)
	f.merge(copies[0],true)
	for index in range(1,count):battle["formations"].append(copies[index])
	return ""

static func frontage(data: GameData, battle: Dictionary, selected: Array, at: Array, intent: String = "") -> String:
	if intent!="" and intent not in ["move","attack_move","retreat"]:return "invalid_order"
	if at.size()!=4 or not SaveGame._battle_point(at.slice(0,2)) or not SaveGame._battle_point(at.slice(2,4)):return "invalid_position"
	var a := CityBattleNavigation.point(at.slice(0,2))
	var b := CityBattleNavigation.point(at.slice(2,4))
	var span := b-a
	var length := span.length()
	var spacing := int(rules(data)["frontage_min_cm"])
	for f in selected:
		if f["formation"]=="phalanx":spacing=maxi(spacing,2*int(rules(data)["phalanx_half_width_cm"]))
	if length<selected.size()*spacing or length>int(rules(data)["frontage_max_cm"]):return "formation_space"
	var facing := Vector2(-span.y,span.x).normalized()
	var prepared: Array=[]
	for index in range(selected.size()):
		var f: Dictionary=selected[index]
		var dest := a.lerp(b,(index+0.5)/selected.size())
		if not CityBattleNavigation.clear(data.roma_city,CityBattleSim.rules(data),dest) or (battle["phase"]=="deployment" and dest.y>=int(CityBattleSim.rules(data)["deployment_limit_cm"])):return "invalid_position"
		if f["formation"]=="phalanx" and not room(data,dest,facing):return "formation_space"
		var path := CityBattleNavigation.route(CityBattleSim.navigation(data),CityBattleNavigation.point(f["position"]),dest)
		if path.is_empty():return "no_path"
		prepared.append({"dest":CityBattleNavigation.packed(dest),"path":path})
	for index in range(selected.size()):
		var f: Dictionary=selected[index]
		f["goal"]=prepared[index]["dest"].duplicate();f["destination"]=prepared[index]["dest"].duplicate()
		f["path"]=prepared[index]["path"];f["order"]="attack_move" if intent=="" else intent;f["target_id"]="";f["runup_cm"]=0
		f["facing_goal"]=CityBattleNavigation.packed(facing*1000);f["facing_locked"]=true
		if battle["phase"]=="deployment":
			f["position"]=f["destination"].duplicate();f["path"]=[];f["order"]="hold";f["facing"]=f["facing_goal"].duplicate()
	return ""

static func facing_dot(f: Dictionary, other: Dictionary) -> float:
	return CityBattleNavigation.point(f["facing"]).normalized().dot((CityBattleNavigation.point(other["position"])-CityBattleNavigation.point(f["position"])).normalized())

static func formed(f: Dictionary) -> bool:
	return f.get("formation","")=="phalanx" and int(f.get("reform_ms",0))==0

static func damage_multiplier(data: GameData, source: Dictionary, target: Dictionary, charging: bool) -> float:
	if not source.has("source_id"):return 1.0
	var r := rules(data)
	var value := float(source["initial_strength"])/maxf(1,float(source["source_strength"]))
	var front := facing_dot(target,source)>=float(r["front_dot"])
	var rear := facing_dot(target,source)<=float(r["rear_dot"])
	var melee := CityBattleNavigation.point(source["position"]).distance_to(CityBattleNavigation.point(target["position"]))<=int(CityBattleSim.rules(data)["melee_range_cm"])
	if melee:
		if not front:value*=float(r["rear_cavalry_damage"] if rear and source["role"]=="cavalry" else r["rear_damage"] if rear else r["flank_damage"])
		if formed(source):value*=float(r["phalanx_attack"] if facing_dot(source,target)>=float(r["front_dot"]) else r["phalanx_off_front_attack"])
	if formed(target):
		value*=float(r["phalanx_front_resistance"] if front else r["phalanx_rear_resistance"] if rear else r["phalanx_side_resistance"])
		if front and charging:
			# Specialist brace may already have removed this charge bonus.
			if not (int(target.get("ability_remaining_ms",0))>0 and CityBattleSpecialists.profile(data,target).get("stops_charge",false)):
				value/=float(CityBattleSim.rules(data)["charge_multiplier"])
	if int(source["reform_ms"])>0:value*=float(r["forming_damage"])
	if int(target["reform_ms"])>0:value*=float(r["forming_resistance"])
	if target["formation"]=="column":value*=float(r["column_resistance"])
	return value

static func speed_multiplier(data: GameData, f: Dictionary) -> float:
	if not f.has("formation"):return 1.0
	if int(f["reform_ms"])>0:return float(rules(data)["forming_speed"])
	if f["formation"]=="phalanx":return float(rules(data)["phalanx_speed"])
	return float(rules(data)["column_speed"]) if f["formation"]=="column" else 1.0

static func turn_toward(data: GameData, f: Dictionary, desired: Vector2) -> Array:
	var current := CityBattleNavigation.point(f["facing"]).normalized()
	if desired.length_squared()==0:return f["facing"].duplicate()
	var rate := float(rules(data)["phalanx_turn_degrees_per_second"] if f["formation"]=="phalanx" else rules(data)["turn_degrees_per_second"])
	var limit := deg_to_rad(rate)*int(CityBattleSim.rules(data)["tick_ms"])/1000.0
	var turned := current.rotated(clampf(current.angle_to(desired),-limit,limit))
	if formed(f) and not room(data,CityBattleNavigation.point(f["position"]),turned):return f["facing"].duplicate()
	return CityBattleNavigation.packed(turned*1000)

static func survivors(battle: Dictionary, side: String) -> Array:
	## Always restore one campaign unit per original source, in source order.
	var output: Array=[]
	var originals: Array=battle["initial_"+side+"s"]
	for index in range(originals.size()):
		var id := "%s_%d"%[side,index]
		var unit: Dictionary=originals[index].duplicate(true)
		var hp := 0
		var experience := int(unit["experience"])
		for f in battle["formations"]:
			if f.get("source_id",f["id"])!=id:continue
			hp+=int(f.get("hp",int(f["unit"]["strength_pct"])*1000))
			if int(f["unit"]["strength_pct"])>0:experience=maxi(experience,int(f["unit"]["experience"]))
		unit["strength_pct"]=ceili(float(hp)/1000);unit["experience"]=experience
		output.append(unit)
	return output

static func enemy_orders(data: GameData, battle: Dictionary, f: Dictionary) -> void:
	var target := CityBattleSim._target(data,battle,f)
	if target.is_empty():
		if f["order"]=="charge":f["order"]="attack_move";f["target_id"]=""
		return
	var a := CityBattleNavigation.point(f["position"])
	var b := CityBattleNavigation.point(target["position"])
	if not CityBattleNavigation.line_clear(data.roma_city,CityBattleSim.rules(data),a,b,int(battle["gate_integrity"])<=0):return
	if f["role"]=="cavalry" and f["order"]=="attack_move":
		f["order"]="charge";f["target_id"]=target["id"]
	if not phalanx_eligible(data,f) and f["formation"]!="phalanx":return
	if int(f["reform_ms"])==0:
		var fits := route_has_room(data,f)
		if f["formation"]=="phalanx" and not fits:
			command(data,battle,[f],"line",[])
			f["ai_reform_ms"]=int(rules(data)["ai_reform_cooldown_ms"])
		elif phalanx_eligible(data,f) and f["formation"]=="line" and fits and int(f["ai_reform_ms"])==0:command(data,battle,[f],"phalanx",[])

static func route_has_room(data: GameData, f: Dictionary) -> bool:
	var previous := CityBattleNavigation.point(f["position"])
	var facing := CityBattleNavigation.point(f["facing"])
	if not room(data,previous,facing):return false
	# Inspect the next grid connectors before forming; narrow streets require
	# ordinary ranks. Decisions use the saved path and no rendering geometry.
	for point in f["path"].slice(0,int(rules(data)["route_lookahead_points"])):
		var next := CityBattleNavigation.point(point)
		if next!=previous:facing=(next-previous).normalized()
		if not room(data,next,facing) or not room(data,next,CityBattleNavigation.point(f["facing"])):return false
		previous=next
	return true


static func forward_connector(data: GameData, start: Vector2, path: Array) -> Array:
	# Repath can choose a nearest grid cell behind slow troops. Skip that
	# connector only when the entire direct segment to the next cell is clear.
	if path.size()<2:return path
	var first := CityBattleNavigation.point(path[0])
	var next := CityBattleNavigation.point(path[1])
	if (first-start).dot(next-start)>=0:return path
	var tuning := CityBattleSim.rules(data)
	var samples := maxi(1,ceili(start.distance_to(next)/int(tuning["projectile_sample_cm"])))
	for i in range(samples+1):
		if not CityBattleNavigation.clear(data.roma_city,tuning,start.lerp(next,float(i)/samples)):return path
	path.pop_front()
	return path
