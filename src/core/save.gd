class_name SaveGame
## Save/load is nothing more than JSON round-tripping the GameState dict —
## by design. Data tables are content, not state, so only the state travels.

const SAVE_VERSION := 2  # v2: Phase 5 added agents and attitude ledgers


static func to_json(state: Dictionary) -> String:
	return JSON.stringify({"version": SAVE_VERSION, "state": state}, "\t")


static func from_json(text: String) -> Dictionary:
	## Returns the state dict, or {} on failure. JSON numbers arrive as floats;
	## the engine int()-coerces on read, so no fixup pass is needed. The one
	## precision-critical field, rng_state, travels as a string (see CampaignRng).
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {}
	if int(parsed.get("version", 0)) != SAVE_VERSION:
		return {}
	var state = parsed.get("state", {})
	return state if state is Dictionary else {}


static func write_file(state: Dictionary, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_json(state))
	file.close()
	return true


static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return from_json(FileAccess.get_file_as_string(path))
