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

	t.check(MovementRules.move_army(data, state, army_id, "delta"), "first step within budget")
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


func test_attack_needs_movement_and_ends_the_turn(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(3)
	var attacker := Fixtures.add_army(state, "red", "beta",
		["test_spears", "test_spears", "test_spears", "test_spears"])
	var defender := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	state["armies"][attacker]["movement_left"] = 0.0
	t.check(CombatRules.attack_army(data, state, resolver, rng, attacker, defender).is_empty(),
		"an army that has marched itself out cannot attack")
	state["armies"][attacker]["movement_left"] = 2.0
	var result := CombatRules.attack_army(data, state, resolver, rng, attacker, defender)
	t.check(not result.is_empty(), "with movement the attack resolves")
	t.check_near(float(state["armies"][attacker]["movement_left"]), 0.0, 0.0001,
		"a battle takes the rest of the season, won or lost")
	var second := Fixtures.add_army(state, "blue", "beta", ["test_mob"])
	t.check(CombatRules.attack_army(data, state, resolver, rng, attacker, second).is_empty(),
		"no army fights twice in one turn")


func test_siege_costs_movement_and_respects_relief_armies(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	state["armies"][army_id]["movement_left"] = 0.0
	t.check(not SiegeRules.begin_siege(data, state, army_id, "alpha"), "no movement, no siege — never a free hop")
	MovementRules.reset_movement(data, state)
	var relief := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	t.check(not SiegeRules.begin_siege(data, state, army_id, "alpha"), "a relieving army must be beaten first")
	state["armies"].erase(relief)
	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege laid once the road is clear")
	t.check_near(float(state["armies"][army_id]["movement_left"]), 0.0, 0.0001, "investing takes the turn")

	# Marching away lifts the siege at once, not at the end of the turn.
	MovementRules.reset_movement(data, state)
	t.check(MovementRules.move_army(data, state, army_id, "beta"), "the besieger marches off")
	t.check(state["settlements"]["alpha"]["siege"] == null, "the siege is released immediately")


func test_fog_on_fixture_map(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var visible := VisibilityRules.visible_regions(data, state, "red")
	t.check(visible.has("beta") and visible.has("epsilon"), "own regions visible")
	t.check(visible.has("alpha") and visible.has("gamma") and visible.has("delta"),
		"one-hop scouting from holdings")

	var blue_visible := VisibilityRules.visible_regions(data, state, "blue")
	t.check(not blue_visible.has("gamma"), "blue cannot see two hops out")
