class_name SaveGame
## Save/load is nothing more than JSON round-tripping the GameState dict —
## by design. Data tables are content, not state, so only the state travels.

## Version history:
##   1  Phases 0-4 / 7 / 8 foundation state.
##   2  Military layer: faction doctrines / reforms / war_record / war_mood,
##      settlement levy_strain (unit weapon/armor are optional keys, no bump).
const SAVE_VERSION := 2


static func to_json(state: Dictionary) -> String:
	return JSON.stringify({"version": SAVE_VERSION, "state": state}, "\t")


static func from_json(text: String, data: GameData = null) -> Dictionary:
	## Returns the state dict, or {} on failure. JSON numbers arrive as floats;
	## the engine int()-coerces on read, so no fixup pass is needed. The one
	## precision-critical field, rng_state, travels as a string (see CampaignRng).
	## Pass the loaded GameData so an old save can be upgraded with content
	## (e.g. the campaign's starting doctrines).
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {}
	var version := int(parsed.get("version", 0))
	if version < 1 or version > SAVE_VERSION:
		return {}
	var state = parsed.get("state", {})
	if not (state is Dictionary):
		return {}
	upgrade(state, version, data)
	return state


static func upgrade(state: Dictionary, version: int, data: GameData = null) -> void:
	## Fill in fields introduced after `version`, with NewGame's defaults and in
	## NewGame's key order (appended last), so an upgraded save and a live game
	## stringify identically and march in step.
	if version < 2:
		var starting := {}
		if data != null:
			for faction_setup in data.campaign.get("factions", []):
				starting[faction_setup["id"]] = NewGame.starting_doctrines(data, faction_setup)
		var faction_ids: Array = state.get("factions", {}).keys()
		faction_ids.sort()
		for faction_id in faction_ids:
			var faction: Dictionary = state["factions"][faction_id]
			if not faction.has("doctrines"):
				# A pre-doctrine save: the faction practises what it did in 270 BC.
				faction["doctrines"] = starting.get(faction_id, [])
			if not faction.has("reforms"):
				faction["reforms"] = []
			if not faction.has("war_record"):
				faction["war_record"] = NewGame.empty_war_record()
			if not faction.has("war_mood"):
				faction["war_mood"] = null
		var region_ids: Array = state.get("settlements", {}).keys()
		region_ids.sort()
		for region_id in region_ids:
			var settlement: Dictionary = state["settlements"][region_id]
			if not settlement.has("levy_strain"):
				settlement["levy_strain"] = 0.0


static func write_file(state: Dictionary, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_json(state))
	file.close()
	return true


static func read_file(path: String, data: GameData = null) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return from_json(FileAccess.get_file_as_string(path), data)
