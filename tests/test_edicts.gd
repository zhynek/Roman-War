extends RefCounted
## Edicts (Phase 6): enactment gates (culture, buildings, techniques,
## exclusivity, the book's size, cooldowns), decree moods and repeal shocks
## through the stacking modifier container, upkeep including the per-head
## clauses, the insolvency collapse, labeled factors in every breakdown,
## recruit/upkeep effects, the citizenship lever, standing drips, and
## determinism across a JSON round trip.


func test_enact_pays_and_shows_its_hand(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var red: Dictionary = state["factions"]["red"]
	var verdict := EdictRules.enact(data, state, "red", "test_dole")
	t.check(bool(verdict["ok"]), "the dole is enacted")
	t.check_eq(int(red["treasury"]), 5000 - 400, "and paid for")
	t.check(EdictRules.enacted(state, "red").has("test_dole"), "the book records it")
	t.check_near(float(red["senate_standing"]), 4.0, 0.001, "the senate frowns at once")
	t.check_near(float(red["popular_standing"]), 1.0, 0.001, "the crowd approves at once")
	t.check_near(_factor(PublicOrderRules.breakdown(data, state, "beta"), "edict:test_dole"), 4.0, 0.001,
		"order breakdown names the edict as its own factor")
	t.check_near(_factor(PublicOrderRules.breakdown(data, state, "alpha"), "edict:test_dole"), 0.0, 0.001,
		"and only in the enactor's cities")


func test_enactment_gates(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check_eq(String(EdictRules.enact(data, state, "blue", "test_dole")["reason"]), "foreign_custom",
		"a tribal court does not keep a Roman dole")
	t.check_eq(String(EdictRules.enact(data, state, "red", "test_census_tax")["reason"]), "wants_technique",
		"the census levy waits on the registration craft")
	state["factions"]["red"]["knowledge"]["test_letters"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	t.check(bool(EdictRules.enact(data, state, "red", "test_census_tax")["ok"]),
		"and opens once it is practiced")
	t.check_eq(String(EdictRules.enact(data, state, "red", "test_farm_tax")["reason"]), "contradicts_test_census_tax",
		"you cannot farm out taxes you collect by census")
	t.check_eq(String(EdictRules.enact(data, state, "red", "test_census_tax")["reason"]), "already_held",
		"no enacting twice")
	state["factions"]["red"]["treasury"] = 50
	t.check_eq(String(EdictRules.enact(data, state, "red", "test_muster")["reason"]), "treasury",
		"the purse refuses")


func test_the_book_has_a_size(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.edicts["test_extra"] = {
		"id": "test_extra", "name": "Extra", "category": "welfare", "kind": "standing",
		"historical_basis": "fixture", "availability": {"cultures": []},
		"prerequisites": {"building_kind": "", "building_level": 0, "techniques": []},
		"enact_cost": 100, "upkeep_per_turn": 10, "upkeep_per_1000_pop": 0.0,
		"effects": {"happiness": 1},
		"tensions": {"exclusive_with": [], "repeal_unrest": {"penalty": 0, "turns": 0},
			"senate_standing_delta": 0.0, "popular_standing_delta": 0.0},
	}
	for eid in ["test_dole", "test_farm_tax", "test_muster", "test_franchise"]:
		t.check(bool(EdictRules.enact(data, state, "red", eid)["ok"]), "enacted " + eid)
	t.check_eq(String(EdictRules.enact(data, state, "red", "test_extra")["reason"]), "book_full",
		"four standing policies is the book's size")


func test_decree_mood_fades(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var verdict := EdictRules.enact(data, state, "red", "test_games")
	t.check(bool(verdict["ok"]), "the games are given")
	t.check(not EdictRules.enacted(state, "red").has("test_games"), "a decree is not held")
	t.check_near(ModifierRules.sum_for(state, "red", "beta", "happiness"), 5.0, 0.001,
		"the mood is on the city")
	t.check_near(_factor(PublicOrderRules.breakdown(data, state, "beta"), "decrees"), 5.0, 0.001,
		"and renders as the decrees factor")
	t.check_eq(String(EdictRules.enact(data, state, "red", "test_games")["reason"]), "too_soon",
		"no games again this soon")
	for i in range(3):
		ModifierRules.tick(state)
	t.check_near(ModifierRules.sum_for(state, "red", "beta", "happiness"), 0.0, 0.001,
		"the mood fades on schedule")
	t.check(state["modifiers"].is_empty(), "and the spent modifier is swept away")


func test_repeal_shock_and_cooldown(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	EdictRules.enact(data, state, "red", "test_dole")
	t.check_near(float(state["factions"]["red"]["senate_standing"]), 4.0, 0.001, "enacting cost the senate's favor")
	t.check(EdictRules.repeal(data, state, "red", "test_dole"), "the dole is struck down")
	t.check_near(ModifierRules.sum_for(state, "red", "beta", "happiness"), -6.0, 0.001,
		"the crowd's fury lands as a fading shock")
	t.check_near(float(state["factions"]["red"]["senate_standing"]), 5.0, 0.001,
		"a voluntary repeal hands the standing back — cycling mints nothing")
	t.check_near(float(state["factions"]["red"]["popular_standing"]), 0.0, 0.001,
		"the crowd's credit goes with it")
	t.check_eq(String(EdictRules.enact(data, state, "red", "test_dole")["reason"]), "too_soon",
		"policy is not a lamp to flick back on")
	t.check(not EdictRules.repeal(data, state, "red", "test_dole"), "nothing left to repeal")


func test_popular_standing_survives_the_senate_drift(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	EdictRules.enact(data, state, "red", "test_dole")
	t.check_near(float(state["factions"]["red"]["popular_standing"]), 1.0, 0.001, "the crowd approves")
	SenateRules.process_turn(data, state, CampaignRng.seeded(1))
	t.check(float(state["factions"]["red"]["popular_standing"]) > 0.85,
		"the senate's regional baseline DRIFTS the number — it never overwrites what politics earned")


func test_upkeep_scales_with_the_mouths_it_feeds(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	EdictRules.enact(data, state, "red", "test_dole")
	# 50 flat + 10 per 1000 heads over beta 2000 + epsilon 6000.
	t.check_eq(EdictRules.upkeep(data, state, "red"), 130, "flat plus per-head clauses")
	var breakdown := EconomyRules.faction_turn_breakdown(data, state, "red")
	t.check_eq(int(breakdown["upkeep"]), 130, "and the treasury pays it each turn")


func test_insolvency_collapses_the_costliest_policy(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	EdictRules.enact(data, state, "red", "test_dole")
	EdictRules.enact(data, state, "red", "test_franchise")
	state["factions"]["red"]["treasury"] = -100
	var events := EdictRules.process_turn(data, state)
	t.check(not EdictRules.enacted(state, "red").has("test_dole"),
		"the dole collapses when the silver runs out")
	t.check(EdictRules.enacted(state, "red").has("test_franchise"),
		"the cheaper policy survives the season")
	var lapsed := false
	for event in events:
		if event.get("kind", "") == "edict_lapsed" and event.get("edict", "") == "test_dole":
			lapsed = true
	t.check(lapsed, "the collapse is reported")
	t.check_near(ModifierRules.sum_for(state, "red", "beta", "happiness"), -6.0, 0.001,
		"and the shock lands all the same")
	t.check_near(float(state["factions"]["red"]["senate_standing"]), 4.0, 0.001,
		"but a collapse refunds nothing — the senate remembers both the act and the failure")


func test_fiscal_edicts_move_the_take(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var taxes_before := _factor(EconomyRules.settlement_income_breakdown(data, state, "beta"), "taxes")
	var farming_before := _factor(EconomyRules.settlement_income_breakdown(data, state, "beta"), "farming")
	EdictRules.enact(data, state, "red", "test_farm_tax")
	EdictRules.enact(data, state, "red", "test_franchise")
	t.check_near(_factor(EconomyRules.settlement_income_breakdown(data, state, "beta"), "taxes"),
		taxes_before * 1.2, 0.01, "farmed taxes squeeze a fifth more")
	t.check_near(_factor(EconomyRules.settlement_income_breakdown(data, state, "beta"), "farming"),
		farming_before * 1.1, 0.01, "the franchise settles the countryside")


func test_military_edicts_price_the_muster(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	EdictRules.enact(data, state, "red", "test_muster")
	var treasury_before := int(state["factions"]["red"]["treasury"])
	t.check(RecruitmentRules.queue_unit(data, state, "beta", "test_spears"), "the levy musters")
	t.check_eq(int(state["factions"]["red"]["treasury"]), treasury_before - 300,
		"at a quarter off the price")
	RecruitmentRules.advance_queues(data, state, "beta")
	t.check_eq(int(state["settlements"]["beta"]["garrison"][0]["experience"]), 1,
		"drilled a chevron above raw")
	Fixtures.add_army(state, "red", "beta", ["test_spears"])
	# Field spearmen 120 + the fresh garrison spearman 120, both a tenth dearer.
	t.check_eq(EconomyRules.faction_upkeep(data, state, "red"), 264,
		"and the wage bill runs a tenth higher")


func test_citizenship_softens_foreign_stones(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["alpha"]["owner"] = "red"
	t.check_near(SettlementRules.culture_penalty_pct(data, state, "alpha"), 40.0, 0.001,
		"a wholly tribal town chafes under Roman rule")
	EdictRules.enact(data, state, "red", "test_franchise")
	t.check_near(SettlementRules.culture_penalty_pct(data, state, "alpha"), 20.0, 0.001,
		"the wider franchise halves the resentment")


func test_standing_drips_each_turn(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	EdictRules.enact(data, state, "red", "test_dole")
	var popular_after_enact := float(state["factions"]["red"]["popular_standing"])
	EdictRules.process_turn(data, state)
	t.check_near(float(state["factions"]["red"]["popular_standing"]), popular_after_enact + 0.2, 0.001,
		"the dole keeps paying the crowd, turn upon turn")


func test_lockstep_after_json_round_trip(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	EdictRules.enact(data, state, "red", "test_dole")
	EdictRules.enact(data, state, "red", "test_games")
	EdictRules.repeal(data, state, "red", "test_dole")
	var twin: Dictionary = JSON.parse_string(JSON.stringify(state))
	for i in range(4):
		EdictRules.process_turn(data, state)
		ModifierRules.tick(state)
		EdictRules.process_turn(data, twin)
		ModifierRules.tick(twin)
	t.check_eq(_canonical(state), _canonical(twin),
		"edict and modifier state march in lockstep through a round trip")


func _factor(factors: Array, label: String) -> float:
	for factor in factors:
		if factor["label"] == label:
			return float(factor["value"])
	return 0.0


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))
