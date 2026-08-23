extends RefCounted
## Phase 7: the office ladder, mission variety, and civil-war sides.


func _world() -> Array:
	var data := Fixtures.data()
	# The fixtures know nothing of Rome; teach them just enough politics.
	data.factions["red"]["is_roman_house"] = true
	data.factions["senate"] = {"id": "senate", "name": "The Senate", "culture": "roman", "is_senate": true}
	var offices_text := FileAccess.get_file_as_string("res://data/offices.json")
	for office in JSON.parse_string(offices_text).get("offices", []):
		data.offices[office["id"]] = office
	var missions_text := FileAccess.get_file_as_string("res://data/missions.json")
	for mission in JSON.parse_string(missions_text).get("missions", []):
		data.missions[mission["id"]] = mission
	var state := Fixtures.state(data)
	state["factions"]["senate"] = {
		"treasury": 0, "capital": "", "alive": true, "era": "pre_marian",
		"senate_standing": 5.0, "popular_standing": 0.0, "diplomacy": {},
		"mission": null, "at_civil_war": false,
		"ai_memory": {"target": null, "war_since": {}}, "attitude": {},
	}
	return [data, state]


func test_offices_follow_standing_and_age(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	Fixtures.add_character(state, "red", "elder", {"age": 45, "influence": 5, "role": "leader"})
	Fixtures.add_character(state, "red", "rising", {"age": 33, "influence": 3})
	Fixtures.add_character(state, "red", "pup", {"age": 21, "influence": 9})
	var rng := CampaignRng.seeded(2)
	var notices := SenateRules.process_turn(data, state, rng)

	# Consul (rank 6, min 32) goes to the strongest eligible: elder, then rising.
	t.check_eq(state["characters"]["elder"]["office"], "consul", "the elder takes a consulship")
	t.check_eq(state["characters"]["rising"]["office"], "consul", "the second seat follows")
	# The pup is too young for every office above quaestor's ladder steps that fit.
	t.check_eq(state["characters"]["pup"]["office"], "quaestor", "youth starts at the bottom")

	var office_notices := 0
	for notice in notices:
		if notice.get("kind", "") == "office_gained":
			office_notices += 1
	t.check_eq(office_notices, 3, "each new office makes news")

	# Office effects flow through the character engine.
	var base := Fixtures.data()
	var effective := CharacterRules.effective(data, state["characters"]["elder"], "influence")
	t.check_eq(effective, 5 + 2, "a consul carries weight (base 5 + office 2)")


func test_offices_reshuffle_yearly_not_in_winter(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	Fixtures.add_character(state, "red", "elder", {"age": 45, "influence": 5})
	state["season"] = "winter"
	var rng := CampaignRng.seeded(2)
	SenateRules.process_turn(data, state, rng)
	t.check(state["characters"]["elder"].get("office") == null, "no winter elections")


func test_mission_variety_and_completion(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	# Make blue courtable so alliance/trade missions are feasible, and give
	# the world a rebel neighbor for take_region.
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	state["settlements"]["gamma"] = {
		"owner": "rebels", "population": 800, "buildings": {},
		"tax_level": "normal", "garrison": [], "construction_queue": [],
		"recruitment_queue": [], "governor": null, "slave_bonus_turns": 0,
		"plague_turns": 0, "recently_conquered": 0, "low_order_streak": 0, "siege": null,
	}
	var rng := CampaignRng.seeded(2)
	SenateRules.process_turn(data, state, rng)
	var mission = state["factions"]["red"]["mission"]
	t.check(mission != null, "a mission is issued")
	var kind := String(data.missions[mission["template"]]["kind"])
	t.check(kind in ["take_region", "make_alliance", "reach_trade_agreement"],
		"the mission is feasible for this world (got %s)" % kind)

	# Force an alliance mission and complete it through the Phase 5 machinery.
	state["factions"]["red"]["mission"] = {
		"template": "court_a_useful_friend", "target_faction": "blue", "turns_left": 8,
	}
	var standing_before := float(state["factions"]["red"]["senate_standing"])
	DiplomacyRules.set_stance(state, "red", "blue", "alliance")
	var notices := SenateRules.process_turn(data, state, rng)
	t.check(state["factions"]["red"]["mission"] == null, "the alliance mission resolves")
	t.check(float(state["factions"]["red"]["senate_standing"]) > standing_before,
		"the senate is pleased")


func test_blockade_mission_gives_fleets_a_purpose(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	# Alpha is blue's coastal town on test_sea; pretend it has a port.
	data.chains["test_port"] = {
		"id": "test_port", "kind": "port", "cultures": ["barbarian"], "name": "Docks",
		"levels": [{"id": "port_1", "name": "Docks", "min_settlement_level": "village",
			"cost": 300, "build_turns": 1, "effects": {"port_level": 1}, "description": ""}],
	}
	state["settlements"]["alpha"]["buildings"]["test_port"] = 1
	state["factions"]["red"]["mission"] = {
		"template": "strangle_their_harbor", "target_region": "alpha", "turns_left": 8,
	}
	state["fleets"]["fleet_1"] = {"owner": "red", "sea_zone": "test_sea",
		"ships": [{"template": "test_spears", "experience": 0, "strength_pct": 100}],
		"movement_left": 0.0}
	var rng := CampaignRng.seeded(2)
	SenateRules.process_turn(data, state, rng)
	t.check(state["factions"]["red"]["mission"] == null,
		"a fleet on the enemy's sea lane completes the blockade")


func test_leader_suicide_comply_and_outlaw(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	Fixtures.add_character(state, "red", "old_lion", {"age": 60, "role": "leader"})
	Fixtures.add_character(state, "red", "cub", {"age": 30, "role": "heir"})
	state["factions"]["red"]["senate_standing"] = -8.0
	state["year"] = -50  # the demand is a late-Republic horror (min_year -60)
	var rng := CampaignRng.seeded(2)
	SenateRules.process_turn(data, state, rng)
	var mission = state["factions"]["red"]["mission"]
	t.check(mission != null and String(data.missions[mission["template"]]["kind"]) == "leader_suicide",
		"at rock bottom the senate demands the leader's life")
	t.check_eq(mission["target_char"], "old_lion", "and names him")

	# Complying kills the leader; the heir succeeds; the mission then resolves.
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	t.check(game.comply_senate_demand(), "the house complies")
	t.check(not state["characters"]["old_lion"]["alive"], "the old lion falls on his sword")
	t.check_eq(state["characters"]["cub"]["role"], "leader", "the cub takes the house")
	SenateRules.process_turn(data, state, rng)
	t.check(state["factions"]["red"]["mission"] == null, "the demand is satisfied")

	# The alternative: let the deadline lapse — the house is outlawed.
	state["factions"]["red"]["senate_standing"] = -8.0
	state["factions"]["red"]["mission"] = {
		"template": "the_senate_demands_your_life", "target_char": "cub", "turns_left": 1,
	}
	var notices := SenateRules.process_turn(data, state, rng)
	t.check(state["factions"]["red"]["at_civil_war"], "refusal means outlawry and civil war")
	var outlawed := false
	for notice in notices:
		if notice.get("kind", "") == "outlawed":
			outlawed = true
	t.check(outlawed, "the outlawry makes news")
	t.check(DiplomacyRules.at_war(state, "red", "senate"), "the senate is now an enemy")


func test_expansion_event_fires(t) -> void:
	var data := GameData.load_from("res://data")
	var game := Game.new_campaign("julii", 42)
	# Hand julii 18 regions outright and process a turn's events.
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	var granted := 0
	for region_id in region_ids:
		if granted >= 18:
			break
		game.state["settlements"][region_id]["owner"] = "julii"
		granted += 1
	var rng := CampaignRng.seeded(3)
	var fired := EventRules.process_turn(game.data, game.state, rng)
	var seen := false
	for event in fired:
		if event.get("id", "") == "master_of_the_middle_sea":
			seen = true
			t.check_eq(event.get("faction", ""), "julii", "the event names the master")
	t.check(seen, "holding 18 regions fires the expansion event")
