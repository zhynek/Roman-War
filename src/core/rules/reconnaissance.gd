class_name ReconRules
## Observation is campaign state, sampled when a force actually changes region.
## The renderer receives public snapshots, never a hidden army's live roster.

static func rules(data: GameData) -> Dictionary:
	return data.balance.get("reconnaissance", {})


static func army_sight(data: GameData, army: Dictionary) -> int:
	return int(rules(data).get("mounted_sight" if MovementRules.mobility_profile(data, army)["mounted"] else "army_sight", 1))


static func post_active(state: Dictionary, region: String, post: Dictionary) -> bool:
	# Posts stand only while their province remains in their builder's hands.
	return not post.is_empty() and state["settlements"].get(region, {}).get("owner", "") == post.get("owner", "")


static func post_quote(data: GameData, state: Dictionary, army_id: String) -> Dictionary:
	var army: Dictionary = state["armies"].get(army_id, {})
	var result := {"ok": false, "reason": "post_need_army", "level": 1, "cost": 0, "sight": 0}
	if army.is_empty() or army["owner"] != state["player_faction"]:
		return result
	var region := String(army["region"])
	var post: Dictionary = state.get("watchposts", {}).get(region, {})
	var level := int(post.get("level", 0)) if post_active(state, region, post) else 0
	result["level"] = level + 1
	result["cost"] = int(rules(data).get("watchtower_cost" if level == 0 else "fort_cost", 0))
	result["sight"] = int(rules(data).get("watchtower_sight" if level == 0 else "fort_sight", 2))
	if level >= 2:
		result["reason"] = "post_complete"
	elif state["settlements"].get(region, {}).get("owner", "") != army["owner"]:
		result["reason"] = "post_own_land"
	elif state["settlements"][region].get("siege") != null or ForceRules.besieging(state, army_id) != null:
		result["reason"] = "post_under_siege"
	elif float(army["movement_left"]) < float(rules(data).get("build_movement_cost", 1)):
		result["reason"] = "post_no_movement"
	elif int(state["factions"][army["owner"]]["treasury"]) < int(result["cost"]):
		result["reason"] = "post_no_money"
	else:
		result["ok"] = true
		result["reason"] = ""
	return result


static func build_post(data: GameData, state: Dictionary, army_id: String) -> Dictionary:
	var quote := post_quote(data, state, army_id)
	if not quote["ok"]:
		return quote
	var army: Dictionary = state["armies"][army_id]
	state["factions"][army["owner"]]["treasury"] -= int(quote["cost"])
	army["movement_left"] = SocietyRules.quantize(float(army["movement_left"]) - float(rules(data)["build_movement_cost"]))
	state["watchposts"] = state.get("watchposts", {})
	state["watchposts"][army["region"]] = {"owner": army["owner"], "level": quote["level"]}
	refresh_contacts(data, state)
	return quote


static func fort_defense(data: GameData, state: Dictionary, army: Dictionary) -> float:
	var region := String(army["region"])
	var post: Dictionary = state.get("watchposts", {}).get(region, {})
	if post_active(state, region, post) and post["owner"] == army["owner"] and int(post["level"]) >= 2:
		return float(rules(data).get("fort_defense_pct", 0))
	return 0.0


static func public_summary(data: GameData, state: Dictionary, army_id: String) -> Dictionary:
	var army: Dictionary = state["armies"][army_id]
	var general = null
	if army.get("general") != null and state["characters"].has(army["general"]):
		var character: Dictionary = state["characters"][army["general"]]
		general = {"id": army["general"], "name": character["name"], "age": character.get("age", 30),
			"command": character.get("command", 0), "is_leader": character.get("role", "") == "leader"}
	return {"id": army_id, "owner": army["owner"], "region": army["region"], "general": general,
		"units": army["units"].size(), "soldiers": CombatRules.soldiers_in(data, army["units"])}


static func record_move(data: GameData, state: Dictionary, army_id: String, destination: String) -> void:
	var army: Dictionary = state["armies"][army_id]
	if army["owner"] == state["player_faction"] or not state.has("recon"):
		return
	var visible := VisibilityRules.visible_regions(data, state, state["player_faction"])
	var origin := String(army["region"])
	if not visible.has(origin) and not visible.has(destination):
		return
	var summary := public_summary(data, state, army_id)
	# A hidden endpoint is deliberately absent, even when a road would let the
	# player guess it. Neither replay nor a loaded dispatch may recover it.
	var from := origin if visible.has(origin) else ""
	var to := destination if visible.has(destination) else ""
	summary["region"] = to if to != "" else from
	var sighting := {"id": army_id, "from": from, "to": to, "summary": summary, "turn": state["turn"]}
	state["recon"]["movements"].append(sighting)
	state["recon"]["contacts"][army_id] = {"summary": summary.duplicate(true), "turn": state["turn"]}


static func refresh_contacts(data: GameData, state: Dictionary) -> void:
	CartographyRules.record_reports(data, state)
	if not state.has("recon"):
		return
	var visible := VisibilityRules.visible_regions(data, state, state["player_faction"])
	var contacts: Dictionary = state["recon"]["contacts"]
	var lifetime := int(rules(data).get("contact_memory_turns", 3))
	for id in contacts.keys():
		var contact: Dictionary = contacts[id]
		if int(state["turn"]) - int(contact["turn"]) > lifetime or visible.has(contact["summary"]["region"]):
			contacts.erase(id)
	var ids: Array = state["armies"].keys()
	ids.sort()
	for id in ids:
		var army: Dictionary = state["armies"][id]
		if army["owner"] != state["player_faction"] and visible.has(army["region"]):
			contacts[id] = {"summary": public_summary(data, state, id), "turn": state["turn"]}
