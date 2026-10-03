class_name CityBattleRules
## Explicit, deterministic tactical commands over an authored city graph.
## Formations are copies until the terminal result crosses BattleResolver once.
## No scene, timer, frame, or random draw advances the fight.


static func locked(state: Dictionary) -> bool:
	for battle in state.get("city_battles", {}).values():
		if battle.get("phase", "finished") != "finished":
			return true
	return false


static func pending_defense(data: GameData, state: Dictionary, region: String) -> bool:
	return _refusal(data, state, region, false) == ""


static func _refusal(data: GameData, state: Dictionary, region: String, practice: bool, drill: bool = false) -> String:
	if region != data.roma_city.get("region", "") or data.roma_city.get("battle", {}).is_empty():
		return "unsupported_city"
	var settlement: Dictionary = state.get("settlements", {}).get(region, {})
	if settlement.get("owner", "") != state.get("player_faction", ""):
		return "unauthorized"
	if settlement.get("garrison", []).is_empty() and not (practice and drill):
		return "no_garrison"
	if practice:
		return ""
	var siege = settlement.get("siege")
	if not siege is Dictionary:
		return "not_besieged"
	var army: Dictionary = state.get("armies", {}).get(siege.get("besieger", ""), {})
	if army.is_empty() or army.get("region", "") != region or army.get("units", []).is_empty():
		return "invalid_besieger"
	if not DiplomacyRules.at_war(state, String(army["owner"]), String(settlement["owner"])):
		return "not_at_war"
	if not siege.get("equipment_ready", false):
		return "equipment_unready"
	return ""


