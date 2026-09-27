class_name RomaCityRules
## The city prototype spends explicit civic days, never campaign seasons.
## Walking is presentation. Only these commands spend money or change the
## existing settlement's societal stocks. No method consumes campaign RNG.
## City records retain discrete policies/projects; slow social memory remains
## in SocietyRules' quantized stocks. Prose belongs to the effects glossary.


static func ensure_city(data: GameData, state: Dictionary, region_id: String) -> bool:
	if _access_reason(data, state, region_id) != "":
		return false
	if not state.has("city_governance"):
		state["city_governance"] = {}
	if not state["city_governance"].has(region_id):
		state["city_governance"][region_id] = _new_city(data)
	else:
		ensure_project_keys(data, state["city_governance"][region_id])
	return true


static func ensure_project_keys(data: GameData, city: Dictionary) -> void:
	# Explicit additive migration. Pure readers tolerate absent project records.
	for policy in data.city_governance.get("default_policies", {}):
		if not city["policies"].has(policy):
			city["policies"][policy] = data.city_governance["default_policies"][policy]
	if not city.has("last_day_report"):
		city["last_day_report"] = {}
	if not city.has("pending_orders"):
		city["pending_orders"] = []
	for action in data.city_governance.get("actions", []):
		if action["kind"] != "project":
			continue
		var project_id: String = action["id"]
		if not city["projects"].has(project_id):
			city["projects"][project_id] = _new_project()
		var project: Dictionary = city["projects"][project_id]
		if not project.has("funded_day"):
			# Older completed ledgers did not retain dates. Zero means unknown.
			var remaining := int(project.get("remaining", 0))
			project["funded_day"] = clampi(int(city["day"]) - int(data.balance["city"]["project_days"][project_id]) + remaining, 1, int(city["day"])) if remaining > 0 else 0
		if not project.has("completed_day"):
			project["completed_day"] = 0


static func _new_project() -> Dictionary:
	return {"remaining": 0, "completed": false, "funded_day": 0, "completed_day": 0}


static func _new_city(data: GameData) -> Dictionary:
	var projects := {}
	for action in data.city_governance.get("actions", []):
		if action["kind"] == "project":
			projects[action["id"]] = _new_project()
	return {
		"day": 1,
		"policies": data.city_governance.get("default_policies", {}).duplicate(true),
		"grain_days": 0,
		"projects": projects,
		"last_day_report": {}, "pending_orders": [],
	}


static func _city(data: GameData, state: Dictionary, region_id: String) -> Dictionary:
	# Do not lazily write during status/drawing: pure queries are replay safe.
	var cities: Dictionary = state.get("city_governance", {})
	return cities[region_id] if cities.has(region_id) else _new_city(data)


static func _access_reason(data: GameData, state: Dictionary, region_id: String) -> String:
	var settlement: Dictionary = state.get("settlements", {}).get(region_id, {})
	if settlement.is_empty() or settlement.get("owner", "") != state.get("player_faction", ""):
		return "unauthorized"
	if not data.city_governance.get("regions", []).has(region_id):
		return "unsupported_city"
	return ""


static func _action(data: GameData, action_id: String) -> Dictionary:
	for action in data.city_governance.get("actions", []):
		if action["id"] == action_id:
			return action
	return {}


static func allowed(data: GameData, state: Dictionary, region_id: String, action_id: String) -> Dictionary:
	var refusal := _access_reason(data, state, region_id)
	if refusal != "":
		return {"ok": false, "reason": refusal}
	if CityBattleRules.locked(state):
		return {"ok": false, "reason": "battle_active", "cost": int(data.balance["city"]["action_costs"].get(action_id, 0))}
	var action := _action(data, action_id)
	if action.is_empty():
		return {"ok": false, "reason": "unknown_action"}
	var city := _city(data, state, region_id)
	var cost := int(data.balance["city"]["action_costs"][action_id])
	var settlement: Dictionary = state["settlements"][region_id]
	var prerequisite: String = action.get("requires_project", "")
	if prerequisite != "" and not _completed(city, prerequisite):
		refusal = "project_required"
	if (data.city_governance.get("military_programs", []).has(action_id) or data.city_governance.get("defense_projects", []).has(action_id)) and settlement["siege"] != null:
		refusal = "under_siege"
	match String(action["kind"]):
		"relief":
			if int(city["grain_days"]) > 0:
				refusal = "relief_active"
		"policy":
			if city["policies"].get(action["policy"], data.city_governance["default_policies"].get(action["policy"], "")) == action["value"]:
				refusal = "already_set"
		"tax":
			if settlement["tax_level"] == action["value"]:
				refusal = "already_set"
		"project":
			var project: Dictionary = city["projects"].get(action_id, {})
			if project.get("completed", false):
				refusal = "project_completed"
			elif int(project.get("remaining", 0)) > 0:
				refusal = "project_active"
	if refusal == "" and int(state["factions"][settlement["owner"]]["treasury"]) < cost:
		refusal = "insufficient_funds"
	return {"ok": refusal == "", "reason": refusal, "cost": cost}


