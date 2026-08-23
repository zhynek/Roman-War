class_name Fixtures
## Synthetic minimal world for formula unit tests, so they don't depend on the
## authored content tables. Balance always comes from data/balance.json — the
## single source of truth the tests guard.


static func data() -> GameData:
	var game_data := GameData.new()
	var balance_text := FileAccess.get_file_as_string("res://data/balance.json")
	game_data.balance = JSON.parse_string(balance_text)

	game_data.cultures = {
		"roman": {"id": "roman", "name": "Roman", "max_settlement_level": "huge_city"},
		"barbarian": {"id": "barbarian", "name": "Tribal", "max_settlement_level": "minor_city"},
		"neutral": {"id": "neutral", "name": "Independent", "max_settlement_level": "large_city"},
	}
	game_data.factions = {
		"red": {"id": "red", "name": "Red", "culture": "roman", "is_roman_house": true},
		"blue": {"id": "blue", "name": "Blue", "culture": "barbarian"},
		"rebels": {"id": "rebels", "name": "Rebels", "culture": "neutral", "is_rebel": true},
	}

	var chains := [
		{
			"id": "test_government", "kind": "government", "cultures": ["roman"], "name": "Government",
			"levels": [
				{"id": "gov_1", "name": "Meeting Hall", "min_settlement_level": "village", "cost": 400, "build_turns": 1, "effects": {"law": 5}, "description": ""},
				{"id": "gov_2", "name": "Town Hall", "min_settlement_level": "town", "cost": 800, "build_turns": 2, "effects": {"law": 5}, "description": ""},
				{"id": "gov_3", "name": "City Hall", "min_settlement_level": "large_town", "cost": 1600, "build_turns": 3, "effects": {"law": 5}, "description": ""},
				{"id": "gov_4", "name": "Great Hall", "min_settlement_level": "minor_city", "cost": 3200, "build_turns": 4, "effects": {"law": 5}, "description": ""},
			],
		},
		{
			"id": "tribal_government", "kind": "government", "cultures": ["barbarian"], "name": "Chief's Hold",
			"levels": [
				{"id": "hold_1", "name": "Chief's Hut", "min_settlement_level": "village", "cost": 300, "build_turns": 1, "effects": {}, "description": ""},
				{"id": "hold_2", "name": "Chief's Hold", "min_settlement_level": "town", "cost": 600, "build_turns": 2, "effects": {}, "description": ""},
				{"id": "hold_3", "name": "High Hold", "min_settlement_level": "large_town", "cost": 1200, "build_turns": 3, "effects": {}, "description": ""},
				{"id": "hold_4", "name": "King's Hall", "min_settlement_level": "minor_city", "cost": 2400, "build_turns": 4, "effects": {}, "description": ""},
			],
		},
		{
			"id": "test_farms", "kind": "farms", "cultures": ["roman", "barbarian"], "name": "Farms", "indestructible": true,
			"levels": [
				{"id": "farm_1", "name": "Cleared Land", "min_settlement_level": "village", "cost": 300, "build_turns": 1, "effects": {"growth": 0.5, "farm_income": 40}, "description": ""},
				{"id": "farm_2", "name": "Field Rows", "min_settlement_level": "town", "cost": 600, "build_turns": 2, "effects": {"growth": 0.5, "farm_income": 40}, "description": ""},
			],
		},
		{
			"id": "test_health", "kind": "health", "cultures": ["roman"], "name": "Drains",
			"levels": [
				{"id": "drain_1", "name": "Drains", "min_settlement_level": "town", "cost": 400, "build_turns": 1, "effects": {"health": 10}, "description": ""},
			],
		},
		{
			"id": "test_walls", "kind": "walls", "cultures": ["roman", "barbarian"], "name": "Walls",
			"levels": [
				{"id": "wall_1", "name": "Palisade", "min_settlement_level": "village", "cost": 300, "build_turns": 1, "effects": {"wall_level": 1}, "description": ""},
				{"id": "wall_2", "name": "Stone Wall", "min_settlement_level": "large_town", "cost": 900, "build_turns": 2, "effects": {"wall_level": 2}, "description": ""},
			],
		},
		{
			"id": "test_barracks", "kind": "barracks", "cultures": ["roman"], "name": "Barracks",
			"levels": [
				{"id": "barracks_1", "name": "Mustering Field", "min_settlement_level": "village", "cost": 400, "build_turns": 1, "effects": {}, "description": ""},
				{"id": "barracks_2", "name": "Drill Yard", "min_settlement_level": "town", "cost": 800, "build_turns": 2, "effects": {}, "description": ""},
			],
		},
	]
	for chain in chains:
		game_data.chains[chain["id"]] = chain
		var index := 1
		for level in chain["levels"]:
			game_data.building_levels[level["id"]] = {"chain": chain["id"], "kind": chain["kind"], "index": index, "level": level}
			index += 1

	game_data.units = {
		"test_spears": {
			"id": "test_spears", "name": "Spears", "class": "spear", "culture": "roman",
			"factions": ["red"], "soldiers": 80, "attack": 6, "defense": 8, "morale": 6,
			"cost": 400, "upkeep": 120, "requirements": {"building_kind": "barracks", "building_level": 1},
			"era": "any", "description": "",
		},
		"test_elites": {
			"id": "test_elites", "name": "Elites", "class": "infantry", "culture": "roman",
			"factions": ["red"], "soldiers": 80, "attack": 12, "defense": 14, "morale": 10,
			"cost": 900, "upkeep": 250, "requirements": {"building_kind": "barracks", "building_level": 2},
			"era": "post_marian", "description": "",
		},
		"test_mob": {
			"id": "test_mob", "name": "Mob", "class": "peasant", "culture": "neutral",
			"factions": ["all"], "soldiers": 60, "attack": 2, "defense": 2, "morale": 2,
			"cost": 100, "upkeep": 50, "requirements": {"building_kind": "government", "building_level": 1},
			"era": "any", "description": "",
		},
	}

	# A five-region line: alpha - beta - gamma - delta - epsilon, alpha coastal.
	var region_ids := ["alpha", "beta", "gamma", "delta", "epsilon"]
	for i in range(region_ids.size()):
		var adjacent: Array = []
		if i > 0:
			adjacent.append(region_ids[i - 1])
		if i < region_ids.size() - 1:
			adjacent.append(region_ids[i + 1])
		game_data.regions[region_ids[i]] = {
			"id": region_ids[i], "name": region_ids[i].capitalize(),
			"settlement_name": region_ids[i].capitalize(), "terrain": "plains",
			"fertility": 1.0, "adjacent": adjacent, "sea_zones": [], "resources": [],
			"hidden_resources": [],
		}
	game_data.regions["alpha"]["sea_zones"] = ["test_sea"]
	game_data.regions["alpha"]["resources"] = ["grain"]
	game_data.sea_zones = {"test_sea": {"id": "test_sea", "name": "Test Sea", "adjacent": []}}

	return game_data


