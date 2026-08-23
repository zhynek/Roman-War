class_name NegotiationRules
## Phase 5 diplomacy: how the powers feel about each other, and what an envoy
## can talk them into. Attitude is the sum of a computed structural part
## (culture, stance, borders) and a stored, decaying ledger of deeds (gifts,
## betrayals, knives in the night) kept in faction["attitude"]. Offers are
## evaluated deterministically against thresholds in balance.json → attitude,
## so the player can learn to read the room rather than reroll it.
##
## Stance changes still go through DiplomacyRules; this module decides
## whether the other side agrees.


## --- Attitude -------------------------------------------------------------

static func attitude_breakdown(data: GameData, state: Dictionary, faction_id: String, other_id: String) -> Array:
	var rules: Dictionary = data.balance["attitude"]
	var factors: Array = []

	if data.culture_of_faction(faction_id) == data.culture_of_faction(other_id):
		factors.append({"label": "kindred_culture", "value": float(rules["same_culture"])})
	else:
		factors.append({"label": "foreign_ways", "value": float(rules["different_culture"])})

	var stance := DiplomacyRules.stance_between(state, faction_id, other_id)
	match stance:
		"trade":
			factors.append({"label": "trade_partners", "value": float(rules["stance_trade"])})
		"alliance", "protectorate":
			factors.append({"label": "sworn_allies", "value": float(rules["stance_alliance"])})
		"war":
			factors.append({"label": "at_war", "value": float(rules["stance_war"])})

	var border := _shared_border_count(data, state, faction_id, other_id)
	if border > 0:
		var friction := maxf(float(border) * float(rules["border_friction_per_region"]),
			float(rules["border_friction_max"]))
		factors.append({"label": "border_friction", "value": friction})

	var stored := stored_attitude(state, other_id, faction_id)
	if stored != 0.0:
		factors.append({"label": "past_deeds", "value": stored})

	return factors


static func attitude_total(data: GameData, state: Dictionary, faction_id: String, other_id: String) -> float:
	## How OTHER feels about FACTION — the number an envoy of faction_id is
	## up against when he asks other_id for something.
	var total := 0.0
	for factor in attitude_breakdown(data, state, faction_id, other_id):
		total += factor["value"]
	return total


static func stored_attitude(state: Dictionary, holder: String, about: String) -> float:
	## The deed ledger holder keeps about `about`.
	return float(state["factions"].get(holder, {}).get("attitude", {}).get(about, 0.0))


static func shift_stored_attitude(data: GameData, state: Dictionary, holder: String, about: String, amount: float) -> void:
	var rules: Dictionary = data.balance["attitude"]
	var faction: Dictionary = state["factions"].get(holder, {})
	if faction.is_empty():
		return
	if not faction.has("attitude"):
		faction["attitude"] = {}
	var ledger: Dictionary = faction["attitude"]
	ledger[about] = clampf(float(ledger.get(about, 0.0)) + amount,
		float(rules["stored_min"]), float(rules["stored_max"]))


static func decay_turn(data: GameData, state: Dictionary) -> void:
	## Deeds fade: every stored attitude entry steps toward zero each turn.
	var step := float(data.balance["attitude"]["stored_decay_per_turn"])
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var ledger: Dictionary = state["factions"][faction_id].get("attitude", {})
		var about_ids: Array = ledger.keys()
		about_ids.sort()
		for about in about_ids:
			var value := float(ledger[about])
			if absf(value) <= step:
				ledger.erase(about)
			else:
				ledger[about] = value - step * signf(value)


## --- Offers ---------------------------------------------------------------

