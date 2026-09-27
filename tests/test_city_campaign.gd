extends RefCounted
## Shared city/map calendar: season rules execute once and civic operations
## continue only after explicit activation. No elapsed time comes from a view.


func _game() -> Game:
	return Game.new_campaign("senate", 42, "medium", "long", false)


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))


func _ready_siege(game: Game, ready: bool = true) -> void:
	game.state["armies"]["city_campaign_enemy"] = {"owner": "gaul", "region": "latium",
		"units": [{"template": "tribal_warband", "strength_pct": 100, "experience": 0, "weapon": 0, "armor": 0}],
		"general": null, "movement_left": 0.0, "forced_march": false}
	DiplomacyRules.set_stance(game.state, "gaul", "senate", "war")
	game.state["settlements"]["latium"]["siege"] = {"besieger": "city_campaign_enemy", "turns": 0, "equipment_ready": ready}


func test_status_is_pure_and_activation_is_idempotent(t) -> void:
	var game := _game()
	var before := _canonical(game.state)
	var report := game.city_campaign_status("latium")
	t.check(not report["active"], "unvisited city does not run civic operations each season")
	t.check_eq(report["year"], -270, "city reads actual campaign year")
	t.check_eq(report["turns_per_year"], game.data.balance["time"]["turns_per_year"], "calendar comes from authored campaign balance")
	t.check_eq(_canonical(game.state), before, "calendar/history reads never activate or write state")
	t.check(game.city_campaign_enter("latium")["ok"], "explicit visit activates shared timeline")
	before = _canonical(game.state)
	game.city_campaign_enter("latium")
	t.check_eq(_canonical(game.state), before, "repeat map/city transitions cannot reset active timeline")
	t.check(game.city_campaign_status("latium")["history"].is_empty(), "entry does not invent a completed season")


func test_unactivated_campaign_keeps_existing_turn_behavior(t) -> void:
	var through_facade := _game()
	var original_engine := _game()
	through_facade.end_turn()
	TurnEngine.end_turn(original_engine.data, original_engine.state, original_engine.resolver)
	t.check_eq(_canonical(through_facade.state), _canonical(original_engine.state), "ordinary unvisited campaign remains equivalent to existing TurnEngine")
	t.check(through_facade.state["city_governance"].is_empty(), "no unvisited city costs or daily state created")


func test_map_and_city_advance_same_world_and_civic_jobs_once(t) -> void:
	var city := _game()
	var map := _game()
	for game in [city, map]:
		game.city_campaign_enter("latium")
		game.city_action("latium", "repair_streets")
		game.state["settlements"]["latium"]["recruitment_queue"] = [
			{"template": "roman_hastati", "turns_left": 1, "city_days_left": 3},
			{"template": "roman_hastati", "turns_left": 1}]
	var result := city.city_campaign_advance("latium")
	var map_report := map.end_turn()
	t.check(result["ok"], "one city season resolves")
	t.check_eq(result["seasons_advanced"], 1, "one explicit season is one campaign turn")
	t.check_eq(result["civic_days_advanced"], 3, "funded season resolves configured local operations")
	t.check_eq(_canonical(city.state), _canonical(map.state), "map and city use precisely the same shared season mechanism")
	var row: Dictionary = map_report["city_campaign"]["latium"]
	t.check_eq(row["completed_units"], ["roman_hastati", "roman_hastati"], "one civic and one seasonal job each finish exactly once")
	t.check(row["completed_projects"].has("repair_streets"), "daily civic project no longer stranded in seasonal play")
	t.check_eq(row["civic_day"], 4, "day ledger reflects three funded operations")
	t.check_eq(city.state["settlements"]["latium"]["recruitment_queue"], [], "finished jobs are consumed from their one shared queue")
	t.check_eq(city.city_campaign_status("latium")["history"].size(), 2, "first advance records initial and resulting season")


func test_pending_siege_and_battle_block_before_civic_spending(t) -> void:
	var game := _game()
	game.city_campaign_enter("latium")
	game.city_action("latium", "repair_streets")
	_ready_siege(game)
	var before := _canonical(game.state)
	t.check_eq(game.city_campaign_advance("latium")["reason"], "defense_pending", "prepared siege requires command")
	t.check_eq(game.end_turn()["reason"], "defense_pending", "map season has same defense preflight")
	t.check_eq(_canonical(game.state), before, "refused season cannot advance or charge civic operations")
	game.state["settlements"]["latium"]["siege"] = null
	game.city_battle_begin("latium", true)
	before = _canonical(game.state)
	t.check_eq(game.city_campaign_advance("latium")["reason"], "battle_active", "practice/reserved armies block seasonal advancement too")
	t.check_eq(_canonical(game.state), before, "hidden or paused battle cannot be bypassed from calendar")


func test_unfunded_civic_work_does_not_block_seasonal_income(t) -> void:
	var game := _game()
	game.city_campaign_enter("latium")
	game.state["factions"]["senate"]["treasury"] = 0
	var result := game.city_campaign_advance("latium")
	t.check(result["ok"], "seasonal economy still runs when city daily operating purse is empty")
	t.check_eq(result["civic_days_advanced"], 0, "unfunded local work does not run for free")
	var row: Dictionary = result["reports"][0]
	t.check_eq(row["unfunded_civic_days"], 3, "all skipped operations are reported")
	t.check_eq(row["civic_reason"], "insufficient_funds", "unfunded work has inspectable reason")
	t.check_eq(game.state["turn"], 1, "the normal campaign turn still advances exactly once")
	t.check_eq(row["civic_day"], 1, "no free city days occurred")


