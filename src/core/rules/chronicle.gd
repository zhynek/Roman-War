class_name ChronicleRules
## The chronicle (Phase 6): everything notable that happens lands in
## state.chronicle as a structured entry (schemas/chronicle_entry.schema.json
## — the narrator contract: stable ids, scalar details, no prose). Entries
## are RECORDED at the same choke points that emit report events — combat,
## capture, revolt, knowledge, edicts — so player and AI actions write the
## same history; collect() at the end of each turn adds only what must be
## DERIVED by comparing before and after: wars opening and closing (the
## running ledger in state.wars), reigns changing hands (the per-faction
## reign ledger — kill-path deaths emit no notices, so leaders are tracked
## by id), factions destroyed. Alliances record at their signing
## (DiplomacyRules.apply_offer — the only place they form).
##
## Characters accrue deeds ({battles_won, battles_lost, sieges_won,
## cities_taken, cities_lost, techniques_completed, edicts_enacted,
## offices_held}) — the
## vocabulary epithets are earned from (C2). Rebels have no scribes: wars
## with rebels are banditry and stay out of the ledger.
##
## Everything here is deterministic and rng-free; caps and compaction come
## from balance.json → chronicle.


static func record(data: GameData, state: Dictionary, kind: String, subjects: Dictionary, magnitude: int, details: Dictionary = {}) -> void:
	## Record with the LIVE date — choke points call this mid-turn, before
	## the date advances, so the entry belongs to the season being resolved.
	_push(data, state, {
		"id": _next_id(state),
		"turn": int(state["turn"]),
		"year": int(state["year"]),
		"season": String(state["season"]),
		"kind": kind,
		"subjects": subjects,
		"magnitude": magnitude,
		"details": details,
	})


static func snapshot(state: Dictionary) -> Dictionary:
	## Taken at the TOP of end_turn: the world before the season resolves.
	## collect() stamps its derived entries with this date (the turn counter
	## has advanced by then) and diffs against the alive set. Alliances need
	## no snapshot — every signing passes through DiplomacyRules.apply_offer,
	## which records them itself.
	var alive := {}
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		alive[faction_id] = bool(state["factions"][faction_id]["alive"])
	return {
		"turn": int(state["turn"]),
		"year": int(state["year"]),
		"season": String(state["season"]),
		"alive": alive,
	}


