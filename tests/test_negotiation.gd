extends RefCounted
## Phase 5 negotiation: attitude breakdowns, offers, and their consequences.


func _world() -> Array:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	return [data, state]


func test_attitude_breakdown_shape(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var factors := NegotiationRules.attitude_breakdown(data, state, "red", "blue")
	t.check(factors.size() >= 2, "attitude is a named factor list")
	var labels: Array = []
	for factor in factors:
		labels.append(factor["label"])
	t.check(labels.has("at_war"), "the war weighs on them")
	t.check(labels.has("foreign_ways"), "culture difference counts")
	var total := NegotiationRules.attitude_total(data, state, "red", "blue")
	t.check(total < -50.0, "an enemy at war regards us hostilely (%f)" % total)


func test_trade_needs_goodwill_and_peace(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	t.check(not NegotiationRules.evaluate(data, state, "red", "blue", {"kind": "trade"})["accept"],
		"no trade while at war")
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	# Neutral, different culture, border friction: attitude below zero — refused.
	var cold := NegotiationRules.evaluate(data, state, "red", "blue", {"kind": "trade"})
	t.check(not cold["accept"], "cold neighbors refuse open markets")
	# Sweetened with silver it clears the bar.
	state["factions"]["red"]["treasury"] = 10000
	var sweet := NegotiationRules.execute(data, state, "red", "blue", {"kind": "trade", "payment": 4000})
	t.check(sweet["accept"], "silver opens markets: %s" % sweet["reason"])
	t.check_eq(DiplomacyRules.stance_between(state, "red", "blue"), "trade", "stance updated")
	t.check_eq(int(state["factions"]["red"]["treasury"]), 6000, "the sweetener is paid")


func test_gift_and_decay(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	state["factions"]["red"]["treasury"] = 10000
	var before := NegotiationRules.attitude_total(data, state, "red", "blue")
	var verdict := NegotiationRules.execute(data, state, "red", "blue", {"kind": "gift", "payment": 2000})
	t.check(verdict["accept"], "gifts are never refused")
	var after := NegotiationRules.attitude_total(data, state, "red", "blue")
	t.check_near(after - before, 12.0, 0.01, "2000 denarii buy 12 points of goodwill")
	NegotiationRules.decay_turn(data, state)
	var decayed := NegotiationRules.attitude_total(data, state, "red", "blue")
	t.check_near(after - decayed, 1.0, 0.01, "deeds fade a point a turn")


func test_peace_with_a_losing_enemy(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	# Red fields a strong army; blue has nothing. Blue is losing badly and
	# takes the peace regardless of attitude.
	Fixtures.add_army(state, "red", "beta", ["test_elites", "test_elites", "test_elites"])
	var verdict := NegotiationRules.execute(data, state, "red", "blue", {"kind": "peace"})
	t.check(verdict["accept"], "a beaten enemy takes the peace: %s" % verdict["reason"])
	t.check(not DiplomacyRules.at_war(state, "red", "blue"), "the war is over")


func test_tribute_respects_fear(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	state["factions"]["blue"]["treasury"] = 5000
	# Without overwhelming strength the demand is laughed off — and remembered.
	var refused := NegotiationRules.execute(data, state, "red", "blue", {"kind": "demand_tribute"})
	t.check(not refused["accept"], "no fear, no tribute")
	t.check(NegotiationRules.stored_attitude(state, "blue", "red") < 0.0,
		"the insult is remembered")
	# With an army at their throat, they pay.
	Fixtures.add_army(state, "red", "beta", ["test_elites", "test_elites", "test_elites", "test_elites"])
	var red_before := int(state["factions"]["red"]["treasury"])
	var paid := NegotiationRules.execute(data, state, "red", "blue", {"kind": "demand_tribute"})
	t.check(paid["accept"], "fear opens the purse")
	t.check_eq(int(state["factions"]["red"]["treasury"]),
		red_before + int(data.balance["attitude"]["tribute_amount"]), "the tribute arrives")


func test_buying_a_town(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	state["factions"]["red"]["treasury"] = 50000
	# Blue holds only alpha — their last town is never for sale.
	t.check_eq(NegotiationRules.sellable_regions(data, state, "red", "blue").size(), 0,
		"a last holding is not for sale")
	# Give blue a second town; alpha borders red's beta, so alpha is buyable.
	state["settlements"]["gamma"] = {
		"owner": "blue", "population": 900, "buildings": {"tribal_government": 1},
		"tax_level": "normal", "garrison": [], "construction_queue": [],
		"recruitment_queue": [], "governor": null, "slave_bonus_turns": 0,
		"plague_turns": 0, "recently_conquered": 0, "low_order_streak": 0, "siege": null,
	}
	state["factions"]["blue"]["capital"] = "gamma"
	var sellable := NegotiationRules.sellable_regions(data, state, "red", "blue")
	t.check_eq(sellable, ["alpha"], "the border town is on the table")

	var price := NegotiationRules.region_price(data, state, "alpha")
	# Goodwill is nowhere near the bar yet.
	var cold := NegotiationRules.evaluate(data, state, "red", "blue",
		{"kind": "buy_region", "region": "alpha", "payment": price})
	t.check(not cold["accept"], "no sale without warm relations")
	NegotiationRules.shift_stored_attitude(data, state, "blue", "red", 80.0)
	var deal := NegotiationRules.execute(data, state, "red", "blue",
		{"kind": "buy_region", "region": "alpha", "payment": price})
	t.check(deal["accept"], "warm relations and full price buy the town: %s" % deal["reason"])
	t.check_eq(state["settlements"]["alpha"]["owner"], "red", "the town changes hands")
	t.check(int(state["settlements"]["alpha"]["recently_conquered"]) > 0,
		"the sold town resents it a little")


func test_peace_lifts_sieges(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var besieger := Fixtures.add_army(state, "red", "beta", ["test_elites", "test_elites", "test_elites"])
	SiegeRules.begin_siege(data, state, besieger, "alpha")
	t.check(state["settlements"]["alpha"]["siege"] != null, "siege laid")
	var verdict := NegotiationRules.execute(data, state, "red", "blue", {"kind": "peace"})
	t.check(verdict["accept"], "the outmatched defender takes the peace")
	t.check(state["settlements"]["alpha"]["siege"] == null, "peace brings the siege lines down")


func test_war_declaration_scars_attitude(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	DiplomacyRules.set_stance(state, "red", "blue", "neutral")
	t.check_eq(NegotiationRules.stored_attitude(state, "blue", "red"), 0.0, "clean slate")
	DiplomacyRules.declare_war(data, state, "red", "blue")
	t.check_near(NegotiationRules.stored_attitude(state, "blue", "red"),
		float(data.balance["attitude"]["war_declared_penalty"]), 0.01,
		"the wronged side remembers who drew first")


func test_envoy_gates_player_offers(t) -> void:
	var world := _world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	t.check(not game.can_negotiate_with("blue"), "no envoy, no talks")
	var verdict := game.propose("blue", {"kind": "peace"})
	t.check_eq(verdict["reason"], "no_envoy", "the facade refuses without an envoy")
	# Put an envoy on their soil.
	state["agents"]["agent_env"] = {
		"owner": "red", "kind": "diplomat", "region": "alpha", "name": "Talker",
		"skill": 1, "movement_left": 0.0, "turns_abroad": 0, "alive": true,
	}
	t.check(game.can_negotiate_with("blue"), "an envoy at their court opens the channel")
