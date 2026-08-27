class_name PathfindingRules
## Multi-region routes over the land adjacency graph, priced exactly like
## single steps are: MovementRules.step_cost (destination terrain, cut by the
## destination's roads). Pure and deterministic — no RNG, every tie broken by
## sorted region id — so a loaded save previews and marches exactly like the
## live game.
##
## Fog rule: hostility blocks a route only inside the caller's visible set —
## a hidden army, or the unseen owner of a fogged settlement, must never bend
## a preview, or the route itself would leak what fog hides. The actual march
## still halts on the real world, because every executed leg goes through
## MovementRules.


static func reachable(data: GameData, state: Dictionary, army_id: String, budget: float, forced: bool, visible: Dictionary) -> Dictionary:
	## {region_id: cumulative cost} for every region the army could enter with
	## `budget` movement points, its own region excluded. Budget is the raw
	## movement_left; forced march stretches it exactly as move_army does.
	if forced:
		budget *= float(data.balance["movement"]["forced_march_multiplier"])
	var search := _dijkstra(data, state, army_id, visible)
	var costs: Dictionary = search["costs"]
	var origin: String = state["armies"][army_id]["region"]
	var in_range := {}
	for region_id in costs:
		if region_id != origin and float(costs[region_id]) <= budget + 0.0001:
			in_range[region_id] = costs[region_id]
	return in_range


static func best_path(data: GameData, state: Dictionary, army_id: String, to_region: String, forced: bool, visible: Dictionary) -> Dictionary:
	## The cheapest multi-turn land route to a destination.
	##   reachable            there is a path with at least one marchable leg
	##   path                 region ids to enter, in order (start excluded);
	##                        when the destination is blocked it ends on the
	##                        cheapest adjacent approach region instead
	##   legs                 [{region, cost}] per entry in path
	##   cost                 total cost of path
	##   turns                estimate to walk it (1 = arrives this turn)
	##   blocked_destination  the destination itself cannot be entered — a
	##                        visibly hostile settlement or army
	var result := {
		"reachable": false, "path": [], "legs": [], "cost": 0.0, "turns": 0,
		"blocked_destination": false,
	}
	var army: Dictionary = state["armies"][army_id]
	if not data.regions.has(to_region) or to_region == army["region"]:
		return result
	var search := _dijkstra(data, state, army_id, visible)
	var costs: Dictionary = search["costs"]
	var target := to_region
	if not costs.has(to_region):
		if _enterable(data, state, army, to_region, visible):
			return result  # enterable but no land route reaches it
		result["blocked_destination"] = true
		target = _cheapest_approach(data, costs, to_region)
		if target == "":
			return result  # blocked, and no way to even stand next to it
	if target == army["region"]:
		return result  # already standing on the approach; nothing to march
	var path: Array = []
	var walk := target
	while walk != army["region"]:
		path.push_front(walk)
		walk = search["previous"][walk]
	var legs: Array = []
	var previous_cost := 0.0
	for region_id in path:
		legs.append({"region": region_id, "cost": float(costs[region_id]) - previous_cost})
		previous_cost = float(costs[region_id])
	var leg_costs: Array = []
	for leg in legs:
		leg_costs.append(leg["cost"])
	result["reachable"] = true
	result["path"] = path
	result["legs"] = legs
	result["cost"] = float(costs[target])
	result["turns"] = estimated_turns(data, state, army_id, leg_costs, forced)
	return result


static func estimated_turns(data: GameData, state: Dictionary, army_id: String, leg_costs: Array, forced: bool) -> int:
	## Turns to walk the legs in order: 1 means the whole route fits the
	## movement the army has right now. Movement is spent leg by leg, exactly
	## as advance_march spends it — points left over when the next leg does
	## not fit are LOST at the turn boundary (reset_movement overwrites them),
	## so this walks the legs rather than dividing a continuous total. The
	## per-turn budget mirrors reset_movement (general bonus, 0.5 floor) and
	## the forced-march multiplier.
	var army: Dictionary = state["armies"][army_id]
	var per_turn := float(data.balance["movement"]["base_movement_points"])
	if army["general"] != null and state["characters"].has(army["general"]):
		per_turn += CharacterRules.effect_total(data, state["characters"][army["general"]], "movement")
	per_turn = maxf(per_turn, 0.5)
	var budget := float(army["movement_left"])
	if forced:
		var multiplier := float(data.balance["movement"]["forced_march_multiplier"])
		per_turn *= multiplier
		budget *= multiplier
	var turns := 1
	for leg_cost_value in leg_costs:
		var leg_cost := float(leg_cost_value)
		if leg_cost <= budget + 0.0001:
			budget -= leg_cost
			continue
		if leg_cost > per_turn + 0.0001:
			return 999  # no fresh turn could ever pay this leg; the march would cancel
		turns += 1
		budget = per_turn - leg_cost
	return turns


