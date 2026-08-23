class_name AgentRules
## Phase 5 campaign agents: envoys, informers, and hired blades. Agents are
## state entities ({owner, kind, region, name, skill, movement_left, alive})
## trained in settlements, walking the same region graph as armies but
## welcome (or at least unhindered) everywhere. Formulas and caps live in
## balance.json → agents; the kinds themselves are data (data/agents.json).
##
## The authored `agent_skill` ancillary effects finally have their readers
## here: a governor's spymaster raises the skill of agents trained under him
## and sharpens the hunt for foreign informers in his town.


static func available_kinds(data: GameData, state: Dictionary, region_id: String) -> Array:
	## Agent kinds this settlement can train right now, with costs.
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty():
		return []
	var owner: String = settlement["owner"]
	var offers: Array = []
	var kind_ids: Array = data.agent_kinds.keys()
	kind_ids.sort()
	for kind_id in kind_ids:
		var kind: Dictionary = data.agent_kinds[kind_id]
		if not _requirements_met(data, settlement, kind["requirements"]):
			continue
		if _count_of_kind(state, owner, kind_id) >= int(data.balance["agents"]["max_per_kind"]):
			continue
		offers.append(kind)
	return offers


static func train(data: GameData, state: Dictionary, region_id: String, kind_id: String, rng: CampaignRng) -> String:
	## Pay for and field a new agent in the settlement. Returns its id or "".
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty():
		return ""
	var allowed := false
	for kind in available_kinds(data, state, region_id):
		if kind["id"] == kind_id:
			allowed = true
			break
	if not allowed:
		return ""
	var kind: Dictionary = data.agent_kinds[kind_id]
	var faction: Dictionary = state["factions"][settlement["owner"]]
	if int(faction["treasury"]) < int(kind["cost"]):
		return ""
	faction["treasury"] = int(faction["treasury"]) - int(kind["cost"])

	# A spymaster in the governor's retinue trains sharper agents.
	var skill := int(kind["base_skill"])
	if settlement["governor"] != null and state["characters"].has(settlement["governor"]):
		var governor: Dictionary = state["characters"][settlement["governor"]]
		skill += int(CharacterRules.effect_total(data, governor, "agent_skill")
			* float(data.balance["agents"]["training_skill_from_agent_skill"]))
	skill = mini(skill, int(data.balance["agents"]["skill_max"]))

	var culture := data.culture_of_faction(settlement["owner"])
	var pool: Dictionary = data.names.get(culture, data.names.get("roman", {}))
	var name_list: Array = pool.get("male", ["Nameless"])
	var agent_name: String = rng.pick(name_list) if not name_list.is_empty() else "Nameless"

	if not state.has("agents"):
		state["agents"] = {}
	var agent_id := "agent_%d" % state["next_id"]
	state["next_id"] += 1
	state["agents"][agent_id] = {
		"owner": settlement["owner"],
		"kind": kind_id,
		"region": region_id,
		"name": agent_name,
		"skill": skill,
		"movement_left": 0.0,
		"turns_abroad": 0,
		"alive": true,
	}
	return agent_id


static func move_towards(data: GameData, state: Dictionary, agent_id: String, target: String) -> String:
	## Walk the agent along the shortest land path toward the target while his
	## movement lasts, taking ship when the land runs out. Agents pass through
	## any territory. Returns the region he ends the order in.
	var agent: Dictionary = state.get("agents", {}).get(agent_id, {})
	if agent.is_empty() or not agent["alive"] or not data.regions.has(target):
		return agent.get("region", "")
	var guard := 0
	while agent["region"] != target and guard < 32:
		guard += 1
		var region: String = agent["region"]
		var hops := MapRules.hops_from(data, target)
		if hops.has(region):
			var current := int(hops[region])
			var step := ""
			var adjacent: Array = data.regions[region].get("adjacent", []).duplicate()
			adjacent.sort()
			var best := current
			for neighbor in adjacent:
				var neighbor_hops := int(hops.get(neighbor, 1 << 20))
				if neighbor_hops < best:
					best = neighbor_hops
					step = neighbor
			if step == "":
				break
			var cost := MovementRules.step_cost(data, state, step)
			if cost > float(agent["movement_left"]) + 0.0001:
				break
			agent["movement_left"] = float(agent["movement_left"]) - cost
			agent["region"] = step
		else:
			if not _sea_leg(data, state, agent, target):
				break
	return agent["region"]


