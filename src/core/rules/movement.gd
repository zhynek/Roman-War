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
	var points := float(data.balance["movement"]["base_movement_points"]) + float(mobility_profile(data, army)["bonus"])
	if army["general"] != null and state["characters"].has(army["general"]):
		points += CharacterRules.effect_total(data, state["characters"][army["general"]], "movement")
	var owner := String(army["owner"])
	points += float(state["factions"][owner].get("boons", {}).get("movement", 0.0))
	points += KnowledgeRules.faction_effect_total(data, state, owner, "movement_points")
	return SocietyRules.quantize(maxf(points, 0.5))


static func mobility_profile(data: GameData, army: Dictionary) -> Dictionary:
	## The slowest company sets the column's pace. Empty general escorts ride.
	var bonuses: Dictionary = data.balance["movement"].get("class_movement_bonus", {})
	var slowest := "general_bodyguard" if army.get("general") != null else "infantry"
	var bonus := INF
	var mounted: bool = army.get("general") != null or not army.get("units", []).is_empty()
	for unit in army.get("units", []):
		var kind := String(data.units.get(unit["template"], {}).get("class", "infantry"))
		var value := float(bonuses.get(kind, 0.0))
		if value < bonus:
			bonus = value
			slowest = kind
		mounted = mounted and kind in ["cavalry", "horse_archer", "general_bodyguard", "chariot"]
	if is_inf(bonus):
		bonus = float(bonuses.get(slowest, 0.0))
	return {"class": slowest, "bonus": bonus, "mounted": mounted}


static func cap_movement(data: GameData, state: Dictionary, army: Dictionary) -> void:
	## Roster changes may slow a column, but never refund this season's march.
	army["movement_left"] = minf(float(army["movement_left"]), movement_points_for(data, state, army))


static func fleet_movement_points_for(data: GameData, state: Dictionary, fleet: Dictionary) -> float:
	## A fleet's budget at the start of a turn: the base, stretched by naval
	## technique and the great lighthouse (the wonder's naval_movement_pct).
	var owner := String(fleet["owner"])
	var naval_pct := KnowledgeRules.faction_effect_total(data, state, owner, "naval_movement_pct") \
		+ SettlementRules.faction_owns_wonder_effect(data, state, owner, "naval_movement_pct")
	var base := INF
	for ship in fleet.get("ships", []):
		base = minf(base, float(PortRules.vessel(data, ship["template"]).get("movement", data.balance["movement"]["base_movement_points"])))
	return SocietyRules.quantize((base if is_finite(base) else 0.0) * (1.0 + naval_pct / 100.0))


static func step_cost(data: GameData, state: Dictionary, to_region: String, from_region: String = "") -> float:
	if from_region != "" and not TerrainRules.land_connection(data, from_region, to_region, state):
		return INF
	var movement_rules: Dictionary = data.balance["movement"]
	var terrain: String = data.regions[to_region]["terrain"]
	var cost := float(movement_rules["terrain_cost"][terrain])
	if state["settlements"].has(to_region):
		var road_level := int(SettlementRules.effect_max(data, state["settlements"][to_region], "road_level"))
		var multipliers: Array = movement_rules["road_cost_multiplier"]
		cost *= float(multipliers[mini(road_level, multipliers.size() - 1)])
	return cost + TerrainRules.crossing_cost(data, from_region, to_region, state)


static func can_enter(data: GameData, state: Dictionary, army_id: String, to_region: String) -> bool:
	## Entering a region held by a faction you are at war with is an attack or a
	## siege, not a move — those go through Game.attack/besiege actions.
	var army: Dictionary = state["armies"][army_id]
	if not TerrainRules.land_connection(data, army["region"], to_region, state):
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
	var cost := step_cost(data, state, to_region, army["region"])
	var budget := float(army["movement_left"])
	if forced_march:
		budget *= float(data.balance["movement"]["forced_march_multiplier"])
	if cost > budget + 0.0001:
		return false
	if not can_enter(data, state, army_id, to_region):
		ReconRules.encounter(data, state, army, to_region)
		return false
	# Remainders are quantized like every stored float: 2.0 - 0.5 - 0.9 is
	# 0.6000000000000001 live and 0.6 after a save, and the next step would
	# then leave 1e-16 in one game and 0.0 in the other.
	if forced_march:
		army["forced_march"] = true
		army["movement_left"] = SocietyRules.quantize(
			maxf(0.0, budget - cost) / float(data.balance["movement"]["forced_march_multiplier"]))
	else:
		army["movement_left"] = SocietyRules.quantize(budget - cost)
	# Marching away lifts a siege at once, not at the end of the turn.
	SiegeRules.release(state, army_id)
	ReconRules.record_move(data, state, army_id, to_region)
	CartographyRules.record_reports(data, state)
	army["region"] = to_region
	CartographyRules.record_reports(data, state)
	sync_general_location(state, army)
	return true


