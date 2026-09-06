class_name DispatchRules
## What a faction is allowed to know about the day just resolved.
##
## The turn journal is written from the world's point of view — every faction's
## buildings, coffers and battles land in it. This filter is what makes it the
## PLAYER's day: their own affairs in full, their neighbours' only where they
## have eyes, and the announcements heralds carry everywhere.
##
## The rule per beat kind is authored in data/dispatch.json, not here, so a new
## beat declares its own discretion alongside its prose.


static func visible_beats(data: GameData, state: Dictionary,
		journal: Array, faction_id: String) -> Array:
	## Fog of war is computed once for the whole journal, not once per beat.
	var seen := VisibilityRules.visible_regions(data, state, faction_id)
	var result: Array = []
	for beat in journal:
		if _may_know(data, beat, faction_id, seen):
			result.append(beat)
	return result


static func _may_know(data: GameData, beat: Dictionary, faction_id: String, seen: Dictionary) -> bool:
	var template: Dictionary = data.dispatch_beats.get(String(beat["kind"]), {})
	if template.is_empty():
		# The validator makes this impossible at build time; at runtime, keeping
		# quiet beats a line of prose nobody wrote.
		return false
	if beat["kind"] == "army_sighted":
		return String(beat["other"]) == faction_id
	var rule: String = String(template["visibility"])
	# A war or an alliance is proclaimed, not discovered — and the player asked
	# to be told when factions go to war, including ones that are not theirs.
	if rule == "public":
		return true
	var is_ours := String(beat["faction"]) == faction_id or String(beat["other"]) == faction_id
	var in_sight := String(beat["region"]) != "" and seen.has(String(beat["region"]))
	match rule:
		"own":
			return is_ours
		"region":
			return in_sight
		"own_or_region":
			return is_ours or in_sight
	return false


static func chapter_of(data: GameData, beat: Dictionary) -> String:
	return String(data.dispatch_beats.get(String(beat["kind"]), {}).get("chapter", ""))


static func severity_of(data: GameData, beat: Dictionary) -> int:
	return int(data.dispatch_beats.get(String(beat["kind"]), {}).get("severity", 1))


static func sequence_beats(data: GameData, beats: Array) -> Array:
	## What the day actually plays out, in journal order. Low-severity ledger
	## lines and anything the table marks dispatch-only are left to the recap,
	## and a busy turn is capped so the day never outstays its welcome — the
	## Dispatch still carries everything.
	var rules: Dictionary = data.balance["dispatch"]
	var min_severity := int(rules["sequence_min_severity"])
	var playable: Array = []
	for beat in beats:
		var template: Dictionary = data.dispatch_beats.get(String(beat["kind"]), {})
		if template.is_empty() or not bool(template["in_sequence"]):
			continue
		if int(template["severity"]) < min_severity:
			continue
		playable.append(beat)

	var cap := int(rules["max_sequence_beats"])
	if playable.size() <= cap:
		return playable

	# Over the cap the loudest news wins its place. Ties break on position, so
	# the choice is reproducible — src/core/ has to replay identically, and
	# sort_custom makes no stability promise of its own.
	var order: Array = []
	for i in range(playable.size()):
		order.append(i)
	order.sort_custom(func(a, b):
		var severity_a := severity_of(data, playable[a])
		var severity_b := severity_of(data, playable[b])
		if severity_a != severity_b:
			return severity_a > severity_b
		return a < b)
	var keep := {}
	for i in range(cap):
		keep[order[i]] = true

	# The survivors replay in journal order, so the day still reads as a
	# sequence of events rather than a ranking.
	var kept: Array = []
	for i in range(playable.size()):
		if keep.has(i):
			kept.append(playable[i])
	return kept


static func headlines(data: GameData, beats: Array) -> Array:
	## The two or three things a person would actually repeat about today.
	var threshold := int(data.balance["dispatch"]["headline_min_severity"])
	var found: Array = []
	for beat in beats:
		if severity_of(data, beat) >= threshold:
			found.append(beat)
	return found
