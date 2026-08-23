extends RefCounted
## Movement points, terrain costs, hostile-region blocking, and fog of war on
## the synthetic fixture map.


func test_movement_costs_and_range(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	t.check(MovementRules.move_army(data, state, army_id, "delta"), "first step within budget")
	t.check(MovementRules.move_army(data, state, army_id, "epsilon"), "second step within budget")
	t.check(not MovementRules.move_army(data, state, army_id, "delta"), "movement points exhausted")


func test_forced_march_stretches_range(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	MovementRules.reset_movement(data, state)

	t.check(MovementRules.move_army(data, state, army_id, "delta"))
	t.check(MovementRules.move_army(data, state, army_id, "epsilon", true), "forced march stretches the budget")
	t.check(MovementRules.move_army(data, state, army_id, "delta", true), "three steps on two points, at a price")
	t.check(state["armies"][army_id]["forced_march"], "army marked fatigued")


func test_cannot_walk_into_enemy_settlement(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(not MovementRules.move_army(data, state, army_id, "alpha"),
		"hostile settlements demand a siege, not a stroll")


func test_siege_and_starve(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(4)
	var army_id := Fixtures.add_army(state, "red", "beta",
		["test_spears", "test_spears", "test_spears", "test_spears"])
	MovementRules.reset_movement(data, state)

	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege begins")
	t.check_eq(state["armies"][army_id]["region"], "alpha", "besieger camps at the walls")
	t.check(SiegeRules.assault(data, state, rng, resolver, army_id, "alpha").is_empty(),
		"no assault without equipment")

	var captured := false
	for i in range(12):
		for event in SiegeRules.advance_sieges(data, state, rng, resolver):
			if event["result"].get("captured", false):
				CombatRules.capture_settlement(data, state, rng, event["region"],
					event["result"]["capture_pending_owner"], "occupy")
				captured = true
		if captured or not state["armies"].has(army_id):
			break
	if state["armies"].has(army_id):
		t.check(captured and state["settlements"]["alpha"]["owner"] == "red",
			"starving garrison falls to the surviving besieger")


func test_fog_on_fixture_map(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var visible := VisibilityRules.visible_regions(data, state, "red")
	t.check(visible.has("beta") and visible.has("epsilon"), "own regions visible")
	t.check(visible.has("alpha") and visible.has("gamma") and visible.has("delta"),
		"one-hop scouting from holdings")

	var blue_visible := VisibilityRules.visible_regions(data, state, "blue")
	t.check(not blue_visible.has("gamma"), "blue cannot see two hops out")
