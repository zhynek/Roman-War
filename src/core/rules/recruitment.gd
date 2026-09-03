class_name RecruitmentRules
## Unit recruitment: gated by faction + culture buildings, paid in denarii and
## population (soldiers are drawn from the settlement's people). What a town
## has built also decides what its recruits carry: drill grounds, war temples
## and practiced techniques give starting experience; forges, armouries and
## metallurgy issue weapon and armour levels. Pressing men into service also
## strains the town (levy_strain), softened by its drill yards.


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
	var cost := recruit_cost(data, state, settlement["owner"], template)
	if int(faction["treasury"]) < cost:
		return false
	var soldiers := int(template["soldiers"])
	var min_population := int(data.balance["growth"]["min_population"])
	if int(settlement["population"]) - soldiers < min_population:
		return false

	faction["treasury"] = int(faction["treasury"]) - cost
	add_levy_strain(data, state, region_id, soldiers)
	settlement["population"] = int(settlement["population"]) - soldiers
	SocietyRules.record_recruitment(data, state, region_id, soldiers)
	settlement["recruitment_queue"].append({
		"template": template_id,
		"turns_left": 1,
	})
	return true


static func recruit_profile(data: GameData, state: Dictionary, region_id: String, template_id: String = "") -> Dictionary:
	## What a unit raised or refitted in this settlement receives. Experience:
	## the best drill-style recruit_xp building, the crafts the people have
	## practiced (faction-wide and per unit class), the standing edicts in
	## force and a guided-trail boon. Kit: the weapon and armour levels its
	## forges, armouries, war temples and metallurgy can issue (summed across
	## chains, capped by balance.recruitment.upgrade_max plus any technique
	## that raises the cap). Quality is stamped on the unit at the moment it
	## is raised and travels with it: a legion equipped in a city with good
	## forges stays well equipped wherever it marches.
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = String(settlement["owner"])
	var recruitment_rules: Dictionary = data.balance["recruitment"]
	var boon_xp := int(state["factions"][owner].get("boons", {}).get("recruit_xp", 0))
	var experience := int(SettlementRules.effect_max(data, settlement, "recruit_xp")) \
		+ int(KnowledgeRules.faction_effect_total(data, state, owner, "recruit_xp")) \
		+ int(EdictRules.faction_effect_total(data, state, owner, "recruit_xp")) \
		+ boon_xp
	if template_id != "":
		experience += KnowledgeRules.class_recruit_xp(data, state, owner, ArmyRules.class_of(data, template_id))
	return {
		"experience": clampi(experience, 0, int(recruitment_rules["experience_max"])),
		"weapon": upgrade_level(data, state, settlement, "weapon_upgrade"),
		"armor": upgrade_level(data, state, settlement, "armor_upgrade"),
	}


static func upgrade_level(data: GameData, state: Dictionary, settlement: Dictionary, effect: String) -> int:
	## What the city can arm a recruit with today: its own forges and armouries
	## (building weapon/armor_upgrade effects, summed across chains) plus the
	## owner's practiced techniques, capped by balance.recruitment.upgrade_max
	## and any technique that raises the cap (upgrade_cap).
	var owner := String(settlement["owner"])
	var cap := int(data.balance["recruitment"]["upgrade_max"]) \
		+ int(KnowledgeRules.faction_effect_total(data, state, owner, "upgrade_cap"))
	var total := SettlementRules.effect_total(data, settlement, effect) \
		+ KnowledgeRules.faction_effect_total(data, state, owner, effect)
	return clampi(int(total), 0, cap)


static func stamp_upgrades(unit: Dictionary, profile: Dictionary) -> void:
	## Issue the settlement's kit to a unit — never taking better kit away.
	for key in ["weapon", "armor"]:
		unit[key] = maxi(int(unit.get(key, 0)), int(profile.get(key, 0)))


