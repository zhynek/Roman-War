extends RefCounted

func _world() -> Game:
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	game.resolver = AutoResolver.new()
	return game

func _lose_sight(game: Game) -> void:
	game.data.terrain_crossings[TerrainRules.edge_key("alpha", "beta")] = {"kind": "ridge"}

func test_remembered_city_freezes_until_reobserved(t) -> void:
	var game := _world()
	CartographyRules.record_reports(game.data, game.state)
	var original := game.settlement_report("alpha")
	t.check(original.get("observed", false), "neighbor city initially observed")
	_lose_sight(game)
	game.state["turn"] = 3
	game.state["settlements"]["alpha"]["owner"] = "rebels"
	game.state["settlements"]["alpha"]["buildings"]["tribal_government"] = 4
	game.state["settlements"]["alpha"]["population"] = 18000
	Fixtures.add_army(game.state, "rebels", "alpha", ["test_mob", "test_spears"])
	CartographyRules.record_reports(game.data, game.state)
	var remembered := game.settlement_report("alpha")
	original["observed"] = false
	t.check_eq(remembered, original, "unseen ownership, city growth and troops cannot rewrite the old survey")
	t.check(game.known_regions().has("alpha"), "the land remains charted after sight is lost")
	t.check(not remembered.has("garrison") and not remembered.has("armies"), "architecture reports carry no troop rosters")
	game.data.terrain_crossings.clear()
	CartographyRules.record_reports(game.data, game.state)
	var current := game.settlement_report("alpha")
	t.check_eq(current["level"], "minor_city", "fresh sight updates architecture")
	t.check_eq(current["owner"], "rebels", "fresh sight updates ownership")
	t.check_eq(current["turn"], 3, "survey keeps its observation date")

func test_watchtower_keeps_survey_current_but_forest_troops_need_detection(t) -> void:
	var game := _world()
	game.data.balance = game.data.balance.duplicate(true)
	game.data.balance["reconnaissance"]["settlement_sight"] = 0
	game.data.regions["alpha"]["terrain"] = "forest"
	CartographyRules.record_reports(game.data, game.state)
	t.check(game.settlement_report("alpha").is_empty(), "no invented survey of unseen forest town")
	game.state["watchposts"]["beta"] = {"owner": "red", "level": 1}
	var hidden := Fixtures.add_army(game.state, "blue", "alpha", ["test_mob"])
	CartographyRules.record_reports(game.data, game.state)
	t.check(game.settlement_report("alpha").get("observed", false), "watchtower maintains geographic observation")
	t.check(not game.army_is_visible(hidden), "distant watchtower cannot inspect a forest's concealed roster")
	game.state["turn"] = 2
	game.state["settlements"]["alpha"]["buildings"]["tribal_government"] = 2
	CartographyRules.record_reports(game.data, game.state)
	t.check_eq(game.settlement_report("alpha")["level"], "town", "observed development remains current")
	game.state["watchposts"]["beta"]["level"] = 2
	t.check(game.army_is_visible(hidden), "fortified post supplies the existing nearby forest detection")

func test_reports_survive_save_load_and_readers_are_detached(t) -> void:
	var game := _world()
	CartographyRules.record_reports(game.data, game.state)
	_lose_sight(game)
	var text := SaveGame.to_json(game.state)
	var loaded := SaveGame.from_json(text)
	t.check(not loaded.is_empty(), "memory passes save validation")
	NewGame.ensure_state_keys(loaded, game.data)
	t.check_eq(loaded["settlement_memory"], JSON.parse_string(JSON.stringify(game.state["settlement_memory"])), "normalization preserves the saved surveys")
	var before := JSON.stringify(game.state)
	var report := game.settlement_report("alpha")
	report["buildings"].clear()
	var reports := game.settlement_reports()
	reports["beta"]["watchpost"]["owner"] = "blue"
	t.check_eq(JSON.stringify(game.state), before, "queries and UI cache edits cannot mutate game state or RNG")

func test_legacy_saves_do_not_invent_unseen_settlement_history(t) -> void:
	var game := _world()
	CartographyRules.record_reports(game.data, game.state)
	_lose_sight(game)
	game.state.erase("settlement_memory")
	var rng: String = game.state["rng_state"]
	NewGame.ensure_state_keys(game.state, game.data)
	t.check(game.settlement_report("alpha").is_empty(), "old geographic chart does not invent an architectural report")
	t.check(not game.settlement_report("beta").is_empty(), "migration seeds only current observation")
	t.check_eq(game.state["rng_state"], rng, "migration draws no RNG")

func test_bought_maps_do_not_grant_live_city_or_troop_intelligence(t) -> void:
	var game := Game.new_campaign("julii", 42)
	CartographyRules.grant(game.data, game.state, "egypt", "julii")
	t.check(game.known_regions().has("aegyptus"), "treaty grants terrain")
	t.check(game.settlement_report("aegyptus").is_empty(), "geography treaty does not grant a live city survey")

func test_malformed_memory_is_rejected_before_rendering(t) -> void:
	var game := _world()
	CartographyRules.record_reports(game.data, game.state)
	for malformed in [[], {"red": []}, {"red": {"alpha": {}}}]:
		var state := game.state.duplicate(true)
		state["settlement_memory"] = malformed
		t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(), "malformed nested memory rejected")
	for change in [{"level": "palace"}, {"turn": -1}, {"turn": 100}, {"buildings": [null]}, {"watchpost": {"level": 2}}]:
		var state := game.state.duplicate(true)
		state["settlement_memory"]["red"]["alpha"].merge(change, true)
		t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(), "invalid report rejected before any UI reader")

func test_survey_shows_working_construction_without_revealing_queued_plans(t) -> void:
	var game := _world()
	game.state["settlements"]["alpha"]["construction_queue"] = [
		{"chain": "test_walls", "turns_left": 2}, {"chain": "test_barracks", "turns_left": 4}]
	CartographyRules.record_reports(game.data, game.state)
	t.check_eq(game.settlement_report("alpha")["construction"], ["wall_1"], "only current works are visible")
	_lose_sight(game)
	game.state["settlements"]["alpha"]["construction_queue"].clear()
	t.check_eq(game.settlement_report("alpha")["construction"], ["wall_1"], "unseen completed works retain old scaffolding")
