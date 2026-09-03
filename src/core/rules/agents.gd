class_name AgentRules
## Campaign agents (Phase 5): envoys, spies and assassins. Agents are state
## entities distinct from family characters —
##   {owner, kind, name, region, skill, movement_left}
## — living in state.agents. Kinds, prices, training requirements and action
## vocabularies come from data/agents.json; every probability and price
## constant from balance.json → agents. Every random draw goes through the
## CampaignRng the caller threads in, and every loop that can steer a draw
## walks sorted ids, so a loaded save replays exactly like the live game.
##
## Skill contests share one shape: success = base + skill·k − difficulty·k,
## clamped. Difficulty is a settlement's counter-intelligence (its own spies,
## its governor's informants, its law) or a character's personal security.


## --- Queries ---------------------------------------------------------------

static func kind_of(data: GameData, agent: Dictionary) -> Dictionary:
	return data.agent_kinds.get(agent.get("kind", ""), {})


static func can(data: GameData, agent: Dictionary, action: String) -> bool:
	return kind_of(data, agent).get("actions", []).has(action)


static func agents_in(state: Dictionary, region_id: String, owner: String = "") -> Array:
	## Sorted ids of the agents standing in a region, optionally one owner's.
	var found: Array = []
	for agent_id in state["agents"]:
		var agent: Dictionary = state["agents"][agent_id]
		if agent["region"] == region_id and (owner == "" or agent["owner"] == owner):
			found.append(agent_id)
	found.sort()
	return found


static func agents_of(state: Dictionary, owner: String) -> Array:
	var found: Array = []
	for agent_id in state["agents"]:
		if state["agents"][agent_id]["owner"] == owner:
			found.append(agent_id)
	found.sort()
	return found


static func upkeep(data: GameData, state: Dictionary, faction_id: String) -> int:
	var total := 0
	for agent in state["agents"].values():
		if agent["owner"] == faction_id:
			total += int(kind_of(data, agent).get("upkeep", 0))
	return total


static func success_chance(data: GameData, skill: float, difficulty: float) -> float:
	## Probability (0–1) that skill beats difficulty, clamped to the balance
	## floor and ceiling so nothing is ever certain in either direction.
	var rules: Dictionary = data.balance["agents"]
	var pct := float(rules["success_base_pct"]) \
		+ skill * float(rules["success_pct_per_skill_point"]) \
		- difficulty * float(rules["success_pct_per_difficulty_point"])
	return clampf(pct, float(rules["success_min_pct"]), float(rules["success_max_pct"])) / 100.0


static func settlement_security(data: GameData, state: Dictionary, region_id: String) -> float:
	## Counter-intelligence: base, plus the owner's spies inside, plus the
	## governor's informants (the `agent_skill` retinue effect), plus law.
	var rules: Dictionary = data.balance["agents"]
	var settlement: Dictionary = state["settlements"][region_id]
	var security := float(rules["settlement_base_security"])
	for agent_id in agents_in(state, region_id, settlement["owner"]):
		var agent: Dictionary = state["agents"][agent_id]
		if can(data, agent, "counter_espionage"):
			security += float(agent["skill"]) * float(rules["security_per_own_spy_skill_point"])
	if settlement["governor"] != null and state["characters"].has(settlement["governor"]):
		security += CharacterRules.effect_total(data, state["characters"][settlement["governor"]], "agent_skill")
	security += PublicOrderRules.law_total(data, state, region_id) * float(rules["security_per_law_point"])
	return maxf(security, 0.0)


static func character_security(data: GameData, state: Dictionary, char_id: String) -> float:
	## Personal security: base + trait/retinue `personal_security`, more for
	## the leader and his heir, a bodyguard while leading an army, or a share
	## of the city's watch while at home.
	var rules: Dictionary = data.balance["agents"]
	var character: Dictionary = state["characters"][char_id]
	var security := float(rules["character_base_security"]) \
		+ CharacterRules.effect_total(data, character, "personal_security")
	if character["role"] in ["leader", "heir"]:
		security += float(rules["leader_security_bonus"])
	if _leads_army(state, char_id):
		security += float(rules["general_bodyguard_security"])
	else:
		var location: String = character.get("location", "")
		if state["settlements"].has(location) and state["settlements"][location]["owner"] == character["faction"]:
			security += settlement_security(data, state, location) \
				* float(rules["character_settlement_security_share"])
	return maxf(security, 0.0)


