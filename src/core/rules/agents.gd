class_name AgentRules
## Campaign agents (Phase 5): diplomats, spies and assassins as pieces on the
## map. Agents live in state["agents"] as
##   {owner, kind, name, region, skill, movement_left}
## and are erased outright when lost — nothing references an agent by id.
##
## This module is where the two long-dormant authored effects finally get
## their engine readers: `personal_security` on a character (traits and
## retinue) defends him against assassination, and `agent_skill` on a
## GOVERNOR's retinue is counter-intelligence — his spy-catchers and food
## tasters make every hostile agent's work harder in his city. All odds
## constants live in balance.json → agents; kinds are data/agents.json.


static func recruit_agent(data: GameData, state: Dictionary, region_id: String, kind: String) -> String:
	## Returns the new agent's id, or "" when the gate, cap or purse refuses.
	var template: Dictionary = data.agent_kinds.get(kind, {})
	if template.is_empty() or not state["settlements"].has(region_id):
		return ""
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = settlement["owner"]
	if not building_gate_met(data, settlement, template):
		return ""
	var owned := 0
	for agent in state["agents"].values():
		if agent["owner"] == owner:
			owned += 1
	if owned >= int(data.balance["agents"]["max_per_faction"]):
		return ""
	var faction: Dictionary = state["factions"][owner]
	if int(faction["treasury"]) < int(template["cost"]):
		return ""
	faction["treasury"] = int(faction["treasury"]) - int(template["cost"])

	# Names come from the culture's pool WITHOUT an rng draw — recruit is a
	# player action and must not steer the campaign's random stream.
	var pool: Dictionary = data.names.get(data.culture_of_faction(owner), data.names.get("roman", {}))
	var name_list: Array = pool.get("male", ["Nameless"])
	var agent_id := "agent_%d" % state["next_id"]
	state["next_id"] = int(state["next_id"]) + 1
	state["agents"][agent_id] = {
		"owner": owner,
		"kind": kind,
		"name": String(name_list[int(state["next_id"]) % name_list.size()]),
		"region": region_id,
		"skill": int(template["base_skill"]),
		"movement_left": 0.0,
	}
	return agent_id


static func move_agent(data: GameData, state: Dictionary, agent_id: String, to_region: String) -> bool:
	## Agents walk the same terrain costs as armies but pass ANY border —
	## slipping into hostile lands is their entire trade.
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or not data.regions.has(to_region):
		return false
	if not MapRules.are_adjacent(data, agent["region"], to_region):
		return false
	var cost := MovementRules.step_cost(data, state, to_region)
	if cost > float(agent["movement_left"]) + 0.0001:
		return false
	agent["movement_left"] = float(agent["movement_left"]) - cost
	agent["region"] = to_region
	return true


static func scout_report(data: GameData, state: Dictionary, agent_id: String) -> Dictionary:
	## A spy's read of the settlement he stands in: garrison, works, mood.
	## Pure query — no state change, no rng.
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or agent["kind"] != "spy":
		return {}
	var region_id: String = agent["region"]
	if not state["settlements"].has(region_id):
		return {}
	var settlement: Dictionary = state["settlements"][region_id]
	var garrison: Array = []
	for unit in settlement["garrison"]:
		garrison.append({
			"name": data.units.get(unit["template"], {}).get("name", unit["template"]),
			"strength_pct": int(unit["strength_pct"]),
		})
	var buildings: Array = []
	var chain_ids: Array = settlement["buildings"].keys()
	chain_ids.sort()
	for chain_id in chain_ids:
		var chain: Dictionary = data.chains.get(chain_id, {})
		var tier := mini(int(settlement["buildings"][chain_id]), chain.get("levels", []).size())
		if tier > 0:
			buildings.append(String(chain["levels"][tier - 1]["name"]))
	return {
		"region": region_id,
		"owner": settlement["owner"],
		"population": int(settlement["population"]),
		"public_order": PublicOrderRules.total(data, state, region_id),
		"garrison": garrison,
		"buildings": buildings,
		"under_siege": settlement["siege"] != null,
	}


