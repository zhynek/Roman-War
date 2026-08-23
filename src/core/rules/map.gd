class_name MapRules
## Pure graph helpers over the static region map. No campaign state mutation.


static func hops_from(data: GameData, origin: String) -> Dictionary:
	## BFS hop counts over land adjacency from a region. {region_id: hops}
	if not data.regions.has(origin):
		return {}
	var hops := {origin: 0}
	var frontier: Array[String] = [origin]
	while not frontier.is_empty():
		var next_frontier: Array[String] = []
		for region_id in frontier:
			for neighbor in data.regions[region_id].get("adjacent", []):
				if not hops.has(neighbor) and data.regions.has(neighbor):
					hops[neighbor] = hops[region_id] + 1
					next_frontier.append(neighbor)
		frontier = next_frontier
	return hops


static func hops_between(data: GameData, from_region: String, to_region: String) -> int:
	## -1 when unreachable by land.
	var hops := hops_from(data, from_region)
	return int(hops.get(to_region, -1))


static func are_adjacent(data: GameData, a: String, b: String) -> bool:
	return data.regions.get(a, {}).get("adjacent", []).has(b)


static func shared_sea_zone(data: GameData, a: String, b: String) -> bool:
	for zone in data.regions.get(a, {}).get("sea_zones", []):
		if data.regions.get(b, {}).get("sea_zones", []).has(zone):
			return true
	return false


static func coastal(data: GameData, region_id: String) -> bool:
	return not data.regions.get(region_id, {}).get("sea_zones", []).is_empty()
