class_name ArmyRules
## Composition queries over a unit array (a field army, a garrison, a fleet).
## Shares are SLOT shares: every unit card counts strength_pct/100 of a slot,
## whatever its headcount, so an 18-man elephant unit weighs as much in the
## line of battle as a 160-man phalanx — which is how the player reads an
## army list, and how the auto-resolver reads a composition.


static func class_of(data: GameData, template_id: String) -> String:
	return String(data.units.get(template_id, {}).get("class", ""))


static func soldiers(data: GameData, units: Array) -> int:
	var total := 0
	for unit in units:
		var template: Dictionary = data.units.get(unit["template"], {})
		total += int(ceil(int(template.get("soldiers", 0)) * int(unit["strength_pct"]) / 100.0))
	return total


static func shares(data: GameData, units: Array) -> Dictionary:
	## {class: share of slots}, keys sorted; {} for an empty or unknown force.
	var slots := {}
	var total := 0.0
	for unit in units:
		var unit_class := class_of(data, unit["template"])
		if unit_class == "":
			continue
		var weight := float(unit["strength_pct"]) / 100.0
		slots[unit_class] = float(slots.get(unit_class, 0.0)) + weight
		total += weight
	var result := {}
	if total <= 0.0:
		return result
	var classes: Array = slots.keys()
	classes.sort()
	for unit_class in classes:
		result[unit_class] = float(slots[unit_class]) / total
	return result


static func composition(data: GameData, units: Array) -> Dictionary:
	## {class: {units: float slots, cards: int, soldiers: int, share: float}}, keys sorted.
	var by_class := {}
	var total_slots := 0.0
	for unit in units:
		var template: Dictionary = data.units.get(unit["template"], {})
		var unit_class: String = template.get("class", "")
		if unit_class == "":
			continue
		var weight := float(unit["strength_pct"]) / 100.0
		var entry: Dictionary = by_class.get(unit_class, {"units": 0.0, "cards": 0, "soldiers": 0, "share": 0.0})
		entry["units"] = float(entry["units"]) + weight
		entry["cards"] = int(entry["cards"]) + 1
		entry["soldiers"] = int(entry["soldiers"]) \
			+ int(ceil(int(template.get("soldiers", 0)) * int(unit["strength_pct"]) / 100.0))
		by_class[unit_class] = entry
		total_slots += weight
	var result := {}
	var classes: Array = by_class.keys()
	classes.sort()
	for unit_class in classes:
		var entry: Dictionary = by_class[unit_class]
		entry["share"] = float(entry["units"]) / total_slots if total_slots > 0.0 else 0.0
		result[unit_class] = entry
	return result


static func role_shares(data: GameData, units: Array) -> Dictionary:
	## {role: share} through data.unit_classes (line / shock / missile / ...).
	## Classes without a record are skipped, so the result is {} until the
	## unit-classes table is loaded.
	var result := {}
	var class_shares := shares(data, units)
	for unit_class in class_shares:
		var record: Dictionary = data.unit_classes.get(unit_class, {})
		if record.is_empty():
			continue
		var role: String = record.get("role", "")
		result[role] = float(result.get(role, 0.0)) + float(class_shares[unit_class])
	return result


static func summary(data: GameData, units: Array) -> Dictionary:
	## What a scroll shows about a force: men, cards, class mix, veterancy, kit.
	var total_experience := 0.0
	var total_weapon := 0.0
	var total_armor := 0.0
	for unit in units:
		total_experience += float(unit.get("experience", 0))
		total_weapon += float(unit.get("weapon", 0))
		total_armor += float(unit.get("armor", 0))
	var count := units.size()
	return {
		"units": count,
		"soldiers": soldiers(data, units),
		"by_class": composition(data, units),
		"avg_experience": total_experience / count if count > 0 else 0.0,
		"weapon_avg": total_weapon / count if count > 0 else 0.0,
		"armor_avg": total_armor / count if count > 0 else 0.0,
	}
