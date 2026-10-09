class_name SaveGame
## Save/load is nothing more than JSON round-tripping the GameState dict —
## by design. Data tables are content, not state, so only the state travels.

const SAVE_VERSION := 2


static func to_json(state: Dictionary) -> String:
	return JSON.stringify({"version": SAVE_VERSION, "state": state}, "\t")


static func from_json(text: String) -> Dictionary:
	## Returns the state dict, or {} on failure. JSON numbers arrive as floats;
	## the engine int()-coerces on read, so no fixup pass is needed. The one
	## precision-critical field, rng_state, travels as a string (see CampaignRng).
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	var parsed: Dictionary = json.data
	# Do not coerce strings, booleans or fractional versions into version 2.
	var version = parsed.get("version")
	if not _number(version) or version != SAVE_VERSION:
		return {}
	var state = parsed.get("state")
	return state if _valid_state(state) else {}


static func write_file(state: Dictionary, path: String) -> bool:
	var text := to_json(state)
	if from_json(text).is_empty():
		return false
	# Stage beside the destination so rename stays on the same filesystem.
	# Never truncate the live save, even if writing/validating the stage fails.
	var staged := path + ".tmp"
	if not _write_verified(text, staged):
		return false
	var previous := _read_text(path)
	if not from_json(previous).is_empty():
		# Keep the PREVIOUS valid save. A corrupt primary must not replace a
		# good backup. Stage the backup too, leaving both old files on failure.
		var backup_stage := path + ".bak.tmp"
		if not _write_verified(previous, backup_stage):
			_remove_file(staged)
			return false
		if DirAccess.rename_absolute(backup_stage, path + ".bak") != OK:
			_remove_file(backup_stage)
			_remove_file(staged)
			return false
	if DirAccess.rename_absolute(staged, path) != OK:
		_remove_file(staged)
		return false
	return true


static func read_file(path: String) -> Dictionary:
	var state := from_json(_read_text(path))
	# Recovery is read-only: preserve a damaged primary for diagnosis and
	# never rewrite the backup merely because the player presses Load.
	return state if not state.is_empty() else from_json(_read_text(path + ".bak"))


