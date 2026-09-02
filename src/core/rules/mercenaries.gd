class_name MercenaryRules
## Regional mercenary pools: hired in the field by an army (a general's purse,
## not a settlement's barracks), replenishing slowly over the turns.


static func pool_for_region(data: GameData, region_id: String) -> Dictionary:
	for pool in data.mercenary_pools:
		if pool["regions"].has(region_id):
			return pool
	return {}


static func available(data: GameData, state: Dictionary, region_id: String, faction_id: String = "") -> Array:
	## Offers in this region; prices reflect the hiring faction's doctrines
	## (mercenary_cost_pct) when it is named.
	var pool := pool_for_region(data, region_id)
	if pool.is_empty():
		return []
	var counts: Dictionary = state["mercenary_pools"].get(pool["id"], {})
	var discount := 1.0
	if faction_id != "" and state["factions"].has(faction_id):
		discount = maxf(0.0, 1.0 + DoctrineRules.scalar(data, state, faction_id, "mercenary_cost_pct") / 100.0)
	var offers: Array = []
	for entry in pool["units"]:
		if int(counts.get(entry["template"], 0.0)) < 1:
			continue
		var template: Dictionary = data.units.get(entry["template"], {})
		offers.append({
			"template": entry["template"],
			"cost": int(round(int(template.get("cost", 0)) * float(entry["cost_multiplier"]) * discount)),
			"upkeep": int(template.get("upkeep", 0)),
			"in_pool": int(counts.get(entry["template"], 0.0)),
		})
	return offers


static func hire(data: GameData, state: Dictionary, army_id: String, template_id: String) -> bool:
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or army["units"].size() >= 20:
		return false
	var pool := pool_for_region(data, army["region"])
	if pool.is_empty():
		return false
	for offer in available(data, state, army["region"], army["owner"]):
		if offer["template"] != template_id:
			continue
		var faction: Dictionary = state["factions"][army["owner"]]
		if int(faction["treasury"]) < int(offer["cost"]):
			return false
		faction["treasury"] = int(faction["treasury"]) - int(offer["cost"])
		var counts: Dictionary = state["mercenary_pools"][pool["id"]]
		counts[template_id] = float(counts[template_id]) - 1.0
		army["units"].append({"template": template_id, "experience": 1, "strength_pct": 100})
		return true
	return false


static func replenish(data: GameData, state: Dictionary) -> void:
	for pool in data.mercenary_pools:
		var counts: Dictionary = state["mercenary_pools"].get(pool["id"], {})
		for entry in pool["units"]:
			var current := float(counts.get(entry["template"], 0.0))
			counts[entry["template"]] = minf(
				current + float(entry["replenish_per_turn"]), float(entry["max"]))
		state["mercenary_pools"][pool["id"]] = counts