static func assassinate(data: GameData, state: Dictionary, rng: CampaignRng, agent_id: String, char_id: String, notices: Array) -> Dictionary:
	## One knife, one night. Success kills the mark; a botched attempt can
	## cost the blade his life — and being caught poisons relations with the
	## mark's house. Returns {attempted, killed, caught}.
	var result := {"attempted": false, "killed": false, "caught": false}
	var agent: Dictionary = state.get("agents", {}).get(agent_id, {})
	var target: Dictionary = state["characters"].get(char_id, {})
	if agent.is_empty() or target.is_empty():
		return result
	if not agent["alive"] or agent["kind"] != "assassin" or not target["alive"]:
		return result
	if target["faction"] == agent["owner"]:
		return result
	if target.get("location", "") != agent["region"]:
		return result
	if float(agent["movement_left"]) <= 0.0:
		return result

	var rules: Dictionary = data.balance["agents"]
	var security := CharacterRules.effect_total(data, target, "personal_security") \
		+ float(CharacterRules.effective(data, target, "influence")) * 0.5
	var chance := float(rules["assassinate_base_chance"]) \
		+ float(agent["skill"]) * float(rules["assassinate_skill_pct"]) / 100.0 \
		- security * float(rules["assassinate_security_pct"]) / 100.0
	chance = clampf(chance, float(rules["assassinate_min_chance"]), float(rules["assassinate_max_chance"]))

	result["attempted"] = true
	agent["movement_left"] = 0.0
	if rng.chance(chance):
		result["killed"] = true
		CharacterRules.kill(state, char_id, data, notices)
		agent["skill"] = mini(int(agent["skill"]) + int(rules["assassin_skill_gain_on_success"]),
			int(data.balance["agents"]["skill_max"]))
		notices.append({"kind": "assassination", "character": char_id,
			"faction": target["faction"], "by": agent["owner"]})
	elif rng.chance(float(rules["assassin_caught_chance_on_failure"])):
		result["caught"] = true
		agent["alive"] = false
		state["agents"].erase(agent_id)
		NegotiationRules.shift_stored_attitude(data, state, target["faction"], agent["owner"],
			float(rules["assassin_caught_attitude"]))
		notices.append({"kind": "assassin_caught", "faction": agent["owner"],
			"by": target["faction"]})
	return result


static func spy_assault_bonus_pct(data: GameData, state: Dictionary, attacker: String, region_id: String) -> float:
	## Informers inside the walls unbar gates for their master's assault.
	var rules: Dictionary = data.balance["agents"]
	var bonus := 0.0
	var agent_ids: Array = state.get("agents", {}).keys()
	agent_ids.sort()
	for agent_id in agent_ids:
		var agent: Dictionary = state["agents"][agent_id]
		if agent["alive"] and agent["owner"] == attacker and agent["kind"] == "spy" \
				and agent["region"] == region_id:
			bonus += float(rules["spy_assault_base_bonus_pct"]) \
				+ float(agent["skill"]) * float(rules["spy_assault_bonus_pct_per_skill"])
	return bonus


