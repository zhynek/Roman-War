class_name NewGame
## Builds the initial GameState Dictionary from data/campaign.json.
## GameState is a plain Dictionary (JSON-serializable, deep-comparable):
##
##  turn: int (0-based), year: int, season: "summer"|"winter"
##  rng_state: int
##  player_faction: String
##  factions: {fid: {treasury, capital, alive, era, senate_standing,
##                   popular_standing, diplomacy: {other_fid: stance},
##                   mission: null|{...}, at_civil_war: bool,
##                   doctrines: [doctrine_id], reforms: [{doctrine, turns_left}],
##                   war_record: {battles_won, battles_lost, faced: {class: battles}},
##                   war_mood: null|{label, value, turns}}}
##  settlements: {region_id: {owner, population, buildings: {chain_id: level_index},
##                tax_level, garrison: [unit], construction_queue: [...],
##                recruitment_queue: [...], governor: char_id|null,
##                slave_bonus_turns, plague_turns, recently_conquered,
##                low_order_streak, siege: null|{besieger, turns, equipment_ready},
##                levy_strain: float}}
##  armies: {army_id: {owner, region, units: [unit], general: char_id|null,
##                     movement_left: float}}
##  fleets: {fleet_id: {owner, sea_zone, ships: [unit], movement_left}}
##  characters: {char_id: {faction, name, age, role, command, management,
##                         influence, traits, ancillaries, location, alive}}
##  events_fired: [event_id], winner: null|String, next_id: int
##
## A "unit" is {template, experience, strength_pct} plus optional weapon /
## armor upgrade levels (absent = 0) stamped by the recruiting settlement.
##
## New state fields are ALWAYS initialised here and in SaveGame.upgrade, never
## lazily on first read: a live game and a loaded save must stringify with the
## same key order or the determinism tests cannot compare them.

const ConstantsScript = preload("res://src/core/constants.gd")


static func build(data: GameData, player_faction: String, seed_value: int, difficulty: String = "medium", campaign_mode: String = "long") -> Dictionary:
	var rng := CampaignRng.seeded(seed_value)
	var state := {
		"turn": 0,
		"year": int(data.balance["time"]["start_year"]),
		"season": "summer",
		"rng_state": "0",
		"difficulty": difficulty,
		"campaign_mode": campaign_mode,
		"event_happiness": null,
		"player_faction": player_faction,
		"factions": {},
		"settlements": {},
		"armies": {},
		"fleets": {},
		"characters": {},
		"events_fired": [],
		"winner": null,
		"next_id": 1,
	}

	for faction_setup in data.campaign["factions"]:
		var fid: String = faction_setup["id"]
		var senate_start := float(data.balance["senate"]["start_standing"])
		state["factions"][fid] = {
			"treasury": int(faction_setup["treasury"]),
			"capital": faction_setup["capital"],
			"alive": true,
			"era": "pre_marian",
			"senate_standing": senate_start,
			"popular_standing": 0.0,
			"diplomacy": {},
			"mission": null,
			"at_civil_war": false,
			"doctrines": _starting_doctrines(data, faction_setup),
			"reforms": [],
			"war_record": empty_war_record(),
			"war_mood": null,
		}
		for entry in faction_setup.get("diplomacy", []):
			state["factions"][fid]["diplomacy"][entry["faction"]] = entry["stance"]

		for settlement_setup in faction_setup.get("settlements", []):
			state["settlements"][settlement_setup["region"]] = _settlement(data, settlement_setup, fid)
		for army_setup in faction_setup.get("armies", []):
			_add_army(state, army_setup, fid)
		for fleet_setup in faction_setup.get("fleets", []):
			_add_fleet(state, fleet_setup, fid)
		for character_setup in faction_setup.get("characters", []):
			_add_character(data, state, character_setup, fid)

	var rebels := "rebels"
	state["factions"][rebels] = {
		"treasury": 0, "capital": "", "alive": true, "era": "pre_marian",
		"senate_standing": 0.0, "popular_standing": 0.0, "diplomacy": {},
		"mission": null, "at_civil_war": false,
		"doctrines": [], "reforms": [], "war_record": empty_war_record(), "war_mood": null,
	}
	for settlement_setup in data.campaign.get("rebel_settlements", []):
		state["settlements"][settlement_setup["region"]] = _settlement(data, settlement_setup, rebels)
	for army_setup in data.campaign.get("rebel_armies", []):
		_add_army(state, army_setup, rebels)

	# Make diplomacy symmetric; default stance between unrelated factions is neutral,
	# and everyone is at war with the rebels.
	for fid in state["factions"]:
		for other in state["factions"]:
			if fid == other:
				continue
			var stances: Dictionary = state["factions"][fid]["diplomacy"]
			var reverse: Dictionary = state["factions"][other]["diplomacy"]
			if stances.has(other) and not reverse.has(fid):
				reverse[fid] = stances[other]
			elif not stances.has(other):
				var default_stance := "war" if (fid == rebels or other == rebels) else "neutral"
				if not stances.has(other):
					stances[other] = reverse.get(fid, default_stance)

	# Governorship is derived from presence, so it is simply computed, never seeded.
	SettlementRules.refresh_governors(data, state)

	# Mercenary pools start at their initial counts (fractional replenishment
	# accumulates in the counts, so they are floats).
	var pools := {}
	for pool in data.mercenary_pools:
		var counts := {}
		for entry in pool["units"]:
			counts[entry["template"]] = float(entry.get("initial", 0))
		pools[pool["id"]] = counts
	state["mercenary_pools"] = pools

	MovementRules.reset_movement(data, state)
	state["rng_state"] = rng.state_string()
	return state


