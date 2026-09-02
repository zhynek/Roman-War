class_name DiplomacyRules
## Stances, war, and the Phase 5 negotiation layer: a named-factor attitude
## model (rendered by the UI like the growth/order breakdowns), remembered
## grievances and favors that decay over time, offers priced in denarii
## (payments, recurring tribute, region cessions, stance changes), and the
## peaceful transfer of settlements. Everything here is deterministic — no rng;
## every weight lives in balance.json → diplomacy, except the difficulty bias
## toward the player, which sits with its sibling difficulty tables in → ai.
##
## An offer dict is written from the PROPOSER's side:
##   {from, to, stance, give_payment, give_tribute: {amount, turns}|null,
##    give_regions: [], ask_payment, ask_tribute: {...}|null, ask_regions: []}
## "stance" is the proposed new mutual stance ("" = no change, payments only).


static func stance_between(state: Dictionary, a: String, b: String) -> String:
	if a == b:
		return "self"
	return state["factions"][a]["diplomacy"].get(b, "neutral")


static func at_war(state: Dictionary, a: String, b: String) -> bool:
	return a != b and stance_between(state, a, b) == "war"


static func roman_internal(data: GameData, a: String, b: String) -> bool:
	## Two Roman parties — houses or the Senate. Their quarrels stay in the
	## forum until a civil war breaks, and once it has they are settled by the
	## sword alone. Both rules lapse with the Republic: once the Senate has
	## fallen the houses are powers like any other.
	var faction_a: Dictionary = data.factions.get(a, {})
	var faction_b: Dictionary = data.factions.get(b, {})
	return (faction_a.get("is_roman_house", false) or faction_a.get("is_senate", false)) \
		and (faction_b.get("is_roman_house", false) or faction_b.get("is_senate", false))


static func roman_war_forbidden(data: GameData, state: Dictionary, a: String, b: String) -> bool:
	## No Roman party may make war on another while the Senate stands, until
	## one of them has broken with the Republic.
	if not roman_internal(data, a, b) or not _senate_stands(data, state):
		return false
	return not (bool(state["factions"][a].get("at_civil_war", false))
		or bool(state["factions"][b].get("at_civil_war", false)))


static func roman_peace_forbidden(data: GameData, state: Dictionary, a: String, b: String) -> bool:
	## A civil war is never talked away: no envoy, no silver, no quiet
	## guttering out. It ends when the Senate falls, or the rebels do.
	if not roman_internal(data, a, b) or not _senate_stands(data, state):
		return false
	return bool(state["factions"][a].get("at_civil_war", false)) \
		or bool(state["factions"][b].get("at_civil_war", false))


static func _senate_stands(data: GameData, state: Dictionary) -> bool:
	for faction_id in state["factions"]:  # pure any() — order-free
		if data.factions.get(faction_id, {}).get("is_senate", false) \
				and state["factions"][faction_id]["alive"]:
			return true
	return false


static func set_stance(state: Dictionary, a: String, b: String, stance: String) -> bool:
	if a == b or not Constants.STANCES.has(stance):
		return false
	if not state["factions"].has(a) or not state["factions"].has(b):
		return false
	state["factions"][a]["diplomacy"][b] = stance
	state["factions"][b]["diplomacy"][a] = stance
	return true


static func declare_war(data: GameData, state: Dictionary, a: String, b: String) -> bool:
	## Any hostile act routes through here, so a betrayed alliance simply ends —
	## and is remembered. The declared-upon side carries the grudge; a broken
	## alliance cuts deeper than an honest enemy's trumpets.
	if a == b or not state["factions"].has(a) or not state["factions"].has(b):
		return false
	if roman_war_forbidden(data, state, a, b):
		return false  # Roman quarrels stay in the forum until a civil war breaks
	var rules: Dictionary = data.balance["diplomacy"]
	var previous := stance_between(state, a, b)
	if previous != "war":
		record_memory(data, state, b, a, float(rules["war_declared_memory"]))
		if previous == "alliance" or previous == "protectorate":
			record_memory(data, state, b, a, float(rules["betrayal_memory"]))
	return set_stance(state, a, b, "war")