static func assassination_chance(data: GameData, state: Dictionary, agent: Dictionary, target: Dictionary) -> float:
	## The exposed odds formula, so the UI can warn before the knife is drawn.
	var rules: Dictionary = data.balance["agents"]
	var security := CharacterRules.effect_total(data, target, "personal_security")
	var counter := counter_intelligence(data, state, String(agent["region"]))
	var chance := float(rules["assassinate_base_chance"]) \
		+ float(agent["skill"]) * float(rules["assassinate_per_skill"]) \
		- security * float(rules["assassinate_per_security"]) \
		- counter * float(rules["assassinate_per_counter_intel"])
	return clampf(chance, float(rules["assassinate_min_chance"]), float(rules["assassinate_max_chance"]))


static func assassinate(data: GameData, state: Dictionary, rng: CampaignRng, agent_id: String, target_char_id: String) -> Dictionary:
	## Returns {attempted, success, agent_lost, chance}. Success settles the
	## succession at once (CharacterRules.kill); failure risks the blade.
	var refused := {"attempted": false, "success": false, "agent_lost": false, "chance": 0.0}
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or agent["kind"] != "assassin":
		return refused
	var target: Dictionary = state["characters"].get(target_char_id, {})
	if target.is_empty() or not target["alive"]:
		return refused
	if target.get("location", "") != agent["region"]:
		return refused
	if target["faction"] == agent["owner"]:
		return refused  # the house does not eat its own

	var rules: Dictionary = data.balance["agents"]
	var chance := assassination_chance(data, state, agent, target)
	var result := {"attempted": true, "success": false, "agent_lost": false, "chance": chance}
	if rng.chance(chance):
		CharacterRules.kill(state, target_char_id, data)
		agent["skill"] = mini(int(agent["skill"]) + 1, int(rules["skill_max"]))
		result["success"] = true
	elif rng.chance(float(rules["failure_death_chance"])):
		state["agents"].erase(agent_id)
		result["agent_lost"] = true
	agent["movement_left"] = 0.0
	return result


static func bribe_cost(data: GameData, army: Dictionary) -> int:
	## Soldiers priced per head, veterans dearer. Deterministic.
	var rules: Dictionary = data.balance["agents"]
	var cost := 0.0
	for unit in army["units"]:
		var template: Dictionary = data.units.get(unit["template"], {})
		var soldiers := ceilf(int(template.get("soldiers", 0)) * int(unit["strength_pct"]) / 100.0)
		cost += soldiers * float(rules["bribe_cost_per_soldier"]) \
			* (1.0 + float(unit.get("experience", 0)) * float(rules["bribe_experience_factor"]))
	return int(ceil(cost))


static func bribe_army(data: GameData, state: Dictionary, agent_id: String, army_id: String) -> Dictionary:
	## A diplomat pays a leaderless band to go home. Armies under a general
	## refuse outright — men follow the man, not the purse. No rng: the coin
	## either suffices or it does not.
	var refused := {"attempted": false, "success": false, "cost": 0}
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or agent["kind"] != "diplomat":
		return refused
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or army["owner"] == agent["owner"] or army["region"] != agent["region"]:
		return refused
	if army["general"] != null:
		return {"attempted": true, "success": false, "cost": 0, "refused_loyal": true}
	var cost := bribe_cost(data, army)
	var faction: Dictionary = state["factions"][agent["owner"]]
	var result := {"attempted": true, "success": false, "cost": cost}
	if int(faction["treasury"]) < cost:
		return result
	faction["treasury"] = int(faction["treasury"]) - cost
	state["armies"].erase(army_id)
	agent["movement_left"] = 0.0
	result["success"] = true
	return result


static func infiltration_bonus(data: GameData, state: Dictionary, region_id: String, attacker_owner: String) -> int:
	## A spy inside the city opens a gate: the assault fights the walls one
	## tier lower. The BattleResolver contract is untouched — only the
	## wall_level context it receives changes.
	for agent in state["agents"].values():
		if agent["kind"] == "spy" and agent["owner"] == attacker_owner \
				and agent["region"] == region_id:
			return int(data.balance["agents"]["infiltration_wall_reduction"])
	return 0


