class_name DiplomacyRules
## Diplomacy (Phase 5): symmetric stances remain the single source of truth
## for who trades and who fights; this module adds what bolts on to them —
## an opinion memory per faction pair, an attitude model, offer evaluation as
## a named factor list, tribute streams, protectorates, and peaceful region
## transfers.
##
## A proposal is a plain dictionary (JSON-friendly, so a scroll, an AI or a
## test can build one the same way):
##   {from, to,
##    stance: "" | "neutral" | "trade" | "alliance" | "protectorate",
##    gift: int, demand: int,                                # one-off gold
##    tribute_per_turn: int, tribute_turns: int,             # proposer pays
##    tribute_demanded_per_turn: int, tribute_demanded_turns: int,
##    regions_offered: [region_id], regions_demanded: [region_id],
##    envoy: agent_id | ""}
## evaluate() never rolls dice: the balance of an offer is a sum the scroll
## can show, and the other side accepts exactly when it is not negative.
## Gold offered and demanded are netted into one figure; region lists are
## deduplicated; a stance below the current one is a dissolution (free of
## consent when nothing is demanded, resented, never a lesson for the envoy);
## a named envoy must be the proposer's, in contact, and free to speak.
## Weights live in balance.json → diplomacy.

const STANCE_RANK := {"war": 0, "neutral": 1, "trade": 2, "alliance": 3, "protectorate": 4}


## --- Stances ------------------------------------------------------------------

static func stance_between(state: Dictionary, a: String, b: String) -> String:
	if a == b:
		return "self"
	return state["factions"][a]["diplomacy"].get(b, "neutral")


static func at_war(state: Dictionary, a: String, b: String) -> bool:
	return a != b and stance_between(state, a, b) == "war"


static func set_stance(state: Dictionary, a: String, b: String, stance: String) -> bool:
	## Raw symmetric stance change. Leaving a protectorate frees the vassal.
	if a == b or not Constants.STANCES.has(stance):
		return false
	if not state["factions"].has(a) or not state["factions"].has(b):
		return false
	state["factions"][a]["diplomacy"][b] = stance
	state["factions"][b]["diplomacy"][a] = stance
	if stance != "protectorate":
		for pair in [[a, b], [b, a]]:
			var faction: Dictionary = state["factions"][pair[0]]
			if faction.get("overlord", null) == pair[1]:
				faction["overlord"] = null
	return true


static func declare_war(state: Dictionary, a: String, b: String, data: GameData = null) -> bool:
	## Any hostile act routes through here, so a betrayed alliance simply
	## ends. Pass `data` to have the victim remember it: a declaration costs
	## opinion, and tearing up a treaty marks the aggressor as treacherous in
	## everyone's eyes.
	if a == b or not state["factions"].has(a) or not state["factions"].has(b):
		return false
	var previous := stance_between(state, a, b)
	if previous == "war":
		return true
	set_stance(state, a, b, "war")
	_set_war_turns(state, a, b, 0)
	if data != null:
		var rules: Dictionary = data.balance["diplomacy"]
		adjust_opinion(data, state, b, a, -float(rules["war_declaration_opinion_penalty"]))
		# Tearing up a treaty, or walking away from a tribute still owed, is
		# betrayal: the victim resents it and every court hears of it.
		if previous in ["trade", "alliance", "protectorate"] or _owes_tribute(state, a, b):
			adjust_opinion(data, state, b, a, -float(rules["betrayal_opinion_penalty"]))
			var aggressor: Dictionary = state["factions"][a]
			aggressor["treachery"] = int(aggressor.get("treachery", 0)) + int(rules["treachery_per_betrayal"])
	return true


## --- Opinion memory ---------------------------------------------------------

static func opinion(state: Dictionary, a: String, b: String) -> float:
	## How `a` feels about `b` (−100…100, drifting back toward 0 each turn).
	return float(state["factions"][a].get("opinion", {}).get(b, 0.0))


