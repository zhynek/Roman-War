class_name ConstructionRules
## Building queues and settlement-tier progression. The settlement level IS the
## government chain tier; upgrading the government building requires the
## population threshold of the next tier, and culture caps gate the top tiers.
##
## `blockers_for` is the single source of truth for "may this settlement build
## that tier". `available_projects` offers a chain iff the next tier has no
## blockers, and BuildingInfo asks the same question of every tier so the UI can
## say *why* a rung is out of reach. One function, two callers, no drift.


static func context(data: GameData, state: Dictionary, region_id: String) -> Dictionary:
	## The per-settlement facts every blocker test needs, computed once so
	## asking about 81 chains does not walk the building list 81 times.
	var settlement: Dictionary = state["settlements"][region_id]
	var queued := {}
	for job in settlement["construction_queue"]:
		queued[job["chain"]] = int(job["turns_left"])
	var temples: Array = []
	for built_chain_id in settlement["buildings"]:
		if data.chains.get(built_chain_id, {}).get("kind", "") == "temple":
			temples.append(built_chain_id)
	temples.sort()
	return {
		"settlement": settlement,
		"region": data.regions[region_id],
		"culture": data.culture_of_faction(settlement["owner"]),
		"level": SettlementRules.settlement_level(data, settlement),
		"queued": queued,
		"queue_order": settlement["construction_queue"],
		"coastal": MapRules.coastal(data, region_id),
		"temples": temples,
	}


static func blockers_for(data: GameData, state: Dictionary, region_id: String,
		chain: Dictionary, tier: int, ctx: Dictionary = {}) -> Array:
	## Everything standing between this settlement and that tier of that chain,
	## as {kind, params} — never prose, which belongs in the glossary data.
	## An empty array means "queue it now". Affordability is deliberately NOT
	## here: available_projects has never filtered on it, and the drawer reports
	## it separately so the button can explain itself instead of going dead.
	if ctx.is_empty():
		ctx = context(data, state, region_id)
	var settlement: Dictionary = ctx["settlement"]
	var culture: String = ctx["culture"]
	var levels: Array = chain["levels"]
	var blockers: Array = []

	if tier < 1 or tier > levels.size():
		return [{"kind": "no_such_tier", "params": {"tier": tier}}]

	var built_tier := int(settlement["buildings"].get(chain["id"], 0))
	if tier <= built_tier:
		return [{"kind": "already_built", "params": {"tier": tier}}]

	if not chain["cultures"].has(culture):
		blockers.append({"kind": "culture", "params": {
			"culture": culture, "chain_cultures": chain["cultures"].duplicate(),
		}})

	if ctx["queued"].has(chain["id"]):
		blockers.append({"kind": "queued", "params": {
			"turns_left": _queue_eta(data, ctx, chain["id"]),
		}})

	if tier > built_tier + 1:
		blockers.append({"kind": "predecessor", "params": {
			"needs": levels[tier - 2]["name"], "tier": tier - 1,
		}})

	if chain.get("requires_coastal", false) and not ctx["coastal"]:
		blockers.append({"kind": "coastal", "params": {}})

	var required_resource: String = chain.get("requires_resource", "")
	if required_resource != "" and not ctx["region"].get("resources", []).has(required_resource):
		blockers.append({"kind": "resource", "params": {"resource": required_resource}})

	if chain["kind"] == "government":
		# The government chain has no min_settlement_level gate: its own tier IS
		# the settlement level, so population is the gate instead.
		if tier > Constants.SETTLEMENT_LEVELS.size():
			blockers.append({"kind": "no_such_tier", "params": {"tier": tier}})
		else:
			var level_name: String = Constants.SETTLEMENT_LEVELS[tier - 1]
			var cap: String = data.cultures[culture]["max_settlement_level"]
			if not Constants.level_at_most(level_name, cap):
				# Unreachable while the validator keeps every government chain
				# exactly as long as its culture's cap; kept so a data change
				# surfaces as a sentence rather than a wrong offer.
				blockers.append({"kind": "culture_cap", "params": {
					"culture": culture, "cap": cap,
				}})
			var needed := data.min_population_for_level(level_name)
			if int(settlement["population"]) < needed:
				blockers.append({"kind": "population", "params": {
					"needs": needed, "have": int(settlement["population"]),
					"level": level_name,
				}})
	else:
		var needs_level: String = levels[tier - 1]["min_settlement_level"]
		if not Constants.level_at_most(needs_level, ctx["level"]):
			blockers.append({"kind": "settlement", "params": {
				"needs": needs_level, "have": ctx["level"],
			}})
		# Only one temple chain per settlement: another god's altar bars this one.
		if chain["kind"] == "temple":
			for other_id in ctx["temples"]:
				if other_id != chain["id"]:
					blockers.append({"kind": "temple", "params": {
						"chain": other_id,
						"name": data.chains[other_id]["name"],
						"god": data.chains[other_id].get("god", ""),
					}})
					break
	return blockers