## --- Attitude --------------------------------------------------------------

static func attitude_breakdown(data: GameData, state: Dictionary, a: String, b: String, strengths: Dictionary = {}) -> Array:
	## How faction a feels about faction b, as named factors. Pure and rng-free.
	## `strengths` is an optional per-turn cache from
	## AiStrategy.all_faction_strengths — the AI passes it so a whole turn of
	## pairwise attitudes costs one world pass instead of hundreds.
	var rules: Dictionary = data.balance["diplomacy"]
	var factors: Array = []

	var stance := stance_between(state, a, b)
	factors.append({"label": "stance", "value": float(rules["stance_attitude"].get(stance, 0.0))})

	if data.culture_of_faction(a) == data.culture_of_faction(b):
		factors.append({"label": "same_culture", "value": float(rules["same_culture_bonus"])})

	if share_border(data, state, a, b):
		factors.append({"label": "shared_border", "value": float(rules["shared_border_penalty"])})

	var own_strength: float = strengths[a] if strengths.has(a) \
		else AiStrategy.faction_total_strength(data, state, a)
	var their_strength: float = strengths[b] if strengths.has(b) \
		else AiStrategy.faction_total_strength(data, state, b)
	if their_strength > own_strength:
		var fear := minf((their_strength / maxf(own_strength, 1.0) - 1.0)
			* float(rules["strength_fear_scale"]), float(rules["strength_fear_max"]))
		factors.append({"label": "their_strength", "value": -fear})
	elif own_strength > their_strength:
		# Predators circle: a clearly weaker neighbor tempts, and the temptation
		# shows in the ledger the weaker side can read.
		var temptation := minf((own_strength / maxf(their_strength, 1.0) - 1.0)
			* float(rules["weakness_temptation_scale"]), float(rules["weakness_temptation_max"]))
		if temptation > 0.0:
			factors.append({"label": "their_weakness", "value": -temptation})

	var aggression := float(AiRules.persona_for(data, a).get("aggression", 1.0))
	if aggression > 1.0:
		factors.append({"label": "ambition",
			"value": -(aggression - 1.0) * float(rules["ambition_attitude_scale"])})

	var memory := float(state["factions"][a].get("attitude_memory", {}).get(b, 0.0))
	if memory != 0.0:
		factors.append({"label": "memory", "value": memory})

	if data.factions.get(a, {}).get("is_roman_house", false) \
			and data.factions.get(b, {}).get("is_roman_house", false):
		var drift: float = absf(float(state["factions"][a]["senate_standing"])
			- float(state["factions"][b]["senate_standing"])) * float(rules["senate_alignment_scale"])
		if drift != 0.0:
			factors.append({"label": "senate_rivalry", "value": -drift})

	if b == state.get("player_faction", "") and a != b:
		var bias := float(data.balance["ai"]["difficulty_player_attitude"].get(
			state.get("difficulty", "medium"), 0.0))
		if bias != 0.0:
			factors.append({"label": "difficulty", "value": bias})

	return factors


static func attitude_total(data: GameData, state: Dictionary, a: String, b: String, strengths: Dictionary = {}) -> float:
	var total := 0.0
	for factor in attitude_breakdown(data, state, a, b, strengths):
		total += factor["value"]
	return total


static func record_memory(data: GameData, state: Dictionary, a: String, b: String, amount: float) -> void:
	## a will remember this about b. Clamped so no single history dominates forever.
	var rules: Dictionary = data.balance["diplomacy"]
	var memories: Dictionary = state["factions"][a].get("attitude_memory", {})
	state["factions"][a]["attitude_memory"] = memories
	var value: float = clampf(float(memories.get(b, 0.0)) + amount,
		float(rules["memory_min"]), float(rules["memory_max"]))
	if value == 0.0:
		memories.erase(b)
	else:
		memories[b] = value


