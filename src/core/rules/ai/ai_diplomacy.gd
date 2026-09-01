class_name AiDiplomacy
## War and peace initiative for the campaign AI: declare war on a hated,
## reachable, beatable neighbor; sue for peace (with silver or tribute) when
## clearly losing; propose trade between compatible neutrals. At most one new
## war, one peace attempt and one trade proposal per faction per turn, so the
## world shifts rather than convulses.
##
## The war ledger below (war_key / ai_memory / tick_wars) comes from the other
## branch's diplomacy AI and is kept: FactionAi records each house's campaign
## target in it, and tick_wars is what finally guts a war neither side can
## prosecute.
##
## Offers to another AI resolve immediately, both sides judged by
## DiplomacyRules.evaluate_offer. Offers to the player queue in
## state.pending_offers with an expiry and a per-pair cooldown. Fully
## deterministic — sorted candidate loops, no rng.


static func run(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary,
		events: Array, round_strengths: Dictionary = {}) -> void:
	# One world pass prices every faction, another maps who can be touched;
	# every consideration below reuses both. The pricing is a PER-TURN value —
	# FactionAi.begin_round computes it once and hands the same snapshot to
	# every house, so twenty-one houses cost one pass over the world rather
	# than twenty-one. Every house then judges the same world, which is fairer
	# as well as faster.
	var strengths := round_strengths if not round_strengths.is_empty() \
		else AiStrategy.all_faction_strengths(data, state)
	var reach := _build_reach_map(data, state, faction_id)
	_consider_war(data, state, faction_id, persona, events, strengths, reach)
	# Two ways a war ends, and they are complementary: sue for terms when you
	# are clearly losing (with silver or tribute), and let a war neither side
	# can prosecute simply gutter out. The first is this branch's negotiation
	# model; the second is the other branch's staleness ledger.
	_consider_peace(data, state, faction_id, persona, events, strengths)
	white_peace_stalled(data, state, faction_id, events)
	_consider_trade(data, state, faction_id, persona, events, strengths, reach)


static func _consider_war(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, events: Array, strengths: Dictionary, reach: Dictionary) -> void:
	var rules: Dictionary = data.balance["diplomacy"]
	var ai_rules: Dictionary = data.balance["ai"]

	# Three restraints carried over from the other branch's diplomacy AI: a
	# house with an empty chest cannot campaign, nobody fights everyone at
	# once, and the ink on a peace stays dry before a new ultimatum.
	if int(state["factions"][faction_id]["treasury"]) < int(ai_rules["war_chest"]):
		return
	var open_wars := 0
	for enemy_id in AiAssess.enemies_of(state, faction_id):
		if not data.factions.get(enemy_id, {}).get("is_rebel", false):
			open_wars += 1
	if open_wars >= int(ai_rules["max_active_wars"]):
		return
	var peace_turn: Dictionary = ai_memory(state)["peace_turn"]
	var peace_cooldown := int(ai_rules["peace_cooldown_turns"])

	var my_strength: float = strengths[faction_id]
	var needed_ratio := float(rules["war_strength_ratio"]) \
		/ maxf(float(persona.get("aggression", 1.0)), 0.01)

	# While brigand land remains in reach, appetite goes there; once the map
	# offers no free room, hungry empires turn on their neighbors.
	var threshold := float(rules["war_declare_attitude"])
	if not _reachable_via(reach, "rebels"):
		threshold += float(rules["war_no_room_shift"]) * float(persona.get("expansion_drive", 1.0))

	var best_target := ""
	var best_attitude := 0.0
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == faction_id or not state["factions"][other_id]["alive"]:
			continue
		if data.factions.get(other_id, {}).get("is_rebel", false):
			continue
		if DiplomacyRules.at_war(state, faction_id, other_id):
			continue
		if _roman_internal(data, faction_id, other_id) \
				and not (state["factions"][faction_id]["at_civil_war"]
					or state["factions"][other_id]["at_civil_war"]):
			continue  # Roman quarrels stay in the forum until a civil war breaks
		var attitude := DiplomacyRules.attitude_total(data, state, faction_id, other_id, strengths)
		if attitude >= threshold:
			continue
		if my_strength < float(strengths[other_id]) * needed_ratio:
			continue
		if not _reachable_via(reach, other_id):
			continue
		var made_peace = peace_turn.get(war_key(faction_id, other_id))
		if made_peace != null and int(state["turn"]) - int(made_peace) < peace_cooldown:
			continue
		if best_target == "" or attitude < best_attitude:
			best_target = other_id
			best_attitude = attitude
	if best_target != "":
		DiplomacyRules.declare_war(data, state, faction_id, best_target)
		events.append({"kind": "war_declared", "by": faction_id, "on": best_target})


