class_name AiMilitary
## Army handling for the campaign AI: raise field armies from the muster
## settlement's surplus, merge under-strength stacks, fight favorable battles,
## besiege and assault the objective, converge on threatened settlements.
##
## Iteration discipline: battles, merges and assaults erase armies mid-flight,
## so every loop walks a SORTED SNAPSHOT of ids and re-checks existence at each
## step. The AI never initiates combat against a faction it is not already at
## war with — attack_army and begin_siege auto-declare war, and an accidental
## declaration was a real shipped bug class. All randomness comes from the
## turn's rng via the resolver; decisions themselves are deterministic.


static func run(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, faction_id: String, persona: Dictionary, events: Array) -> void:
	_raise_from_muster(data, state, faction_id, persona)

	var army_ids: Array = []
	for army_id in state["armies"]:
		if state["armies"][army_id]["owner"] == faction_id:
			army_ids.append(army_id)
	army_ids.sort()

	for army_id in army_ids:
		if not state["armies"].has(army_id):
			continue
		_merge_with_colocated(data, state, faction_id, army_id, persona)
		if not state["armies"].has(army_id):
			continue
		_run_army(data, state, rng, resolver, faction_id, army_id, persona, events)


## --- Mustering -------------------------------------------------------------

static func _raise_from_muster(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary) -> void:
	var muster := AiStrategy.muster_region(state, faction_id)
	if muster == "" or not state["settlements"].has(muster):
		return
	var settlement: Dictionary = state["settlements"][muster]
	if settlement["owner"] != faction_id:
		return
	var objective = state["factions"][faction_id]["ai"].get("objective")
	if objective == null or not (objective is Dictionary) or String(objective.get("kind", "")) != "take":
		return
	var floor_units := int(persona.get("garrison_frontier_units", 4)) \
		if AiEconomy.is_frontier(data, state, faction_id, muster) \
		else int(persona.get("garrison_min_units", 2))
	var surplus: int = settlement["garrison"].size() - floor_units
	if surplus < int(data.balance["ai"]["raise_army_min_units"]):
		return
	var unit_count := mini(surplus, int(persona.get("army_size_target", 8)))
	var army_id := "army_%d" % state["next_id"]
	state["next_id"] = int(state["next_id"]) + 1
	var units: Array = []
	for i in range(unit_count):
		# Newest recruits stand at the end of the garrison list — they are the
		# muster surplus; the old garrison keeps the walls.
		units.append(settlement["garrison"].pop_back())
	state["armies"][army_id] = {
		"owner": faction_id, "region": muster, "units": units,
		"general": null, "movement_left": 0.0, "forced_march": false,
	}


static func _merge_with_colocated(data: GameData, state: Dictionary, faction_id: String, army_id: String, persona: Dictionary) -> void:
	## Two friendly stacks in one region combine while under the size ceiling.
	## The survivor is the one with a general, else the lower (older) id; two
	## generals never share a tent.
	var army: Dictionary = state["armies"][army_id]
	var ceiling := int(ceil(float(persona.get("army_size_target", 8))
		* float(data.balance["ai"]["merge_ceiling_factor"])))
	if _besieges_something(state, army_id):
		return  # a besieger must survive as itself, or settlement.siege dangles
	var other_ids: Array = state["armies"].keys()
	other_ids.sort()
	for other_id in other_ids:
		if other_id == army_id or not state["armies"].has(other_id) or not state["armies"].has(army_id):
			continue
		army = state["armies"][army_id]
		var other: Dictionary = state["armies"][other_id]
		if other["owner"] != faction_id or other["region"] != army["region"]:
			continue
		if _besieges_something(state, other_id):
			continue
		if army["units"].size() + other["units"].size() > ceiling:
			continue
		if army["general"] != null and other["general"] != null:
			continue
		var keep_id: String = army_id
		var lose_id: String = other_id
		if army["general"] == null and other["general"] != null:
			keep_id = other_id
			lose_id = army_id
		elif army["general"] == null and other["general"] == null \
				and _army_seniority(other_id) < _army_seniority(army_id):
			keep_id = other_id
			lose_id = army_id
		var keep: Dictionary = state["armies"][keep_id]
		var lose: Dictionary = state["armies"][lose_id]
		for unit in lose["units"]:
			keep["units"].append(unit)
		keep["movement_left"] = minf(float(keep["movement_left"]), float(lose["movement_left"]))
		state["armies"].erase(lose_id)
		RecruitmentRules.merge_units(keep["units"])
		if lose_id == army_id:
			return


static func _army_seniority(army_id: String) -> int:
	return army_id.trim_prefix("army_").to_int()