static func decay_memories(data: GameData, state: Dictionary) -> void:
	var decay := float(data.balance["diplomacy"]["memory_decay_per_turn"])
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var memories: Dictionary = state["factions"][faction_id].get("attitude_memory", {})
		var others: Array = memories.keys()
		others.sort()
		for other in others:
			var value := float(memories[other])
			value = maxf(value - decay, 0.0) if value > 0.0 else minf(value + decay, 0.0)
			if value == 0.0:
				memories.erase(other)
			else:
				memories[other] = value


## --- Offers ----------------------------------------------------------------

static func evaluate_offer(data: GameData, state: Dictionary, from_id: String, to_id: String, offer: Dictionary, strengths: Dictionary = {}) -> Dictionary:
	## Price the offer in denarii from the RECEIVER's chair. Returns
	## {accept, score, breakdown, vetoes} — the breakdown feeds the negotiation
	## UI's live hint, factor-list style; vetoes are the named hard floors no
	## price overrides, shown so a refusal is never a mystery.
	var rules: Dictionary = data.balance["diplomacy"]
	var factors: Array = []
	var vetoes: Array = []

	if data.factions.get(from_id, {}).get("is_rebel", false) \
			or data.factions.get(to_id, {}).get("is_rebel", false):
		# There is no treating with brigands — from either chair. Without this,
		# silver could buy a permanent peace no rebel would ever break.
		return {"accept": false, "score": 0.0, "breakdown": [],
			"vetoes": ["no_treating_with_brigands"]}
	var proposed_stance: String = offer.get("stance", "")
	if proposed_stance != "" and proposed_stance != "war" \
			and roman_peace_forbidden(data, state, from_id, to_id):
		# A civil war is settled by the sword, not the envoy.
		return {"accept": false, "score": 0.0, "breakdown": [],
			"vetoes": ["the_republic_is_at_war_with_itself"]}

	var give_payment := int(offer.get("give_payment", 0))
	if give_payment > 0:
		factors.append({"label": "their_payment", "value": float(give_payment)})
	var ask_payment := int(offer.get("ask_payment", 0))
	if ask_payment > 0:
		factors.append({"label": "our_payment", "value": -float(ask_payment)})

	var give_tribute = offer.get("give_tribute")
	if give_tribute != null and int(give_tribute.get("amount", 0)) > 0:
		factors.append({"label": "their_tribute", "value": _tribute_value(data, give_tribute)})
	var ask_tribute = offer.get("ask_tribute")
	if ask_tribute != null and int(ask_tribute.get("amount", 0)) > 0:
		factors.append({"label": "our_tribute", "value": -_tribute_value(data, ask_tribute)})

	for region_id in offer.get("give_regions", []):
		# Only land the proposer actually holds is worth anything — no gifting
		# a third party's region, no "ceding" what the receiver already owns.
		if state["settlements"].get(region_id, {}).get("owner", "") != from_id:
			vetoes.append("not_theirs_to_give")
			continue
		factors.append({"label": "ceded_to_us", "value": region_value(data, state, region_id)})
	for region_id in offer.get("ask_regions", []):
		factors.append({"label": "ceded_by_us", "value": -region_value(data, state, region_id)})

	var stance: String = offer.get("stance", "")
	var stance_value := _stance_change_value(data, state, to_id, from_id, stance, strengths)
	if stance_value != 0.0:
		factors.append({"label": "new_stance", "value": stance_value})

	var attitude := attitude_total(data, state, to_id, from_id, strengths)
	if attitude != 0.0:
		factors.append({"label": "attitude", "value": attitude * float(rules["attitude_value_per_point"])})

	var envoy := AgentRules.envoy_bonus(data, state, from_id, to_id)
	if envoy > 0.0:
		factors.append({"label": "envoy", "value": envoy})

	var score := 0.0
	for factor in factors:
		score += factor["value"]

	vetoes.append_array(_bearability_vetoes(state, to_id, offer))
	if give_payment > int(state["factions"][from_id]["treasury"]):
		vetoes.append("their_purse_cannot_cover_it")  # nobody banks an empty promise
	var accept := score >= float(rules["accept_threshold"]) and vetoes.is_empty()
	return {"accept": accept, "score": score, "breakdown": factors, "vetoes": vetoes}