func test_existing_civic_day_is_not_replayed_by_city_entry(t) -> void:
	var game := _game()
	game.city_advance_day("latium")
	var day := int(game.city_status("latium")["day"])
	game.city_campaign_enter("latium")
	game.city_campaign_enter("latium")
	t.check_eq(game.city_status("latium")["day"], day, "activation does not replay the prior dawn")
	var result := game.city_campaign_advance("latium")
	t.check_eq(result["reports"][0]["civic_day"], day + 3, "season adds only its three new civic operations")


func test_batch_stops_for_visible_threat_and_live_decision(t) -> void:
	var game := _game()
	_ready_siege(game, false)
	var before := _canonical(game.state)
	t.check_eq(game.city_campaign_advance("latium", 2)["reason"], "siege_threat", "batch cannot skip a forming siege")
	t.check_eq(_canonical(game.state), before, "batch refusal happens before implicit activation or costs")
	game.state["settlements"]["latium"]["siege"] = null
	game.state["armies"].erase("city_campaign_enemy")
	DiplomacyRules.set_stance(game.state, "gaul", "senate", "neutral")
	game.state["pending_offers"].append({"id": "city_campaign_offer", "from": "gaul", "to": "senate", "stance": "", "give_payment": 0, "give_regions": []})
	before = _canonical(game.state)
	t.check_eq(game.city_campaign_advance("latium", 2)["reason"], "decision_pending", "year advance stops for a valid diplomatic decision")
	t.check_eq(_canonical(game.state), before, "pending decision is not silently expired by advancing")


func test_invalid_duration_loss_and_victory_are_atomic(t) -> void:
	var game := _game()
	var before := _canonical(game.state)
	for count in [0, -1, 5, 1000]:
		t.check_eq(game.city_campaign_advance("latium", count)["reason"], "invalid_duration", "requested timespan is explicitly bounded")
	t.check_eq(_canonical(game.state), before, "bad durations create no city record")
	game.city_campaign_enter("latium")
	game.state["settlements"]["latium"]["owner"] = "gaul"
	before = _canonical(game.state)
	t.check_eq(game.city_campaign_advance("latium")["reason"], "city_lost", "former owner cannot govern captured Roma")
	t.check(not game.city_campaign_status("latium")["can_advance"], "lost city disables season control")
	t.check_eq(_canonical(game.state), before, "loss refusal is atomic")
	game.state["settlements"]["latium"]["owner"] = "senate"
	game.state["winner"] = "senate"
	before = _canonical(game.state)
	t.check_eq(game.city_campaign_advance("latium")["reason"], "campaign_finished", "calendar honors existing campaign victory/time limit")
	t.check_eq(game.end_turn()["reason"], "campaign_finished", "map and city share the same activated campaign ending")
	t.check_eq(_canonical(game.state), before, "finished campaigns do not accrue extra civic benefits")


func test_city_campaign_save_resume_keeps_history_and_future_world(t) -> void:
	var live := _game()
	live.city_campaign_enter("latium")
	live.city_action("latium", "improve_barracks")
	live.city_campaign_advance("latium")
	var resumed := Game.new()
	resumed.data = live.data
	resumed.resolver = AutoResolver.new()
	resumed.state = SaveGame.from_json(SaveGame.to_json(live.state))
	t.check(not resumed.state.is_empty(), "activated city calendar survives save validation")
	if resumed.state.is_empty():
		return
	NewGame.ensure_state_keys(resumed.state, resumed.data)
	live.city_campaign_advance("latium")
	resumed.city_campaign_advance("latium")
	t.check_eq(_canonical(live.state), _canonical(resumed.state), "civic jobs, calendar, AI, history and RNG resume identically")
	var status := resumed.city_campaign_status("latium")
	status["history"][0]["population"] = 1
	t.check(resumed.state["city_campaign"]["latium"]["history"][0]["population"] != 1, "detached history cannot rewrite campaign through UI")


func test_old_save_migration_and_malformed_history_boundary(t) -> void:
	var game := _game()
	game.state.erase("city_campaign")
	var legacy := SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(legacy, game.data)
	t.check_eq(legacy["city_campaign"], {}, "legacy campaigns stay inactive on additive migration")
	game.city_campaign_enter("latium")
	game.city_campaign_advance("latium")
	for change in ["active", "history", "future", "duplicate", "nanlike", "unit", "year_zero"]:
		var bad := game.state.duplicate(true)
		var record: Dictionary = bad["city_campaign"]["latium"]
		match change:
			"active": record["active"] = "yes"
			"history": record["history"] = {}
			"future": record["history"][0]["turn"] = 9999
			"duplicate": record["history"][1]["turn"] = record["history"][0]["turn"]
			"nanlike": record["history"][0]["treasury"] = "broken"
			"unit": record["history"][0]["completed_units"] = [44]
			"year_zero": record["history"][0]["year"] = 0
		t.check(SaveGame.from_json(SaveGame.to_json(bad)).is_empty(), "invalid history rejected: " + change)


func test_history_retains_a_century_of_season_snapshots(t) -> void:
	## Retention/save fixture only: no century of AI play or fictitious fast-
	## forward implementation. Exercise dated history capacity directly.
	var game := _game()
	game.city_campaign_enter("latium")
	for turn in range(200):
		var before := CityCampaignRules._snapshot(game.data, game.state, "latium")
		game.state["turn"] = turn + 1
		game.state["year"] = -270 + int((turn + 1) / 2)
		game.state["season"] = "summer" if (turn + 1) % 2 == 0 else "winter"
		var report := {}
		CityCampaignRules.record_season(game.data, game.state, report,
			{"latium": {"before": before, "completed_units": []}})
	var history: Array = game.state["city_campaign"]["latium"]["history"]
	t.check_eq(history.size(), 200, "season history capacity supports a full century")
	t.check_eq(history.back()["year"], -170, "history uses real signed years")
	t.check(not SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(), "century-scale ledger remains save compatible")
