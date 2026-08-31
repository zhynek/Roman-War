class_name AiAssess
## Deterministic situation queries shared by the AI behavior modules: force
## power estimates, threat detection, reachability over the region graph, and
## expansion target scoring. Pure reads — nothing here mutates state or draws
## randomness. Power estimates use BattleResolver.force_strength (the shared
## interface estimate), never resolver internals.

static var _traversal_cache := {}  # per-GameData augmented neighbor table


static func sea_hop_cost(data: GameData) -> int:
	## Weight of one sea crossing in route planning, derived from the same
	## balance constant MovementRules.sea_move_army charges — so tuning
	## movement.sea_move_cost retunes AI route planning with it.
	return maxi(1, int(round(float(data.balance["movement"]["sea_move_cost"]))))


static func unit_power(data: GameData, units: Array) -> float:
	var experience_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	return BattleResolver.force_strength(data, units, null, experience_pct)


static func army_power(data: GameData, state: Dictionary, army: Dictionary) -> float:
	var experience_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	return BattleResolver.force_strength(
		data, army["units"], CombatRules.general_profile(data, state, army), experience_pct)


static func garrison_power(data: GameData, state: Dictionary, region_id: String) -> float:
	var settlement: Dictionary = state["settlements"][region_id]
	var experience_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	var governor_profile = null
	var governor = settlement["governor"]
	if governor != null and state["characters"].has(governor):
		governor_profile = CharacterRules.battle_profile(data, state["characters"][governor])
	return BattleResolver.force_strength(data, settlement["garrison"], governor_profile, experience_pct)


static func assault_defense_power(data: GameData, state: Dictionary, region_id: String) -> float:
	## Garrison power as an attacker planning an assault should weigh it:
	## scaled by terrain and wall-tier defense multipliers from balance data.
	var battle_rules: Dictionary = data.balance["battle"]
	var settlement: Dictionary = state["settlements"][region_id]
	var power := garrison_power(data, state, region_id)
	power *= float(battle_rules["terrain_defense_multiplier"].get(
		data.regions[region_id]["terrain"], 1.0))
	var wall_level := int(SettlementRules.effect_max(data, settlement, "wall_level"))
	var wall_multipliers: Array = battle_rules["wall_defense_multiplier"]
	power *= float(wall_multipliers[mini(wall_level, wall_multipliers.size() - 1)])
	return power


static func sally_defense_power(data: GameData, state: Dictionary, region_id: String) -> float:
	## Garrison power in the forced last sally of a starve-out: terrain, the
	## wall tier reduced one step (starving defenders man them thinly), and the
	## sally strength bonus — the worst battle a besieger must survive.
	var battle_rules: Dictionary = data.balance["battle"]
	var settlement: Dictionary = state["settlements"][region_id]
	var power := garrison_power(data, state, region_id)
	power *= float(battle_rules["terrain_defense_multiplier"].get(
		data.regions[region_id]["terrain"], 1.0))
	var wall_level := maxi(0, int(SettlementRules.effect_max(data, settlement, "wall_level")) - 1)
	var wall_multipliers: Array = battle_rules["wall_defense_multiplier"]
	power *= float(wall_multipliers[mini(wall_level, wall_multipliers.size() - 1)])
	return power * (1.0 + float(data.balance["siege"]["sally_strength_bonus_pct"]) / 100.0)


static func field_defense_power(data: GameData, state: Dictionary, army: Dictionary) -> float:
	## An army's power when defending its current region (terrain multiplier in).
	var battle_rules: Dictionary = data.balance["battle"]
	return army_power(data, state, army) * float(battle_rules["terrain_defense_multiplier"].get(
		data.regions[army["region"]]["terrain"], 1.0))


static func faction_power(data: GameData, state: Dictionary, faction_id: String) -> float:
	var power := 0.0
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army["owner"] == faction_id:
			power += army_power(data, state, army)
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] == faction_id:
			power += garrison_power(data, state, region_id)
	return power


