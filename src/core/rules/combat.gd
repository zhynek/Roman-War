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
	# Attacking IS a declaration of war — alliances end the moment blood is
	# drawn. A war the Republic forbids (Roman on Roman before the break) is
	# refused here too, so no blade can start what no herald may.
	if not DiplomacyRules.declare_war(data, state, attacker["owner"], defender["owner"]):
		return {}
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
		"attacker_martial": SocietyRules.faction_stocks_for(data, state, String(attacker["owner"]))["martial_ethos"],
		"defender_martial": SocietyRules.faction_stocks_for(data, state, String(defender["owner"]))["martial_ethos"],
	})

	_process_general_deaths(data, state, attacker, defender, result)
	# Defeat teaches: the beaten court accumulates reform pressure (the
	# boarding-bridge law — see KnowledgeRules).
	var attacker_won_field: bool = result["winner"] == "attacker"
	KnowledgeRules.on_battle_lost(data, state,
		String(defender["owner"] if attacker_won_field else attacker["owner"]))
	# The annals: one battle entry whoever fought it (player and AI battles
	# both pass through here), the war ledger's count, the generals' deeds.
	ChronicleRules.on_battle(state, attacker["owner"], defender["owner"])
	var battle_subjects := {
		"faction": attacker["owner"], "other_faction": defender["owner"],
		"region": defender["region"],
	}
	var winner_general = attacker["general"] if attacker_won_field else defender["general"]
	if winner_general != null:
		battle_subjects["character"] = winner_general
	ChronicleRules.record(data, state, "battle", battle_subjects,
		6 if attacker_soldiers + defender_soldiers >= 1500 else 4, {
			"winner": String(result["winner"]),
			"attacker_soldiers": attacker_soldiers,
			"defender_soldiers": defender_soldiers,
		})
	ChronicleRules.add_deed(state, winner_general, "battles_won")
	ChronicleRules.add_deed(state,
		defender["general"] if attacker_won_field else attacker["general"], "battles_lost")
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

	# The trail counts the player's field victories here — every field battle
	# passes through, so defending against an AI attack counts too. (Siege
	# battles count in SiegeRules.assault.)
	if winner_army["owner"] == state.get("player_faction", ""):
		GuidedRules.bump(state, "battles_won")

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

	# A captured province starts resentful and a stranger to its new masters; the
	# conqueror gains one more victorious house expecting to be rewarded, and an
	# atrocity is remembered in every province he holds, not only this one.
	SocietyRules.record_conquest(data, state, region_id, new_owner, occupation)
	EdictRules.clear(settlement)

	state["factions"][new_owner]["treasury"] = int(state["factions"][new_owner]["treasury"]) + loot
	SocietyRules.record_plunder(data, state, new_owner, float(loot))

	# The fall of a city both teaches and warns: the victor gains awareness of
	# every craft its late owner practiced (with a conquest discount toward
	# adopting them), and the loser's court accumulates reform pressure.
	KnowledgeRules.on_settlement_captured(data, state, new_owner, previous_owner)
	KnowledgeRules.on_settlement_lost(data, state, previous_owner)

	# The annals: every capture path comes through here — occupation decides
	# whether the scribes write a taking or a sack. The loser's leader carries
	# the loss BEFORE displacement, which may cost him his life in the fall.
	ChronicleRules.on_city_taken(state, new_owner, previous_owner)
	ChronicleRules.record(data, state,
		"city_taken" if occupation == "occupy" else "city_sacked", {
			"faction": new_owner, "other_faction": previous_owner, "region": region_id,
		}, 6 if occupation == "occupy" else 7,
		{"occupation": occupation, "loot": loot, "population": int(settlement["population"])})
	ChronicleRules.add_deed(state, ChronicleRules.leader_of(state, previous_owner), "cities_lost")

	var taken := displace_characters(data, state, region_id, previous_owner)

	# Every capture path funnels through here — assault, starve-out, AI or
	# player — so the trail's capture counter lives here (revolts don't).
	if new_owner == state.get("player_faction", ""):
		GuidedRules.bump(state, "regions_captured")

	# Losing your last settlement destroys the faction.
	check_faction_destroyed(state)
	SettlementRules.refresh_governors(data, state)
	return {"loot": loot, "slaves": slaves, "occupation": occupation, "characters_taken": taken}


