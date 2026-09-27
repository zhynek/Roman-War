class_name CityCampaignRules
## Roma's local operations share the existing campaign clock after an explicit
## visit/activation. Seasons always run through Game.end_turn / TurnEngine;
## these helpers neither replace the campaign nor manufacture elapsed years.


static func enter(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var reason := _access_reason(data, state, region)
	if reason != "":
		return {"ok": false, "reason": reason}
	if not state.has("city_campaign"):
		state["city_campaign"] = {}
	if not state["city_campaign"].has(region):
		state["city_campaign"][region] = {"active": true, "history": []}
	else:
		state["city_campaign"][region]["active"] = true
	return {"ok": true, "reason": "", "status": status(data, state, region)}


static func active(state: Dictionary) -> bool:
	for record in state.get("city_campaign", {}).values():
		if record.get("active", false):
			return true
	return false


static func status(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var reason := _access_reason(data, state, region)
	var report := _snapshot(data, state, region)
	var hard_reason := _hard_stop(data, state, region)
	var record: Dictionary = state.get("city_campaign", {}).get(region, {})
	report.merge({"available": reason == "", "reason": reason, "region": region,
		"active": bool(record.get("active", false)), "can_advance": hard_reason == "",
		"advance_reason": hard_reason,
		"batch_reason": interruption(data, state, region),
		"start_year": int(data.balance["time"]["start_year"]),
		"end_year": int(data.balance["time"]["end_year"]),
		"turns_per_year": int(data.balance["time"]["turns_per_year"]),
		"max_advance_seasons": int(data.balance["city_campaign"]["max_advance_seasons"]),
		"civic_days_per_season": int(data.balance["city_campaign"]["civic_days_per_season"]),
		"pending_defense": CityBattleRules.pending_defense(data, state, region),
		"history": record.get("history", []), "recent_chronicle": _recent_chronicle(data, state, region),
		"winner": state.get("winner")})
	return report.duplicate(true)


static func advance(game: Game, region: String, seasons: int = 1) -> Dictionary:
	var result := {"ok": false, "reason": "", "seasons_advanced": 0,
		"civic_days_advanced": 0, "stop_reason": "", "reports": []}
	if seasons < 1 or seasons > int(game.data.balance["city_campaign"]["max_advance_seasons"]):
		result["reason"] = "invalid_duration"
		return result
	var reason := _hard_stop(game.data, game.state, region)
	if reason == "" and seasons > 1:
		reason = interruption(game.data, game.state, region)
	if reason != "":
		result["reason"] = reason
		result["stop_reason"] = reason
		return result
	enter(game.data, game.state, region)
	for index in range(seasons):
		# Repeat the facade's preflight before every season; a new threat or
		# decision ends a batch before another civic cost or queue progresses.
		if index > 0:
			reason = interruption(game.data, game.state, region)
			if reason != "":
				result["stop_reason"] = reason
				break
		var report := game.end_turn()
		if not report.get("ok", true):
			result["stop_reason"] = report.get("reason", "advance_blocked")
			break
		result["seasons_advanced"] = int(result["seasons_advanced"]) + 1
		var summary: Dictionary = report.get("city_campaign", {}).get(region, {})
		result["reports"].append(summary.duplicate(true))
		result["civic_days_advanced"] = int(result["civic_days_advanced"]) + int(summary.get("civic_days_advanced", 0))
		reason = interruption(game.data, game.state, region)
		if reason != "":
			result["stop_reason"] = reason
			break
	result["ok"] = int(result["seasons_advanced"]) > 0
	result["reason"] = "" if result["ok"] else result["stop_reason"]
	result["status"] = status(game.data, game.state, region)
	return result


static func advance_civic_work(data: GameData, state: Dictionary) -> Dictionary:
	## Called only after Game.end_turn has accepted every global battle lock.
	## A civic day is a funded local management operation, not a claim that a
	## campaign season lasts three literal days. Unfunded work waits while the
	## normal seasonal economy can restore the treasury.
	var operations := {}
	var regions: Array = state.get("city_campaign", {}).keys()
	regions.sort()
	for region in regions:
		var record: Dictionary = state["city_campaign"][region]
		if not record.get("active", false) or _access_reason(data, state, region) != "":
			continue
		var before := _snapshot(data, state, region)
		if record["history"].is_empty():
			var initial := _history_row(before, before, "initial", {})
			record["history"].append(initial)
		var work := {"before": before, "civic_days_advanced": 0, "unfunded_civic_days": 0,
			"civic_reason": "", "completed_projects": [], "completed_units": []}
		var days := int(data.balance["city_campaign"]["civic_days_per_season"])
		for day in range(days):
			var civic_quote := RomaCityRules.status(data, state, region)
			if not civic_quote.get("can_advance", false):
				work["civic_reason"] = civic_quote.get("advance_reason", civic_quote.get("reason", "advance_blocked"))
				if work["civic_reason"] == "insufficient_funds":
					work["unfunded_civic_days"] = days - day
				break
			var recruit := ""
			if state["settlements"][region]["siege"] == null:
				for job in state["settlements"][region]["recruitment_queue"]:
					if job.has("city_days_left"):
						if int(job["city_days_left"]) == 1:
							recruit = String(job["template"])
						break
			if not RomaCityRules.advance_day(data, state, region):
				work["civic_reason"] = "advance_blocked"
				break
			work["civic_days_advanced"] = int(work["civic_days_advanced"]) + 1
			if recruit != "":
				work["completed_units"].append(recruit)
			for event in state["city_governance"][region]["last_day_report"]["events"]:
				if event["kind"] == "project_completed":
					work["completed_projects"].append(event["params"]["project"])
		operations[region] = work
	return operations


static func record_season(data: GameData, state: Dictionary, report: Dictionary, operations: Dictionary) -> void:
	if operations.is_empty():
		return
	var summaries := {}
	var regions: Array = operations.keys()
	regions.sort()
	for region in regions:
		var work: Dictionary = operations[region]
		work["completed_units"].append_array(report.get("completed_units", {}).get(region, []))
		work["completed_buildings"] = report.get("completed_buildings", {}).get(region, []).duplicate()
		var after := _snapshot(data, state, region)
		var row := _history_row(work["before"], after, "season", work)
		row["stop_reason"] = interruption(data, state, region)
		var history: Array = state["city_campaign"][region]["history"]
		history.append(row)
		var limit := int(data.balance["city_campaign"]["history_limit"])
		while history.size() > limit:
			history.pop_front()
		summaries[region] = row.duplicate(true)
	report["city_campaign"] = summaries


static func interruption(data: GameData, state: Dictionary, region: String) -> String:
	var hard := _hard_stop(data, state, region)
	if hard != "":
		return hard
	if state["settlements"][region]["siege"] != null:
		return "siege_threat"
	var player := String(state["player_faction"])
	for offer in state.get("pending_offers", []):
		if offer.get("to", "") == player and DiplomacyRules.offer_still_stands(data, state, offer):
			return "decision_pending"
	var mission = state["factions"][player].get("mission")
	if mission is Dictionary and data.missions.get(mission.get("template", ""), {}).get("kind", "") == "leader_suicide":
		return "decision_pending"
	var nearby: Array = data.regions.get(region, {}).get("adjacent", []).duplicate()
	nearby.append(region)
	for army in state["armies"].values():
		if nearby.has(army["region"]) and DiplomacyRules.at_war(state, player, String(army["owner"])) \
				and VisibilityRules.army_visible(data, state, player, army):
			return "nearby_threat"
	return ""


static func _hard_stop(data: GameData, state: Dictionary, region: String) -> String:
	var access := _access_reason(data, state, region)
	if access != "":
		return access
	if state.get("winner") != null:
		return "campaign_finished"
	if CityBattleRules.locked(state):
		return "battle_active"
	# Keep this global, matching Game.end_turn's preflight: another ready
	# authored defense must not permit civic spending before refusal.
	for city in state["settlements"]:
		if CityBattleRules.pending_defense(data, state, city):
			return "defense_pending"
	return ""


static func _access_reason(data: GameData, state: Dictionary, region: String) -> String:
	if not data.city_governance.get("regions", []).has(region):
		return "unsupported_city"
	if state.get("settlements", {}).get(region, {}).get("owner", "") != state.get("player_faction", ""):
		return "city_lost" if state.get("city_campaign", {}).has(region) else "unauthorized"
	return ""


static func _snapshot(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var settlement: Dictionary = state.get("settlements", {}).get(region, {})
	var owner := String(settlement.get("owner", ""))
	var player := String(state.get("player_faction", ""))
	return {"turn": int(state.get("turn", 0)), "year": int(state.get("year", 0)),
		"season": String(state.get("season", "summer")), "owner": owner,
		"population": int(settlement.get("population", 0)),
		"treasury": int(state.get("factions", {}).get(player, {}).get("treasury", 0)),
		"garrison_soldiers": CombatRules.soldiers_in(data, settlement.get("garrison", [])) if owner == player else 0,
		"civic_day": int(state.get("city_governance", {}).get(region, {}).get("day", 1))}


static func _history_row(before: Dictionary, after: Dictionary, kind: String, work: Dictionary) -> Dictionary:
	var row := after.duplicate(true)
	row.merge({"kind": kind, "population_delta": int(after["population"]) - int(before["population"]),
		"treasury_delta": int(after["treasury"]) - int(before["treasury"]),
		"garrison_delta": int(after["garrison_soldiers"]) - int(before["garrison_soldiers"]),
		"civic_days_advanced": int(work.get("civic_days_advanced", 0)),
		"unfunded_civic_days": int(work.get("unfunded_civic_days", 0)),
		"civic_reason": String(work.get("civic_reason", "")), "stop_reason": "",
		"completed_projects": work.get("completed_projects", []).duplicate(),
		"completed_units": work.get("completed_units", []).duplicate(),
		"completed_buildings": work.get("completed_buildings", []).duplicate()})
	return row


static func _recent_chronicle(data: GameData, state: Dictionary, region: String) -> Array:
	var recent: Array = []
	var entries: Array = state.get("chronicle", [])
	var limit := int(data.balance["city_campaign"]["chronicle_limit"])
	var player: String = state.get("player_faction", "")
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		var subjects: Dictionary = entry.get("subjects", {})
		if subjects.get("region", "") == region or subjects.get("faction", "") == player or subjects.get("other_faction", "") == player:
			recent.push_front(entry.duplicate(true))
			if recent.size() >= limit:
				break
	return recent
