extends RefCounted
## Protocol acceptance: commands, pure previews, save continuation and commit.


func _game() -> Game:
	return Game.new_campaign("senate", 42, "medium", "long", false)


func _campaign_snapshot(game: Game) -> String:
	var copy: Dictionary = game.state.duplicate(true)
	copy.erase("city_battles")
	return JSON.stringify(JSON.parse_string(JSON.stringify(copy)))


func _siege(game: Game, template: String = "tribal_warband", cards: int = 4) -> String:
	var units: Array = []
	for index in range(cards):
		units.append(template)
	var army := Fixtures.add_army(game.state, "gaul", "latium", units)
	DiplomacyRules.set_stance(game.state, "gaul", "senate", "war")
	game.state["settlements"]["latium"]["siege"] = {"besieger": army, "turns": 2, "equipment_ready": true}
	return army


func _finish(game: Game) -> void:
	for tick in range(int(CityBattleSim.rules(game.data)["maximum_ms"])/int(CityBattleSim.rules(game.data)["tick_ms"]) + 1):
		if game.city_battle_status("latium")["phase"] == "finished":
			break
		game.city_battle_step("latium")


func test_practice_isolated_from_campaign_and_status_aliases(t) -> void:
	var game := _game()
	var before := _campaign_snapshot(game)
	t.check(game.city_battle_begin("latium", true)["ok"], "owned Roma opens a practice defense")
	var report := game.city_battle_status("latium")
	report["formations"][0]["unit"]["strength_pct"] = 0
	t.check_eq(game.city_battle_status("latium")["formations"][0]["unit"]["strength_pct"], 100, "reports have no writable state aliases")
	t.check(game.city_battle_start("latium")["ok"], "explicit start leaves deployment")
	_finish(game)
	t.check_eq(game.city_battle_status("latium")["phase"], "finished", "fight reaches bounded terminal state")
	t.check_eq(_campaign_snapshot(game), before, "practice never changes any campaign state including RNG, garrison, treasury, ownership or chronicle")
	t.check(game.city_battle_close("latium")["ok"], "close removes completed practice")
	t.check_eq(_campaign_snapshot(game), before, "closing has no campaign effects")


func test_deployment_orders_and_commands_are_atomic(t) -> void:
	var game := _game()
	t.check(game.city_battle_begin("latium", true)["ok"], "practice begins")
	var before := JSON.stringify(game.state)
	for reply in [game.city_battle_step("latium"), game.city_battle_order("latium", "attacker_0", "forum"),
		game.city_battle_order("latium", "defender_0", "approach"), game.city_battle_order("latium", "defender_0", "void"),
		game.city_battle_begin("latium", true)]:
		t.check(not reply["ok"], "invalid command rejected")
	t.check_eq(JSON.stringify(game.state), before, "rejected commands do not partly alter deployment")
	t.check(game.city_battle_order("latium", "defender_0", "gate_street")["ok"], "actual garrison can deploy near gate")
	var defender: Dictionary = game.city_battle_status("latium")["formations"].filter(func(f): return f["id"] == "defender_0")[0]
	t.check_eq(defender["node"], "gate_street", "deployment move is explicit and immediate")
	t.check_eq(game.city_battle_status("latium")["tick"], 0, "deployment never advances time")


func test_gate_and_casualties_advance_only_on_explicit_step(t) -> void:
	var game := _game()
	game.city_battle_begin("latium", true)
	var original := JSON.stringify(game.state)
	for repeat in range(8):
		game.city_battle_status("latium")
		game.city_status("latium")
	t.check_eq(JSON.stringify(game.state), original, "battle and civic reports cannot advance simulation")
	game.city_battle_start("latium")
	game.city_battle_step("latium")
	var report := game.city_battle_status("latium")
	t.check_eq(report["tick"], 1, "exactly one tick per step")
	t.check(int(report["gate_integrity"]) < int(game.data.balance["city_battle"]["gate_integrity"]), "attacking formations breach the gate")
	for formation in report["formations"]:
		t.check_eq(formation["unit"]["strength_pct"], formation["initial_strength"], "no contact means no unexplained casualties")


