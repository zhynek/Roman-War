extends RefCounted


func _game() -> Game:
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)
	game.resolver = AutoResolver.new()
	return game


func test_march_quote_is_read_only_and_seasons_match_execution(t) -> void:
	var game := _game()
	var army := Fixtures.add_army(game.state, "red", "alpha", ["test_spears"])
	var before := game.state.duplicate(true)
	var quote := game.army_order_preview(army, "epsilon")
	t.check_eq(game.state, before, "hover never mutates the world or RNG")
	t.check_eq(quote["action"], "march", "open land is a march")
	t.check_eq(quote["turns"], 2, "the road takes two seasons")
	t.check_eq(quote["legs"].map(func(leg): return leg["turn"]), [1, 1, 2, 2], "season chips show exactly when each leg can be walked")
	var result := game.march_army(army, "epsilon")
	t.check_eq(result["traversed"], ["beta", "gamma"], "animation receives only the steps actually taken")
	t.check_eq(game.state["armies"][army]["march_path"], ["delta", "epsilon"], "the rest is still queued")


func test_exhausted_army_can_queue_but_cannot_attack(t) -> void:
	var game := _game()
	var army := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	game.state["armies"][army]["movement_left"] = 0.0
	var quote := game.army_order_preview(army, "gamma")
	t.check_eq(quote["reason"], "", "a march can wait for the next season")
	t.check_eq(quote["legs"][0]["turn"], 2, "the next season is labelled")
	var attack := game.army_order_preview(army, "alpha")
	t.check_eq(attack["action"], "siege", "nearby hostile walls are identified")
	t.check_eq(attack["reason"], "no_movement", "but cannot be invested without movement")


func test_neighbouring_battles_and_sieges_are_explicit(t) -> void:
	var game := _game()
	var army := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	var enemy := Fixtures.add_army(game.state, "blue", "alpha", ["test_mob"])
	var preview := game.army_order_preview(army, "alpha")
	t.check_eq(preview["action"], "attack", "a field army is fought before the walls")
	t.check_eq(preview["defender"], enemy, "the exact enemy is quoted")
	game.state["armies"].erase(enemy)
	t.check_eq(game.army_order_preview(army, "alpha")["action"], "siege", "unguarded walls offer a siege")
	t.check(game.besiege(army, "alpha"), "the quoted siege works")
	MovementRules.reset_movement(game.data, game.state)
	t.check_eq(game.army_order_preview(army, "alpha")["reason"], "engines", "unready engines explain a disabled assault")
	game.state["settlements"]["alpha"]["siege"]["equipment_ready"] = true
	t.check_eq(game.army_order_preview(army, "alpha")["action"], "assault", "a ready siege offers assault in place")
	t.check_eq(game.army_order_preview(army, "alpha")["reason"], "", "the assault is available")


func test_forced_preview_warns_and_preserves_fatigue(t) -> void:
	var game := _game()
	var army := Fixtures.add_army(game.state, "red", "alpha", ["test_spears"])
	var preview := game.army_order_preview(army, "epsilon", true)
	t.check(preview["forced"], "forced intent is retained")
	t.check_eq(preview["turns"], 1, "forced march reaches in one season")
	var result := game.march_army(army, "epsilon", true)
	t.check_eq(result["traversed"], preview["path"], "execution follows the quoted route")
	t.check(game.state["armies"][army]["forced_march"], "the men actually pay the fatigue cost")


func test_unseen_roads_and_enemies_do_not_change_orders(t) -> void:
	var game := _game()
	var army := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	var seen := {"beta": true}
	var before := MapOrderRules.preview(game.data, game.state, army, "alpha", false, seen)
	Fixtures.add_army(game.state, "blue", "alpha", ["test_mob"])
	game.data.chains["hidden_roads"] = {"id": "hidden_roads", "kind": "roads", "levels": [{"effects": {"road_level": 3}}]}
	game.state["settlements"]["alpha"]["buildings"]["hidden_roads"] = 1
	var after := MapOrderRules.preview(game.data, game.state, army, "alpha", false, seen)
	t.check_eq(after, before, "hidden armies, owners and roads cannot steer a preview")
	t.check(after["uncertain"], "the player is told the route is unscouted")


func test_foreign_orders_cannot_be_cancelled_or_queried(t) -> void:
	var game := _game()
	var enemy := Fixtures.add_army(game.state, "blue", "alpha", ["test_mob"])
	game.state["armies"][enemy]["march_path"] = ["zeta"]
	game.state["armies"][enemy]["march_forced"] = false
	var before := game.state.duplicate(true)
	t.check(not game.move_army(enemy, "zeta"), "foreign move is refused")
	t.check(not game.halt_march(enemy), "foreign halt is refused")
	t.check_eq(game.army_reachable(enemy), {}, "foreign reach is private")
	t.check_eq(game.army_path_preview(enemy, "zeta"), {}, "foreign route is private")
	t.check_eq(game.army_order_preview(enemy, "zeta"), {}, "foreign command is private")
	t.check_eq(game.state, before, "refused orders do not erase the enemy's march")


func test_withdrawing_quotes_the_siege_it_will_lift(t) -> void:
	var game := _game()
	var army := Fixtures.add_army(game.state, "red", "beta", ["test_spears"])
	t.check(game.besiege(army, "alpha"), "establish a siege")
	MovementRules.reset_movement(game.data, game.state)
	var quote := game.army_order_preview(army, "beta")
	t.check_eq(quote["action"], "withdraw", "leaving a siege is clearly a withdrawal")
	t.check_eq(quote["path"], ["beta"], "the direct withdrawal route is quoted")
	t.check(game.move_army(army, "beta"), "withdrawal is legal")
	t.check_eq(game.state["settlements"]["alpha"]["siege"], null, "withdrawal lifts the siege")


func test_saved_queue_preview_does_not_replan_the_road(t) -> void:
	var game := _game()
	var army := Fixtures.add_army(game.state, "red", "alpha", ["test_spears"])
	game.state["armies"][army]["march_path"] = ["zeta", "eta", "epsilon"]
	game.state["armies"][army]["march_forced"] = false
	var quote := game.queued_march_preview(army)
	t.check_eq(quote["path"], ["zeta", "eta", "epsilon"], "a retained route is the one that will execute")
	t.check_eq(game.army_order_preview(army, "epsilon")["path"], ["beta", "gamma", "delta", "epsilon"], "new orders can choose a different road")
	var before := game.state.duplicate(true)
	game.queued_march_preview(army)
	t.check_eq(game.state, before, "showing a saved order never changes it")
