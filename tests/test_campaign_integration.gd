extends RefCounted
## Full-stack tests over the real authored data tables: the campaign boots,
## many turns resolve without invariant violations, saves round-trip, and the
## same seed replays identically.

const TURNS := 24


func test_data_loads_clean(t) -> void:
	var data := GameData.load_from("res://data")
	t.check(data.ok(), "data load errors: " + ", ".join(data.load_errors))
	t.check(data.regions.size() >= 40, "map has a real region count (got %d)" % data.regions.size())
	t.check(data.units.size() >= 40, "roster has real breadth (got %d)" % data.units.size())
	t.check(data.factions.size() >= 15, "faction list complete (got %d)" % data.factions.size())
	for faction_id in ["julii", "junii", "cornelii", "senate", "rebels"]:
		t.check(data.factions.has(faction_id), "core faction present: " + faction_id)


func test_campaign_boots(t) -> void:
	var game := Game.new_campaign("julii", 42)
	t.check(game.state["settlements"].size() >= 40, "every region settled at start")
	t.check(game.state["factions"].size() >= 15, "all factions in play")
	var julii_settlements := 0
	for settlement in game.state["settlements"].values():
		if settlement["owner"] == "julii":
			julii_settlements += 1
	t.check(julii_settlements >= 1, "the player starts with a home")


func test_long_campaign_invariants(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var start_year := int(game.state["year"])
	for i in range(TURNS):
		var report := game.end_turn()
		t.check(report is Dictionary, "end_turn returns a report")

	t.check_eq(int(game.state["turn"]), TURNS, "turn counter advanced")
	t.check_eq(int(game.state["year"]), start_year + TURNS / 2, "two turns to the year")

	for region_id in game.state["settlements"]:
		var settlement: Dictionary = game.state["settlements"][region_id]
		t.check(int(settlement["population"]) >= 400, "population floor holds in " + region_id)
		t.check(game.state["factions"].has(settlement["owner"]), "owner exists for " + region_id)
	for faction_id in game.state["factions"]:
		var faction: Dictionary = game.state["factions"][faction_id]
		t.check(typeof(faction["treasury"]) == TYPE_INT or typeof(faction["treasury"]) == TYPE_FLOAT,
			"treasury numeric for " + faction_id)


func test_same_seed_same_world(t) -> void:
	var first := Game.new_campaign("julii", 1234)
	var second := Game.new_campaign("julii", 1234)
	for i in range(8):
		first.end_turn()
		second.end_turn()
	t.check_eq(JSON.stringify(first.state), JSON.stringify(second.state), "deterministic replay")


func test_save_round_trip(t) -> void:
	var game := Game.new_campaign("julii", 7)
	for i in range(4):
		game.end_turn()
	var json_before := SaveGame.to_json(game.state)
	var restored := SaveGame.from_json(json_before)
	t.check(not restored.is_empty(), "save parses back")

	# The restored state must continue identically to the original. Compare in
	# canonical JSON form: a parsed state holds 2.0 where the live one holds 2
	# (JSON numbers are floats), which is meaningless — every reader coerces.
	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored
	game.end_turn()
	resumed.end_turn()
	t.check_eq(_canonical(game.state), _canonical(resumed.state), "resumed game marches in step")


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))


func test_growth_order_income_queries(t) -> void:
	var game := Game.new_campaign("julii", 42)
	for region_id in game.state["settlements"]:
		if game.state["settlements"][region_id]["owner"] != "julii":
			continue
		t.check(not game.growth_breakdown(region_id).is_empty(), "growth breakdown for " + region_id)
		t.check(not game.order_breakdown(region_id).is_empty(), "order breakdown for " + region_id)
		t.check(not game.income_breakdown(region_id).is_empty(), "income breakdown for " + region_id)
		t.check(not game.available_buildings(region_id).is_empty(), "something to build in " + region_id)


func test_fog_of_war(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var visible := game.visible_regions()
	t.check(visible.size() > 0, "player sees something")
	t.check(visible.size() < game.data.regions.size(), "player does not see everything")
