class_name AiDiplomacy
## War and peace initiative for the campaign AI: declare war on a hated,
## reachable, beatable neighbor; sue for peace (with silver or tribute) when
## clearly losing; propose trade between compatible neutrals. At most one new
## war, one peace attempt and one trade proposal per faction per turn, so the
## world shifts rather than convulses.
##
## Offers to another AI resolve immediately, both sides judged by
## DiplomacyRules.evaluate_offer. Offers to the player queue in
## state.pending_offers with an expiry and a per-pair cooldown. Fully
## deterministic — sorted candidate loops, no rng.


static func run(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, events: Array) -> void:
	# One world pass prices every faction; every attitude below reuses it.
	var strengths := AiStrategy.all_faction_strengths(data, state)
	_consider_war(data, state, faction_id, persona, events, strengths)
	_consider_peace(data, state, faction_id, persona, events, strengths)
	_consider_trade(data, state, faction_id, persona, events, strengths)


static func _consider_war(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, events: Array, strengths: Dictionary) -> void:
	var rules: Dictionary = data.balance["diplomacy"]
	var my_strength: float = strengths[faction_id]
	var needed_ratio := float(rules["war_strength_ratio"]) \
		/ maxf(float(persona.get("aggression", 1.0)), 0.01)
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
		if attitude >= float(rules["war_declare_attitude"]):
			continue
		if my_strength < float(strengths[other_id]) * needed_ratio:
			continue
		if not _reachable(data, state, faction_id, other_id):
			continue
		if best_target == "" or attitude < best_attitude:
			best_target = other_id
			best_attitude = attitude
	if best_target != "":
		DiplomacyRules.declare_war(data, state, faction_id, best_target)
		events.append({"kind": "war_declared", "by": faction_id, "on": best_target})


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


static func _consider_trade(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, events: Array, strengths: Dictionary) -> void:
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
		if not _reachable(data, state, faction_id, other_id):
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


static func _reachable(data: GameData, state: Dictionary, faction_id: String, other_id: String) -> bool:
	## A war (or trade route) needs a way to touch: a land border, or a sea link
	## between a coastal holding of each side.
	if DiplomacyRules.share_border(data, state, faction_id, other_id):
		return true
	var mine: Array = []
	var theirs: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var owner: String = state["settlements"][region_id]["owner"]
		if owner == faction_id and MapRules.coastal(data, region_id):
			mine.append(region_id)
		elif owner == other_id and MapRules.coastal(data, region_id):
			theirs.append(region_id)
	for own_region in mine:
		for their_region in theirs:
			if AiStrategy.sea_linked(data, own_region, their_region):
				return true
	return false


static func _roman_internal(data: GameData, a: String, b: String) -> bool:
	var faction_a: Dictionary = data.factions.get(a, {})
	var faction_b: Dictionary = data.factions.get(b, {})
	return (faction_a.get("is_roman_house", false) or faction_a.get("is_senate", false)) \
		and (faction_b.get("is_roman_house", false) or faction_b.get("is_senate", false))