static func adjust_opinion(data: GameData, state: Dictionary, a: String, b: String, delta: float) -> void:
	if a == b or delta == 0.0 or not state["factions"].has(a) or not state["factions"].has(b):
		return
	if data.factions.get(a, {}).get("is_rebel", false) or data.factions.get(b, {}).get("is_rebel", false):
		return
	var rules: Dictionary = data.balance["diplomacy"]
	var opinions := _opinions(state["factions"][a])
	opinions[b] = clampf(float(opinions.get(b, 0.0)) + delta,
		float(rules["opinion_min"]), float(rules["opinion_max"]))


static func war_turns(state: Dictionary, a: String, b: String) -> int:
	return int(state["factions"][a].get("war_turns", {}).get(b, 0))


## --- Power and geography -------------------------------------------------------

static func strength(data: GameData, state: Dictionary, faction_id: String) -> float:
	## Quality-weighted fighting strength of everything under arms: field
	## armies and garrisons (no generals — this is the muster, not a battle).
	var experience_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	var total := 0.0
	for army in state["armies"].values():
		if army["owner"] == faction_id:
			total += BattleResolver.force_strength(data, army["units"], null, experience_pct)
	for settlement in state["settlements"].values():
		if settlement["owner"] == faction_id:
			total += BattleResolver.force_strength(data, settlement["garrison"], null, experience_pct)
	return total


static func power_ratio(data: GameData, state: Dictionary, a: String, b: String) -> float:
	## a's strength over b's; at least a token strength on each side.
	return maxf(strength(data, state, a), 1.0) / maxf(strength(data, state, b), 1.0)


static func shared_enemies(data: GameData, state: Dictionary, a: String, b: String) -> Array:
	var result: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other in faction_ids:
		if other == a or other == b or not state["factions"][other]["alive"]:
			continue
		if data.factions.get(other, {}).get("is_rebel", false):
			continue
		if at_war(state, a, other) and at_war(state, b, other):
			result.append(other)
	return result


static func border_count(data: GameData, state: Dictionary, a: String, b: String) -> int:
	## Regions of `a` touching a region of `b`.
	var count := 0
	for region_id in state["settlements"]:
		if state["settlements"][region_id]["owner"] != a:
			continue
		for neighbor in data.regions.get(region_id, {}).get("adjacent", []):
			if state["settlements"].get(neighbor, {}).get("owner", "") == b:
				count += 1
				break
	return count


static func region_value(data: GameData, state: Dictionary, region_id: String) -> float:
	var rules: Dictionary = data.balance["diplomacy"]
	var settlement: Dictionary = state["settlements"][region_id]
	return float(settlement["population"]) / 1000.0 * float(rules["region_value_per_1000_pop"]) \
		+ float(settlement["buildings"].size()) * float(rules["region_value_per_building"])


## --- Attitude ------------------------------------------------------------------

static func attitude_breakdown(data: GameData, state: Dictionary, evaluator: String, other: String) -> Array:
	## How `evaluator` regards `other`, as named factors: the standing
	## relationship, remembered dealings, common enemies, kinship of culture,
	## the friction of a shared border, and the other's record of treachery.
	var rules: Dictionary = data.balance["diplomacy"]
	var factors: Array = []
	var stance := stance_between(state, evaluator, other)
	factors.append({"label": "stance", "value": float(rules["attitude_stance"].get(stance, 0.0))})
	var remembered := opinion(state, evaluator, other) * float(rules["attitude_opinion_weight"])
	if remembered != 0.0:
		factors.append({"label": "past_dealings", "value": remembered})
	var enemies := shared_enemies(data, state, evaluator, other).size()
	if enemies > 0:
		factors.append({"label": "common_enemies", "value": minf(
			float(enemies) * float(rules["attitude_shared_enemy"]), float(rules["attitude_shared_enemy_cap"]))})
	if data.culture_of_faction(evaluator) == data.culture_of_faction(other):
		factors.append({"label": "shared_culture", "value": float(rules["attitude_same_culture"])})
	var borders := border_count(data, state, evaluator, other)
	if borders > 0:
		factors.append({"label": "shared_borders", "value": maxf(
			float(borders) * float(rules["attitude_per_border"]), float(rules["attitude_border_cap"]))})
	var treachery := int(state["factions"][other].get("treachery", 0))
	if treachery > 0:
		factors.append({"label": "treachery", "value": float(treachery) * float(rules["attitude_treachery_weight"])})
	return factors