## --- Training --------------------------------------------------------------

static func kinds_available(data: GameData, state: Dictionary, region_id: String) -> Array:
	## Kinds this settlement can train: [{id, name, cost, upkeep}] sorted by id.
	var settlement: Dictionary = state["settlements"][region_id]
	var result: Array = []
	var kind_ids: Array = data.agent_kinds.keys()
	kind_ids.sort()
	for kind_id in kind_ids:
		var kind: Dictionary = data.agent_kinds[kind_id]
		if not _requirements_met(data, settlement, kind["requirements"]):
			continue
		result.append({"id": kind_id, "name": kind["name"],
			"cost": int(kind["cost"]), "upkeep": int(kind["upkeep"])})
	return result


static func recruit(data: GameData, state: Dictionary, rng: CampaignRng, region_id: String, kind_id: String) -> String:
	## Pays the price and puts the agent in the settlement's region at once,
	## with no movement left this turn. Returns the new id, or "" if refused.
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or not data.agent_kinds.has(kind_id):
		return ""
	var allowed := false
	for offer in kinds_available(data, state, region_id):
		if offer["id"] == kind_id:
			allowed = true
	if not allowed:
		return ""
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var cost := int(data.agent_kinds[kind_id]["cost"])
	if int(faction["treasury"]) < cost:
		return ""
	faction["treasury"] = int(faction["treasury"]) - cost
	return spawn(data, state, rng, settlement["owner"], kind_id, region_id)


static func spawn(data: GameData, state: Dictionary, rng: CampaignRng, owner: String, kind_id: String, region_id: String, skill: int = -1) -> String:
	## Creates an agent outright (campaign start, training). Names come from
	## the owner culture's pool through the campaign RNG.
	var kind: Dictionary = data.agent_kinds[kind_id]
	var agent_id := "agent_%d" % state["next_id"]
	state["next_id"] += 1
	var culture := data.culture_of_faction(owner)
	var pool: Dictionary = data.names.get(culture, data.names.get("roman", {}))
	var name_list: Array = pool.get("male", [])
	var name: String = String(rng.pick(name_list)) if not name_list.is_empty() else "Nameless"
	state["agents"][agent_id] = {
		"owner": owner,
		"kind": kind_id,
		"name": name,
		"region": region_id,
		"skill": int(kind["base_skill"]) if skill < 0 else skill,
		"movement_left": 0.0,
	}
	return agent_id


## --- Movement --------------------------------------------------------------

static func move(data: GameData, state: Dictionary, agent_id: String, to_region: String) -> bool:
	## Agents cross every border: no war closes a road to a spy, and an envoy
	## walks straight into the enemy's capital.
	var agent: Dictionary = state["agents"][agent_id]
	if not MapRules.are_adjacent(data, agent["region"], to_region):
		return false
	var cost := MovementRules.step_cost(data, state, to_region)
	if cost > float(agent["movement_left"]) + 0.0001:
		return false
	agent["movement_left"] = float(agent["movement_left"]) - cost
	agent["region"] = to_region
	return true


static func sea_move(data: GameData, state: Dictionary, agent_id: String, to_region: String) -> bool:
	## The same abstracted crossing armies use: coast to coast on the same or
	## an adjacent sea zone, taking the whole turn.
	var agent: Dictionary = state["agents"][agent_id]
	if not MovementRules.sea_connected(data, agent["region"], to_region):
		return false
	var cost := float(data.balance["movement"]["sea_move_cost"])
	if cost > float(agent["movement_left"]) + 0.0001:
		return false
	agent["movement_left"] = 0.0
	agent["region"] = to_region
	return true