static func collect(data: GameData, state: Dictionary, report: Dictionary, pre: Dictionary) -> void:
	## END of end_turn, fixed order: wars open → wars close (summaries from
	## the ledger, no scan) → factions destroyed → epithets earned → reigns.
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()

	# 1. Wars opening: an at-war non-rebel pair with no open ledger entry —
	# or one the battle hooks opened mid-turn (a war's first battle lands
	# before the scribes sit down) that still wants its declaration entry.
	for i in range(faction_ids.size()):
		for j in range(i + 1, faction_ids.size()):
			var a: String = faction_ids[i]
			var b: String = faction_ids[j]
			if a == "rebels" or b == "rebels":
				continue
			if not state["factions"][a]["alive"] or not state["factions"][b]["alive"]:
				continue
			if String(state["factions"][a]["diplomacy"].get(b, "neutral")) != "war":
				continue
			var war := _open_war(state, a, b)
			if war.is_empty():
				state["wars"].append({
					"a": a, "b": b, "began_turn": int(pre["turn"]),
					"battles": 0, "cities": {a: 0, b: 0}, "ended_turn": null, "logged": true,
				})
			elif bool(war.get("logged", true)):
				continue
			else:
				war["logged"] = true
			_push(data, state, _dated(state, pre, "war_declared",
				{"faction": a, "other_faction": b}, 6, {}))

	# 2. Wars closing: an open entry whose pair is no longer at war (peace),
	# or one of whose parties is gone (the summary still closes the book).
	for war in state["wars"]:
		if war["ended_turn"] != null:
			continue
		var a: String = war["a"]
		var b: String = war["b"]
		var a_alive: bool = state["factions"][a]["alive"]
		var b_alive: bool = state["factions"][b]["alive"]
		var still_at_war: bool = a_alive and b_alive \
			and String(state["factions"][a]["diplomacy"].get(b, "neutral")) == "war"
		if still_at_war:
			continue
		war["ended_turn"] = int(pre["turn"])
		if a_alive and b_alive:
			_push(data, state, _dated(state, pre, "peace_made",
				{"faction": a, "other_faction": b}, 5, {}))
		_push(data, state, _dated(state, pre, "war_summary",
			{"faction": a, "other_faction": b}, 7, {
				"turns": int(pre["turn"]) - int(war["began_turn"]),
				"battles": int(war["battles"]),
				"cities_taken_a": int(war["cities"][a]),
				"cities_taken_b": int(war["cities"][b]),
			}))

	# 3. Factions destroyed: alive at the snapshot, gone now.
	for faction_id in faction_ids:
		if bool(pre["alive"].get(faction_id, false)) and not state["factions"][faction_id]["alive"]:
			_push(data, state, _dated(state, pre, "faction_destroyed",
				{"faction": faction_id}, 9, {}))

	# 4. Epithets: the deeds vocabulary earns names, ONE per man, EVER — the
	# Hellenistic convention: the first name earned sticks for life. Lower
	# precedence checks first; report notices carry it to the player's log.
	if not data.epithets.is_empty():
		var epithet_order: Array = data.epithets.keys()
		epithet_order.sort_custom(func(x, y):
			var px := int(data.epithets[x]["precedence"])
			var py := int(data.epithets[y]["precedence"])
			return px < py if px != py else String(x) < String(y))
		var char_ids: Array = state["characters"].keys()
		char_ids.sort()
		for char_id in char_ids:
			var character: Dictionary = state["characters"][char_id]
			if not character["alive"] or character.get("epithet", "") != "":
				continue
			var deeds = character.get("deeds")
			if deeds == null:
				continue
			for epithet_id in epithet_order:
				if not _epithet_earned(data.epithets[epithet_id], deeds as Dictionary):
					continue
				character["epithet"] = epithet_id
				_push(data, state, _dated(state, pre, "epithet_earned", {
					"character": char_id, "faction": character["faction"],
					"epithet": epithet_id,
				}, 5, {}))
				if report.has("characters"):
					report["characters"].append({"kind": "epithet_earned",
						"character": char_id, "faction": character["faction"],
						"name": String(data.epithets[epithet_id]["name"])})
				break

	# 5. Reigns: one pass over characters finds every living leader; a faction
	# whose reign ledger names someone else has seen a succession (however the
	# old leader went — battle, blade, or age; kill paths emit no notices).
	var leaders := _living_leaders(state)
	for faction_id in faction_ids:
		if faction_id == "rebels" or not state["factions"][faction_id]["alive"]:
			continue
		var faction: Dictionary = state["factions"][faction_id]
		if not faction.has("reign"):
			faction["reign"] = {"leader": String(leaders.get(faction_id, "")), "since_turn": int(pre["turn"])}
			continue
		var reign: Dictionary = faction["reign"]
		var old_leader := String(reign.get("leader", ""))
		var new_leader := String(leaders.get(faction_id, ""))
		if new_leader == old_leader:
			continue
		if old_leader != "" and state["characters"].has(old_leader):
			var dead: Dictionary = state["characters"][old_leader]
			if not dead["alive"]:
				_push(data, state, _dated(state, pre, "leader_died",
					{"faction": faction_id, "character": old_leader}, 6,
					{"age": int(dead["age"])}))
			var deeds: Dictionary = dead.get("deeds", {})
			_push(data, state, _dated(state, pre, "reign_summary",
				{"faction": faction_id, "character": old_leader}, 6, {
					"turns": int(pre["turn"]) - int(reign.get("since_turn", 0)),
					"battles_won": int(deeds.get("battles_won", 0)),
					"cities_taken": int(deeds.get("cities_taken", 0)),
					"techniques_completed": int(deeds.get("techniques_completed", 0)),
					"edicts_enacted": int(deeds.get("edicts_enacted", 0)),
				}))
		if new_leader != "":
			_push(data, state, _dated(state, pre, "succession",
				{"faction": faction_id, "character": new_leader}, 5, {}))
		reign["leader"] = new_leader
		reign["since_turn"] = int(pre["turn"])

	_compact(data, state)


