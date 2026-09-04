class_name AiDiplomacy
## The AI at the table: it declares war on weaker neighbours it does not
## like (the more so the more aggressive, the less so across a standing
## treaty, never on Roman kin outside a civil war), seeks peace when it is
## losing or weary (sweetening the offer with gold it can spare), demands
## submission from enemies it dwarfs, and offers trade rights and alliances
## to courts it deals with. Every offer is a proposal dictionary carried by
## an envoy in contact — the same rules the player's scroll obeys. Offers to
## another AI resolve at once through DiplomacyRules.propose; offers to the
## player wait in state.pending_offers for the player's answer.


static func act(data: GameData, state: Dictionary, brain: Dictionary, notices: Array) -> void:
	if brain["is_rebel"]:
		return
	var faction_id: String = brain["id"]
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other in faction_ids:
		if other == faction_id or not state["factions"][other]["alive"]:
			continue
		if data.factions.get(other, {}).get("is_rebel", false):
			continue
		if DiplomacyRules.at_war(state, faction_id, other):
			consider_peace(data, state, brain, other, notices)
		elif not consider_war(data, state, brain, other, notices):
			consider_treaties(data, state, brain, other, notices)


## --- War -----------------------------------------------------------------------

static func consider_war(data: GameData, state: Dictionary, brain: Dictionary, other: String, notices: Array) -> bool:
	## Declares war and returns true when the numbers and the temperament say so.
	var rules: Dictionary = brain["rules"]
	var faction_id: String = brain["id"]
	var memory: Dictionary = brain["memory"]
	if AiController.weight(brain, "aggression") <= 0.0 or int(brain["p"].get("max_wars", 0)) <= 0:
		return false
	if roman_kin(data, state, faction_id, other):
		return false
	if int(brain["turn"]) - int(memory.get("last_war_turn", -999)) < int(rules["war_declare_interval_turns"]):
		return false
	# A peace just made is kept for a while, whatever the odds.
	if int(brain["turn"]) - int(state["factions"][faction_id].get("peace_since", {}).get(other, -999)) \
			< int(rules["min_peace_turns_before_war"]):
		return false
	if AiController.enemies_of(data, state, faction_id).size() >= int(brain["p"].get("max_wars", 0)):
		return false
	if int(state["factions"][faction_id]["treasury"]) < int(rules["war_declare_min_treasury"]):
		return false
	if DiplomacyRules.border_count(data, state, faction_id, other) == 0:
		return false
	if DiplomacyRules.attitude(data, state, faction_id, other) > float(rules["war_declare_attitude_max"]):
		return false
	var stance := DiplomacyRules.stance_between(state, faction_id, other)
	if stance == "protectorate" and state["factions"][faction_id].get("overlord", null) == other:
		return false
	var needed := AiController.needed_ratio(brain, float(rules["war_declare_strength_ratio"]))
	if stance in ["trade", "alliance", "protectorate"]:
		# No backstab on a fresh treaty; an old one is broken only for a
		# margin scaled by loyalty.
		if DiplomacyRules.treaty_age(state, faction_id, other) < int(rules["min_treaty_turns_before_betrayal"]):
			return false
		needed *= 1.0 + AiController.weight(brain, "loyalty") * float(rules["break_treaty_loyalty_weight"])
	if DiplomacyRules.power_ratio(data, state, faction_id, other) < needed:
		return false
	DiplomacyRules.declare_war(state, faction_id, other, data)
	memory["last_war_turn"] = brain["turn"]
	notices.append({"kind": "war_declared", "from": faction_id, "to": other, "broke_treaty": stance != "neutral"})
	return true


static func roman_kin(data: GameData, state: Dictionary, a: String, b: String) -> bool:
	## The houses and the Senate keep the peace among themselves until a
	## civil war breaks it.
	var first: Dictionary = data.factions.get(a, {})
	var second: Dictionary = data.factions.get(b, {})
	var roman_a: bool = first.get("is_roman_house", false) or first.get("is_senate", false)
	var roman_b: bool = second.get("is_roman_house", false) or second.get("is_senate", false)
	if not (roman_a and roman_b):
		return false
	return not (state["factions"][a].get("at_civil_war", false) or state["factions"][b].get("at_civil_war", false))


## --- Peace and submission --------------------------------------------------------