static func advance_march(data: GameData, state: Dictionary, army_id: String) -> Dictionary:
	## Walk the army's stored march order with the movement it has, one leg at
	## a time, strictly through MovementRules.move_army — an auto-march can
	## only ever do what a plain move can, so it can never attack, besiege, or
	## declare a war. Running out of points keeps the order for next turn; a
	## leg that stops being enterable (a war began, an enemy army appeared)
	## cancels what remains. Returns {} when the army has no march order,
	## else a report entry for the turn log.
	var army: Dictionary = state["armies"][army_id]
	var path: Array = army.get("march_path", [])
	if path.is_empty():
		return {}
	var siege = state["settlements"].get(army["region"], {}).get("siege")
	if siege != null and siege.get("besieger", "") == army_id:
		# A stale order must never walk a besieger away from his own siege
		# (the facade clears orders on hostile actions; this is the backstop).
		return _finish_march(army, army_id, 0, false, true)
	var forced := bool(army.get("march_forced", false))
	var steps := 0
	while not path.is_empty():
		var next_region := String(path[0])
		if MovementRules.move_army(data, state, army_id, next_region, forced):
			path.remove_at(0)
			steps += 1
			continue
		if not MovementRules.can_enter(data, state, army_id, next_region):
			return _finish_march(army, army_id, steps, false, true)
		if steps == 0 and MovementRules.step_cost(data, state, next_region) > _full_turn_budget(data, state, army, forced) + 0.0001:
			# Even a fresh turn could never pay for this leg (a crippled
			# general's 0.5-point floor against mountains) — cancel rather
			# than stall silently forever.
			return _finish_march(army, army_id, steps, false, true)
		break  # merely out of movement — the order resumes next turn
	if path.is_empty():
		return _finish_march(army, army_id, steps, true, false)
	return {
		"army": army_id, "owner": army["owner"], "region": army["region"],
		"steps": steps, "arrived": false, "halted": false,
	}


static func _finish_march(army: Dictionary, army_id: String, steps: int, arrived: bool, halted: bool) -> Dictionary:
	army.erase("march_path")
	army.erase("march_forced")
	return {
		"army": army_id, "owner": army["owner"], "region": army["region"],
		"steps": steps, "arrived": arrived, "halted": halted,
	}


static func _full_turn_budget(data: GameData, state: Dictionary, army: Dictionary, forced: bool) -> float:
	var points := float(data.balance["movement"]["base_movement_points"])
	if army["general"] != null and state["characters"].has(army["general"]):
		points += CharacterRules.effect_total(data, state["characters"][army["general"]], "movement")
	points = maxf(points, 0.5)
	if forced:
		points *= float(data.balance["movement"]["forced_march_multiplier"])
	return points


static func _dijkstra(data: GameData, state: Dictionary, army_id: String, visible: Dictionary) -> Dictionary:
	## Cheapest cost from the army's region to every enterable region.
	## {costs: {region: cost}, previous: {region: region}}. Iteration is over
	## sorted ids throughout, so equal-cost ties always resolve the same way.
	var army: Dictionary = state["armies"][army_id]
	var origin: String = army["region"]
	var costs := {origin: 0.0}
	var previous := {}
	var done := {}
	while true:
		var current := ""
		var current_cost := INF
		var open_ids: Array = costs.keys()
		open_ids.sort()
		for region_id in open_ids:
			if not done.has(region_id) and float(costs[region_id]) < current_cost:
				current_cost = float(costs[region_id])
				current = region_id
		if current == "":
			break
		done[current] = true
		var neighbors: Array = data.regions[current].get("adjacent", []).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if done.has(neighbor) or not data.regions.has(neighbor):
				continue
			if not _enterable(data, state, army, neighbor, visible):
				continue
			var next_cost: float = current_cost + MovementRules.step_cost(data, state, neighbor)
			if next_cost < float(costs.get(neighbor, INF)) - 0.0001:
				costs[neighbor] = next_cost
				previous[neighbor] = current
	return {"costs": costs, "previous": previous}


static func _enterable(data: GameData, state: Dictionary, army: Dictionary, region_id: String, visible: Dictionary) -> bool:
	## Mirrors MovementRules.can_enter, except NOTHING outside the caller's
	## visible set may block: routing around a fogged at-war settlement or a
	## hidden army would leak what fog hides. The executed march still halts
	## on the real state, because every leg goes through MovementRules.
	if not visible.has(region_id):
		return true
	var owner: String = army["owner"]
	if state["settlements"].has(region_id):
		if DiplomacyRules.at_war(state, owner, state["settlements"][region_id]["owner"]):
			return false
	for other in state["armies"].values():
		if other["region"] == region_id and DiplomacyRules.at_war(state, owner, other["owner"]):
			return false
	return true


static func _cheapest_approach(data: GameData, costs: Dictionary, to_region: String) -> String:
	## The reachable neighbor of a blocked destination with the lowest cost,
	## ties to the lowest id (the neighbors are iterated sorted).
	var best := ""
	var best_cost := INF
	var neighbors: Array = data.regions[to_region].get("adjacent", []).duplicate()
	neighbors.sort()
	for neighbor in neighbors:
		if costs.has(neighbor) and float(costs[neighbor]) < best_cost - 0.0001:
			best_cost = float(costs[neighbor])
			best = neighbor
	return best
