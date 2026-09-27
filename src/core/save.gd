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
		"map_access": TYPE_DICTIONARY, "recon": TYPE_DICTIONARY,
		"city_governance": TYPE_DICTIONARY,
		"journal": TYPE_DICTIONARY, "ai": TYPE_DICTIONARY, "guided": TYPE_DICTIONARY,
		"event_cooldowns": TYPE_DICTIONARY, "mercenary_pools": TYPE_DICTIONARY,
	}, true):
		return false
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
	for army in state["armies"].values():
		if not _fields(army, {"owner": TYPE_STRING, "region": TYPE_STRING,
			"movement_left": TYPE_FLOAT, "units": TYPE_ARRAY}) or not _units(army["units"]):
			return false
		if not _nullable_fields(army, {"general": TYPE_STRING}):
			return false
		if not _fields(army, {"march_path": TYPE_ARRAY}, true):
			return false
	for fleet in state["fleets"].values():
		if not _fields(fleet, {"owner": TYPE_STRING, "sea_zone": TYPE_STRING,
			"movement_left": TYPE_FLOAT, "ships": TYPE_ARRAY}) or not _units(fleet["ships"]):
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
	for recipients in state.get("map_access", {}).values():
		if not recipients is Array:
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