func test_active_fight_locks_city_army_and_season_commands(t) -> void:
	var game := _game()
	game.city_battle_begin("latium", true)
	var before := JSON.stringify(game.state)
	t.check(not game.city_action("latium", "grain_relief"), "civic spending waits")
	t.check(not RomaCityRules.advance_day(game.data, game.state, "latium"), "direct civic day waits")
	t.check(not game.city_advance_day("latium"), "facade civic day waits")
	t.check_eq(game.retrain_garrison("latium"), 0, "cannot retrain reserved defenders")
	t.check(not game.raise_units("latium", [0])["ok"], "cannot remove reserved garrison")
	t.check(not game.disband_unit("garrison:latium", 0)["ok"], "cannot disband reserved garrison")
	t.check(not game.end_turn()["ok"], "no campaign season during deployment or fighting")
	t.check(not game.set_stance("gaul", "peace"), "battle diplomacy waits")
	t.check_eq(JSON.stringify(game.state), before, "all refusals preserve campaign and tactical state")
	t.check(not game.city_status("latium")["can_advance"], "city preview reflects battle lock")


func test_save_and_resume_produce_identical_tactical_result(t) -> void:
	var game := _game()
	game.city_battle_begin("latium", true)
	game.city_battle_order("latium", "defender_0", "gate_street")
	game.city_battle_start("latium")
	for tick in range(5):
		game.city_battle_step("latium")
	var loaded := Game.new()
	loaded.data = game.data
	loaded.resolver = AutoResolver.new()
	loaded.state = SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not loaded.state.is_empty(), "active tactical session passes save boundary")
	if loaded.state.is_empty():
		return
	_finish(game)
	_finish(loaded)
	t.check_eq(JSON.stringify(JSON.parse_string(JSON.stringify(game.state))), JSON.stringify(JSON.parse_string(JSON.stringify(loaded.state))), "save continuation replays formations, gate and outcome exactly")


func test_real_defense_commits_once_through_siege_aftermath(t) -> void:
	var game := _game()
	var army := _siege(game, "tribal_warband", 1)
	var garrison_before: Array = game.state["settlements"]["latium"]["garrison"].duplicate(true)
	var wins := int(game.state["factions"]["senate"]["war_record"]["battles_won"])
	t.check(game.city_battle_begin("latium", false)["ok"], "ready real hostile siege opens defense")
	game.city_battle_start("latium")
	game.city_battle_step("latium")
	t.check_eq(game.state["settlements"]["latium"]["garrison"], garrison_before, "intermediate ticks keep campaign troops reserved")
	t.check(not game.city_battle_close("latium")["ok"], "cannot abandon a live real assault to erase casualties")
	_finish(game)
	var report := game.city_battle_status("latium")
	t.check_eq(report["result"]["winner"], "defender", "strong garrison repels weak assault")
	t.check(report["committed"], "real result commits at terminal tick")
	t.check_eq(game.state["settlements"]["latium"]["siege"], null, "existing siege aftermath lifts repulsed siege")
	t.check_eq(game.state["factions"]["senate"]["war_record"]["battles_won"], wins + 1, "existing battle ledger records one victory")
	t.check(not game.state["armies"].has(army) or int(game.state["armies"][army]["units"][0]["strength_pct"]) < 100, "surviving attackers retain tactical losses")
	var after := JSON.stringify(game.state)
	t.check(not game.city_battle_step("latium")["ok"], "finished battle cannot resolve twice")
	t.check_eq(JSON.stringify(game.state), after, "repeated terminal command cannot duplicate losses or rewards")
	t.check(not SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(), "committed result remains loadable")