static func reset_movement(data: GameData, state: Dictionary) -> void:
	var base := float(data.balance["agents"]["base_movement_points"])
	for agent in state["agents"].values():
		agent["movement_left"] = base


## --- Spies: open the gates ---------------------------------------------------

static func can_open_gates(data: GameData, state: Dictionary, agent_id: String) -> bool:
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or not can(data, agent, "open_gates"):
		return false
	var settlement: Dictionary = state["settlements"].get(agent["region"], {})
	if settlement.is_empty() or settlement["siege"] == null or settlement["siege"].get("gates_open", false):
		return false
	var besieger: Dictionary = state["armies"].get(settlement["siege"]["besieger"], {})
	return not besieger.is_empty() and besieger["owner"] == agent["owner"]


static func open_gates(data: GameData, state: Dictionary, rng: CampaignRng, agent_id: String) -> Dictionary:
	## A spy inside a city our army is besieging tries to unbar a gate. Success
	## marks the siege `gates_open`: the assault needs no equipment and meets no
	## walls. Failure risks the spy.
	if not can_open_gates(data, state, agent_id):
		return {}
	var agent: Dictionary = state["agents"][agent_id]
	var region_id: String = agent["region"]
	var settlement: Dictionary = state["settlements"][region_id]
	var chance := success_chance(data, float(agent["skill"]), settlement_security(data, state, region_id))
	var result := {"action": "open_gates", "agent": agent_id, "region": region_id,
		"chance": chance, "success": false, "caught": false, "notices": []}
	if rng.chance(chance):
		settlement["siege"]["gates_open"] = true
		result["success"] = true
		_gain_skill(data, rng, agent)
	else:
		result["caught"] = _maybe_caught(data, state, rng, agent_id, "open_gates",
			settlement["owner"], float(data.balance["diplomacy"]["sabotage_caught_opinion_penalty"]))
	return result


## --- Assassins ---------------------------------------------------------------

static func assassination_targets(data: GameData, state: Dictionary, agent_id: String) -> Array:
	## Foreign adult family members and foreign agents in the assassin's region:
	## [{kind: "character"|"agent", id, name, faction, chance}], deterministic order.
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or not can(data, agent, "assassinate"):
		return []
	var targets: Array = []
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if not character["alive"] or character["faction"] == agent["owner"]:
			continue
		if character.get("location", "") != agent["region"]:
			continue
		if character["role"] not in ["leader", "heir", "family"]:
			continue
		targets.append({"kind": "character", "id": char_id, "name": character["name"],
			"faction": character["faction"],
			"chance": success_chance(data, float(agent["skill"]), character_security(data, state, char_id))})
	for other_id in agents_in(state, agent["region"]):
		var other: Dictionary = state["agents"][other_id]
		if other["owner"] == agent["owner"]:
			continue
		targets.append({"kind": "agent", "id": other_id,
			"name": "%s (%s)" % [other["name"], kind_of(data, other).get("name", other["kind"])],
			"faction": other["owner"],
			"chance": success_chance(data, float(agent["skill"]), float(other["skill"]))})
	return targets


static func assassinate(data: GameData, state: Dictionary, rng: CampaignRng, agent_id: String, target_id: String) -> Dictionary:
	## Skill against security. A dead leader's succession settles at once; a
	## survivor remembers (the survived_assassination trigger); a failure may
	## cost the assassin his life and his master a diplomatic grudge.
	var target := {}
	for candidate in assassination_targets(data, state, agent_id):
		if candidate["id"] == target_id:
			target = candidate
	if target.is_empty():
		return {}
	var agent: Dictionary = state["agents"][agent_id]
	var diplomacy_rules: Dictionary = data.balance["diplomacy"]
	var victim_faction: String = target["faction"]
	var result := {"action": "assassinate", "agent": agent_id, "target": target_id,
		"target_name": target["name"], "target_kind": target["kind"], "faction": victim_faction,
		"chance": float(target["chance"]), "success": false, "caught": false, "notices": []}
	if rng.chance(float(target["chance"])):
		result["success"] = true
		if target["kind"] == "character":
			CharacterRules.kill(state, target_id, data, result["notices"])
		else:
			state["agents"].erase(target_id)
		DiplomacyRules.adjust_opinion(data, state, victim_faction, agent["owner"],
			-float(diplomacy_rules["assassination_success_opinion_penalty"]))
		_gain_skill(data, rng, agent)
	else:
		if target["kind"] == "character":
			CharacterRules.fire_trigger(data, state, target_id, "survived_assassination", {}, rng, result["notices"])
		result["caught"] = _maybe_caught(data, state, rng, agent_id, "assassinate", victim_faction,
			float(diplomacy_rules["assassination_caught_opinion_penalty"]))
	return result


