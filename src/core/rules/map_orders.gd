class_name MapOrderRules
## Read-only intent for a map order. The same route is quoted and marched;
## hostility is considered only where the player has reports. No UI or RNG.


static func preview(data: GameData, state: Dictionary, army_id: String,
		target: String, forced: bool, visible: Dictionary) -> Dictionary:
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or army["owner"] != state["player_faction"] or not data.regions.has(target):
		return {}
	var origin := String(army["region"])
	var result := {"action": "march", "from": origin, "target": target,
		"force": army_id, "forced": forced, "legs": [], "path": [], "cost": 0.0,
		"turns": 0, "blocked": false, "reason": "", "uncertain": not visible.has(target)}
	if state.get("cartography", {}).has(army["owner"]) and not CartographyRules.known_regions(data, state, army["owner"]).has(target):
		result["reason"] = "uncharted"
		return result
	result["crossing"] = TerrainRules.crossing_kind(data, origin, target)
	var settlement: Dictionary = state["settlements"].get(target, {})
	var siege = settlement.get("siege")
	var nearby := origin == target or TerrainRules.land_connection(data, origin, target)
	if nearby and visible.has(target):
		var enemies: Array = state["armies"].keys()
		enemies.sort()
		for enemy_id in enemies:
			var enemy: Dictionary = state["armies"][enemy_id]
			if enemy["region"] == target and DiplomacyRules.at_war(state, army["owner"], enemy["owner"]):
				result["action"] = "attack"
				result["defender"] = enemy_id
				break
		if result["action"] != "attack" and not settlement.is_empty() \
				and DiplomacyRules.at_war(state, army["owner"], settlement["owner"]):
			result["action"] = "siege"
			if siege != null:
				if siege["besieger"] == army_id:
					result["action"] = "assault"
					if not siege.get("equipment_ready", false):
						result["reason"] = "engines"
				else:
					result["reason"] = "invested"
			elif SiegeRules._owner_army_in(state, String(settlement["owner"]), target):
				result["reason"] = "relief_army"
		if result["action"] in ["attack", "siege", "assault"]:
			var cost := 0.0 if origin == target else MovementRules.step_cost(data, state, target, origin)
			result["cost"] = cost
			result["turns"] = 1
			if float(army["movement_left"]) <= 0.0001 or cost > float(army["movement_left"]) + 0.0001:
				result["reason"] = "no_movement"
			result["blocked"] = true
			return result
	if origin == target:
		result["action"] = "inspect"
		return result
	if ForceRules.besieging(state, army_id) != null:
		var budget := float(army["movement_left"])
		if forced:
			budget *= float(data.balance["movement"]["forced_march_multiplier"])
		if TerrainRules.land_connection(data, origin, target) and MovementRules.can_enter(data, state, army_id, target) \
				and MovementRules.step_cost(data, state, target, origin) <= budget + 0.0001:
			result["action"] = "withdraw"
			result["cost"] = MovementRules.step_cost(data, state, target, origin)
			result["turns"] = 1
			result["legs"] = [{"region": target, "cost": result["cost"], "turn": 1}]
			result["path"] = [target]
		else:
			result["reason"] = "holding_siege"
		return result
	var route := PathfindingRules.best_path(data, state, army_id, target, visible, forced)
	if route.is_empty():
		result["reason"] = "unreachable"
		return result
	for key in ["legs", "path", "cost", "turns"]:
		result[key] = route[key]
	result["blocked"] = route["blocked_destination"]
	if route["path"].is_empty():
		result["reason"] = "barred"
	_schedule(data, state, army, result, visible)
	return result


static func queued(data: GameData, state: Dictionary, army_id: String, visible: Dictionary) -> Dictionary:
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or army["owner"] != state["player_faction"]:
		return {}
	var path: Array = army.get("march_path", []).duplicate()
	if path.is_empty():
		return {}
	var result := {"action": "march", "from": army["region"], "target": path.back(),
		"force": army_id, "forced": army.get("march_forced", false), "legs": [], "path": path,
		"cost": 0.0, "turns": 0, "blocked": false, "reason": "", "uncertain": false}
	var previous := String(army["region"])
	for region in path:
		if not data.regions.has(region):
			return {}
		var cost := PathfindingRules.known_step_cost(data, state, region, visible, previous)
		result["legs"].append({"region": region, "cost": cost})
		result["cost"] += cost
		previous = region
	# Retain the actual saved queue. Re-running best_path here could draw a
	# newly cheaper road that the army was never ordered to take.
	_schedule(data, state, army, result, visible)
	return result


static func _schedule(data: GameData, state: Dictionary, army: Dictionary,
		result: Dictionary, visible: Dictionary) -> void:
	var forced := bool(result["forced"])
	var multiplier := float(data.balance["movement"]["forced_march_multiplier"]) if forced else 1.0
	var budget := float(army["movement_left"]) * multiplier
	var full := MovementRules.movement_points_for(data, state, army) * multiplier
	var season := 1
	for leg in result["legs"]:
		if float(leg["cost"]) > budget + 0.0001:
			season += 1
			budget = full
		budget -= float(leg["cost"])
		leg["turn"] = season
		if not visible.has(leg["region"]):
			result["uncertain"] = true
	result["turns"] = season if not result["legs"].is_empty() else 0