static func evaluate(data: GameData, state: Dictionary, from_id: String, to_id: String, offer: Dictionary) -> Dictionary:
	## Would they take it? {accept: bool, reason: String}. Pure query — no
	## state change; execute() applies an accepted offer.
	var rules: Dictionary = data.balance["attitude"]
	if from_id == to_id or not state["factions"].has(to_id) or not state["factions"][to_id]["alive"]:
		return {"accept": false, "reason": "no_such_power"}
	var at_war := DiplomacyRules.at_war(state, from_id, to_id)
	var attitude := attitude_total(data, state, from_id, to_id)
	var payment := int(offer.get("payment", 0))
	if payment < 0 or payment > int(state["factions"][from_id]["treasury"]):
		return {"accept": false, "reason": "cannot_pay"}
	var sweetened := attitude + float(payment) / 1000.0 * float(rules["payment_attitude_per_1000"])

	match String(offer.get("kind", "")):
		"peace":
			if not at_war:
				return {"accept": false, "reason": "not_at_war"}
			var losing := _faction_war_strength(data, state, to_id) \
				< _faction_war_strength(data, state, from_id) * float(rules["peace_losing_ratio"])
			if losing or sweetened >= float(rules["accept_peace_threshold"]):
				return {"accept": true, "reason": "war_ends"}
			return {"accept": false, "reason": "they_smell_victory"}
		"trade":
			if at_war:
				return {"accept": false, "reason": "at_war"}
			var stance := DiplomacyRules.stance_between(state, from_id, to_id)
			if stance in ["trade", "alliance", "protectorate"]:
				return {"accept": false, "reason": "already_agreed"}
			if sweetened >= float(rules["accept_trade_threshold"]):
				return {"accept": true, "reason": "markets_open"}
			return {"accept": false, "reason": "too_little_goodwill"}
		"alliance":
			if at_war:
				return {"accept": false, "reason": "at_war"}
			if DiplomacyRules.stance_between(state, from_id, to_id) == "alliance":
				return {"accept": false, "reason": "already_agreed"}
			if sweetened >= float(rules["accept_alliance_threshold"]):
				return {"accept": true, "reason": "oaths_sworn"}
			return {"accept": false, "reason": "too_little_goodwill"}
		"gift":
			if payment <= 0:
				return {"accept": false, "reason": "empty_handed"}
			return {"accept": true, "reason": "gift_received"}
		"demand_tribute":
			if at_war:
				return {"accept": false, "reason": "at_war"}
			var amount := int(rules["tribute_amount"])
			if int(state["factions"][to_id]["treasury"]) < amount:
				return {"accept": false, "reason": "they_are_poor"}
			var fear: bool = _faction_war_strength(data, state, from_id) \
				> _faction_war_strength(data, state, to_id) * float(rules["tribute_demand_fear_ratio"])
			if fear:
				return {"accept": true, "reason": "tribute_paid"}
			return {"accept": false, "reason": "they_do_not_fear_us"}
		"buy_region":
			var region_id := String(offer.get("region", ""))
			var check := _sellable(data, state, from_id, to_id, region_id)
			if check != "":
				return {"accept": false, "reason": check}
			if payment < region_price(data, state, region_id):
				return {"accept": false, "reason": "insulting_price"}
			if attitude < float(rules["accept_sell_region_threshold"]):
				return {"accept": false, "reason": "too_little_goodwill"}
			return {"accept": true, "reason": "town_sold"}
	return {"accept": false, "reason": "unknown_offer"}


static func execute(data: GameData, state: Dictionary, from_id: String, to_id: String, offer: Dictionary) -> Dictionary:
	## Evaluate and, if accepted, apply. Rejections can still leave marks —
	## a refused tribute demand is an insult remembered.
	var rules: Dictionary = data.balance["attitude"]
	var verdict := evaluate(data, state, from_id, to_id, offer)
	var payment := int(offer.get("payment", 0))
	if not verdict["accept"]:
		if String(offer.get("kind", "")) == "demand_tribute" \
				and verdict["reason"] == "they_do_not_fear_us":
			shift_stored_attitude(data, state, to_id, from_id, float(rules["tribute_refused_attitude"]))
		return verdict

	match String(offer.get("kind", "")):
		"peace":
			DiplomacyRules.set_stance(state, from_id, to_id, "neutral")
			_pay(state, from_id, to_id, payment)
		"trade":
			DiplomacyRules.set_stance(state, from_id, to_id, "trade")
			_pay(state, from_id, to_id, payment)
		"alliance":
			DiplomacyRules.set_stance(state, from_id, to_id, "alliance")
			_pay(state, from_id, to_id, payment)
		"gift":
			_pay(state, from_id, to_id, payment)
			shift_stored_attitude(data, state, to_id, from_id,
				float(payment) / 1000.0 * float(rules["gift_attitude_per_1000"]))
		"demand_tribute":
			var amount := int(rules["tribute_amount"])
			_pay(state, to_id, from_id, amount)
			shift_stored_attitude(data, state, to_id, from_id, float(rules["tribute_paid_attitude"]))
			verdict["amount"] = amount
		"buy_region":
			var region_id := String(offer.get("region", ""))
			_pay(state, from_id, to_id, payment)
			_hand_over_region(data, state, region_id, from_id)
	return verdict