static func status(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var battle: Dictionary = state.get("city_battles", {}).get(region, {})
	if battle.is_empty():
		return {"ok": true, "reason": _refusal(data, state, region, false), "active": false,
			"can_drill": not locked(state) and _refusal(data,state,region,true,true)=="",
			"can_practice": not locked(state) and _refusal(data, state, region, true) == "",
			"can_defend": not locked(state) and _refusal(data, state, region, false) == ""}
	var report := {}
	for key in ["phase", "region", "practice", "tick", "gate_integrity", "objective_progress",
			"formations", "result", "committed"]:
		report[key] = battle[key]
	for key in ["model_version", "paused", "speed", "elapsed_ms", "capture_ms", "events", "event_seq", "siege_engine", "fire_prepared", "gate_max_integrity", "specialists_version", "tactics_version"]:
		if battle.has(key): report[key] = battle[key]
	report["active"] = true
	report["ok"] = true
	report["reason"] = _command_reason(data, state, battle) if battle["phase"] != "finished" else ""
	return report.duplicate(true)


static func begin(data: GameData, state: Dictionary, region: String, practice: bool, drill: bool = false) -> Dictionary:
	if locked(state) or state.get("city_battles", {}).has(region):
		return _error("battle_active")
	var reason := _refusal(data, state, region, practice, drill)
	if reason != "":
		return _error(reason)
	var graph: Dictionary = data.roma_city["battle"]
	var settlement: Dictionary = state["settlements"][region]
	var defenders: Array = settlement["garrison"].duplicate(true)
	if practice and drill:
		defenders=[]
		for template in CityBattleTactics.rules(data)["drill_units"]:
			defenders.append({"template":template,"strength_pct":100,"experience":int(CityBattleTactics.rules(data)["phalanx_experience"]),"weapon":0,"armor":0})
	var attackers: Array = []
	var context := {"terrain": data.regions[region]["terrain"], "wall_level": int(SettlementRules.effect_max(data, settlement, "wall_level"))}
	var besieger := ""
	if practice:
		for template in graph["practice_attackers"]:
			attackers.append({"template": template, "strength_pct": 100, "experience": 0, "weapon": 0, "armor": 0})
		context["defender_mods"] = KnowledgeRules.army_mods(data, state, String(settlement["owner"]))
		context["defender_martial"] = SocietyRules.faction_stocks_for(data, state, String(settlement["owner"]))["martial_ethos"]
	else:
		besieger = String(settlement["siege"]["besieger"])
		attackers = state["armies"][besieger]["units"].duplicate(true)
		context = SiegeRules.assault_context(data, state, state["armies"][besieger], region, false)
	# Normalize floating context once so a JSON save resumes bit-for-bit.
	context = JSON.parse_string(JSON.stringify(context))
	var formations: Array = []
	for side in ["attacker", "defender"]:
		var units: Array = attackers if side == "attacker" else defenders
		for index in range(units.size()):
			var unit: Dictionary = units[index].duplicate(true)
			formations.append({"id": "%s_%d" % [side, index], "side": side,
				"template": unit["template"], "unit": unit, "initial_strength": int(unit["strength_pct"]),
				"node": graph["attacker_entry"] if side == "attacker" else graph["defender_entry"],
				"target": graph["objective"] if side == "attacker" else graph["defender_entry"]})
	var node_ids: Array = []
	for node in graph["nodes"]:
		node_ids.append(node["id"])
	var battle := {"region": region, "owner": settlement["owner"], "practice": practice,
		"phase": "deployment", "tick": 0, "gate_integrity": int(data.balance["city_battle"]["gate_integrity"]),
		"objective_progress": 0, "formations": formations, "result": {}, "committed": false,
		"besieger": besieger, "context": context, "node_ids": node_ids,
		"graph_signature": JSON.stringify(graph), "source": _source(state, region, besieger),
		"initial_attackers": attackers, "initial_defenders": defenders}
	if data.city_battle_navigation.is_empty():
		data.city_battle_navigation = CityBattleNavigation.build(data.roma_city, CityBattleSim.rules(data))
	CityBattleSim.initialize(data, battle)
	CitySiegeRules.initialize(data, state, battle)
	CityBattleSpecialists.initialize(data, battle)
	CityBattleTactics.initialize(battle)
	if not state.has("city_battles"):
		state["city_battles"] = {}
	state["city_battles"][region] = battle
	return status(data, state, region)


static func order(data: GameData, state: Dictionary, region: String, formation_id: String, node_id: String) -> Dictionary:
	var battle := _session(state, region)
	var reason := _command_reason(data, state, battle)
	if reason != "":
		return _error(reason)
	if not battle["node_ids"].has(node_id):
		return _error("unknown_node")
	if battle["phase"] == "deployment" and not data.roma_city["battle"]["deployment_nodes"].has(node_id):
		return _error("outside_deployment")
	for formation in battle["formations"]:
		if formation["id"] != formation_id:
			continue
		if formation["side"] != "defender" or int(formation["unit"]["strength_pct"]) <= 0:
			return _error("invalid_formation")
		if int(battle.get("model_version", 1)) >= 2:
			var target_position: Array = _nodes(data)[node_id]["position"]
			var command_reason := CityBattleSim.command(data, battle, [formation_id], "move", [roundi(target_position[0]*100), roundi(target_position[1]*100)])
			if command_reason != "": return _error(command_reason)
		formation["target"] = node_id
		if battle["phase"] == "deployment":
			formation["node"] = node_id
		return status(data, state, region)
	return _error("invalid_formation")


static func start(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var battle := _session(state, region)
	var reason := _command_reason(data, state, battle)
	if reason != "":
		return _error(reason)
	if battle["phase"] != "deployment":
		return _error("wrong_phase")
	battle["phase"] = "fighting"
	if battle.has("paused"): battle["paused"] = false
	return status(data, state, region)


static func step(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var battle := _session(state, region)
	var reason := _command_reason(data, state, battle)
	if reason != "":
		return _error(reason)
	if battle["phase"] != "fighting":
		return _error("wrong_phase")
	if int(battle.get("model_version", 1)) >= 2:
		if data.city_battle_navigation.is_empty():
			data.city_battle_navigation = CityBattleNavigation.build(data.roma_city, CityBattleSim.rules(data))
		CityBattleSim.tick(data, state, battle)
		return status(data, state, region)
	var tuning: Dictionary = data.balance["city_battle"]
	var nodes := _nodes(data)
	var gate := ""
	for id in nodes:
		if nodes[id]["role"] == "gate":
			gate = id
	var formations: Array = battle["formations"]
	var positions := {}
	var gate_hits := 0
	for formation in formations:
		if not _alive(formation):
			continue
		var node := String(formation["node"])
		positions[formation["id"]] = node
		if formation["side"] == "attacker" and int(battle["gate_integrity"]) > 0 and nodes[node]["neighbors"].has(gate):
			gate_hits += 1
			continue
		# A formation blocks its occupied node; adjacent flank fire does not
		# seal an otherwise clear street or prevent a push onto the objective.
		var next := _next_node(nodes, node, String(formation["target"]))
		if next == "" or (next == gate and int(battle["gate_integrity"]) > 0):
			continue
		var blocked := false
		for enemy in formations:
			if not _alive(enemy) or enemy["side"] == formation["side"]:
				continue
			if enemy["node"] == next or enemy["node"] == node:
				blocked = true
		if not blocked:
			positions[formation["id"]] = next
	battle["gate_integrity"] = maxi(0, int(battle["gate_integrity"]) - gate_hits * int(tuning["gate_damage_per_formation"]))
	for formation in formations:
		if positions.has(formation["id"]):
			formation["node"] = positions[formation["id"]]
	# Damage is accumulated from the same pre-casualty snapshot for both sides.
	var damage := {}
	for formation in formations:
		if not _alive(formation):
			continue
		var is_attacker: bool = formation["side"] == "attacker"
		var template: Dictionary = data.units[formation["template"]]
		var reach := int(tuning["missile_range"]) if float(template.get("missile_attack", 0)) > 0 else int(tuning["melee_range"])
		var target: Dictionary = {}
		var best_distance := reach + 1
		for enemy in formations:
			if not _alive(enemy) or enemy["side"] == formation["side"]:
				continue
			var distance := _distance(nodes, String(formation["node"]), String(enemy["node"]))
			if distance < best_distance:
				target = enemy
				best_distance = distance
		if target.is_empty():
			continue
		var context: Dictionary = battle["context"].duplicate(true)
		# Walls help only the gate approach. An open square offers no rampart.
		if formation["node"] != gate and target["node"] != gate:
			context["wall_level"] = 0
		var estimate := BattleResolver.estimate(data,
			[formation["unit"]] if is_attacker else [target["unit"]],
			[target["unit"]] if is_attacker else [formation["unit"]], context)
		var strength := float(estimate[formation["side"]]["strength"])
		var opposition := float(estimate[target["side"]]["strength"])
		var ratio := clampf(strength / maxf(1.0, opposition), float(tuning["minimum_damage_ratio"]), float(tuning["maximum_damage_ratio"]))
		var hit := maxi(1, int(round(float(tuning["casualty_pct_per_step"]) * ratio)))
		damage[target["id"]] = int(damage.get(target["id"], 0)) + hit
	for formation in formations:
		var unit: Dictionary = formation["unit"]
		unit["strength_pct"] = maxi(0, int(unit["strength_pct"]) - int(damage.get(formation["id"], 0)))
	battle["tick"] = int(battle["tick"]) + 1
	var attackers_left := false
	var defenders_left := false
	var occupying := false
	var contesting := false
	var objective: String = data.roma_city["battle"]["objective"]
	for formation in formations:
		if not _alive(formation):
			continue
		if formation["side"] == "attacker":
			attackers_left = true
			occupying = occupying or formation["node"] == objective
		else:
			defenders_left = true
			contesting = contesting or formation["node"] == objective
	battle["objective_progress"] = int(battle["objective_progress"]) + 1 if occupying and not contesting else 0
	if not attackers_left:
		_finish(data, state, battle, "defender", "attackers_defeated")
	elif not defenders_left:
		_finish(data, state, battle, "attacker", "defenders_defeated")
	elif int(battle["objective_progress"]) >= int(tuning["objective_hold_steps"]):
		_finish(data, state, battle, "attacker", "forum_captured")
	elif int(battle["tick"]) >= int(tuning["maximum_steps"]):
		_finish(data, state, battle, "defender", "assault_exhausted")
	return status(data, state, region)


static func close(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var battle := _session(state, region)
	if battle.is_empty():
		return _error("no_battle")
	if not battle["practice"] and battle["phase"] == "fighting" and _command_reason(data, state, battle) != "stale_battle":
		return _error("battle_unfinished")
	state["city_battles"].erase(region)
	return {"ok": true, "reason": ""}


static func _finish(data: GameData, state: Dictionary, battle: Dictionary, winner: String, cause: String) -> void:
	var estimate := BattleResolver.estimate(data, battle["initial_attackers"], battle["initial_defenders"], battle["context"])
	var ratio := float(estimate["ratio"])
	var underdog := float(data.balance["battle"]["underdog_strength_ratio"])
	var was_underdog := ratio * underdog <= 1.0 if winner == "attacker" else ratio >= underdog
	var experience := int(data.balance["battle"]["experience_gain_underdog"] if was_underdog else data.balance["battle"]["experience_gain_on_victory"])
	for formation in battle["formations"]:
		if formation["side"] == winner and _alive(formation):
			formation["unit"]["experience"] = mini(int(formation["unit"]["experience"]) + experience, int(data.balance["recruitment"]["experience_max"]))
	var result := {"winner": winner, "cause": cause, "experience_gained": experience,
		"attacker_general_died": false, "defender_general_died": false, "walkover": false}
	for side in ["attacker", "defender"]:
		var before := 0
		var after := 0
		var report: Array = []
		var survivors := CityBattleTactics.survivors(battle,side)
		for index in range(survivors.size()):
			var unit: Dictionary=survivors[index]
			var original: Dictionary=battle["initial_"+side+"s"][index]
			var full := int(data.units[unit["template"]]["soldiers"])
			before += ceili(float(full * int(original["strength_pct"])) / 100.0)
			after += ceili(float(full * int(unit["strength_pct"])) / 100.0)
			report.append({"template":unit["template"],"strength_before":original["strength_pct"],
				"strength_after":unit["strength_pct"],"destroyed":int(unit["strength_pct"])<=0})
		result[side + "_casualty_pct"] = SocietyRules.quantize(100.0 * float(before - after) / maxf(1.0, float(before)))
		result[side + "_destroyed"] = after == 0
		result[side + "_report"] = report
	battle["result"] = result
	battle["phase"] = "finished"
	if battle["practice"]:
		return
	# Existing siege/capture bookkeeping is the sole campaign commit path.
	var rng := CampaignRng.from_state_string(String(state["rng_state"]))
	var tactical := CityBattleResolver.new(battle)
	var outcome := SiegeRules.assault(data, state, rng, tactical, String(battle["besieger"]), String(battle["region"]))
	if outcome.get("captured", false):
		var general = state["armies"].get(battle["besieger"], {}).get("general")
		outcome["capture"] = CombatRules.capture_settlement(data, state, rng, String(battle["region"]), String(outcome["capture_pending_owner"]), "occupy")
		var notices: Array = outcome.get("character_notices", [])
		CombatRules.fire_occupation_triggers(data, state, rng, general, "occupy", notices)
		outcome["character_notices"] = notices
		AiMilitary._garrison_captured(data, state, String(battle["besieger"]))
	if state["armies"].has(battle["besieger"]):
		state["armies"][battle["besieger"]]["movement_left"] = 0.0
	state["rng_state"] = rng.state_string()
	battle["result"] = outcome
	battle["committed"] = true


static func _source(state: Dictionary, region: String, besieger: String) -> String:
	var settlement: Dictionary = state.get("settlements", {}).get(region, {})
	var army: Dictionary = state.get("armies", {}).get(besieger, {}).duplicate(true)
	var garrison: Array = settlement.get("garrison", []).duplicate(true)
	# Zero armament is an additive save default, not a changed military source.
	for units in [garrison, army.get("units", [])]:
		for unit in units:
			unit["weapon"] = int(unit.get("weapon", 0))
			unit["armor"] = int(unit.get("armor", 0))
	return JSON.stringify(JSON.parse_string(JSON.stringify({"turn": state.get("turn", 0), "owner": settlement.get("owner", ""),
		"garrison": garrison, "governor": settlement.get("governor"),
		"siege": settlement.get("siege"), "army": army, "player": state.get("player_faction", "")})))


static func _command_reason(data: GameData, state: Dictionary, battle: Dictionary) -> String:
	if battle.is_empty():
		return "no_battle"
	if battle["phase"] == "finished":
		return "battle_finished"
	if battle.has("layout_signature") and battle["layout_signature"] != JSON.stringify(data.roma_city):
		return "stale_battle"
	for formation in battle["formations"]:
		if not data.units.has(formation["template"]):
			return "stale_battle"
	if battle["graph_signature"] != JSON.stringify(data.roma_city.get("battle", {})):
		return "stale_battle"
	if battle["source"] != _source(state, String(battle["region"]), String(battle["besieger"])):
		return "stale_battle"
	if not battle["practice"]:
		if _refusal(data, state, String(battle["region"]), false) != "":
			return "stale_battle"
		var context := SiegeRules.assault_context(data, state, state["armies"][battle["besieger"]], String(battle["region"]), false)
		if JSON.stringify(JSON.parse_string(JSON.stringify(context))) != JSON.stringify(battle["context"]):
			return "stale_battle"
	return ""


static func _session(state: Dictionary, region: String) -> Dictionary:
	return state.get("city_battles", {}).get(region, {})


static func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _alive(formation: Dictionary) -> bool:
	return int(formation["unit"]["strength_pct"]) > 0


static func _nodes(data: GameData) -> Dictionary:
	var result := {}
	for node in data.roma_city["battle"]["nodes"]:
		result[node["id"]] = node
	return result


static func _next_node(nodes: Dictionary, source: String, target: String) -> String:
	if source == target:
		return ""
	var queue: Array = [source]
	var previous := {source: ""}
	for current in queue:
		var neighbors: Array = nodes[current]["neighbors"].duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if previous.has(neighbor):
				continue
			previous[neighbor] = current
			if neighbor == target:
				var cursor: String = target
				while previous[cursor] != source:
					cursor = previous[cursor]
				return cursor
			queue.append(neighbor)
	return ""


static func _distance(nodes: Dictionary, source: String, target: String) -> int:
	var cursor := source
	var distance := 0
	while cursor != target and distance <= nodes.size():
		cursor = _next_node(nodes, cursor, target)
		if cursor == "":
			return nodes.size() + 1
		distance += 1
	return distance


static func command(data: GameData, state: Dictionary, region: String, ids: Array, action: String, position: Array = [], target: String = "") -> Dictionary:
	var battle := _session(state, region)
	var reason := _command_reason(data, state, battle)
	if reason != "": return _error(reason)
	if int(battle.get("model_version",1)) < 2: return _error("stale_battle")
	if data.city_battle_navigation.is_empty():
		data.city_battle_navigation = CityBattleNavigation.build(data.roma_city, CityBattleSim.rules(data))
	reason = CityBattleSim.command(data,battle,ids,action,position,target)
	return status(data,state,region) if reason == "" else _error(reason)


static func control(data: GameData, state: Dictionary, region: String, action: String) -> Dictionary:
	var battle := _session(state,region)
	var reason := _command_reason(data,state,battle)
	if reason != "": return _error(reason)
	if not battle.has("paused"): return _error("stale_battle")
	if action == "pause": battle["paused"] = true
	elif action == "resume": battle["paused"] = false
	elif action == "speed": battle["speed"] = 2 if int(battle["speed"]) == 1 else 1
	else: return _error("invalid_order")
	return status(data,state,region)