static func offer_still_stands(data: GameData, state: Dictionary, offer: Dictionary) -> bool:
	## A pending offer is a promise, and promises age: the proposer must still
	## be alive, still able to pay, still hold every region offered — and an
	## offer of friendship does not survive a war begun since it was made.
	var from_id: String = offer.get("from", "")
	var to_id: String = offer.get("to", "")
	if not state["factions"].get(from_id, {}).get("alive", false):
		return false
	if not state["factions"].get(to_id, {}).get("alive", false):
		return false
	if int(offer.get("give_payment", 0)) > int(state["factions"][from_id]["treasury"]):
		return false
	for region_id in offer.get("give_regions", []):
		if state["settlements"].get(region_id, {}).get("owner", "") != from_id:
			return false
	var stance: String = offer.get("stance", "")
	if stance != "" and stance != "neutral" and at_war(state, from_id, to_id):
		return false
	if stance != "" and stance != "war" and roman_peace_forbidden(data, state, from_id, to_id):
		return false  # an envoy sent before the break is recalled by it
	return true


static func apply_offer(data: GameData, state: Dictionary, offer: Dictionary) -> void:
	## Execute an accepted offer: money moves, tribute schedules start, regions
	## change hands, the stance is set, and both sides remember the generosity.
	var rules: Dictionary = data.balance["diplomacy"]
	var from_id: String = offer["from"]
	var to_id: String = offer["to"]

	var give_payment := int(offer.get("give_payment", 0))
	if give_payment > 0:
		state["factions"][from_id]["treasury"] = int(state["factions"][from_id]["treasury"]) - give_payment
		state["factions"][to_id]["treasury"] = int(state["factions"][to_id]["treasury"]) + give_payment
		record_memory(data, state, to_id, from_id,
			give_payment / 1000.0 * float(rules["gift_memory_per_1000"]))
	var ask_payment := int(offer.get("ask_payment", 0))
	if ask_payment > 0:
		state["factions"][to_id]["treasury"] = int(state["factions"][to_id]["treasury"]) - ask_payment
		state["factions"][from_id]["treasury"] = int(state["factions"][from_id]["treasury"]) + ask_payment
		record_memory(data, state, from_id, to_id,
			ask_payment / 1000.0 * float(rules["gift_memory_per_1000"]))

	var give_tribute = offer.get("give_tribute")
	if give_tribute != null and int(give_tribute.get("amount", 0)) > 0:
		state["tributes"].append({"from": from_id, "to": to_id,
			"amount": int(give_tribute["amount"]), "turns_left": int(give_tribute["turns"])})
	var ask_tribute = offer.get("ask_tribute")
	if ask_tribute != null and int(ask_tribute.get("amount", 0)) > 0:
		state["tributes"].append({"from": to_id, "to": from_id,
			"amount": int(ask_tribute["amount"]), "turns_left": int(ask_tribute["turns"])})

	for region_id in offer.get("give_regions", []):
		# Ownership re-checked at the moment of transfer: only the proposer's
		# own land moves — never a third party's, never the receiver's own.
		if state["settlements"].get(region_id, {}).get("owner", "") == from_id:
			cede_region(data, state, region_id, to_id)
	for region_id in offer.get("ask_regions", []):
		if state["settlements"].get(region_id, {}).get("owner", "") == to_id:
			cede_region(data, state, region_id, from_id)

	var stance: String = offer.get("stance", "")
	if stance != "" and Constants.STANCES.has(stance) \
			and not (stance != "war" and roman_peace_forbidden(data, state, from_id, to_id)):
		var ends_a_war := at_war(state, from_id, to_id) and stance != "war"
		set_stance(state, from_id, to_id, stance)
		if ends_a_war:
			# A concluded peace is a truce, not a mood: both courts bank enough
			# goodwill that the war cannot simply be re-declared next season.
			# It decays like any memory, so old wars can rekindle — later.
			record_memory(data, state, from_id, to_id, float(rules["peace_concluded_memory"]))
			record_memory(data, state, to_id, from_id, float(rules["peace_concluded_memory"]))
		if stance == "alliance":
			record_memory(data, state, from_id, to_id, float(rules["alliance_formed_memory"]))
			record_memory(data, state, to_id, from_id, float(rules["alliance_formed_memory"]))
			# Every alliance is signed here (AI and player offers alike), so
			# the chronicle records it at the signing, not by diffing.
			ChronicleRules.record(data, state, "alliance_made",
				{"faction": from_id, "other_faction": to_id}, 4)