static func attitude(data: GameData, state: Dictionary, evaluator: String, other: String) -> float:
	var total := 0.0
	for factor in attitude_breakdown(data, state, evaluator, other):
		total += float(factor["value"])
	return total


static func attitude_label(data: GameData, value: float) -> String:
	## The word for a number: balance.json lists labels with the attitude each
	## one holds up to, so "hostile" applies below the lowest threshold and the
	## last label catches everything above.
	var labels: Dictionary = data.balance["diplomacy"]["attitude_labels"]
	var entries: Array = []
	for label in labels:
		entries.append([float(labels[label]), String(label)])
	entries.sort()
	for entry in entries:
		if value < float(entry[0]):
			return String(entry[1])
	return String(entries[-1][1]) if not entries.is_empty() else ""


## --- Offers ----------------------------------------------------------------------

static func evaluate(data: GameData, state: Dictionary, proposal: Dictionary) -> Dictionary:
	## {accept, score, factors: [{label, value}], reason}. `reason` is set only
	## for offers refused outright, whatever the sum: nobody sells a capital,
	## nobody trades while at war, the independents keep no court.
	var from: String = proposal.get("from", "")
	var to: String = proposal.get("to", "")
	var rules: Dictionary = data.balance["diplomacy"]
	if from == to or not state["factions"].has(from) or not state["factions"].has(to):
		return _refusal("There is no such power to treat with.")
	if not state["factions"][from]["alive"] or not state["factions"][to]["alive"]:
		return _refusal("That house is no more.")
	if data.factions.get(to, {}).get("is_rebel", false) or data.factions.get(from, {}).get("is_rebel", false):
		return _refusal("The independents keep no court to treat with.")

	var current := stance_between(state, from, to)
	var stance: String = proposal.get("stance", "")
	if stance == current:
		stance = ""
	if stance == "war":
		return _refusal("War is declared, not proposed.")
	if stance in ["trade", "alliance"] and current == "war":
		return _refusal("There can be no treaty while we are at war. Make peace first.")
	var power := power_ratio(data, state, from, to)
	if stance == "protectorate" and power <= 1.0:
		return _refusal("No court submits to a weaker one.")
	# A stance below the standing one is a dissolution, not a fresh treaty.
	var dissolving: bool = stance != "" and current != "war" \
		and int(STANCE_RANK.get(stance, 0)) < int(STANCE_RANK.get(current, 0))
	if dissolving and current == "protectorate" and state["factions"][from].get("overlord", null) == to:
		return _refusal("A protectorate is released by its overlord, not by itself.")

	# Gold each way is one figure: a gift wrapped around a demand is neither.
	var net_gold := maxi(0, int(proposal.get("gift", 0))) - maxi(0, int(proposal.get("demand", 0)))
	var gift := maxi(0, net_gold)
	var demand := maxi(0, -net_gold)
	if gift > int(state["factions"][from]["treasury"]):
		return _refusal("We cannot pay what we offer.")
	if demand > int(state["factions"][to]["treasury"]):
		return _refusal("They cannot pay what is asked.")
	var tribute_per_turn := maxi(0, int(proposal.get("tribute_per_turn", 0)))
	var tribute_turns := maxi(0, int(proposal.get("tribute_turns", 0)))
	var demanded_per_turn := maxi(0, int(proposal.get("tribute_demanded_per_turn", 0)))
	var demanded_turns := maxi(0, int(proposal.get("tribute_demanded_turns", 0)))
	if (tribute_per_turn > 0 and tribute_turns <= 0) or (demanded_per_turn > 0 and demanded_turns <= 0):
		return _refusal("A tribute needs a term of seasons.")
	if tribute_per_turn * tribute_turns + gift > int(state["factions"][from]["treasury"]):
		return _refusal("We cannot promise more than we hold.")
	if demanded_per_turn + demand > int(state["factions"][to]["treasury"]):
		return _refusal("They cannot pay what is asked.")

	var offered := _unique(proposal.get("regions_offered", []))
	var demanded := _unique(proposal.get("regions_demanded", []))
	if (not offered.is_empty() or not demanded.is_empty()) and current == "war" \
			and stance not in ["neutral", "protectorate"]:
		return _refusal("No land changes hands while we are at war, unless this treaty ends it.")
	for region_id in offered:
		if state["settlements"].get(region_id, {}).get("owner", "") != from \
				or state["factions"][from]["capital"] == region_id:
			return _refusal("We cannot give away what is not ours to give.")
	if not offered.is_empty() and _regions_of(state, from).size() <= offered.size():
		return _refusal("A house that gives away its last city is no house at all.")
	var evaluator_regions := _regions_of(state, to)
	for region_id in demanded:
		if state["settlements"].get(region_id, {}).get("owner", "") != to:
			return _refusal("They do not hold that land.")
		if state["factions"][to]["capital"] == region_id or evaluator_regions.size() <= demanded.size():
			return _refusal("No power surrenders its capital or its last city at the table.")

	var envoy_id: String = proposal.get("envoy", "")
	var envoy: Dictionary = state["agents"].get(envoy_id, {})
	if envoy_id != "" and (envoy.is_empty() or envoy["owner"] != from
			or not AgentRules.in_contact(data, state, envoy_id, to) or not AgentRules.can_act(envoy)):
		return _refusal("That envoy cannot speak for us at that court this season.")

	var factors: Array = []
	# Dissolving a treaty of ours is not a bargain the other side gets to
	# refuse — unless we try to squeeze them on the way out.
	var demanding: bool = demand > 0 or demanded_per_turn > 0 or not demanded.is_empty()
	if dissolving and not demanding:
		factors.append({"label": "treaty_dissolved", "value": 0.0})
		return {"accept": true, "score": 0.0, "factors": factors, "reason": ""}

	factors.append({"label": "attitude", "value": attitude(data, state, to, from)})
	var weariness := minf(float(war_turns(state, to, from)) * float(rules["war_weariness_per_turn"]),
		float(rules["war_weariness_cap"]))
	if dissolving:
		factors.append({"label": "treaty_dissolved", "value": 0.0})
	else:
		match stance:
			"neutral":
				factors.append({"label": "peace", "value": float(rules["peace_base"])})
				if weariness > 0.0:
					factors.append({"label": "war_weariness", "value": weariness})
				factors.append({"label": "relative_power", "value": clampf(
					(power - 1.0) * float(rules["peace_power_weight"]),
					-float(rules["peace_power_cap"]), float(rules["peace_power_cap"]))})
			"trade":
				factors.append({"label": "trade_rights", "value": float(rules["trade_base"])})
			"alliance":
				factors.append({"label": "alliance", "value": float(rules["alliance_base"])})
				var enemies := shared_enemies(data, state, from, to).size()
				if enemies > 0:
					factors.append({"label": "common_enemies",
						"value": float(enemies) * float(rules["alliance_per_shared_enemy"])})
				factors.append({"label": "relative_power", "value": clampf(
					(power - 1.0) * float(rules["alliance_power_weight"]),
					-float(rules["alliance_power_cap"]), float(rules["alliance_power_cap"]))})
				var allies_fought := _allies_at_war_with(state, to, from)
				if allies_fought > 0:
					factors.append({"label": "war_with_our_allies",
						"value": -float(allies_fought) * float(rules["alliance_enemy_of_ally_penalty"])})
			"protectorate":
				factors.append({"label": "submission", "value": float(rules["protectorate_base"])})
				factors.append({"label": "our_weakness", "value": minf(
					(power - 1.0) * float(rules["protectorate_weakness_weight"]),
					float(rules["protectorate_weakness_cap"]))})
				if current == "war" and weariness > 0.0:
					factors.append({"label": "war_weariness", "value": weariness})

	var gold_per_point := float(rules["offer_gold_per_point"])
	if gift > 0:
		factors.append({"label": "gift", "value": float(gift) / gold_per_point})
	if demand > 0:
		factors.append({"label": "gold_demanded",
			"value": -float(demand) / gold_per_point * float(rules["demand_multiplier"])})
	var tribute := tribute_per_turn * tribute_turns
	if tribute > 0:
		factors.append({"label": "tribute_offered",
			"value": float(tribute) / gold_per_point * float(rules["tribute_value_factor"])})
	var tribute_demanded := demanded_per_turn * demanded_turns
	if tribute_demanded > 0:
		factors.append({"label": "tribute_demanded",
			"value": -float(tribute_demanded) / gold_per_point * float(rules["demand_multiplier"])})
	var offered_value := 0.0
	for region_id in offered:
		offered_value += region_value(data, state, region_id)
	if offered_value > 0.0:
		factors.append({"label": "regions_offered", "value": offered_value})
	var demanded_value := 0.0
	for region_id in demanded:
		demanded_value += region_value(data, state, region_id)
	if demanded_value > 0.0:
		factors.append({"label": "regions_demanded", "value": -demanded_value * float(rules["demand_multiplier"])})
	if not envoy.is_empty():
		factors.append({"label": "envoy_skill", "value": float(envoy["skill"]) * float(rules["envoy_skill_per_point"])})

	var score := 0.0
	for factor in factors:
		score += float(factor["value"])
	return {"accept": score >= 0.0, "score": score, "factors": factors, "reason": ""}


