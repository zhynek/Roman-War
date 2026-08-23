extends RefCounted
## War declaration, hostile acts as declarations, sea transport, mercenary
## hiring, and event happiness — the systems added by the first review round.


func test_declare_war_is_symmetric(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "alliance")
	t.check_eq(DiplomacyRules.stance_between(state, "blue", "red"), "alliance", "stances are symmetric")
	t.check(DiplomacyRules.declare_war(data, state, "red", "blue"), "war can be declared")
	t.check(DiplomacyRules.at_war(state, "blue", "red"), "war is mutual")


func test_attacking_declares_war(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(6)
	DiplomacyRules.set_stance(state, "red", "blue", "alliance")

	var attacker_id := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	var defender_id := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	var result := CombatRules.attack_army(data, state, resolver, rng, attacker_id, defender_id)
	t.check(not result.is_empty(), "the attack resolves")
	t.check(DiplomacyRules.at_war(state, "red", "blue"), "betrayal ends the alliance in war")


func test_cannot_attack_own_faction(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(6)
	var first := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	var second := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	t.check(CombatRules.attack_army(data, state, resolver, rng, first, second).is_empty(),
		"no fratricide")


func test_besieging_declares_war(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	DiplomacyRules.set_stance(state, "red", "blue", "trade")
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege of a trade partner allowed")
	t.check(DiplomacyRules.at_war(state, "red", "blue"), "and it means war")


func test_sea_move(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# epsilon and alpha share test_sea; alpha is hostile (blue at war) so it is
	# closed, but after peace the crossing opens.
	var army_id := Fixtures.add_army(state, "red", "epsilon", ["test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(not MovementRules.sea_move_army(data, state, army_id, "alpha"), "no landing on a war shore")
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	t.check(MovementRules.sea_move_army(data, state, army_id, "alpha"), "peaceful crossing works")
	t.check_eq(state["armies"][army_id]["region"], "alpha", "army crossed the sea")
	t.check_near(float(state["armies"][army_id]["movement_left"]), 0.0, 0.001, "crossing takes the whole turn")
	t.check(not MovementRules.sea_move_army(data, state, army_id, "epsilon"), "no second crossing this turn")


func test_mercenary_hiring(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	var offers := MercenaryRules.available(data, state, "gamma")
	t.check_eq(offers.size(), 1, "one offer in the pool")
	t.check_eq(int(offers[0]["cost"]), 750, "cost carries the multiplier (500 x 1.5)")

	var treasury_before := int(state["factions"]["red"]["treasury"])
	t.check(MercenaryRules.hire(data, state, army_id, "test_merc"), "hire accepted")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before - 750, "purse paid")
	t.check_eq(state["armies"][army_id]["units"].size(), 2, "sellswords join the army")
	t.check(not MercenaryRules.hire(data, state, army_id, "test_merc"), "pool exhausted")

	MercenaryRules.replenish(data, state)
	MercenaryRules.replenish(data, state)
	t.check(MercenaryRules.hire(data, state, army_id, "test_merc"), "pool refills over the turns")


func test_event_happiness_factor(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["event_happiness"] = {"value": 5.0, "turns": 2}
	var by_label := {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("events", 0.0), 5.0, 0.001, "event happiness reaches the breakdown")

	EventRules.tick_event_happiness(state)
	EventRules.tick_event_happiness(state)
	t.check(state["event_happiness"] == null, "the mood passes")