static func _besieges_something(state: Dictionary, army_id: String) -> bool:
	for settlement in state["settlements"].values():
		var siege = settlement["siege"]
		if siege != null and siege["besieger"] == army_id:
			return true
	return false


## --- One army's turn -------------------------------------------------------

static func _run_army(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, faction_id: String, army_id: String, persona: Dictionary, events: Array) -> void:
	var siege_region := _besieging_region(state, army_id)
	if siege_region != "":
		_consider_assault(data, state, rng, resolver, faction_id, army_id, siege_region, persona, events)
		return

	var steps := 0
	var action_cap := int(data.balance["ai"]["army_action_cap"])
	while steps < action_cap and state["armies"].has(army_id):
		steps += 1
		if _attack_best_adjacent(data, state, rng, resolver, faction_id, army_id, events):
			continue
		if not state["armies"].has(army_id):
			return
		if _try_besiege_objective(data, state, faction_id, army_id, events):
			return
		if _consider_garrisoning(data, state, faction_id, army_id):
			return
		if not _step_toward_destination(data, state, faction_id, army_id, persona):
			return


static func _besieging_region(state: Dictionary, army_id: String) -> String:
	var army: Dictionary = state["armies"][army_id]
	var region_id: String = army["region"]
	if state["settlements"].has(region_id):
		var siege = state["settlements"][region_id]["siege"]
		if siege != null and siege["besieger"] == army_id:
			return region_id
	return ""


static func _consider_assault(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, faction_id: String, army_id: String, region_id: String, persona: Dictionary, events: Array) -> void:
	var settlement: Dictionary = state["settlements"][region_id]
	var siege: Dictionary = settlement["siege"]
	if not siege.get("equipment_ready", false):
		return  # keep starving them; advance_sieges resolves the endgame
	var army: Dictionary = state["armies"][army_id]
	var defense := AiStrategy.settlement_defense(data, state, region_id)
	if AiStrategy.force_strength(data, army["units"]) < defense * float(data.balance["ai"]["assault_ratio"]):
		return
	var previous_owner: String = settlement["owner"]
	var result := SiegeRules.assault(data, state, rng, resolver, army_id, region_id)
	if result.get("captured", false):
		var occupation: String = persona.get("occupation", "occupy")
		CombatRules.capture_settlement(data, state, rng, region_id,
			result["capture_pending_owner"], occupation)
		var notices: Array = result.get("character_notices", [])
		CombatRules.fire_occupation_triggers(data, state, rng,
			result.get("besieger_general"), occupation, notices)
		events.append({"kind": "ai_conquest", "faction": faction_id, "region": region_id,
			"occupation": occupation, "from": previous_owner})


static func _attack_best_adjacent(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, faction_id: String, army_id: String, events: Array) -> bool:
	## Fight the most favorable battle available against a faction already at
	## war; one battle per army per turn, and never below the strength ratio.
	var army: Dictionary = state["armies"][army_id]
	if float(army["movement_left"]) <= 0.0:
		return false
	var own_strength := AiStrategy.force_strength(data, army["units"])
	var min_ratio := float(data.balance["ai"]["min_attack_ratio"])
	var best_target := ""
	var best_ratio := 0.0
	var enemy_ids: Array = state["armies"].keys()
	enemy_ids.sort()
	for enemy_id in enemy_ids:
		var enemy: Dictionary = state["armies"][enemy_id]
		if not DiplomacyRules.at_war(state, faction_id, enemy["owner"]):
			continue
		if enemy["region"] != army["region"] \
				and not MapRules.are_adjacent(data, army["region"], enemy["region"]):
			continue
		var enemy_strength := AiStrategy.force_strength(data, enemy["units"])
		var ratio := own_strength / maxf(enemy_strength, 1.0)
		if ratio >= min_ratio and ratio > best_ratio:
			best_ratio = ratio
			best_target = enemy_id
	if best_target == "":
		return false
	var defender_owner: String = state["armies"][best_target]["owner"]
	var region: String = state["armies"][best_target]["region"]
	var result := CombatRules.attack_army(data, state, resolver, rng, army_id, best_target)
	if result.is_empty():
		return false
	if state["armies"].has(army_id):
		state["armies"][army_id]["movement_left"] = 0.0
	events.append({"kind": "ai_attack", "faction": faction_id, "defender": defender_owner,
		"region": region, "winner": result.get("winner", "")})
	return true


