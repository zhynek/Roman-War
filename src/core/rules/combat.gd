class_name CombatRules
## Campaign-side combat orchestration: field battles, settlement capture and the
## occupy / enslave / exterminate decision. All actual fighting goes through the
## injected BattleResolver — never assume auto-resolve here.


static func attack_army(data: GameData, state: Dictionary, resolver: BattleResolver, rng: CampaignRng, attacker_id: String, defender_id: String) -> Dictionary:
	var attacker: Dictionary = state["armies"][attacker_id]
	var defender: Dictionary = state["armies"][defender_id]
	if attacker["region"] != defender["region"] \
			and not MapRules.are_adjacent(data, attacker["region"], defender["region"]):
		return {}
	var region: Dictionary = data.regions[defender["region"]]

	var result := resolver.resolve(data, rng, attacker["units"], defender["units"], {
		"terrain": region["terrain"],
		"wall_level": 0,
		"attacker_general": _general_of(state, attacker),
		"defender_general": _general_of(state, defender),
		"attacker_fatigued": attacker.get("forced_march", false),
		"sally": false,
	})

	_process_general_deaths(state, attacker, defender, result)
	if result["winner"] == "attacker":
		attacker["region"] = defender["region"]
		attacker["movement_left"] = 0.0
	_cleanup_destroyed_army(state, attacker_id)
	_cleanup_destroyed_army(state, defender_id)
	return result


static func capture_settlement(data: GameData, state: Dictionary, rng: CampaignRng, region_id: String, new_owner: String, occupation: String) -> Dictionary:
	## occupation: "occupy" | "enslave" | "exterminate". Returns {loot, slaves}.
	var settlement: Dictionary = state["settlements"][region_id]
	var occupation_rules: Dictionary = data.balance["occupation"]
	var economy_rules: Dictionary = data.balance["economy"]
	var population := int(settlement["population"])
	var loot := 0
	var slaves := 0

	match occupation:
		"enslave":
			slaves = int(population * float(occupation_rules["enslave_population_removed_pct"]) / 100.0)
			population -= slaves
			loot = int(slaves * float(economy_rules["loot_per_enslaved_pop"]))
			_distribute_slaves(data, state, new_owner)
		"exterminate":
			var killed := int(population * float(occupation_rules["exterminate_population_killed_pct"]) / 100.0)
			population -= killed
			loot = int(killed * float(economy_rules["loot_per_exterminated_pop"]))
		_:
			occupation = "occupy"
			loot = int(population * float(economy_rules["loot_per_occupied_pop"]))

	var order_penalty := int(occupation_rules["%s_order_penalty" % occupation])
	var decay := int(data.balance["public_order"]["recently_conquered_decay_per_turn"])

	settlement["owner"] = new_owner
	settlement["population"] = maxi(population, 400)
	settlement["garrison"] = []
	settlement["construction_queue"] = []
	settlement["recruitment_queue"] = []
	settlement["governor"] = null
	settlement["siege"] = null
	settlement["low_order_streak"] = 0
	settlement["tax_level"] = "normal"
	settlement["recently_conquered"] = int(ceil(float(order_penalty) / float(maxi(decay, 1))))

	state["factions"][new_owner]["treasury"] = int(state["factions"][new_owner]["treasury"]) + loot

	# Losing your last settlement destroys the faction.
	_check_faction_destroyed(state)
	return {"loot": loot, "slaves": slaves, "occupation": occupation}


static func garrison_army(data: GameData, state: Dictionary, army_id: String, region_id: String) -> bool:
	## Merge a friendly army standing in its own settlement's region into the garrison.
	var army: Dictionary = state["armies"][army_id]
	if army["region"] != region_id or not state["settlements"].has(region_id):
		return false
	var settlement: Dictionary = state["settlements"][region_id]
	if settlement["owner"] != army["owner"]:
		return false
	for unit in army["units"]:
		settlement["garrison"].append(unit)
	if army["general"] != null and settlement["governor"] == null:
		settlement["governor"] = army["general"]
	state["armies"].erase(army_id)
	return true


static func _distribute_slaves(data: GameData, state: Dictionary, faction_id: String) -> void:
	var turns := int(data.balance["growth"]["slave_influx_turns"])
	for other in state["settlements"].values():
		if other["owner"] == faction_id and other["governor"] != null:
			other["slave_bonus_turns"] = turns


static func _general_of(state: Dictionary, army: Dictionary) -> Variant:
	if army["general"] != null and state["characters"].has(army["general"]):
		return state["characters"][army["general"]]
	return null


static func _process_general_deaths(state: Dictionary, attacker: Dictionary, defender: Dictionary, result: Dictionary) -> void:
	if result.get("attacker_general_died", false) and attacker["general"] != null:
		_kill_character(state, attacker["general"])
		attacker["general"] = null
	if result.get("defender_general_died", false) and defender["general"] != null:
		_kill_character(state, defender["general"])
		defender["general"] = null


static func _kill_character(state: Dictionary, char_id: String) -> void:
	if state["characters"].has(char_id):
		state["characters"][char_id]["alive"] = false
	for settlement in state["settlements"].values():
		if settlement["governor"] == char_id:
			settlement["governor"] = null


static func _cleanup_destroyed_army(state: Dictionary, army_id: String) -> void:
	if not state["armies"].has(army_id):
		return
	var army: Dictionary = state["armies"][army_id]
	if army["units"].is_empty():
		if army["general"] != null:
			_kill_character(state, army["general"])
		state["armies"].erase(army_id)


static func _check_faction_destroyed(state: Dictionary) -> void:
	for faction_id in state["factions"]:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction["alive"] or faction_id == "rebels":
			continue
		var owns_settlement := false
		for settlement in state["settlements"].values():
			if settlement["owner"] == faction_id:
				owns_settlement = true
				break
		if not owns_settlement:
			faction["alive"] = false
			# Field armies of a dead faction defect to the rebels.
			for army in state["armies"].values():
				if army["owner"] == faction_id:
					army["owner"] = "rebels"
			for fleet in state["fleets"].values():
				if fleet["owner"] == faction_id:
					fleet["owner"] = "rebels"