static func state(game_data: GameData) -> Dictionary:
	## Two-faction world: red holds beta (capital) and epsilon, blue holds alpha.
	var campaign_state := {
		"turn": 0, "year": -270, "season": "summer", "rng_state": 0,
		"player_faction": "red",
		"factions": {
			"red": _faction("beta"),
			"blue": _faction("alpha"),
			"rebels": _faction(""),
		},
		"settlements": {
			"beta": _settlement("red", 2000, {"test_government": 2, "test_farms": 1, "test_barracks": 1}),
			"epsilon": _settlement("red", 6000, {"test_government": 2}),
			"alpha": _settlement("blue", 1200, {"tribal_government": 1}),
		},
		"armies": {}, "fleets": {}, "characters": {},
		"events_fired": [], "winner": null, "next_id": 1,
	}
	campaign_state["factions"]["red"]["diplomacy"] = {"blue": "war", "rebels": "war"}
	campaign_state["factions"]["blue"]["diplomacy"] = {"red": "war", "rebels": "war"}
	campaign_state["factions"]["rebels"]["diplomacy"] = {"red": "war", "blue": "war"}
	return campaign_state


static func add_army(campaign_state: Dictionary, owner: String, region: String, templates: Array) -> String:
	var army_id := "army_%d" % campaign_state["next_id"]
	campaign_state["next_id"] += 1
	var units: Array = []
	for template in templates:
		units.append({"template": template, "experience": 0, "strength_pct": 100})
	campaign_state["armies"][army_id] = {
		"owner": owner, "region": region, "units": units, "general": null,
		"movement_left": 2.0, "forced_march": false,
	}
	return army_id


static func _faction(capital: String) -> Dictionary:
	return {
		"treasury": 5000, "capital": capital, "alive": true, "era": "pre_marian",
		"senate_standing": 5.0, "popular_standing": 0.0, "diplomacy": {},
		"mission": null, "at_civil_war": false,
	}


static func _settlement(owner: String, population: int, buildings: Dictionary) -> Dictionary:
	return {
		"owner": owner, "population": population, "buildings": buildings,
		"tax_level": "normal", "garrison": [], "construction_queue": [],
		"recruitment_queue": [], "governor": null, "slave_bonus_turns": 0,
		"plague_turns": 0, "recently_conquered": 0, "low_order_streak": 0,
		"siege": null,
	}
