class_name CombatRules
## Campaign-side combat orchestration: field battles, settlement capture and the
## occupy / enslave / exterminate decision. All actual fighting goes through the
## injected BattleResolver — never assume auto-resolve here.


static func attack_army(data: GameData, state: Dictionary, resolver: BattleResolver, rng: CampaignRng, attacker_id: String, defender_id: String) -> Dictionary:
	var attacker: Dictionary = state["armies"][attacker_id]
	var defender: Dictionary = state["armies"][defender_id]
	if attacker["owner"] == defender["owner"]:
		return {}
	if attacker["region"] != defender["region"] \
			and not MapRules.are_adjacent(data, attacker["region"], defender["region"]):
		return {}
	# Attacking IS a declaration of war — alliances end the moment blood is drawn.
	DiplomacyRules.declare_war(state, attacker["owner"], defender["owner"])
	var region: Dictionary = data.regions[defender["region"]]

	var attacker_soldiers := soldiers_in(data, attacker["units"])
	var defender_soldiers := soldiers_in(data, defender["units"])
	var attacker_had_general: bool = attacker["general"] != null
	var defender_had_general: bool = defender["general"] != null

	var result := resolver.resolve(data, rng, attacker["units"], defender["units"], {
		"terrain": region["terrain"],
		"wall_level": 0,
		"attacker_general": general_profile(data, state, attacker),
		"defender_general": general_profile(data, state, defender),
		"attacker_fatigued": attacker.get("forced_march", false),
		"sally": false,
	})

	_process_general_deaths(data, state, attacker, defender, result)
	if result["winner"] == "attacker":
		attacker["region"] = defender["region"]
		MovementRules.sync_general_location(state, attacker)
		attacker["movement_left"] = 0.0

	# Battle records shape the victors and the beaten (surviving generals only),
	# and a captain's unlikely victory can earn him adoption into the family.
	var odds_ratio := float(data.balance["characters"]["odds_against_ratio"])
	var notices: Array = []
	var attacker_won: bool = result["winner"] == "attacker"
	if attacker["general"] != null:
		CharacterRules.fire_trigger(data, state, attacker["general"],
			"battle_won" if attacker_won else "battle_lost",
			{"odds_against": defender_soldiers >= attacker_soldiers * odds_ratio}, rng, notices)
	if defender["general"] != null:
		CharacterRules.fire_trigger(data, state, defender["general"],
			"battle_won" if not attacker_won else "battle_lost",
			{"odds_against": attacker_soldiers >= defender_soldiers * odds_ratio}, rng, notices)
	var winner_army := attacker if attacker_won else defender
	var winner_soldiers := attacker_soldiers if attacker_won else defender_soldiers
	var loser_soldiers := defender_soldiers if attacker_won else attacker_soldiers
	# Only a captain earns the hour — never a stand-in for a general who fell
	# in this same battle.
	var winner_had_general: bool = attacker_had_general if attacker_won else defender_had_general
	if not winner_army["units"].is_empty() and not winner_had_general:
		FamilyRules.maybe_man_of_the_hour(data, state, rng, winner_army,
			winner_soldiers, loser_soldiers, notices)
	result["character_notices"] = notices

	_cleanup_destroyed_army(data, state, attacker_id)
	_cleanup_destroyed_army(data, state, defender_id)
	return result


static func soldiers_in(data: GameData, units: Array) -> int:
	var soldiers := 0
	for unit in units:
		var template: Dictionary = data.units.get(unit["template"], {})
		soldiers += int(ceil(int(template.get("soldiers", 0)) * int(unit["strength_pct"]) / 100.0))
	return soldiers


static func general_profile(data: GameData, state: Dictionary, army: Dictionary) -> Variant:
	## Effective command/morale (base + traits + retinue) for the resolver.
	if army["general"] != null and state["characters"].has(army["general"]):
		return CharacterRules.battle_profile(data, state["characters"][army["general"]])
	return null


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

	var previous_owner: String = settlement["owner"]
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

	var taken := displace_characters(data, state, region_id, previous_owner)

	# Losing your last settlement destroys the faction.
	_check_faction_destroyed(state)
	SettlementRules.refresh_governors(data, state)
	return {"loot": loot, "slaves": slaves, "occupation": occupation, "characters_taken": taken}


