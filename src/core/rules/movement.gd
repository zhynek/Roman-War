class_name MovementRules
## Army movement over the region graph. Costs come from destination terrain,
## reduced by the destination settlement's road tier. Fleets move between
## adjacent sea zones. Forced march doubles range but marks the army fatigued
## (a battle malus applied by the auto-resolver).


static func reset_movement(data: GameData, state: Dictionary) -> void:
	var base := float(data.balance["movement"]["base_movement_points"])
	for army in state["armies"].values():
		army["movement_left"] = movement_points_for(data, state, army)
		army["forced_march"] = false
	for fleet in state["fleets"].values():
		fleet["movement_left"] = base


static func movement_points_for(data: GameData, state: Dictionary, army: Dictionary) -> float:
	## The budget an army is granted at the start of a turn. Logistics-minded
	## generals stretch the column's daily march: the "movement" effect is a
	## flat bonus in movement points (base 2.0), so a Quartermaster's +0.25 is
	## a real quarter-step, not a rounding. Never below half a point.
	var points := float(data.balance["movement"]["base_movement_points"])
	if army["general"] != null and state["characters"].has(army["general"]):
		points += CharacterRules.effect_total(data, state["characters"][army["general"]], "movement")
	return maxf(points, 0.5)


static func step_cost(data: GameData, state: Dictionary, to_region: String) -> float:
	var movement_rules: Dictionary = data.balance["movement"]
	var terrain: String = data.regions[to_region]["terrain"]
	var cost := float(movement_rules["terrain_cost"][terrain])
	if state["settlements"].has(to_region):
		var road_level := int(SettlementRules.effect_max(data, state["settlements"][to_region], "road_level"))
		var multipliers: Array = movement_rules["road_cost_multiplier"]
		cost *= float(multipliers[mini(road_level, multipliers.size() - 1)])
	return cost


static func can_enter(data: GameData, state: Dictionary, army_id: String, to_region: String) -> bool:
	## Entering a region held by a faction you are at war with is an attack or a
	## siege, not a move — those go through Game.attack/besiege actions.
	var army: Dictionary = state["armies"][army_id]
	if not MapRules.are_adjacent(data, army["region"], to_region):
		return false
	var owner: String = army["owner"]
	if hostile_army_in(state, owner, to_region):
		return false
	if state["settlements"].has(to_region):
		var holder: String = state["settlements"][to_region]["owner"]
		if _at_war(state, owner, holder):
			return false
	return true


static func move_army(data: GameData, state: Dictionary, army_id: String, to_region: String, forced_march: bool = false) -> bool:
	var army: Dictionary = state["armies"][army_id]
	if not can_enter(data, state, army_id, to_region):
		return false
	var cost := step_cost(data, state, to_region)
	var budget := float(army["movement_left"])
	if forced_march:
		budget *= float(data.balance["movement"]["forced_march_multiplier"])
	if cost > budget + 0.0001:
		return false
	if forced_march:
		army["forced_march"] = true
		army["movement_left"] = maxf(0.0, budget - cost) / float(data.balance["movement"]["forced_march_multiplier"])
	else:
		army["movement_left"] = budget - cost
	# Marching away lifts the siege at once, not at the end of the turn.
	SiegeRules.release(state, army_id)
	army["region"] = to_region
	sync_general_location(state, army)
	return true


static func sea_move_army(data: GameData, state: Dictionary, army_id: String, to_region: String) -> bool:
	## Naval transport, abstracted for the foundation: an army in a coastal
	## region may cross to another coastal region on the same or an adjacent
	## sea zone, spending its whole turn. Explicit embark-on-fleet transport
	## can replace this later without touching callers.
	var army: Dictionary = state["armies"][army_id]
	var from_zones: Array = data.regions.get(army["region"], {}).get("sea_zones", [])
	var to_zones: Array = data.regions.get(to_region, {}).get("sea_zones", [])
	if from_zones.is_empty() or to_zones.is_empty() or army["region"] == to_region:
		return false
	var connected := false
	for zone in from_zones:
		if to_zones.has(zone):
			connected = true
			break
		for adjacent_zone in data.sea_zones.get(zone, {}).get("adjacent", []):
			if to_zones.has(adjacent_zone):
				connected = true
				break
	if not connected:
		return false
	var cost := float(data.balance["movement"]["sea_move_cost"])
	if cost > float(army["movement_left"]) + 0.0001:
		return false
	if hostile_army_in(state, army["owner"], to_region):
		return false
	if state["settlements"].has(to_region):
		var holder: String = state["settlements"][to_region]["owner"]
		if _at_war(state, army["owner"], holder):
			return false
	army["movement_left"] = 0.0
	SiegeRules.release(state, army_id)
	army["region"] = to_region
	sync_general_location(state, army)
	return true


