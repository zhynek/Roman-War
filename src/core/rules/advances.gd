class_name AdvanceRules
## Technology as accumulated practice rather than a research tree. There is no
## queue and nothing to choose: advances unlock when a faction's Craft crosses
## their threshold, and are LOST again when it falls back below the threshold
## times a retention factor. A people does not own what it has worked out; it
## keeps it only for as long as it keeps teaching it.
##
## Consumes no randomness. Faction-held advances live in state.factions[id].advances.


static func held(state: Dictionary, faction_id: String) -> Array:
	var faction: Dictionary = state["factions"].get(faction_id, {})
	return faction.get("advances", [])


static func available_to(data: GameData, faction_id: String) -> Array:
	## Advance ids this faction's culture may ever reach, in threshold order.
	var culture := data.culture_of_faction(faction_id)
	var ids: Array = data.advances.keys()
	ids.sort()
	var result: Array = []
	for advance_id in ids:
		var advance: Dictionary = data.advances[advance_id]
		if advance.has("culture") and String(advance["culture"]) != culture:
			continue
		result.append(advance_id)
	result.sort_custom(func(a, b):
		var ta := float(data.advances[a]["knowledge_threshold"])
		var tb := float(data.advances[b]["knowledge_threshold"])
		return ta < tb if ta != tb else String(a) < String(b))
	return result


static func effect_total(data: GameData, state: Dictionary, faction_id: String, effect: String) -> float:
	var total := 0.0
	for advance_id in held(state, faction_id):
		total += float(data.advances.get(advance_id, {}).get("effects", {}).get(effect, 0.0))
	return total


static func refresh(data: GameData, state: Dictionary, faction_ids: Array) -> Array:
	## Recompute every faction's advances from its Craft. Returns notices for
	## what was gained and — the part that matters — what was forgotten.
	var rules: Dictionary = data.balance["society"]
	var retention := float(rules["advance_retention_factor"])
	var notices: Array = []
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction["alive"]:
			continue
		var knowledge := float(SocietyRules.faction_stocks(data, faction)["knowledge"])
		var previous: Array = faction.get("advances", [])
		var current: Array = []
		for advance_id in available_to(data, faction_id):
			var threshold := float(data.advances[advance_id]["knowledge_threshold"])
			if previous.has(advance_id):
				# Held knowledge is stickier than new knowledge, but not permanent.
				if knowledge >= threshold * retention:
					current.append(advance_id)
				else:
					notices.append({"kind": "advance_lost", "faction": faction_id, "advance": advance_id})
			elif knowledge >= threshold:
				current.append(advance_id)
				notices.append({"kind": "advance_gained", "faction": faction_id, "advance": advance_id})
		faction["advances"] = current
	return notices