static func _settlement(data: GameData, setup: Dictionary, owner: String) -> Dictionary:
	var buildings := {}
	for level_id in setup.get("buildings", []):
		var info: Dictionary = data.building_levels.get(level_id, {})
		if info.is_empty():
			push_warning("campaign.json references unknown building level: " + str(level_id))
			continue
		var chain_id: String = info["chain"]
		buildings[chain_id] = maxi(int(buildings.get(chain_id, 0)), int(info["index"]))
	return {
		"owner": owner,
		"population": int(setup["population"]),
		"buildings": buildings,
		"tax_level": setup.get("tax_level", "normal"),
		"garrison": _units(setup.get("garrison", [])),
		"construction_queue": [],
		"recruitment_queue": [],
		"governor": null,
		"slave_bonus_turns": 0,
		"plague_turns": 0,
		"recently_conquered": 0,
		"low_order_streak": 0,
		"siege": null,
		"levy_strain": 0.0,
	}


static func empty_war_record() -> Dictionary:
	return {"battles_won": 0, "battles_lost": 0, "faced": {}}


static func _starting_doctrines(data: GameData, faction_setup: Dictionary) -> Array:
	## Doctrines a faction already practises in 270 BC (campaign.json), kept
	## sorted like every other doctrine list; unknown ids are dropped.
	var result: Array = []
	for doctrine_id in faction_setup.get("doctrines", []):
		if data.doctrines.has(doctrine_id) and not result.has(doctrine_id):
			result.append(doctrine_id)
	result.sort()
	return result


static func _units(setups: Array) -> Array:
	var result: Array = []
	for setup in setups:
		var unit := {
			"template": setup["template"],
			"experience": int(setup.get("experience", 0)),
			"strength_pct": int(setup.get("strength_pct", 100)),
		}
		if int(setup.get("weapon", 0)) > 0:
			unit["weapon"] = int(setup["weapon"])
		if int(setup.get("armor", 0)) > 0:
			unit["armor"] = int(setup["armor"])
		result.append(unit)
	return result


static func _add_army(state: Dictionary, setup: Dictionary, owner: String) -> void:
	var army_id := "army_%d" % state["next_id"]
	state["next_id"] += 1
	state["armies"][army_id] = {
		"owner": owner,
		"region": setup["region"],
		"units": _units(setup["units"]),
		"general": setup.get("general", null),
		"movement_left": 0.0,
	}


static func _add_fleet(state: Dictionary, setup: Dictionary, owner: String) -> void:
	var fleet_id := "fleet_%d" % state["next_id"]
	state["next_id"] += 1
	state["fleets"][fleet_id] = {
		"owner": owner,
		"sea_zone": setup["sea_zone"],
		"ships": _units(setup["ships"]),
		"movement_left": 0.0,
	}


static func _add_character(data: GameData, state: Dictionary, setup: Dictionary, owner: String) -> void:
	# Starting trait ids become just enough points to hold the trait's first level.
	var trait_points := {}
	for trait_id in setup.get("traits", []):
		var trait_def: Dictionary = data.traits.get(trait_id, {})
		if not trait_def.is_empty():
			trait_points[trait_id] = int(trait_def["levels"][0]["threshold"])
	state["characters"][setup["id"]] = {
		"faction": owner,
		"name": setup["name"],
		"age": int(setup["age"]),
		"role": setup["role"],
		"gender": setup.get("gender", "female" if setup["role"] == "spouse" else "male"),
		"father": setup.get("father", null),
		"command": int(setup.get("command", 0)),
		"management": int(setup.get("management", 0)),
		"influence": int(setup.get("influence", 0)),
		"trait_points": trait_points,
		"ancillaries": [],
		"location": setup.get("location", ""),
		"alive": true,
	}
