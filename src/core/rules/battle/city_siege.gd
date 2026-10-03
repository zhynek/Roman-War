class_name CitySiegeRules
## Siege equipment and fire advance only in deterministic battle ticks.
## A ram represents its machine and crew; it is not an extra campaign cohort.

static func tuning(data: GameData) -> Dictionary:
	return data.balance["city_battle"]["siege"]

static func defenses(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var city: Dictionary = state.get("city_governance", {}).get(region, {})
	var projects: Dictionary = city.get("projects", {})
	var reinforced: bool = projects.get("reinforce_gate", {}).get("completed", false)
	return {"gate_integrity": int(data.balance["city_battle"]["gate_integrity"])+(int(tuning(data)["gate_bonus"]) if reinforced else 0),
		"fire_prepared": bool(projects.get("prepare_fire_arrows", {}).get("completed", false))}

static func initialize(data: GameData, state: Dictionary, battle: Dictionary) -> void:
	var config := tuning(data)
	var preparation := defenses(data,state,battle["region"])
	battle["gate_integrity"] = preparation["gate_integrity"]
	battle["gate_max_integrity"] = preparation["gate_integrity"]
	battle["fire_prepared"] = preparation["fire_prepared"]
	var gate: Array = data.roma_city["battle"]["spatial"]["gate_cm"]
	battle["siege_engine"] = {"id":"siege_ram", "position":[int(gate[0]), int(gate[1])+int(config["ram_spawn_offset_cm"])],
		"hp":int(config["ram_hp"]), "max_hp":int(config["ram_hp"]), "heat":0, "burning":false,
		"cooldown_ms":0, "attack_seq":0, "moving":false, "crewed":true}

static func command(data: GameData, battle: Dictionary, selected: Array, action: String) -> String:
	if battle["phase"] not in ["deployment","fighting"]:return "wrong_phase"
	for f in selected:
		if f["role"]!="archer":return "archers_only"
	if action=="fire_arrows" and not battle.get("fire_prepared",false):return "fire_unprepared"
	if action=="attack_engine" and int(battle.get("siege_engine",{}).get("hp",0))<=0:return "no_engine"
	for f in selected:
		if action=="fire_arrows":
			f["incendiary"] = not f.get("incendiary",false)
		else:
			f["target_id"]="siege_ram"
			f["order"]="hold"
			f["path"]=[]
			f["fire_at_will"]=true
	return ""

static func event(data: GameData, battle: Dictionary, kind: String, from: Array, to: Array, extra: Dictionary = {}) -> void:
	battle["event_seq"] = int(battle["event_seq"])+1
	var record := {"id":battle["event_seq"], "kind":kind, "from":from.duplicate(), "to":to.duplicate(), "time_ms":int(battle["elapsed_ms"])}
	record.merge(extra)
	battle["events"].append(record)
	while battle["events"].size()>int(tuning(data)["event_limit"]):battle["events"].pop_front()

static func archer_shot(data: GameData, battle: Dictionary, f: Dictionary) -> bool:
	var engine: Dictionary = battle.get("siege_engine",{})
	if engine.is_empty() or int(engine["hp"])<=0 or f["side"]!="defender" or f["role"]!="archer" or not f["fire_at_will"] or f["target_id"]!="siege_ram":return false
	var p := CityBattleNavigation.point(f["position"])
	var target := CityBattleNavigation.point(engine["position"])
	if p.distance_to(target)>int(CityBattleSim.rules(data)["profiles"]["archer"]["range_cm"]):return false
	if not arrow_clear(data,p,target):return false
	if int(f["cooldown_ms"])>0:return true
	var config := tuning(data)
	var fire: bool = f.get("incendiary",false) and battle.get("fire_prepared",false)
	var strength := float(f["unit"]["strength_pct"])/100.0
	engine["hp"]=maxi(0,int(engine["hp"])-maxi(1,roundi(int(config["arrow_damage"])*strength)))
	if fire:
		engine["heat"]=mini(int(config["ignition_heat"]),int(engine["heat"])+maxi(1,roundi(int(config["fire_heat_per_volley"])*strength)))
		engine["burning"]=int(engine["heat"])>=int(config["ignition_heat"])
	f["cooldown_ms"]=int(CityBattleSim.rules(data)["profiles"]["archer"]["attack_ms"])
	f["attack_seq"]=int(f["attack_seq"])+1
	if not battle.has("tactics_version"):f["facing"]=CityBattleNavigation.packed((target-p).normalized()*1000)
	event(data,battle,"fire_volley" if fire else "volley",f["position"],engine["position"],{"source":f["id"],"target":"siege_ram","arc_cm":int(config["arrow_arc_cm"])})
	return true

static func arrow_clear(data: GameData, a: Vector2, b: Vector2) -> bool:
	# Sample the same parabolic arc that presentation draws. Houses and gate
	# masonry occlude at their actual height, not an infinite 2D rectangle.
	var steps := maxi(1,ceili(a.distance_to(b)/int(CityBattleSim.rules(data)["projectile_sample_cm"])))
	var wall := float(data.roma_city["walls"]["half_extent"])
	for i in range(steps+1):
		var t := float(i)/steps
		var p := a.lerp(b,t)/100.0
		var height := 1.7+4.0*float(tuning(data)["arrow_arc_cm"])/100.0*t*(1.0-t)
		for building in data.roma_city["buildings"]:
			var at := CityBattleNavigation.point(building["position"])
			var half := CityBattleNavigation.point(building["size"])*0.5
			if absf(p.x-at.x)<half.x and absf(p.y-at.y)<half.y and height<float(building["height"])+minf(2.8,float(building["size"][1])*0.18):return false
		if absf(p.y-wall)<2.0 and height<float(data.roma_city["walls"]["height"])+1.0:return false
	return true

static func tick(data: GameData, battle: Dictionary) -> void:
	var engine: Dictionary = battle.get("siege_engine",{})
	if engine.is_empty():return # Existing saved battles retain their original siege.
	engine["moving"]=false
	engine["crewed"]=false
	if int(engine["hp"])<=0:return
	var config := tuning(data)
	var dt := int(CityBattleSim.rules(data)["tick_ms"])
	if engine["burning"]:
		engine["hp"]=maxi(0,int(engine["hp"])-int(config["burn_damage_per_second"])*dt/1000)
	if int(engine["hp"])<=0:return
	var p := CityBattleNavigation.point(engine["position"])
	for f in battle["formations"]:
		if f["side"]=="attacker" and CityBattleSim.active(f) and p.distance_to(CityBattleNavigation.point(f["position"]))<=int(config["crew_radius_cm"]):engine["crewed"]=true
	if not engine["crewed"] or int(battle["gate_integrity"])<=0:return
	var goal := CityBattleNavigation.point(data.roma_city["battle"]["spatial"]["gate_cm"])+Vector2(0,int(config["ram_stop_offset_cm"]))
	engine["cooldown_ms"]=maxi(0,int(engine["cooldown_ms"])-dt)
	if p!=goal:
		engine["position"]=CityBattleNavigation.packed(p.move_toward(goal,float(config["ram_speed_cm_s"])*dt/1000.0))
		engine["moving"]=true
	elif int(engine["cooldown_ms"])==0:
		battle["gate_integrity"]=maxi(0,int(battle["gate_integrity"])-int(config["ram_gate_damage"]))
		engine["cooldown_ms"]=int(config["ram_attack_ms"])
		engine["attack_seq"]=int(engine["attack_seq"])+1
		event(data,battle,"ram_hit",engine["position"],data.roma_city["battle"]["spatial"]["gate_cm"])
