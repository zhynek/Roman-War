class_name SettlementRules
## Shared settlement queries used by growth, order, economy, construction.


static func settlement_level(data: GameData, settlement: Dictionary) -> String:
	## Settlement level IS the government building tier (index 1 = village).
	var owner_culture := data.culture_of_faction(settlement["owner"])
	var government := data.chain_for(owner_culture, "government")
	var tier := 1
	if not government.is_empty():
		tier = maxi(1, int(settlement["buildings"].get(government["id"], 1)))
	else:
		# Foreign-culture government building present from conquest; use its tier.
		for chain_id in settlement["buildings"]:
			if data.chains.has(chain_id) and data.chains[chain_id]["kind"] == "government":
				tier = maxi(tier, int(settlement["buildings"][chain_id]))
	return Constants.SETTLEMENT_LEVELS[mini(tier - 1, Constants.SETTLEMENT_LEVELS.size() - 1)]


static func effect_total(data: GameData, settlement: Dictionary, effect: String) -> float:
	## Sum an effect key across every built building level up to the built tier.
	## Effects are cumulative within a chain (a level-3 market includes the
	## bonuses of levels 1-2), matching how the data tables are authored
	## (each level lists only its increment).
	var total := 0.0
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		var built_tier := int(settlement["buildings"][chain_id])
		for i in range(mini(built_tier, chain["levels"].size())):
			total += float(chain["levels"][i].get("effects", {}).get(effect, 0.0))
	return total


static func effect_max(data: GameData, settlement: Dictionary, effect: String) -> float:
	## Highest single value of an effect key (for tier-like effects such as
	## wall_level, road_level, port_level — these are not cumulative).
	var best := 0.0
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		var built_tier := int(settlement["buildings"][chain_id])
		for i in range(mini(built_tier, chain["levels"].size())):
			best = maxf(best, float(chain["levels"][i].get("effects", {}).get(effect, 0.0)))
	return best


static func garrison_soldiers(data: GameData, settlement: Dictionary) -> int:
	var soldiers := 0
	for unit in settlement["garrison"]:
		var template: Dictionary = data.units.get(unit["template"], {})
		soldiers += int(ceil(int(template.get("soldiers", 0)) * int(unit["strength_pct"]) / 100.0))
	return soldiers


static func culture_penalty_pct(data: GameData, state: Dictionary, region_id: String) -> float:
	## Penalty proportional to the share of buildings belonging to foreign cultures.
	var settlement: Dictionary = state["settlements"][region_id]
	var owner_culture := data.culture_of_faction(settlement["owner"])
	var cancelled_cultures := _cancelled_cultures(data, state, settlement["owner"])
	var total := 0
	var foreign := 0
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		total += 1
		var chain_cultures: Array = chain["cultures"]
		if not chain_cultures.has(owner_culture):
			var all_cancelled := true
			for culture in chain_cultures:
				if not cancelled_cultures.has(culture):
					all_cancelled = false
			if not all_cancelled:
				foreign += 1
	if total == 0:
		return 0.0
	return float(foreign) / float(total) * float(data.balance["public_order"]["culture_penalty_scale"])


static func _cancelled_cultures(data: GameData, state: Dictionary, faction_id: String) -> Array:
	## Wonders can cancel the culture penalty for buildings of one culture.
	var cancelled: Array = []
	for wonder_id in data.wonders:
		var wonder: Dictionary = data.wonders[wonder_id]
		var wonder_region: String = wonder["region"]
		if not state["settlements"].has(wonder_region):
			continue
		if state["settlements"][wonder_region]["owner"] != faction_id:
			continue
		var culture = wonder.get("effects", {}).get("cancel_culture_penalty_culture")
		if culture != null:
			cancelled.append(culture)
	return cancelled


static func faction_owns_wonder_effect(data: GameData, state: Dictionary, faction_id: String, effect: String) -> float:
	var total := 0.0
	for wonder_id in data.wonders:
		var wonder: Dictionary = data.wonders[wonder_id]
		if not state["settlements"].has(wonder["region"]):
			continue
		if state["settlements"][wonder["region"]]["owner"] != faction_id:
			continue
		total += float(wonder.get("effects", {}).get(effect, 0.0))
	return total
