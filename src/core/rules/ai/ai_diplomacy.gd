class_name AiDiplomacy
## Deliberate war and peace for AI factions. Wars are declared only against
## neutral neighbors, from a full war chest, at favorable odds, and within the
## configured limit of simultaneous wars; Roman houses never open a war against
## another house or the senate (the civil-war rules own that). Stalled AI-vs-AI
## wars end in a white peace once neither side has prosecuted them for long
## enough — wars against the player never end on their own (negotiation is the
## player's, and Phase 5's, business). The staleness ledger lives in
## state.ai.war_turns so a loaded save remembers how tired every war is.


static func war_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func ai_memory(state: Dictionary) -> Dictionary:
	if not state.has("ai"):
		state["ai"] = {}
	var memory: Dictionary = state["ai"]
	if not memory.has("war_turns"):
		memory["war_turns"] = {}
	if not memory.has("targets"):
		memory["targets"] = {}
	if not memory.has("peace_turn"):
		memory["peace_turn"] = {}
	return memory


static func tick_wars(data: GameData, state: Dictionary) -> void:
	## Once per world turn, before any faction acts: age the ledger of every
	## AI-vs-AI war, resetting pairs that saw prosecution — a siege between the
	## pair, an army standing on the other's ground, or a campaign target aimed
	## at the other (mustering for an invasion is intent, not quiet).
	var memory := ai_memory(state)
	var war_turns: Dictionary = memory["war_turns"]

	var active := {}
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		var siege = settlement["siege"]
		if siege != null and state["armies"].has(siege["besieger"]):
			active[war_key(state["armies"][siege["besieger"]]["owner"], settlement["owner"])] = true
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if not state["settlements"].has(army["region"]):
			continue
		var holder: String = state["settlements"][army["region"]]["owner"]
		if DiplomacyRules.at_war(state, army["owner"], holder):
			active[war_key(army["owner"], holder)] = true
	var targets: Dictionary = memory["targets"]
	var aiming_ids: Array = targets.keys()
	aiming_ids.sort()
	for faction_id in aiming_ids:
		var goal: String = targets[faction_id]
		if not state["factions"].has(faction_id) or not state["factions"][faction_id]["alive"] \
				or not state["settlements"].has(goal):
			targets.erase(faction_id)
			continue
		var holder: String = state["settlements"][goal]["owner"]
		if DiplomacyRules.at_war(state, faction_id, holder):
			active[war_key(faction_id, holder)] = true

	var peace_turn: Dictionary = memory["peace_turn"]
	var cooldown := int(data.balance["ai"]["peace_cooldown_turns"])
	var peace_keys: Array = peace_turn.keys()
	peace_keys.sort()
	for key in peace_keys:
		if int(state["turn"]) - int(peace_turn[key]) > cooldown:
			peace_turn.erase(key)

	var tracked := {}
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for a in faction_ids:
		if not _peace_capable(data, state, a):
			continue
		for b in faction_ids:
			if b <= a or not _peace_capable(data, state, b):
				continue
			if DiplomacyRules.at_war(state, a, b):
				tracked[war_key(a, b)] = true

	var stale_keys: Array = war_turns.keys()
	stale_keys.sort()
	for key in stale_keys:
		if not tracked.has(key):
			war_turns.erase(key)
	var tracked_keys: Array = tracked.keys()
	tracked_keys.sort()
	for key in tracked_keys:
		war_turns[key] = 0 if active.has(key) else int(war_turns.get(key, 0)) + 1


static func _peace_capable(data: GameData, state: Dictionary, faction_id: String) -> bool:
	## Only wars between two living AI factions can gutter out on their own.
	if faction_id == state["player_faction"]:
		return false
	if not state["factions"][faction_id]["alive"]:
		return false
	return not data.factions.get(faction_id, {}).get("is_rebel", false)


static func consider_peace(data: GameData, state: Dictionary, faction_id: String, ai_notices: Array) -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	var memory := ai_memory(state)
	var war_turns: Dictionary = memory["war_turns"]
	var exhausted_line := int(ai_rules["peace_exhausted_treasury"])
	for other_id in AiAssess.enemies_of(state, faction_id):
		if not _peace_capable(data, state, other_id):
			continue
		var key := war_key(faction_id, other_id)
		var quiet := int(war_turns.get(key, 0))
		var threshold := int(ai_rules["peace_min_war_turns"])
		if int(state["factions"][faction_id]["treasury"]) < exhausted_line \
				or int(state["factions"][other_id]["treasury"]) < exhausted_line:
			threshold = int(ceil(threshold / 2.0))
		if quiet >= threshold:
			DiplomacyRules.set_stance(state, faction_id, other_id, "neutral")
			war_turns.erase(key)
			memory["peace_turn"][key] = int(state["turn"])
			ai_notices.append({"kind": "peace", "faction": faction_id, "target": other_id})


static func consider_war(data: GameData, state: Dictionary, faction_id: String, ai_notices: Array) -> bool:
	## Called only when the faction has no reachable target left in its current
	## wars. Returns true when a war was declared.
	var ai_rules: Dictionary = data.balance["ai"]
	var faction: Dictionary = state["factions"][faction_id]
	if int(faction["treasury"]) < int(ai_rules["war_chest"]):
		return false

	var open_wars := 0
	for enemy_id in AiAssess.enemies_of(state, faction_id):
		if not data.factions.get(enemy_id, {}).get("is_rebel", false):
			open_wars += 1
	if open_wars >= int(ai_rules["max_active_wars"]):
		return false

	var we_are_roman: bool = data.factions.get(faction_id, {}).get("is_roman_house", false)
	var peace_turn: Dictionary = ai_memory(state)["peace_turn"]
	var cooldown := int(ai_rules["peace_cooldown_turns"])
	var candidates := {}
	for region_id in AiAssess.owned_regions(state, faction_id):
		for neighbor in data.regions[region_id].get("adjacent", []):
			if not state["settlements"].has(neighbor):
				continue
			var other_id: String = state["settlements"][neighbor]["owner"]
			if other_id == faction_id or not state["factions"][other_id]["alive"]:
				continue
			if DiplomacyRules.stance_between(state, faction_id, other_id) != "neutral":
				continue
			var other_data: Dictionary = data.factions.get(other_id, {})
			if other_data.get("is_rebel", false):
				continue
			if we_are_roman and (other_data.get("is_roman_house", false) or other_data.get("is_senate", false)):
				continue
			# The ink on a peace stays dry for a while before a new ultimatum.
			var made_peace = peace_turn.get(war_key(faction_id, other_id))
			if made_peace != null and int(state["turn"]) - int(made_peace) < cooldown:
				continue
			candidates[other_id] = true

	var our_power := AiAssess.faction_power(data, state, faction_id)
	var pick := ""
	var pick_power := 0.0
	var candidate_ids: Array = candidates.keys()
	candidate_ids.sort()
	for other_id in candidate_ids:
		var their_power := AiAssess.faction_power(data, state, other_id)
		if our_power < their_power * float(ai_rules["declare_war_odds"]):
			continue
		if pick == "" or their_power < pick_power:
			pick = other_id
			pick_power = their_power
	if pick == "":
		return false
	DiplomacyRules.declare_war(state, faction_id, pick)
	ai_notices.append({"kind": "war_declared", "faction": faction_id, "target": pick})
	return true
