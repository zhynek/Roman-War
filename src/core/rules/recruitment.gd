class_name RecruitmentRules
## Unit recruitment: gated by faction + culture buildings, paid in denarii and
## population (soldiers are drawn from the settlement's people). What a town
## has built also decides what its recruits carry: drill and war temples give
## starting experience, forges and armouries issue weapon and armour levels.


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
	add_levy_strain(data, state, region_id, soldiers)
	settlement["population"] = int(settlement["population"]) - soldiers
	settlement["recruitment_queue"].append({
		"template": template_id,
		"turns_left": 1,
	})
	return true


static func recruit_profile(data: GameData, state: Dictionary, region_id: String, _template_id: String = "") -> Dictionary:
	## What a unit raised or refitted in this settlement receives: starting
	## experience from the best drill-style recruit_xp building, and the weapon
	## and armour levels its forges, armouries and war temples can issue (summed
	## across chains, capped by balance.recruitment.upgrade_max).
	var settlement: Dictionary = state["settlements"][region_id]
	var recruitment_rules: Dictionary = data.balance["recruitment"]
	var upgrade_max := int(recruitment_rules["upgrade_max"])
	var experience := int(SettlementRules.effect_max(data, settlement, "recruit_xp"))
	return {
		"experience": clampi(experience, 0, int(recruitment_rules["experience_max"])),
		"weapon": clampi(int(SettlementRules.effect_total(data, settlement, "weapon_upgrade")), 0, upgrade_max),
		"armor": clampi(int(SettlementRules.effect_total(data, settlement, "armor_upgrade")), 0, upgrade_max),
	}


static func stamp_upgrades(unit: Dictionary, profile: Dictionary) -> void:
	## Issue the settlement's kit to a unit — never taking better kit away. The
	## keys are only written when non-zero, so an unarmed unit keeps the plain
	## {template, experience, strength_pct} shape.
	for key in ["weapon", "armor"]:
		var level := maxi(int(unit.get(key, 0)), int(profile.get(key, 0)))
		if level > 0:
			unit[key] = level


static func advance_queues(data: GameData, state: Dictionary, region_id: String) -> Array:
	## One unit finishes per turn (the head of the queue). Finished units join
	## the garrison with the settlement's recruit profile: experience from
	## drill-style buildings, kit from forges and armouries.
	var settlement: Dictionary = state["settlements"][region_id]
	var completed: Array = []
	var remaining: Array = []
	var first := true
	for job in settlement["recruitment_queue"]:
		if first:
			job["turns_left"] = int(job["turns_left"]) - 1
			first = false
		if int(job["turns_left"]) <= 0:
			var profile := recruit_profile(data, state, region_id, job["template"])
			var unit := {
				"template": job["template"],
				"experience": int(profile["experience"]),
				"strength_pct": 100,
			}
			stamp_upgrades(unit, profile)
			settlement["garrison"].append(unit)
			completed.append(job["template"])
		else:
			remaining.append(job)
	settlement["recruitment_queue"] = remaining
	return completed


static func retrain_garrison(data: GameData, state: Dictionary, region_id: String) -> int:
	## Refit the garrison to the town's current standard: every unit the town
	## could recruit draws its weapon and armour levels (never downgraded), and
	## depleted units are refilled, paying cost proportional to missing men.
	## Returns the number of units refilled.
	var settlement: Dictionary = state["settlements"][region_id]
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var healed := 0
	for unit in settlement["garrison"]:
		var template: Dictionary = data.units.get(unit["template"], {})
		if not _requirements_met(data, settlement, template):
			continue
		stamp_upgrades(unit, recruit_profile(data, state, region_id, unit["template"]))
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
		add_levy_strain(data, state, region_id, men)
		settlement["population"] = int(settlement["population"]) - men
		unit["strength_pct"] = 100
		healed += 1
	return healed


static func add_levy_strain(data: GameData, state: Dictionary, region_id: String, soldiers: int) -> void:
	## Pressing men into service leaves resentment in proportion to the share
	## of the town they were: strain points that weigh on order and growth and
	## fade each turn. Drill yards soften the levy (and some doctrines change it).
	var settlement: Dictionary = state["settlements"][region_id]
	var order_rules: Dictionary = data.balance["public_order"]
	var population := maxi(int(settlement["population"]), 1)
	var drill := SettlementRules.effect_total(data, settlement, "drill")
	var softening := maxf(0.0, 1.0 - drill * float(order_rules["levy_strain_drill_reduction_pct"]) / 100.0)
	var added := float(soldiers) / float(population) * float(order_rules["levy_strain_scale"]) * softening
	settlement["levy_strain"] = minf(float(settlement.get("levy_strain", 0.0)) + added,
		float(order_rules["levy_strain_max"]))


static func merge_units(units: Array) -> void:
	## Combine same-template depleted units in one force (highest experience
	## and the better kit kept).
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
				stamp_upgrades(unit, other)
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