static func region_value(data: GameData, state: Dictionary, region_id: String) -> float:
	var rules: Dictionary = data.balance["diplomacy"]
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty():
		return 0.0
	return float(rules["region_value_base"]) \
		+ float(settlement["population"]) / 1000.0 * float(rules["region_value_per_1000_pop"])


static func cede_region(data: GameData, state: Dictionary, region_id: String, new_owner: String) -> void:
	## A peaceful handover: no loot, no burning. The garrison marches home to
	## the old owner's nearest settlement (or disbands with nowhere to go), the
	## old owner's family flee ahead of the new administration, and the new
	## subjects still need a little convincing.
	var settlement: Dictionary = state["settlements"][region_id]
	var previous_owner: String = settlement["owner"]
	if previous_owner == new_owner or not state["factions"].has(new_owner):
		return

	var refuge := _nearest_owned_settlement(data, state, region_id, previous_owner)
	if refuge != "":
		for unit in settlement["garrison"]:
			state["settlements"][refuge]["garrison"].append(unit)
	settlement["garrison"] = []
	settlement["construction_queue"] = []
	settlement["recruitment_queue"] = []
	settlement["governor"] = null
	settlement["siege"] = null
	settlement["low_order_streak"] = 0
	settlement["tax_level"] = "normal"
	settlement["owner"] = new_owner
	var decay := int(data.balance["public_order"]["recently_conquered_decay_per_turn"])
	settlement["recently_conquered"] = int(ceil(
		float(data.balance["diplomacy"]["cede_order_penalty"]) / float(maxi(decay, 1))))

	CombatRules.displace_characters(data, state, region_id, previous_owner)
	CombatRules.check_faction_destroyed(state)
	SettlementRules.refresh_governors(data, state)


static func process_turn(data: GameData, state: Dictionary) -> Array:
	## TurnEngine step 1.5: tribute changes hands, grudges fade, stale offers
	## lapse. Returns report events. Deterministic — arrays keep their order
	## through a save, and the faction loop is sorted.
	var rules: Dictionary = data.balance["diplomacy"]
	var events: Array = []
	var remaining: Array = []
	for tribute in state["tributes"]:
		var payer: Dictionary = state["factions"][tribute["from"]]
		var receiver: Dictionary = state["factions"][tribute["to"]]
		if not payer["alive"] or not receiver["alive"]:
			continue
		if int(payer["treasury"]) < int(tribute["amount"]):
			# An empty purse cannot mint denarii: the schedule collapses, and
			# the stiffed side remembers the default.
			events.append({"kind": "tribute_defaulted", "from": tribute["from"],
				"to": tribute["to"], "amount": int(tribute["amount"])})
			record_memory(data, state, tribute["to"], tribute["from"],
				float(rules["tribute_default_memory"]))
			continue
		payer["treasury"] = int(payer["treasury"]) - int(tribute["amount"])
		receiver["treasury"] = int(receiver["treasury"]) + int(tribute["amount"])
		events.append({"kind": "tribute_paid", "from": tribute["from"],
			"to": tribute["to"], "amount": int(tribute["amount"])})
		tribute["turns_left"] = int(tribute["turns_left"]) - 1
		if int(tribute["turns_left"]) > 0:
			remaining.append(tribute)
	state["tributes"] = remaining

	decay_memories(data, state)

	var open_offers: Array = []
	for offer in state["pending_offers"]:
		if int(offer.get("expires_turn", 0)) > int(state["turn"]) \
				and offer_still_stands(data, state, offer):
			open_offers.append(offer)
		elif offer.get("to", "") == state.get("player_faction", ""):
			events.append({"kind": "offer_expired", "from": offer["from"]})
	state["pending_offers"] = open_offers
	return events


