class_name MovementRules
## Army movement over the region graph. Costs come from destination terrain,
## reduced by the destination settlement's road tier. Fleets move between
## adjacent sea zones. Forced march doubles range but marks the army fatigued
## (a battle malus applied by the auto-resolver).


static func reset_movement(data: GameData, state: Dictionary) -> void:
	var base := float(data.balance["movement"]["base_movement_points"])
	for army in state["armies"].values():
		var points := base
		if army["general"] != null and state["characters"].has(army["general"]):
			# Logistics-minded generals stretch the column's daily march. The
			# "movement" effect is a flat bonus in movement points (base 2.0),
			# so a Quartermaster's +0.25 is a real quarter-step, not a rounding.
			points += CharacterRules.effect_total(data, state["characters"][army["general"]], "movement")
		# Guided-trail boons march the whole faction a little harder.
		points += float(state["factions"][army["owner"]].get("boons", {}).get("movement", 0.0))
		army["movement_left"] = maxf(points, 0.5)
		army["forced_march"] = false
	for fleet in state["fleets"].values():
		fleet["movement_left"] = base


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
	if _hostile_army_in(state, owner, to_region):
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
	if _hostile_army_in(state, army["owner"], to_region):
		return false
	if state["settlements"].has(to_region):
		var holder: String = state["settlements"][to_region]["owner"]
		if _at_war(state, army["owner"], holder):
			return false
	army["movement_left"] = 0.0
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


static func _hostile_army_in(state: Dictionary, faction_id: String, region_id: String) -> bool:
	for army in state["armies"].values():
		if army["region"] == region_id and _at_war(state, faction_id, army["owner"]):
			return true
	return false


static func _at_war(state: Dictionary, a: String, b: String) -> bool:
	if a == b:
		return false
	return state["factions"][a]["diplomacy"].get(b, "neutral") == "war"


static func sync_general_location(state: Dictionary, army: Dictionary) -> void:
	## Call this wherever an army's region changes — a general's location must
	## never drift from the army he leads (co-location gates retinue transfers,
	## births, and the family panel).
	if army["general"] != null and state["characters"].has(army["general"]):
		state["characters"][army["general"]]["location"] = army["region"]
