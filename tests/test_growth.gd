extends RefCounted
## Growth formula anchors from the research report: squalor ≈ pop/3000 (1% per
## 3000, capped), low taxes +0.5%, farms +0.5%/level, health +1% per +10%.


func test_squalor_anchor(t) -> void:
	var data := Fixtures.data()
	# 24,000 people ≈ 8% squalor; the report's headline anchor.
	t.check_near(GrowthRules.squalor_pct(data, {"population": 24000}), 8.0, 0.001, "24k pop squalor")
	t.check_near(GrowthRules.squalor_pct(data, {"population": 3000}), 1.0, 0.001, "3k pop squalor")
	# Capped at the balance maximum.
	var cap := float(data.balance["squalor"]["max_growth_penalty_pct"])
	t.check_near(GrowthRules.squalor_pct(data, {"population": 500000}), cap, 0.001, "squalor cap")


func test_growth_factors(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var factors := GrowthRules.breakdown(data, state, "beta")

	var by_label := {}
	for factor in factors:
		by_label[factor["label"]] = factor["value"]

	t.check_near(by_label.get("base_fertility", 0.0), 1.0, 0.001, "fertility factor")
	t.check_near(by_label.get("buildings", 0.0), 0.5, 0.001, "one farm level = +0.5%")
	t.check_near(by_label.get("squalor", 0.0), -2000.0 / 3000.0, 0.001, "squalor factor at 2000 pop")
	t.check(not by_label.has("taxes"), "normal taxes contribute no growth factor")

	state["settlements"]["beta"]["tax_level"] = "low"
	factors = GrowthRules.breakdown(data, state, "beta")
	for factor in factors:
		if factor["label"] == "taxes":
			t.check_near(factor["value"], 0.5, 0.001, "low taxes +0.5% growth")


func test_health_contribution(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["beta"]["buildings"]["test_health"] = 1
	var by_label := {}
	for factor in GrowthRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("health", 0.0), 1.0, 0.001, "+10 health = +1% growth")


func test_population_grows_and_shrinks(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(7)

	var before := int(state["settlements"]["beta"]["population"])
	GrowthRules.apply_turn(data, state, "beta", rng)
	t.check(int(state["settlements"]["beta"]["population"]) > before, "healthy town grows")

	# A huge population with no health support shrinks under squalor.
	state["settlements"]["epsilon"]["population"] = 60000
	GrowthRules.apply_turn(data, state, "epsilon", rng)
	t.check(int(state["settlements"]["epsilon"]["population"]) < 60000, "squalid city shrinks")


func test_grain_import_routes(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# beta is adjacent to alpha (blue, at war): no grain route while hostile.
	var by_label := {}
	for factor in GrowthRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check(not by_label.has("grain_imports"), "no grain from an enemy")

	state["factions"]["red"]["diplomacy"]["blue"] = "trade"
	state["factions"]["blue"]["diplomacy"]["red"] = "trade"
	by_label = {}
	for factor in GrowthRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("grain_imports", 0.0), 1.5, 0.001, "one grain route = +1.5%")