static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func _write_verified(text: String, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	var written := _read_text(path)
	if error != OK or written != text or from_json(written).is_empty():
		_remove_file(path)
		return false
	return true


static func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _valid_state(state: Variant) -> bool:
	## Structural boundary for the original campaign and load migrations.
	## Additive fields remain optional; unknown keys are retained unchanged.
	## This deliberately does not validate content ids against today's tables
	## or repair a damaged world by inventing missing factions/forces.
	if not _fields(state, {
		"turn": TYPE_FLOAT, "year": TYPE_FLOAT, "next_id": TYPE_FLOAT,
		"season": TYPE_STRING, "rng_state": TYPE_STRING, "player_faction": TYPE_STRING,
		"factions": TYPE_DICTIONARY, "settlements": TYPE_DICTIONARY,
		"armies": TYPE_DICTIONARY, "fleets": TYPE_DICTIONARY,
		"characters": TYPE_DICTIONARY, "events_fired": TYPE_ARRAY,
	}):
		return false
	if not _nullable_fields(state, {"winner": TYPE_STRING}):
		return false
	if not state["rng_state"].is_valid_int() or not state["factions"].has(state["player_faction"]):
		return false
	if not _fields(state, {
		"modifiers": TYPE_ARRAY, "chronicle": TYPE_ARRAY, "wars": TYPE_ARRAY,
		"tributes": TYPE_ARRAY, "pending_offers": TYPE_ARRAY, "sites_explored": TYPE_ARRAY,
		"agents": TYPE_DICTIONARY, "watchposts": TYPE_DICTIONARY,
		"forest_patrols": TYPE_DICTIONARY, "cartography": TYPE_DICTIONARY,
		"settlement_memory": TYPE_DICTIONARY,
		"map_access": TYPE_DICTIONARY, "recon": TYPE_DICTIONARY,
		"waterworks": TYPE_DICTIONARY, "naval_report": TYPE_DICTIONARY,
		"city_governance": TYPE_DICTIONARY, "city_battles": TYPE_DICTIONARY, "city_campaign": TYPE_DICTIONARY,
		"advisor_unlocks": TYPE_DICTIONARY, "patronage": TYPE_DICTIONARY, "advisor_tutorial": TYPE_DICTIONARY, "divine_dilemmas": TYPE_DICTIONARY,
		"journal": TYPE_DICTIONARY, "ai": TYPE_DICTIONARY, "guided": TYPE_DICTIONARY,
		"event_cooldowns": TYPE_DICTIONARY, "mercenary_pools": TYPE_DICTIONARY,
	}, true):
		return false
	if state.has("patronage") and not _valid_patronage(state.patronage, state):return false
	if state.has("advisor_tutorial") and not _valid_advisor_tutorial(state.advisor_tutorial,state):return false
	if state.has("divine_dilemmas") and not _valid_divine_dilemmas(state.divine_dilemmas,state):return false
	for unlock in state.get("advisor_unlocks", {}).values():
		if not _fields(unlock, {"turn":TYPE_FLOAT,"region":TYPE_STRING}):return false
		if not _whole_at_least(unlock.turn,0) or unlock.turn > state.turn:return false
		if not state.settlements.has(unlock.region):return false
	for faction in state["factions"].values():
		if not _fields(faction, {"treasury": TYPE_FLOAT, "capital": TYPE_STRING,
			"alive": TYPE_BOOL, "era": TYPE_STRING, "diplomacy": TYPE_DICTIONARY,
			"senate_standing": TYPE_FLOAT, "popular_standing": TYPE_FLOAT, "at_civil_war": TYPE_BOOL}):
			return false
		if not _nullable_fields(faction, {"mission": TYPE_DICTIONARY}):
			return false
		if not _fields(faction, {"society": TYPE_DICTIONARY, "ai": TYPE_DICTIONARY,
			"attitude_memory": TYPE_DICTIONARY, "knowledge": TYPE_DICTIONARY,
			"edicts": TYPE_DICTIONARY, "edict_cooldowns": TYPE_DICTIONARY,
			"war_record": TYPE_DICTIONARY, "reign": TYPE_DICTIONARY,
			"advances": TYPE_ARRAY}, true):
			return false
	for settlement in state["settlements"].values():
		if not _fields(settlement, {"owner": TYPE_STRING, "population": TYPE_FLOAT,
			"buildings": TYPE_DICTIONARY, "tax_level": TYPE_STRING,
			"construction_queue": TYPE_ARRAY, "recruitment_queue": TYPE_ARRAY,
			"garrison": TYPE_ARRAY}):
			return false
		if not _nullable_fields(settlement, {"governor": TYPE_STRING, "siege": TYPE_DICTIONARY}):
			return false
		if not _fields(settlement, {"harbour": TYPE_ARRAY, "society": TYPE_DICTIONARY,
			"edict": TYPE_DICTIONARY}, true):
			return false
		if not _units(settlement["garrison"]) or not _units(settlement.get("harbour", [])):
			return false
		for job in settlement["recruitment_queue"]:
			if not job is Dictionary: return false
			if job.has("city_days_left") and not _whole_at_least(job["city_days_left"],1): return false
	for army in state["armies"].values():
		if not _fields(army, {"owner": TYPE_STRING, "region": TYPE_STRING,
			"movement_left": TYPE_FLOAT, "units": TYPE_ARRAY}) or not _units(army["units"]):
			return false
		if not _nullable_fields(army, {"general": TYPE_STRING}):
			return false
		if not _fields(army, {"march_path": TYPE_ARRAY}, true):
			return false
	if state.has("waterworks"):
		var works: Dictionary = state["waterworks"]
		if not _fields(works, {"landings": TYPE_DICTIONARY, "bridges": TYPE_DICTIONARY, "projects": TYPE_ARRAY}):
			return false
		for project in works["projects"]:
			if not _fields(project, {"region": TYPE_STRING, "other": TYPE_STRING, "owner": TYPE_STRING, "kind": TYPE_STRING, "key": TYPE_STRING, "turns": TYPE_FLOAT}):
				return false
			if not project["kind"] in ["landing", "bridge", "boat"] or not _whole_at_least(project["turns"], 1):
				return false
	for fleet in state["fleets"].values():
		if not _fields(fleet, {"owner": TYPE_STRING, "sea_zone": TYPE_STRING,
			"movement_left": TYPE_FLOAT, "ships": TYPE_ARRAY}) or not _units(fleet["ships"]):
			return false
		if not _fields(fleet, {"cargo": TYPE_DICTIONARY, "trade_route": TYPE_DICTIONARY, "sail_path": TYPE_ARRAY, "sail_mode": TYPE_STRING}, true):
			return false
		for zone in fleet.get("sail_path", []):
			if not zone is String:
				return false
		var cargo: Dictionary = fleet.get("cargo", {})
		if not cargo.is_empty():
			if not _fields(cargo, {"id": TYPE_STRING, "army": TYPE_DICTIONARY}) or state["armies"].has(cargo["id"]):
				return false
			var army: Dictionary = cargo["army"]
			if not _fields(army, {"owner": TYPE_STRING, "region": TYPE_STRING, "movement_left": TYPE_FLOAT, "units": TYPE_ARRAY}) or not _units(army["units"]) or not _nullable_fields(army, {"general": TYPE_STRING}):
				return false
			if army["owner"] != fleet["owner"]:
				return false
		var route: Dictionary = fleet.get("trade_route", {})
		if not route.is_empty():
			if not _fields(route, {"from": TYPE_STRING, "to": TYPE_STRING, "from_zone": TYPE_STRING, "to_zone": TYPE_STRING, "heading": TYPE_STRING, "paid_turn": TYPE_FLOAT, "paused": TYPE_BOOL}):
				return false
			if not route["heading"] in ["from", "to"]:
				return false
	for character in state["characters"].values():
		if not _fields(character, {"faction": TYPE_STRING, "name": TYPE_STRING,
			"alive": TYPE_BOOL, "role": TYPE_STRING, "location": TYPE_STRING,
			"trait_points": TYPE_DICTIONARY, "ancillaries": TYPE_ARRAY}):
			return false
		if not _fields(character, {"deeds": TYPE_DICTIONARY, "offices_held": TYPE_ARRAY}, true):
			return false
	# These optional entities are dereferenced by geographic migration before
	# ensure_state_keys returns. Missing collections still migrate normally.
	for agent in state.get("agents", {}).values():
		if not _fields(agent, {"owner": TYPE_STRING, "region": TYPE_STRING}):
			return false
	for post in state.get("watchposts", {}).values():
		if not _fields(post, {"owner": TYPE_STRING, "level": TYPE_FLOAT}):
			return false
	for region_id in state.get("city_governance", {}):
		if not state["settlements"].has(region_id) or not _valid_city(state["city_governance"][region_id]):
			return false
	for region_id in state.get("city_campaign", {}):
		if not state["settlements"].has(region_id) or not _valid_city_campaign(state["city_campaign"][region_id], int(state["turn"])):
			return false
	var active_battles := 0
	for region_id in state.get("city_battles", {}):
		var battle = state["city_battles"][region_id]
		if not state["settlements"].has(region_id) or not _valid_city_battle(battle, String(region_id)):
			return false
		if battle["phase"] != "finished":
			active_battles += 1
	if active_battles > 1:
		return false
	for recipients in state.get("map_access", {}).values():
		if not recipients is Array:
			return false
	for memory in state.get("settlement_memory", {}).values():
		if not memory is Dictionary:
			return false
		for report in memory.values():
			if not _fields(report, {"owner": TYPE_STRING, "level": TYPE_STRING,
				"population": TYPE_FLOAT, "buildings": TYPE_ARRAY,
				"turn": TYPE_FLOAT, "watchpost": TYPE_DICTIONARY}):
				return false
			if not Constants.SETTLEMENT_LEVELS.has(report["level"]) or not _whole_at_least(report["population"], 0) or not _whole_at_least(report["turn"], 0) or int(report["turn"]) > int(state["turn"]):
				return false
			for building in report["buildings"]:
				if not building is String:
					return false
			if not _fields(report, {"construction": TYPE_ARRAY}, true):
				return false
			for building in report.get("construction", []):
				if not building is String:
					return false
			if not report["watchpost"].is_empty() and not _fields(report["watchpost"], {"owner": TYPE_STRING, "level": TYPE_FLOAT}):
				return false
	return true


static func _valid_city_campaign(record: Variant, current_turn: int) -> bool:
	if not _fields(record, {"active": TYPE_BOOL, "history": TYPE_ARRAY}):
		return false
	var previous_turn := -1
	for row in record["history"]:
		if not _fields(row, {"kind": TYPE_STRING, "turn": TYPE_FLOAT, "year": TYPE_FLOAT,
			"season": TYPE_STRING, "owner": TYPE_STRING, "population": TYPE_FLOAT,
			"treasury": TYPE_FLOAT, "garrison_soldiers": TYPE_FLOAT, "civic_day": TYPE_FLOAT,
			"population_delta": TYPE_FLOAT, "treasury_delta": TYPE_FLOAT, "garrison_delta": TYPE_FLOAT,
			"civic_days_advanced": TYPE_FLOAT, "unfunded_civic_days": TYPE_FLOAT,
			"civic_reason": TYPE_STRING, "stop_reason": TYPE_STRING,
			"completed_projects": TYPE_ARRAY, "completed_units": TYPE_ARRAY}):
			return false
		if not row["kind"] in ["initial", "season"] or not row["season"] in ["summer", "winter"]:
			return false
		for key in ["turn", "population", "garrison_soldiers", "civic_days_advanced", "unfunded_civic_days"]:
			if not _whole_at_least(row[key], 0):
				return false
		if not _whole_at_least(row["civic_day"], 1) or int(row["turn"]) <= previous_turn or int(row["turn"]) > current_turn:
			return false
		if float(row["year"]) != floor(float(row["year"])) or int(row["year"]) == 0:
			return false
		for key in ["treasury", "population_delta", "treasury_delta", "garrison_delta"]:
			if float(row[key]) != floor(float(row[key])):
				return false
		if not _fields(row, {"completed_buildings": TYPE_ARRAY}, true):
			return false
		for key in ["completed_projects", "completed_units", "completed_buildings"]:
			for id in row.get(key, []):
				if not id is String or id == "":
					return false
		previous_turn = int(row["turn"])
	return true


static func _valid_city_battle(battle: Variant, region: String) -> bool:
	if not _fields(battle, {"region": TYPE_STRING, "owner": TYPE_STRING, "phase": TYPE_STRING,
		"practice": TYPE_BOOL, "committed": TYPE_BOOL, "tick": TYPE_FLOAT,
		"gate_integrity": TYPE_FLOAT, "objective_progress": TYPE_FLOAT,
		"formations": TYPE_ARRAY, "result": TYPE_DICTIONARY, "context": TYPE_DICTIONARY,
		"node_ids": TYPE_ARRAY, "besieger": TYPE_STRING, "source": TYPE_STRING,
		"graph_signature": TYPE_STRING, "initial_attackers": TYPE_ARRAY, "initial_defenders": TYPE_ARRAY}):
		return false
	if battle["region"] != region or battle["owner"] == "" or not battle["phase"] in ["deployment", "fighting", "finished"]:
		return false
	for key in ["tick", "gate_integrity", "objective_progress"]:
		if not _whole_at_least(battle[key], 0):
			return false
	if battle["phase"] == "deployment" and int(battle["tick"]) != 0:
		return false
	if battle["committed"] and (battle["phase"] != "finished" or battle["practice"]):
		return false
	if not battle["practice"] and (battle["besieger"] == "" or (battle["phase"] == "finished" and not battle["committed"])):
		return false
	if battle["phase"] == "finished":
		if not battle["result"].get("winner", "") in ["attacker", "defender"]:
			return false
	elif not battle["result"].is_empty():
		return false
	var graph = JSON.parse_string(battle["graph_signature"])
	var source = JSON.parse_string(battle["source"])
	if not graph is Dictionary or not source is Dictionary or not graph.get("nodes") is Array:
		return false
	if not _fields(source, {"turn": TYPE_FLOAT, "owner": TYPE_STRING, "garrison": TYPE_ARRAY,
		"army": TYPE_DICTIONARY, "player": TYPE_STRING}) or not _units(source["garrison"]):
		return false
	if not _nullable_fields(source, {"siege": TYPE_DICTIONARY, "governor": TYPE_STRING}):
		return false
	if not _fields(battle["context"], {"terrain": TYPE_STRING, "wall_level": TYPE_FLOAT}):
		return false
	if not _fields(battle["context"], {"attacker_martial": TYPE_FLOAT, "defender_martial": TYPE_FLOAT,
		"attacker_mods": TYPE_DICTIONARY, "defender_mods": TYPE_DICTIONARY, "attacker_fatigued": TYPE_BOOL, "sally": TYPE_BOOL}, true):
		return false
	for side in ["attacker", "defender"]:
		if not _valid_city_battle_mods(battle["context"].get(side + "_mods", {})):
			return false
		var general = battle["context"].get(side + "_general")
		if general != null and not _fields(general, {"command": TYPE_FLOAT, "troop_morale": TYPE_FLOAT}, true):
			return false
	var nodes := {}
	for id in battle["node_ids"]:
		if not id is String or id == "" or nodes.has(id):
			return false
		nodes[id] = true
	if nodes.is_empty() or graph["nodes"].size() != nodes.size():
		return false
	var graph_ids := {}
	for node in graph["nodes"]:
		if not _fields(node, {"id": TYPE_STRING, "neighbors": TYPE_ARRAY, "role": TYPE_STRING, "position": TYPE_ARRAY}):
			return false
		if not nodes.has(node["id"]) or graph_ids.has(node["id"]):
			return false
		graph_ids[node["id"]] = true
		for neighbor in node["neighbors"]:
			if not neighbor is String or not nodes.has(neighbor):
				return false
	var originals := {}
	for side in ["attacker", "defender"]:
		var units: Array = battle["initial_" + side + "s"]
		if units.is_empty() or not _units(units):
			return false
		for index in range(units.size()):
			var unit: Dictionary = units[index]
			if not _whole_at_least(unit["strength_pct"], 1) or float(unit["strength_pct"]) > 100.0:
				return false
			originals["%s_%d" % [side, index]] = unit
	if not battle.has("tactics_version") and battle["formations"].size() != originals.size():
		return false
	if battle.has("model_version"):
		if not _whole_at_least(battle["model_version"],2) or int(battle["model_version"]) != 2: return false
		if not _fields(battle,{"paused":TYPE_BOOL,"speed":TYPE_FLOAT,"elapsed_ms":TYPE_FLOAT,"capture_ms":TYPE_FLOAT,"events":TYPE_ARRAY,"event_seq":TYPE_FLOAT,"layout_signature":TYPE_STRING}): return false
		if not _whole_at_least(battle["speed"],1) or not int(battle["speed"]) in [1,2]: return false
		for key in ["elapsed_ms","capture_ms","event_seq"]:
			if not _whole_at_least(battle[key],0): return false
		if not JSON.parse_string(battle["layout_signature"]) is Dictionary: return false
		if battle["events"].size()>128: return false
		for event in battle["events"]:
			if not _fields(event,{"id":TYPE_FLOAT,"kind":TYPE_STRING,"from":TYPE_ARRAY,"to":TYPE_ARRAY}): return false
			if not event["kind"] in ["volley","clash","fire_volley","ram_hit"] or not _battle_point(event["from"]) or not _battle_point(event["to"]): return false
			if not _fields(event,{"source":TYPE_STRING,"target":TYPE_STRING},true): return false
			for key in ["time_ms","arc_cm"]:
				if event.has(key) and not _whole_at_least(event[key],0):return false
			if not _whole_at_least(event["id"],1) or event["id"]>battle["event_seq"]:return false
	if battle.has("siege_engine"):
		if not _fields(battle,{"siege_engine":TYPE_DICTIONARY,"fire_prepared":TYPE_BOOL,"gate_max_integrity":TYPE_FLOAT}):return false
		if not _whole_at_least(battle["gate_max_integrity"],1) or battle["gate_integrity"]>battle["gate_max_integrity"]:return false
		var engine: Dictionary=battle["siege_engine"]
		if not _fields(engine,{"id":TYPE_STRING,"position":TYPE_ARRAY,"hp":TYPE_FLOAT,"max_hp":TYPE_FLOAT,"heat":TYPE_FLOAT,"burning":TYPE_BOOL,"cooldown_ms":TYPE_FLOAT,"attack_seq":TYPE_FLOAT,"moving":TYPE_BOOL,"crewed":TYPE_BOOL}):return false
		if engine["id"]!="siege_ram" or not _battle_point(engine["position"]):return false
		for key in ["hp","max_hp","heat","cooldown_ms","attack_seq"]:
			if not _whole_at_least(engine[key],0):return false
		if engine["max_hp"]<=0 or engine["hp"]>engine["max_hp"]:return false
	elif battle.has("fire_prepared") or battle.has("gate_max_integrity"):
		return false
	var formations := {}
	var shares := {}
	if battle.has("tactics_version"):
		if not _whole_at_least(battle["tactics_version"],1) or int(battle["tactics_version"])!=1 or not battle.has("model_version"):return false
		if battle["formations"].size()>originals.size()*3:return false
	if battle.has("specialists_version") and (not _whole_at_least(battle["specialists_version"],1) or int(battle["specialists_version"])!=1):return false
	for formation in battle["formations"]:
		if not formation is Dictionary:return false
		if battle.has("specialists_version") or formation.has("specialty") or formation.has("ability_remaining_ms") or formation.has("ability_cooldown_ms"):
			if not battle.has("specialists_version") or not _fields(formation,{"specialty":TYPE_STRING,"ability_remaining_ms":TYPE_FLOAT,"ability_cooldown_ms":TYPE_FLOAT}):return false
			if not formation["specialty"] in ["","commander","veteran","spear_guard"]:return false
			for key in ["ability_remaining_ms","ability_cooldown_ms"]:
				if not _whole_at_least(formation[key],0) or formation[key]>120000:return false
			if formation["ability_remaining_ms"]>formation["ability_cooldown_ms"]:return false
			if formation["specialty"]=="" and (formation["ability_remaining_ms"]>0 or formation["ability_cooldown_ms"]>0):return false
		if not _fields(formation, {"id": TYPE_STRING, "side": TYPE_STRING, "template": TYPE_STRING,
			"unit": TYPE_DICTIONARY, "initial_strength": TYPE_FLOAT, "node": TYPE_STRING, "target": TYPE_STRING}):
			return false
		if formation.has("source_id") and not formation["source_id"] is String:return false
		var source_id: String=formation.get("source_id",formation["id"])
		if not originals.has(source_id) or formations.has(formation["id"]) or not formation["side"] in ["attacker", "defender"]:
			return false
		if not String(formation["id"]).begins_with(String(formation["side"]) + "_"):
			return false
		formations[formation["id"]] = true
		var original: Dictionary = originals[source_id]
		var unit: Dictionary = formation["unit"]
		if not _units([unit]) or formation["template"] != unit["template"] or unit["template"] != original["template"]:
			return false
		if battle.has("tactics_version"):
			if not _battle_formation(formation) or not _tactical_formation(formation,original):return false
			if not shares.has(source_id):shares[source_id]={"strength":0,"parts":[],"hp":0}
			shares[source_id]["strength"]+=int(formation["initial_strength"])
			shares[source_id]["hp"]+=int(formation["hp"])
			if shares[source_id]["parts"].has(int(formation["platoon"])):return false
			shares[source_id]["parts"].append(int(formation["platoon"]))
		elif formation.has("source_id") or formation.has("formation") or formation.has("platoon") or formation.has("reform_ms") or formation.has("facing_goal") or formation.has("facing_locked") or formation.has("source_strength") or formation.has("ai_reform_ms"):return false
		if not battle.has("tactics_version") and float(formation["initial_strength"]) != float(original["strength_pct"]):
			return false
		if not _whole_at_least(unit["strength_pct"], 0) or float(unit["strength_pct"]) > float(formation["initial_strength"]):
			return false
		if not nodes.has(formation["node"]) or not nodes.has(formation["target"]):
			return false
		if battle.has("model_version") and not _battle_formation(formation): return false
	if battle.has("tactics_version"):
		if shares.size()!=originals.size():return false
		for id in shares:
			var share: Dictionary=shares[id]
			share["parts"].sort()
			if share["parts"]!=[0] and share["parts"]!=[1,2,3]:return false
			if int(share["strength"])!=int(originals[id]["strength_pct"]) or int(share["hp"])>int(share["strength"])*1000:return false
	return true


static func _tactical_formation(f: Dictionary, original: Dictionary) -> bool:
	if not _fields(f,{"source_id":TYPE_STRING,"source_strength":TYPE_FLOAT,"platoon":TYPE_FLOAT,"formation":TYPE_STRING,"reform_ms":TYPE_FLOAT,"ai_reform_ms":TYPE_FLOAT,"facing_goal":TYPE_ARRAY,"facing_locked":TYPE_BOOL}):return false
	if not _whole_at_least(f["platoon"],0) or int(f["platoon"])>3:return false
	if not _whole_at_least(f["source_strength"],1) or f["source_strength"]!=original["strength_pct"]:return false
	if not _whole_at_least(f["initial_strength"],1):return false
	if not f["formation"] in ["line","column","phalanx"]:return false
	for clock in ["reform_ms","ai_reform_ms"]:
		if not _whole_at_least(f[clock],0) or f[clock]>120000:return false
	if not _battle_point(f["facing_goal"]) or not _battle_point(f.get("facing")):return false
	for key in ["facing","facing_goal"]:
		var length := CityBattleNavigation.point(f[key]).length()
		if length<998 or length>1002:return false
	var expected := String(f["source_id"])+("_p"+str(int(f["platoon"])) if int(f["platoon"])>1 else "")
	if f["id"]!=expected:return false
	return true


static func _valid_city_battle_mods(mods: Variant) -> bool:
	if not mods is Dictionary:
		return false
	for key in mods:
		if key in ["class_stats", "matchup_pct", "terrain_pct"]:
			if not mods[key] is Dictionary:
				return false
			for row in mods[key].values():
				if not row is Dictionary:
					return false
				for number in row.values():
					if not _number(number):
						return false
		elif key == "fatigue_immune":
			if not mods[key] is bool:
				return false
		elif not _number(mods[key]):
			return false
	return true


static func _valid_city(city: Variant) -> bool:
	if not _fields(city, {"day": TYPE_FLOAT, "grain_days": TYPE_FLOAT,
		"policies": TYPE_DICTIONARY, "projects": TYPE_DICTIONARY}):
		return false
	if not _whole_at_least(city["day"], 1) or not _whole_at_least(city["grain_days"], 0):
		return false
	if not _fields(city["policies"], {"patrols": TYPE_STRING, "taverns": TYPE_STRING}):
		return false
	if not ["normal", "heavy"].has(city["policies"]["patrols"]) or not ["open", "closed"].has(city["policies"]["taverns"]):
		return false
	if city["policies"].has("workforce") and not ["normal", "paid", "requisition"].has(city["policies"]["workforce"]):
		return false
	if city.has("pending_orders") and not _valid_city_orders(city["pending_orders"]):
		return false
	if city.has("last_day_report") and not _valid_city_report(city["last_day_report"], int(city["day"])):
		return false
	for project in city["projects"].values():
		if not _fields(project, {"remaining": TYPE_FLOAT, "completed": TYPE_BOOL}):
			return false
		if not _whole_at_least(project["remaining"], 0) or (project["completed"] and project["remaining"] != 0):
			return false
		for stamp in ["funded_day", "completed_day"]:
			if project.has(stamp) and (not _whole_at_least(project[stamp], 0) or float(project[stamp]) > float(city["day"])):
				return false
		if int(project.get("completed_day", 0)) > 0 and not project["completed"]:
			return false
		if int(project.get("completed_day", 0)) > 0 and int(project.get("funded_day", 0)) > int(project["completed_day"]):
			return false
	return true


static func _valid_city_orders(orders: Variant) -> bool:
	if not orders is Array:
		return false
	var seen := {}
	for order in orders:
		if not _fields(order, {"id": TYPE_STRING, "count": TYPE_FLOAT, "cost": TYPE_FLOAT}):
			return false
		if order["id"] == "" or seen.has(order["id"]) or not _whole_at_least(order["count"], 1) or not _whole_at_least(order["cost"], 0):
			return false
		seen[order["id"]] = true
	return true


static func _valid_city_report(report: Variant, current_day: int) -> bool:
	if not report is Dictionary:
		return false
	if report.is_empty():
		return true
	if not _fields(report, {"day_before": TYPE_FLOAT, "day_after": TYPE_FLOAT, "treasury_spent": TYPE_FLOAT,
		"order_cost": TYPE_FLOAT, "before": TYPE_DICTIONARY, "after": TYPE_DICTIONARY, "deltas": TYPE_DICTIONARY,
		"flows": TYPE_DICTIONARY, "events": TYPE_ARRAY, "orders_issued": TYPE_ARRAY}):
		return false
	if not _whole_at_least(report["day_before"], 1) or report["day_after"] != report["day_before"] + 1 or report["day_after"] > current_day:
		return false
	if not _whole_at_least(report["treasury_spent"], 0) or not _whole_at_least(report["order_cost"], 0) or not _valid_city_orders(report["orders_issued"]):
		return false
	var order_cost := 0
	for order in report["orders_issued"]:
		order_cost += int(order["cost"])
	if order_cost != int(report["order_cost"]):
		return false
	for section in ["before", "after", "deltas"]:
		var snapshot: Dictionary = report[section]
		for key in ["day", "treasury", "daily_cost", "grain_days", "unrest", "grievance", "legitimacy"]:
			if not _number(snapshot.get(key)):
				return false
		for key in ["day", "treasury", "daily_cost", "grain_days"]:
			if float(snapshot[key]) != floorf(float(snapshot[key])):
				return false
		if section != "deltas":
			if not _whole_at_least(snapshot["day"], 1) or not _whole_at_least(snapshot["grain_days"], 0) or not _whole_at_least(snapshot["daily_cost"], 0):
				return false
	if report["before"]["day"] != report["day_before"] or report["after"]["day"] != report["day_after"]:
		return false
	if report["before"]["treasury"] - report["after"]["treasury"] != report["treasury_spent"]:
		return false
	for stock in ["grievance", "legitimacy"]:
		if not report["flows"].get(stock) is Array:
			return false
		for factor in report["flows"][stock]:
			if not _fields(factor, {"label": TYPE_STRING, "value": TYPE_FLOAT}):
				return false
	for event in report["events"]:
		if not _fields(event, {"kind": TYPE_STRING, "params": TYPE_DICTIONARY}):
			return false
		match String(event["kind"]):
			"project_completed", "program_paused":
				if not _fields(event["params"], {"project": TYPE_STRING}):
					return false
			"troops_trained", "troops_equipped":
				if not _whole_at_least(event["params"].get("count"), 0):
					return false
			"relief_expired":
				pass
			_:
				return false
	return true


static func _whole_at_least(value: Variant, minimum: int) -> bool:
	return _number(value) and float(value) >= minimum and float(value) == floorf(float(value))


static func _fields(record: Variant, types: Dictionary, optional: bool = false) -> bool:
	if not record is Dictionary:
		return false
	for key in types:
		if optional and not record.has(key):
			continue
		var value = record.get(key)
		if types[key] == TYPE_FLOAT:
			if not _number(value):
				return false
		elif typeof(value) != types[key]:
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _nullable_fields(record: Dictionary, types: Dictionary) -> bool:
	for key in types:
		if not record.has(key):
			return false
		if record[key] != null and typeof(record[key]) != types[key]:
			return false
	return true


static func _units(units: Array) -> bool:
	for unit in units:
		if not _fields(unit, {"template": TYPE_STRING, "experience": TYPE_FLOAT,
			"strength_pct": TYPE_FLOAT}):
			return false
		if not _fields(unit, {"weapon": TYPE_FLOAT, "armor": TYPE_FLOAT}, true):
			return false
	return true


static func _battle_point(value: Variant) -> bool:
	return value is Array and value.size()==2 and _whole_at_least(value[0],-100000) and _whole_at_least(value[1],-100000) and absf(float(value[0]))<=100000 and absf(float(value[1]))<=100000


static func _battle_formation(f: Dictionary) -> bool:
	if f.has("incendiary") and not f["incendiary"] is bool:return false
	if not _fields(f,{"position":TYPE_ARRAY,"goal":TYPE_ARRAY,"destination":TYPE_ARRAY,"path":TYPE_ARRAY,"facing":TYPE_ARRAY,"role":TYPE_STRING,"order":TYPE_STRING,"target_id":TYPE_STRING,"fire_at_will":TYPE_BOOL,"hp":TYPE_FLOAT,"soldiers":TYPE_FLOAT,"revealed":TYPE_BOOL,"cooldown_ms":TYPE_FLOAT,"charge_cooldown_ms":TYPE_FLOAT,"runup_cm":TYPE_FLOAT,"morale":TYPE_FLOAT,"routed":TYPE_BOOL,"engaged":TYPE_BOOL,"moving":TYPE_BOOL,"power":TYPE_FLOAT,"attack_seq":TYPE_FLOAT}): return false
	for key in ["position","goal","destination","facing"]:
		if not _battle_point(f[key]): return false
	if f["path"].size()>20000: return false
	for p in f["path"]:
		if not _battle_point(p): return false
	if not f["role"] in ["soldier","archer","cavalry"] or not f["order"] in ["hold","move","attack_move","attack","charge","retreat"]: return false
	for key in ["soldiers","hp","cooldown_ms","charge_cooldown_ms","runup_cm","morale","power","attack_seq"]:
		if not _whole_at_least(f[key],0): return false
	return int(f["hp"])<=int(f["initial_strength"])*1000 and int(f["unit"]["strength_pct"])==ceili(float(f["hp"])/1000.0) and int(f["morale"])<=100


static func _valid_patronage(record: Variant, state: Dictionary) -> bool:
	if not _fields(record,{"chosen":TYPE_STRING,"pledged_turn":TYPE_FLOAT,
		"baseline_owned":TYPE_FLOAT,"progress":TYPE_FLOAT,"last_checked_turn":TYPE_FLOAT,
		"completed":TYPE_DICTIONARY}):return false
	for key in ["pledged_turn","baseline_owned","progress","last_checked_turn"]:
		if not _whole_at_least(record[key],0):return false
	if record.pledged_turn > state.turn or record.last_checked_turn > state.turn:return false
	if record.last_checked_turn < record.pledged_turn:return false
	if record.baseline_owned > state.settlements.size() or record.progress > state.settlements.size() + state.turn:return false
	var chosen: String = record.chosen
	if chosen != "" and (not chosen.is_valid_identifier() or chosen.length() > 64):return false
	if chosen == "" and (record.pledged_turn != 0 or record.baseline_owned != 0 or record.progress != 0 or record.last_checked_turn != 0):return false
	if chosen != "" and record.baseline_owned < 1:return false
	# Bounded extensible identifiers keep future narrative content additive.
	if record.completed.size() > 32:return false
	for id in record.completed:
		if not id is String or not id.is_valid_identifier() or id.length() > 64:return false
		if not _whole_at_least(record.completed[id],0) or record.completed[id] > state.turn:return false
	return true


static func _valid_advisor_tutorial(ledger: Variant, state: Dictionary) -> bool:
	if not _fields(ledger,{"baseline_turn":TYPE_FLOAT,"last_checked_turn":TYPE_FLOAT,
		"strain_active":TYPE_BOOL,"milestones":TYPE_DICTIONARY}):return false
	for key in ["baseline_turn","last_checked_turn"]:
		if not _whole_at_least(ledger[key],0) or ledger[key] > state.turn:return false
	if ledger.last_checked_turn < ledger.baseline_turn or ledger.milestones.size() > 32:return false
	for id in ledger.milestones:
		if not id is String or not id.is_valid_identifier() or id.length() > 64:return false
		var item = ledger.milestones[id]
		if not _fields(item,{"status":TYPE_STRING,"turn":TYPE_FLOAT,"params":TYPE_DICTIONARY,"postponed_until":TYPE_FLOAT}):return false
		if item.status not in ["pending","acknowledged","dismissed"]:return false
		if not _whole_at_least(item.turn,0) or item.turn < ledger.baseline_turn or item.turn > state.turn:return false
		if not _whole_at_least(item.postponed_until,0) or item.postponed_until < item.turn:return false
		if not _fields(item.params,{"region":TYPE_STRING,"subject":TYPE_STRING,"value":TYPE_FLOAT}):return false
		if item.params.size() != 3:return false
		if item.params.region != "" and not state.settlements.has(item.params.region):return false
		if item.params.subject.length() > 128:return false
		if float(item.params.value) != floorf(float(item.params.value)):return false
	return true


static func _valid_divine_dilemmas(ledger: Variant, state: Dictionary) -> bool:
	if not _fields(ledger,{"cooldown_until":TYPE_FLOAT,"resolved":TYPE_DICTIONARY}):return false
	if not _whole_at_least(ledger.cooldown_until,0) or ledger.resolved.size() > 32:return false
	if ledger.resolved.is_empty() and ledger.cooldown_until != 0:return false
	for id in ledger.resolved:
		if not id is String or not id.is_valid_identifier() or id.length() > 64:return false
		var receipt = ledger.resolved[id]
		if not _fields(receipt,{"turn":TYPE_FLOAT,"region":TYPE_STRING,"choice":TYPE_STRING}):return false
		if not _whole_at_least(receipt.turn,0) or receipt.turn > state.turn or receipt.turn > ledger.cooldown_until:return false
		if not state.settlements.has(receipt.region):return false
		if not receipt.choice.is_valid_identifier() or receipt.choice.length() > 64:return false
	return true