static func apply_action(data: GameData, state: Dictionary, region_id: String, action_id: String) -> bool:
	var permission := allowed(data, state, region_id, action_id)
	if not permission["ok"]:
		return false
	ensure_city(data, state, region_id)
	var city: Dictionary = state["city_governance"][region_id]
	var settlement: Dictionary = state["settlements"][region_id]
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var action := _action(data, action_id)
	faction["treasury"] = int(faction["treasury"]) - int(permission["cost"])
	match String(action["kind"]):
		"relief":
			city["grain_days"] = int(data.balance["city"]["grain_duration_days"])
		"policy":
			city["policies"][action["policy"]] = action["value"]
		"tax":
			settlement["tax_level"] = action["value"]
		"project":
			city["projects"][action_id] = {
				"remaining": int(data.balance["city"]["project_days"][action_id]),
				"completed": false,
				"funded_day": int(city["day"]), "completed_day": 0,
			}
	var recorded := false
	for order in city["pending_orders"]:
		if order["id"] == action_id:
			order["count"] = int(order["count"]) + 1
			order["cost"] = int(order["cost"]) + int(permission["cost"])
			recorded = true
			break
	if not recorded:
		city["pending_orders"].append({"id": action_id, "count": 1, "cost": int(permission["cost"])})
	return true


static func building_info(data: GameData, state: Dictionary, region_id: String, site_id: String) -> Dictionary:
	var report := status(data, state, region_id)
	if not report.get("available", false):
		return report
	var profile: Dictionary = {}
	for candidate in data.city_governance.get("building_profiles", []):
		if candidate["site"] == site_id:
			profile = candidate
			break
	if profile.is_empty():
		return {"available": false, "reason": "unknown_site"}
	var project_id: String = profile["project"]
	var rules: Dictionary = data.balance["city"]
	var project: Dictionary = report["projects"].get(project_id, {})
	var completed := bool(project.get("completed", false))
	var remaining := int(project.get("remaining", 0))
	var days := int(rules["project_days"][project_id])
	var rate := _project_rate(data, _city(data, state, region_id), project_id)
	var funded := completed or remaining > 0
	var stage := "improved" if completed else ("construction" if remaining > 0 else "current")
	var evolution: Array = []
	for step in ["current", "construction", "improved"]:
		evolution.append({"stage": step, "key": profile["stages"][step], "active": stage == step})
	var actions: Array = []
	for action in report["actions"]:
		if action["site"] == site_id:
			actions.append(action.duplicate(true))
	var effects := {}
	for stock in ["grievance", "legitimacy"]:
		effects[stock] = [{"label": project_id, "value": float(rules["project_effects"][project_id][stock])}]
	return {
		"available": true, "reason": "", "site": site_id,
		"name_key": "site_" + site_id, "description_key": "about_" + site_id,
		"stage": stage, "stage_key": profile["stages"][stage], "evolution": evolution,
		"project": {"id": project_id, "funded": funded, "in_progress": remaining > 0, "completed": completed,
			"remaining": remaining, "days": days, "elapsed": days - remaining if funded else 0,
			"duration": ceili(float(days) / rate), "estimated_days_remaining": ceili(float(remaining) / rate),
			"cost": int(rules["action_costs"][project_id]),
			"maintenance": int(rules["project_maintenance"][project_id]),
			"funded_day": int(project.get("funded_day", 0)),
			"completion_day": int(project.get("completed_day", 0)) if completed else (int(report["day"]) + ceili(float(remaining) / rate) if funded else 0)},
		"effects": effects, "actions": actions,
	}


