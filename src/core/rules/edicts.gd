class_name EdictRules
## Edicts — the statecraft lever beside the building queue (Phase 6). A
## STANDING edict is a held policy: enacted for a price, carried at upkeep,
## its effects faction-wide until repealed (and repeal has a price of its
## own — take away the dole and the crowd remembers). A DECREE is a one-time
## act whose mood lives in the stacking modifier container and fades.
##
## Everything tunable: balance.json → edicts; the table is data/edicts.json,
## each entry carrying its historical_basis. Enacted standing edicts live in
## factions[fid].edicts as {eid: {turn}}, cooldowns (after repeal, and after
## a decree) in factions[fid].edict_cooldowns. The insolvency rule is the
## historically self-balancing one: when the silver runs out, the costliest
## policy collapses on its own, shock and all. Rebels hold no edicts.


static func enacted(state: Dictionary, faction_id: String) -> Dictionary:
	var faction: Dictionary = state["factions"][faction_id]
	if not faction.has("edicts"):
		faction["edicts"] = {}
	return faction["edicts"]


static func cooldowns(state: Dictionary, faction_id: String) -> Dictionary:
	var faction: Dictionary = state["factions"][faction_id]
	if not faction.has("edict_cooldowns"):
		faction["edict_cooldowns"] = {}
	return faction["edict_cooldowns"]


static func available(data: GameData, state: Dictionary, faction_id: String, caches: Dictionary = {}) -> Array:
	## Every edict this court could hold, each with {id, edict, cost, ready,
	## reason} — reason names the first bar in the way ("" when enactable),
	## so the UI can show the whole book with the locked pages explained.
	var effective_caches := caches if not caches.is_empty() else KnowledgeRules.build_caches(data, state, false)
	var held := enacted(state, faction_id)
	var result: Array = []
	var edict_ids: Array = data.edicts.keys()
	edict_ids.sort()
	for eid in edict_ids:
		if held.has(eid):
			continue
		var edict: Dictionary = data.edicts[eid]
		var allowed: Array = edict["availability"]["cultures"]
		if not allowed.is_empty() and not allowed.has(data.culture_of_faction(faction_id)):
			continue  # not of this court's world at all — not even listed
		result.append({
			"id": eid, "edict": edict, "cost": int(edict["enact_cost"]),
			"reason": _refusal(data, state, effective_caches, faction_id, eid),
		})
	return result


static func enact(data: GameData, state: Dictionary, faction_id: String, edict_id: String, caches: Dictionary = {}) -> Dictionary:
	var refused := {"ok": false, "reason": "", "cost": 0}
	var edict: Dictionary = data.edicts.get(edict_id, {})
	var faction: Dictionary = state["factions"].get(faction_id, {})
	if edict.is_empty() or faction.is_empty() or not faction.get("alive", false):
		refused["reason"] = "unknown"
		return refused
	var allowed: Array = edict["availability"]["cultures"]
	if not allowed.is_empty() and not allowed.has(data.culture_of_faction(faction_id)):
		refused["reason"] = "foreign_custom"
		return refused
	var effective_caches := caches if not caches.is_empty() else KnowledgeRules.build_caches(data, state, false)
	var reason := _refusal(data, state, effective_caches, faction_id, edict_id)
	if reason != "":
		refused["reason"] = reason
		return refused
	var cost := int(edict["enact_cost"])
	refused["cost"] = cost
	if int(faction["treasury"]) < cost:
		refused["reason"] = "treasury"
		return refused
	faction["treasury"] = int(faction["treasury"]) - cost

	var tensions: Dictionary = edict["tensions"]
	faction["senate_standing"] = _clamped_senate(data,
		float(faction["senate_standing"]) + float(tensions["senate_standing_delta"]))
	faction["popular_standing"] = float(faction["popular_standing"]) + float(tensions["popular_standing_delta"])

	if String(edict["kind"]) == "decree":
		var mood: Dictionary = edict["timed_happiness"]
		ModifierRules.add(state, faction_id, "", "happiness",
			float(mood["value"]), int(mood["turns"]), "decree:" + edict_id)
		cooldowns(state, faction_id)[edict_id] = int(data.balance["edicts"]["reenact_cooldown_turns"])
	else:
		enacted(state, faction_id)[edict_id] = {"turn": int(state["turn"])}
	return {"ok": true, "reason": "", "cost": cost}


static func repeal(data: GameData, state: Dictionary, faction_id: String, edict_id: String) -> bool:
	## Repealing is free of coin and dear in mood: the repeal_unrest shock
	## lands as a fading happiness modifier, and the cooldown bars a quick
	## re-enactment (policy is not a lamp to flick).
	var held := enacted(state, faction_id)
	if not held.has(edict_id):
		return false
	held.erase(edict_id)
	var edict: Dictionary = data.edicts.get(edict_id, {})
	var shock: Dictionary = edict.get("tensions", {}).get("repeal_unrest", {})
	if float(shock.get("penalty", 0.0)) > 0.0 and int(shock.get("turns", 0)) > 0:
		ModifierRules.add(state, faction_id, "", "happiness",
			-float(shock["penalty"]), int(shock["turns"]), "repeal:" + edict_id)
	cooldowns(state, faction_id)[edict_id] = int(data.balance["edicts"]["reenact_cooldown_turns"])
	return true


