class_name EconomyRules
## Settlement income breakdowns and faction-level treasury resolution.
## Construction and recruitment are paid up front at queue time
## (ConstructionRules / RecruitmentRules); this module handles the per-turn
## income and upkeep stream.


static func settlement_income_breakdown(data: GameData, state: Dictionary, region_id: String, rng: CampaignRng = null) -> Array:
	var settlement: Dictionary = state["settlements"][region_id]
	var region: Dictionary = data.regions[region_id]
	var tax_rules: Dictionary = data.balance["taxes"]
	var economy_rules: Dictionary = data.balance["economy"]
	var factors: Array = []

	var tax_income := float(settlement["population"]) / 1000.0 \
		* float(tax_rules["base_income_per_1000_pop"]) \
		* float(tax_rules["income_multiplier"][settlement["tax_level"]])
	factors.append({"label": "taxes", "value": tax_income})

	var farm_income := float(region["fertility"]) * float(economy_rules["farm_income_fertility_multiplier"]) \
		+ SettlementRules.effect_total(data, settlement, "farm_income")
	farm_income *= 1.0 + SettlementRules.faction_owns_wonder_effect(
		data, state, settlement["owner"], "farm_income_pct") / 100.0
	if rng != null:
		farm_income *= rng.randf_pct(float(economy_rules["harvest_variance_pct"]))
	factors.append({"label": "farming", "value": farm_income})

	var trade := trade_income(data, state, region_id)
	if trade > 0.0:
		factors.append({"label": "trade", "value": trade})

	var mines := SettlementRules.effect_total(data, settlement, "mine_income")
	if mines > 0.0:
		factors.append({"label": "mines", "value": mines})

	var gross := tax_income + farm_income + trade + mines

	# A capable governor grows the whole take; trade-minded traits favor commerce.
	if settlement["governor"] != null and state["characters"].has(settlement["governor"]):
		var governor: Dictionary = state["characters"][settlement["governor"]]
		var management_pct := float(CharacterRules.effective(data, governor, "management")) \
			* float(data.balance["characters"]["governor_management_income_pct_per_point"])
		var governor_income := gross * management_pct / 100.0 \
			+ trade * CharacterRules.effect_total(data, governor, "trade_pct") / 100.0
		if governor_income != 0.0:
			factors.append({"label": "governor", "value": governor_income})

	var corruption := corruption_pct(data, state, region_id) / 100.0 * gross
	if corruption > 0.0:
		factors.append({"label": "corruption", "value": -corruption})

	return factors


static func settlement_income(data: GameData, state: Dictionary, region_id: String, rng: CampaignRng = null) -> float:
	var total := 0.0
	for factor in settlement_income_breakdown(data, state, region_id, rng):
		total += factor["value"]
	return total


static func trade_income(data: GameData, state: Dictionary, region_id: String) -> float:
	## Land routes to adjacent partner regions; sea routes (capped by port level)
	## to partner regions sharing a sea zone. A route is worth a base amount plus
	## a premium for each resource the partner has that this region lacks.
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = settlement["owner"]
	var economy_rules: Dictionary = data.balance["economy"]
	var own_resources: Array = data.regions[region_id].get("resources", [])
	var port_level := int(SettlementRules.effect_max(data, settlement, "port_level"))
	var trade_pct := SettlementRules.effect_total(data, settlement, "trade_pct")
	var sea_trade_wonder := SettlementRules.faction_owns_wonder_effect(data, state, owner, "sea_trade_pct")

	var land_total := 0.0
	var sea_routes: Array = []
	for other_id in state["settlements"]:
		if other_id == region_id:
			continue
		var other: Dictionary = state["settlements"][other_id]
		if not _trades_with(state, owner, other["owner"]):
			continue
		var premium := 0.0
		for resource in data.regions[other_id].get("resources", []):
			if not own_resources.has(resource):
				premium += float(economy_rules["trade_income_per_resource"])
		if MapRules.are_adjacent(data, region_id, other_id):
			var road_bonus := 1.0 + SettlementRules.effect_max(data, settlement, "road_level") \
				* float(economy_rules["road_trade_bonus_per_level"])
			land_total += (float(economy_rules["land_trade_route_base"]) + premium) * road_bonus
		elif port_level > 0 and MapRules.shared_sea_zone(data, region_id, other_id) \
				and SettlementRules.effect_max(data, other, "port_level") > 0.0:
			sea_routes.append(float(economy_rules["sea_trade_route_base"]) + premium)

	sea_routes.sort()
	sea_routes.reverse()
	var sea_total := 0.0
	for i in range(mini(port_level * int(economy_rules["sea_routes_per_port_level"]), sea_routes.size())):
		sea_total += sea_routes[i]
	sea_total *= 1.0 + sea_trade_wonder / 100.0

	return (land_total + sea_total) * (1.0 + trade_pct / 100.0)