static func quoted_cost(data: GameData, state: Dictionary, settlement: Dictionary,
		chain: Dictionary, level: Dictionary) -> Dictionary:
	## The price a settlement would actually pay, wonder discounts included, so
	## a ladder showing future tiers cannot quote a number the button disagrees
	## with.
	return {
		"cost": _discounted_cost(data, state, settlement, chain, level),
		"build_turns": _discounted_turns(data, state, String(settlement["owner"]), level),
	}


static func available_projects(data: GameData, state: Dictionary, region_id: String) -> Array:
	## Next buildable level for every chain this settlement's culture can build.
	var settlement: Dictionary = state["settlements"][region_id]
	var ctx := context(data, state, region_id)
	var projects: Array = []

	for chain in data.chains.values():
		var built_tier := int(settlement["buildings"].get(chain["id"], 0))
		var next_tier := built_tier + 1
		if next_tier > chain["levels"].size():
			continue
		if not blockers_for(data, state, region_id, chain, next_tier, ctx).is_empty():
			continue
		var next_level: Dictionary = chain["levels"][built_tier]
		var quote := quoted_cost(data, state, settlement, chain, next_level)

		# A level may require a PRACTICED technique (the era gate generalized).
		var needed_technique: String = next_level.get("requires_technique", "")
		if needed_technique != "" and not KnowledgeRules.adopted(state, settlement["owner"], needed_technique):
			continue

		projects.append({
			"chain": chain["id"],
			"kind": chain["kind"],
			"level_id": next_level["id"],
			"name": next_level["name"],
			"cost": quote["cost"],
			"build_turns": quote["build_turns"],
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


static func _queue_eta(data: GameData, ctx: Dictionary, chain_id: String) -> int:
	## Only the head job ticks, so a second queued chain sits frozen behind it.
	## The honest wait is the running sum up to and including this job.
	var total := 0
	for job in ctx["queue_order"]:
		total += int(job["turns_left"])
		if job["chain"] == chain_id:
			return total
	return total


static func _discounted_cost(data: GameData, state: Dictionary, settlement: Dictionary, chain: Dictionary, level: Dictionary) -> int:
	var faction_id: String = settlement["owner"]
	var cost := float(level["cost"])
	if chain["kind"] == "temple":
		var discount := SettlementRules.faction_owns_wonder_effect(
			data, state, faction_id, "religious_building_discount_pct")
		cost *= 1.0 - discount / 100.0
	# Craft that has been worked out makes everything cheaper to raise, and a
	# labour levy makes it cheaper here — paid in days owed rather than coin.
	cost *= 1.0 + AdvanceRules.effect_total(data, state, faction_id, "build_cost_pct") / 100.0
	cost *= 1.0 + EdictRules.effect(data, settlement, "build_cost_pct") / 100.0
	# Practiced builder's craft (concrete) cheapens every project too: all three
	# effects are authored negative, so each multiplier only shrinks the bill.
	# The early return the merge left here skipped this one entirely.
	cost *= 1.0 + KnowledgeRules.faction_effect_total(data, state, faction_id, "build_cost_pct") / 100.0
	return maxi(0, int(round(cost)))


static func _discounted_turns(data: GameData, state: Dictionary, faction_id: String, level: Dictionary) -> int:
	var turns := int(level["build_turns"])
	var reduction := int(SettlementRules.faction_owns_wonder_effect(
		data, state, faction_id, "build_time_reduction_turns")) \
		+ int(AdvanceRules.effect_total(data, state, faction_id, "build_turns_reduction"))
	if reduction > 0:
		var min_for_reduction := int(SettlementRules.faction_owns_wonder_effect(
			data, state, faction_id, "build_time_reduction_min_turns"))
		if turns >= maxi(min_for_reduction, 2):
			turns = maxi(1, turns - reduction)
	return turns