static func enemies_of(state: Dictionary, faction_id: String) -> Array:
	## Living factions this one is at war with, sorted by id.
	var enemies: Array = []
	var other_ids: Array = state["factions"].keys()
	other_ids.sort()
	for other_id in other_ids:
		if other_id == faction_id or not state["factions"][other_id]["alive"]:
			continue
		if DiplomacyRules.at_war(state, faction_id, other_id):
			enemies.append(other_id)
	return enemies


static func passable(state: Dictionary, faction_id: String, region_id: String) -> bool:
	## A region this faction's armies may stand in: unsettled, or settled by
	## anyone it is not at war with. (Hostile field armies are handled at move
	## time — they block a step, not the route plan.)
	if not state["settlements"].has(region_id):
		return true
	return not DiplomacyRules.at_war(state, faction_id, state["settlements"][region_id]["owner"])


static func distance_map(data: GameData, state: Dictionary, faction_id: String, sources: Array) -> Dictionary:
	## Cheapest traversal cost from the nearest of the source regions, over
	## regions this faction can pass: land steps cost 1, a sea crossing
	## (coastal to coastal on the same or an adjacent zone) costs
	## sea_hop_cost(), mirroring MovementRules.sea_move_army connectivity.
	## Sources seed the search even when hostile (a goal region is reached by
	## besieging from next door) — but only over land: an army cannot SAIL
	## into a hostile region, so sea edges out of an impassable source would
	## advertise approaches no army can finish (they froze real campaigns on
	## coastal targets). Returns {region_id: cost}; absent means unreachable.
	var cost := {}
	var frontier: Array = []
	for source in sources:
		if data.regions.has(source):
			cost[source] = 0
			frontier.append(source)
	var table := _traversal_table(data)
	while not frontier.is_empty():
		frontier.sort()  # canonical expansion order
		var next_frontier: Array = []
		for region_id in frontier:
			var here := int(cost[region_id])
			var land_only := not passable(state, faction_id, region_id)
			for step in table[region_id]:
				if land_only and step["sea"]:
					continue
				var neighbor: String = step["region"]
				if not passable(state, faction_id, neighbor):
					continue
				var through := here + int(step["cost"])
				if not cost.has(neighbor) or through < int(cost[neighbor]):
					cost[neighbor] = through
					next_frontier.append(neighbor)
		frontier = next_frontier
	return cost


static func _traversal_table(data: GameData) -> Dictionary:
	## {region_id: [{region, cost, sea}, ...]} — land adjacency at cost 1 plus
	## sea crossings at sea_hop_cost(). The map never changes after load, so
	## the table is built once per GameData instance.
	var cache_key := data.get_instance_id()
	if _traversal_cache.has(cache_key):
		return _traversal_cache[cache_key]
	var crossing := sea_hop_cost(data)
	var table := {}
	var region_ids: Array = data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		var steps: Array = []
		for neighbor in data.regions[region_id].get("adjacent", []):
			if data.regions.has(neighbor):
				steps.append({"region": neighbor, "cost": 1, "sea": false})
		var zones: Array = data.regions[region_id].get("sea_zones", [])
		if not zones.is_empty():
			var reachable_zones := {}
			for zone in zones:
				reachable_zones[zone] = true
				for adjacent_zone in data.sea_zones.get(zone, {}).get("adjacent", []):
					reachable_zones[adjacent_zone] = true
			for other_id in region_ids:
				if other_id == region_id:
					continue
				for zone in data.regions[other_id].get("sea_zones", []):
					if reachable_zones.has(zone):
						steps.append({"region": other_id, "cost": crossing, "sea": true})
						break
		table[region_id] = steps
	if _traversal_cache.size() > 8:
		_traversal_cache.clear()
	_traversal_cache[cache_key] = table
	return table


static func sea_neighbors(data: GameData, region_id: String) -> Array:
	## Regions one legal sea crossing away (shared or adjacent zone, both
	## coastal), in sorted order — exactly the crossings sea_move_army allows.
	var found: Array = []
	for step in _traversal_table(data)[region_id]:
		if step["sea"]:
			found.append(step["region"])
	return found