static func status(data: GameData, state: Dictionary, region_id: String) -> Dictionary:
	var refusal := _access_reason(data, state, region_id)
	if refusal != "":
		return {"available": false, "reason": refusal}
	var city := _city(data, state, region_id)
	var settlement: Dictionary = state["settlements"][region_id]
	var rules: Dictionary = data.balance["city"]
	var stocks := SocietyRules.stocks_of(data, settlement)
	var policies: Dictionary = city["policies"].duplicate(true)
	policies["workforce"] = policies.get("workforce", data.city_governance["default_policies"]["workforce"])
	policies["tax"] = settlement["tax_level"]
	var cleanliness := float(rules["completed_cleanliness"] if _completed(city, "clean_water") else rules["initial_cleanliness"])
	var street_condition := float(rules["completed_street_condition"] if _completed(city, "repair_streets") else rules["initial_street_condition"])
	var factors: Array = [
		{"label": "city_pressure", "value": float(rules["unrest_base"])},
		{"label": "grievance", "value": float(stocks["grievance"]) * float(rules["unrest_grievance_scale"])},
		{"label": "legitimacy", "value": (100.0 - float(stocks["legitimacy"])) * float(rules["unrest_legitimacy_gap_scale"])},
		{"label": "grime", "value": (100.0 - cleanliness) * float(rules["unrest_grime_scale"])},
		{"label": "disrepair", "value": (100.0 - street_condition) * float(rules["unrest_disrepair_scale"])},
	]
	if policies["patrols"] == "heavy":
		factors.append({"label": "patrols", "value": float(rules["unrest_patrols"])})
	if policies["taverns"] == "closed":
		factors.append({"label": "taverns_closed", "value": float(rules["unrest_taverns_closed"])})
	if int(city["grain_days"]) > 0:
		factors.append({"label": "grain_relief", "value": float(rules["unrest_grain"])})
	var unrest := SocietyRules.quantize(clampf(_sum(factors), 0.0, 100.0))
	var mood := "calm"
	if unrest >= float(rules["rebellious_threshold"]):
		mood = "rebellious"
	elif unrest >= float(rules["restive_threshold"]):
		mood = "restive"
	var treasury := int(state["factions"][settlement["owner"]]["treasury"])
	var daily_cost := int(rules["daily_cost_by_tax"][policies["tax"]])
	daily_cost += int(rules["workforce_daily_cost"][policies["workforce"]])
	if policies["patrols"] == "heavy":
		daily_cost += int(rules["daily_patrol_cost"])
	if policies["taverns"] == "closed":
		daily_cost += int(rules["daily_taverns_closed_cost"])
	for project_id in rules["project_maintenance"]:
		if _completed(city, project_id):
			daily_cost += int(rules["project_maintenance"][project_id])
	var actions: Array = []
	for action in data.city_governance.get("actions", []):
		var quote := allowed(data, state, region_id, action["id"])
		actions.append({
			"id": action["id"], "kind": action["kind"], "site": action["site"],
			"cost": int(quote["cost"]), "days": ceili(float(rules["project_days"].get(action["id"], 0)) / _project_rate(data, city, action["id"])),
			"requires_project": String(action.get("requires_project", "")),
			"available": quote["ok"], "reason": quote["reason"],
		})
	var projects := {}
	for project_id in rules["project_days"]:
		var project: Dictionary = city.get("projects", {}).get(project_id, {})
		# JSON loads numbers as floats; reports have stable integer timers/dates.
		projects[project_id] = {"remaining": int(project.get("remaining", 0)),
			"estimated_days_remaining": ceili(float(project.get("remaining", 0)) / _project_rate(data, city, project_id)),
			"completed": bool(project.get("completed", false)),
			"funded_day": int(project.get("funded_day", 0)),
			"completed_day": int(project.get("completed_day", 0))}
	return {
		"available": true, "reason": "", "region": region_id,
		"day": int(city["day"]), "treasury": treasury, "unrest": unrest, "mood": mood,
		"grievance": stocks["grievance"], "legitimacy": stocks["legitimacy"],
		"policies": policies, "projects": projects,
		"work_rate": int(rules["workforce_rate"][policies["workforce"]]),
		"last_day_report": _normalize_record(city.get("last_day_report", {})),
		"pending_orders": _normalize_record(city.get("pending_orders", [])),
		"grain_days": int(city["grain_days"]), "cleanliness": cleanliness, "street_condition": street_condition,
		"factors": factors, "flows": _flows(data, city, policies, cleanliness, street_condition),
		"actions": actions, "daily_cost": daily_cost, "can_advance": treasury >= daily_cost and not CityBattleRules.locked(state),
		"advance_reason": "battle_active" if CityBattleRules.locked(state) else ("" if treasury >= daily_cost else "insufficient_funds"),
	}


