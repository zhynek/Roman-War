extends RefCounted
## Legibility: a state can only act on what it can see, and seeing is
## infrastructure. Clarity is derived from distance, roads, the government tier
## and whether anyone of yours is standing there — and it decides whether the
## player is shown live figures, a stale rounded survey, or only rumour.
## None of it consumes randomness.


func test_clarity_falls_with_distance_and_is_bought_back(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# red's capital is beta; the fixture map is a line alpha-beta-gamma-delta-epsilon.
	t.check_eq(LegibilityRules.clarity(data, state, "beta"), 1.0, "the capital is seen perfectly")

	state["settlements"]["delta"] = state["settlements"]["epsilon"].duplicate(true)
	state["settlements"]["delta"]["buildings"] = {"test_government": 1}
	var far := LegibilityRules.clarity(data, state, "delta")
	t.check(far < 1.0, "a distant province is seen less well")

	# Roads and a larger government buy the sight back.
	state["settlements"]["delta"]["buildings"] = {"test_government": 4}
	t.check(LegibilityRules.clarity(data, state, "delta") > far,
		"administration is what lets the centre see its own edges")


func test_a_governor_sharpens_the_picture(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["epsilon"]["buildings"] = {"test_government": 1}
	var blind := LegibilityRules.clarity(data, state, "epsilon")
	Fixtures.add_character(state, "red", "steward", {"location": "epsilon", "management": 8})
	SettlementRules.refresh_governors(data, state)
	t.check(LegibilityRules.clarity(data, state, "epsilon") > blind,
		"someone of yours standing there reports better than nobody")


func test_well_governed_provinces_report_exactly(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var report := LegibilityRules.reported(data, state, "beta")
	t.check_eq(report["level"], LegibilityRules.LEVEL_EXACT, "the capital reports exactly")
	t.check(report["exact"], "and says so")
	t.check_eq(int(report["stale_turns"]), 0, "with no lag")
	var live := SocietyRules.stocks_of(data, state["settlements"]["beta"])
	t.check_eq(float(report["legitimacy"]), float(live["legitimacy"]), "the figure is the live stock")


func test_a_barely_governed_province_yields_only_rumour(t) -> void:
	## The island the land network cannot reach: no road, no records, nobody of
	## yours standing there. You have opinions about it, not information.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rules: Dictionary = data.balance["society"]
	state["settlements"]["island"] = state["settlements"]["epsilon"].duplicate(true)
	state["settlements"]["island"]["buildings"] = {"test_government": 1}
	state["settlements"]["island"]["governor"] = null

	t.check(LegibilityRules.clarity(data, state, "island")
		< float(rules["clarity_banded_threshold"]), "there is no way for word to travel")
	LegibilityRules.refresh_surveys(data, state, ["island"])
	state["turn"] = 20
	var report := LegibilityRules.reported(data, state, "island")
	t.check_eq(report["level"], LegibilityRules.LEVEL_RUMOUR, "the province reports only rumour")
	t.check_eq(report["legitimacy"], null, "no figures at all")
	t.check(String(report["unrest_state"]) != "", "only what is said about the place")
	t.check(LegibilityRules.reported_breakdown(data, state, "island").is_empty(),
		"and the panel is given nothing to render")
	t.check(LegibilityRules.clarity(data, state, "island") >= float(rules["clarity_min"]),
		"clarity never falls below its floor")


func test_a_middling_province_reports_a_stale_rounded_survey(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rules: Dictionary = data.balance["society"]
	state["settlements"]["alpha"]["owner"] = "red"
	state["factions"]["red"]["capital"] = "alpha"
	state["settlements"]["epsilon"]["buildings"] = {"test_government": 1}
	state["settlements"]["epsilon"]["governor"] = null

	var clarity := LegibilityRules.clarity(data, state, "epsilon")
	t.check(clarity >= float(rules["clarity_banded_threshold"])
		and clarity < float(rules["clarity_exact_threshold"]),
		"four hops out with a small government hall is a middling province")

	LegibilityRules.refresh_surveys(data, state, ["epsilon"])
	state["settlements"]["epsilon"]["society"]["legitimacy"] = 77.0
	state["turn"] = 6
	var report := LegibilityRules.reported(data, state, "epsilon")
	t.check_eq(report["level"], LegibilityRules.LEVEL_BANDED, "it reports a survey")
	t.check(int(report["stale_turns"]) > 0, "and the survey is out of date")
	var band := float(rules["clarity_band_size"])
	t.check_near(fmod(float(report["legitimacy"]), band), 0.0, 0.001, "rounded to the band")
	t.check(float(report["legitimacy"]) != 77.0,
		"you are reading the survey, not the province")


func test_surveys_are_taken_less_often_where_you_see_less(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check_eq(LegibilityRules.survey_interval(data, state, "beta"), 1,
		"a well-run province reports every turn")
	state["settlements"]["epsilon"]["buildings"] = {"test_government": 1}
	state["factions"]["red"]["capital"] = "alpha"
	state["settlements"]["alpha"]["owner"] = "red"
	t.check(LegibilityRules.survey_interval(data, state, "epsilon") > 1,
		"a distant one reports when word happens to arrive")


func test_reading_the_province_consumes_no_randomness(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["rng_state"] = "987654321"
	for i in range(8):
		LegibilityRules.clarity(data, state, "beta")
		LegibilityRules.level_for(data, state, "beta")
		LegibilityRules.reported(data, state, "beta")
		LegibilityRules.survey_interval(data, state, "beta")
	t.check_eq(state["rng_state"], "987654321",
		"partial observability is lag, not dice — it must replay identically")