static func move_fleet(data: GameData, state: Dictionary, fleet_id: String, to_zone: String) -> bool:
	var fleet: Dictionary = state["fleets"][fleet_id]
	if not data.sea_zones.has(to_zone):
		return false
	if not data.sea_zones[fleet["sea_zone"]]["adjacent"].has(to_zone):
		return false
	var cost := float(data.balance["movement"]["sea_lane_cost"])
	if cost > float(fleet["movement_left"]) + 0.0001:
		return false
	fleet["movement_left"] = float(fleet["movement_left"]) - cost
	fleet["sea_zone"] = to_zone
	return true


## --- Reach and multi-step orders ---------------------------------------------

static func reachable(data: GameData, state: Dictionary, army_id: String, viewer_visible: Dictionary = {}) -> Dictionary:
	## Where an army can get to this season: a Dijkstra over land adjacency
	## from its region using step_cost, with the forced-march budget as the
	## horizon. Returns
	##   {"reach": {region_id: {cost, forced, via}}, "blocked": {region_id: reason}}
	## where forced means the region needs a forced march, via is the previous
	## region on the cheapest path, and reason is "hostile_army" or
	## "hostile_settlement". FOG RULE: hostiles block only where the viewer can
	## see them — pass the viewer's visible set, or {} to be omniscient (tests,
	## the AI). A fogged region is planned as passable; march() then halts on
	## contact, so highlights never leak what the fog hides.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return {"reach": {}, "blocked": {}}
	var plain := float(army["movement_left"])
	var horizon := plain * float(data.balance["movement"]["forced_march_multiplier"])
	var omniscient := viewer_visible.is_empty()
	var owner: String = army["owner"]
	var origin: String = army["region"]
	var best := {origin: 0.0}
	var reach := {}
	var blocked := {}
	var frontier: Array = [[0.0, origin]]
	while not frontier.is_empty():
		# Pop the cheapest entry, ties by region id — deterministic by construction.
		var best_index := 0
		for i in range(1, frontier.size()):
			var cheaper: bool = frontier[i][0] < frontier[best_index][0] - 0.000001
			var same_cost: bool = absf(frontier[i][0] - frontier[best_index][0]) <= 0.000001
			if cheaper or (same_cost and String(frontier[i][1]) < String(frontier[best_index][1])):
				best_index = i
		var current: Array = frontier[best_index]
		frontier.remove_at(best_index)
		var cost: float = current[0]
		var region: String = current[1]
		if cost > float(best.get(region, INF)) + 0.000001:
			continue  # a cheaper path already expanded this region
		var neighbors: Array = data.regions[region].get("adjacent", []).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if not data.regions.has(neighbor):
				continue
			var total := cost + step_cost(data, state, neighbor)
			if total > horizon + 0.0001:
				continue
			var seen: bool = omniscient or viewer_visible.has(neighbor)
			var reason := block_reason(state, owner, neighbor, seen)
			if reason != "":
				if not blocked.has(neighbor):
					blocked[neighbor] = reason
				continue
			if total < float(best.get(neighbor, INF)) - 0.000001:
				best[neighbor] = total
				reach[neighbor] = {"cost": total, "forced": total > plain + 0.0001, "via": region}
				frontier.append([total, neighbor])
	return {"reach": reach, "blocked": blocked}


static func block_reason(state: Dictionary, owner: String, region_id: String, seen: bool = true) -> String:
	## Why a region cannot simply be entered: "" when it can.
	if not seen:
		return ""
	if hostile_army_in(state, owner, region_id):
		return "hostile_army"
	if state["settlements"].has(region_id) and _at_war(state, owner, state["settlements"][region_id]["owner"]):
		return "hostile_settlement"
	return ""


static func march(data: GameData, state: Dictionary, army_id: String, to_region: String, forced: bool = false) -> Dictionary:
	## Walk the cheapest path to a region one move_army step at a time, seen
	## through the owner's own fog, halting at the first refused step (an army
	## the fog hid, a city that turned hostile, or a short budget). Never
	## attacks and never besieges. The march is forced as a whole only when the
	## destination lies beyond the plain budget (the doubled range must apply
	## from the first step), so a column is weary only if it had to be. Returns
	##   {ok, arrived, path: [regions entered], stopped_at, reason}
	## with reason "" | "not_found" | "unreachable" | "needs_forced_march" |
	## "hostile_army" | "hostile_settlement" | "no_movement".
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return {"ok": false, "arrived": false, "path": [], "stopped_at": "", "reason": "not_found"}
	if to_region == army["region"]:
		return {"ok": true, "arrived": true, "path": [], "stopped_at": to_region, "reason": ""}
	var visible := VisibilityRules.visible_regions(data, state, army["owner"])
	var plan := reachable(data, state, army_id, visible)
	var reach: Dictionary = plan["reach"]
	if not reach.has(to_region):
		var reason: String = plan["blocked"].get(to_region, "unreachable")
		return {"ok": false, "arrived": false, "path": [], "stopped_at": army["region"], "reason": reason}
	if reach[to_region]["forced"] and not forced:
		return {"ok": false, "arrived": false, "path": [], "stopped_at": army["region"], "reason": "needs_forced_march"}
	var path: Array = []
	var cursor := to_region
	while cursor != army["region"]:
		path.push_front(cursor)
		cursor = reach[cursor]["via"]
	var walked: Array = []
	var force_pace: bool = forced and reach[to_region]["forced"]
	for step in path:
		if not move_army(data, state, army_id, step, force_pace):
			var reason := block_reason(state, army["owner"], step)
			if reason == "":
				reason = "no_movement"
			return {"ok": not walked.is_empty(), "arrived": false, "path": walked,
				"stopped_at": army["region"], "reason": reason}
		walked.append(step)
	return {"ok": true, "arrived": true, "path": walked, "stopped_at": to_region, "reason": ""}


