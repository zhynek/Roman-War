class_name PathfindingRules
## Deterministic weighted pathfinding over the land region graph, priced by
## MovementRules.step_cost — so a mountain crossing genuinely reads as two
## days of plains marching. Pure graph math: no scene nodes, no RNG, and no
## state mutation except advance_march, which only replays
## MovementRules.move_army steps.
##
## Determinism: neighbor lists are sorted before iteration and the frontier
## pops the lexicographically smallest region among equal costs, so the same
## world always yields the same path and a loaded save previews exactly what
## the live game previewed.


static func reachable(data: GameData, state: Dictionary, army_id: String,
		budget: float = -1.0, forced: bool = false, visible: Dictionary = {}) -> Dictionary:
	## {region_id: cost} for every region the army could enter within budget.
	## Default budget is the army's remaining points (stretched by the forced
	## march multiplier when forced); an explicit budget is used verbatim.
	var army: Dictionary = state["armies"][army_id]
	var limit := budget
	if limit < 0.0:
		limit = float(army["movement_left"])
		if forced:
			limit *= float(data.balance["movement"]["forced_march_multiplier"])
	var found := _search(data, state, army, limit, visible)
	var costs: Dictionary = found["dist"].duplicate()
	costs.erase(army["region"])
	return costs


static func best_path(data: GameData, state: Dictionary, army_id: String,
		to_region: String, visible: Dictionary = {}) -> Dictionary:
	## Cheapest route toward a destination, ignoring the per-turn budget:
	## {"path": [step, ...], "legs": [{"region", "cost"}], "cost": total,
	##  "turns": estimate, "blocked_destination": bool}. When the destination
	## itself cannot be entered (an at-war settlement, a visible hostile
	## army), the path halts in the cheapest region beside it and
	## blocked_destination is true — entering combat stays an explicit order.
	## {} when nothing leads toward the destination at all.
	var army: Dictionary = state["armies"][army_id]
	if not data.regions.has(to_region):
		return {}
	if to_region == army["region"]:
		return {"path": [], "legs": [], "cost": 0.0, "turns": 0, "blocked_destination": false}
	var found := _search(data, state, army, INF, visible)
	var dist: Dictionary = found["dist"]
	var target := to_region
	var blocked := false
	if not dist.has(to_region):
		if not _blocked(data, state, String(army["owner"]), to_region, visible):
			return {}
		blocked = true
		var beside := ""
		var beside_cost := INF
		var approaches: Array = data.regions[to_region].get("adjacent", []).duplicate()
		approaches.sort()
		for neighbor in approaches:
			if dist.has(neighbor) and float(dist[neighbor]) < beside_cost - 0.000001:
				beside_cost = float(dist[neighbor])
				beside = String(neighbor)
		if beside == "":
			return {}
		target = beside
		if target == army["region"]:
			return {"path": [], "legs": [], "cost": 0.0, "turns": 0, "blocked_destination": true}
	var path: Array = []
	var walk := target
	while walk != String(army["region"]):
		path.push_front(walk)
		walk = String(found["prev"][walk])
	var legs: Array = []
	for step in path:
		legs.append({"region": step, "cost": MovementRules.step_cost(data, state, String(step))})
	var total := float(dist[target])
	return {"path": path, "legs": legs, "cost": total,
		"turns": estimated_turns(data, state, army_id, total), "blocked_destination": blocked}


static func estimated_turns(data: GameData, state: Dictionary, army_id: String,
		total_cost: float, forced: bool = false) -> int:
	## Turns until arrival: the rest of this turn's points, then full turns.
	if total_cost <= 0.0001:
		return 0
	var army: Dictionary = state["armies"][army_id]
	var multiplier := float(data.balance["movement"]["forced_march_multiplier"]) if forced else 1.0
	var first := float(army["movement_left"]) * multiplier
	if total_cost <= first + 0.0001:
		return 1
	var per_turn := _full_points(data, state, army) * multiplier
	return 1 + int(ceilf((total_cost - first - 0.0001) / per_turn))