static func owned_regions(state: Dictionary, faction_id: String) -> Array:
	var owned: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] == faction_id:
			owned.append(region_id)
	return owned


static func hostile_armies_in(state: Dictionary, faction_id: String, region_id: String) -> Array:
	## Ids of at-war armies standing in a region, sorted.
	var found: Array = []
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army["region"] == region_id and DiplomacyRules.at_war(state, faction_id, army["owner"]):
			found.append(army_id)
	return found


static func hostile_power_in(data: GameData, state: Dictionary, faction_id: String, region_id: String) -> float:
	var power := 0.0
	for army_id in hostile_armies_in(state, faction_id, region_id):
		power += field_defense_power(data, state, state["armies"][army_id])
	return power


static func threat_level(data: GameData, state: Dictionary, region_id: String) -> String:
	## "threatened": hostile army in or next to the settlement (or a siege).
	## "frontier": borders territory of a faction the owner is at war with.
	## "interior": everything else.
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = settlement["owner"]
	if settlement["siege"] != null:
		return "threatened"
	if not hostile_armies_in(state, owner, region_id).is_empty():
		return "threatened"
	var frontier := false
	for neighbor in data.regions[region_id].get("adjacent", []):
		if not data.regions.has(neighbor):
			continue
		if not hostile_armies_in(state, owner, neighbor).is_empty():
			return "threatened"
		if state["settlements"].has(neighbor) \
				and DiplomacyRules.at_war(state, owner, state["settlements"][neighbor]["owner"]):
			frontier = true
	return "frontier" if frontier else "interior"


static func choose_target(data: GameData, state: Dictionary, faction_id: String) -> String:
	## The settlement this faction should try to take: an enemy-held region
	## whose approach (an adjacent region the faction can stand in) lies within
	## ai.target_max_hops of its territory. A senate mission target is preferred
	## when valid; otherwise the nearest candidate wins, the least defended
	## (garrison scaled by terrain and walls) breaking distance ties, then
	## region id. "" means no reachable target.
	var max_hops := int(data.balance["ai"]["target_max_hops"])
	var reach := distance_map(data, state, faction_id, owned_regions(state, faction_id))

	var mission = state["factions"][faction_id].get("mission")
	if mission != null:
		var mission_target: String = mission.get("target_region", "")
		if mission_target != "" and state["settlements"].has(mission_target) \
				and DiplomacyRules.at_war(state, faction_id, state["settlements"][mission_target]["owner"]) \
				and approach_cost(data, state, faction_id, mission_target, reach) <= max_hops:
			return mission_target

	var best := ""
	var best_cost := 1 << 30
	var best_power := 0.0
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if not DiplomacyRules.at_war(state, faction_id, state["settlements"][region_id]["owner"]):
			continue
		var cost := approach_cost(data, state, faction_id, region_id, reach)
		if cost > max_hops:
			continue
		var power := assault_defense_power(data, state, region_id)
		if best == "" or cost < best_cost or (cost == best_cost and power < best_power):
			best = region_id
			best_cost = cost
			best_power = power
	return best


static func approach_cost(data: GameData, state: Dictionary, faction_id: String, goal: String, reach: Dictionary) -> int:
	## Cost to put an army next to a (hostile) goal region, given a
	## distance_map from this faction's own territory: cheapest reached
	## passable land neighbor of the goal, plus the final step. A goal the
	## faction can stand in directly (its own or a neutral region) costs its
	## own reach value.
	var unreachable := 1 << 30
	if passable(state, faction_id, goal):
		return int(reach.get(goal, unreachable))
	var best := unreachable
	for neighbor in data.regions.get(goal, {}).get("adjacent", []):
		if not data.regions.has(neighbor) or not passable(state, faction_id, neighbor):
			continue
		var cost := int(reach.get(neighbor, unreachable))
		if cost < unreachable:
			best = mini(best, cost + 1)
	return best
