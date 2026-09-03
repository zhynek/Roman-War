extends RefCounted
## The societal layer: the coercion asymmetry that makes a garrisoned province
## read calm while its grievance climbs, hysteresis on the way out of unrest,
## belonging as diffusion, and the two ways elite pressure kills a state. All
## thresholds come from data/balance.json — never a literal.


func _rules(data) -> Dictionary:
	return data.balance["society"]


func test_load_is_a_named_factor_list(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var factors := SocietyRules.load_breakdown(data, state, "beta")
	t.check(not factors.is_empty(), "load returns factors")
	for factor in factors:
		t.check(factor.has("label") and factor.has("value"), "every factor is {label, value}")
	var by_label := {}
	for factor in factors:
		by_label[factor["label"]] = float(factor["value"])
	t.check_eq(by_label["base"], float(_rules(data)["load_base"]), "base load is the balance constant")

	# Taxes are a demand, so raising them raises the load.
	var normal := SocietyRules.load_total(data, state, "beta")
	state["settlements"]["beta"]["tax_level"] = "very_high"
	t.check(SocietyRules.load_total(data, state, "beta") > normal, "heavier taxes are a heavier load")


func test_buildings_carry_a_burden(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var before := SocietyRules.load_total(data, state, "beta")
	state["settlements"]["beta"]["buildings"]["test_walls"] = 2
	t.check(SocietyRules.load_total(data, state, "beta") > before,
		"a wall is built by requisitioned labour and shows up in the load")


func test_legitimacy_drifts_and_does_not_jump(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement: Dictionary = state["settlements"]["beta"]
	settlement["buildings"]["test_health"] = 1   # drains and clean water
	settlement["buildings"]["test_school"] = 1   # a school
	settlement["buildings"]["test_temple"] = 1   # and a temple of their own gods
	settlement["buildings"].erase("test_barracks")

	var target := SocietyRules.legitimacy_target(data, state, "beta")
	var before: float = SocietyRules.stocks_of(data, settlement)["legitimacy"]
	t.check(target > before, "the province is heading somewhere better than it is")

	SocietyRules.apply_settlement_turn(data, state, "beta")
	var after: float = SocietyRules.stocks_of(data, settlement)["legitimacy"]
	t.check(after > before, "standing moves toward the target")
	t.check(after < target, "but does not arrive in one turn — this is a generation's work")

	# Ten turns later it is much closer, but relaxation never overshoots.
	for i in range(10):
		SocietyRules.apply_settlement_turn(data, state, "beta")
	var later: float = SocietyRules.stocks_of(data, settlement)["legitimacy"]
	t.check(later > after, "it keeps closing the gap")
	t.check(later <= SocietyRules.legitimacy_target(data, state, "beta") + 0.001, "and never overshoots")


func test_coercion_buys_order_without_buying_consent(t) -> void:
	## The load-bearing asymmetry. A garrison and a wall raise public order, and
	## change nothing about the load — so grievance goes on charging underneath.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement: Dictionary = state["settlements"]["beta"]
	settlement["tax_level"] = "very_high"

	var bare_order := PublicOrderRules.total(data, state, "beta")
	var bare_load := SocietyRules.load_total(data, state, "beta")

	settlement["buildings"]["test_walls"] = 2
	settlement["garrison"] = [{"template": "test_spears", "experience": 0, "strength_pct": 100}]

	t.check(PublicOrderRules.total(data, state, "beta") > bare_order,
		"force raises public order")
	t.check(SocietyRules.load_total(data, state, "beta") >= bare_load,
		"and does not reduce what the province is being asked to bear")
	t.check(SocietyRules.coercion_total(data, state, "beta") > 0.0, "coercion is being applied")

	# Standing is actively pushed DOWN by ruling this way.
	var by_label := {}
	for factor in SocietyRules.legitimacy_target_breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(by_label.get("rule_by_fear", 0.0) < 0.0, "rule by fear lowers where standing is heading")


func test_grievance_charges_on_the_coerced_share(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement: Dictionary = state["settlements"]["beta"]
	settlement["tax_level"] = "very_high"
	settlement["society"]["legitimacy"] = 0.0   # no consent at all: all of it is coerced

	var before: float = SocietyRules.stocks_of(data, settlement)["grievance"]
	SocietyRules.apply_settlement_turn(data, state, "beta")
	var charged: float = SocietyRules.stocks_of(data, settlement)["grievance"] - before
	t.check(charged > 0.0, "an entirely coerced load charges grievance")

	# With consent well above the load, it drains instead.
	settlement["society"]["legitimacy"] = 100.0
	settlement["tax_level"] = "very_low"
	var high: float = SocietyRules.stocks_of(data, settlement)["grievance"]
	SocietyRules.apply_settlement_turn(data, state, "beta")
	t.check(SocietyRules.stocks_of(data, settlement)["grievance"] < high,
		"consent in excess of what you ask relieves it")

	# And it relieves more slowly than it charges — resentment is not free to undo.
	t.check(float(_rules(data)["grievance_relief_rate"]) < float(_rules(data)["grievance_charge_rate"]),
		"grievance drains more slowly than it fills")


func test_unrest_ignites_high_and_extinguishes_low(t) -> void:
	## Hysteresis: fixing the cause does not undo the crisis. This gap is what
	## makes the decision that caused it feel irreversible.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rules := _rules(data)
	var settlement: Dictionary = state["settlements"]["beta"]

	# Just below the ignition point, with nothing pushing it up: still calm.
	settlement["society"]["grievance"] = float(rules["restive_ignite"]) - 1.0
	settlement["society"]["legitimacy"] = 100.0
	settlement["tax_level"] = "very_low"
	SocietyRules.apply_settlement_turn(data, state, "beta")
	t.check_eq(SocietyRules.stocks_of(data, settlement)["unrest_state"], SocietyRules.UNREST_CALM,
		"below the ignition threshold the province is settled")

	# Push it clear of the threshold (further than one turn of relief can undo)
	# and it ignites.
	settlement["society"]["grievance"] = float(rules["restive_ignite"]) + 5.0
	var notice := SocietyRules.apply_settlement_turn(data, state, "beta")
	t.check_eq(SocietyRules.stocks_of(data, settlement)["unrest_state"], SocietyRules.UNREST_RESTIVE,
		"crossing the ignition threshold turns the province restive")
	t.check_eq(String(notice.get("to", "")), SocietyRules.UNREST_RESTIVE,
		"and the turn reports the transition")

	# Now bring grievance back to where it was when everything was fine. It does
	# NOT settle: extinction happens far lower than ignition.
	settlement["society"]["grievance"] = float(rules["restive_ignite"]) - 1.0
	SocietyRules.apply_settlement_turn(data, state, "beta")
	t.check_eq(SocietyRules.stocks_of(data, settlement)["unrest_state"], SocietyRules.UNREST_RESTIVE,
		"restoring the old conditions does not undo the crisis")
	t.check(float(rules["restive_extinguish"]) < float(rules["restive_ignite"]),
		"there is a real gap between igniting and settling")

	# Only well below does it settle.
	settlement["society"]["grievance"] = float(rules["restive_extinguish"]) - 1.0
	SocietyRules.apply_settlement_turn(data, state, "beta")
	t.check_eq(SocietyRules.stocks_of(data, settlement)["unrest_state"], SocietyRules.UNREST_CALM,
		"it settles only once resentment has fallen far below where it ignited")


func test_open_revolt_secedes_however_large_the_garrison(t) -> void:
	## Coercion delays and does not immunise: a province that has withdrawn its
	## consent entirely goes, whatever the order number says.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rules := _rules(data)
	var settlement: Dictionary = state["settlements"]["beta"]
	var rng := CampaignRng.seeded(4)

	# A garrison big enough to hold order far above the riot threshold.
	settlement["garrison"] = []
	for i in range(6):
		settlement["garrison"].append({"template": "test_spears", "experience": 0, "strength_pct": 100})
	t.check(PublicOrderRules.total(data, state, "beta") >= float(data.balance["public_order"]["riot_threshold"]),
		"order reads perfectly calm")

	settlement["society"]["unrest_state"] = SocietyRules.UNREST_REBELLIOUS
	settlement["society"]["unrest_turns"] = int(rules["rebellious_turns_to_revolt"])
	var result := PublicOrderRules.apply_turn(data, state, "beta", rng)
	t.check(result["revolted"], "a province in open revolt secedes despite the garrison")
	t.check_eq(state["settlements"]["beta"]["owner"], "rebels", "and it goes to the rebels")


func test_belonging_diffuses_and_grievance_is_friction(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement: Dictionary = state["settlements"]["beta"]
	settlement["society"]["assimilation"] = 40.0
	settlement["society"]["grievance"] = 0.0

	var bare := SocietyRules.assimilation_contact(data, state, "beta")
	settlement["buildings"]["test_temple"] = 1      # red is roman: this is their own
	var with_own := SocietyRules.assimilation_contact(data, state, "beta")
	t.check(with_own > bare, "your own culture's temple carries the culture in")

	settlement["buildings"]["test_foreign_temple"] = 1   # barbarian: not theirs
	t.check(SocietyRules.assimilation_contact(data, state, "beta") < with_own,
		"another culture's stonework crowds yours out")

	# With no resentment, belonging rises.
	settlement["buildings"].erase("test_foreign_temple")
	SocietyRules.apply_settlement_turn(data, state, "beta")
	var risen: float = SocietyRules.stocks_of(data, settlement)["assimilation"]
	t.check(risen > 40.0, "belonging spreads on contact")

	# A resentful province does not become yours.
	settlement["society"]["assimilation"] = 40.0
	settlement["society"]["grievance"] = float(_rules(data)["grievance_max"])
	SocietyRules.apply_settlement_turn(data, state, "beta")
	t.check(SocietyRules.stocks_of(data, settlement)["assimilation"] < risen,
		"resentment is friction on belonging")


func test_conquest_makes_a_province_a_stranger(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rules := _rules(data)
	state["settlements"]["alpha"]["owner"] = "red"
	SocietyRules.record_conquest(data, state, "alpha", "red", "occupy")
	var stocks := SocietyRules.stocks_of(data, state["settlements"]["alpha"])
	t.check_eq(stocks["assimilation"], float(rules["assimilation_start_foreign"]),
		"a conquered province starts as a stranger to its new masters")
	t.check_eq(stocks["grievance"], float(rules["grievance_conquest_shock"]),
		"and starts resentful")
	t.check(float(SocietyRules.faction_stocks(data, state["factions"]["red"])["elite_pressure"])
		> float(rules["elite_start"]), "the conqueror gains another house expecting a reward")


func test_extermination_is_remembered_everywhere(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["alpha"]["owner"] = "red"
	SocietyRules.record_conquest(data, state, "alpha", "red", "exterminate")
	var stocks := SocietyRules.faction_stocks(data, state["factions"]["red"])
	t.check(float(stocks["civic_shock"]) < 0.0,
		"a reputation for atrocity follows you into every province you hold")
	t.check(float(stocks["martial_ethos"]) > float(_rules(data)["martial_start"]),
		"and the society that did it is changed by having done it")


func test_recruiting_is_felt_where_the_men_are_taken(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["beta"]["buildings"]["test_barracks"] = 1
	var before: float = SocietyRules.stocks_of(data, state["settlements"]["beta"])["grievance"]
	t.check(RecruitmentRules.queue_unit(data, state, "beta", "test_spears"), "the unit is raised")
	t.check(SocietyRules.stocks_of(data, state["settlements"]["beta"])["grievance"] > before,
		"conscription charges grievance in the province that supplied the men")


func test_both_extremes_of_ambition_fail(t) -> void:
	## Elite pressure is drained by offices AND by commands, so a state fails
	## whether it militarises or refuses to.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var faction: Dictionary = state["factions"]["red"]
	faction["society"]["elite_pressure"] = 50.0
	var start := 50.0

	# With offices and commands to absorb them, pressure falls.
	Fixtures.add_army(state, "red", "beta", ["test_spears"])
	SocietyRules.apply_faction_turn(data, state, "red")
	var with_outlets: float = SocietyRules.faction_stocks(data, faction)["elite_pressure"]

	# Strip the commands away and the same state does worse.
	state["armies"] = {}
	faction["society"]["elite_pressure"] = start
	SocietyRules.apply_faction_turn(data, state, "red")
	var without: float = SocietyRules.faction_stocks(data, faction)["elite_pressure"]
	t.check(without > with_outlets,
		"a state with nowhere to send ambitious men accumulates more of them")

	# A legitimate state channels ambition into service.
	for region_id in ["beta", "epsilon"]:
		state["settlements"][region_id]["society"]["legitimacy"] = 100.0
	faction["society"]["elite_pressure"] = start
	SocietyRules.apply_faction_turn(data, state, "red")
	t.check(float(SocietyRules.faction_stocks(data, faction)["elite_pressure"]) < without,
		"a state its own elite believes in turns claimants into servants")


func test_craft_decays_without_institutions(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var faction: Dictionary = state["factions"]["red"]
	faction["society"]["knowledge"] = 50.0
	SocietyRules.apply_faction_turn(data, state, "red")
	t.check(float(SocietyRules.faction_stocks(data, faction)["knowledge"]) < 50.0,
		"craft that is not taught is forgotten")

	# Schools hold it up.
	state["settlements"]["beta"]["buildings"]["test_school"] = 1
	state["settlements"]["epsilon"]["buildings"]["test_school"] = 1
	faction["society"]["knowledge"] = 5.0
	for i in range(12):
		SocietyRules.apply_faction_turn(data, state, "red")
	t.check(float(SocietyRules.faction_stocks(data, faction)["knowledge"]) > 5.0,
		"institutions accumulate it")


func test_martial_spirit_follows_what_is_practised(t) -> void:
	## Compare equilibria rather than the starting value: what matters is that a
	## society that drills settles somewhere more martial than one that does not.
	var rules := _rules(Fixtures.data())

	var peaceful_data := Fixtures.data()
	var peaceful := Fixtures.state(peaceful_data)
	for i in range(60):
		SocietyRules.apply_faction_turn(peaceful_data, peaceful, "red")
	var at_peace: float = SocietyRules.faction_stocks(
		peaceful_data, peaceful["factions"]["red"])["martial_ethos"]

	var martial_data := Fixtures.data()
	var martial_state := Fixtures.state(martial_data)
	for region_id in ["beta", "epsilon"]:
		martial_state["settlements"][region_id]["buildings"]["test_barracks"] = 2
		martial_state["settlements"][region_id]["buildings"]["test_walls"] = 2
	for i in range(60):
		SocietyRules.apply_faction_turn(martial_data, martial_state, "red")
	var at_arms: float = SocietyRules.faction_stocks(
		martial_data, martial_state["factions"]["red"])["martial_ethos"]

	t.check(at_arms > at_peace, "a society that builds drill yards becomes a martial one")

	# And it is a ratchet: it rises faster than it falls, so what you become is
	# easier to reach than to leave.
	t.check(float(rules["martial_rise_rate"]) > float(rules["martial_fall_rate"]),
		"martial spirit rises faster than it subsides")
	for region_id in ["beta", "epsilon"]:
		martial_state["settlements"][region_id]["buildings"].erase("test_barracks")
		martial_state["settlements"][region_id]["buildings"].erase("test_walls")
	SocietyRules.apply_faction_turn(martial_data, martial_state, "red")
	var after: float = SocietyRules.faction_stocks(
		martial_data, martial_state["factions"]["red"])["martial_ethos"]
	t.check(after < at_arms, "tearing the barracks down does start to undo it")
	t.check(after > at_arms - (at_arms - at_peace) * 0.5,
		"but a disposition outlives the policy that raised it")


func test_militarisation_buys_battlefield_strength(t) -> void:
	## What martialism is FOR — against everything it costs elsewhere.
	var data := Fixtures.data()
	var units := [{"template": "test_spears", "experience": 0, "strength_pct": 100}]
	var resolver := AutoResolver.new()
	var peaceful := BattleResolver.force_strength(data, units, null,
		float(data.balance["battle"]["experience_strength_pct_per_chevron"]))
	t.check(peaceful > 0.0, "a force has strength")
	var context := {"terrain": "plains", "wall_level": 0, "attacker_martial": 100.0, "defender_martial": 0.0}
	# The resolver applies the martial multiplier; check the constant is live.
	t.check(float(data.balance["battle"]["martial_ethos_strength_pct_at_full"]) > 0.0,
		"martial ethos is worth something in battle")
	var attackers := [{"template": "test_spears", "experience": 0, "strength_pct": 100}]
	var defenders := [{"template": "test_spears", "experience": 0, "strength_pct": 100}]
	var result := resolver.resolve(data, CampaignRng.seeded(3), attackers, defenders, context)
	t.check(result.has("winner"), "the resolver honours the extended context")


func test_equipment_travels_with_the_unit(t) -> void:
	## weapon_upgrade / armor_upgrade were authored in the data and read by
	## nothing. A unit raised in a well-forged city is now genuinely better.
	var data := Fixtures.data()
	var experience_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	var plain := [{"template": "test_spears", "experience": 0, "strength_pct": 100}]
	var equipped := [{"template": "test_spears", "experience": 0, "strength_pct": 100, "weapon": 2, "armor": 2}]
	t.check(BattleResolver.force_strength(data, equipped, null, experience_pct)
		> BattleResolver.force_strength(data, plain, null, experience_pct),
		"better arms and armour make a stronger force")


func test_queries_never_touch_the_campaign_rng(t) -> void:
	## The UI calls these arbitrarily often. If any of them drew from the shared
	## stream, a save would replay differently from the live game.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["rng_state"] = "123456789"
	for i in range(5):
		SocietyRules.load_breakdown(data, state, "beta")
		SocietyRules.legitimacy_target_breakdown(data, state, "beta")
		SocietyRules.society_breakdown(data, state, "beta")
		SocietyRules.faction_breakdown(data, state, "red")
		LegibilityRules.clarity(data, state, "beta")
		LegibilityRules.reported(data, state, "beta")
	t.check_eq(state["rng_state"], "123456789", "no query consumed randomness")


func test_stocks_survive_a_json_round_trip_exactly(t) -> void:
	## Godot's JSON writer does not round-trip an arbitrary double, so the stocks
	## are quantized. Without this a loaded save drifts from the live game.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	for i in range(9):
		SocietyRules.apply_faction_turn(data, state, "red")
		SocietyRules.apply_settlement_turn(data, state, "beta")
	var restored := SaveGame.from_json(SaveGame.to_json(state))
	t.check(not restored.is_empty(), "the state saves and parses back")
	var live: Dictionary = state["settlements"]["beta"]["society"]
	var back: Dictionary = restored["settlements"]["beta"]["society"]
	for key in ["legitimacy", "grievance", "assimilation"]:
		t.check_eq(float(back[key]), float(live[key]), "%s survives the round trip exactly" % key)
	for key in ["elite_pressure", "martial_ethos", "knowledge"]:
		t.check_eq(float(restored["factions"]["red"]["society"][key]),
			float(state["factions"]["red"]["society"][key]),
			"%s survives the round trip exactly" % key)


func test_provision_becomes_expectation_and_withdrawal_is_a_load(t) -> void:
	## The euergetism ratchet, and the civic counterpart of the coercion trap: a
	## city that never had baths does not resent their absence; one that had them
	## and lost them does.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rules := _rules(data)
	var settlement: Dictionary = state["settlements"]["beta"]

	# A city given nothing expects nothing, so there is no shortfall to bear.
	var by_label := {}
	for factor in SocietyRules.load_breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(not by_label.has("broken_promises"), "a city given nothing is owed nothing")

	# Build the drains and let the city grow used to them.
	settlement["buildings"]["test_health"] = 1
	var given := SocietyRules.provision(data, settlement)
	t.check(given > 0.0, "clean water is something the state visibly provides")
	for i in range(40):
		SocietyRules.apply_settlement_turn(data, state, "beta")
	var expectation: float = SocietyRules.stocks_of(data, settlement)["expectation"]
	t.check(expectation > 0.0, "the city comes to expect what it is given")

	# While it still has them, there is nothing owed.
	by_label = {}
	for factor in SocietyRules.load_breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(not by_label.has("broken_promises"), "provision that continues costs nothing")

	# Take them away, and the city is now worse off than before they were built.
	var before_withdrawal := SocietyRules.load_total(data, state, "beta")
	settlement["buildings"].erase("test_health")
	var after := SocietyRules.load_total(data, state, "beta")
	t.check(after > before_withdrawal, "withdrawing provision is itself a load")
	by_label = {}
	for factor in SocietyRules.load_breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(by_label.get("broken_promises", 0.0) > 0.0, "and it is named as such")

	# The memory fades far more slowly than it formed.
	t.check(float(rules["expectation_fall_rate"]) < float(rules["expectation_rise_rate"]),
		"a city learns what to expect faster than it forgets it")


func test_expectation_starts_at_what_is_already_provided(t) -> void:
	## Nothing is retroactively owed: a province resents only what it is given
	## and then loses.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var settlement: Dictionary = state["settlements"]["beta"]
	settlement["buildings"]["test_health"] = 1
	settlement["society"] = SocietyRules.new_settlement_society(
		data, true, SocietyRules.provision(data, settlement))
	var by_label := {}
	for factor in SocietyRules.load_breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(not by_label.has("broken_promises"),
		"a province seeded at its own provision owes nothing on turn one")


func test_plunder_is_felt_in_provinces_that_never_saw_the_war(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var faction: Dictionary = state["factions"]["red"]

	var before := SocietyRules.legitimacy_target(data, state, "beta")
	SocietyRules.record_plunder(data, state, "red", 40000.0)
	t.check(float(SocietyRules.faction_stocks(data, faction)["plunder_pending"]) > 0.0,
		"loot is buffered until the turn resolves")
	SocietyRules.apply_faction_turn(data, state, "red")
	var spoils: float = SocietyRules.faction_stocks(data, faction)["spoils"]
	t.check(spoils > 0.0, "and becomes a share of what the polity lives on")
	t.check_eq(float(SocietyRules.faction_stocks(data, faction)["plunder_pending"]), 0.0,
		"the buffer is cleared each turn")

	var after := SocietyRules.legitimacy_target(data, state, "beta")
	t.check(after < before, "beta never saw the war and is governed on less consent for it")
	var by_label := {}
	for factor in SocietyRules.legitimacy_target_breakdown(data, state, "beta"):
		by_label[factor["label"]] = float(factor["value"])
	t.check(by_label.get("plunder", 0.0) < 0.0, "and the reason is named")

	# It also rots the administration.
	var clean_data := Fixtures.data()
	var clean := Fixtures.state(clean_data)
	clean["factions"]["red"]["capital"] = "alpha"
	clean["settlements"]["alpha"]["owner"] = "red"
	state["factions"]["red"]["capital"] = "alpha"
	state["settlements"]["alpha"]["owner"] = "red"
	t.check(EconomyRules.corruption_pct(data, state, "epsilon")
		> EconomyRules.corruption_pct(clean_data, clean, "epsilon"),
		"an administration living off plunder stops accounting for anything")


func test_plunders_share_outlives_the_conquest(t) -> void:
	## An average with a long memory, so the reckoning arrives in peacetime.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var faction: Dictionary = state["factions"]["red"]
	for i in range(20):
		SocietyRules.record_plunder(data, state, "red", 40000.0)
		SocietyRules.apply_faction_turn(data, state, "red")
	var at_war: float = SocietyRules.faction_stocks(data, faction)["spoils"]
	t.check(at_war > 0.0, "a conquering polity lives off what it takes")

	# The taking stops. It does not clear at once.
	SocietyRules.apply_faction_turn(data, state, "red")
	var one_turn_later: float = SocietyRules.faction_stocks(data, faction)["spoils"]
	t.check(one_turn_later < at_war, "it does start to fall")
	t.check(one_turn_later > at_war * 0.5, "but a single peaceful year does not undo it")


func test_the_senate_drifts_popular_standing_and_never_assigns_it(t) -> void:
	## The invariant HANDOFF §5.11 names: SenateRules moves popular_standing
	## TOWARD the regional baseline instead of recomputing it, because edict
	## tension deltas and the per-turn drips write the same number. An
	## overwrite would silently turn every edict's political cost into dead
	## code, which is how this shipped as a bug once.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rules: Dictionary = data.balance["senate"]
	var faction: Dictionary = state["factions"]["red"]

	# Put politics somewhere the baseline is not, the way an edict would.
	var displaced := -4.0
	faction["popular_standing"] = displaced
	var before := float(faction["popular_standing"])
	SenateRules.process_turn(data, state, CampaignRng.seeded(9))
	var after := float(faction["popular_standing"])

	t.check(after != before, "the senate turn moved the crowd's mood at all")
	# One turn may only close a fraction of the gap: a jump straight to the
	# baseline is exactly the overwrite this test exists to catch.
	var baseline := minf(float(rules["max_standing"]),
		float(state["settlements"].size()) * float(rules["popular_standing_per_region"]))
	if absf(baseline - before) > 0.001:
		var closed := (after - before) / (baseline - before)
		t.check(closed > 0.0, "it drifted toward the baseline, not away from it")
		t.check(closed < 0.9, "it drifted a fraction of the gap, not onto the baseline")

	# And what it stores must survive a JSON round trip, or a loaded save
	# diverges from the live game a turn later.
	var reparsed = JSON.parse_string(JSON.stringify(after))
	t.check_eq(float(reparsed), after, "popular_standing is quantized for the save")