static func corruption_pct(data: GameData, state: Dictionary, region_id: String) -> float:
	var corruption_rules: Dictionary = data.balance["corruption"]
	var distance_rules: Dictionary = data.balance["distance_to_capital"]
	var settlement: Dictionary = state["settlements"][region_id]
	var capital: String = state["factions"][settlement["owner"]]["capital"]
	var hops := 0
	if capital != "" and capital != region_id:
		hops = MapRules.hops_between(data, capital, region_id)
		if hops < 0:
			hops = 99
	var beyond := maxi(0, hops - int(distance_rules["free_hops"]))
	var corruption := minf(float(beyond) * float(corruption_rules["pct_per_hop_beyond_free"]),
		float(corruption_rules["max_pct"]))
	var law := PublicOrderRules.law_total(data, state, region_id)
	corruption *= maxf(0.0, 1.0 - law * float(corruption_rules["law_reduction_factor"]))
	return corruption


static func army_upkeep(data: GameData, units: Array) -> int:
	var upkeep := 0
	for unit in units:
		upkeep += int(data.units.get(unit["template"], {}).get("upkeep", 0))
	return upkeep


static func faction_upkeep(data: GameData, state: Dictionary, faction_id: String) -> int:
	var upkeep := 0
	for army in state["armies"].values():
		if army["owner"] == faction_id:
			upkeep += army_upkeep(data, army["units"])
	for fleet in state["fleets"].values():
		if fleet["owner"] == faction_id:
			upkeep += army_upkeep(data, fleet["ships"])
	for settlement in state["settlements"].values():
		if settlement["owner"] == faction_id:
			upkeep += army_upkeep(data, settlement["garrison"])
	return upkeep


static func faction_turn_breakdown(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng = null) -> Dictionary:
	var income := 0.0
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] == faction_id:
			income += settlement_income(data, state, region_id, rng)

	var difficulty_multiplier := 1.0
	if faction_id != state["player_faction"]:
		var ai_rules: Dictionary = data.balance["ai"]
		difficulty_multiplier = float(ai_rules["difficulty_income_multiplier"].get(
			state.get("difficulty", "medium"), 1.0))
	income *= difficulty_multiplier

	var upkeep := faction_upkeep(data, state, faction_id)
	return {"income": income, "upkeep": upkeep, "net": income - float(upkeep)}


static func apply_faction_turn(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng) -> Dictionary:
	var result := faction_turn_breakdown(data, state, faction_id, rng)
	var faction: Dictionary = state["factions"][faction_id]
	faction["treasury"] = int(faction["treasury"]) + int(round(result["net"]))

	# Sustained deep debt forces disbandment: one costliest field unit per turn.
	var threshold := int(data.balance["economy"]["debt_disband_threshold"])
	if int(faction["treasury"]) < threshold:
		result["disbanded"] = _disband_costliest_unit(data, state, faction_id)
	return result


static func _disband_costliest_unit(data: GameData, state: Dictionary, faction_id: String) -> bool:
	# Armies are walked in sorted id order: ties on upkeep must resolve the
	# same way in a loaded save as in the live game (JSON re-orders keys).
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	var worst_id := ""
	var worst_index := -1
	var worst_upkeep := 0
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army["owner"] != faction_id:
			continue
		for i in range(army["units"].size()):
			var upkeep := int(data.units.get(army["units"][i]["template"], {}).get("upkeep", 0))
			if upkeep > worst_upkeep:
				worst_upkeep = upkeep
				worst_id = army_id
				worst_index = i
	if worst_index < 0:
		return false
	var worst_army: Dictionary = state["armies"][worst_id]
	worst_army["units"].remove_at(worst_index)
	if worst_army["units"].is_empty():
		# The last men go home: no ghost army lingers to hold a siege or block
		# a road. Its general stays where he stood, unattached.
		SiegeRules.release(state, worst_id)
		state["armies"].erase(worst_id)
	return true


static func _trades_with(state: Dictionary, a: String, b: String) -> bool:
	if a == b:
		return true
	var stance: String = state["factions"][a]["diplomacy"].get(b, "neutral")
	return stance in ["trade", "alliance", "protectorate"]