static func advance_day(data: GameData, state: Dictionary, region_id: String) -> bool:
	if CityBattleRules.locked(state):
		return false
	var report := status(data, state, region_id)
	if not report.get("available", false) or not report.get("can_advance", false):
		return false
	ensure_city(data, state, region_id)
	var city: Dictionary = state["city_governance"][region_id]
	var settlement: Dictionary = state["settlements"][region_id]
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var events: Array = []
	faction["treasury"] = int(faction["treasury"]) - int(report["daily_cost"])
	if not settlement.has("society"):
		settlement["society"] = SocietyRules.stocks_of(data, settlement)
	var society: Dictionary = settlement["society"]
	# Apply the promised day's flows before stockpiles expire and work finishes.
	# Completed infrastructure changes the next day's flow, immediately visible.
	for stock in ["grievance", "legitimacy"]:
		var limit := float(data.balance["society"][stock + "_max"])
		society[stock] = SocietyRules.quantize(clampf(float(report[stock]) + _sum(report["flows"][stock]), 0.0, limit))
	city["day"] = int(city["day"]) + 1
	city["grain_days"] = maxi(0, int(city["grain_days"]) - 1)
	if int(report["grain_days"]) == 1:
		events.append({"kind": "relief_expired", "params": {}})
	var project_ids: Array = city["projects"].keys()
	project_ids.sort()
	for project_id in project_ids:
		var project: Dictionary = city["projects"][project_id]
		if int(project["remaining"]) > 0:
			if (data.city_governance.get("military_programs", []).has(project_id) or data.city_governance.get("defense_projects", []).has(project_id)) and settlement["siege"] != null:
				events.append({"kind": "program_paused", "params": {"project": project_id}})
				continue
			project["remaining"] = maxi(0, int(project["remaining"]) - _project_rate(data, city, project_id))
			project["completed"] = int(project["remaining"]) == 0
			if project["completed"]:
				project["completed_day"] = int(city["day"])
				events.append({"kind": "project_completed", "params": {"project": project_id}})
				_complete_program(data, state, region_id, project_id, events)
	# Civic-day recruits advance only here, never on a render frame or season.
	if settlement["siege"] == null:
		for job in settlement["recruitment_queue"]:
			if not job.has("city_days_left"): continue
			job["city_days_left"] = maxi(0,int(job["city_days_left"])-1)
			if int(job["city_days_left"]) == 0:
				var profile := RecruitmentRules.recruit_profile(data,state,region_id,String(job["template"]))
				var unit := {"template":job["template"],"strength_pct":100,"experience":int(profile["experience"]),"weapon":int(profile["weapon"]),"armor":int(profile["armor"])}
				RecruitmentRules.deliver_unit(data,state,region_id,unit)
				settlement["recruitment_queue"].erase(job)
				events.append({"kind":"troops_trained","params":{"count":1}})
			break
	var after := status(data, state, region_id)
	var order_cost := 0
	for order in city["pending_orders"]:
		order_cost += int(order["cost"])
	city["last_day_report"] = {
		"day_before": int(report["day"]), "day_after": int(after["day"]),
		"treasury_spent": int(report["daily_cost"]), "order_cost": order_cost,
		"before": _snapshot(report), "after": _snapshot(after), "deltas": _deltas(report, after),
		"flows": _quantized_flows(report["flows"]), "events": events,
		"orders_issued": city["pending_orders"].duplicate(true),
	}
	city["pending_orders"] = []
	return true


static func _completed(city: Dictionary, project_id: String) -> bool:
	return bool(city.get("projects", {}).get(project_id, {}).get("completed", false))


static func _flows(data: GameData, city: Dictionary, policies: Dictionary, cleanliness: float, street_condition: float) -> Dictionary:
	var rules: Dictionary = data.balance["city"]
	var result := {}
	for stock in ["grievance", "legitimacy"]:
		var factors: Array = [
			{"label": "city_pressure", "value": float(rules[stock + "_base"])},
			{"label": "taxes", "value": float(rules[stock + "_tax"][policies["tax"]])},
		]
		var workforce: String = policies.get("workforce", "normal")
		if float(rules["workforce_" + stock][workforce]) != 0.0:
			factors.append({"label": "workforce_" + workforce, "value": float(rules["workforce_" + stock][workforce])})
		if stock == "grievance":
			factors.append({"label": "grime", "value": (100.0 - cleanliness) * float(rules["grievance_grime_scale"])})
			factors.append({"label": "disrepair", "value": (100.0 - street_condition) * float(rules["grievance_disrepair_scale"])})
		if policies["patrols"] == "heavy":
			factors.append({"label": "patrols", "value": float(rules[stock + "_patrols"])})
		if policies["taverns"] == "closed":
			factors.append({"label": "taverns_closed", "value": float(rules[stock + "_taverns_closed"])})
		if int(city["grain_days"]) > 0:
			factors.append({"label": "grain_relief", "value": float(rules[stock + "_grain"])})
		for project_id in rules["project_effects"]:
			if _completed(city, project_id):
				factors.append({"label": project_id, "value": float(rules["project_effects"][project_id][stock])})
		result[stock] = factors
	return result


