class_name AiEconomy
## The AI's purse: taxes set as high as order allows, a garrison target per
## settlement (bigger where threatened, bigger still where the field army
## gathers), the best unit and the most useful building the treasury can bear
## beyond a reserve, and the agents the personality calls for. In debt it
## squeezes taxes and buys nothing.


static func act(data: GameData, state: Dictionary, rng: CampaignRng, brain: Dictionary, _notices: Array) -> void:
	var faction_id: String = brain["id"]
	var faction: Dictionary = state["factions"][faction_id]
	relocate_capital(data, state, brain)
	var owned := AiController.settlements_of(state, faction_id)
	var in_debt := int(faction["treasury"]) < 0
	for region_id in owned:
		set_taxes(data, state, brain, region_id, in_debt)
	if in_debt:
		shed_garrisons(data, state, brain)
		return
	var reserve := AiController.reserve_for(brain, owned.size())
	var muster := AiMilitary.muster_city(data, state, brain)
	for region_id in owned:
		recruit(data, state, brain, region_id, reserve, region_id == muster)
	for region_id in owned:
		if int(faction["treasury"]) > reserve:
			RecruitmentRules.retrain_garrison(data, state, region_id)
	for region_id in owned:
		build(data, state, brain, region_id, reserve)
	if not brain["is_rebel"]:
		train_agents(data, state, rng, brain, reserve)


static func relocate_capital(data: GameData, state: Dictionary, brain: Dictionary) -> void:
	## A capital lost to the enemy is replaced by the largest city still held,
	## so distance and corruption are measured from a seat the house has.
	var faction: Dictionary = state["factions"][brain["id"]]
	var capital: String = faction["capital"]
	if state["settlements"].has(capital) and state["settlements"][capital]["owner"] == brain["id"]:
		return
	var best := ""
	var best_population := -1
	for region_id in AiController.settlements_of(state, brain["id"]):
		var population := int(state["settlements"][region_id]["population"])
		if population > best_population:
			best = region_id
			best_population = population
	if best != "":
		faction["capital"] = best


static func shed_garrisons(data: GameData, state: Dictionary, brain: Dictionary) -> void:
	## In debt, every settlement above the floor lets its costliest unit go —
	## one a season each — so upkeep falls until the purse recovers.
	var rules: Dictionary = brain["rules"]
	var floor_units := int(rules["debt_garrison_floor"])
	for region_id in AiController.settlements_of(state, brain["id"]):
		var garrison: Array = state["settlements"][region_id]["garrison"]
		if garrison.size() <= floor_units:
			continue
		var worst := -1
		var worst_upkeep := -1
		for i in range(garrison.size()):
			var upkeep := int(data.units.get(garrison[i]["template"], {}).get("upkeep", 0))
			if upkeep > worst_upkeep:
				worst = i
				worst_upkeep = upkeep
		if worst >= 0:
			garrison.remove_at(worst)


## --- Taxes ---------------------------------------------------------------------

static func set_taxes(data: GameData, state: Dictionary, brain: Dictionary, region_id: String, in_debt: bool) -> void:
	## The highest rate that keeps order a margin above the riot line; the
	## greedy allow themselves the top rate, and debt allows a squeeze.
	var rules: Dictionary = brain["rules"]
	var settlement: Dictionary = state["settlements"][region_id]
	var max_index := int(rules["max_tax_index_base"])
	if AiController.weight(brain, "greed") >= float(rules["greed_top_tax_threshold"]):
		max_index += int(rules["max_tax_index_greed_bonus"])
	if in_debt:
		max_index = maxi(max_index, int(rules["debt_tax_index"]))
	max_index = mini(max_index, Constants.TAX_LEVELS.size() - 1)
	var floor_order := float(data.balance["public_order"]["riot_threshold"]) + float(rules["tax_order_margin"])
	var chosen := 0
	for index in range(max_index, -1, -1):
		settlement["tax_level"] = Constants.TAX_LEVELS[index]
		if index == 0 or PublicOrderRules.total(data, state, region_id) >= floor_order:
			chosen = index
			break
	settlement["tax_level"] = Constants.TAX_LEVELS[chosen]


## --- Recruitment ---------------------------------------------------------------------

static func desired_garrison(data: GameData, state: Dictionary, brain: Dictionary, region_id: String, muster: bool) -> int:
	var rules: Dictionary = brain["rules"]
	var settlement: Dictionary = state["settlements"][region_id]
	var units := int(rules["garrison_units_base"]) \
		+ int(int(settlement["population"]) / 5000) * int(rules["garrison_units_per_5000_pop"])
	if AiController.weight(brain, "caution") >= float(rules["caution_garrison_threshold"]):
		units += int(rules["garrison_units_caution_bonus"])
	if AiMilitary.threat_at(data, state, brain["id"], region_id) > 0.0:
		units += int(rules["garrison_units_threat_bonus"])
	units = mini(units, int(rules["garrison_units_cap"]))
	if muster:
		units += int(rules["field_army_min_units"])
	return units