static func on_battle(state: Dictionary, attacker_owner: String, defender_owner: String) -> void:
	## Ledger increment from the combat choke point — one per field battle or
	## assault between the pair's war (opened here if the first battle lands
	## before collect's scribes; they back-fill the declaration entry).
	var war := _open_or_start_war(state, attacker_owner, defender_owner)
	if not war.is_empty():
		war["battles"] = int(war["battles"]) + 1


static func on_city_taken(state: Dictionary, new_owner: String, previous_owner: String) -> void:
	var war := _open_or_start_war(state, new_owner, previous_owner)
	if not war.is_empty() and war["cities"].has(new_owner):
		war["cities"][new_owner] = int(war["cities"][new_owner]) + 1


static func add_deed(state: Dictionary, char_id, key: String, amount: int = 1) -> void:
	## Deeds accrue on characters for life (and beyond — the record stands).
	if char_id == null or not state["characters"].has(char_id):
		return
	var character: Dictionary = state["characters"][char_id]
	if not character.has("deeds"):
		character["deeds"] = {}
	character["deeds"][key] = int(character["deeds"].get(key, 0)) + amount


static func leader_of(state: Dictionary, faction_id: String) -> String:
	## The faction's living leader by sorted-id scan ("" when the seat is
	## empty). For per-faction one-off credit (technique and edict deeds).
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["alive"] and character["faction"] == faction_id \
				and String(character["role"]) == "leader":
			return char_id
	return ""


static func resolved(data: GameData, state: Dictionary) -> Array:
	## The narrator feed and the annals panel's input: every entry with a
	## names dict resolving its subject ids to display names. Dead characters
	## persist in state, so the save alone suffices. Read-only.
	var out: Array = []
	for entry in state.get("chronicle", []):
		var resolved_entry: Dictionary = entry.duplicate(true)
		resolved_entry["names"] = _names_for(data, state, entry)
		out.append(resolved_entry)
	return out


static func render_entry(data: GameData, state: Dictionary, entry: Dictionary) -> String:
	## In-game prose from data/annals.json templates: variant chosen by entry
	## id (stable — no rng), placeholders filled from resolved names, the
	## date, and scalar details. The future narrator replaces this prose,
	## never the entries.
	var variants: Array = data.annals.get(String(entry["kind"]), [])
	if variants.is_empty():
		return String(entry["kind"]).replace("_", " ")
	var template := String(variants[int(entry["id"]) % variants.size()])
	var values := _names_for(data, state, entry)
	for key in entry["details"]:
		values[key] = str(entry["details"][key])
	values["year"] = year_text(int(entry["year"]))
	values["season"] = String(entry["season"]).capitalize()
	return template.format(values)


static func year_text(year: int) -> String:
	return "%d BC" % -year if year < 0 else "AD %d" % year


static func _names_for(data: GameData, state: Dictionary, entry: Dictionary) -> Dictionary:
	var names := {}
	var subjects: Dictionary = entry["subjects"]
	for key in subjects:
		var subject_id := String(subjects[key])
		match String(key):
			"faction", "other_faction":
				names[key] = String(data.factions.get(subject_id, {}).get("name", subject_id))
			"character":
				names[key] = String(state["characters"].get(subject_id, {}).get("name", subject_id))
			"region":
				names[key] = String(data.regions.get(subject_id, {}).get("settlement_name", subject_id))
			"technique":
				names[key] = String(data.techniques.get(subject_id, {}).get("name", subject_id))
			"edict":
				names[key] = String(data.edicts.get(subject_id, {}).get("name", subject_id))
			"epithet":
				names[key] = String(data.epithets.get(subject_id, {}).get("name", subject_id))
			"office":
				names[key] = String(data.offices.get(subject_id, {}).get("name", subject_id))
			_:
				names[key] = subject_id
	return names


## --- Internals -------------------------------------------------------------

static func _epithet_earned(epithet: Dictionary, deeds: Dictionary) -> bool:
	for key in epithet["requires"]:
		if int(deeds.get(key, 0)) < int(epithet["requires"][key]):
			return false
	for key in epithet["limits"]:
		if int(deeds.get(key, 0)) > int(epithet["limits"][key]):
			return false
	return true