func test_city_loss_uses_capture_and_enemy_garrison_aftermath(t) -> void:
	var game := _game()
	game.state["settlements"]["latium"]["garrison"] = [{"template": "roman_town_watch", "experience": 0, "strength_pct": 10, "weapon": 0, "armor": 0}]
	_siege(game, "gallic_long_swords", 4)
	t.check(game.city_battle_begin("latium", false)["ok"], "weak defenders may still command a real battle")
	game.city_battle_start("latium")
	_finish(game)
	var report := game.city_battle_status("latium")
	t.check_eq(report["result"]["winner"], "attacker", "overwhelming assault takes the city")
	t.check_eq(game.state["settlements"]["latium"]["owner"], "gaul", "capture changes campaign ownership")
	t.check(report["result"].get("captured", false), "standard siege result exposes capture")
	t.check(not game.state["settlements"]["latium"]["garrison"].is_empty(), "AI leaves its ordinary occupying garrison")
	t.check(game.city_battle_close("latium")["ok"], "losing city does not trap finished result")


func test_stale_source_does_not_overwrite_campaign_troops(t) -> void:
	var game := _game()
	_siege(game)
	game.city_battle_begin("latium", false)
	game.city_battle_start("latium")
	game.state["settlements"]["latium"]["garrison"][0]["strength_pct"] = 22
	var before := JSON.stringify(game.state)
	t.check_eq(game.city_battle_step("latium")["reason"], "stale_battle", "out-of-band mutation invalidates snapshot")
	t.check_eq(JSON.stringify(game.state), before, "stale commit cannot replace newer troops")
	t.check(game.city_battle_close("latium")["ok"], "invalid source can be discarded safely")


func test_old_saves_migrate_and_malformed_sessions_reject(t) -> void:
	var game := _game()
	game.state.erase("city_battles")
	var legacy := SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(legacy, game.data)
	t.check_eq(legacy.get("city_battles"), {}, "pre-tactical saves migrate additively")
	game.city_battle_begin("latium", true)
	for kind in ["formations", "side", "node", "strength", "phase", "context", "duplicate", "committed", "source"]:
		var bad := game.state.duplicate(true)
		var battle: Dictionary = bad["city_battles"]["latium"]
		match kind:
			"formations": battle["formations"] = "broken"
			"side": battle["formations"][0]["side"] = "foreign"
			"node": battle["formations"][0]["node"] = "void"
			"strength": battle["formations"][0]["unit"]["strength_pct"] = 101
			"phase": battle["phase"] = "timer"
			"context": battle["context"]["attacker_mods"] = {"class_stats": "broken"}
			"duplicate": battle["formations"][1]["id"] = battle["formations"][0]["id"]
			"committed": battle["committed"] = true
			"source": battle["source"] = "[]"
		t.check(SaveGame.from_json(SaveGame.to_json(bad)).is_empty(), "reject malformed session: " + kind)


func test_actual_defense_requires_ready_hostility_and_correct_owner(t) -> void:
	var game := _game()
	var before := JSON.stringify(game.state)
	t.check_eq(game.city_battle_begin("latium", false)["reason"], "not_besieged", "cannot fabricate campaign attackers")
	t.check(not game.city_battle_begin("campania", true)["ok"], "unsupported city cannot invent geometry")
	t.check_eq(JSON.stringify(game.state), before, "invalid beginnings do not create records")
	_siege(game)
	game.state["settlements"]["latium"]["siege"]["equipment_ready"] = false
	t.check_eq(game.city_battle_begin("latium", false)["reason"], "equipment_unready", "real assault needs existing siege engines")
	game.state["settlements"]["latium"]["siege"]["equipment_ready"] = true
	t.check(CityBattleRules.pending_defense(game.data, game.state, "latium"), "ready siege pauses campaign for manual defense")
	t.check_eq(game.end_turn()["reason"], "defense_pending", "cannot skip pending city assault by advancing another season")


