class_name GrowthRules
## Population growth as a summed list of named factors, mirroring the
## settlement-details breakdown. All constants come from data/balance.json.


static func breakdown(data: GameData, state: Dictionary, region_id: String) -> Array:
	var settlement: Dictionary = state["settlements"][region_id]
	var region: Dictionary = data.regions[region_id]
	var growth_rules: Dictionary = data.balance["growth"]
	var factors: Array = []

	factors.append({"label": "base_fertility", "value": float(region["fertility"])})

	var farm_growth := SettlementRules.effect_total(data, settlement, "growth")
	if farm_growth != 0.0:
		factors.append({"label": "buildings", "value": farm_growth})

	var knowledge_growth := KnowledgeRules.faction_effect_total(data, state, settlement["owner"], "growth")
	if knowledge_growth != 0.0:
		factors.append({"label": "knowledge", "value": knowledge_growth})

	var held = state["factions"][settlement["owner"]].get("edicts")
	if held != null and not (held as Dictionary).is_empty():
		var edict_ids: Array = (held as Dictionary).keys()
		edict_ids.sort()
		for eid in edict_ids:
			var edict_growth := float(data.edicts.get(eid, {}).get("effects", {}).get("growth", 0.0))
			if edict_growth != 0.0:
				factors.append({"label": "edict:" + String(eid), "value": edict_growth})

	var health := SettlementRules.effect_total(data, settlement, "health")
	if health != 0.0:
		var per_10: float = growth_rules["health_pct_per_10_health"]
		factors.append({"label": "health", "value": health / 10.0 * per_10})

	var tax_growth: float = growth_rules["tax_growth_pct"][settlement["tax_level"]]
	if tax_growth != 0.0:
		factors.append({"label": "taxes", "value": tax_growth})

	if int(settlement["slave_bonus_turns"]) > 0:
		factors.append({"label": "slaves", "value": float(growth_rules["slave_influx_pct"])})

	var grain_routes := _grain_routes(data, state, region_id)
	if grain_routes > 0:
		var tiers: Array = growth_rules["grain_import_pct_by_routes"]
		factors.append({"label": "grain_imports", "value": float(tiers[mini(grain_routes, tiers.size()) - 1])})

	if settlement["governor"] != null and state["characters"].has(settlement["governor"]):
		var governor_growth := CharacterRules.effect_total(
			data, state["characters"][settlement["governor"]], "growth")
		if governor_growth != 0.0:
			factors.append({"label": "governor", "value": governor_growth})

	var squalor := squalor_pct(data, settlement)
	if squalor > 0.0:
		factors.append({"label": "squalor", "value": -squalor})

	if int(settlement["plague_turns"]) > 0:
		factors.append({"label": "plague", "value": float(growth_rules["plague_growth_pct"])})

	if int(settlement["recently_conquered"]) > 0:
		factors.append({"label": "recently_conquered", "value": float(growth_rules["recently_conquered_growth_pct"])})

	# Men marched off to the levy are men not at the plough; the strain fades
	# a little each turn (PublicOrderRules.decay_levy_strain).
	var strain := float(settlement.get("levy_strain", 0.0))
	if strain > 0.0:
		factors.append({"label": "levy_strain", "value": -strain * float(growth_rules["levy_strain_growth_pct_per_point"])})

	# A province that has stopped cooperating stops growing: fields go unworked,
	# markets stay shut, and those who can leave do.
	var society_rules: Dictionary = data.balance["society"]
	var unrest_state := String(SocietyRules.stocks_of(data, settlement)["unrest_state"])
	if unrest_state == SocietyRules.UNREST_RESTIVE:
		factors.append({"label": "unrest", "value": -float(society_rules["restive_growth_penalty_pct"])})
	elif unrest_state == SocietyRules.UNREST_REBELLIOUS:
		factors.append({"label": "unrest", "value": -float(society_rules["rebellious_growth_penalty_pct"])})

	return factors


static func total_pct(data: GameData, state: Dictionary, region_id: String) -> float:
	var total := 0.0
	for factor in breakdown(data, state, region_id):
		total += factor["value"]
	var growth_rules: Dictionary = data.balance["growth"]
	return clampf(total, float(growth_rules["min_growth_pct"]), float(growth_rules["max_growth_pct"]))


