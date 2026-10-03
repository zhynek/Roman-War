class_name CityBattleSpecialists
## Optional per-battle extension. Existing battles keep their original rules;
## new battles persist abilities and their fixed-quantum recovery clocks.

static func rules(data: GameData) -> Dictionary:
	return data.balance["city_battle"]["specialists"]

static func specialty(data: GameData, template: String) -> String:
	var tuning := rules(data)
	return String(tuning["templates"].get(template,tuning["classes"].get(data.units.get(template,{}).get("class",""),"")))

static func initialize(data: GameData, battle: Dictionary) -> void:
	battle["specialists_version"]=1
	for f in battle["formations"]:
		f["specialty"]=specialty(data,f["template"])
		f["ability_remaining_ms"]=0
		f["ability_cooldown_ms"]=0

static func profile(data: GameData, f: Dictionary) -> Dictionary:
	return rules(data)["profiles"].get(f.get("specialty",""),{})

static func command(data: GameData, battle: Dictionary, selected: Array) -> String:
	if battle["phase"]!="fighting":return "wrong_phase"
	if not battle.has("specialists_version"):return "no_ability"
	# Validate the entire batch before spending any cooldown.
	for f in selected:
		if profile(data,f).is_empty():return "no_ability"
		if int(f.get("ability_cooldown_ms",0))>0:return "ability_recovering"
	for f in selected:activate(data,f)
	return ""

static func activate(data: GameData, f: Dictionary) -> void:
	var p := profile(data,f)
	f["ability_remaining_ms"]=int(p["duration_ms"])
	f["ability_cooldown_ms"]=int(p["cooldown_ms"])

static func prepare(data: GameData, battle: Dictionary) -> void:
	if not battle.has("specialists_version"):return
	for f in battle["formations"]:
		if not CityBattleSim.active(f):
			f["ability_remaining_ms"]=0
			continue
		# Enemy specialists use the same ability and recovery rules at contact.
		var p := profile(data,f)
		if f["side"]!="attacker" or p.is_empty() or int(f["ability_cooldown_ms"])>0:continue
		for enemy in battle["formations"]:
			if enemy["side"]==f["side"] or not CityBattleSim.active(enemy):continue
			var reach := maxi(int(CityBattleSim.rules(data)["melee_range_cm"]),int(p["radius_cm"]))
			var a := CityBattleNavigation.point(f["position"])
			var b := CityBattleNavigation.point(enemy["position"])
			if a.distance_to(b)<=reach and CityBattleNavigation.line_clear(data.roma_city,CityBattleSim.rules(data),a,b,int(battle["gate_integrity"])<=0):
				activate(data,f)
				break

static func elapse(battle: Dictionary, dt: int) -> void:
	if not battle.has("specialists_version"):return
	for f in battle["formations"]:
		f["ability_remaining_ms"]=maxi(0,int(f["ability_remaining_ms"])-dt) if CityBattleSim.active(f) else 0
		f["ability_cooldown_ms"]=maxi(0,int(f["ability_cooldown_ms"])-dt)

static func rally(data: GameData, battle: Dictionary, f: Dictionary) -> Dictionary:
	if not CityBattleSim.active(f):return {}
	for leader in battle["formations"]:
		if leader["side"]!=f["side"] or leader.get("specialty","")!="commander" or not CityBattleSim.active(leader) or int(leader.get("ability_remaining_ms",0))<=0:continue
		var p := profile(data,leader)
		var a := CityBattleNavigation.point(leader["position"])
		var b := CityBattleNavigation.point(f["position"])
		if a.distance_to(b)<=int(p["radius_cm"]) and CityBattleNavigation.line_clear(data.roma_city,CityBattleSim.rules(data),a,b,int(battle["gate_integrity"])<=0):return p
	return {}

static func damage_multiplier(data: GameData, battle: Dictionary, source: Dictionary, target: Dictionary, charging: bool) -> float:
	var attack := profile(data,source)
	var defense := profile(data,target)
	var value := float(attack.get("damage",1.0))*float(defense.get("resistance",1.0))
	if int(source.get("ability_remaining_ms",0))>0:value*=float(attack.get("active_damage",1.0))
	var protection := 1.0
	if int(target.get("ability_remaining_ms",0))>0 and (not battle.has("tactics_version") or target.get("specialty","")!="spear_guard" or CityBattleTactics.facing_dot(target,source)>=float(CityBattleTactics.rules(data)["front_dot"])):
		protection=float(defense.get("active_resistance",1.0))
		if charging and defense.get("stops_charge",false):value/=float(CityBattleSim.rules(data)["charge_multiplier"])
	# Rally does not stack with itself or multiply another defensive ability.
	protection=minf(protection,float(rally(data,battle,target).get("active_resistance",1.0)))
	return value*protection

static func speed_multiplier(data: GameData, f: Dictionary) -> float:
	return float(profile(data,f).get("active_speed",1.0)) if int(f.get("ability_remaining_ms",0))>0 else 1.0

static func morale_bonus(data: GameData, battle: Dictionary, f: Dictionary) -> int:
	var own := int(profile(data,f).get("morale_bonus",0)) if int(f.get("ability_remaining_ms",0))>0 else 0
	return maxi(own,int(rally(data,battle,f).get("morale_bonus",0)))