static func faction_effect_total(data: GameData, state: Dictionary, faction_id: String, effect: String) -> float:
	## Sum an effect across the faction's enacted standing edicts. Sits on the
	## same hot paths as its knowledge twin — allocation-free inner loop.
	var faction = state["factions"].get(faction_id)
	if faction == null:
		return 0.0
	var held = faction.get("edicts")
	if held == null or (held as Dictionary).is_empty():
		return 0.0
	var total := 0.0
	var edicts := data.edicts
	for eid in held:  # pure sum — iteration order cannot steer anything
		var edict = edicts.get(eid)
		if edict == null:
			continue
		var effects = (edict as Dictionary).get("effects")
		if effects != null:
			total += float((effects as Dictionary).get(effect, 0.0))
	return total


static func upkeep(data: GameData, state: Dictionary, faction_id: String) -> int:
	## What holding the book of policies costs this turn: flat upkeep plus the
	## per-head clauses (the dole scales with the mouths it feeds).
	var held: Dictionary = state["factions"].get(faction_id, {}).get("edicts", {})
	if held.is_empty():
		return 0
	var population := 0
	for settlement in state["settlements"].values():  # pure sum
		if settlement["owner"] == faction_id:
			population += int(settlement["population"])
	var total := 0.0
	for eid in held:  # pure sum
		var edict: Dictionary = data.edicts.get(eid, {})
		total += float(edict.get("upkeep_per_turn", 0)) \
			+ float(edict.get("upkeep_per_1000_pop", 0.0)) * population / 1000.0
	return int(round(total))


static func process_turn(data: GameData, state: Dictionary) -> Array:
	## Runs right after treasuries resolve: standing drips tick, cooldowns
	## fade, and an insolvent court watches its costliest policy collapse
	## (auto-repeal with the full shock — the dole ends when the silver does).
	## Deterministic, no rng. Returns report events.
	var events: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction["alive"]:
			continue
		var held := enacted(state, faction_id)
		if not held.is_empty():
			var senate_drip := faction_effect_total(data, state, faction_id, "senate_standing_per_turn")
			var popular_drip := faction_effect_total(data, state, faction_id, "popular_standing_per_turn")
			if senate_drip != 0.0:
				faction["senate_standing"] = _clamped_senate(data, float(faction["senate_standing"]) + senate_drip)
			if popular_drip != 0.0:
				faction["popular_standing"] = float(faction["popular_standing"]) + popular_drip

			if int(faction["treasury"]) < int(data.balance["edicts"]["insolvency_repeal_treasury"]):
				var costliest := _costliest_edict(data, held)
				if costliest != "":
					repeal(data, state, faction_id, costliest)
					events.append({"kind": "edict_lapsed", "faction": faction_id, "edict": costliest})

		var cooling := cooldowns(state, faction_id)
		var edict_ids: Array = cooling.keys()
		edict_ids.sort()
		for eid in edict_ids:
			cooling[eid] = int(cooling[eid]) - 1
			if int(cooling[eid]) <= 0:
				cooling.erase(eid)
	return events


static func _costliest_edict(data: GameData, held: Dictionary) -> String:
	## Highest flat+per-head upkeep, sorted-id tie-break (save-determinism).
	var best := ""
	var best_upkeep := -1.0
	var edict_ids: Array = held.keys()
	edict_ids.sort()
	for eid in edict_ids:
		var edict: Dictionary = data.edicts.get(eid, {})
		var cost := float(edict.get("upkeep_per_turn", 0)) + float(edict.get("upkeep_per_1000_pop", 0.0))
		if cost > best_upkeep:
			best_upkeep = cost
			best = eid
	return best


static func _refusal(data: GameData, state: Dictionary, caches: Dictionary, faction_id: String, edict_id: String) -> String:
	## The first bar in the way, or "" — shared by available() and enact().
	var edict: Dictionary = data.edicts[edict_id]
	var held := enacted(state, faction_id)
	if held.has(edict_id):
		return "already_held"
	if int(cooldowns(state, faction_id).get(edict_id, 0)) > 0:
		return "too_soon"
	for other in edict["tensions"]["exclusive_with"]:
		if held.has(other):
			return "contradicts_" + String(other)
	if String(edict["kind"]) == "standing" \
			and held.size() >= int(data.balance["edicts"]["max_enacted"]):
		return "book_full"
	var prereq: Dictionary = edict["prerequisites"]
	var kind := String(prereq["building_kind"])
	if kind != "" and int(caches["kind_levels"].get(faction_id, {}).get(kind, 0)) < int(prereq["building_level"]):
		return "wants_building"
	for needed in prereq["techniques"]:
		if not KnowledgeRules.adopted(state, faction_id, String(needed)):
			return "wants_technique"
	return ""


static func _clamped_senate(data: GameData, value: float) -> float:
	return clampf(value, float(data.balance["senate"]["min_standing"]),
		float(data.balance["senate"]["max_standing"]))
