class_name RecruitmentRules
## Unit recruitment: gated by faction + culture buildings, paid in denarii and
## population (soldiers are drawn from the settlement's people).


static func available_units(data: GameData, state: Dictionary, region_id: String) -> Array:
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = settlement["owner"]
	var faction: Dictionary = state["factions"][owner]
	var available: Array = []
	for unit in data.units_for_faction(owner):
		if unit.get("era", "any") != "any" and unit["era"] != faction["era"]:
			continue
		# The era gate generalized: a unit may require a PRACTICED technique
		# (the boarding bridge before corvus marines, and so on).
		var needed_technique: String = unit.get("requires_technique", "")
		if needed_technique != "" and not KnowledgeRules.adopted(state, owner, needed_technique):
			continue
		if unit["factions"].has("mercenary"):
			continue
		if not _requirements_met(data, settlement, unit):
			continue
		available.append(unit)
	return available


static func queue_unit(data: GameData, state: Dictionary, region_id: String, template_id: String) -> bool:
	var settlement: Dictionary = state["settlements"][region_id]
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var template: Dictionary = data.units.get(template_id, {})
	if template.is_empty():
		return false
	var allowed := false
	for unit in available_units(data, state, region_id):
		if unit["id"] == template_id:
			allowed = true
			break
	if not allowed:
		return false
	if int(faction["treasury"]) < int(template["cost"]):
		return false
	var soldiers := int(template["soldiers"])
	var min_population := int(data.balance["growth"]["min_population"])
	if int(settlement["population"]) - soldiers < min_population:
		return false

	faction["treasury"] = int(faction["treasury"]) - int(template["cost"])
	settlement["population"] = int(settlement["population"]) - soldiers
	settlement["recruitment_queue"].append({
		"template": template_id,
		"turns_left": 1,
	})
	return true


static func advance_queues(data: GameData, state: Dictionary, region_id: String) -> Array:
	## One unit finishes per turn (the head of the queue). Finished units join
	## the garrison with experience from blacksmith-style recruit_xp bonuses
	## (buildings and practiced techniques alike), armed to the city's current
	## standard — the weapons/armor stamp travels with the unit for life.
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = settlement["owner"]
	var completed: Array = []
	var remaining: Array = []
	var first := true
	for job in settlement["recruitment_queue"]:
		if first:
			job["turns_left"] = int(job["turns_left"]) - 1
			first = false
		if int(job["turns_left"]) <= 0:
			var experience := clampi(int(SettlementRules.effect_max(data, settlement, "recruit_xp")) \
				+ int(KnowledgeRules.faction_effect_total(data, state, owner, "recruit_xp")),
				0, int(data.balance["recruitment"]["experience_max"]))
			settlement["garrison"].append({
				"template": job["template"],
				"experience": experience,
				"strength_pct": 100,
				"weapons": upgrade_level(data, state, settlement, "weapon_upgrade"),
				"armor": upgrade_level(data, state, settlement, "armor_upgrade"),
			})
			completed.append(job["template"])
		else:
			remaining.append(job)
	settlement["recruitment_queue"] = remaining
	return completed


static func upgrade_level(data: GameData, state: Dictionary, settlement: Dictionary, effect: String) -> int:
	## What the city can arm a recruit with today: its own forges (building
	## weapon/armor_upgrade effects — authored since the foundation, read at
	## last) plus the owner's practiced techniques. Clamped 0–3.
	var total := SettlementRules.effect_total(data, settlement, effect) \
		+ KnowledgeRules.faction_effect_total(data, state, String(settlement["owner"]), effect)
	return clampi(int(total), 0, 3)


static func retrain_garrison(data: GameData, state: Dictionary, region_id: String) -> int:
	## Refill depleted garrison units, paying cost proportional to missing men.
	## Retraining is also RE-ARMING: every unit the city could recruit afresh is
	## brought up to the current weapons/armor standard, free — the forges and
	## techniques were the investment. Marching veterans home to re-arm is the
	## strategic move this buys.
	var settlement: Dictionary = state["settlements"][region_id]
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var weapons_now := upgrade_level(data, state, settlement, "weapon_upgrade")
	var armor_now := upgrade_level(data, state, settlement, "armor_upgrade")
	var healed := 0
	for unit in settlement["garrison"]:
		var template: Dictionary = data.units.get(unit["template"], {})
		if not _requirements_met(data, settlement, template):
			continue
		unit["weapons"] = maxi(int(unit.get("weapons", 0)), weapons_now)
		unit["armor"] = maxi(int(unit.get("armor", 0)), armor_now)
		var strength := int(unit["strength_pct"])
		if strength >= 100:
			continue
		var missing_fraction := (100 - strength) / 100.0
		var cost_factor := float(data.balance["recruitment"]["retrain_cost_factor"])
		var cost := int(round(int(template["cost"]) * missing_fraction * cost_factor))
		var men := int(round(int(template["soldiers"]) * missing_fraction))
		var min_population := int(data.balance["growth"]["min_population"])
		if int(faction["treasury"]) < cost or int(settlement["population"]) - men < min_population:
			continue
		faction["treasury"] = int(faction["treasury"]) - cost
		settlement["population"] = int(settlement["population"]) - men
		unit["strength_pct"] = 100
		healed += 1
	return healed


static func merge_units(units: Array) -> void:
	## Combine same-template depleted units in one force (highest experience kept).
	var index := 0
	while index < units.size():
		var unit: Dictionary = units[index]
		if int(unit["strength_pct"]) < 100:
			for j in range(units.size() - 1, index, -1):
				var other: Dictionary = units[j]
				if other["template"] != unit["template"]:
					continue
				var combined := int(unit["strength_pct"]) + int(other["strength_pct"])
				unit["strength_pct"] = mini(combined, 100)
				unit["experience"] = maxi(int(unit["experience"]), int(other["experience"]))
				unit["weapons"] = maxi(int(unit.get("weapons", 0)), int(other.get("weapons", 0)))
				unit["armor"] = maxi(int(unit.get("armor", 0)), int(other.get("armor", 0)))
				var leftover := combined - 100
				if leftover > 0:
					other["strength_pct"] = leftover
				else:
					units.remove_at(j)
				if int(unit["strength_pct"]) >= 100:
					break
		index += 1


static func _requirements_met(data: GameData, settlement: Dictionary, unit: Dictionary) -> bool:
	if unit.is_empty():
		return false
	var requirements: Dictionary = unit["requirements"]
	var needed_kind: String = requirements["building_kind"]
	var needed_level := int(requirements["building_level"])
	var needed_god: String = requirements.get("temple_god", "")
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty() or chain["kind"] != needed_kind:
			continue
		if needed_god != "" and chain.get("god", "") != needed_god:
			continue
		if int(settlement["buildings"][chain_id]) >= needed_level:
			return true
	return false