static func sea_move_army(_data: GameData, _state: Dictionary, _army_id: String, _to_region: String) -> bool:
	## Transport now requires an actual fleet, landing and carrying capacity.
	return false


static func move_fleet(data: GameData, state: Dictionary, fleet_id: String, to_zone: String) -> bool:
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	if fleet.is_empty():
		return false
	var cost := WaterwayRules.step_cost(data, fleet, fleet["sea_zone"], to_zone, fleet.get("sail_mode", "coastal"))
	if cost > float(fleet["movement_left"]) or not WaterwayRules.hostiles(state, fleet).is_empty():
		return false
	var target := fleet.duplicate()
	target["sea_zone"] = to_zone
	if not WaterwayRules.hostiles(state, target).is_empty():
		return false # Combat belongs to the facade's resolver-backed voyage.
	fleet["sail_path"] = []
	fleet["trade_route"] = {}
	fleet["movement_left"] = SocietyRules.quantize(float(fleet["movement_left"]) - cost)
	fleet["sea_zone"] = to_zone
	WaterwayRules._sync_cargo(state, fleet)
	CartographyRules.record_reports(data, state)
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

static func block_reason(state: Dictionary, owner: String, region_id: String, seen: bool = true, data: GameData = null) -> String:
	## Why a region cannot simply be entered: "" when it can. A region the
	## viewer cannot see never reports a reason — highlights must not leak what
	## the fog hides; the march halts on contact instead.
	if not seen:
		return ""
	if state["armies"].values().any(func(a): return a["region"] == region_id and _at_war(state, owner, a["owner"]) and (data == null or VisibilityRules.army_visible(data, state, owner, a))):
		return "hostile_army"
	if state["settlements"].has(region_id) and _at_war(state, owner, state["settlements"][region_id]["owner"]):
		return "hostile_settlement"
	return ""


static func targets_for(data: GameData, state: Dictionary, army_id: String, observer: String = "") -> Dictionary:
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
		# Striking into a neighbouring region pays its step like any march
		# (the winner ends up there); the army's own region costs nothing.
		if region_id != army["region"] and not can_afford_step(data, state, army, region_id):
			continue
		if state["armies"].values().any(func(a): return a["region"] == region_id and _at_war(state, owner, a["owner"]) and (observer == "" or VisibilityRules.army_visible(data, state, observer, a))):
			targets[region_id] = "attack"
		elif state["settlements"].has(region_id):
			var settlement: Dictionary = state["settlements"][region_id]
			if _at_war(state, owner, settlement["owner"]) and settlement["siege"] == null \
					and not state["armies"].values().any(func(a): return a["region"] == region_id and a["owner"] == settlement["owner"] and (observer == "" or VisibilityRules.army_visible(data, state, observer, a))):
				targets[region_id] = "siege"
	return targets


static func can_afford_step(data: GameData, state: Dictionary, army: Dictionary, region_id: String) -> bool:
	## Whether the army's remaining points pay for the step into a region —
	## the price a siege laid from next door, or an attack across the border,
	## charges exactly as a march would.
	return step_cost(data, state, region_id, army["region"]) <= float(army["movement_left"]) + 0.0001


static func fleet_reachable(data: GameData, state: Dictionary, fleet_id: String) -> Dictionary:
	var reach := {}
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	for zone in data.sea_zones:
		var quote := WaterwayRules.preview(data, state, fleet_id, zone, fleet.get("sail_mode", "coastal"))
		if not quote.is_empty() and not quote["path"].is_empty() and int(quote["turns"]) == 1:
			reach[zone] = {"cost": quote["cost"], "via": fleet["sea_zone"] if quote["path"].size() == 1 else quote["path"][-2]}
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