static func region_price(data: GameData, state: Dictionary, region_id: String) -> int:
	var rules: Dictionary = data.balance["attitude"]
	var population := int(state["settlements"][region_id]["population"])
	return maxi(int(rules["sell_region_min_price"]),
		int(round(population * float(rules["sell_region_price_per_pop"]))))


static func sellable_regions(data: GameData, state: Dictionary, from_id: String, to_id: String) -> Array:
	## Their border towns we could plausibly buy: adjacent to our lands, not
	## their capital, never their last holding. Sorted.
	var found: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if _sellable(data, state, from_id, to_id, region_id) == "":
			found.append(region_id)
	return found


## --- Internals ------------------------------------------------------------

static func _sellable(data: GameData, state: Dictionary, from_id: String, to_id: String, region_id: String) -> String:
	## "" when sellable, else the reason it is not.
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != to_id:
		return "not_theirs"
	if DiplomacyRules.at_war(state, from_id, to_id):
		return "at_war"
	if state["factions"][to_id]["capital"] == region_id:
		return "their_capital"
	var holdings := 0
	for other in state["settlements"].values():
		if other["owner"] == to_id:
			holdings += 1
	if holdings <= 1:
		return "their_last_town"
	var borders_us := false
	for neighbor in data.regions[region_id].get("adjacent", []):
		if state["settlements"].has(neighbor) and state["settlements"][neighbor]["owner"] == from_id:
			borders_us = true
			break
	if not borders_us:
		return "not_on_our_border"
	return ""


static func _hand_over_region(data: GameData, state: Dictionary, region_id: String, new_owner: String) -> void:
	## A peaceful handover: the garrison marches home into thin air, the
	## people stay, and the new master inherits a town mildly unhappy about
	## being sold like a mule.
	var settlement: Dictionary = state["settlements"][region_id]
	var previous_owner: String = settlement["owner"]
	settlement["owner"] = new_owner
	settlement["garrison"] = []
	settlement["construction_queue"] = []
	settlement["recruitment_queue"] = []
	settlement["governor"] = null
	settlement["siege"] = null
	settlement["low_order_streak"] = 0
	settlement["tax_level"] = "normal"
	settlement["recently_conquered"] = int(data.balance["attitude"]["sell_region_handover_unrest"])
	CombatRules.displace_characters(data, state, region_id, previous_owner)
	SettlementRules.refresh_governors(data, state)


static func _pay(state: Dictionary, from_id: String, to_id: String, amount: int) -> void:
	if amount <= 0:
		return
	state["factions"][from_id]["treasury"] = int(state["factions"][from_id]["treasury"]) - amount
	state["factions"][to_id]["treasury"] = int(state["factions"][to_id]["treasury"]) + amount


static func _shared_border_count(data: GameData, state: Dictionary, a: String, b: String) -> int:
	var count := 0
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] != a:
			continue
		for neighbor in data.regions[region_id].get("adjacent", []):
			if state["settlements"].has(neighbor) and state["settlements"][neighbor]["owner"] == b:
				count += 1
				break
	return count


static func _faction_war_strength(data: GameData, state: Dictionary, faction_id: String) -> float:
	var xp_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	var total := 0.0
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army["owner"] == faction_id:
			total += BattleResolver.force_strength(data, army["units"],
				CombatRules.general_profile(data, state, army), xp_pct)
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] == faction_id:
			total += BattleResolver.force_strength(data, settlement["garrison"], null, xp_pct)
	return total