static func recruit(data: GameData, state: Dictionary, brain: Dictionary, region_id: String, reserve: int, muster: bool) -> String:
	## Queues the unit with the best strength per denarius (cost plus a few
	## seasons of upkeep) the settlement can raise, while below its target.
	var rules: Dictionary = brain["rules"]
	var settlement: Dictionary = state["settlements"][region_id]
	if not settlement["recruitment_queue"].is_empty():
		return ""
	if settlement["garrison"].size() >= desired_garrison(data, state, brain, region_id, muster):
		return ""
	var faction: Dictionary = state["factions"][brain["id"]]
	var budget := mini(int(faction["treasury"]) - reserve,
		int(float(faction["treasury"]) * float(rules["recruit_max_cost_share_of_treasury"])))
	if budget <= 0:
		return ""
	var min_population := int(data.balance["growth"]["min_population"])
	var upkeep_turns := int(rules["recruit_upkeep_weight_turns"])
	var best := ""
	var best_score := 0.0
	for unit in RecruitmentRules.available_units(data, state, region_id):
		var cost := int(unit["cost"])
		if cost > budget or int(settlement["population"]) - int(unit["soldiers"]) < min_population:
			continue
		var strength := AiController.strength_of(data, [{"template": unit["id"], "experience": 0, "strength_pct": 100}])
		var score := strength / float(cost + int(unit["upkeep"]) * upkeep_turns)
		if score > best_score:
			best = unit["id"]
			best_score = score
	if best != "" and RecruitmentRules.queue_unit(data, state, region_id, best):
		return best
	return ""


## --- Construction ---------------------------------------------------------------------

static func build(data: GameData, state: Dictionary, brain: Dictionary, region_id: String, reserve: int) -> String:
	## Weighs every project the settlement could start: kind weights from the
	## balance table, raised for order-restoring buildings where order is low,
	## military buildings in wartime, walls on a frontier, health under
	## squalor; cheaper projects win ties. Returns the chain queued, or "".
	var rules: Dictionary = brain["rules"]
	var settlement: Dictionary = state["settlements"][region_id]
	if not settlement["construction_queue"].is_empty():
		return ""
	var faction: Dictionary = state["factions"][brain["id"]]
	var budget := int(faction["treasury"]) - reserve
	if budget <= 0:
		return ""
	var order := PublicOrderRules.total(data, state, region_id)
	var squalor := GrowthRules.squalor_pct(data, settlement)
	var at_war := not AiController.enemies_of(data, state, brain["id"]).is_empty()
	var frontier := AiMilitary.threat_at(data, state, brain["id"], region_id) > 0.0
	var weights: Dictionary = rules["build_weights"]
	var best := ""
	var best_score := -1.0
	for project in ConstructionRules.available_projects(data, state, region_id):
		var cost := int(project["cost"])
		if cost > budget:
			continue
		var kind: String = project["kind"]
		var weight := float(weights.get(kind, 1.0))
		var chain: Dictionary = data.chains[project["chain"]]
		var next_level: Dictionary = chain["levels"][int(settlement["buildings"].get(project["chain"], 0))]
		var effects: Dictionary = next_level.get("effects", {})
		if order < float(rules["build_order_low_threshold"]) \
				and (float(effects.get("happiness", 0.0)) > 0.0 or float(effects.get("law", 0.0)) > 0.0):
			weight *= float(rules["build_unrest_multiplier"])
		if at_war:
			weight *= float(rules["build_war_kind_multipliers"].get(kind, 1.0))
		if frontier and kind == "walls":
			weight *= float(rules["build_frontier_walls_multiplier"])
		if squalor >= float(rules["build_squalor_health_threshold"]) and kind == "health":
			weight *= float(rules["build_squalor_health_multiplier"])
		var score := weight * 1000.0 / float(cost + int(rules["build_cost_softening"]))
		if score > best_score:
			best = project["chain"]
			best_score = score
	if best != "" and ConstructionRules.queue_project(data, state, region_id, best):
		return best
	return ""


## --- Agents ---------------------------------------------------------------------------

static func train_agents(data: GameData, state: Dictionary, rng: CampaignRng, brain: Dictionary, reserve: int) -> String:
	## One agent a season at most, from the capital: an envoy if the house
	## talks at all, a spy for the home watch, more spies and an assassin for
	## the espionage-minded when there is a war to use them in.
	var rules: Dictionary = brain["rules"]
	var faction_id: String = brain["id"]
	var faction: Dictionary = state["factions"][faction_id]
	if int(faction["treasury"]) < reserve * int(rules["agent_reserve_multiplier"]):
		return ""
	# Agents train where the home watch stands, so the two never disagree.
	var capital := AiAgents.home_region(data, state, faction_id)
	if capital == "":
		return ""
	var available := {}
	for offer in AgentRules.kinds_available(data, state, capital):
		available[offer["id"]] = true
	var counts := {}
	var home_watch := 0
	for agent_id in AgentRules.agents_of(state, faction_id):
		var agent: Dictionary = state["agents"][agent_id]
		counts[agent["kind"]] = int(counts.get(agent["kind"], 0)) + 1
		if agent["region"] == capital and AgentRules.can(data, agent, "counter_espionage"):
			home_watch += 1
	var espionage := AiController.weight(brain, "espionage")
	var wanted := ""
	if AiController.weight(brain, "diplomacy") > 0.0 and int(counts.get("envoy", 0)) == 0 and available.has("envoy"):
		wanted = "envoy"
	elif home_watch == 0 and available.has("spy"):
		wanted = "spy"
	elif espionage >= float(rules["spy_abroad_min_espionage"]) \
			and int(counts.get("spy", 0)) < int(rules["spies_abroad_max"]) and available.has("spy"):
		wanted = "spy"
	elif espionage >= float(rules["assassin_min_espionage"]) and int(counts.get("assassin", 0)) == 0 \
			and available.has("assassin") and not AiController.enemies_of(data, state, faction_id).is_empty():
		wanted = "assassin"
	if wanted == "":
		return ""
	return AgentRules.recruit(data, state, rng, capital, wanted)
