extends RefCounted
## Provincial edicts: the player's fast lever on a simulation whose stocks move
## over decades. An edict is shaped like a building you can raise and pull down
## in a few turns, so most of it rides SettlementRules.effect_total and reaches
## every existing reader; these tests prove each of those paths actually carries.


func _rules(data) -> Dictionary:
	return data.balance["society"]


func _town(data, state) -> Dictionary:
	## beta is red's capital: a town with a government, farms and barracks.
	return state["settlements"]["beta"]


## --- Gating ----------------------------------------------------------------

func test_a_province_may_hold_one_order_at_a_time(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check(EdictRules.issue(data, state, "beta", "martial_law"), "an order can be given")
	t.check(not EdictRules.issue(data, state, "beta", "census"),
		"a second order cannot be given while the first stands")
	var refusal := EdictRules.allowed(data, state, "beta", "census")
	t.check(String(refusal["reason"]) != "", "and the refusal says why")


func test_settlement_level_and_buildings_gate_what_may_be_ordered(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement := _town(data, state)

	# The corn dole needs somewhere to distribute from.
	t.check(not EdictRules.allowed(data, state, "beta", "grain_dole")["ok"],
		"no market, no corn dole")
	settlement["buildings"]["test_market"] = 1
	t.check(EdictRules.allowed(data, state, "beta", "grain_dole")["ok"],
		"a market makes it possible")

	# Enfranchisement needs a real city.
	t.check(not EdictRules.allowed(data, state, "beta", "grant_of_citizenship")["ok"],
		"a town is not enfranchised")
	settlement["buildings"]["test_government"] = 4
	t.check(EdictRules.allowed(data, state, "beta", "grant_of_citizenship")["ok"],
		"a minor city is")


func test_revoking_starts_a_cooldown(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement := _town(data, state)
	# Raise the town so the census is blocked by the cooldown and nothing else —
	# otherwise this test passes for the wrong reason.
	settlement["buildings"]["test_government"] = 3
	t.check(EdictRules.allowed(data, state, "beta", "census")["ok"],
		"the census is otherwise available here")

	EdictRules.issue(data, state, "beta", "martial_law")
	var cooldown := int(data.edicts["martial_law"]["cooldown_turns"])
	t.check(EdictRules.revoke(data, state, "beta"), "the order is revoked")
	t.check_eq(int(EdictRules.of(settlement)["cooldown"]), cooldown, "and a cooldown begins")
	var blocked := EdictRules.allowed(data, state, "beta", "census")
	t.check(not blocked["ok"], "nothing else may be ordered while it runs")
	t.check(String(blocked["reason"]).contains("unwound"),
		"and the refusal names the cooldown, not some other gate")

	for i in range(cooldown):
		EdictRules.advance_turn(data, state, ["beta"])
	t.check_eq(int(EdictRules.of(settlement)["cooldown"]), 0, "the cooldown runs down")
	t.check(EdictRules.allowed(data, state, "beta", "census")["ok"], "and then a new order may be given")


func test_a_province_that_changes_hands_answers_to_nobody(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	EdictRules.issue(data, state, "beta", "martial_law")
	EdictRules.clear(state["settlements"]["beta"])
	t.check_eq(EdictRules.of(state["settlements"]["beta"])["id"], EdictRules.NONE,
		"a captured or seceded province carries no standing order")


## --- Taking hold, and letting go -------------------------------------------

func test_an_order_takes_hold_over_turns_and_stops_at_once(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement := _town(data, state)
	var settle := int(data.edicts["martial_law"]["settle_turns"])
	var full := float(data.edicts["martial_law"]["effects"]["coercion"])

	EdictRules.issue(data, state, "beta", "martial_law")
	t.check_eq(EdictRules.strength(data, settlement), 0.0, "a new order is not yet obeyed")
	t.check_eq(EdictRules.effect(data, settlement, "coercion"), 0.0, "so it does nothing yet")

	EdictRules.advance_turn(data, state, ["beta"])
	var partial := EdictRules.effect(data, settlement, "coercion")
	t.check(partial > 0.0 and partial < full, "after one turn it is partly in force")

	for i in range(settle):
		EdictRules.advance_turn(data, state, ["beta"])
	t.check_eq(EdictRules.strength(data, settlement), 1.0, "it reaches full strength")
	t.check_eq(EdictRules.effect(data, settlement, "coercion"), full, "at its authored value")

	# Letting go is immediate — that asymmetry is what makes the dole a trap.
	EdictRules.revoke(data, state, "beta")
	t.check_eq(EdictRules.effect(data, settlement, "coercion"), 0.0, "revoking stops it the same turn")


## --- One test per reader the edict has to reach ------------------------------

func _in_force(data, state, region_id: String, edict_id: String) -> void:
	EdictRules.issue(data, state, region_id, edict_id)
	for i in range(int(data.edicts[edict_id]["settle_turns"])):
		EdictRules.advance_turn(data, state, [region_id])


func test_civic_and_burden_reach_the_society_flows(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var target_before := SocietyRules.legitimacy_target(data, state, "beta")
	var load_before := SocietyRules.load_total(data, state, "beta")
	_in_force(data, state, "beta", "martial_law")
	t.check(SocietyRules.legitimacy_target(data, state, "beta") < target_before,
		"an edict's civic cost reaches the legitimacy target")
	t.check(SocietyRules.load_total(data, state, "beta") > load_before,
		"and its burden reaches the load")


func test_coercion_reaches_public_order(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var before := PublicOrderRules.total(data, state, "beta")
	_in_force(data, state, "beta", "martial_law")
	t.check(PublicOrderRules.total(data, state, "beta") > before,
		"martial law raises order — that is exactly why it is tempting")
	var by_label := {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(by_label.get("coercion", 0.0) > 0.0, "and it is named as coercion, not as consent")


func test_happiness_reaches_provision_and_therefore_expectation(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement := _town(data, state)
	settlement["buildings"]["test_market"] = 1
	t.check_eq(SocietyRules.provision(data, settlement), 0.0, "the town provides nothing yet")
	_in_force(data, state, "beta", "grain_dole")
	t.check(SocietyRules.provision(data, settlement) > 0.0,
		"the dole is something the state visibly provides")


func test_clarity_income_and_build_cost_each_reach_their_reader(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement := _town(data, state)
	settlement["buildings"]["test_government"] = 3

	state["settlements"]["epsilon"]["buildings"]["test_government"] = 3
	var clarity_before := LegibilityRules.clarity(data, state, "epsilon")
	t.check(EdictRules.allowed(data, state, "epsilon", "census")["ok"], "the census may be ordered")
	_in_force(data, state, "epsilon", "census")
	t.check(LegibilityRules.clarity(data, state, "epsilon") > clarity_before,
		"a census is sight bought outright")

	var income_before := EconomyRules.settlement_income(data, state, "beta")
	_in_force(data, state, "beta", "tax_farming")
	t.check(EconomyRules.settlement_income(data, state, "beta") > income_before,
		"tax farming fills the treasury this year")

	var plain_data := Fixtures.data()
	var plain := Fixtures.state(plain_data)
	var levy_data := Fixtures.data()
	var levy := Fixtures.state(levy_data)
	_in_force(levy_data, levy, "beta", "labour_levy")
	var plain_cost := int(ConstructionRules.available_projects(plain_data, plain, "beta")[0]["cost"])
	var levy_cost := int(ConstructionRules.available_projects(levy_data, levy, "beta")[0]["cost"])
	t.check(levy_cost < plain_cost, "a labour levy builds cheaply, here and nowhere else")


func test_grievance_relief_and_elite_pressure_reach_their_stocks(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement := _town(data, state)
	settlement["society"]["grievance"] = 60.0
	settlement["society"]["legitimacy"] = 100.0
	settlement["tax_level"] = "very_low"

	var plain_data := Fixtures.data()
	var plain := Fixtures.state(plain_data)
	plain["settlements"]["beta"]["society"]["grievance"] = 60.0
	plain["settlements"]["beta"]["society"]["legitimacy"] = 100.0
	plain["settlements"]["beta"]["tax_level"] = "very_low"

	_in_force(data, state, "beta", "amnesty")
	SocietyRules.apply_settlement_turn(data, state, "beta")
	SocietyRules.apply_settlement_turn(plain_data, plain, "beta")
	t.check(float(SocietyRules.stocks_of(data, settlement)["grievance"])
		< float(SocietyRules.stocks_of(plain_data, plain["settlements"]["beta"])["grievance"]),
		"an amnesty empties the ledger faster than time alone")

	var ambition_before: float = SocietyRules.faction_stocks(data, state["factions"]["red"])["elite_pressure"]
	for i in range(10):
		SocietyRules.apply_faction_turn(data, state, "red")
	var with_amnesty: float = SocietyRules.faction_stocks(data, state["factions"]["red"])["elite_pressure"]
	for i in range(10):
		SocietyRules.apply_faction_turn(plain_data, plain, "red")
	t.check(with_amnesty > float(SocietyRules.faction_stocks(plain_data, plain["factions"]["red"])["elite_pressure"]),
		"and the men it pardoned are men you will meet again")
	t.check(ambition_before >= 0.0, "ambition is readable throughout")


func test_the_bill_is_a_named_factor_and_scales_with_the_city(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_town(data, state)["buildings"]["test_market"] = 1
	_in_force(data, state, "beta", "grain_dole")

	var by_label := {}
	for factor in EconomyRules.settlement_income_breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(by_label.get("edict_upkeep", 0.0) < 0.0, "the dole sends a bill every turn")

	var small := EdictRules.upkeep(data, state["settlements"]["beta"])
	state["settlements"]["beta"]["population"] = int(state["settlements"]["beta"]["population"]) * 3
	t.check(EdictRules.upkeep(data, state["settlements"]["beta"]) > small,
		"and it scales with the number of people being fed")


## --- The two lessons the edicts exist to teach --------------------------------

func test_the_corn_dole_is_a_promise_not_a_purchase(t) -> void:
	## Give it, let the city grow used to it, take it away: the city is now
	## worse off than one that never had it.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement := _town(data, state)
	settlement["buildings"]["test_market"] = 1

	var by_label := {}
	for factor in SocietyRules.load_breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(not by_label.has("broken_promises"), "a city given nothing is owed nothing")

	_in_force(data, state, "beta", "grain_dole")
	for i in range(40):
		SocietyRules.apply_settlement_turn(data, state, "beta")
	t.check(float(SocietyRules.stocks_of(data, settlement)["expectation"]) > 0.0,
		"the city comes to expect the distribution")

	var before_revoking := SocietyRules.load_total(data, state, "beta")
	EdictRules.revoke(data, state, "beta")
	t.check(SocietyRules.load_total(data, state, "beta") > before_revoking,
		"stopping it is itself a load")
	by_label = {}
	for factor in SocietyRules.load_breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(by_label.get("broken_promises", 0.0) > 0.0, "and it is named as a broken promise")


func test_martial_law_improves_the_number_and_ruins_the_province(t) -> void:
	## The coercion trap compressed into one click, and both halves must be
	## visible in the same turn or the player learns nothing from it.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var order_before := PublicOrderRules.total(data, state, "beta")
	var standing_before := SocietyRules.legitimacy_target(data, state, "beta")
	_in_force(data, state, "beta", "martial_law")
	t.check(PublicOrderRules.total(data, state, "beta") > order_before,
		"order improves tonight")
	t.check(SocietyRules.legitimacy_target(data, state, "beta") < standing_before,
		"and nothing else about this province does")


## --- Discipline ---------------------------------------------------------------

func test_reading_edicts_consumes_no_randomness(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_in_force(data, state, "beta", "census")
	state["rng_state"] = "424242"
	for i in range(6):
		EdictRules.available(data, state, "beta")
		EdictRules.status(data, state, "beta")
		EdictRules.effect(data, state["settlements"]["beta"], "law")
		EdictRules.upkeep(data, state["settlements"]["beta"])
	t.check_eq(state["rng_state"], "424242", "no edict query draws from the campaign stream")


func test_a_campaign_with_standing_orders_survives_save_and_load(t) -> void:
	var game := Game.new_campaign("julii", 19)
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if game.state["settlements"][region_id]["owner"] == "julii":
			game.set_edict(region_id, "census")
	for turn in range(12):
		game.end_turn()

	var restored := SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not restored.is_empty(), "the campaign saves and parses back")
	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored
	for turn in range(6):
		game.end_turn()
		resumed.end_turn()
	t.check_eq(_canonical(game.state), _canonical(resumed.state),
		"a campaign with standing orders marches in step with its save")


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))
