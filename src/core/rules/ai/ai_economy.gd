class_name AiEconomy
## Settlement stewardship for one AI faction's turn: keep the capital somewhere
## it still rules, tax as high as public order safely bears, retrain mauled
## garrisons, recruit toward threat-based garrison floors (raised for rioting
## cities and for the very rich), and build by data-tuned priorities.
## Deterministic throughout: sorted iteration, no randomness, and every
## threshold from data/balance.json.


static func fix_capital(data: GameData, state: Dictionary, faction_id: String) -> void:
	## A house whose capital has fallen rules from its largest remaining city
	## (corruption and unrest both measure distance to the capital, so a lost
	## capital quietly poisons the whole economy).
	var faction: Dictionary = state["factions"][faction_id]
	var capital: String = faction["capital"]
	if capital != "" and state["settlements"].has(capital) \
			and state["settlements"][capital]["owner"] == faction_id:
		return
	var best := ""
	var best_population := -1
	for region_id in AiAssess.owned_regions(state, faction_id):
		var population := int(state["settlements"][region_id]["population"])
		if population > best_population:
			best = region_id
			best_population = population
	if best != "":
		faction["capital"] = best


static func take_turn(data: GameData, state: Dictionary, faction_id: String, context: Dictionary) -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	var faction: Dictionary = state["factions"][faction_id]
	var owned := AiAssess.owned_regions(state, faction_id)

	for region_id in owned:
		_set_tax(data, state, region_id)

	if int(faction["treasury"]) > int(ai_rules["treasury_reserve"]):
		for region_id in owned:
			RecruitmentRules.retrain_garrison(data, state, region_id)

	if int(faction["treasury"]) < int(ai_rules["shed_debt_treasury"]):
		_shed_debt(data, state, faction_id, owned)

	var projected_net := float(EconomyRules.faction_turn_breakdown(data, state, faction_id, null)["net"])
	for region_id in owned:
		projected_net -= _recruit(data, state, faction_id, region_id, context, projected_net)

	if not context["is_rebel"]:
		for region_id in owned:
			_build(data, state, faction_id, region_id)


## --- Taxes ----------------------------------------------------------------

static func _set_tax(data: GameData, state: Dictionary, region_id: String) -> void:
	## The highest tax level projected to keep order clear of the riot line by
	## the configured margin. Projection swaps only the tax factor — the other
	## factors don't move with taxes (growth coupling is second-order and the
	## margin absorbs it). Raising taxes demands extra clearance
	## (tax_raise_hysteresis) so border-line settlements don't flap between
	## levels every season.
	var order_rules: Dictionary = data.balance["public_order"]
	var settlement: Dictionary = state["settlements"][region_id]
	var floor_needed := float(order_rules["riot_threshold"]) \
		+ float(data.balance["ai"]["order_safety_margin"])
	var hysteresis := float(data.balance["ai"]["tax_raise_hysteresis"])

	var current_total := PublicOrderRules.total(data, state, region_id)
	var tax_table: Dictionary = order_rules["tax_happiness"]
	var current_level: String = settlement["tax_level"]
	var current_rank := Constants.TAX_LEVELS.find(current_level)
	var current_bonus := float(tax_table[current_level])

	var levels := Constants.TAX_LEVELS.duplicate()
	levels.reverse()  # very_high first
	for level in levels:
		var clearance := floor_needed
		if Constants.TAX_LEVELS.find(level) > current_rank:
			clearance += hysteresis
		if float(current_total) - current_bonus + float(tax_table[level]) >= clearance:
			settlement["tax_level"] = level
			return
	settlement["tax_level"] = "very_low"


## --- Debt -----------------------------------------------------------------

static func _shed_debt(data: GameData, state: Dictionary, faction_id: String, owned: Array) -> void:
	## A treasury deep in the red sheds one thing a turn before the engine's
	## forced disbandment bites: the costliest fleet ship first (fleets earn
	## nothing until naval phases exist), then the weakest garrison unit from
	## the calmest settlement that still keeps a guard behind.
	var fleet_ids: Array = state["fleets"].keys()
	fleet_ids.sort()
	var worst_fleet := ""
	var worst_index := -1
	var worst_upkeep := -1
	for fleet_id in fleet_ids:
		var fleet: Dictionary = state["fleets"][fleet_id]
		if fleet["owner"] != faction_id:
			continue
		for i in range(fleet["ships"].size()):
			var upkeep := int(data.units.get(fleet["ships"][i]["template"], {}).get("upkeep", 0))
			if upkeep > worst_upkeep:
				worst_fleet = fleet_id
				worst_index = i
				worst_upkeep = upkeep
	if worst_fleet != "":
		state["fleets"][worst_fleet]["ships"].remove_at(worst_index)
		if state["fleets"][worst_fleet]["ships"].is_empty():
			state["fleets"].erase(worst_fleet)
		return

	var threat_rank := {"interior": 0, "frontier": 1, "threatened": 2}
	var pick := ""
	var pick_rank := 3
	for region_id in owned:
		if state["settlements"][region_id]["garrison"].size() < 2:
			continue
		var rank: int = threat_rank[AiAssess.threat_level(data, state, region_id)]
		if rank < pick_rank:
			pick = region_id
			pick_rank = rank
	if pick == "":
		return
	var garrison: Array = state["settlements"][pick]["garrison"]
	var weakest := 0
	var weakest_power := AiAssess.unit_power(data, [garrison[0]])
	for i in range(1, garrison.size()):
		var power := AiAssess.unit_power(data, [garrison[i]])
		if power < weakest_power:
			weakest = i
			weakest_power = power
	garrison.remove_at(weakest)