## --- Internals -------------------------------------------------------------

static func share_border(data: GameData, state: Dictionary, a: String, b: String) -> bool:
	for region_id in state["settlements"]:
		if state["settlements"][region_id]["owner"] != a:
			continue
		for neighbor in data.regions[region_id].get("adjacent", []):
			if state["settlements"].has(neighbor) and state["settlements"][neighbor]["owner"] == b:
				return true
	return false


static func _tribute_value(data: GameData, tribute: Dictionary) -> float:
	return float(tribute["amount"]) * float(tribute["turns"]) \
		* float(data.balance["diplomacy"]["tribute_value_factor"])


static func _stance_change_value(data: GameData, state: Dictionary, evaluator: String, other: String, new_stance: String, strengths: Dictionary = {}) -> float:
	if new_stance == "" or not Constants.STANCES.has(new_stance):
		return 0.0
	var rules: Dictionary = data.balance["diplomacy"]
	var current := stance_between(state, evaluator, other)
	if new_stance == current:
		return 0.0
	var value := 0.0
	if current == "war":
		value += _peace_value(data, state, evaluator, other, strengths)
	match new_stance:
		"trade":
			value += float(rules["trade_stance_value"])
		"alliance", "protectorate":
			value += float(rules["alliance_stance_value"])
			var attitude := attitude_total(data, state, evaluator, other, strengths)
			var shortfall := float(rules["alliance_min_attitude"]) - attitude
			if shortfall > 0.0:
				# Nobody swears an oath to a stranger they distrust.
				value -= shortfall * float(rules["attitude_value_per_point"])
	return value


static func _peace_value(data: GameData, state: Dictionary, evaluator: String, other: String, strengths: Dictionary = {}) -> float:
	## What ending the war is worth to the evaluator: the losing side pays for
	## peace, the winning side must be paid to stop.
	var rules: Dictionary = data.balance["diplomacy"]
	var own: float = strengths[evaluator] if strengths.has(evaluator) \
		else AiStrategy.faction_total_strength(data, state, evaluator)
	var theirs: float = strengths[other] if strengths.has(other) \
		else AiStrategy.faction_total_strength(data, state, other)
	var ratio := theirs / maxf(own, 1.0)
	return minf(float(rules["peace_base_value"]) + (ratio - 1.0) * float(rules["peace_strength_scale"]),
		float(rules["peace_value_max"]))


static func _bearability_vetoes(state: Dictionary, evaluator: String, offer: Dictionary) -> Array:
	## Hard floors no price overrides, as named labels for the appraisal UI:
	## never cede the capital, never cede the last settlement, never promise
	## money that cannot exist.
	var vetoes: Array = []
	if int(offer.get("ask_payment", 0)) > int(state["factions"][evaluator]["treasury"]):
		vetoes.append("beyond_our_purse")
	var asked: Array = offer.get("ask_regions", [])
	if asked.is_empty():
		return vetoes
	var owned := 0
	for settlement in state["settlements"].values():
		if settlement["owner"] == evaluator:
			owned += 1
	if asked.size() >= owned:
		vetoes.append("never_the_last_home")
	var capital: String = state["factions"][evaluator]["capital"]
	for region_id in asked:
		if region_id == capital:
			vetoes.append("never_the_capital")
		elif not state["settlements"].has(region_id) \
				or state["settlements"][region_id]["owner"] != evaluator:
			vetoes.append("not_ours_to_cede")
	return vetoes


static func _nearest_owned_settlement(data: GameData, state: Dictionary, from_region: String, faction_id: String) -> String:
	var hops := MapRules.hops_from(data, from_region)
	var best := ""
	var best_hops := 1 << 30
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if region_id == from_region or state["settlements"][region_id]["owner"] != faction_id:
			continue
		var distance := int(hops.get(region_id, 1 << 29))
		if distance < best_hops:
			best_hops = distance
			best = region_id
	return best
