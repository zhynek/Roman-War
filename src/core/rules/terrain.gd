class_name TerrainRules
## Military topology. Political adjacency remains separate for border relations.
## Every route constraint is authored once and shared by rules and presentation.

static func edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

static func crossing_kind(data: GameData, a: String, b: String, state: Dictionary = {}) -> String:
	if state.get("waterworks", {}).get("bridges", {}).has(edge_key(a, b)):
		return "bridge"
	return String(data.terrain_crossings.get(edge_key(a, b), {}).get("kind", ""))

static func land_connection(data: GameData, a: String, b: String, state: Dictionary = {}) -> bool:
	return MapRules.are_adjacent(data, a, b) and not crossing_kind(data, a, b, state) in ["river", "ridge", "water"]

static func crossing_cost(data: GameData, a: String, b: String, state: Dictionary = {}) -> float:
	return float(data.balance.get("terrain_routes", {}).get("crossing_cost", {}).get(crossing_kind(data, a, b, state), 0.0))

static func crossing_defense(data: GameData, a: String, b: String, state: Dictionary = {}) -> float:
	return float(data.balance.get("terrain_routes", {}).get("crossing_defense_pct", {}).get(crossing_kind(data, a, b, state), 0.0))

static func supply_regions(data: GameData, state: Dictionary, faction: String, observed_only: bool = false) -> Dictionary:
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
		if state["armies"].values().any(func(a): return a["region"] == current and DiplomacyRules.at_war(state, faction, a["owner"]) and (not observed_only or VisibilityRules.army_visible(data, state, faction, a))):
			continue
		reached[current] = true
		var neighbors: Array = data.regions.get(current, {}).get("adjacent", []).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if land_connection(data, current, neighbor, state):
				frontier.append(neighbor)
	return reached
