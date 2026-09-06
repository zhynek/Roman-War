extends RefCounted

func _world() -> Game:
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	game.resolver = AutoResolver.new()
	return game

func test_ridge_blocks_move_path_attack_siege_and_sight_without_rng(t) -> void:
	var game := _world()
	var army := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	var enemy := Fixtures.add_army(game.state, "blue", "alpha", ["test_mob"])
	game.data.terrain_crossings[TerrainRules.edge_key("alpha", "beta")] = {"kind": "ridge"}
	var before := game.state.duplicate(true)
	t.check(not MovementRules.can_enter(game.data, game.state, army, "alpha"), "ridge has no march connection")
	t.check(is_inf(MovementRules.step_cost(game.data, game.state, "alpha", "beta")), "no budget pays for a ridge")
	t.check(game.attack_army(army, enemy).is_empty(), "an attack cannot teleport across a ridge")
	game.state["armies"].erase(enemy)
	t.check(not game.besiege(army, "alpha"), "siege also respects the ridge")
	t.check(not game.visible_regions().has("alpha"), "nearby sight cannot see through the ridge")
	t.check_eq(game.state["rng_state"], before["rng_state"], "blocked actions consume no random draws")

func test_bridge_cost_preview_execution_and_defense_share_one_rule(t) -> void:
	var game := _world()
	var army := Fixtures.add_army(game.state, "red", "alpha", ["test_spears"])
	var enemy := Fixtures.add_army(game.state, "blue", "beta", ["test_mob"])
	game.data.terrain_crossings[TerrainRules.edge_key("alpha", "beta")] = {"kind": "bridge"}
	var context := CombatRules.battle_context(game.data, game.state, game.state["armies"][army], game.state["armies"][enemy])
	var estimate := BattleResolver.estimate(game.data, game.state["armies"][army]["units"], game.state["armies"][enemy]["units"], context)
	t.check_eq(context["crossing_defense_pct"], 20.0, "bridge defense reaches the resolver")
	t.check(estimate["defender"]["factors"].any(func(f): return f["label"] == "crossing" and is_equal_approx(f["value"], 1.2)), "odds show the exact bridge advantage")
	game.state["armies"].erase(enemy)
	var quote := game.army_order_preview(army, "beta")
	t.check_near(quote["cost"], 1.25, 0.0001, "quote includes the crossing surcharge")
	var before := float(game.state["armies"][army]["movement_left"])
	t.check(game.move_army(army, "beta"), "the bridge permits the quoted march")
	t.check_near(before - float(game.state["armies"][army]["movement_left"]), quote["cost"], 0.0001, "execution pays the quoted cost")

func test_marsh_roads_and_elevated_defense_are_data_driven(t) -> void:
	var game := _world()
	game.data.regions["gamma"]["terrain"] = "marsh"
	t.check_near(MovementRules.step_cost(game.data, game.state, "gamma", "beta"), 2.0, 0.0001, "marsh costs twice a plain step")
	game.data.regions["gamma"]["terrain"] = "mountains"
	var a := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	var d := Fixtures.add_army(game.state, "blue", "gamma", ["test_spears"])
	var context := CombatRules.battle_context(game.data, game.state, game.state["armies"][a], game.state["armies"][d])
	var result := BattleResolver.estimate(game.data, game.state["armies"][a]["units"], game.state["armies"][d]["units"], context)
	t.check(result["defender"]["factors"].any(func(f): return f["label"] == "terrain" and f["value"] > 1.0), "troops defending mountain terrain gain elevated defense")

func test_new_campaign_only_knows_its_reports_and_cannot_order_uncharted(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var known := game.known_regions()
	t.check(known.size() < game.data.regions.size(), "a new campaign is not an omniscient atlas")
	t.check(not known.has("parthia"), "distant land starts uncharted")
	var army := ""
	for id in game.state["armies"]:
		if game.state["armies"][id]["owner"] == "julii":
			army = id
			break
	t.check_eq(game.army_order_preview(army, "parthia")["reason"], "uncharted", "UI explains why a distant destination is unavailable")
	t.check(game.army_path_preview(army, "parthia").is_empty(), "pathfinder cannot disclose a route through uncharted provinces")
	var before := JSON.stringify(game.state)
	game.known_regions()
	game.visible_regions()
	game.terrain_report("parthia")
	t.check_eq(JSON.stringify(game.state), before, "map and terrain readers never mutate state")

func test_paid_map_access_persists_without_live_intel_and_ends_on_war(t) -> void:
	var game := Game.new_campaign("julii", 42)
	DiplomacyRules.set_stance(game.state, "julii", "egypt", "alliance")
	var own_sight := game.visible_regions()
	var before := String(game.state["rng_state"])
	var offer := {"from": "julii", "to": "egypt", "ask_map_access": true, "give_payment": 10000}
	game.state["factions"]["julii"]["treasury"] = 20000
	var value := DiplomacyRules.evaluate_offer(game.data, game.state, "julii", "egypt", offer)
	t.check(value["accept"], "a sufficiently funded treaty can buy maps")
	DiplomacyRules.apply_offer(game.data, game.state, offer)
	t.check(game.known_regions().has("aegyptus"), "signed map rights disclose their atlas")
	t.check_eq(game.visible_regions(), own_sight, "map sharing grants no live army observation")
	t.check_eq(game.state["factions"]["julii"]["treasury"], 10000, "the accepted map trade charges its payment")
	DiplomacyRules.set_stance(game.state, "julii", "egypt", "war")
	t.check(not game.state["map_access"]["egypt"].has("julii"), "war revokes future updates")
	t.check(game.known_regions().has("aegyptus"), "already learned geography is retained")
	t.check_eq(game.state["rng_state"], before, "mapping and negotiation consume no RNG")
	var twin: Dictionary = JSON.parse_string(JSON.stringify(game.state))
	NewGame.ensure_state_keys(twin, game.data)
	t.check_eq(twin["cartography"], JSON.parse_string(JSON.stringify(game.state["cartography"])), "atlas survives save normalization")
	t.check_eq(twin["map_access"], game.state["map_access"], "map rights survive save normalization")

func test_old_saves_are_seeded_only_from_present_reports(t) -> void:
	var game := Game.new_campaign("julii", 42)
	game.state.erase("cartography")
	game.state.erase("map_access")
	var before := String(game.state["rng_state"])
	NewGame.ensure_state_keys(game.state, game.data)
	t.check(game.state.has("cartography") and game.state.has("map_access"), "old saves get additive mapping keys")
	t.check(not game.known_regions().has("parthia"), "migration never reveals the whole map")
	t.check_eq(game.state["rng_state"], before, "migration preserves random state")

func test_land_supply_and_commerce_cannot_cross_a_blocked_border(t) -> void:
	var game := _world()
	game.state["settlements"]["alpha"]["owner"] = "red"
	t.check(TerrainRules.supply_regions(game.data, game.state, "red").has("alpha"), "friendly neighboring land has a supply link")
	game.data.terrain_crossings[TerrainRules.edge_key("alpha", "beta")] = {"kind": "river"}
	t.check(not TerrainRules.supply_regions(game.data, game.state, "red").has("alpha"), "unbridged water severs that ground supply link")
	game.data.terrain_crossings[TerrainRules.edge_key("alpha", "beta")]["kind"] = "bridge"
	t.check(TerrainRules.supply_regions(game.data, game.state, "red").has("alpha"), "a bridge restores the land connection")
