class_name AiStrategy
## Target selection and force estimation for the campaign AI. A faction holds
## one persistent objective ({kind: "defend"|"take", region, set_turn}) in
## state.factions[fid].ai.objective — persistence stops armies oscillating
## between equally-scored targets. Objectives refresh when achieved, invalid,
## stale (balance ai.objective_stale_turns), or when a defense need appears
## (defense always outranks expansion). Deterministic: sorted candidate loops,
## strict-improvement argmax, region-id tie-breaks, no rng.


static func refresh_objective(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary) -> Dictionary:
	var faction: Dictionary = state["factions"][faction_id]
	var ai_memory: Dictionary = faction["ai"]

	var threatened := _most_threatened_settlement(data, state, faction_id)
	if threatened != "":
		var current = ai_memory.get("objective")
		if current == null or current.get("kind") != "defend" or current.get("region") != threatened:
			ai_memory["objective"] = {"kind": "defend", "region": threatened, "set_turn": int(state["turn"])}
	else:
		var objective = ai_memory.get("objective")
		if not _objective_still_valid(data, state, faction_id, objective):
			objective = _pick_expansion_target(data, state, faction_id, persona)
			ai_memory["objective"] = objective
	_refresh_muster(data, state, faction_id)
	return ai_memory.get("objective") if ai_memory.get("objective") != null else {}


static func muster_region(state: Dictionary, faction_id: String) -> String:
	return String(state["factions"][faction_id]["ai"].get("muster", ""))


static func force_strength(data: GameData, units: Array) -> float:
	## Paper strength of a unit list: quality × soldiers × condition, with the
	## battle experience chevron bonus and the weapons/armor stamp counted the
	## way the resolver does — an AI that ignored arming would misjudge every
	## upgraded enemy.
	var ai_rules: Dictionary = data.balance["ai"]
	var chevron_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	var weapon_pct := float(data.balance["battle"].get("weapon_upgrade_attack_pct", 0.0))
	var armor_pct := float(data.balance["battle"].get("armor_upgrade_defense_pct", 0.0))
	var total := 0.0
	for unit in units:
		var template: Dictionary = data.units.get(unit["template"], {})
		var weapon_bonus := 1.0 + float(unit.get("weapons", 0)) * weapon_pct / 100.0
		var armor_bonus := 1.0 + float(unit.get("armor", 0)) * armor_pct / 100.0
		var quality := float(template.get("attack", 0)) * weapon_bonus * float(ai_rules["strength_attack_weight"]) \
			+ float(template.get("defense", 0)) * armor_bonus * float(ai_rules["strength_defense_weight"]) \
			+ float(template.get("morale", 0)) * float(ai_rules["strength_morale_weight"])
		var condition := float(unit.get("strength_pct", 100)) / 100.0
		var experience := 1.0 + float(unit.get("experience", 0)) * chevron_pct / 100.0
		total += quality * float(template.get("soldiers", 0)) * condition * experience
	return total


static func settlement_defense(data: GameData, state: Dictionary, region_id: String) -> float:
	## Garrison strength behind its walls, plus any of the owner's field armies
	## standing in the region — what an attacker must expect to beat.
	## (A pure sum — iteration order cannot matter, so no sort is needed.)
	var settlement: Dictionary = state["settlements"][region_id]
	var wall_multipliers: Array = data.balance["battle"]["wall_defense_multiplier"]
	# Counting the defender's wallcraft technique keeps the AI's estimate
	# honest against rampart-holding cities (mirrors SiegeRules.assault).
	var wall_level := mini(int(SettlementRules.effect_max(data, settlement, "wall_level"))
		+ int(KnowledgeRules.faction_effect_total(data, state, settlement["owner"], "wall_level_bonus")),
		wall_multipliers.size() - 1)
	var defense := force_strength(data, settlement["garrison"]) * float(wall_multipliers[wall_level])
	for army in state["armies"].values():
		if army["region"] == region_id and army["owner"] == settlement["owner"]:
			defense += force_strength(data, army["units"])
	return defense


static func faction_field_strength(data: GameData, state: Dictionary, faction_id: String) -> float:
	## Total army strength (field only — garrisons defend, they do not project).
	## Pure sum: order-free, no sort.
	var total := 0.0
	for army in state["armies"].values():
		if army["owner"] == faction_id:
			total += force_strength(data, army["units"])
	return total


static func faction_total_strength(data: GameData, state: Dictionary, faction_id: String) -> float:
	## Field armies plus garrisons — the weight a faction throws on the scales
	## of diplomacy, where a wall of spears counts even if it never marches.
	## Pure sum: order-free, no sort.
	var total := faction_field_strength(data, state, faction_id)
	for settlement in state["settlements"].values():
		if settlement["owner"] == faction_id:
			total += force_strength(data, settlement["garrison"])
	return total


static func all_faction_strengths(data: GameData, state: Dictionary) -> Dictionary:
	## Every faction's total strength in ONE pass over the world — the per-turn
	## cache the diplomacy layer hands to attitude_total, which would otherwise
	## recompute strengths per faction pair.
	var strengths := {}
	for faction_id in state["factions"]:
		strengths[faction_id] = 0.0
	for army in state["armies"].values():
		strengths[army["owner"]] = float(strengths.get(army["owner"], 0.0)) \
			+ force_strength(data, army["units"])
	for settlement in state["settlements"].values():
		strengths[settlement["owner"]] = float(strengths.get(settlement["owner"], 0.0)) \
			+ force_strength(data, settlement["garrison"])
	return strengths


