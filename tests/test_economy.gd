extends RefCounted
## Treasury math: tax income scales with population and rate, upkeep drains,
## deep debt disbands, corruption grows with distance and shrinks with law.


func test_tax_income(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var by_label := {}
	for factor in EconomyRules.settlement_income_breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	# 2000 pop at normal rate: 2 * 100 * 1.0
	t.check_near(by_label.get("taxes", 0.0), 200.0, 0.001, "tax income formula")

	state["settlements"]["beta"]["tax_level"] = "very_high"
	by_label = {}
	for factor in EconomyRules.settlement_income_breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("taxes", 0.0), 300.0, 0.001, "very high taxes x1.5")


func test_corruption_distance_and_law(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check_near(EconomyRules.corruption_pct(data, state, "beta"), 0.0, 0.01, "no corruption at the capital")
	var far := EconomyRules.corruption_pct(data, state, "epsilon")
	t.check(far > 0.0, "distant settlements leak")
	# More law shrinks it: epsilon has 2 government tiers (10 law) already;
	# strip them to compare.
	state["settlements"]["epsilon"]["buildings"] = {}
	t.check(EconomyRules.corruption_pct(data, state, "epsilon") > far, "law suppresses corruption")


func test_upkeep_and_debt_disband(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(11)
	Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	t.check_eq(EconomyRules.faction_upkeep(data, state, "red"), 360, "upkeep sums")

	state["factions"]["red"]["treasury"] = int(data.balance["economy"]["debt_disband_threshold"]) - 10000
	var result := EconomyRules.apply_faction_turn(data, state, "red", rng)
	t.check(result.get("disbanded", false), "deep debt disbands a unit")
	var remaining := 0
	for army in state["armies"].values():
		if army["owner"] == "red":
			remaining += army["units"].size()
	t.check_eq(remaining, 2, "one unit disbanded per turn")


func test_trade_needs_peace_or_ownership(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# beta's only neighbors are alpha (enemy) and gamma (empty): no trade routes.
	t.check_near(EconomyRules.trade_income(data, state, "beta"), 0.0, 0.001, "war chokes land trade")
	state["factions"]["red"]["diplomacy"]["blue"] = "trade"
	state["factions"]["blue"]["diplomacy"]["red"] = "trade"
	t.check(EconomyRules.trade_income(data, state, "beta") > 0.0, "trade rights open the route")
