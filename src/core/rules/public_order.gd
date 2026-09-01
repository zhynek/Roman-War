class_name PublicOrderRules
## Public order = base 100 + a summed list of named factors (Law and Happiness
## both feed it; Law additionally suppresses corruption in EconomyRules).
##
## Order is now a READOUT of the societal stocks as much as a thing in itself:
## Standing and Grievance enter as named factors, and coercion buys order
## without buying consent. That asymmetry is deliberate — a garrisoned province
## reads calm while its grievance climbs, and riots when the accumulated
## resentment finally outweighs the force holding it down.


static func breakdown(data: GameData, state: Dictionary, region_id: String) -> Array:
	var settlement: Dictionary = state["settlements"][region_id]
	var order_rules: Dictionary = data.balance["public_order"]
	var factors: Array = []

	factors.append({"label": "base", "value": float(order_rules["base"])})

	# Building law only — edict law arrives via its own edict:<id> factor
	# below (law_total, which feeds corruption, sums both).
	var law := SettlementRules.effect_total(data, settlement, "law")
	if law != 0.0:
		factors.append({"label": "law", "value": law})

	var happiness := SettlementRules.effect_total(data, settlement, "happiness")
	if happiness != 0.0:
		factors.append({"label": "happiness_buildings", "value": happiness})

	var knowledge_happiness := KnowledgeRules.faction_effect_total(data, state, settlement["owner"], "happiness")
	if knowledge_happiness != 0.0:
		factors.append({"label": "knowledge", "value": knowledge_happiness})

	# Each standing edict shows its hand by name (happiness and law both feed
	# order one-for-one); decree moods and repeal shocks sum as one factor.
	# Null-checks over .get defaults: this is the breakdown hot path.
	var held = state["factions"][settlement["owner"]].get("edicts")
	if held != null and not (held as Dictionary).is_empty():
		var edict_ids: Array = (held as Dictionary).keys()
		edict_ids.sort()
		for eid in edict_ids:
			var effects: Dictionary = data.edicts.get(eid, {}).get("effects", {})
			var value := float(effects.get("happiness", 0.0)) + float(effects.get("law", 0.0))
			if value != 0.0:
				factors.append({"label": "edict:" + String(eid), "value": value})
	var moods := ModifierRules.sum_for(state, settlement["owner"], region_id, "happiness")
	if moods != 0.0:
		factors.append({"label": "decrees", "value": moods})

	var tax_happiness: float = order_rules["tax_happiness"][settlement["tax_level"]]
	if tax_happiness != 0.0:
		factors.append({"label": "taxes", "value": tax_happiness})

	var garrison := garrison_bonus(data, settlement)
	if garrison > 0.0:
		factors.append({"label": "garrison", "value": garrison})

	if settlement["governor"] != null and state["characters"].has(settlement["governor"]):
		var governor: Dictionary = state["characters"][settlement["governor"]]
		var per_point := float(order_rules["governor_influence_pct_per_point"])
		var influence_bonus := float(CharacterRules.effective(data, governor, "influence")) * per_point
		if influence_bonus != 0.0:
			factors.append({"label": "governor", "value": influence_bonus})
		var governor_traits := CharacterRules.effect_total(data, governor, "law") \
			+ CharacterRules.effect_total(data, governor, "happiness")
		if governor_traits != 0.0:
			factors.append({"label": "governor_traits", "value": governor_traits})
	else:
		factors.append({"label": "no_governor", "value": -float(order_rules["no_governor_penalty"])})

	var squalor_rules: Dictionary = data.balance["squalor"]
	var squalor := minf(float(settlement["population"]) / float(squalor_rules["population_per_pct"]),
		float(squalor_rules["max_order_penalty_pct"]))
	if squalor > 0.0:
		factors.append({"label": "squalor", "value": -squalor})

	var distance := distance_penalty(data, state, region_id)
	if distance > 0.0:
		factors.append({"label": "distance_to_capital", "value": -distance})

	var culture := SettlementRules.culture_penalty_pct(data, state, region_id)
	if culture > 0.0:
		factors.append({"label": "culture_penalty", "value": -culture})

	if int(settlement["recently_conquered"]) > 0:
		var decay := float(order_rules["recently_conquered_decay_per_turn"])
		var penalty := minf(float(order_rules["recently_conquered_penalty"]),
			float(settlement["recently_conquered"]) * decay)
		factors.append({"label": "recently_conquered", "value": -penalty})

	var wonder_happiness := SettlementRules.faction_owns_wonder_effect(
		data, state, settlement["owner"], "happiness_all_settlements")
	if wonder_happiness != 0.0:
		factors.append({"label": "wonders", "value": wonder_happiness})

	var growth := GrowthRules.total_pct(data, state, region_id)
	if growth >= float(data.balance["public_order"]["population_boom_growth_pct"]):
		factors.append({"label": "population_boom", "value": float(order_rules["population_boom_bonus"])})

	var event_happiness = state.get("event_happiness")
	if event_happiness != null and float(event_happiness["value"]) != 0.0:
		factors.append({"label": "events", "value": float(event_happiness["value"])})

	var society_rules: Dictionary = data.balance["society"]
	var stocks := SocietyRules.stocks_of(data, settlement)

	var standing := (float(stocks["legitimacy"]) - float(society_rules["order_legitimacy_neutral"])) \
		* float(society_rules["order_legitimacy_scale"])
	if standing != 0.0:
		factors.append({"label": "standing", "value": standing})

	var grievance := float(stocks["grievance"]) * float(society_rules["order_grievance_scale"])
	if grievance > 0.0:
		factors.append({"label": "grievance", "value": -grievance})

	# Force keeps order without earning it. Nothing here reduces the load, so
	# the grievance it is suppressing goes on rising underneath.
	var coercion := SocietyRules.coercion_total(data, state, region_id) \
		* float(society_rules["order_coercion_scale"])
	if coercion > 0.0:
		factors.append({"label": "coercion", "value": coercion})

	var unrest_state := String(stocks["unrest_state"])
	if unrest_state == SocietyRules.UNREST_RESTIVE:
		factors.append({"label": "restive", "value": -float(society_rules["restive_order_penalty"])})
	elif unrest_state == SocietyRules.UNREST_REBELLIOUS:
		factors.append({"label": "in_revolt", "value": -float(society_rules["rebellious_order_penalty"])})

	if settlement["owner"] != state.get("player_faction", ""):
		var ai_bonus := float(data.balance["ai"]["difficulty_order_bonus"].get(
			state.get("difficulty", "medium"), 0.0))
		if ai_bonus != 0.0:
			factors.append({"label": "ai_difficulty", "value": ai_bonus})

	return factors