static func propose(data: GameData, state: Dictionary, proposal: Dictionary) -> Dictionary:
	## Evaluate and, if accepted, carry out every term. Returns the evaluation
	## with `accepted` set. Deterministic: no dice.
	var verdict := evaluate(data, state, proposal)
	var result := {"accepted": verdict["accept"], "score": verdict["score"],
		"factors": verdict["factors"], "reason": verdict["reason"]}
	if not verdict["accept"]:
		return result
	_apply(data, state, proposal)
	return result


## --- Transfers and tributes ---------------------------------------------------------

static func transfer_settlement(data: GameData, state: Dictionary, region_id: String, new_owner: String, options: Dictionary = {}) -> void:
	## A settlement changes hands without a fight. Its garrison marches out as
	## a field army of the old owner unless `keep_garrison` (a bought town's
	## watch takes the new coin); queues empty; family inside flee as from a
	## fallen city; `unrest` seeds the recently-conquered counter (default 0).
	var settlement: Dictionary = state["settlements"][region_id]
	var previous_owner: String = settlement["owner"]
	if previous_owner == new_owner:
		return
	if not options.get("keep_garrison", false) and not settlement["garrison"].is_empty() \
			and state["factions"][previous_owner]["alive"]:
		var army_id := "army_%d" % state["next_id"]
		state["next_id"] += 1
		state["armies"][army_id] = {
			"owner": previous_owner, "region": region_id, "units": settlement["garrison"],
			"general": null, "movement_left": 0.0, "forced_march": false,
		}
		settlement["garrison"] = []
	settlement["owner"] = new_owner
	settlement["construction_queue"] = []
	settlement["recruitment_queue"] = []
	settlement["governor"] = null
	settlement["low_order_streak"] = 0
	settlement["tax_level"] = "normal"
	settlement["recently_conquered"] = int(options.get("unrest", 0))
	var siege = settlement["siege"]
	if siege != null:
		var besieger: Dictionary = state["armies"].get(siege["besieger"], {})
		if besieger.is_empty() or not at_war(state, besieger["owner"], new_owner):
			settlement["siege"] = null
	CombatRules.displace_characters(data, state, region_id, previous_owner)
	CombatRules.check_faction_destroyed(state)
	SettlementRules.refresh_governors(data, state)