static func counter_intelligence(data: GameData, state: Dictionary, region_id: String) -> float:
	## The governor's spy-catchers and food tasters (retinue/trait agent_skill)
	## harden his city against hostile agents — the dormant effect's reader.
	if not state["settlements"].has(region_id):
		return 0.0
	var governor = state["settlements"][region_id]["governor"]
	if governor == null or not state["characters"].has(governor):
		return 0.0
	return CharacterRules.effect_total(data, state["characters"][governor], "agent_skill")


static func envoy_bonus(data: GameData, state: Dictionary, from_id: String, to_id: String) -> float:
	## A diplomat at the other side's court sweetens the terms on the table.
	var rules: Dictionary = data.balance["agents"]
	var best := 0.0
	for agent in state["agents"].values():
		if agent["kind"] != "diplomat" or agent["owner"] != from_id:
			continue
		var region: String = agent["region"]
		if state["settlements"].has(region) and state["settlements"][region]["owner"] == to_id:
			best = maxf(best, float(agent["skill"]) * float(rules["envoy_offer_bonus_per_skill"]))
	return best


static func steal_chance(data: GameData, state: Dictionary, agent: Dictionary) -> float:
	## Exposed odds for stealing a craft from the city the spy stands in, so
	## the UI can price the risk. Counter-intelligence is the governor's
	## agent_skill, same as assassination.
	var rules: Dictionary = data.balance["knowledge"]
	var counter := counter_intelligence(data, state, String(agent["region"]))
	var chance := float(rules["steal_base_chance"]) \
		+ float(agent["skill"]) * float(rules["steal_per_skill"]) \
		- counter * float(rules["steal_per_counter_intel"])
	return clampf(chance, float(rules["steal_min_chance"]), float(rules["steal_max_chance"]))


static func steal_technique(data: GameData, state: Dictionary, rng: CampaignRng, agent_id: String, technique_id: String) -> Dictionary:
	## A spy copies drawings, hires away a master craftsman, bribes a clerk of
	## the works: success brings home AWARENESS of a craft the city's owner has
	## institutionalized, plus a head start on adopting it (the espionage
	## discount). Failure risks the spy. Returns
	## {attempted, success, agent_lost, chance}.
	var refused := {"attempted": false, "success": false, "agent_lost": false, "chance": 0.0}
	var agent: Dictionary = state["agents"].get(agent_id, {})
	if agent.is_empty() or agent["kind"] != "spy":
		return refused
	var region_id: String = agent["region"]
	if not state["settlements"].has(region_id):
		return refused
	var owner: String = state["settlements"][region_id]["owner"]
	if owner == agent["owner"]:
		return refused
	# The city cannot teach what its masters do not practice.
	var source: Dictionary = KnowledgeRules.knowledge_of(state, owner)
	if String(source.get(technique_id, {}).get("stage", "")) != "adopted":
		return refused
	# A court already aware (however it learned) has nothing left to steal —
	# awareness IS the stolen good.
	var thief_knowledge := KnowledgeRules.knowledge_of(state, String(agent["owner"]))
	if String(thief_knowledge.get(technique_id, {}).get("stage", "")) != "":
		return refused

	var rules: Dictionary = data.balance["knowledge"]
	var chance := steal_chance(data, state, agent)
	var result := {"attempted": true, "success": false, "agent_lost": false, "chance": chance}
	if rng.chance(chance):
		thief_knowledge[technique_id] = {
			"stage": "aware", "turn": int(state["turn"]), "progress": 0,
			"discount_pct": float(rules["espionage_discount_pct"]),
		}
		agent["skill"] = mini(int(agent["skill"]) + 1, int(data.balance["agents"]["skill_max"]))
		result["success"] = true
	elif rng.chance(float(rules["steal_failure_death_chance"])):
		state["agents"].erase(agent_id)
		result["agent_lost"] = true
	agent["movement_left"] = 0.0
	return result


static func reset_movement(data: GameData, state: Dictionary) -> void:
	for agent in state["agents"].values():
		agent["movement_left"] = float(data.agent_kinds.get(agent["kind"], {}).get("movement_points", 2))


static func building_gate_met(data: GameData, settlement: Dictionary, template: Dictionary) -> bool:
	var needed_kind: String = template["building_kind"]
	var needed_level := int(template["building_level"])
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.get("kind", "") != needed_kind:
			continue
		if int(settlement["buildings"][chain_id]) >= needed_level:
			return true
	return false
