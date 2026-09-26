extends RefCounted

func _world() -> Game:
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	game.resolver = AutoResolver.new()
	game.data.regions["gamma"]["terrain"] = "forest"
	game.data.regions["alpha"]["terrain"] = "forest"
	return game

func test_geography_is_not_force_observation_or_a_roster_oracle(t) -> void:
	var g := _world()
	var own := Fixtures.add_army(g.state, "red", "beta", ["test_spears"])
	var foe := Fixtures.add_army(g.state, "blue", "gamma", ["test_mob"])
	t.check(g.visible_regions().has("gamma"), "lookouts chart the woodland")
	t.check(not g.army_is_visible(foe), "lookouts cannot spot troops below the canopy")
	var before := JSON.stringify(g.state)
	var quote := g.army_order_preview(own, "gamma")
	var reach := g.reachable_regions(own)
	t.check(g.force_summary(foe).is_empty(), "direct force query reveals nothing")
	t.check(g.battle_estimate(own, foe).is_empty(), "guessed army IDs reveal no odds")
	t.check(not g.targets_for(own).has("gamma"), "no red attack ring betrays a hidden force")
	t.check(g.observed_armies_in("gamma").is_empty(), "region list has no concealed entry")
	t.check_eq(JSON.stringify(g.state), before, "all preview queries are read-only")
	g.state["armies"].erase(foe)
	t.check_eq(g.army_order_preview(own, "gamma"), quote, "a hidden force does not change the quote")
	t.check_eq(g.reachable_regions(own), reach, "a hidden force does not change reach or block warnings")

func test_patrol_cost_expiry_reveal_and_save_replay(t) -> void:
	var g := _world()
	var own := Fixtures.add_army(g.state, "red", "beta", ["test_spears"])
	var foe := Fixtures.add_army(g.state, "blue", "gamma", ["test_mob"])
	var rng: String = g.state["rng_state"]
	var points := float(g.state["armies"][own]["movement_left"])
	t.check(g.patrol_woods(own)["ok"], "patrol is an actual order")
	t.check_near(g.state["armies"][own]["movement_left"], points - 1, 0.0001, "patrol spends exactly its configured movement")
	t.check(g.army_is_visible(foe), "the patrol reveals the concealed force")
	t.check_eq(g.army_order_preview(own, "gamma")["action"], "attack", "newly spotted enemies become explicit battle targets")
	t.check_eq(g.state["rng_state"], rng, "spotting has no random draw")
	var loaded := SaveGame.from_json(SaveGame.to_json(g.state))
	NewGame.ensure_state_keys(loaded, g.data)
	t.check(VisibilityRules.visible_armies(g.data, loaded, "red").has(foe), "save preserves the season's patrol")
	g.state["turn"] += 1
	loaded["turn"] += 1
	t.check(not g.army_is_visible(foe), "cover returns next season if observers have left")
	t.check_eq(VisibilityRules.visible_armies(g.data, loaded, "red"), g.visible_armies(), "loaded sight expires identically")

func test_unaffordable_and_foreign_patrols_are_noops(t) -> void:
	var g := _world()
	var own := Fixtures.add_army(g.state, "red", "beta", ["test_spears"])
	var foe := Fixtures.add_army(g.state, "blue", "gamma", ["test_mob"])
	g.state["armies"][own]["movement_left"] = 0.0
	var before := JSON.stringify(g.state)
	t.check(not g.patrol_woods(own)["ok"] and not g.patrol_woods(foe)["ok"], "unfunded and foreign patrols are refused")
	t.check(not g.move_army(own, "gamma"), "an unaffordable attempted march cannot scout")
	t.check_eq(JSON.stringify(g.state), before, "rejected actions preserve all state")

func test_contact_halts_without_automatic_battle_then_allows_counterplay(t) -> void:
	var g := _world()
	var own := Fixtures.add_army(g.state, "red", "beta", ["test_spears"])
	var foe := Fixtures.add_army(g.state, "blue", "gamma", ["test_mob"])
	var rng: String = g.state["rng_state"]
	var result := g.march_army(own, "gamma")
	t.check(result["halted"] and result["moved"] == 0, "the advance guard halts at the forest border")
	t.check_eq(g.state["armies"][own]["region"], "beta", "no movement through a concealed enemy")
	t.check(g.army_is_visible(foe), "actual contact reveals the blocking column")
	t.check_eq(g.state["rng_state"], rng, "contact never silently resolves combat")
	t.check_near(g.state["armies"][own]["movement_left"], 1.0, 0.0001, "contact spends a patrol point, preventing free probes")
	t.check(not g.state["armies"][own].has("march_path"), "contact cancels the queued march")

func test_movement_reports_clip_woodland_endpoints_and_forced_march_exposes(t) -> void:
	var g := _world()
	var foe := Fixtures.add_army(g.state, "blue", "alpha", ["test_mob"])
	ReconRules.record_move(g.data, g.state, foe, "beta")
	var report: Dictionary = g.state["recon"]["movements"].back()
	t.check_eq(report["from"], "", "forest origin remains absent from an emergence report")
	t.check_eq(report["to"], "beta", "visible emergence is reported")
	g.state["armies"][foe]["region"] = "beta"
	ReconRules.record_move(g.data, g.state, foe, "alpha")
	report = g.state["recon"]["movements"].back()
	t.check_eq(report["to"], "", "entering woods hides the destination")
	g.state["armies"][foe]["region"] = "alpha"
	g.state["armies"][foe]["forced_march"] = true
	t.check(g.army_is_visible(foe), "a forced march gives up concealment")