static func advance_march(data: GameData, state: Dictionary, army_id: String) -> Dictionary:
	## Walks the army's queued march_path as far as this turn's points allow.
	## Only ever replays MovementRules.move_army — a march can never attack,
	## besiege, or declare war. A step that has become illegal cancels the
	## rest of the path; a step that is merely unaffordable this turn waits.
	## -> {"moved": steps taken, "arrived": bool, "halted": bool}
	var army: Dictionary = state["armies"][army_id]
	var path: Array = army.get("march_path", [])
	var forced := bool(army.get("march_forced", false))
	var moved := 0
	var halted := false
	while not path.is_empty():
		var next := String(path[0])
		if MovementRules.move_army(data, state, army_id, next, forced):
			path.pop_front()
			moved += 1
			continue
		if not MovementRules.can_enter(data, state, army_id, next):
			halted = true
			break
		# Enterable but unaffordable: wait for a fresh turn — unless even a
		# full turn's points could never pay for it (a slowed army facing a
		# mountain), which would stall the march forever.
		var full_budget := _full_points(data, state, army)
		if forced:
			full_budget *= float(data.balance["movement"]["forced_march_multiplier"])
		if MovementRules.step_cost(data, state, next) > full_budget + 0.0001:
			halted = true
		break
	var arrived := not halted and path.is_empty()
	if halted or path.is_empty():
		army.erase("march_path")
		army.erase("march_forced")
	else:
		army["march_path"] = path
	return {"moved": moved, "arrived": arrived, "halted": halted}


static func _search(data: GameData, state: Dictionary, army: Dictionary,
		limit: float, visible: Dictionary) -> Dictionary:
	## Dijkstra from the army's region over enterable regions only.
	var origin := String(army["region"])
	var owner := String(army["owner"])
	var dist := {origin: 0.0}
	var prev := {}
	var done := {}
	while true:
		var current := ""
		var best := INF
		for region_id in dist:
			if done.has(region_id):
				continue
			var cost := float(dist[region_id])
			if cost < best - 0.000001 \
					or (absf(cost - best) <= 0.000001 and (current == "" or String(region_id) < current)):
				best = cost
				current = String(region_id)
		if current == "":
			break
		done[current] = true
		var neighbors: Array = data.regions.get(current, {}).get("adjacent", []).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if not data.regions.has(neighbor):
				continue
			if _blocked(data, state, owner, String(neighbor), visible):
				continue
			var cost := best + MovementRules.step_cost(data, state, String(neighbor))
			if cost > limit + 0.0001:
				continue
			if not dist.has(neighbor) or cost < float(dist[neighbor]) - 0.000001:
				dist[neighbor] = cost
				prev[neighbor] = current
	return {"dist": dist, "prev": prev}


static func _blocked(data: GameData, state: Dictionary, owner: String,
		region_id: String, visible: Dictionary) -> bool:
	## Mirrors MovementRules.can_enter's blocking rules (minus adjacency).
	## An at-war settlement always blocks — taking it is a siege, an explicit
	## order. Hostile armies block only where the owner can see them when a
	## visibility set is supplied: a preview that swerved around an unseen
	## army would leak its position.
	if state["settlements"].has(region_id):
		if DiplomacyRules.at_war(state, owner, String(state["settlements"][region_id]["owner"])):
			return true
	if visible.is_empty() or visible.has(region_id):
		for army in state["armies"].values():
			if army["region"] == region_id and DiplomacyRules.at_war(state, owner, String(army["owner"])):
				return true
	return false


static func _full_points(data: GameData, state: Dictionary, army: Dictionary) -> float:
	## A fresh turn's budget for this army — mirrors MovementRules.reset_movement.
	var points := float(data.balance["movement"]["base_movement_points"])
	if army["general"] != null and state["characters"].has(army["general"]):
		points += CharacterRules.effect_total(data, state["characters"][army["general"]], "movement")
	return maxf(points, 0.5)