static func process_turn(data: GameData, state: Dictionary) -> Array:
	## Once per turn: opinions drift back toward indifference, wars grow
	## wearier, tributes are paid (and lapse with death or war), and vassals
	## send their overlords a share of the season's income. No dice.
	var rules: Dictionary = data.balance["diplomacy"]
	var notices: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	var decay := float(rules["opinion_decay_per_turn"])
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		var opinions := _opinions(faction)
		var others: Array = opinions.keys()
		others.sort()
		for other in others:
			var value := float(opinions[other])
			if value > 0.0:
				opinions[other] = maxf(0.0, value - decay)
			elif value < 0.0:
				opinions[other] = minf(0.0, value + decay)
		var wars := _war_turn_table(faction)
		var stances: Array = faction["diplomacy"].keys()
		stances.sort()
		for other in stances:
			if other != faction_id and faction["diplomacy"][other] == "war":
				wars[other] = int(wars.get(other, 0)) + 1
			elif wars.has(other):
				wars.erase(other)

	var remaining: Array = []
	for tribute in state.get("tributes", []):
		var payer: String = tribute["from"]
		var payee: String = tribute["to"]
		if not state["factions"].has(payer) or not state["factions"].has(payee) \
				or not state["factions"][payer]["alive"] or not state["factions"][payee]["alive"] \
				or at_war(state, payer, payee):
			notices.append({"kind": "tribute_ended", "from": payer, "to": payee, "lapsed": true})
			continue
		var amount := int(tribute["per_turn"])
		if int(state["factions"][payer]["treasury"]) < amount:
			# An empty treasury cannot pay; the promise lapses rather than
			# driving the payer into debt.
			notices.append({"kind": "tribute_ended", "from": payer, "to": payee, "lapsed": true})
			continue
		_pay(state, payer, payee, amount)
		tribute["turns_left"] = int(tribute["turns_left"]) - 1
		notices.append({"kind": "tribute_paid", "from": payer, "to": payee, "amount": amount})
		if int(tribute["turns_left"]) > 0:
			remaining.append(tribute)
		else:
			notices.append({"kind": "tribute_ended", "from": payer, "to": payee, "lapsed": false})
	state["tributes"] = remaining

	var share := float(rules["protectorate_tribute_pct"]) / 100.0
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		var overlord = faction.get("overlord", null)
		if overlord == null:
			continue
		if not state["factions"].has(overlord) or not state["factions"][overlord]["alive"] \
				or not faction["alive"] or stance_between(state, faction_id, overlord) != "protectorate":
			faction["overlord"] = null
			continue
		# The share is taken from what the season actually brought in (the
		# treasury step records it), not from an estimate.
		var income := float(faction.get("last_income",
			EconomyRules.faction_turn_breakdown(data, state, faction_id)["income"]))
		var amount := int(round(maxf(income, 0.0) * share))
		if amount <= 0:
			continue
		faction["treasury"] = int(faction["treasury"]) - amount
		state["factions"][overlord]["treasury"] = int(state["factions"][overlord]["treasury"]) + amount
		notices.append({"kind": "protectorate_tribute", "from": faction_id, "to": overlord, "amount": amount})
	return notices