static func white_peace_stalled(data: GameData, state: Dictionary, faction_id: String, ai_notices: Array) -> void:
	## Quiet turns end wars in three bands: peace_min_war_turns for a war
	## nobody even aims at any more, the longer peace_stale_war_turns while a
	## side still holds a campaign target against the other (preparation is
	## intent, but even intent goes stale), and the short
	## peace_exhausted_war_turns when either treasury is too empty to make the
	## intent credible.
	var ai_rules: Dictionary = data.balance["ai"]
	var memory := ai_memory(state)
	var war_turns: Dictionary = memory["war_turns"]
	var targets: Dictionary = memory["targets"]
	var exhausted_line := int(ai_rules["peace_exhausted_treasury"])
	for other_id in AiAssess.enemies_of(state, faction_id):
		if not _peace_capable(data, state, other_id):
			continue
		var key := war_key(faction_id, other_id)
		var quiet := int(war_turns.get(key, 0))
		var threshold := int(ai_rules["peace_min_war_turns"])
		if _aims_at(state, targets, faction_id, other_id) \
				or _aims_at(state, targets, other_id, faction_id):
			threshold = int(ai_rules["peace_stale_war_turns"])
		if int(state["factions"][faction_id]["treasury"]) < exhausted_line \
				or int(state["factions"][other_id]["treasury"]) < exhausted_line:
			threshold = mini(threshold, int(ai_rules["peace_exhausted_war_turns"]))
		if quiet >= threshold:
			DiplomacyRules.set_stance(state, faction_id, other_id, "neutral")
			war_turns.erase(key)
			memory["peace_turn"][key] = int(state["turn"])
			ai_notices.append({"kind": "peace", "faction": faction_id, "target": other_id})

static func _consider_peace(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, events: Array, strengths: Dictionary) -> void:
	var rules: Dictionary = data.balance["diplomacy"]
	var my_strength: float = strengths[faction_id]
	var threshold := float(rules["peace_seek_strength_ratio"]) \
		* float(persona.get("peace_willingness", 1.0))
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == faction_id or not state["factions"][other_id]["alive"]:
			continue
		if data.factions.get(other_id, {}).get("is_rebel", false):
			continue  # there is no treating with brigands
		if not DiplomacyRules.at_war(state, faction_id, other_id):
			continue
		var their_strength: float = strengths[other_id]
		if my_strength >= their_strength * threshold:
			continue  # the war is not lost enough to sue for peace

		var offer := {"from": faction_id, "to": other_id, "stance": "neutral",
			"give_payment": 0, "give_tribute": null, "give_regions": [],
			"ask_payment": 0, "ask_tribute": null, "ask_regions": []}
		var verdict := DiplomacyRules.evaluate_offer(data, state, faction_id, other_id, offer, strengths)
		if not verdict["accept"]:
			var needed := int(ceil(-float(verdict["score"]))) + int(rules["peace_sweetener_margin"])
			var spare: int = int(state["factions"][faction_id]["treasury"]) \
				- int(data.balance["ai"]["treasury_reserve"])
			if spare >= needed:
				offer["give_payment"] = needed
			else:
				var turns := int(rules["peace_tribute_turns"])
				offer["give_tribute"] = {"turns": turns, "amount":
					int(ceil(float(needed) / (float(turns) * float(rules["tribute_value_factor"]))))}
		if other_id == state.get("player_faction", ""):
			_queue_offer_to_player(data, state, offer, events)
		else:
			verdict = DiplomacyRules.evaluate_offer(data, state, faction_id, other_id, offer, strengths)
			if verdict["accept"]:
				DiplomacyRules.apply_offer(data, state, offer)
				events.append({"kind": "peace_made", "between": [faction_id, other_id]})
		return  # one suit for peace a turn