static func sabotage_targets(data: GameData, state: Dictionary, agent_id: String) -> Array:
	## Building chains that can be wrecked where the assassin stands (foreign
	## settlements only; the government seat and farmland are beyond reach):
	## [{chain, name, chance}] sorted by chain id.
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or not can(data, agent, "sabotage"):
		return []
	var settlement: Dictionary = state["settlements"].get(agent["region"], {})
	if settlement.is_empty() or settlement["owner"] == agent["owner"]:
		return []
	var chance := success_chance(data, float(agent["skill"]), settlement_security(data, state, agent["region"]))
	var targets: Array = []
	var chain_ids: Array = settlement["buildings"].keys()
	chain_ids.sort()
	for chain_id in chain_ids:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty() or chain.get("indestructible", false) or chain["kind"] == "government":
			continue
		targets.append({"chain": chain_id, "name": chain.get("name", chain_id), "chance": chance})
	return targets


static func sabotage(data: GameData, state: Dictionary, rng: CampaignRng, agent_id: String, chain_id: String) -> Dictionary:
	## Knock one tier off a building, the way a riot does.
	var target := {}
	for candidate in sabotage_targets(data, state, agent_id):
		if candidate["chain"] == chain_id:
			target = candidate
	if target.is_empty():
		return {}
	var agent: Dictionary = state["agents"][agent_id]
	var settlement: Dictionary = state["settlements"][agent["region"]]
	var result := {"action": "sabotage", "agent": agent_id, "region": agent["region"], "chain": chain_id,
		"chain_name": target["name"], "faction": settlement["owner"],
		"chance": float(target["chance"]), "success": false, "caught": false, "notices": []}
	if rng.chance(float(target["chance"])):
		result["success"] = true
		var tier := int(settlement["buildings"][chain_id]) - 1
		if tier <= 0:
			settlement["buildings"].erase(chain_id)
		else:
			settlement["buildings"][chain_id] = tier
		_gain_skill(data, rng, agent)
	else:
		result["caught"] = _maybe_caught(data, state, rng, agent_id, "sabotage", settlement["owner"],
			float(data.balance["diplomacy"]["sabotage_caught_opinion_penalty"]))
	return result


## --- Envoys: contact and bribery ------------------------------------------------

static func in_contact(data: GameData, state: Dictionary, agent_id: String, faction_id: String) -> bool:
	## An envoy treats with a power whose land he stands on or beside, or whose
	## army shares his region.
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or agent["owner"] == faction_id or not can(data, agent, "negotiate"):
		return false
	var region_id: String = agent["region"]
	if state["settlements"].get(region_id, {}).get("owner", "") == faction_id:
		return true
	for neighbor in data.regions.get(region_id, {}).get("adjacent", []):
		if state["settlements"].get(neighbor, {}).get("owner", "") == faction_id:
			return true
	for army in state["armies"].values():
		if army["owner"] == faction_id and army["region"] == region_id:
			return true
	return false


static func factions_in_contact(data: GameData, state: Dictionary, agent_id: String) -> Array:
	## Every living, negotiable power the envoy could open talks with, sorted.
	var result: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		if not state["factions"][faction_id]["alive"] or data.factions.get(faction_id, {}).get("is_rebel", false):
			continue
		if in_contact(data, state, agent_id, faction_id):
			result.append(faction_id)
	return result