func test_spies_local_presence_and_posts_respect_physical_barriers(t) -> void:
	var g := _world()
	var foe := Fixtures.add_army(g.state, "blue", "gamma", ["test_mob"])
	g.state["agents"]["scout"] = {"owner":"red", "region":"beta", "kind":"spy"}
	t.check(g.army_is_visible(foe), "an adjacent spy penetrates the forest")
	g.state["agents"].clear()
	g.state["watchposts"]["beta"] = {"owner":"red", "level":1}
	t.check(not g.army_is_visible(foe), "distant tower lookouts do not penetrate woods")
	g.state["watchposts"]["beta"]["level"] = 2
	t.check(g.army_is_visible(foe), "a fort patrols the adjacent woodland")
	g.data.terrain_crossings[TerrainRules.edge_key("beta", "gamma")] = {"kind":"ridge"}
	t.check(not g.army_is_visible(foe), "a fort cannot patrol through an impassable ridge")

func test_map_treaty_and_old_save_migration_do_not_reveal_forest_forces(t) -> void:
	var g := _world()
	var foe := Fixtures.add_army(g.state, "blue", "gamma", ["test_mob"])
	DiplomacyRules.set_stance(g.state, "red", "blue", "alliance")
	CartographyRules.grant(g.data, g.state, "blue", "red")
	t.check(g.known_regions().has("gamma"), "maps include the grantor's observed forest")
	t.check(not g.army_is_visible(foe), "the treaty never supplies forest detection")
	g.state.erase("forest_patrols")
	var rng: String = g.state["rng_state"]
	NewGame.ensure_state_keys(g.state, g.data)
	t.check_eq(g.state["forest_patrols"], {}, "old saves receive an empty additive patrol ledger")
	t.check_eq(g.state["rng_state"], rng, "migration consumes no RNG")

func test_route_is_repeatable_and_every_leg_uses_campaign_rules(t) -> void:
	var g := CampaignRoute.build()
	var twin := CampaignRoute.build()
	t.check_eq(JSON.stringify(g.state), JSON.stringify(twin.state), "development route has identical initial conditions")
	var route: Array = g.data.terrain_content["development_route"]["regions"]
	var own := ""
	for id in g.state["armies"]:
		if g.state["armies"][id]["owner"] == g.state["player_faction"]:
			own = id
			break
	for i in range(1, route.size()):
		var origin := String(g.state["armies"][own]["region"])
		var cost := MovementRules.step_cost(g.data, g.state, route[i], origin)
		# Use normal seasonal reset in this focused movement test; full end-turn
		# replay and the standalone build probe separately test the wider world.
		MovementRules.reset_movement(g.data, g.state)
		var before := float(g.state["armies"][own]["movement_left"])
		var quote := g.army_order_preview(own, route[i])
		t.check_near(quote["cost"], cost, 0.0001, "route waypoint quotes the real edge cost")
		t.check(g.march_army(own, route[i]).get("arrived", false), "route waypoint is playable through march_army")
		t.check_near(before - float(g.state["armies"][own]["movement_left"]), cost, 0.0001, "route execution pays its terrain and crossing cost")

func test_mounted_scouts_reveal_and_hidden_ids_cannot_cancel_orders(t) -> void:
	var g := _world()
	var own := Fixtures.add_army(g.state, "red", "beta", ["test_spears"])
	var foe := Fixtures.add_army(g.state, "blue", "gamma", ["test_mob"])
	g.state["armies"][own]["march_path"] = ["delta"]
	var before := JSON.stringify(g.state)
	t.check(g.attack_army(own, foe).is_empty(), "a guessed hidden id cannot be attacked")
	t.check_eq(JSON.stringify(g.state), before, "rejected hidden attack cannot erase an existing order")
	g.data.units["scout_riders"] = g.data.units["test_spears"].duplicate(true)
	g.data.units["scout_riders"]["class"] = "cavalry"
	g.state["armies"][own]["units"][0]["template"] = "scout_riders"
	t.check(g.army_is_visible(foe), "an adjacent mounted column spots the hidden enemy")
	g.state["armies"][own]["region"] = "epsilon"
	t.check(not g.army_is_visible(foe), "distant mounted sight maps more land than it can search")

func test_render_caches_and_classic_banners_share_the_force_visibility_mask(t) -> void:
	var g := _world()
	var own := Fixtures.add_army(g.state, "red", "beta", ["test_spears"])
	var foe := Fixtures.add_army(g.state, "blue", "gamma", ["test_mob"])
	var view := MapView.new()
	view.game = g
	view.size = Vector2(900, 700)
	Engine.get_main_loop().root.add_child(view)
	view.refresh_state()
	t.check(not view.army_visuals.has(foe) and not view.force_summaries.has(foe), "both rendering surfaces receive no hidden model input")
	t.check(not view.army_groups.has("gamma"), "aggregate badges cannot disclose the concealed army")
	g.patrol_woods(own)
	view.refresh_state()
	t.check(view.army_visuals.has(foe), "patrol adds the force to the render cache")
	t.check(view.army_visuals[foe]["classes"].is_empty(), "the revealed enemy uses a generic public model")
	var look: Array = view.troop_looks[foe].duplicate(true)
	g.state["armies"][foe]["units"] = []
	view.refresh_state()
	t.check_eq(view.troop_looks[foe], look, "hidden enemy composition cannot change the model")
	view.free()