static func squalor_pct(data: GameData, settlement: Dictionary) -> float:
	var squalor_rules: Dictionary = data.balance["squalor"]
	var squalor := float(settlement["population"]) / float(squalor_rules["population_per_pct"])
	return minf(squalor, float(squalor_rules["max_growth_penalty_pct"]))


static func apply_turn(data: GameData, state: Dictionary, region_id: String, rng: CampaignRng) -> Dictionary:
	## Returns what changed, so the turn journal can report a city outgrowing
	## its walls or a plague taking hold without recomputing any of it.
	var settlement: Dictionary = state["settlements"][region_id]
	var population := int(settlement["population"])
	var population_before := population
	var level_before := SettlementRules.settlement_level(data, settlement)
	var plague_before := int(settlement["plague_turns"])
	population = int(round(population * (1.0 + total_pct(data, state, region_id) / 100.0)))

	_plague_turn(data, state, settlement, rng)
	if int(settlement["plague_turns"]) > 0:
		var loss_pct := float(data.balance["plague"]["population_loss_pct_per_turn"])
		population = int(round(population * (1.0 - loss_pct / 100.0)))

	settlement["population"] = maxi(population, int(data.balance["growth"]["min_population"]))

	for counter in ["slave_bonus_turns", "recently_conquered"]:
		if int(settlement[counter]) > 0:
			settlement[counter] = int(settlement[counter]) - 1

	return {
		"population_before": population_before,
		"population_after": int(settlement["population"]),
		"delta": int(settlement["population"]) - population_before,
		"level_before": level_before,
		"level_after": SettlementRules.settlement_level(data, settlement),
		"plague_started": plague_before == 0 and int(settlement["plague_turns"]) > 0,
	}


static func _plague_turn(data: GameData, state: Dictionary, settlement: Dictionary, rng: CampaignRng) -> void:
	var plague_rules: Dictionary = data.balance["plague"]
	if int(settlement["plague_turns"]) > 0:
		settlement["plague_turns"] = int(settlement["plague_turns"]) - 1
		return
	# Plague risk grows with population beyond what health infrastructure
	# supports; practiced techniques (drains, aqueducts, physicians' regimens —
	# plague_resistance, in people sheltered) raise the whole faction's capacity.
	var health := SettlementRules.effect_total(data, settlement, "health")
	# Both knowledge layers raise the ceiling a city can live under, and they
	# work differently: an advance scales the whole capacity (drains, clean
	# water, the measured fall of an aqueduct), while a practiced technique
	# adds sheltered people outright.
	var capacity := float(plague_rules["base_capacity"]) \
		+ health * float(plague_rules["health_capacity_per_health_pct"])
	capacity *= 1.0 + AdvanceRules.effect_total(
		data, state, String(settlement["owner"]), "health_capacity_pct") / 100.0
	capacity += KnowledgeRules.faction_effect_total(
		data, state, String(settlement["owner"]), "plague_resistance")
	var excess := float(settlement["population"]) - capacity
	if excess <= 0.0:
		return
	var outbreak_chance := excess / 1000.0 * float(plague_rules["base_chance_per_1000_over_health_capacity"])
	if rng.chance(outbreak_chance):
		settlement["plague_turns"] = rng.randi_range(
			int(plague_rules["duration_turns_min"]), int(plague_rules["duration_turns_max"]))


static func _grain_routes(data: GameData, state: Dictionary, region_id: String) -> int:
	## Grain flows in from trading-partner or own regions that produce grain and
	## are reachable by land adjacency or a shared sea zone (needs a port here).
	## Iterates the immutable grain index, not every settlement — this runs
	## inside every growth AND order breakdown.
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = settlement["owner"]
	var has_port := SettlementRules.effect_max(data, settlement, "port_level") > 0.0
	var routes := 0
	for other_id in data.grain_regions:
		if other_id == region_id:
			continue
		var other = state["settlements"].get(other_id)
		if other == null:
			continue
		if not _trades_with(state, owner, (other as Dictionary)["owner"]):
			continue
		var land := MapRules.are_adjacent(data, region_id, other_id)
		var sea: bool = has_port and MapRules.shared_sea_zone(data, region_id, other_id)
		if land or sea:
			routes += 1
	return routes


static func _trades_with(state: Dictionary, a: String, b: String) -> bool:
	if a == b:
		return true
	var stance: String = state["factions"][a]["diplomacy"].get(b, "neutral")
	return stance in ["trade", "alliance", "protectorate"]
