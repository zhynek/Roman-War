extends RefCounted
## Multi-turn march orders through the Game facade and the turn engine:
## orders persist across end turns, saves resume in lockstep, a hostile
## arrival halts the column without a shot, and armies from saves that
## predate the march keys still work.


func _fixture_game() -> Game:
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	game.resolver = AutoResolver.new()
	return game


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))


func test_march_order_completes_across_turns(t) -> void:
	var game := _fixture_game()
	var army_id := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(game.data, game.state)

	t.check(game.march_army(army_id, "eta"), "order accepted")
	t.check_eq(game.state["armies"][army_id]["region"], "zeta", "this turn's movement is spent at once")
	t.check_eq(game.state["armies"][army_id]["march_path"], ["eta"], "the rest is remembered")

	var report := game.end_turn()
	t.check_eq(game.state["armies"][army_id]["region"], "eta", "end turn walks the last leg")
	var arrived := false
	for march in report["marches"]:
		if march["army"] == army_id and march["arrived"]:
			arrived = true
	t.check(arrived, "arrival reported for the turn log")
	t.check(not game.state["armies"][army_id].has("march_path"), "order cleared on arrival")


func test_saved_march_resumes_in_lockstep(t) -> void:
	var game := _fixture_game()
	var army_id := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(game.data, game.state)
	game.march_army(army_id, "eta")

	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not resumed.state.is_empty(), "mid-march save parses back")

	game.end_turn()
	resumed.end_turn()
	t.check_eq(_canonical(game.state), _canonical(resumed.state), "the loaded march walks in lockstep")
	t.check_eq(resumed.state["armies"][army_id]["region"], "eta", "and reaches the same forest")


func test_march_halts_when_an_enemy_appears(t) -> void:
	var game := _fixture_game()
	var army_id := Fixtures.add_army(game.state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(game.data, game.state)
	game.state["armies"][army_id]["movement_left"] = 0.0
	t.check(game.march_army(army_id, "epsilon"), "order accepted even with nothing left to spend")
	t.check_eq(game.state["armies"][army_id]["region"], "gamma", "no points, no steps")

	# An enemy slips into the corridor before the column moves again.
	Fixtures.add_army(game.state, "blue", "delta", ["test_mob"])
	var stances_before: Dictionary = game.state["factions"]["red"]["diplomacy"].duplicate()
	var report := game.end_turn()
	t.check_eq(game.state["armies"][army_id]["region"], "gamma", "the march halts before contact")
	t.check(not game.state["armies"][army_id].has("march_path"), "the dead order is discarded")
	for other_faction in stances_before:
		t.check_eq(game.state["factions"]["red"]["diplomacy"][other_faction], stances_before[other_faction],
			"the halt changed no stance with " + String(other_faction))
	var halted := false
	for march in report["marches"]:
		if march["army"] == army_id and march["halted"]:
			halted = true
	t.check(halted, "the halt is reported for the turn log")


func test_manual_orders_supersede_a_march(t) -> void:
	var game := _fixture_game()
	var army_id := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(game.data, game.state)
	game.state["armies"][army_id]["movement_left"] = 0.0
	game.march_army(army_id, "eta")
	t.check(game.state["armies"][army_id].has("march_path"), "order stored")

	MovementRules.reset_movement(game.data, game.state)
	t.check(game.move_army(army_id, "gamma"), "a manual step still works")
	t.check(not game.state["armies"][army_id].has("march_path"), "and supersedes the standing march")

	t.check(not game.halt_march(army_id), "halting a marchless army is a no-op")


func test_old_save_shape_still_plays(t) -> void:
	var game := _fixture_game()
	var army_id := Fixtures.add_army(game.state, "red", "gamma", ["test_spears"])
	t.check(not game.state["armies"][army_id].has("march_path"), "fixture armies are old-shaped")
	var report := game.end_turn()
	t.check(report["marches"].is_empty(), "no orders, no march reports")
	t.check(game.state["armies"].has(army_id), "the army soldiers on")
	t.check_eq(int(game.state["turn"]), 1, "the world turned")