static func _living_leaders(state: Dictionary) -> Dictionary:
	## One sorted pass: {faction_id: leader_char_id} for every living leader.
	var leaders := {}
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["alive"] and String(character["role"]) == "leader" \
				and not leaders.has(character["faction"]):
			leaders[character["faction"]] = char_id
	return leaders


static func _open_war(state: Dictionary, a: String, b: String) -> Dictionary:
	if a == "rebels" or b == "rebels" or a == b:
		return {}
	for war in state.get("wars", []):  # pure find: at most one open per pair
		if war["ended_turn"] == null \
				and ((war["a"] == a and war["b"] == b) or (war["a"] == b and war["b"] == a)):
			return war
	return {}


static func _open_or_start_war(state: Dictionary, a: String, b: String) -> Dictionary:
	## The combat hooks' entry: the pair's open war, started unlogged if the
	## fighting outran the declaration record.
	if a == "rebels" or b == "rebels" or a == b:
		return {}
	var war := _open_war(state, a, b)
	if not war.is_empty():
		return war
	if not state.has("wars"):
		state["wars"] = []
	var pair: Array = [a, b]
	pair.sort()
	var opened := {
		"a": pair[0], "b": pair[1], "began_turn": int(state["turn"]),
		"battles": 0, "cities": {pair[0]: 0, pair[1]: 0}, "ended_turn": null, "logged": false,
	}
	state["wars"].append(opened)
	return opened


static func _dated(state: Dictionary, pre: Dictionary, kind: String, subjects: Dictionary, magnitude: int, details: Dictionary) -> Dictionary:
	return {
		"id": _next_id(state),
		"turn": int(pre["turn"]),
		"year": int(pre["year"]),
		"season": String(pre["season"]),
		"kind": kind,
		"subjects": subjects,
		"magnitude": magnitude,
		"details": details,
	}


static func _next_id(state: Dictionary) -> int:
	var id := int(state["next_id"])
	state["next_id"] = id + 1
	return id


static func _push(data: GameData, state: Dictionary, entry: Dictionary) -> void:
	## Append under the per-turn cap: a crowded season keeps its
	## highest-magnitude records (the first lowest is displaced),
	## deterministically.
	if not state.has("chronicle"):
		state["chronicle"] = []
	var chronicle: Array = state["chronicle"]
	var cap := int(data.balance["chronicle"]["per_turn_cap"])
	var turn := int(entry["turn"])
	var this_turn: Array = []
	for i in range(chronicle.size() - 1, -1, -1):
		if int(chronicle[i]["turn"]) != turn:
			break
		this_turn.append(i)
	if this_turn.size() < cap:
		chronicle.append(entry)
		return
	# Full season: displace the first-lowest entry if this one outweighs it.
	var lowest_index := -1
	var lowest_magnitude := 99
	this_turn.reverse()  # chronological order within the turn
	for i in this_turn:
		if int(chronicle[i]["magnitude"]) < lowest_magnitude:
			lowest_magnitude = int(chronicle[i]["magnitude"])
			lowest_index = i
	if lowest_index >= 0 and int(entry["magnitude"]) > lowest_magnitude:
		chronicle.remove_at(lowest_index)
		chronicle.append(entry)


static func _compact(data: GameData, state: Dictionary) -> void:
	## Bound the annals: past max_entries, the oldest minor records
	## (magnitude at or under the floor) are dropped first, then the oldest
	## of any weight — the chronicle never outgrows the save.
	var rules: Dictionary = data.balance["chronicle"]
	var max_entries := int(rules["max_entries"])
	var chronicle: Array = state["chronicle"]
	if chronicle.size() <= max_entries:
		return
	var floor_magnitude := int(rules["compact_min_magnitude"])
	var kept: Array = []
	var over := chronicle.size() - max_entries
	for entry in chronicle:
		if over > 0 and int(entry["magnitude"]) <= floor_magnitude:
			over -= 1
			continue
		kept.append(entry)
	while kept.size() > max_entries:
		kept.remove_at(0)
	state["chronicle"] = kept
