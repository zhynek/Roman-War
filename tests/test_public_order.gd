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


func test_revolt_of_last_settlement_destroys_the_faction(t) -> void:
	## The destruction check must run on revolts exactly as it does on capture
	## and cession — otherwise a landless zombie faction keeps playing.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var stray := Fixtures.add_army(state, "blue", "gamma", ["test_mob"])
	PublicOrderRules._revolt(data, state, "alpha")
	t.check_eq(state["settlements"]["alpha"]["owner"], "rebels", "the city joined the rebels")
	t.check(not state["factions"]["blue"]["alive"], "and its landless master is destroyed")
	t.check_eq(state["armies"][stray]["owner"], "rebels", "his field army defects to the rebels")


func test_culture_penalty(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(3)
	# Blue holds only alpha; a field army will outlive the city.
	var army_id := Fixtures.add_army(state, "blue", "gamma", ["test_mob"])
	var settlement: Dictionary = state["settlements"]["alpha"]
	settlement["tax_level"] = "very_high"
	settlement["population"] = 80000
	var revolted := false
	for i in range(int(data.balance["public_order"]["revolt_consecutive_turns"]) + 1):
		settlement["recently_conquered"] = 6
		settlement["population"] = 80000
		if PublicOrderRules.apply_turn(data, state, "alpha", rng)["revolted"]:
			revolted = true
			break
	t.check(revolted, "the last city rose")
	t.check(not state["factions"]["blue"]["alive"],
		"losing the last settlement to its own people destroys the faction")
	t.check_eq(state["armies"][army_id]["owner"], "rebels",
		"the landless army defects to the rebels")


## --- The garrison's quality, the levy's cost, the war's mood ----------------

func _garrison_of(templates: Array, experience: int = 0) -> Array:
	var units: Array = []
	for template in templates:
		units.append({"template": template, "experience": experience, "strength_pct": 100})
	return units


func test_garrison_quality_weights_classes(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	beta["garrison"] = _garrison_of(["test_elites"])   # 80 infantry, weight 1.0
	var infantry := SettlementRules.garrison_policing(data, beta)
	beta["garrison"] = _garrison_of(["test_horse"])    # 40 cavalry, weight 0.9
	var horse := SettlementRules.garrison_policing(data, beta)
	beta["garrison"] = _garrison_of(["test_mob", "test_mob"])  # 120 peasants, weight 0.5
	var mob := SettlementRules.garrison_policing(data, beta)
	t.check_near(infantry, 80.0, 0.001, "eighty foot police as eighty")
	t.check_near(horse, 36.0, 0.001, "forty horsemen police as thirty-six: a little less use per man in the streets")
	t.check_near(mob, 60.0, 0.001, "a hundred and twenty levies police as sixty")
	t.check(mob < infantry, "a bigger mob of levies polices worse than fewer regulars")


func test_garrison_experience_and_drill(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	beta["garrison"] = _garrison_of(["test_spears"])          # 80 men in a town of 2000: 16 order
	var green := PublicOrderRules.garrison_bonus(data, beta)
	t.check_near(green, 16.0, 0.001, "raw headcount suppression as before")
	beta["garrison"] = _garrison_of(["test_spears"], 4)
	t.check_near(PublicOrderRules.garrison_bonus(data, beta), 19.2, 0.001, "four chevrons police 20% better")
	t.check_near(PublicOrderRules.garrison_bonus(data, beta, 1.0), 21.12, 0.001, "and a drill yard adds 10% on top")
	beta["buildings"]["test_barracks"] = 2  # the fixture drill yard
	var by_label := {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("garrison", 0.0), 21.12, 0.001, "the breakdown reads the town's drill")


func test_levy_strain_rises_and_decays(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	var rng := CampaignRng.seeded(1)
	t.check(RecruitmentRules.queue_unit(data, state, "beta", "test_spears"), "levy raised")
	t.check_near(float(beta["levy_strain"]), 4.0, 0.001, "80 men of 2000 = 4 strain points")
	var by_label := {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("levy_strain", 0.0), -4.0, 0.001, "the strain weighs on order")
	by_label = {}
	for factor in GrowthRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("levy_strain", 0.0), -0.2, 0.001, "and a little on growth")

	PublicOrderRules.apply_turn(data, state, "beta", rng)
	t.check_near(float(beta["levy_strain"]), 2.0, 0.001, "strain fades two points a turn")
	PublicOrderRules.apply_turn(data, state, "beta", rng)
	t.check_near(float(beta["levy_strain"]), 0.0, 0.001, "and is forgotten")

	beta["buildings"]["test_barracks"] = 2  # drilled towns resent the levy less
	RecruitmentRules.queue_unit(data, state, "beta", "test_spears")
	t.check(float(beta["levy_strain"]) < 4.0 and float(beta["levy_strain"]) > 0.0, "drill softens the levy")


func test_war_mood_after_decisive_victory(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(9)
	# 1,200 pikemen against 360 peasants: well over the size floor, and a massacre.
	var pikes: Array = []
	for i in range(10):
		pikes.append("test_pikes")
	var attacker_id := Fixtures.add_army(state, "red", "beta", pikes)
	var defender_id := Fixtures.add_army(state, "blue", "alpha", ["test_mob", "test_mob", "test_mob", "test_mob", "test_mob", "test_mob"])
	var result := CombatRules.attack_army(data, state, resolver, rng, attacker_id, defender_id)
	t.check_eq(result["winner"], "attacker", "the phalanx wins")
	var red: Dictionary = state["factions"]["red"]
	var blue: Dictionary = state["factions"]["blue"]
	t.check(red["war_mood"] is Dictionary and float(red["war_mood"]["value"]) > 0.0, "a triumph at home for the victor")
	t.check(blue["war_mood"] is Dictionary and float(blue["war_mood"]["value"]) < 0.0, "a shock at home for the beaten")
	var by_label := {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = factor["value"]
	t.check_near(by_label.get("war_mood", 0.0), float(data.balance["public_order"]["triumph_bonus"]), 0.001,
		"the victor's towns feel it")
	t.check_eq(int(red["war_record"]["battles_won"]), 1, "the win is recorded")
	t.check_eq(int(blue["war_record"]["battles_lost"]), 1, "so is the loss")
	t.check_eq(int(red["war_record"]["faced"].get("peasant", 0)), 1, "and whom each side faced")
	t.check_eq(int(blue["war_record"]["faced"].get("pike", 0)), 1, "the mob remembers the pikes")
	for i in range(int(data.balance["public_order"]["triumph_turns"])):
		PublicOrderRules.tick_war_mood(state)
	t.check(red["war_mood"] == null and blue["war_mood"] == null, "moods fade after their turns")


func test_skirmishes_do_not_move_the_mood(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var attacker_id := Fixtures.add_army(state, "red", "beta", ["test_elites", "test_elites", "test_elites"])
	var defender_id := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	var result := CombatRules.attack_army(data, state, AutoResolver.new(), CampaignRng.seeded(2), attacker_id, defender_id)
	t.check_eq(result["winner"], "attacker", "the cohorts win the skirmish")
	t.check(state["factions"]["red"]["war_mood"] == null, "three hundred men engaged is no triumph")
	t.check_eq(int(state["factions"]["red"]["war_record"]["battles_won"]), 1, "but it still counts as a battle")


func test_walkover_is_not_a_battle(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_elites", "test_elites"])
	state["settlements"]["alpha"]["garrison"] = []
	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege laid on the empty town")
	state["settlements"]["alpha"]["siege"]["equipment_ready"] = true
	var result := SiegeRules.assault(data, state, CampaignRng.seeded(3), AutoResolver.new(), army_id, "alpha")
	t.check(result.get("captured", false) and result.get("walkover", false), "the empty town falls without a fight")
	t.check_eq(int(state["factions"]["red"]["war_record"]["battles_won"]), 0, "a walkover is no victory for the record")
	t.check(state["factions"]["red"]["war_mood"] == null, "and no triumph")


func test_stronger_mood_stands(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	CombatRules.set_war_mood(state, "red", "defeat", -8.0, 4)
	CombatRules.set_war_mood(state, "red", "triumph", 5.0, 4)
	t.check_near(float(state["factions"]["red"]["war_mood"]["value"]), -8.0, 0.001, "a small triumph does not erase a deep shock")
	CombatRules.set_war_mood(state, "red", "defeat", -8.0, 2)
	t.check_eq(int(state["factions"]["red"]["war_mood"]["turns"]), 2, "an equal blow restarts the clock")
	CombatRules.set_war_mood(state, "red", "triumph", 12.0, 3)
	t.check_near(float(state["factions"]["red"]["war_mood"]["value"]), 12.0, 0.001, "a greater one replaces it")
