class_name ConstructionRules
## Building queues and settlement-tier progression. The settlement level IS the
## government chain tier; upgrading the government building requires the
## population threshold of the next tier, and culture caps gate the top tiers.


static func available_projects(data: GameData, state: Dictionary, region_id: String) -> Array:
	## Next buildable level for every chain this settlement's culture can build.
	var settlement: Dictionary = state["settlements"][region_id]
	var region: Dictionary = data.regions[region_id]
	var culture := data.culture_of_faction(settlement["owner"])
	var level := SettlementRules.settlement_level(data, settlement)
	var projects: Array = []

	var queued := {}
	for job in settlement["construction_queue"]:
		queued[job["chain"]] = true

	for chain in data.chains.values():
		if not chain["cultures"].has(culture):
			continue
		if queued.has(chain["id"]):
			continue
		if chain.get("requires_coastal", false) and not MapRules.coastal(data, region_id):
			continue
		var required_resource: String = chain.get("requires_resource", "")
		if required_resource != "" and not region.get("resources", []).has(required_resource):
			continue

		var built_tier := int(settlement["buildings"].get(chain["id"], 0))
		if built_tier >= chain["levels"].size():
			continue
		var next_level: Dictionary = chain["levels"][built_tier]

		if chain["kind"] == "government":
			if not _government_upgrade_allowed(data, settlement, culture, built_tier):
				continue
		else:
			if not Constants.level_at_most(next_level["min_settlement_level"], level):
				continue
			# Only one temple chain per settlement: skip other gods once one is built.
			if chain["kind"] == "temple" and _has_other_temple(data, settlement, chain["id"]):
				continue

		projects.append({
			"chain": chain["id"],
			"kind": chain["kind"],
			"level_id": next_level["id"],
			"name": next_level["name"],
			"cost": _discounted_cost(data, state, settlement["owner"], chain, next_level),
			"build_turns": _discounted_turns(data, state, settlement["owner"], next_level),
		})
	return projects


static func queue_project(data: GameData, state: Dictionary, region_id: String, chain_id: String) -> bool:
	var settlement: Dictionary = state["settlements"][region_id]
	var faction: Dictionary = state["factions"][settlement["owner"]]
	for project in available_projects(data, state, region_id):
		if project["chain"] != chain_id:
			continue
		if int(faction["treasury"]) < int(project["cost"]):
			return false
		faction["treasury"] = int(faction["treasury"]) - int(project["cost"])
		settlement["construction_queue"].append({
			"chain": chain_id,
			"turns_left": int(project["build_turns"]),
		})
		return true
	return false


static func demolish(data: GameData, state: Dictionary, region_id: String, chain_id: String) -> bool:
	## Demolishing (a tier at a time) is how culture penalty is worked off.
	## Farms and government chains cannot be demolished.
	var settlement: Dictionary = state["settlements"][region_id]
	var chain: Dictionary = data.chains.get(chain_id, {})
	if chain.is_empty() or chain.get("indestructible", false) or chain["kind"] == "government":
		return false
	var tier := int(settlement["buildings"].get(chain_id, 0))
	if tier <= 0:
		return false
	if tier == 1:
		settlement["buildings"].erase(chain_id)
	else:
		settlement["buildings"][chain_id] = tier - 1
	return true


static func advance_queues(data: GameData, state: Dictionary, region_id: String) -> Array:
	## Progress construction one turn; returns completed level ids.
	var settlement: Dictionary = state["settlements"][region_id]
	var completed: Array = []
	var remaining: Array = []
	var first := true
	for job in settlement["construction_queue"]:
		if first:
			job["turns_left"] = int(job["turns_left"]) - 1
			first = false
		if int(job["turns_left"]) <= 0:
			var chain: Dictionary = data.chains[job["chain"]]
			var new_tier := int(settlement["buildings"].get(job["chain"], 0)) + 1
			settlement["buildings"][job["chain"]] = mini(new_tier, chain["levels"].size())
			completed.append(chain["levels"][new_tier - 1]["id"])
		else:
			remaining.append(job)
	settlement["construction_queue"] = remaining
	return completed


static func _government_upgrade_allowed(data: GameData, settlement: Dictionary, culture: String, built_tier: int) -> bool:
	var next_tier := built_tier + 1
	if next_tier > Constants.SETTLEMENT_LEVELS.size():
		return false
	var next_level_name: String = Constants.SETTLEMENT_LEVELS[next_tier - 1]
	var cap: String = data.cultures[culture]["max_settlement_level"]
	if not Constants.level_at_most(next_level_name, cap):
		return false
	return int(settlement["population"]) >= data.min_population_for_level(next_level_name)


static func _has_other_temple(data: GameData, settlement: Dictionary, chain_id: String) -> bool:
	for built_chain_id in settlement["buildings"]:
		if built_chain_id == chain_id:
			continue
		if data.chains.get(built_chain_id, {}).get("kind", "") == "temple":
			return true
	return false


static func _discounted_cost(data: GameData, state: Dictionary, faction_id: String, chain: Dictionary, level: Dictionary) -> int:
	var cost := float(level["cost"])
	if chain["kind"] == "temple":
		var discount := SettlementRules.faction_owns_wonder_effect(
			data, state, faction_id, "religious_building_discount_pct")
		cost *= 1.0 - discount / 100.0
	return int(round(cost))


static func _discounted_turns(data: GameData, state: Dictionary, faction_id: String, level: Dictionary) -> int:
	var turns := int(level["build_turns"])
	var reduction := int(SettlementRules.faction_owns_wonder_effect(
		data, state, faction_id, "build_time_reduction_turns"))
	if reduction > 0:
		var min_for_reduction := int(SettlementRules.faction_owns_wonder_effect(
			data, state, faction_id, "build_time_reduction_min_turns"))
		if turns >= maxi(min_for_reduction, 2):
			turns = maxi(1, turns - reduction)
	return turns