static func assault_and_capture(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, army_id: String, region_id: String, occupation: String) -> Dictionary:
	## The whole storming, shared by the player facade and the AI: assault the
	## walls, and on a capture apply the occupation decision and let the
	## general answer for it.
	var result := SiegeRules.assault(data, state, rng, resolver, army_id, region_id)
	if result.get("captured", false):
		var general = state["armies"].get(army_id, {}).get("general")
		result["capture"] = capture_settlement(
			data, state, rng, region_id, result["capture_pending_owner"], occupation)
		var notices: Array = result.get("character_notices", [])
		fire_occupation_triggers(data, state, rng, general, occupation, notices)
		result["character_notices"] = notices
	return result


static func fire_occupation_triggers(data: GameData, state: Dictionary, rng: CampaignRng, general_id, occupation: String, notices: Array) -> void:
	## The conquering general remembers how the city was treated. Every capture
	## path (assault or starve-out, player or AI) must come through here.
	if general_id == null or not state["characters"].has(general_id):
		return
	var context := {"occupation": occupation}
	CharacterRules.fire_trigger(data, state, general_id, "settlement_captured", context, rng, notices)
	if occupation == "enslave":
		CharacterRules.fire_trigger(data, state, general_id, "settlement_enslaved", context, rng, notices)
	elif occupation == "exterminate":
		CharacterRules.fire_trigger(data, state, general_id, "settlement_exterminated", context, rng, notices)


static func displace_characters(data: GameData, state: Dictionary, region_id: String, losing_faction: String) -> Array:
	## Family caught in a fallen city flee to the nearest settlement their house
	## still holds. Those with nowhere to run are lost with the city.
	var taken: Array = []
	var refuge := _nearest_owned_settlement(data, state, region_id, losing_faction)
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if not character["alive"] or character["faction"] != losing_faction:
			continue
		if character.get("location", "") != region_id:
			continue
		# A general still at the head of an army in the field marches on with it.
		var with_army := false
		for army in state["armies"].values():
			if army["general"] == char_id:
				with_army = true
				break
		if with_army:
			continue
		if refuge == "":
			CharacterRules.kill(state, char_id, data)
			taken.append(char_id)
		else:
			character["location"] = refuge
	return taken


static func _nearest_owned_settlement(data: GameData, state: Dictionary, from_region: String, faction_id: String) -> String:
	var hops := MapRules.hops_from(data, from_region)
	var best := ""
	var best_hops := 1 << 30
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if region_id == from_region or state["settlements"][region_id]["owner"] != faction_id:
			continue
		var distance := int(hops.get(region_id, 1 << 29))
		if distance < best_hops:
			best_hops = distance
			best = region_id
	return best


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
	if army["general"] != null and state["characters"].has(army["general"]):
		state["characters"][army["general"]]["location"] = region_id
	state["armies"].erase(army_id)
	SettlementRules.refresh_governors(data, state)
	return true


static func _distribute_slaves(data: GameData, state: Dictionary, faction_id: String) -> void:
	var turns := int(data.balance["growth"]["slave_influx_turns"])
	for other in state["settlements"].values():
		if other["owner"] == faction_id and other["governor"] != null:
			other["slave_bonus_turns"] = turns


static func _process_general_deaths(data: GameData, state: Dictionary, attacker: Dictionary, defender: Dictionary, result: Dictionary) -> void:
	if result.get("attacker_general_died", false) and attacker["general"] != null:
		CharacterRules.kill(state, attacker["general"], data)
	if result.get("defender_general_died", false) and defender["general"] != null:
		CharacterRules.kill(state, defender["general"], data)


static func _cleanup_destroyed_army(data: GameData, state: Dictionary, army_id: String) -> void:
	if not state["armies"].has(army_id):
		return
	var army: Dictionary = state["armies"][army_id]
	if army["units"].is_empty():
		if army["general"] != null:
			CharacterRules.kill(state, army["general"], data)
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