static func _sum(factors: Array) -> float:
	var total := 0.0
	for factor in factors:
		total += float(factor["value"])
	return total


static func _project_rate(data: GameData, city: Dictionary, project_id: String) -> int:
	if data.city_governance.get("military_programs", []).has(project_id):
		return int(data.balance["city"]["military_daily_progress"])
	var workforce: String = city.get("policies", {}).get("workforce", data.city_governance["default_policies"]["workforce"])
	return int(data.balance["city"]["workforce_rate"][workforce])


static func action_forecast(data: GameData, state: Dictionary, region_id: String, action_id: String = "") -> Dictionary:
	var before := status(data, state, region_id)
	if not before.get("available", false):
		return {"available": false, "reason": before.get("reason", "unauthorized")}
	var quote := {"ok": true, "reason": "", "cost": 0}
	if action_id != "":
		quote = allowed(data, state, region_id, action_id)
	if not quote["ok"]:
		return {"available": false, "reason": quote["reason"], "action": action_id, "cost": int(quote.get("cost", 0))}
	# Reuse commands on a deep copy: previews cannot drift into an independent
	# rules implementation or write histories, stocks, queues or RNG in reality.
	var predicted: Dictionary = state.duplicate(true)
	if action_id != "":
		apply_action(data, predicted, region_id, action_id)
	var immediate := status(data, predicted, region_id)
	var advanced := advance_day(data, predicted, region_id)
	var next := status(data, predicted, region_id)
	return {
		"available": true, "reason": "", "action": action_id, "cost": int(quote["cost"]),
		"before": _snapshot(before), "immediate": _snapshot(immediate),
		"next_day": _snapshot(next) if advanced else {},
		"immediate_delta": _deltas(before, immediate),
		"next_day_delta": _deltas(immediate, next) if advanced else {},
		"next_day_available": advanced, "next_day_reason": "" if advanced else immediate["advance_reason"],
		"factors_before": _quantized_factors(before["factors"]),
		"factors_immediate": _quantized_factors(immediate["factors"]),
		"flows": _quantized_flows(immediate["flows"]),
		"events": next["last_day_report"].get("events", []).duplicate(true) if advanced else [],
	}


static func _snapshot(report: Dictionary) -> Dictionary:
	var result := {}
	for key in ["day", "treasury", "daily_cost", "grain_days"]:
		result[key] = int(report[key])
	for key in ["unrest", "grievance", "legitimacy"]:
		result[key] = SocietyRules.quantize(float(report[key]))
	return result


