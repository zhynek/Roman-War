extends RefCounted
## Public order: base 100 + factors; riots below the threshold; revolt to the
## rebels after a sustained collapse; distance-to-capital and garrison shapes.


func test_order_breakdown_shape(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var by_label := {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("base", 0.0), 100.0, 0.001, "base is 100")
	t.check_near(by_label.get("law", 0.0), 10.0, 0.001, "tier-2 government law standing value")
	t.check(by_label.get("no_governor", 0.0) < 0.0, "ungoverned settlements suffer")
	t.check(by_label.get("squalor", 0.0) < 0.0, "squalor hurts order")


func test_distance_to_capital(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# beta IS the capital: no penalty. epsilon is 3 hops out: 1 beyond free (2).
	t.check_near(PublicOrderRules.distance_penalty(data, state, "beta"), 0.0, 0.001, "capital has no penalty")
	var per_hop := float(data.balance["distance_to_capital"]["pct_per_hop"])
	t.check_near(PublicOrderRules.distance_penalty(data, state, "epsilon"), per_hop, 0.001, "one hop beyond free radius")


func test_garrison_suppression_cap(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement: Dictionary = state["settlements"]["beta"]
	for i in range(20):
		settlement["garrison"].append({"template": "test_spears", "experience": 0, "strength_pct": 100})
	var cap := float(data.balance["public_order"]["garrison_max_bonus"])
	t.check_near(PublicOrderRules.garrison_bonus(data, settlement), cap, 0.001, "garrison bonus caps")


func test_taxes_and_riot(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(3)
	var settlement: Dictionary = state["settlements"]["epsilon"]

	settlement["tax_level"] = "very_high"
	settlement["population"] = 40000
	var order := PublicOrderRules.total(data, state, "epsilon")
	t.check(order < float(data.balance["public_order"]["riot_threshold"]), "squalid overtaxed city is rioting")

	var result := PublicOrderRules.apply_turn(data, state, "epsilon", rng)
	t.check(result["rioted"], "riot fires")


func test_revolt_after_streak(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(3)
	var settlement: Dictionary = state["settlements"]["epsilon"]
	settlement["tax_level"] = "very_high"
	settlement["population"] = 80000
	settlement["recently_conquered"] = 6

	t.check(PublicOrderRules.total(data, state, "epsilon") < float(data.balance["public_order"]["revolt_threshold"]),
		"order is below revolt threshold")
	var revolted := false
	for i in range(int(data.balance["public_order"]["revolt_consecutive_turns"]) + 1):
		settlement["recently_conquered"] = 6
		settlement["population"] = 80000
		if PublicOrderRules.apply_turn(data, state, "epsilon", rng)["revolted"]:
			revolted = true
			break
	t.check(revolted, "sustained collapse revolts")
	t.check_eq(settlement["owner"], "rebels", "settlement secedes to the rebels")


func test_culture_penalty(t) -> void:
	## Foreign rule is no longer a building census read off instantly — it is a
	## stock that drifts. The census survives as the friction term on
	## assimilation; the ORDER penalty now reads the drifting stock.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# Red (roman) takes alpha, which has only a tribal government building.
	var settlement: Dictionary = state["settlements"]["alpha"]
	settlement["owner"] = "red"
	t.check_near(SettlementRules.foreign_building_share(data, state, "alpha"), 1.0, 0.001,
		"every standing building belongs to another culture")

	# A settlement that has always been theirs feels no foreign rule...
	var scale := float(data.balance["public_order"]["culture_penalty_scale"])
	var settled := SettlementRules.culture_penalty_pct(data, state, "alpha")
	t.check(settled < scale * 0.2, "a long-held province carries almost no culture penalty")

	# ...but one just taken by force does, and it does not clear by demolition alone.
	SocietyRules.record_conquest(data, state, "alpha", "red", "occupy")
	var conquered := SettlementRules.culture_penalty_pct(data, state, "alpha")
	var foreign_start := float(data.balance["society"]["assimilation_start_foreign"])
	t.check_near(conquered, (100.0 - foreign_start) / 100.0 * scale, 0.001,
		"a freshly conquered province carries the full weight of foreign rule")
	t.check(conquered > settled * 3.0, "conquest is what makes a province a stranger")
