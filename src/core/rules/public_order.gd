class_name PublicOrderRules
## Public order = base 100 + a summed list of named factors (Law and Happiness
## both feed it; Law additionally suppresses corruption in EconomyRules).


static func breakdown(data: GameData, state: Dictionary, region_id: String) -> Array:
	var settlement: Dictionary = state["settlements"][region_id]
	var order_rules: Dictionary = data.balance["public_order"]
	var factors: Array = []

	factors.append({"label": "base", "value": float(order_rules["base"])})

	var law := law_total(data, state, region_id)
	if law != 0.0:
		factors.append({"label": "law", "value": law})

	var happiness := SettlementRules.effect_total(data, settlement, "happiness")
	if happiness != 0.0:
		factors.append({"label": "happiness_buildings", "value": happiness})

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
	var settlement: Dictionary = state["settlements"][region_id]
	return SettlementRules.effect_total(data, settlement, "law")


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

	if order >= float(order_rules["riot_threshold"]):
		settlement["low_order_streak"] = 0
		return result

	result["rioted"] = true
	var loss_pct := float(order_rules["riot_population_loss_pct"])
	settlement["population"] = maxi(400, int(round(settlement["population"] * (1.0 - loss_pct / 100.0))))
	if rng.chance(float(order_rules["riot_building_damage_chance"])):
		_damage_random_building(settlement, rng)

	if order < float(order_rules["revolt_threshold"]):
		settlement["low_order_streak"] = int(settlement["low_order_streak"]) + 1
		if settlement["low_order_streak"] >= int(order_rules["revolt_consecutive_turns"]):
			_revolt(data, state, region_id)
			result["revolted"] = true
	else:
		settlement["low_order_streak"] = 0
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
	settlement["owner"] = "rebels"
	settlement["garrison"] = []
	settlement["construction_queue"] = []
	settlement["recruitment_queue"] = []
	settlement["governor"] = null
	settlement["low_order_streak"] = 0
	settlement["recently_conquered"] = 0
	settlement["siege"] = null
	settlement["tax_level"] = "normal"
	CombatRules.displace_characters(data, state, region_id, previous_owner)
	SettlementRules.refresh_governors(data, state)