static func _deltas(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for key in ["day", "treasury", "daily_cost", "grain_days"]:
		result[key] = int(after[key]) - int(before[key])
	for key in ["unrest", "grievance", "legitimacy"]:
		result[key] = SocietyRules.quantize(float(after[key]) - float(before[key]))
	return result


static func _quantized_factors(factors: Array) -> Array:
	var result: Array = []
	for factor in factors:
		result.append({"label": String(factor["label"]), "value": SocietyRules.quantize(float(factor["value"]))})
	return result


static func _quantized_flows(flows: Dictionary) -> Dictionary:
	var result := {}
	for stock in ["grievance", "legitimacy"]:
		result[stock] = _quantized_factors(flows[stock])
	return result


static func _normalize_record(record: Variant) -> Variant:
	# Canonical numeric types in returned histories match JSON-loaded histories.
	# Integer consumers cast ids/counts/days explicitly; stocks are quantized.
	if record is Dictionary:
		var result := {}
		for key in record:
			result[key] = _normalize_record(record[key])
		return result
	if record is Array:
		var result: Array = []
		for value in record:
			result.append(_normalize_record(value))
		return result
	if record is int or record is float:
		return float(record)
	return record


static func military_bonus(data: GameData, state: Dictionary, region_id: String, effect: String) -> int:
	var city: Dictionary = state.get("city_governance", {}).get(region_id, {})
	var value := 0
	for project_id in data.city_governance.get("military_programs", []):
		if _completed(city, project_id):
			value += int(data.balance["city"]["project_military_effects"][project_id].get(effect, 0))
	return value


static func _complete_program(data: GameData, state: Dictionary, region_id: String, project_id: String, events: Array) -> void:
	if not data.city_governance.get("military_programs", []).has(project_id):
		return
	var eligible := {}
	for template in RecruitmentRules.available_units(data, state, region_id, true, true):
		if template.get("class", "") != "ship":
			eligible[template["id"]] = true
	var effects: Dictionary = data.balance["city"]["project_military_effects"][project_id]
	var trained := 0
	var equipped := 0
	for unit in state["settlements"][region_id]["garrison"]:
		if not eligible.has(unit["template"]):
			continue
		var old_experience := int(unit["experience"])
		unit["experience"] = mini(int(data.balance["recruitment"]["experience_max"]), old_experience + int(effects["experience"]))
		if int(unit["experience"]) > old_experience:
			trained += 1
		if int(effects["weapon"]) > 0 or int(effects["armor"]) > 0:
			var old_weapon := int(unit.get("weapon", 0))
			var old_armor := int(unit.get("armor", 0))
			RecruitmentRules.stamp_upgrades(unit, RecruitmentRules.recruit_profile(data, state, region_id, unit["template"]))
			if int(unit["weapon"]) > old_weapon or int(unit["armor"]) > old_armor:
				equipped += 1
	if int(effects["experience"]) > 0:
		events.append({"kind": "troops_trained", "params": {"count": trained}})
	if int(effects["weapon"]) > 0 or int(effects["armor"]) > 0:
		events.append({"kind": "troops_equipped", "params": {"count": equipped}})


static func troop_status(data: GameData, state: Dictionary, region_id: String) -> Dictionary:
	var refusal := _access_reason(data, state, region_id)
	if refusal != "":
		return {"available": false, "reason": refusal}
	var city := _city(data, state, region_id)
	var rules: Dictionary = data.balance["city"]
	var settlement: Dictionary = state["settlements"][region_id]
	var programs: Array = []
	for project_id in data.city_governance.get("military_programs", []):
		var project: Dictionary = city.get("projects", {}).get(project_id, {})
		var quote := allowed(data, state, region_id, project_id)
		programs.append({"id": project_id, "requires_project": _action(data, project_id).get("requires_project", ""),
			"available": quote["ok"], "reason": quote["reason"], "cost": int(quote["cost"]),
			"days": int(rules["project_days"][project_id]), "remaining": int(project.get("remaining", 0)),
			"completed": bool(project.get("completed", false)),
			"effects": rules["project_military_effects"][project_id].duplicate(true),
			"maintenance": int(rules["project_maintenance"][project_id])})
	var garrison: Array = []
	for unit in settlement["garrison"]:
		garrison.append({"template": unit["template"], "name": data.units.get(unit["template"], {}).get("name", unit["template"]),
			"experience": int(unit["experience"]), "weapon": int(unit.get("weapon", 0)), "armor": int(unit.get("armor", 0)),
			"strength_pct": int(unit["strength_pct"])})
	var recruitable: Array = []
	for template in RecruitmentRules.available_units(data, state, region_id, true):
		if template.get("class", "") == "ship":
			continue
		var cost := RecruitmentRules.recruit_cost(data, state, settlement["owner"], template)
		var reason := ""
		if settlement["siege"] != null:
			reason = "under_siege"
		elif int(state["factions"][settlement["owner"]]["treasury"]) < cost:
			reason = "insufficient_funds"
		elif int(settlement["population"]) - int(template["soldiers"]) < int(data.balance["growth"]["min_population"]):
			reason = "insufficient_population"
		recruitable.append({"id": template["id"], "name": template["name"], "cost": cost,
			"soldiers": int(template["soldiers"]), "upkeep": int(template["upkeep"]),
			"profile": RecruitmentRules.recruit_profile(data, state, region_id, template["id"]),
			"available": reason == "", "reason": reason})
	return {"available": true, "reason": "", "programs": programs, "garrison": garrison,
		"recruitable": recruitable, "queue": _normalize_record(settlement["recruitment_queue"]),
		"profile": RecruitmentRules.recruit_profile(data, state, region_id)}