static func advance_queues(data: GameData, state: Dictionary, region_id: String) -> Array:
	## One unit finishes per turn (the head of the queue). Finished units join
	## the garrison with the settlement's recruit profile: experience from
	## drill-style buildings, techniques, edicts and boons; kit from forges
	## and armouries — the weapons/armor stamp travels with the unit for life.
	var settlement: Dictionary = state["settlements"][region_id]
	var completed: Array = []
	var remaining: Array = []
	var first := true
	for job in settlement["recruitment_queue"]:
		if first:
			job["turns_left"] = int(job["turns_left"]) - 1
			first = false
		if int(job["turns_left"]) <= 0:
			var profile := recruit_profile(data, state, region_id, String(job["template"]))
			var unit := {
				"template": job["template"],
				"experience": int(profile["experience"]),
				"weapon": 0,
				"armor": 0,
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
	## Refill depleted garrison units, paying cost proportional to missing men.
	## Retraining is also RE-ARMING: every unit the city could recruit afresh is
	## brought up to the current weapons/armor standard, free — the forges and
	## techniques were the investment. Marching veterans home to re-arm is the
	## strategic move this buys.
	var settlement: Dictionary = state["settlements"][region_id]
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var kit := recruit_profile(data, state, region_id)
	var healed := 0
	for unit in settlement["garrison"]:
		var template: Dictionary = data.units.get(unit["template"], {})
		if not _requirements_met(data, settlement, template):
			continue
		stamp_upgrades(unit, kit)
		var strength := int(unit["strength_pct"])
		if strength >= 100:
			continue
		var missing_fraction := (100 - strength) / 100.0
		var cost_factor := float(data.balance["recruitment"]["retrain_cost_factor"])
		var cost := int(round(recruit_cost(data, state, settlement["owner"], template) \
			* missing_fraction * cost_factor))
		var men := int(round(int(template["soldiers"]) * missing_fraction))
		var min_population := int(data.balance["growth"]["min_population"])
		if int(faction["treasury"]) < cost or int(settlement["population"]) - men < min_population:
			continue
		faction["treasury"] = int(faction["treasury"]) - cost
		add_levy_strain(data, state, region_id, men)
		settlement["population"] = int(settlement["population"]) - men
		SocietyRules.record_recruitment(data, state, region_id, men)
		unit["strength_pct"] = 100
		healed += 1
	return healed


static func add_levy_strain(data: GameData, state: Dictionary, region_id: String, soldiers: int) -> void:
	## Pressing men into service leaves resentment in proportion to the share
	## of the town they were: strain points that weigh on order and growth and
	## fade each turn. Drill yards soften the levy; some techniques change it.
	var settlement: Dictionary = state["settlements"][region_id]
	var order_rules: Dictionary = data.balance["public_order"]
	var population := maxi(int(settlement["population"]), 1)
	var drill := SettlementRules.effect_total(data, settlement, "drill")
	var softening := maxf(0.0, 1.0 - drill * float(order_rules["levy_strain_drill_reduction_pct"]) / 100.0)
	var added := float(soldiers) / float(population) * float(order_rules["levy_strain_scale"]) * softening
	added *= maxf(0.0, 1.0 + KnowledgeRules.faction_effect_total(data, state, String(settlement["owner"]), "levy_strain_pct") / 100.0)
	settlement["levy_strain"] = SocietyRules.quantize(minf(float(settlement.get("levy_strain", 0.0)) + added,
		float(order_rules["levy_strain_max"])))


static func recruit_cost(data: GameData, state: Dictionary, faction_id: String, template: Dictionary) -> int:
	## Template cost under the owner's military edicts (the citizen levy
	## musters cheap, veteran land draws volunteers). Retraining prices off
	## the same number.
	return int(round(int(template.get("cost", 0)) * (1.0 + EdictRules.faction_effect_total(
		data, state, faction_id, "recruit_cost_pct") / 100.0)))


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
