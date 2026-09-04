class_name SaveGame
## Save/load is nothing more than JSON round-tripping the GameState dict —
## by design. Data tables are content, not state, so only the state travels.
## Version history:
##   1 — foundation through Phase 4
##   2 — Phase 5: agents, tributes, per-faction opinion/war_turns/treachery/overlord
##   3 — Phase 6: pending_offers (AI offers awaiting the player)

const SAVE_VERSION := 3
const OLDEST_LOADABLE_VERSION := 1


static func to_json(state: Dictionary) -> String:
	return JSON.stringify({"version": SAVE_VERSION, "state": state}, "\t")


static func from_json(text: String) -> Dictionary:
	## Returns the state dict, or {} on failure. JSON numbers arrive as floats;
	## the engine int()-coerces on read, so no fixup pass is needed. The one
	## precision-critical field, rng_state, travels as a string (see CampaignRng).
	## Saves from earlier versions are upgraded in place.
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {}
	var version := int(parsed.get("version", 0))
	if version < OLDEST_LOADABLE_VERSION or version > SAVE_VERSION:
		return {}
	var state = parsed.get("state", {})
	if not (state is Dictionary):
		return {}
	return upgrade(state, version)


static func upgrade(state: Dictionary, version: int) -> Dictionary:
	## Older saves gain the fields later phases introduced, with the defaults
	## a new campaign starts from; nothing already present is touched.
	if version < 2:
		if not state.has("agents"):
			state["agents"] = {}
		if not state.has("tributes"):
			state["tributes"] = []
		for faction in state.get("factions", {}).values():
			if not faction.has("opinion"):
				faction["opinion"] = {}
			if not faction.has("war_turns"):
				faction["war_turns"] = {}
			if not faction.has("treachery"):
				faction["treachery"] = 0
			if not faction.has("overlord"):
				faction["overlord"] = null
	if version < 3:
		if not state.has("pending_offers"):
			state["pending_offers"] = []
	return state


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
