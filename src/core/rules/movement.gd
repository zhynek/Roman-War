class_name MovementRules
## Army movement over the region graph. Costs come from destination terrain,
## reduced by the destination settlement's road tier. Fleets move between
## adjacent sea zones. Forced march doubles range but marks the army fatigued
## (a battle malus applied by the auto-resolver).


static func reset_movement(data: GameData, state: Dictionary) -> void:
	for army in state["armies"].values():
		army["movement_left"] = movement_points_for(data, state, army)
		army["forced_march"] = false
	for fleet in state["fleets"].values():
		fleet["movement_left"] = fleet_movement_points_for(data, state, fleet)
	# The season's memory of who marched how far (garrison musters, a
	# general's ride) is forgotten with the fresh points.
	ForceRules.clear_musters(state)
	AgentRules.reset_movement(data, state)


static func movement_points_for(data: GameData, state: Dictionary, army: Dictionary) -> float:
	## The budget an army is granted at the start of a turn — one rule, read by
	## the reset, the pathfinder's turn estimates, a freshly raised army and the
	## force card alike. Logistics-minded generals stretch the column's daily
	## march: the "movement" effect is a flat bonus in movement points (base
	## 2.0), so a Quartermaster's +0.25 is a real quarter-step, not a rounding.
	## Guided-trail boons march the whole faction a little harder, and practiced
	## logistics (marching camps, surveyed roads) speed every column. Never
	## below half a point.
	var points := float(data.balance["movement"]["base_movement_points"])
	if army["general"] != null and state["characters"].has(army["general"]):
		points += CharacterRules.effect_total(data, state["characters"][army["general"]], "movement")
	var owner := String(army["owner"])
	points += float(state["factions"][owner].get("boons", {}).get("movement", 0.0))
	points += KnowledgeRules.faction_effect_total(data, state, owner, "movement_points")
	return maxf(points, 0.5)


static func fleet_movement_points_for(data: GameData, state: Dictionary, fleet: Dictionary) -> float:
	## A fleet's budget at the start of a turn: the base, stretched by naval
	## technique and the great lighthouse (the wonder's naval_movement_pct).
	var owner := String(fleet["owner"])
	var naval_pct := KnowledgeRules.faction_effect_total(data, state, owner, "naval_movement_pct") \
		+ SettlementRules.faction_owns_wonder_effect(data, state, owner, "naval_movement_pct")
	return float(data.balance["movement"]["base_movement_points"]) * (1.0 + naval_pct / 100.0)


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
	# Marching away lifts a siege at once, not at the end of the turn.
	SiegeRules.release(state, army_id)
	army["region"] = to_region
	sync_general_location(state, army)
	return true


static func sea_move_army(data: GameData, state: Dictionary, army_id: String, to_region: String) -> bool:
	## Naval transport, abstracted for the foundation: an army in a coastal
	## region may cross to another coastal region on the same or an adjacent
	## sea zone, spending its whole turn. Explicit embark-on-fleet transport
	## can replace this later without touching callers.
	##
	## Landing on the shore of a faction you are AT WAR with is an amphibious
	## invasion: allowed as long as no hostile field army contests the beach
	## (the garrison waits behind its walls — besiege it next turn). Without
	## this, island regions with no land link — rebel-held Creta and Cyprus
	## among them — could never change hands, and Egypt's long campaign could
	## never be won.
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
	army["movement_left"] = 0.0
	# Marching away lifts a siege at once, not at the end of the turn.
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


static func hostile_army_in(state: Dictionary, faction_id: String, region_id: String) -> bool:
	## True when an army of a faction at war with faction_id stands in the region.
	for army in state["armies"].values():
		if army["region"] == region_id and _at_war(state, faction_id, army["owner"]):
			return true
	return false


static func _at_war(state: Dictionary, a: String, b: String) -> bool:
	return DiplomacyRules.at_war(state, a, b)


## --- What a force can do from where it stands ---------------------------------

static func block_reason(state: Dictionary, owner: String, region_id: String, seen: bool = true) -> String:
	## Why a region cannot simply be entered: "" when it can. A region the
	## viewer cannot see never reports a reason — highlights must not leak what
	## the fog hides; the march halts on contact instead.
	if not seen:
		return ""
	if hostile_army_in(state, owner, region_id):
		return "hostile_army"
	if state["settlements"].has(region_id) and _at_war(state, owner, state["settlements"][region_id]["owner"]):
		return "hostile_settlement"
	return ""


static func targets_for(data: GameData, state: Dictionary, army_id: String) -> Dictionary:
	## {region_id: "attack" | "siege"}: the hostile armies and at-war
	## settlements an army can strike from where it stands — its own region
	## and its neighbours. Fog is the caller's business. An army with no
	## movement left has no targets: a battle takes the rest of the season.
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


static func sync_general_location(state: Dictionary, army: Dictionary) -> void:
	## Call this wherever an army's region changes — a general's location must
	## never drift from the army he leads (co-location gates retinue transfers,
	## births, and the family panel).
	if army["general"] != null and state["characters"].has(army["general"]):
		state["characters"][army["general"]]["location"] = army["region"]