## --- Internals -------------------------------------------------------------------------

static func _apply(data: GameData, state: Dictionary, proposal: Dictionary) -> void:
	var rules: Dictionary = data.balance["diplomacy"]
	var from: String = proposal["from"]
	var to: String = proposal["to"]
	var current := stance_between(state, from, to)
	var stance: String = proposal.get("stance", "")
	var raised := false
	if stance != "" and stance != current:
		var dissolving: bool = current != "war" \
			and int(STANCE_RANK.get(stance, 0)) < int(STANCE_RANK.get(current, 0))
		set_stance(state, from, to, stance)
		if current == "war":
			_set_war_turns(state, from, to, 0)
			_lift_sieges_between(state, from, to)
		if dissolving:
			adjust_opinion(data, state, to, from, -float(rules["treaty_ended_opinion_penalty"]))
		else:
			raised = true
			var bonus := float(rules["treaty_opinion_bonus"].get(stance, 0.0))
			adjust_opinion(data, state, to, from, bonus)
			adjust_opinion(data, state, from, to, bonus)
		if stance == "protectorate":
			state["factions"][to]["overlord"] = from

	var net_gold := maxi(0, int(proposal.get("gift", 0))) - maxi(0, int(proposal.get("demand", 0)))
	if net_gold > 0:
		_pay(state, from, to, net_gold)
		adjust_opinion(data, state, to, from, float(net_gold) / 100.0 * float(rules["opinion_per_100_gold_gift"]))
	elif net_gold < 0:
		_pay(state, to, from, -net_gold)
		adjust_opinion(data, state, to, from, float(net_gold) / 100.0 * float(rules["opinion_per_100_gold_demanded"]))

	# The first installment of a tribute changes hands with the signatures;
	# the rest follow at each season's end.
	_start_tribute(state, from, to, int(proposal.get("tribute_per_turn", 0)), int(proposal.get("tribute_turns", 0)))
	_start_tribute(state, to, from, int(proposal.get("tribute_demanded_per_turn", 0)),
		int(proposal.get("tribute_demanded_turns", 0)))

	for region_id in _unique(proposal.get("regions_offered", [])):
		transfer_settlement(data, state, region_id, to)
	for region_id in _unique(proposal.get("regions_demanded", [])):
		transfer_settlement(data, state, region_id, from)

	# An accepted offer is the envoy's work for the season; a treaty concluded
	# (never one dissolved) is a lesson learned, and he grows.
	var envoy: Dictionary = state["agents"].get(proposal.get("envoy", ""), {})
	if not envoy.is_empty() and envoy["owner"] == from:
		AgentRules.spend_season(envoy)
		if raised:
			envoy["skill"] = mini(int(envoy["skill"]) + 1, int(data.balance["agents"]["max_skill"]))


