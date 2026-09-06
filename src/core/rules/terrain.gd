class_name TerrainRules
## Military topology. Political adjacency remains separate for border relations.
## Every route constraint is authored once and shared by rules and presentation.

static func edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

static func crossing_kind(data: GameData, a: String, b: String) -> String:
	return String(data.terrain_crossings.get(edge_key(a, b), {}).get("kind", ""))

static func land_connection(data: GameData, a: String, b: String) -> bool:
	return MapRules.are_adjacent(data, a, b) and not crossing_kind(data, a, b) in ["river", "ridge", "water"]

static func crossing_cost(data: GameData, a: String, b: String) -> float:
	return float(data.balance.get("terrain_routes", {}).get("crossing_cost", {}).get(crossing_kind(data, a, b), 0.0))

static func crossing_defense(data: GameData, a: String, b: String) -> float:
	return float(data.balance.get("terrain_routes", {}).get("crossing_defense_pct", {}).get(crossing_kind(data, a, b), 0.0))

static func supply_regions(data: GameData, state: Dictionary, faction: String) -> Dictionary:
	## Ground supply from the capital through friendly or allied territory.
	## Enemy field forces and besieged towns interrupt a road just like a ridge.
	var origin := String(state["factions"].get(faction, {}).get("capital", ""))
	var reached := {}
	var frontier: Array = [origin]
	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		if reached.has(current) or not state["settlements"].has(current):
			continue
		var settlement: Dictionary = state["settlements"][current]
		var stance := DiplomacyRules.stance_between(state, faction, settlement["owner"])
		if not stance in ["self", "alliance", "protectorate"] or settlement.get("siege") != null:
			continue
		if MovementRules.hostile_army_in(state, faction, current):
			continue
		reached[current] = true
		var neighbors: Array = data.regions.get(current, {}).get("adjacent", []).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if land_connection(data, current, neighbor):
				frontier.append(neighbor)
	return reached