static func best_envoy(data: GameData, state: Dictionary, faction_id: String, other: String) -> String:
	## Our most skilled negotiator in contact with `other`, or "".
	var best := ""
	var best_skill := -1
	for agent_id in agents_of(state, faction_id):
		var agent: Dictionary = state["agents"][agent_id]
		if int(agent["skill"]) > best_skill and in_contact(data, state, agent_id, other):
			best = agent_id
			best_skill = int(agent["skill"])
	return best


static func bribe_army_cost(data: GameData, state: Dictionary, agent_id: String, army_id: String) -> int:
	## Price of buying an army standing with the envoy, or -1 when it cannot
	## be bought: our own, or led by a man of another house — family do not
	## sell out; only captains and brigands do.
	var agent: Dictionary = state["agents"].get(agent_id, {})
	var army: Dictionary = state["armies"].get(army_id, {})
	if agent.is_empty() or army.is_empty() or not can(data, agent, "bribe"):
		return -1
	if army["region"] != agent["region"] or army["owner"] == agent["owner"] or army["general"] != null:
		return -1
	var rules: Dictionary = data.balance["agents"]
	var value := 0.0
	for unit in army["units"]:
		value += float(data.units.get(unit["template"], {}).get("cost", 0)) * float(unit["strength_pct"]) / 100.0
	var is_rebel: bool = data.factions.get(army["owner"], {}).get("is_rebel", false)
	var multiplier := float(rules["bribe_rebel_cost_multiplier"] if is_rebel else rules["bribe_cost_multiplier"])
	return maxi(int(round(value * multiplier * (1.0 - _bribe_discount(data, agent)))), int(rules["bribe_min_cost"]))


static func bribe_army(data: GameData, state: Dictionary, agent_id: String, army_id: String) -> Dictionary:
	## Gold changes hands and the army changes banners where it stands.
	var cost := bribe_army_cost(data, state, agent_id, army_id)
	if cost < 0:
		return {}
	var agent: Dictionary = state["agents"][agent_id]
	var army: Dictionary = state["armies"][army_id]
	var faction: Dictionary = state["factions"][agent["owner"]]
	var result := {"action": "bribe_army", "agent": agent_id, "army": army_id, "cost": cost,
		"faction": army["owner"], "success": false}
	if int(faction["treasury"]) < cost:
		result["reason"] = "treasury"
		return result
	faction["treasury"] = int(faction["treasury"]) - cost
	var previous_owner: String = army["owner"]
	army["owner"] = agent["owner"]
	army["movement_left"] = 0.0
	army["forced_march"] = false
	if not data.factions.get(previous_owner, {}).get("is_rebel", false):
		DiplomacyRules.adjust_opinion(data, state, previous_owner, agent["owner"],
			-float(data.balance["diplomacy"]["bribe_opinion_penalty"]))
	result["success"] = true
	return result


static func bribe_settlement_cost(data: GameData, state: Dictionary, agent_id: String) -> int:
	## Independent towns can be bought outright; -1 for anyone else's.
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or not can(data, agent, "bribe"):
		return -1
	var settlement: Dictionary = state["settlements"].get(agent["region"], {})
	if settlement.is_empty() or not data.factions.get(settlement["owner"], {}).get("is_rebel", false):
		return -1
	var rules: Dictionary = data.balance["agents"]
	var cost := float(settlement["population"]) * float(rules["bribe_settlement_cost_per_pop"])
	return maxi(int(round(cost * (1.0 - _bribe_discount(data, agent)))), int(rules["bribe_min_cost"]))