static func _pay(state: Dictionary, payer: String, payee: String, amount: int) -> void:
	state["factions"][payer]["treasury"] = int(state["factions"][payer]["treasury"]) - amount
	state["factions"][payee]["treasury"] = int(state["factions"][payee]["treasury"]) + amount


static func _start_tribute(state: Dictionary, payer: String, payee: String, per_turn: int, turns: int) -> void:
	if per_turn <= 0 or turns <= 0:
		return
	_pay(state, payer, payee, per_turn)
	if turns > 1:
		state["tributes"].append({"from": payer, "to": payee, "per_turn": per_turn, "turns_left": turns - 1})


static func _lift_sieges_between(state: Dictionary, a: String, b: String) -> void:
	## Peace ends every siege the two were pressing on each other.
	for settlement in state["settlements"].values():
		var siege = settlement["siege"]
		if siege == null:
			continue
		var besieger: Dictionary = state["armies"].get(siege["besieger"], {})
		if besieger.is_empty():
			continue
		if (settlement["owner"] == a and besieger["owner"] == b) \
				or (settlement["owner"] == b and besieger["owner"] == a):
			settlement["siege"] = null


static func lift_siege_by(state: Dictionary, army_id: String) -> void:
	## An army that changed banners keeps no siege its new master is not at war over.
	for settlement in state["settlements"].values():
		var siege = settlement["siege"]
		if siege != null and siege["besieger"] == army_id:
			var besieger: Dictionary = state["armies"].get(army_id, {})
			if besieger.is_empty() or not at_war(state, besieger["owner"], settlement["owner"]):
				settlement["siege"] = null


static func _owes_tribute(state: Dictionary, payer: String, payee: String) -> bool:
	for tribute in state.get("tributes", []):
		if tribute["from"] == payer and tribute["to"] == payee:
			return true
	return false


static func _unique(list: Array) -> Array:
	var seen := {}
	var result: Array = []
	for item in list:
		if not seen.has(item):
			seen[item] = true
			result.append(item)
	return result


static func _refusal(reason: String) -> Dictionary:
	return {"accept": false, "score": 0.0, "factors": [], "reason": reason}


static func _opinions(faction: Dictionary) -> Dictionary:
	if not faction.has("opinion") or not (faction["opinion"] is Dictionary):
		faction["opinion"] = {}
	return faction["opinion"]


static func _war_turn_table(faction: Dictionary) -> Dictionary:
	if not faction.has("war_turns") or not (faction["war_turns"] is Dictionary):
		faction["war_turns"] = {}
	return faction["war_turns"]


static func _set_war_turns(state: Dictionary, a: String, b: String, value: int) -> void:
	_war_turn_table(state["factions"][a])[b] = value
	_war_turn_table(state["factions"][b])[a] = value


static func _regions_of(state: Dictionary, faction_id: String) -> Array:
	var result: Array = []
	for region_id in state["settlements"]:
		if state["settlements"][region_id]["owner"] == faction_id:
			result.append(region_id)
	result.sort()
	return result


static func _allies_at_war_with(state: Dictionary, faction_id: String, enemy: String) -> int:
	## How many of faction_id's allies `enemy` is fighting.
	var count := 0
	for other in state["factions"]:
		if other == faction_id or other == enemy or not state["factions"][other]["alive"]:
			continue
		if stance_between(state, faction_id, other) == "alliance" and at_war(state, other, enemy):
			count += 1
	return count
