extends RefCounted
## The guided campaign trail and point-of-interest exploration: counter
## safety, stage lifecycle (chains, any/all, baselines, expiry, cooldowns,
## reactive targets), rewards including boons and their read paths,
## choke-point counters, explore semantics, and real-data determinism with
## scripted player actions.


func _game(data: GameData, state: Dictionary) -> Game:
	var game := Game.new()
	game.data = data
	game.resolver = AutoResolver.new()
	game.state = state
	return game


func _stage(id: String, trigger: Dictionary, objectives: Array, extra: Dictionary = {}) -> Dictionary:
	var stage := {
		"id": id, "name": id.capitalize(), "text": "Test stage %s." % id,
		"trigger": trigger, "objectives": objectives, "reward": {"treasury": 100},
	}
	for key in extra:
		stage[key] = extra[key]
	return stage


func _install_stages(data: GameData, stages: Array) -> void:
	data.guided_stages = stages
	data.guided_stage_index = {}
	for stage in stages:
		data.guided_stage_index[stage["id"]] = stage


func _install_site(data: GameData, region: String, outcomes: Array) -> String:
	var site := {
		"id": "test_site_%s" % region, "region": region, "name": "Test Site",
		"kind": "cache", "text": "A testing ground.", "outcomes": outcomes,
	}
	data.sites[site["id"]] = site
	data.sites_by_region[region] = site
	return site["id"]


## --- Counter safety --------------------------------------------------------