static func threat_near(data: GameData, state: Dictionary, faction_id: String, region_id: String, radius: int) -> float:
	## Summed strength of at-war armies within `radius` land hops of a region.
	## Pure sum: order-free, no sort.
	var hops := MapRules.hops_from(data, region_id)
	var total := 0.0
	for army in state["armies"].values():
		if not DiplomacyRules.at_war(state, faction_id, army["owner"]):
			continue
		var distance := int(hops.get(army["region"], -1))
		if distance >= 0 and distance <= radius:
			total += force_strength(data, army["units"])
	return total


## --- Internals -------------------------------------------------------------

static func _most_threatened_settlement(data: GameData, state: Dictionary, faction_id: String) -> String:
	var radius := int(data.balance["ai"]["defend_radius_hops"])
	var worst := ""
	var worst_threat := 0.0
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] != faction_id:
			continue
		var threat := threat_near(data, state, faction_id, region_id, radius)
		if settlement["siege"] != null:
			# A siege in progress is the emergency, whatever the raw numbers.
			threat *= float(data.balance["ai"]["siege_threat_multiplier"])
		if threat > worst_threat:
			worst_threat = threat
			worst = region_id
	return worst


static func _objective_still_valid(data: GameData, state: Dictionary, faction_id: String, objective) -> bool:
	if objective == null or not (objective is Dictionary) or objective.is_empty():
		return false
	var region: String = objective.get("region", "")
	if not state["settlements"].has(region):
		return false
	var age := int(state["turn"]) - int(objective.get("set_turn", 0))
	if age > int(data.balance["ai"]["objective_stale_turns"]):
		return false
	match String(objective.get("kind", "")):
		"take":
			var owner: String = state["settlements"][region]["owner"]
			if owner == faction_id:
				return false  # achieved
			# A take objective survives only while the target is takeable:
			# rebel-held, or held by someone we are at war with.
			return owner == "rebels" or DiplomacyRules.at_war(state, faction_id, owner)
		"defend":
			return false  # defense needs are recomputed fresh every turn
	return false


static func _pick_expansion_target(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary):
	var ai_rules: Dictionary = data.balance["ai"]
	var drive := float(persona.get("expansion_drive", 1.0))
	if drive <= 0.0:
		return null
	var own_regions: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] == faction_id:
			own_regions.append(region_id)
	if own_regions.is_empty():
		return null

	var best_region := ""
	var best_score := 0.0
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		var owner: String = settlement["owner"]
		if owner == faction_id:
			continue
		if owner != "rebels" and not DiplomacyRules.at_war(state, faction_id, owner):
			continue
		var distance := _distance_from_any(data, state, own_regions, region_id)
		if distance < 0:
			continue
		var score := (float(ai_rules["target_base_score"]) / float(1 + distance) \
			+ float(settlement["population"]) * float(ai_rules["target_population_weight"]) \
			- settlement_defense(data, state, region_id) * float(ai_rules["target_defense_weight"])) * drive
		if best_region == "" or score > best_score:
			best_region = region_id
			best_score = score
	if best_region == "" or best_score < float(ai_rules["target_min_score"]):
		return null
	return {"kind": "take", "region": best_region, "set_turn": int(state["turn"])}


static func _distance_from_any(data: GameData, state: Dictionary, own_regions: Array, target: String) -> int:
	## Least land hops from any owned settlement; sea-only targets count as a
	## flat crossing distance when a coastal holding shares (or neighbors) one
	## of the target's sea zones. -1 means unreachable entirely.
	var hops := MapRules.hops_from(data, target)
	var best := -1
	for region_id in own_regions:
		var distance := int(hops.get(region_id, -1))
		if distance >= 0 and (best < 0 or distance < best):
			best = distance
	if best >= 0:
		return best
	for region_id in own_regions:
		if sea_linked(data, region_id, target):
			return int(data.balance["ai"]["sea_target_hops"])
	return -1


static func sea_linked(data: GameData, from_region: String, to_region: String) -> bool:
	## Mirrors MovementRules.sea_move_army's reachability: same or adjacent zone.
	var from_zones: Array = data.regions.get(from_region, {}).get("sea_zones", [])
	var to_zones: Array = data.regions.get(to_region, {}).get("sea_zones", [])
	if from_zones.is_empty() or to_zones.is_empty():
		return false
	for zone in from_zones:
		if to_zones.has(zone):
			return true
		for adjacent_zone in data.sea_zones.get(zone, {}).get("adjacent", []):
			if to_zones.has(adjacent_zone):
				return true
	return false


static func _refresh_muster(data: GameData, state: Dictionary, faction_id: String) -> void:
	## Armies form nearest the objective: the owned settlement with the fewest
	## hops to it (the threatened settlement itself for a defense objective).
	var faction: Dictionary = state["factions"][faction_id]
	var objective = faction["ai"].get("objective")
	if objective == null or not (objective is Dictionary) or objective.is_empty():
		faction["ai"]["muster"] = ""
		return
	var target: String = objective["region"]
	if String(objective.get("kind", "")) == "defend":
		faction["ai"]["muster"] = target
		return
	var hops := MapRules.hops_from(data, target)
	var best := ""
	var best_distance := 1 << 30
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] != faction_id:
			continue
		var distance := int(hops.get(region_id, 1 << 29))
		if distance < best_distance:
			best_distance = distance
			best = region_id
	faction["ai"]["muster"] = best