static func bribe_settlement(data: GameData, state: Dictionary, agent_id: String) -> Dictionary:
	var cost := bribe_settlement_cost(data, state, agent_id)
	if cost < 0:
		return {}
	var agent: Dictionary = state["agents"][agent_id]
	var faction: Dictionary = state["factions"][agent["owner"]]
	var result := {"action": "bribe_settlement", "agent": agent_id, "region": agent["region"],
		"cost": cost, "success": false}
	if int(faction["treasury"]) < cost:
		result["reason"] = "treasury"
		return result
	faction["treasury"] = int(faction["treasury"]) - cost
	# A bought town brings its watch along and welcomes its new master.
	DiplomacyRules.transfer_settlement(data, state, agent["region"], agent["owner"],
		{"keep_garrison": true, "unrest": 0})
	result["success"] = true
	return result


## --- Turn resolution ------------------------------------------------------------

static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	## Covert agents standing in foreign territory may be caught by the local
	## counter-intelligence. Envoys travel openly and are never touched.
	var notices: Array = []
	var rules: Dictionary = data.balance["agents"]
	var agent_ids: Array = state["agents"].keys()
	agent_ids.sort()
	for agent_id in agent_ids:
		var agent: Dictionary = state["agents"][agent_id]
		if not kind_of(data, agent).get("covert", false):
			continue
		var settlement: Dictionary = state["settlements"].get(agent["region"], {})
		if settlement.is_empty() or settlement["owner"] == agent["owner"]:
			continue
		var security := settlement_security(data, state, agent["region"])
		var pct := float(rules["detection_base_pct"]) \
			+ (security - float(agent["skill"])) * float(rules["detection_pct_per_security_point"])
		pct = clampf(pct, 0.0, float(rules["detection_max_pct"]))
		if pct > 0.0 and rng.chance(pct / 100.0):
			notices.append({"kind": "agent_caught", "agent": agent_id, "name": agent["name"],
				"agent_kind": agent["kind"], "owner": agent["owner"], "region": agent["region"],
				"by": settlement["owner"]})
			state["agents"].erase(agent_id)
	return notices


static func remove_faction_agents(state: Dictionary, faction_id: String) -> void:
	## A destroyed house's agents scatter; nobody pays them any more.
	for agent_id in state["agents"].keys():
		if state["agents"][agent_id]["owner"] == faction_id:
			state["agents"].erase(agent_id)


## --- Internals -------------------------------------------------------------------

static func _maybe_caught(data: GameData, state: Dictionary, rng: CampaignRng, agent_id: String, action: String, offended: String, opinion_penalty: float) -> bool:
	## A failed covert act may expose the agent. Being caught ends him and the
	## offended power knows exactly whose man he was.
	var pct := float(data.balance["agents"]["caught_on_failure_pct"].get(action, 0))
	if pct <= 0.0 or not rng.chance(pct / 100.0):
		return false
	var agent: Dictionary = state["agents"][agent_id]
	DiplomacyRules.adjust_opinion(data, state, offended, agent["owner"], -opinion_penalty)
	state["agents"].erase(agent_id)
	return true


static func _gain_skill(data: GameData, rng: CampaignRng, agent: Dictionary) -> bool:
	## Success teaches; the trade improves with use up to the cap.
	var rules: Dictionary = data.balance["agents"]
	if int(agent["skill"]) >= int(rules["max_skill"]):
		return false
	if not rng.chance(float(rules["skill_gain_chance_on_success"])):
		return false
	agent["skill"] = int(agent["skill"]) + 1
	return true


static func _bribe_discount(data: GameData, agent: Dictionary) -> float:
	var rules: Dictionary = data.balance["agents"]
	var pct := minf(float(agent["skill"]) * float(rules["bribe_discount_pct_per_skill_point"]),
		float(rules["bribe_max_discount_pct"]))
	return pct / 100.0


static func _leads_army(state: Dictionary, char_id: String) -> bool:
	for army in state["armies"].values():
		if army["general"] == char_id:
			return true
	return false


static func _requirements_met(data: GameData, settlement: Dictionary, requirements: Dictionary) -> bool:
	var needed_kind: String = requirements["building_kind"]
	var needed_level := int(requirements["building_level"])
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty() or chain["kind"] != needed_kind:
			continue
		if int(settlement["buildings"][chain_id]) >= needed_level:
			return true
	return false