static func _consider_trade(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, events: Array, strengths: Dictionary, reach: Dictionary) -> void:
	var rules: Dictionary = data.balance["diplomacy"]
	if float(persona.get("peace_willingness", 1.0)) < float(rules["trade_propose_min_willingness"]):
		return  # raiders do not send trade envoys
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == faction_id or not state["factions"][other_id]["alive"]:
			continue
		if data.factions.get(other_id, {}).get("is_rebel", false):
			continue
		if DiplomacyRules.stance_between(state, faction_id, other_id) != "neutral":
			continue
		if DiplomacyRules.attitude_total(data, state, faction_id, other_id, strengths) \
				< float(rules["trade_min_attitude"]):
			continue
		if not _reachable_via(reach, other_id):
			continue
		var offer := {"from": faction_id, "to": other_id, "stance": "trade",
			"give_payment": 0, "give_tribute": null, "give_regions": [],
			"ask_payment": 0, "ask_tribute": null, "ask_regions": []}
		if other_id == state.get("player_faction", ""):
			_queue_offer_to_player(data, state, offer, events)
			return
		if DiplomacyRules.evaluate_offer(data, state, faction_id, other_id, offer, strengths)["accept"]:
			DiplomacyRules.apply_offer(data, state, offer)
			events.append({"kind": "trade_agreed", "between": [faction_id, other_id]})
			return  # one new partner a turn


static func _queue_offer_to_player(data: GameData, state: Dictionary, offer: Dictionary, events: Array) -> void:
	var rules: Dictionary = data.balance["diplomacy"]
	for pending in state["pending_offers"]:
		if pending.get("from", "") == offer["from"] and pending.get("to", "") == offer["to"]:
			return  # one envoy at their door at a time
	var ai_memory: Dictionary = state["factions"][offer["from"]]["ai"]
	var cooldowns: Dictionary = ai_memory.get("offer_cooldowns", {})
	ai_memory["offer_cooldowns"] = cooldowns
	var last := int(cooldowns.get(offer["to"], -(1 << 20)))
	if int(state["turn"]) - last < int(rules["ai_offer_cooldown_turns"]):
		return
	cooldowns[offer["to"]] = int(state["turn"])
	offer["id"] = "offer_%d" % state["next_id"]
	state["next_id"] = int(state["next_id"]) + 1
	offer["expires_turn"] = int(state["turn"]) + int(rules["offer_expiry_turns"])
	state["pending_offers"].append(offer)
	events.append({"kind": "offer_sent", "from": offer["from"], "to": offer["to"]})


static func _build_reach_map(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	## Who this faction can touch, from ONE world pass: land borders, plus the
	## sea zones its coasts reach (own zones and their neighbors) against every
	## other faction's direct coastal zones. Mirrors sea_move_army's
	## same-or-adjacent-zone rule. Set-building only — order-free.
	var borders := {}
	var my_zones := {}
	var their_zones := {}
	for region_id in state["settlements"]:
		var owner: String = state["settlements"][region_id]["owner"]
		if owner == faction_id:
			for neighbor in data.regions[region_id].get("adjacent", []):
				if state["settlements"].has(neighbor):
					var other: String = state["settlements"][neighbor]["owner"]
					if other != faction_id:
						borders[other] = true
			for zone in data.regions[region_id].get("sea_zones", []):
				my_zones[zone] = true
				for adjacent_zone in data.sea_zones.get(zone, {}).get("adjacent", []):
					my_zones[adjacent_zone] = true
		else:
			for zone in data.regions[region_id].get("sea_zones", []):
				their_zones.get_or_add(owner, {})[zone] = true
	return {"borders": borders, "my_zones": my_zones, "their_zones": their_zones}


static func _reachable_via(reach: Dictionary, other_id: String) -> bool:
	if reach["borders"].has(other_id):
		return true
	for zone in reach["their_zones"].get(other_id, {}):
		if reach["my_zones"].has(zone):
			return true
	return false


static func _roman_internal(data: GameData, a: String, b: String) -> bool:
	var faction_a: Dictionary = data.factions.get(a, {})
	var faction_b: Dictionary = data.factions.get(b, {})
	return (faction_a.get("is_roman_house", false) or faction_a.get("is_senate", false)) \
		and (faction_b.get("is_roman_house", false) or faction_b.get("is_senate", false))


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
	## AI-vs-AI war, resetting pairs that saw physical prosecution — a siege
	## between the pair, or an army standing on the other's ground. (A war
	## merely being mustered for does not reset the clock; it instead holds
	## out for the longer peace_stale_war_turns in consider_peace, so cold
	## wars still end while preparation is protected from a premature peace.)
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
		if not state["factions"].has(faction_id) or not state["factions"][faction_id]["alive"] \
				or not state["settlements"].has(targets[faction_id]):
			targets.erase(faction_id)

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


static func _aims_at(state: Dictionary, targets: Dictionary, faction_id: String, other_id: String) -> bool:
	var goal: String = targets.get(faction_id, "")
	return goal != "" and state["settlements"].has(goal) \
		and state["settlements"][goal]["owner"] == other_id