## --- Recruitment ----------------------------------------------------------

static func _recruit(data: GameData, state: Dictionary, faction_id: String, region_id: String, context: Dictionary, projected_net: float) -> float:
	## Fill the garrison toward its threat floor — raised while a rioting city
	## needs the garrison order bonus, and for very rich factions, whose
	## surplus should stand on walls rather than pile in the treasury. Returns
	## the upkeep of any unit queued (the caller keeps the faction-wide
	## net-income projection).
	var ai_rules: Dictionary = data.balance["ai"]
	var settlement: Dictionary = state["settlements"][region_id]
	if not settlement["recruitment_queue"].is_empty():
		return 0.0

	var faction: Dictionary = state["factions"][faction_id]
	var rich := int(faction["treasury"]) > int(ai_rules["rich_treasury"])
	var threat := AiAssess.threat_level(data, state, region_id)
	var unrest := PublicOrderRules.total(data, state, region_id) \
		< float(data.balance["public_order"]["riot_threshold"])
	var floor_units := AiMilitary.garrison_floor(data, state, region_id)
	if unrest:
		floor_units = maxi(floor_units, int(ai_rules["garrison_units_unrest"]))
	if rich:
		floor_units += int(ai_rules["rich_garrison_bonus_units"])
	if region_id == context["staging"] and context["wants_muster"]:
		floor_units += int(ai_rules["muster_min_units"])
	if settlement["garrison"].size() >= floor_units:
		return 0.0

	var budget := int(faction["treasury"]) - int(ai_rules["treasury_reserve"])
	var best := {}
	var best_power := 0.0
	for unit in RecruitmentRules.available_units(data, state, region_id):
		if int(unit["cost"]) > budget:
			continue
		# Recruiting into the red is for settlements under the gun, cities on
		# the edge of riot, and treasuries deep enough to bleed a while.
		if threat != "threatened" and not unrest and not rich \
				and projected_net - float(unit["upkeep"]) < 0.0:
			continue
		var power := AiAssess.unit_power(data,
			[{"template": unit["id"], "experience": 0, "strength_pct": 100}])
		if best.is_empty() or power > best_power \
				or (power == best_power and int(unit["cost"]) < int(best["cost"])):
			best = unit
			best_power = power
	if best.is_empty():
		return 0.0
	if RecruitmentRules.queue_unit(data, state, region_id, best["id"]):
		return float(best["upkeep"])
	return 0.0


## --- Construction ---------------------------------------------------------

static func _build(data: GameData, state: Dictionary, faction_id: String, region_id: String) -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	var settlement: Dictionary = state["settlements"][region_id]
	if not settlement["construction_queue"].is_empty():
		return
	var faction: Dictionary = state["factions"][faction_id]
	var budget := int(faction["treasury"]) - int(ai_rules["treasury_reserve"])
	if budget <= 0:
		return

	var order_rules: Dictionary = data.balance["public_order"]
	var order_low := PublicOrderRules.total(data, state, region_id) \
		< float(order_rules["riot_threshold"]) + float(ai_rules["order_safety_margin"])
	var threat := AiAssess.threat_level(data, state, region_id)
	var priorities: Dictionary = ai_rules["build_priority"]
	var frontier_bonus: Dictionary = ai_rules["frontier_build_bonus"]

	var best := {}
	var best_score := -1.0
	for project in ConstructionRules.available_projects(data, state, region_id):
		if int(project["cost"]) > budget:
			continue
		var score := float(priorities.get(project["kind"], ai_rules["build_priority_default"]))
		var effects: Dictionary = data.building_levels[project["level_id"]]["level"].get("effects", {})
		if order_low and (float(effects.get("happiness", 0)) > 0.0 or float(effects.get("law", 0)) > 0.0):
			score += float(ai_rules["order_need_build_bonus"])
		if threat != "interior":
			score += float(frontier_bonus.get(project["kind"], 0.0))
		if best.is_empty() or score > best_score \
				or (score == best_score and int(project["cost"]) < int(best["cost"])) \
				or (score == best_score and int(project["cost"]) == int(best["cost"])
					and String(project["chain"]) < String(best["chain"])):
			best = project
			best_score = score
	if not best.is_empty():
		ConstructionRules.queue_project(data, state, region_id, best["chain"])
