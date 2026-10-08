class_name AdvisorRules
extends RefCounted
## Permanent, player-only unlocks. Reconcile only at creation, legacy migration
## or season close. Status is a pure read; neither path consumes campaign RNG.

static func status(data: GameData, state: Dictionary, advisor_id: String) -> Dictionary:
	var spec: Dictionary = data.advisors.get(advisor_id, {})
	if spec.is_empty():return {}
	var requirement: Dictionary = spec.unlock
	var best_level := 0
	var best_region := ""
	var required_building := ""
	var regions: Array = state.get("settlements", {}).keys()
	regions.sort()
	for region in regions:
		var settlement: Dictionary = state.settlements[region]
		if settlement.owner != state.player_faction:continue
		var chains: Array = settlement.get("buildings", {}).keys()
		chains.sort()
		for chain_id in chains:
			var chain: Dictionary = data.chains.get(chain_id, {})
			if chain.get("kind", "") != requirement.building_kind:continue
			var level := mini(int(settlement.buildings[chain_id]), chain.levels.size())
			if level > best_level:
				best_level = level
				best_region = region
				if chain.levels.size() >= int(requirement.min_level):
					required_building = chain.levels[int(requirement.min_level)-1].name
	var unlocked: Dictionary = state.get("advisor_unlocks", {}).get(advisor_id, {})
	return {"id":advisor_id, "available":not unlocked.is_empty(),
		"qualifies":best_level >= int(requirement.min_level), "level":best_level,
		"required_level":int(requirement.min_level), "region":best_region,
		"required_building":required_building, "unlocked":unlocked.duplicate(true)}

static func reconcile(data: GameData, state: Dictionary) -> void:
	if not state.has("advisor_unlocks"):state.advisor_unlocks = {}
	var ids: Array = data.advisors.keys()
	ids.sort()
	for id in ids:
		if state.advisor_unlocks.has(id):continue
		var result := status(data,state,id)
		if result.qualifies:
			state.advisor_unlocks[id] = {"turn":int(state.turn),"region":result.region}