static func consider_peace(data: GameData, state: Dictionary, brain: Dictionary, other: String, notices: Array) -> void:
	var rules: Dictionary = brain["rules"]
	var faction_id: String = brain["id"]
	if not offer_due(brain, other):
		return
	var ratio := DiplomacyRules.power_ratio(data, state, faction_id, other)
	if ratio >= float(rules["submission_demand_strength_ratio"]) \
			and AiController.weight(brain, "aggression") >= float(rules["submission_demand_min_aggression"]):
		make_offer(data, state, brain, other, {"stance": "protectorate"}, notices)
		return
	# Weariness ends a war that is not being won and has no siege in hand.
	var weary := DiplomacyRules.war_turns(state, faction_id, other) >= int(rules["peace_seek_war_turns"]) \
		and ratio < float(rules["peace_weary_max_ratio"]) and not besieging_any(state, faction_id, other)
	if ratio < float(rules["peace_seek_strength_ratio"]) or weary:
		make_offer(data, state, brain, other, {"stance": "neutral"}, notices)


static func besieging_any(state: Dictionary, faction_id: String, other: String) -> bool:
	for settlement in state["settlements"].values():
		var siege = settlement["siege"]
		if siege == null or settlement["owner"] != other:
			continue
		if state["armies"].get(siege["besieger"], {}).get("owner", "") == faction_id:
			return true
	return false


## --- Treaties ---------------------------------------------------------------------

static func consider_treaties(data: GameData, state: Dictionary, brain: Dictionary, other: String, notices: Array) -> void:
	var rules: Dictionary = brain["rules"]
	var faction_id: String = brain["id"]
	var diplomacy := AiController.weight(brain, "diplomacy")
	if not offer_due(brain, other):
		return
	var stance := DiplomacyRules.stance_between(state, faction_id, other)
	if stance == "neutral" and diplomacy >= float(rules["trade_offer_min_diplomacy"]) \
			and DiplomacyRules.border_count(data, state, faction_id, other) > 0:
		make_offer(data, state, brain, other, {"stance": "trade"}, notices)
	elif stance in ["neutral", "trade"] and diplomacy >= float(rules["alliance_offer_min_diplomacy"]) \
			and not DiplomacyRules.shared_enemies(data, state, faction_id, other).is_empty():
		make_offer(data, state, brain, other, {"stance": "alliance"}, notices)


## --- Making offers ------------------------------------------------------------------

static func offer_due(brain: Dictionary, other: String) -> bool:
	var offers: Dictionary = brain["memory"].get("offers", {})
	return int(brain["turn"]) - int(offers.get(other, -999)) >= int(brain["rules"]["offer_interval_turns"])


static func make_offer(data: GameData, state: Dictionary, brain: Dictionary, other: String, terms: Dictionary, notices: Array) -> bool:
	## Carries the terms to the other court through an envoy in contact; with
	## none, marks the court for an envoy to travel to. Offers to the player
	## are queued for the player's answer; offers to another AI are weighed on
	## the spot and, for peace and treaties, sweetened with a gift the purse
	## can spare when the balance falls just short.
	var rules: Dictionary = brain["rules"]
	var faction_id: String = brain["id"]
	var memory: Dictionary = brain["memory"]
	var proposal := terms.duplicate(true)
	proposal["from"] = faction_id
	proposal["to"] = other
	var envoy := AgentRules.best_envoy(data, state, faction_id, other)
	if envoy == "":
		memory["envoy_target"] = other
		return false
	proposal["envoy"] = envoy
	if not memory.has("offers") or not (memory["offers"] is Dictionary):
		memory["offers"] = {}
	memory["offers"][other] = brain["turn"]

	if other == state["player_faction"]:
		if not state.has("pending_offers"):
			state["pending_offers"] = []
		state["pending_offers"].append({"from": faction_id, "proposal": proposal, "turn": brain["turn"]})
		notices.append({"kind": "offer", "from": faction_id, "stance": proposal.get("stance", "")})
		# Carrying the offer is the envoy's work for the season, answered or not.
		AgentRules.spend_season(state["agents"][envoy])
		return true

	var verdict := DiplomacyRules.evaluate(data, state, proposal)
	if not verdict["accept"] and verdict["reason"] == "" and proposal.get("stance", "") in ["neutral", "trade", "alliance"]:
		var gold_per_point := float(data.balance["diplomacy"]["offer_gold_per_point"])
		var rounding := float(rules["gift_rounding"])
		var shortfall := -float(verdict["score"])
		var gift := int(ceil(shortfall * gold_per_point / rounding) * rounding)
		var treasury := int(state["factions"][faction_id]["treasury"])
		if gift > 0 and gift <= int(float(treasury) * float(rules["peace_gift_share_of_treasury"])):
			proposal["gift"] = gift
			verdict = DiplomacyRules.evaluate(data, state, proposal)
	if not verdict["accept"]:
		return false
	var result := DiplomacyRules.propose(data, state, proposal)
	if result["accepted"]:
		notices.append({"kind": "treaty", "from": faction_id, "to": other,
			"stance": proposal.get("stance", ""), "gift": int(proposal.get("gift", 0))})
	return result["accepted"]