static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	## Counter-intelligence and tradecraft, once per turn: informers and
	## blades on foreign ground risk the governor's hunters; those who survive
	## the streets long enough learn from them.
	var rules: Dictionary = data.balance["agents"]
	var notices: Array = []
	var agent_ids: Array = state.get("agents", {}).keys()
	agent_ids.sort()
	for agent_id in agent_ids:
		var agent: Dictionary = state["agents"][agent_id]
		if not agent["alive"]:
			continue
		var region: String = agent["region"]
		var settlement: Dictionary = state["settlements"].get(region, {})
		var abroad: bool = not settlement.is_empty() and settlement["owner"] != agent["owner"]
		if not abroad or agent["kind"] == "diplomat":
			continue  # envoys enjoy a rough immunity; nobody hangs the herald
		agent["turns_abroad"] = int(agent.get("turns_abroad", 0)) + 1

		var hunter_skill := 0.0
		if settlement["governor"] != null and state["characters"].has(settlement["governor"]):
			hunter_skill = CharacterRules.effect_total(
				data, state["characters"][settlement["governor"]], "agent_skill")
		var chance := float(rules["spy_detection_base_chance"]) \
			+ hunter_skill * float(rules["spy_detection_agent_skill_pct"]) / 100.0 \
			- float(agent["skill"]) * float(rules["spy_skill_detection_reduction_pct"]) / 100.0
		chance = maxf(chance, float(rules["spy_detection_min_chance"]))
		if rng.chance(chance):
			agent["alive"] = false
			state["agents"].erase(agent_id)
			notices.append({"kind": "agent_caught", "agent_kind": agent["kind"],
				"faction": agent["owner"], "region": region, "by": settlement["owner"]})
			continue

		var seasoning := int(rules["spy_skill_gain_turns_abroad"])
		if seasoning > 0 and int(agent["turns_abroad"]) % seasoning == 0:
			agent["skill"] = mini(int(agent["skill"]) + 1, int(rules["skill_max"]))
	return notices


static func reset_movement(data: GameData, state: Dictionary) -> void:
	for agent in state.get("agents", {}).values():
		var kind: Dictionary = data.agent_kinds.get(agent["kind"], {})
		agent["movement_left"] = float(kind.get("movement", 3))


static func faction_upkeep(data: GameData, state: Dictionary, faction_id: String) -> int:
	var upkeep := 0
	for agent in state.get("agents", {}).values():
		if agent["alive"] and agent["owner"] == faction_id:
			upkeep += int(data.agent_kinds.get(agent["kind"], {}).get("upkeep", 0))
	return upkeep


static func agents_in(state: Dictionary, region_id: String, owner: String = "") -> Array:
	## Agent ids standing in a region, optionally one faction's only. Sorted.
	var found: Array = []
	var agent_ids: Array = state.get("agents", {}).keys()
	agent_ids.sort()
	for agent_id in agent_ids:
		var agent: Dictionary = state["agents"][agent_id]
		if agent["alive"] and agent["region"] == region_id \
				and (owner == "" or agent["owner"] == owner):
			found.append(agent_id)
	return found


static func has_envoy_with(data: GameData, state: Dictionary, faction_id: String, other_id: String) -> bool:
	## Negotiation needs an envoy of ours standing on their soil.
	for agent in state.get("agents", {}).values():
		if not agent["alive"] or agent["owner"] != faction_id or agent["kind"] != "diplomat":
			continue
		var settlement: Dictionary = state["settlements"].get(agent["region"], {})
		if not settlement.is_empty() and settlement["owner"] == other_id:
			return true
	return false


## --- Internals ------------------------------------------------------------

static func _sea_leg(data: GameData, state: Dictionary, agent: Dictionary, target: String) -> bool:
	## Cross toward the target's coast, whole-turn like an army's crossing.
	var cost := float(data.balance["movement"]["sea_move_cost"])
	if cost > float(agent["movement_left"]) + 0.0001:
		return false
	var from_zones: Array = data.regions.get(agent["region"], {}).get("sea_zones", [])
	if from_zones.is_empty():
		return false
	var candidates: Array = [target]
	for neighbor in data.regions[target].get("adjacent", []):
		candidates.append(neighbor)
	candidates.sort()
	for candidate in candidates:
		if candidate == agent["region"]:
			continue
		var to_zones: Array = data.regions.get(candidate, {}).get("sea_zones", [])
		if to_zones.is_empty():
			continue
		var connected := false
		for zone in from_zones:
			if to_zones.has(zone):
				connected = true
				break
			for adjacent_zone in data.sea_zones.get(zone, {}).get("adjacent", []):
				if to_zones.has(adjacent_zone):
					connected = true
					break
		if connected:
			agent["movement_left"] = 0.0
			agent["region"] = candidate
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


static func _count_of_kind(state: Dictionary, faction_id: String, kind_id: String) -> int:
	var count := 0
	for agent in state.get("agents", {}).values():
		if agent["alive"] and agent["owner"] == faction_id and agent["kind"] == kind_id:
			count += 1
	return count
