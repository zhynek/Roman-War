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
	## the garrison with experience from blacksmith-style recruit_xp bonuses.
	var settlement: Dictionary = state["settlements"][region_id]
	var completed: Array = []
	var remaining: Array = []
	var first := true
	for job in settlement["recruitment_queue"]:
		if first:
			job["turns_left"] = int(job["turns_left"]) - 1
			first = false
		if int(job["turns_left"]) <= 0:
			var experience := int(SettlementRules.effect_max(data, settlement, "recruit_xp"))
			settlement["garrison"].append({
				"template": job["template"],
				"experience": experience,
				"strength_pct": 100,
			})
			completed.append(job["template"])
		else:
			remaining.append(job)
	settlement["recruitment_queue"] = remaining
	return completed


static func retrain_garrison(data: GameData, state: Dictionary, region_id: String) -> int:
	## Refill depleted garrison units, paying cost proportional to missing men.
	var settlement: Dictionary = state["settlements"][region_id]
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var healed := 0
	for unit in settlement["garrison"]:
		var strength := int(unit["strength_pct"])
		if strength >= 100:
			continue
		var template: Dictionary = data.units.get(unit["template"], {})
		if not _requirements_met(data, settlement, template):
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
	return SettlementRules.building_tier(data, settlement, needed_kind, needed_god) >= needed_level