static func targets_for(data: GameData, state: Dictionary, army_id: String) -> Dictionary:
	## {region_id: "attack" | "siege"}: the hostile armies and at-war
	## settlements an army can strike from where it stands — its own region
	## and its neighbours. Fog is the caller's business.
	var targets := {}
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or float(army["movement_left"]) <= 0.0001:
		return targets
	var owner: String = army["owner"]
	var candidates: Array = data.regions[army["region"]].get("adjacent", []).duplicate()
	candidates.append(army["region"])
	candidates.sort()
	for region_id in candidates:
		if hostile_army_in(state, owner, region_id):
			targets[region_id] = "attack"
		elif state["settlements"].has(region_id):
			var settlement: Dictionary = state["settlements"][region_id]
			if _at_war(state, owner, settlement["owner"]) and settlement["siege"] == null:
				targets[region_id] = "siege"
	return targets


static func fleet_reachable(data: GameData, state: Dictionary, fleet_id: String) -> Dictionary:
	## {zone_id: {cost, via}} for every sea a fleet can reach this season,
	## one lane at a time. Fleets pass each other at sea; battle is explicit.
	var reach := {}
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	if fleet.is_empty():
		return reach
	var lane := float(data.balance["movement"]["sea_lane_cost"])
	var budget := float(fleet["movement_left"])
	var frontier: Array = [fleet["sea_zone"]]
	var best := {fleet["sea_zone"]: 0.0}
	while not frontier.is_empty():
		var zone: String = frontier.pop_front()
		var cost: float = best[zone]
		var adjacent: Array = data.sea_zones.get(zone, {}).get("adjacent", []).duplicate()
		adjacent.sort()
		for next_zone in adjacent:
			if not data.sea_zones.has(next_zone) or best.has(next_zone):
				continue
			if cost + lane > budget + 0.0001:
				continue
			best[next_zone] = cost + lane
			reach[next_zone] = {"cost": cost + lane, "via": zone}
			frontier.append(next_zone)
	return reach


static func sail(data: GameData, state: Dictionary, fleet_id: String, to_zone: String) -> Dictionary:
	## Multi-lane move_fleet along the cheapest route. {ok, arrived, path, stopped_at}
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	if fleet.is_empty():
		return {"ok": false, "arrived": false, "path": [], "stopped_at": ""}
	if to_zone == fleet["sea_zone"]:
		return {"ok": true, "arrived": true, "path": [], "stopped_at": to_zone}
	var reach := fleet_reachable(data, state, fleet_id)
	if not reach.has(to_zone):
		return {"ok": false, "arrived": false, "path": [], "stopped_at": fleet["sea_zone"]}
	var path: Array = []
	var cursor := to_zone
	while cursor != fleet["sea_zone"]:
		path.push_front(cursor)
		cursor = reach[cursor]["via"]
	var sailed: Array = []
	for lane in path:
		if not move_fleet(data, state, fleet_id, lane):
			return {"ok": not sailed.is_empty(), "arrived": false, "path": sailed, "stopped_at": fleet["sea_zone"]}
		sailed.append(lane)
	return {"ok": true, "arrived": true, "path": sailed, "stopped_at": to_zone}


static func hostile_army_in(state: Dictionary, faction_id: String, region_id: String) -> bool:
	## True when an army of a faction at war with faction_id stands in the region.
	for army in state["armies"].values():
		if army["region"] == region_id and _at_war(state, faction_id, army["owner"]):
			return true
	return false


static func _at_war(state: Dictionary, a: String, b: String) -> bool:
	return DiplomacyRules.at_war(state, a, b)


static func sync_general_location(state: Dictionary, army: Dictionary) -> void:
	## Call this wherever an army's region changes — a general's location must
	## never drift from the army he leads (co-location gates retinue transfers,
	## births, and the family panel).
	if army["general"] != null and state["characters"].has(army["general"]):
		state["characters"][army["general"]]["location"] = army["region"]