func test_bumps_are_safe_and_player_only(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var game := _game(data, state)
	# No guided key at all (a pre-trail save): actions must not crash.
	t.check(game.set_tax_level("beta", "high"), "action works without the trail")
	t.check(not state.has("guided"), "no trail state sprouts on its own")

	Fixtures.enable_guided(state)
	state["guided"]["enabled"] = false
	game.set_tax_level("beta", "low")
	t.check(state["guided"]["counters"].is_empty(), "a disabled trail counts nothing")

	state["guided"]["enabled"] = true
	game.set_tax_level("beta", "normal")
	t.check_eq(int(state["guided"]["counters"].get("taxes_set", 0)), 1, "player action counted")
	game.set_tax_level("alpha", "high")  # blue's settlement — the API allows it,
	t.check_eq(int(state["guided"]["counters"].get("taxes_set", 0)), 1,
		"but only the player's own settlements count")
	t.check(game.queue_building("beta", "test_farms"), "building queued")
	t.check_eq(int(state["guided"]["counters"].get("buildings_queued", 0)), 1, "build counted")
	t.check_eq(int(state["guided"]["counters"].get("buildings_queued:farms", 0)), 1,
		"build counted under its kind too")


## --- Stage lifecycle -------------------------------------------------------

func test_start_and_after_chain(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	_install_stages(data, [
		_stage("s_one", {"kind": "start"}, [{"kind": "set_taxes"}]),
		_stage("s_two", {"kind": "after", "stages": ["s_one"]}, [{"kind": "set_taxes"}]),
	])
	var game := _game(data, state)

	var notices := GuidedRules.process_turn(data, state)
	t.check_eq(notices.size(), 1, "only the start stage opens")
	t.check_eq(state["guided"]["stages"]["s_one"]["status"], "active", "start stage active")
	t.check(not state["guided"]["stages"].has("s_two"), "the follower waits")

	game.set_tax_level("beta", "high")
	notices = GuidedRules.process_turn(data, state)
	t.check_eq(state["guided"]["stages"]["s_one"]["status"], "done", "objective met, stage done")
	t.check_eq(state["guided"]["stages"]["s_two"]["status"], "active",
		"the follower opens the same pass, after judgement")
	var kinds: Array = []
	for notice in notices:
		kinds.append(notice["kind"])
	t.check(kinds.has("stage_complete") and kinds.has("stage_started"), "both notices reported")
	# The follower judged only NEXT turn even though its counter baseline
	# predates it — the baseline snapshot excludes the earlier tax change.
	notices = GuidedRules.process_turn(data, state)
	t.check_eq(state["guided"]["stages"]["s_two"]["status"], "active",
		"the follower does not inherit the parent's deed")
	game.set_tax_level("beta", "low")
	GuidedRules.process_turn(data, state)
	t.check_eq(state["guided"]["stages"]["s_two"]["status"], "done", "its own deed completes it")


func test_any_vs_all_completion(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	_install_stages(data, [
		_stage("wants_any", {"kind": "start"},
			[{"kind": "set_taxes"}, {"kind": "hold_regions", "count": 99}], {"complete": "any"}),
		_stage("wants_all", {"kind": "start"},
			[{"kind": "set_taxes"}, {"kind": "hold_regions", "count": 99}]),
	])
	var game := _game(data, state)
	GuidedRules.process_turn(data, state)
	game.set_tax_level("beta", "high")
	GuidedRules.process_turn(data, state)
	t.check_eq(state["guided"]["stages"]["wants_any"]["status"], "done", "any-of: one path suffices")
	t.check_eq(state["guided"]["stages"]["wants_all"]["status"], "active", "all-of: still short")


func test_expiry_closes_without_reward_and_unblocks_followers(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	_install_stages(data, [
		_stage("doomed", {"kind": "start"}, [{"kind": "hold_regions", "count": 99}],
			{"expires_turns": 3}),
		_stage("heir", {"kind": "after", "stages": ["doomed"]}, [{"kind": "set_taxes"}]),
	])
	GuidedRules.process_turn(data, state)
	var treasury_before := int(state["factions"]["red"]["treasury"])
	state["turn"] = 3
	var notices := GuidedRules.process_turn(data, state)
	t.check_eq(state["guided"]["stages"]["doomed"]["status"], "expired", "the stage lapsed")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before, "no reward for a lapse")
	t.check_eq(state["guided"]["stages"]["heir"]["status"], "active",
		"expiry closes the stage without failing the trail")
	var expired_seen := false
	for notice in notices:
		if notice["kind"] == "stage_expired":
			expired_seen = true
	t.check(expired_seen, "the lapse is reported")


func test_reactive_siege_stage_is_target_bound(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	_install_stages(data, [
		_stage("relief", {"kind": "player_settlement_besieged"},
			[{"kind": "no_siege_on_target"}],
			{"expires_turns": 8, "repeatable": true, "cooldown_turns": 5}),
	])
	# Blue invests red's epsilon.
	var blue_army := Fixtures.add_army(state, "blue", "delta", ["test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, blue_army, "epsilon"), "the enemy invests epsilon")

	GuidedRules.process_turn(data, state)
	var inst: Dictionary = state["guided"]["stages"]["relief"]
	t.check_eq(inst["status"], "active", "the alarm is raised")
	t.check_eq(inst["target"], "epsilon", "bound to the besieged city")

	# The siege is broken (the besieger is destroyed): the stage pays out.
	state["settlements"]["epsilon"]["siege"] = null
	state["armies"].erase(blue_army)
	var treasury_before := int(state["factions"]["red"]["treasury"])
	GuidedRules.process_turn(data, state)
	t.check_eq(inst["status"], "cooldown", "a repeatable stage rests after firing")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before + 100, "relief rewarded")


func test_reactive_siege_pays_nothing_if_the_city_falls(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	_install_stages(data, [
		_stage("relief", {"kind": "player_settlement_besieged"},
			[{"kind": "no_siege_on_target"}],
			{"expires_turns": 4, "repeatable": true, "cooldown_turns": 5}),
	])
	var blue_army := Fixtures.add_army(state, "blue", "delta", ["test_spears"])
	MovementRules.reset_movement(data, state)
	SiegeRules.begin_siege(data, state, blue_army, "epsilon")
	GuidedRules.process_turn(data, state)

	# The city falls: the siege is gone, but not because it was broken.
	state["settlements"]["epsilon"]["siege"] = null
	state["settlements"]["epsilon"]["owner"] = "blue"
	var treasury_before := int(state["factions"]["red"]["treasury"])
	state["turn"] = 4
	GuidedRules.process_turn(data, state)
	t.check_eq(state["guided"]["stages"]["relief"]["status"], "cooldown",
		"the stage lapses onto cooldown")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before,
		"a fallen city earns nothing")


func test_cooldown_recurrence(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	_install_stages(data, [
		_stage("debts", {"kind": "player_in_debt"},
			[{"kind": "treasury_at_least", "amount": 1000}],
			{"repeatable": true, "cooldown_turns": 6}),
	])
	state["factions"]["red"]["treasury"] = -500
	GuidedRules.process_turn(data, state)
	var inst: Dictionary = state["guided"]["stages"]["debts"]
	t.check_eq(inst["status"], "active", "debt raises the alarm")
	t.check_eq(int(inst["fired"]), 1, "first firing")

	state["factions"]["red"]["treasury"] = 1200
	state["turn"] = 1
	GuidedRules.process_turn(data, state)
	t.check_eq(inst["status"], "cooldown", "resolved and resting")

	state["factions"]["red"]["treasury"] = -500
	state["turn"] = 3
	GuidedRules.process_turn(data, state)
	t.check_eq(state["guided"]["stages"]["debts"]["status"], "cooldown",
		"the cooldown holds even though the condition is back")
	state["turn"] = 7
	GuidedRules.process_turn(data, state)
	var again: Dictionary = state["guided"]["stages"]["debts"]
	t.check_eq(again["status"], "active", "it re-arms after the cooldown")
	t.check_eq(int(again["fired"]), 2, "second firing counted")
	t.check_eq(int(again["started_turn"]), 7, "fresh instance clock")


## --- Rewards ---------------------------------------------------------------

func test_rewards_units_experience_and_boons(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	state["armies"][army_id]["units"][0]["experience"] = 8
	_install_stages(data, [
		_stage("jackpot", {"kind": "start"}, [{"kind": "set_taxes"}], {"reward": {
			"treasury": 500,
			"units": [{"template": "test_mob", "count": 2}],
			"experience": 2,
			"boon": {"recruit_xp": 2, "income_pct": 10.0, "movement": 0.5},
		}}),
	])
	var game := _game(data, state)
	GuidedRules.process_turn(data, state)
	game.set_tax_level("beta", "high")
	var treasury_before := int(state["factions"]["red"]["treasury"])
	GuidedRules.process_turn(data, state)

	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before + 500, "gold granted")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 2,
		"granted units muster in the capital")
	t.check_eq(int(state["armies"][army_id]["units"][0]["experience"]), 9,
		"field-army experience granted, capped at the maximum")
	var boons: Dictionary = state["factions"]["red"]["boons"]
	t.check_eq(int(boons["recruit_xp"]), 2, "recruit boon stored")

	# The three boon read paths.
	t.check(RecruitmentRules.queue_unit(data, state, "beta", "test_spears"), "recruit queued")
	RecruitmentRules.advance_queues(data, state, "beta")
	var garrison: Array = state["settlements"]["beta"]["garrison"]
	t.check_eq(int(garrison[garrison.size() - 1]["experience"]), 2,
		"recruits come out sharper with the boon")
	var with_income := float(EconomyRules.faction_turn_breakdown(data, state, "red", null)["income"])
	var kept_boons: Dictionary = state["factions"]["red"]["boons"]
	state["factions"]["red"].erase("boons")
	var without_income := float(EconomyRules.faction_turn_breakdown(data, state, "red", null)["income"])
	state["factions"]["red"]["boons"] = kept_boons
	t.check_near(with_income / without_income, 1.10, 0.001, "the income boon pays exactly its rate")
	MovementRules.reset_movement(data, state)
	t.check_near(float(state["armies"][army_id]["movement_left"]), 2.5, 0.001,
		"the movement boon stretches the march")


func test_reward_units_lost_with_the_capital(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	state["settlements"]["beta"]["owner"] = "blue"  # red's capital is lost
	_install_stages(data, [
		_stage("levy", {"kind": "start"}, [{"kind": "set_taxes"}],
			{"reward": {"units": [{"template": "test_mob", "count": 2}]}}),
	])
	var game := _game(data, state)
	GuidedRules.process_turn(data, state)
	game.set_tax_level("epsilon", "high")
	GuidedRules.process_turn(data, state)
	t.check_eq(state["guided"]["stages"]["levy"]["status"], "done", "the stage still completes")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 0,
		"granted units are silently lost without the capital (the senate rule)")


## --- Choke-point counters --------------------------------------------------

func test_battles_and_captures_count_at_the_choke_points(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(9)

	# An AI attacker loses to the player's stronger defender: a defensive win.
	var blue_mob := Fixtures.add_army(state, "blue", "gamma", ["test_mob"])
	var red_wall := Fixtures.add_army(state, "red", "gamma", ["test_spears", "test_spears"])
	CombatRules.attack_army(data, state, resolver, rng, blue_mob, red_wall)
	t.check_eq(int(state["guided"]["counters"].get("battles_won", 0)), 1,
		"defending the field counts")

	# An AI-vs-AI battle far away counts nothing.
	Fixtures.add_faction(state, "green", "delta")
	Fixtures.add_settlement(state, "delta", "green", 1000, {"tribal_government": 1})
	DiplomacyRules.set_stance(state, "green", "blue", "war")
	var green_army := Fixtures.add_army(state, "green", "delta", ["test_spears", "test_spears"])
	var blue_two := Fixtures.add_army(state, "blue", "delta", ["test_mob"])
	CombatRules.attack_army(data, state, resolver, rng, green_army, blue_two)
	t.check_eq(int(state["guided"]["counters"].get("battles_won", 0)), 1,
		"AI battles do not count for the trail")

	# A capture through the shared capture path counts; an AI capture does not.
	CombatRules.capture_settlement(data, state, rng, "alpha", "red", "occupy")
	t.check_eq(int(state["guided"]["counters"].get("regions_captured", 0)), 1, "player capture counts")
	CombatRules.capture_settlement(data, state, rng, "delta", "blue", "occupy")
	t.check_eq(int(state["guided"]["counters"].get("regions_captured", 0)), 1,
		"AI capture does not")


## --- Exploration -----------------------------------------------------------

func test_explore_site_semantics(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)  # deliberately NO guided key: sites stand alone
	_install_site(data, "gamma", [
		{"weight": 1, "text": "Coin.", "reward": {"treasury": 300}},
	])
	var red_army := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	var blue_army := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	MovementRules.reset_movement(data, state)
	var game := _game(data, state)

	t.check(game.explore_site(blue_army).is_empty(), "only the player explores")
	var treasury_before := int(state["factions"]["red"]["treasury"])
	var result := game.explore_site(red_army)
	t.check(not result.is_empty(), "the search succeeds")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before + 300, "the find pays")
	t.check_eq(float(state["armies"][red_army]["movement_left"]), 0.0,
		"searching spends the season's movement")
	t.check(state["sites_explored"].has("test_site_gamma"), "the site is spent")
	t.check(game.explore_site(red_army).is_empty(), "a spent site yields nothing more")

	# No movement, no search.
	_install_site(data, "delta", [{"weight": 1, "text": "More.", "reward": {"treasury": 100}}])
	state["armies"][red_army]["region"] = "delta"
	t.check(game.explore_site(red_army).is_empty(), "no movement left, no search")


func test_explore_units_join_and_overflow_to_capital(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_install_site(data, "gamma", [
		{"weight": 1, "text": "Soldiers.", "reward": {"units": [{"template": "test_mob", "count": 2}]}},
	])
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	var army: Dictionary = state["armies"][army_id]
	var cap := int(data.balance["recruitment"]["army_unit_cap"])
	while army["units"].size() < cap - 1:
		army["units"].append({"template": "test_mob", "experience": 0, "strength_pct": 100})
	MovementRules.reset_movement(data, state)
	var game := _game(data, state)

	game.explore_site(army_id)
	t.check_eq(army["units"].size(), cap, "found soldiers join up to the army cap")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 1,
		"the overflow musters in the capital instead")


func test_explore_is_deterministic(t) -> void:
	var data := Fixtures.data()
	_install_site(data, "gamma", [
		{"weight": 3, "text": "A little.", "reward": {"treasury": 100}},
		{"weight": 2, "text": "Some.", "reward": {"treasury": 300}},
		{"weight": 1, "text": "A lot.", "reward": {"treasury": 900}},
	])
	var first_state := Fixtures.state(data)
	var second_state := Fixtures.state(data)
	var results: Array = []
	for state in [first_state, second_state]:
		var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
		MovementRules.reset_movement(data, state)
		state["rng_state"] = "424242"
		var game := _game(data, state)
		results.append(game.explore_site(army_id))
	t.check_eq(JSON.stringify(results[0]), JSON.stringify(results[1]),
		"the same world state draws the same find")
	t.check_eq(JSON.stringify(JSON.parse_string(JSON.stringify(first_state))),
		JSON.stringify(JSON.parse_string(JSON.stringify(second_state))),
		"and leaves identical worlds behind")


## --- Overview --------------------------------------------------------------

func test_overview_shapes_and_capture_hint(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.enable_guided(state)
	_install_stages(data, [
		_stage("conquer", {"kind": "start"}, [{"kind": "capture_regions"}]),
	])
	GuidedRules.process_turn(data, state)
	var overview := GuidedRules.overview(data, state)
	t.check(overview["enabled"], "the trail reports itself on")
	t.check_eq(overview["active"].size(), 1, "one stage underway")
	var stage: Dictionary = overview["active"][0]
	t.check_eq(stage["id"], "conquer", "the right stage")
	t.check(not bool(stage["objectives"][0]["met"]), "objective honestly unmet")
	t.check_eq(stage["target_region"], "alpha",
		"an unmet capture objective suggests the nearest enemy settlement")

	state["guided"]["enabled"] = false
	t.check(not GuidedRules.overview(data, state)["enabled"], "a disabled trail reports off")


## --- Real data -------------------------------------------------------------

func test_real_campaign_trail_and_scripted_determinism(t) -> void:
	var off := Game.new_campaign("julii", 11, "medium", "long", false)
	t.check(not off.state["guided"]["enabled"], "the start-menu toggle reaches the state")
	for i in range(2):
		var report := off.end_turn()
		t.check(report["guided"].is_empty(), "a disabled trail stays silent")

	var states: Array = []
	for run in range(2):
		var game := Game.new_campaign("julii", 11)
		t.check(game.state["guided"]["enabled"], "the trail is on by default")
		game.end_turn()
		game.set_tax_level("etruria", "high")
		var raised := game.raise_army("umbria")
		t.check(raised != "", "the player can raise a field army (run %d)" % run)
		game.end_turn()
		var found := game.explore_site(raised)
		t.check(not found.is_empty(), "the julii reach their home site (run %d)" % run)
		game.end_turn()
		# Save, resume, and march both worlds one more turn in step.
		var resumed := Game.new()
		resumed.data = game.data
		resumed.resolver = AutoResolver.new()
		resumed.state = SaveGame.from_json(SaveGame.to_json(game.state))
		game.end_turn()
		resumed.end_turn()
		t.check_eq(_canonical(game.state), _canonical(resumed.state),
			"a mid-trail save marches in step (run %d)" % run)
		states.append(_canonical(game.state))
	t.check_eq(states[0], states[1], "two identically scripted campaigns are identical")

	var final_state = JSON.parse_string(states[0])
	t.check(int(final_state["guided"]["counters"].get("sites_explored", 0)) >= 1,
		"the exploration was counted")
	var done_stages := 0
	for stage_id in final_state["guided"]["stages"]:
		if final_state["guided"]["stages"][stage_id]["status"] == "done":
			done_stages += 1
	t.check(done_stages >= 1, "the trail is progressing (%d stages done)" % done_stages)


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))