static func total(data: GameData, state: Dictionary, region_id: String) -> float:
	var sum := 0.0
	for factor in breakdown(data, state, region_id):
		sum += factor["value"]
	return maxf(sum, 0.0)


static func law_total(data: GameData, state: Dictionary, region_id: String) -> float:
	## Building law plus standing-edict law — corruption suppression reads this.
	var settlement: Dictionary = state["settlements"][region_id]
	return SettlementRules.effect_total(data, settlement, "law") \
		+ EdictRules.faction_effect_total(data, state, settlement["owner"], "law")


static func garrison_bonus(data: GameData, settlement: Dictionary) -> float:
	var order_rules: Dictionary = data.balance["public_order"]
	var soldiers := SettlementRules.garrison_soldiers(data, settlement)
	if soldiers == 0 or int(settlement["population"]) == 0:
		return 0.0
	var ratio := float(soldiers) / float(settlement["population"])
	return minf(ratio * float(order_rules["garrison_ratio_scale"]), float(order_rules["garrison_max_bonus"]))


static func distance_penalty(data: GameData, state: Dictionary, region_id: String) -> float:
	var settlement: Dictionary = state["settlements"][region_id]
	var capital: String = state["factions"][settlement["owner"]]["capital"]
	if capital == "" or capital == region_id:
		return 0.0
	var distance_rules: Dictionary = data.balance["distance_to_capital"]
	var hops := MapRules.hops_between(data, capital, region_id)
	if hops < 0:
		hops = int(distance_rules["max_penalty_pct"] / distance_rules["pct_per_hop"]) + int(distance_rules["free_hops"])
	var beyond := maxi(0, hops - int(distance_rules["free_hops"]))
	return minf(float(beyond) * float(distance_rules["pct_per_hop"]), float(distance_rules["max_penalty_pct"]))