static func _try_besiege_objective(data: GameData, state: Dictionary, faction_id: String, army_id: String, events: Array) -> bool:
	var objective = state["factions"][faction_id]["ai"].get("objective")
	if objective == null or not (objective is Dictionary) or String(objective.get("kind", "")) != "take":
		return false
	var target: String = objective["region"]
	var army: Dictionary = state["armies"][army_id]
	if float(army["movement_left"]) <= 0.0:
		return false  # a freshly-raised or spent army cannot invest this tick
	if army["region"] != target and not MapRules.are_adjacent(data, army["region"], target):
		return false
	if not state["settlements"].has(target):
		return false
	var settlement: Dictionary = state["settlements"][target]
	var owner: String = settlement["owner"]
	if owner == faction_id or not DiplomacyRules.at_war(state, faction_id, owner):
		return false  # never a hostile act against a faction not already at war
	if settlement["siege"] != null:
		return false  # someone else got there first
	var defense := AiStrategy.settlement_defense(data, state, target)
	if AiStrategy.force_strength(data, army["units"]) < defense * float(data.balance["ai"]["siege_min_ratio"]):
		return false
	if not SiegeRules.begin_siege(data, state, army_id, target):
		return false
	events.append({"kind": "ai_siege", "faction": faction_id, "region": target, "owner": owner})
	return true


static func _consider_garrisoning(data: GameData, state: Dictionary, faction_id: String, army_id: String) -> bool:
	## A defender that cannot win in the open folds into the garrison and mans
	## the walls instead.
	var objective = state["factions"][faction_id]["ai"].get("objective")
	if objective == null or not (objective is Dictionary) or String(objective.get("kind", "")) != "defend":
		return false
	var army: Dictionary = state["armies"][army_id]
	var target: String = objective["region"]
	if army["region"] != target or not state["settlements"].has(target):
		return false
	if state["settlements"][target]["owner"] != faction_id:
		return false
	var radius := int(data.balance["ai"]["defend_radius_hops"])
	var threat := AiStrategy.threat_near(data, state, faction_id, target, radius)
	if AiStrategy.force_strength(data, army["units"]) >= threat:
		return true  # strong enough to hold the field here; stand and cover the city
	return CombatRules.garrison_army(data, state, army_id, target)


static func _step_toward_destination(data: GameData, state: Dictionary, faction_id: String, army_id: String, persona: Dictionary) -> bool:
	var destination := _destination_for(data, state, faction_id, army_id, persona)
	var army: Dictionary = state["armies"][army_id]
	if destination == "" or destination == army["region"]:
		return false
	var hops := MapRules.hops_from(data, destination)
	var here := int(hops.get(army["region"], -1))

	var best_next := ""
	var best_distance := here if here >= 0 else (1 << 29)
	var neighbors: Array = data.regions[army["region"]].get("adjacent", []).duplicate()
	neighbors.sort()
	for neighbor in neighbors:
		var distance := int(hops.get(neighbor, -1))
		if distance < 0 or distance >= best_distance:
			continue
		if not MovementRules.can_enter(data, state, army_id, neighbor):
			continue
		best_next = neighbor
		best_distance = distance
	if best_next != "":
		return MovementRules.move_army(data, state, army_id, best_next, false)
	if here < 0:
		return _sea_step(data, state, army_id, destination)
	return false


static func _sea_step(data: GameData, state: Dictionary, army_id: String, destination: String) -> bool:
	## Cross the water when land cannot reach the destination: straight onto the
	## target shore when the landing rules allow it, else the closest coastal
	## region to it. sea_move_army itself enforces zone links, hostile-army
	## contests and the at-war landing rule.
	if MovementRules.sea_move_army(data, state, army_id, destination):
		return true
	var hops := MapRules.hops_from(data, destination)
	var candidates: Array = []
	var region_ids: Array = data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		var distance := int(hops.get(region_id, -1))
		if distance >= 0 and MapRules.coastal(data, region_id):
			candidates.append([distance, region_id])
	candidates.sort()
	for candidate in candidates:
		if MovementRules.sea_move_army(data, state, army_id, candidate[1]):
			return true
	return false


static func _destination_for(data: GameData, state: Dictionary, faction_id: String, army_id: String, persona: Dictionary) -> String:
	var objective = state["factions"][faction_id]["ai"].get("objective")
	if objective == null or not (objective is Dictionary) or objective.is_empty():
		return ""  # nothing to do; hold position
	var target: String = objective["region"]
	if String(objective.get("kind", "")) == "defend":
		return target
	# Take objectives: march on the target once strong enough for the siege,
	# otherwise gather at the muster settlement and wait for weight of numbers.
	var army: Dictionary = state["armies"][army_id]
	var needed := AiStrategy.settlement_defense(data, state, target) \
		* float(data.balance["ai"]["siege_min_ratio"])
	if AiStrategy.force_strength(data, army["units"]) >= needed:
		return target
	return AiStrategy.muster_region(state, faction_id)
