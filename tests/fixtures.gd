class_name Fixtures
## Synthetic minimal world for formula unit tests, so they don't depend on the
## authored content tables. Balance always comes from data/balance.json — the
## single source of truth the tests guard.


static var _shared: GameData = null


static func shared_data() -> GameData:
	## The add_* helpers take no GameData, so they draw on one built once.
	if _shared == null:
		_shared = data()
	return _shared


static func data() -> GameData:
	var game_data := GameData.new()
	var balance_text := FileAccess.get_file_as_string("res://data/balance.json")
	game_data.balance = JSON.parse_string(balance_text)
	# Balance, advances and society all come from the real tables — they are the
	# single source of truth the tests guard, not fixtures to invent.
	var advance_doc: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/advances.json"))
	for advance in advance_doc.get("advances", []):
		game_data.advances[advance["id"]] = advance
	game_data.society = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/society.json"))
	var edict_doc: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/edicts.json"))
	for edict in edict_doc.get("edicts", []):
		game_data.edicts[edict["id"]] = edict

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
				{"id": "gov_1", "name": "Meeting Hall", "min_settlement_level": "village", "cost": 400, "build_turns": 1, "effects": {"law": 5, "civic": 1, "burden": 0.5}, "description": ""},
				{"id": "gov_2", "name": "Town Hall", "min_settlement_level": "town", "cost": 800, "build_turns": 2, "effects": {"law": 10, "civic": 2, "burden": 1}, "description": ""},
				{"id": "gov_3", "name": "City Hall", "min_settlement_level": "large_town", "cost": 1600, "build_turns": 3, "effects": {"law": 15}, "description": ""},
				{"id": "gov_4", "name": "Great Hall", "min_settlement_level": "minor_city", "cost": 3200, "build_turns": 4, "effects": {"law": 20}, "description": ""},
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
				{"id": "farm_2", "name": "Field Rows", "min_settlement_level": "town", "cost": 600, "build_turns": 2, "effects": {"growth": 1.0, "farm_income": 80}, "description": ""},
			],
		},
		{
			"id": "test_health", "kind": "health", "cultures": ["roman"], "name": "Drains",
			"levels": [
				{"id": "drain_1", "name": "Drains", "min_settlement_level": "town", "cost": 400, "build_turns": 1, "effects": {"health": 10, "civic": 8, "burden": 2}, "description": ""},
			],
		},
		{
			"id": "test_walls", "kind": "walls", "cultures": ["roman", "barbarian"], "name": "Walls",
			"levels": [
				{"id": "wall_1", "name": "Palisade", "min_settlement_level": "village", "cost": 300, "build_turns": 1, "effects": {"wall_level": 1, "coercion": 2, "burden": 1, "martial": 1}, "description": ""},
				{"id": "wall_2", "name": "Stone Wall", "min_settlement_level": "large_town", "cost": 900, "build_turns": 2, "effects": {"wall_level": 2, "coercion": 4, "burden": 2, "martial": 2}, "description": ""},
			],
		},
		{
			"id": "test_market", "kind": "market", "cultures": ["roman", "barbarian"], "name": "Market",
			"levels": [
				{"id": "market_1", "name": "Market Stalls", "min_settlement_level": "village", "cost": 400, "build_turns": 1, "effects": {"trade_pct": 10, "knowledge": 1}, "description": ""},
				{"id": "market_2", "name": "Forum", "min_settlement_level": "town", "cost": 900, "build_turns": 2, "effects": {"trade_pct": 20, "knowledge": 2}, "description": ""},
			],
		},
		{
			"id": "test_school", "kind": "education", "cultures": ["roman"], "name": "School",
			"levels": [
				{"id": "school_1", "name": "School", "min_settlement_level": "town", "cost": 500, "build_turns": 2, "effects": {"knowledge": 6, "civic": 3, "burden": 1}, "description": ""},
			],
		},
		{
			"id": "test_temple", "kind": "temple", "cultures": ["roman"], "god": "Jupiter", "archetype": "law", "name": "Temple",
			"levels": [
				{"id": "temple_1", "name": "Shrine", "min_settlement_level": "village", "cost": 300, "build_turns": 1, "effects": {"law": 4, "civic": 3, "assimilation_pull": 4, "burden": 0.5}, "description": ""},
			],
		},
		{
			"id": "test_foreign_temple", "kind": "temple", "cultures": ["barbarian"], "god": "Taranis", "archetype": "battle", "name": "Grove",
			"levels": [
				{"id": "grove_1", "name": "Grove", "min_settlement_level": "village", "cost": 250, "build_turns": 1, "effects": {"happiness": 4, "martial": 2, "assimilation_pull": 4, "burden": 0.5}, "description": ""},
			],
		},
		{
			"id": "test_barracks", "kind": "barracks", "cultures": ["roman"], "name": "Barracks",
			"levels": [
				{"id": "barracks_1", "name": "Mustering Field", "min_settlement_level": "village", "cost": 400, "build_turns": 1, "effects": {"martial": 2, "civic": -1, "burden": 0.5}, "description": ""},
				{"id": "barracks_2", "name": "Drill Yard", "min_settlement_level": "town", "cost": 800, "build_turns": 2, "effects": {"martial": 4, "civic": -2, "burden": 1}, "description": ""},
			],
		},
		{
			"id": "test_education", "kind": "education", "cultures": ["roman"], "name": "Learning",
			"levels": [
				{"id": "edu_1", "name": "School", "min_settlement_level": "village", "cost": 500, "build_turns": 1, "effects": {}, "description": ""},
				{"id": "edu_2", "name": "Academy", "min_settlement_level": "town", "cost": 1000, "build_turns": 2, "effects": {}, "description": ""},
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

	# A five-region line: alpha - beta - gamma - delta - epsilon, alpha coastal,
	# plus "island", which no land route reaches at all.
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
	game_data.regions["island"] = {
		"id": "island", "name": "Island", "settlement_name": "Island", "terrain": "plains",
		"fertility": 1.0, "adjacent": [], "sea_zones": ["test_sea"], "resources": [],
		"hidden_resources": [],
	}
	game_data.regions["alpha"]["sea_zones"] = ["test_sea"]
	game_data.regions["alpha"]["resources"] = ["grain"]
	game_data.regions["epsilon"]["sea_zones"] = ["test_sea"]
	game_data.sea_zones = {"test_sea": {"id": "test_sea", "name": "Test Sea", "adjacent": []}}
	game_data.index_grain_regions()

	# A mountain pass arcs over the plains line: alpha-zeta-eta-epsilon is one
	# hop shorter than the four-step line but strictly dearer (2.0 + 1.5 + 1.0
	# against four 1.0 steps), so pathfinding tests can price terrain. The
	# line regions also get positions; zeta/eta sit north of it.
	game_data.regions["zeta"] = {
		"id": "zeta", "name": "Zeta", "settlement_name": "Zeta", "terrain": "mountains",
		"fertility": 0.5, "adjacent": ["alpha", "eta"], "sea_zones": [], "resources": [],
		"hidden_resources": [],
	}
	game_data.regions["eta"] = {
		"id": "eta", "name": "Eta", "settlement_name": "Eta", "terrain": "forest",
		"fertility": 1.0, "adjacent": ["epsilon", "zeta"], "sea_zones": [], "resources": [],
		"hidden_resources": [],
	}
	game_data.regions["alpha"]["adjacent"].append("zeta")
	game_data.regions["epsilon"]["adjacent"].append("eta")
	var fixture_positions := {
		"alpha": [10, 50], "beta": [20, 50], "gamma": [30, 50], "delta": [40, 50],
		"epsilon": [50, 50], "zeta": [18, 42], "eta": [42, 42],
	}
	for region_id in fixture_positions:
		game_data.regions[region_id]["position"] = {
			"x": fixture_positions[region_id][0], "y": fixture_positions[region_id][1],
		}

	game_data.units["test_merc"] = {
		"id": "test_merc", "name": "Sellswords", "class": "infantry", "culture": "neutral",
		"factions": ["mercenary"], "soldiers": 60, "attack": 7, "defense": 7, "morale": 7,
		"cost": 500, "upkeep": 150, "requirements": {"building_kind": "government", "building_level": 1},
		"era": "any", "description": "",
	}
	game_data.mercenary_pools = [{
		"id": "test_pool", "regions": ["gamma", "delta"],
		"units": [{"template": "test_merc", "max": 2, "initial": 1, "replenish_per_turn": 0.5, "cost_multiplier": 1.5}],
	}]

	game_data.traits = {
		"test_steward": {
			"id": "test_steward", "name": "Steward", "anti_trait": "test_slacker",
			"levels": [
				{"name": "Able Steward", "threshold": 2, "effects": {"management": 1, "law": 2}},
				{"name": "Great Steward", "threshold": 5, "effects": {"management": 2, "law": 5}},
			],
			"triggers": [
				{"when": "turn_end_governing", "condition": {"min_public_order": 80}, "chance": 1.0, "points": 1},
			],
		},
		"test_slacker": {
			"id": "test_slacker", "name": "Slacker", "anti_trait": "test_steward",
			"levels": [{"name": "Idle Hands", "threshold": 2, "effects": {"management": -1}}],
			"triggers": [{"when": "turn_end_idle", "chance": 1.0, "points": 1}],
		},
		"test_brave": {
			"id": "test_brave", "name": "Brave",
			"levels": [{"name": "Brave", "threshold": 1, "effects": {"command": 1, "troop_morale": 2}}],
			"triggers": [{"when": "battle_won", "condition": {"odds_against": true}, "chance": 1.0, "points": 1}],
		},
		"test_pathfinder": {
			"id": "test_pathfinder", "name": "Pathfinder",
			"levels": [{"name": "Pathfinder", "threshold": 1, "effects": {"movement": 0.5}}],
			"triggers": [{"when": "turn_end_campaigning", "chance": 0.5, "points": 1}],
		},
	}
	game_data.ancillaries = {
		"test_scribe": {
			"id": "test_scribe", "name": "Scribe",
			"effects": {"management": 1},
			"triggers": [
				{"when": "turn_end_governing", "condition": {"building_kind": "government", "min_building_level": 1}, "chance": 1.0},
			],
		},
		"test_bodyguard": {
			"id": "test_bodyguard", "name": "Bodyguard",
			"effects": {"personal_security": 4},
			"triggers": [],
		},
		"test_spycatcher": {
			"id": "test_spycatcher", "name": "Spy Catcher",
			"effects": {"agent_skill": 3},
			"triggers": [],
		},
	}
	game_data.names = {
		"roman": {"male": ["Testus", "Probus", "Cassius"], "female": ["Testa", "Proba"], "surnames": ["Fixturus"]},
		"barbarian": {"male": ["Brox", "Karn"], "female": ["Enna"]},
	}

	game_data.ai_personas = {
		"default": {
			"id": "default", "name": "Balanced",
			"aggression": 1.0, "expansion_drive": 1.0, "peace_willingness": 1.0,
			"occupation": "occupy",
			"build_weights": {"order": 1.0, "growth": 1.0, "income": 1.0, "military": 1.0, "walls": 1.0},
			"knowledge_priorities": {"military": 1.0, "economic": 1.0, "civic": 1.0},
			"edict_priorities": {"welfare": 1.0, "religion": 1.0, "land": 1.0, "citizenship": 1.0,
				"taxation": 1.0, "debt": 1.0, "military": 1.0, "trade": 1.0},
			"garrison_min_units": 2, "garrison_frontier_units": 4, "army_size_target": 8,
		},
	}

	game_data.agent_kinds = {
		"diplomat": {"id": "diplomat", "name": "Envoy", "cost": 250, "upkeep": 30,
			"building_kind": "government", "building_level": 1, "base_skill": 1, "movement_points": 3},
		"spy": {"id": "spy", "name": "Informer", "cost": 300, "upkeep": 40,
			"building_kind": "government", "building_level": 1, "base_skill": 1, "movement_points": 3},
		"assassin": {"id": "assassin", "name": "Hired Blade", "cost": 500, "upkeep": 60,
			"building_kind": "government", "building_level": 1, "base_skill": 1, "movement_points": 3},
	}

	game_data.techniques = {
		"test_smithing": {
			"id": "test_smithing", "name": "Pattern Smithing", "domain": "metallurgy_craft",
			"historical_basis": "fixture",
			"start_adopted": {"cultures": ["barbarian"], "factions": []},
			"origin_cultures": [],
			"prerequisites": {"building_kind": "barracks", "building_level": 1, "resource": "", "hidden_resource": "", "coastal": false, "techniques": []},
			"adoption": {"cost": 600, "turns": 2},
			"culture_resistance": {},
			"effects": {"weapon_upgrade": 1},
		},
		"test_letters": {
			"id": "test_letters", "name": "Letters", "domain": "scholarship_statecraft",
			"historical_basis": "fixture",
			"start_adopted": {"cultures": [], "factions": []},
			"origin_cultures": ["roman"],
			"prerequisites": {"building_kind": "education", "building_level": 1, "resource": "", "hidden_resource": "", "coastal": false, "techniques": []},
			"adoption": {"cost": 400, "turns": 1},
			"culture_resistance": {"barbarian": 2.0},
			"effects": {"scholarship": 1},
		},
		"test_irrigation": {
			"id": "test_irrigation", "name": "Ditch Irrigation", "domain": "agrarian",
			"historical_basis": "fixture",
			"start_adopted": {"cultures": [], "factions": []},
			"origin_cultures": [],
			"prerequisites": {"building_kind": "farms", "building_level": 1, "resource": "grain", "hidden_resource": "", "coastal": false, "techniques": []},
			"adoption": {"cost": 500, "turns": 2},
			"culture_resistance": {},
			"effects": {"growth": 0.5, "farm_income_pct": 10},
		},
		"test_greatworks": {
			"id": "test_greatworks", "name": "Great Works", "domain": "military_engineering",
			"historical_basis": "fixture",
			"start_adopted": {"cultures": [], "factions": []},
			"origin_cultures": [],
			"prerequisites": {"building_kind": "", "building_level": 0, "resource": "", "hidden_resource": "", "coastal": false, "techniques": ["test_letters"]},
			"adoption": {"cost": 800, "turns": 2},
			"culture_resistance": {},
			"effects": {"wall_level_bonus": 1},
		},
	}

	# The fixture edicts that lived here belonged to the other edicts engine and
	# overwrote the real table loaded above, which is what test_edicts.gd reads.

	game_data.epithets = {
		"test_victor": {
			"id": "test_victor", "name": "the Victor", "historical_basis": "fixture",
			"precedence": 10, "requires": {"battles_won": 2}, "limits": {},
		},
		"test_guardian": {
			"id": "test_guardian", "name": "the Guardian", "historical_basis": "fixture",
			"precedence": 20, "requires": {"battles_won": 1}, "limits": {"cities_lost": 0},
		},
	}
	game_data.annals = {
		"battle": ["{faction} and {other_faction} met in battle near {region}."],
		"city_taken": ["{faction} took {region} from {other_faction}.",
			"The gates of {region} were opened to {faction}."],
		"epithet_earned": ["{character} of {faction} was named {epithet}."],
	}

	return game_data


static func state(game_data: GameData) -> Dictionary:
	## Two-faction world: red holds beta (capital) and epsilon, blue holds alpha.
	var campaign_state := {
		"turn": 0, "year": -270, "season": "summer", "rng_state": "0",
		"difficulty": "medium", "campaign_mode": "long", "event_happiness": null,
		"modifiers": [], "chronicle": [], "wars": [],
		"mercenary_pools": {"test_pool": {"test_merc": 1.0}},
		"player_faction": "red",
		"factions": {
			"red": _faction(game_data, "beta"),
			"blue": _faction(game_data, "alpha"),
			"rebels": _faction(game_data, ""),
		},
		"settlements": {
			"beta": _settlement(game_data, "red", 2000, {"test_government": 2, "test_farms": 1, "test_barracks": 1}),
			"epsilon": _settlement(game_data, "red", 6000, {"test_government": 2}),
			"alpha": _settlement(game_data, "blue", 1200, {"tribal_government": 1}),
		},
		"armies": {}, "fleets": {}, "characters": {},
		"events_fired": [], "event_cooldowns": {}, "winner": null, "next_id": 1,
		"tributes": [], "pending_offers": [], "agents": {},
	}
	campaign_state["factions"]["red"]["diplomacy"] = {"blue": "war", "rebels": "war"}
	campaign_state["factions"]["blue"]["diplomacy"] = {"red": "war", "rebels": "war"}
	campaign_state["factions"]["rebels"]["diplomacy"] = {"red": "war", "blue": "war"}
	return campaign_state


static func add_character(campaign_state: Dictionary, faction: String, char_id: String, overrides: Dictionary = {}) -> String:
	campaign_state["characters"][char_id] = {
		"faction": faction,
		"name": overrides.get("name", char_id.capitalize()),
		"age": int(overrides.get("age", 30)),
		"role": overrides.get("role", "family"),
		"gender": overrides.get("gender", "male"),
		"father": overrides.get("father", null),
		"command": int(overrides.get("command", 2)),
		"management": int(overrides.get("management", 2)),
		"influence": int(overrides.get("influence", 2)),
		"trait_points": overrides.get("trait_points", {}).duplicate(),
		"ancillaries": overrides.get("ancillaries", []).duplicate(),
		"location": overrides.get("location", ""),
		"alive": true,
		"deeds": {},
		"epithet": "",
	}
	return char_id


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


static func enable_guided(campaign_state: Dictionary) -> void:
	## The fixture state ships without the trail (like a pre-trail save);
	## guided tests opt in explicitly.
	campaign_state["guided"] = {"enabled": true, "counters": {}, "stages": {}}
	campaign_state["sites_explored"] = []


static func add_faction(campaign_state: Dictionary, faction_id: String, capital: String) -> void:
	campaign_state["factions"][faction_id] = _faction(shared_data(), capital)


static func add_settlement(campaign_state: Dictionary, region: String, owner: String, population: int, buildings: Dictionary) -> void:
	campaign_state["settlements"][region] = _settlement(shared_data(), owner, population, buildings)



static func _faction(game_data: GameData, capital: String) -> Dictionary:
	return {
		"treasury": 5000, "capital": capital, "alive": true, "era": "pre_marian",
		"senate_standing": 5.0, "popular_standing": 0.0, "diplomacy": {},
		"mission": null, "at_civil_war": false,
		"society": SocietyRules.new_faction_society(game_data), "advances": [],
		"ai": {}, "attitude_memory": {},
		"knowledge": {}, "reform_pressure": 0.0, "edicts": {}, "edict_cooldowns": {},
	}


static func _settlement(game_data: GameData, owner: String, population: int, buildings: Dictionary) -> Dictionary:
	return {
		"owner": owner, "population": population, "buildings": buildings,
		"tax_level": "normal", "garrison": [], "construction_queue": [],
		"recruitment_queue": [], "governor": null, "slave_bonus_turns": 0,
		"plague_turns": 0, "recently_conquered": 0, "low_order_streak": 0,
		"siege": null,
		"society": SocietyRules.new_settlement_society(game_data, true, 0.0),
		"edict": EdictRules.new_record(),
	}
