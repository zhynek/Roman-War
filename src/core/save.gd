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
	for recipients in state.get("map_access", {}).values():
		if not recipients is Array:
			return false
	return true


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