static func fire_occupation_triggers(data: GameData, state: Dictionary, rng: CampaignRng, general_id, occupation: String, notices: Array) -> void:
	## The conquering general remembers how the city was treated. Every capture
	## path (assault or starve-out, player or AI) must come through here.
	if general_id == null or not state["characters"].has(general_id):
		return
	ChronicleRules.add_deed(state, general_id, "cities_taken")
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


static func raise_army(data: GameData, state: Dictionary, region_id: String, unit_indices: Array, general_id: Variant = null) -> String:
	## Split garrison units out into a new field army standing in the settlement's
	## region — the inverse of garrison_army. unit_indices index into the garrison
	## array. An optional general must be a living adult male of the owning house
	## present in the settlement and not already leading an army. Returns the new
	## army id, or "" if nothing could be raised. The army marches next turn
	## (movement_left starts at 0).
	if not state["settlements"].has(region_id):
		return ""
	var settlement: Dictionary = state["settlements"][region_id]
	# A besieged garrison cannot slip out of the gates as a field army — its
	# way out is the walls' battle (sally or assault), with the walls' odds.
	if settlement["siege"] != null:
		return ""
	var garrison: Array = settlement["garrison"]
	var picked: Array = []
	var sorted_indices := _unique_sorted(unit_indices)
	for i in range(sorted_indices.size() - 1, -1, -1):
		var index := int(sorted_indices[i])
		if index >= 0 and index < garrison.size():
			picked.push_front(garrison[index])
			garrison.remove_at(index)
	if picked.is_empty():
		return ""

	var general = null
	if general_id != null and state["characters"].has(general_id):
		var character: Dictionary = state["characters"][general_id]
		var leads_army := false
		for army in state["armies"].values():
			if army["general"] == general_id:
				leads_army = true
				break
		if character["alive"] and character["faction"] == settlement["owner"] \
				and character.get("gender", "male") == "male" \
				and not character["role"] in ["spouse", "child"] \
				and int(character["age"]) >= int(data.balance["characters"]["come_of_age"]) \
				and character.get("location", "") == region_id and not leads_army:
			general = general_id

	var army_id := "army_%d" % state["next_id"]
	state["next_id"] = int(state["next_id"]) + 1
	state["armies"][army_id] = {
		"owner": settlement["owner"],
		"region": region_id,
		"units": picked,
		"general": general,
		"movement_left": 0.0,
		"forced_march": false,
	}
	SettlementRules.refresh_governors(data, state)
	return army_id


static func detach_to_garrison(data: GameData, state: Dictionary, army_id: String, unit_indices: Array) -> bool:
	## Move some of a field army's units into the friendly settlement it stands
	## in. Detaching every unit dissolves the army; its general stays in the city.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or not state["settlements"].has(army["region"]):
		return false
	var settlement: Dictionary = state["settlements"][army["region"]]
	if settlement["owner"] != army["owner"]:
		return false
	var units: Array = army["units"]
	var sorted_indices := _unique_sorted(unit_indices)
	var moved := false
	for i in range(sorted_indices.size() - 1, -1, -1):
		var index := int(sorted_indices[i])
		if index >= 0 and index < units.size():
			settlement["garrison"].append(units[index])
			units.remove_at(index)
			moved = true
	if units.is_empty():
		state["armies"].erase(army_id)
	if moved:
		SettlementRules.refresh_governors(data, state)
	return moved


static func _unique_sorted(indices: Array) -> Array:
	## Sorted, de-duplicated copy — a repeated index must not remove whichever
	## unit slid into the position after the first removal.
	var seen := {}
	for index in indices:
		seen[int(index)] = true
	var unique: Array = seen.keys()
	unique.sort()
	return unique


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


static func check_faction_destroyed(state: Dictionary) -> void:
	## Public entry for other modules that transfer settlements (cessions).
	_check_faction_destroyed(state)


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