func test_deployment_choice_changes_contact_and_losses(t) -> void:
	var forward := _game()
	var reserve := _game()
	forward.city_battle_begin("latium", true)
	reserve.city_battle_begin("latium", true)
	for formation in forward.city_battle_status("latium")["formations"]:
		if formation["side"] == "defender":
			forward.city_battle_order("latium", formation["id"], "gate_street")
	for formation in reserve.city_battle_status("latium")["formations"]:
		if formation["side"] == "defender":
			reserve.city_battle_order("latium", formation["id"], "forum")
	forward.city_battle_start("latium")
	reserve.city_battle_start("latium")
	for tick in range(400):
		forward.city_battle_step("latium")
		reserve.city_battle_step("latium")
	var forward_report := forward.city_battle_status("latium")
	var reserve_report := reserve.city_battle_status("latium")
	var forward_strength := 0
	var reserve_strength := 0
	for formation in forward_report["formations"]:
		forward_strength += int(formation["unit"]["strength_pct"])
	for formation in reserve_report["formations"]:
		reserve_strength += int(formation["unit"]["strength_pct"])
	t.check(forward_strength != reserve_strength, "holding the gate and defending the forum create different engagements, not cosmetic deployment")
	t.check_eq(_campaign_snapshot(forward), _campaign_snapshot(reserve), "tactical choices in practice change only the practice battle")


func test_simultaneous_damage_does_not_give_first_formation_free_survival(t) -> void:
	var game := _game()
	game.data.roma_city["battle"]["practice_attackers"] = ["tribal_warband"]
	CityBattleSim.rules(game.data)["base_damage_per_second"] = 500000
	game.state["settlements"]["latium"]["garrison"] = [{"template": "tribal_warband", "experience": 0, "strength_pct": 100}]
	game.city_battle_begin("latium", true)
	game.city_battle_order("latium", "defender_0", "gate_street")
	game.city_battle_start("latium")
	_finish(game)
	var report := game.city_battle_status("latium")
	t.check_eq(report["formations"][0]["unit"]["strength_pct"], 0, "attacker received defender's damage on lethal simultaneous tick")
	t.check_eq(report["formations"][1]["unit"]["strength_pct"], 0, "defender received attacker's damage on the same tick")


func test_real_battle_save_replay_matches_aftermath_and_rng(t) -> void:
	var live := _game()
	_siege(live, "tribal_warband", 1)
	live.city_battle_begin("latium", false)
	live.city_battle_start("latium")
	live.city_battle_step("latium")
	var resumed := Game.new()
	resumed.data = live.data
	resumed.resolver = AutoResolver.new()
	resumed.state = SaveGame.from_json(SaveGame.to_json(live.state))
	t.check(not resumed.state.is_empty(), "real reserved armies and modifiers are saveable")
	if resumed.state.is_empty():
		return
	NewGame.ensure_state_keys(resumed.state, resumed.data)
	_finish(live)
	_finish(resumed)
	t.check_eq(JSON.stringify(JSON.parse_string(JSON.stringify(live.state))), JSON.stringify(JSON.parse_string(JSON.stringify(resumed.state))), "real tactical casualties, ledger, aftermath and RNG replay exactly")


func test_changed_or_unknown_content_reports_stale_and_can_discard(t) -> void:
	var game := _game()
	game.city_battle_begin("latium", true)
	game.data.units.erase(game.city_battle_status("latium")["formations"][0]["template"])
	t.check_eq(game.city_battle_status("latium")["reason"], "stale_battle", "removed content exposes a recoverable stale reason")
	t.check_eq(game.city_battle_start("latium")["reason"], "stale_battle", "unknown template never reaches tactical array indexing")
	t.check(game.city_battle_close("latium")["ok"], "stale save can be discarded")


func test_flank_fire_does_not_count_as_holding_forum(t) -> void:
	var game := _game()
	CityBattleSim.rules(game.data)["base_damage_per_second"] = 1
	game.city_battle_begin("latium", true)
	for formation in game.city_battle_status("latium")["formations"]:
		if formation["side"] == "defender":
			t.check(game.city_battle_command("latium", [formation["id"]], "move", [-6000,-4000])["ok"], "reserve deploys away from objective")
	game.city_battle_start("latium")
	_finish(game)
	var report := game.city_battle_status("latium")
	t.check_eq(report["result"]["cause"], "forum_captured", "unoccupied central lane allows attackers to take the forum despite adjacent flank troops")
	t.check(report["formations"].any(func(f): return f["side"] == "defender" and int(f["unit"]["strength_pct"]) > 0), "objective loss is distinct from annihilating every defender")