static func apply_turn(data: GameData, state: Dictionary, region_id: String, rng: CampaignRng) -> Dictionary:
	## Riots and revolts. Returns {order: float, rioted: bool, revolted: bool}.
	var settlement: Dictionary = state["settlements"][region_id]
	var order_rules: Dictionary = data.balance["public_order"]
	var order := total(data, state, region_id)
	var result := {"order": order, "rioted": false, "revolted": false}

	# A province that has withdrawn its consent entirely is past the point where
	# the garrison decides the question. Coercion buys time here, not immunity:
	# it keeps the ORDER number high while grievance climbs, and then this check
	# fires anyway. That is the whole shape of the trap.
	var society_rules: Dictionary = data.balance["society"]
	var stocks := SocietyRules.stocks_of(data, settlement)
	var in_open_revolt: bool = String(stocks["unrest_state"]) == SocietyRules.UNREST_REBELLIOUS \
		and int(stocks["unrest_turns"]) >= int(society_rules["rebellious_turns_to_revolt"])

	if order >= float(order_rules["riot_threshold"]) and not in_open_revolt:
		settlement["low_order_streak"] = 0
		return result

	result["rioted"] = true
	var loss_pct := float(order_rules["riot_population_loss_pct"])
	settlement["population"] = maxi(400, int(round(settlement["population"] * (1.0 - loss_pct / 100.0))))
	if rng.chance(float(order_rules["riot_building_damage_chance"])):
		_damage_random_building(settlement, rng)

	if order < float(order_rules["revolt_threshold"]):
		settlement["low_order_streak"] = int(settlement["low_order_streak"]) + 1
	else:
		settlement["low_order_streak"] = 0

	# Two roads to secession: an order collapse (as before), or a province that has
	# been in open revolt long enough to choose its own masters — the second is
	# the one accumulated grievance drives, and no garrison prevents it.
	if in_open_revolt or settlement["low_order_streak"] >= int(order_rules["revolt_consecutive_turns"]):
		_revolt(data, state, region_id)
		result["revolted"] = true
	return result


static func _damage_random_building(settlement: Dictionary, rng: CampaignRng) -> void:
	var chain_ids: Array = settlement["buildings"].keys()
	if chain_ids.is_empty():
		return
	chain_ids.sort()
	var chain_id: String = rng.pick(chain_ids)
	var tier := int(settlement["buildings"][chain_id]) - 1
	if tier <= 0:
		settlement["buildings"].erase(chain_id)
	else:
		settlement["buildings"][chain_id] = tier


static func _revolt(data: GameData, state: Dictionary, region_id: String) -> void:
	## The settlement secedes to the rebel faction; the garrison is expelled...
	## by which we mean destroyed, as is traditional. Any family caught inside
	## flees to the nearest city the house still holds.
	var settlement: Dictionary = state["settlements"][region_id]
	var previous_owner: String = settlement["owner"]
	ChronicleRules.record(data, state, "city_revolted",
		{"faction": previous_owner, "region": region_id}, 5)
	settlement["owner"] = "rebels"
	settlement["garrison"] = []
	settlement["construction_queue"] = []
	settlement["recruitment_queue"] = []
	settlement["governor"] = null
	settlement["low_order_streak"] = 0
	settlement["recently_conquered"] = 0
	settlement["siege"] = null
	settlement["tax_level"] = "normal"
	# The province is governing itself now: the grievance was against the masters
	# it just threw off, and it belongs to nobody but itself.
	settlement["society"] = SocietyRules.new_settlement_society(
		data, true, SocietyRules.provision(data, settlement))
	EdictRules.clear(settlement)
	CombatRules.displace_characters(data, state, region_id, previous_owner)
	# A house can lose its last city to its own people, not just to conquest.
	# A revolt can take a faction's LAST settlement — the destruction check
	# must run here just as it does after capture and cession, or a landless
	# zombie faction keeps playing full turns.
	CombatRules.check_faction_destroyed(state)
	SettlementRules.refresh_governors(data, state)
