extends RefCounted
## Phase 7 politics: the cursus honorum. The synthetic world gains a Senate
## and a second Roman house so "by standing" has something to compare, and
## the real offices table (the content the tests guard) fills the ladder.


func _world() -> Dictionary:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_senate(data, state)
	Fixtures.add_house(data, state, "green", "delta")
	return {"data": data, "state": state}


func _men(state: Dictionary) -> void:
	## Red (standing 8) fields an elder, a rising man and a youth; green
	## (standing 2) fields one elder of great personal weight.
	state["factions"]["red"]["senate_standing"] = 8.0
	state["factions"]["green"]["senate_standing"] = 2.0
	Fixtures.add_character(state, "red", "red_elder", {"role": "leader", "age": 50, "influence": 5, "location": "beta"})
	Fixtures.add_character(state, "red", "red_rising", {"role": "heir", "age": 34, "influence": 3, "location": "beta"})
	Fixtures.add_character(state, "red", "red_young", {"age": 21, "influence": 1, "location": "beta"})
	Fixtures.add_character(state, "red", "red_wife", {"role": "spouse", "gender": "female", "age": 40, "influence": 9, "location": "beta"})
	Fixtures.add_character(state, "green", "green_elder", {"role": "leader", "age": 52, "influence": 9, "location": "delta"})


func _office_of(state: Dictionary, char_id: String) -> String:
	var office = state["characters"][char_id].get("office")
	return "" if office == null else String(office)


func _count(notices: Array, kind: String) -> int:
	var n := 0
	for notice in notices:
		if String(notice.get("kind", "")) == kind:
			n += 1
	return n


func test_offices_table_is_a_strict_ladder(t) -> void:
	var data := Fixtures.data()
	t.check_eq(data.offices.size(), 6, "six magistracies")
	var ranks := {}
	var seats := 0
	for office in data.offices.values():
		ranks[int(office["rank"])] = true
		seats += int(office["seats"])
		t.check(int(office.get("requires_prior_rank", 0)) < int(office["rank"]),
			"%s requires a lower rung" % office["id"])
		for key in office["effects"]:
			t.check(["command", "management", "influence"].has(String(key)),
				"%s effect %s is an attribute" % [office["id"], key])
	t.check_eq(ranks.size(), 6, "ranks are unique")
	t.check_eq(seats, 12, "twelve seats in the Republic")


func test_summer_election_seats_by_standing_then_influence(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	var notices := SenateRules.process_turn(data, state, CampaignRng.seeded(3))

	# Scores: red_elder 13, green_elder 11 (older than red_rising's 11),
	# red_rising 11, red_young 9. Nobody has climbed the ladder yet, so the
	# censorship and the consulships go to suffects in score order, highest
	# office first.
	t.check_eq(_office_of(state, "red_elder"), "censor", "the highest score takes the censorship")
	t.check_eq(_office_of(state, "green_elder"), "consul", "a great man of a lesser house takes a consulship")
	t.check_eq(_office_of(state, "red_rising"), "consul", "the next man the other")
	t.check_eq(_office_of(state, "red_young"), "quaestor", "the youth starts as quaestor")
	t.check_eq(_office_of(state, "red_wife"), "", "wives do not stand")
	t.check_eq(_count(notices, "office_gained"), 4, "four men took office")
	t.check_eq(CharacterRules.effective(data, state["characters"]["red_elder"], "influence"), 5 + 1,
		"a censor's influence carries the office's weight")
	t.check_eq(CharacterRules.effective(data, state["characters"]["red_elder"], "management"), 2 + 2,
		"and its authority over the rolls")
	t.check_eq(CharacterRules.effective(data, state["characters"]["red_rising"], "command"), 2 + 2,
		"a consul holds imperium")
	t.check_eq(state["characters"]["red_elder"]["offices_held"], ["censor"], "the career is remembered")
	t.check_eq(int(state["characters"]["red_elder"]["deeds"].get("offices_held", 0)), 1, "and counted as a deed")
	var recorded := 0
	for entry in state["chronicle"]:
		if String(entry["kind"]) == "office_taken":
			recorded += 1
			t.check(entry["subjects"].has("office"), "the annals name the office")
	t.check_eq(recorded, 3, "the higher magistracies (praetor and up) make the annals; the quaestor does not")
	# The fixture world keeps its own synthetic annals; borrow the real prose.
	var real_annals: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/annals.json"))["templates"]
	data.annals["office_taken"] = real_annals["office_taken"]
	var line := ChronicleRules.render_entry(data, state, state["chronicle"][0])
	t.check(line.contains("Censor") or line.contains("Consul"), "the annals print the office by name: " + line)


func test_no_election_in_winter(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	state["season"] = "winter"
	var notices := SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	t.check_eq(_count(notices, "office_gained"), 0, "the Senate elects in summer only")
	t.check_eq(_office_of(state, "red_elder"), "", "no seats filled")


func test_reelection_keeps_the_seat_without_new_laurels(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	var second := SenateRules.process_turn(data, state, CampaignRng.seeded(4))
	t.check_eq(_office_of(state, "red_elder"), "censor", "the censor is returned")
	t.check_eq(_count(second, "office_gained"), 0, "a returned man gains nothing new")
	t.check_eq(state["characters"]["red_elder"]["offices_held"], ["censor"], "the career lists the office once")


func test_death_vacates_a_seat_and_the_cursus_promotes(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	CharacterRules.kill(state, "red_elder", data)
	t.check_eq(_office_of(state, "red_elder"), "", "dead men hold no office")
	# Next summer the censorship is open. Both consuls have climbed to it on
	# the ladder; equal scores, so the elder takes it and the other keeps
	# his consulship.
	SenateRules.process_turn(data, state, CampaignRng.seeded(5))
	t.check_eq(_office_of(state, "green_elder"), "censor", "the elder consular climbs to censor")
	t.check_eq(_office_of(state, "red_rising"), "consul", "the younger keeps the consulship")
	t.check(state["characters"]["green_elder"]["offices_held"].has("consul")
		and state["characters"]["green_elder"]["offices_held"].has("censor"), "the career records both rungs")


func test_a_house_at_civil_war_holds_no_office(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	state["factions"]["green"]["at_civil_war"] = true
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	t.check_eq(_office_of(state, "green_elder"), "", "a house in arms against the Republic is barred")
	t.check_eq(_office_of(state, "red_rising"), "consul", "its seat goes to the loyal")
	t.check(SenateRules.eligible_offices(data, state, "green_elder").is_empty(), "and it may not stand")


func test_the_senates_fall_dissolves_the_offices(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	state["factions"]["senate"]["alive"] = false
	var notices := SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	t.check_eq(_count(notices, "office_gained"), 0, "no Senate, no election")
	t.check_eq(_office_of(state, "red_elder"), "", "the Republic's magistracies end with it")


func test_eligibility_reads_the_ladder_honestly(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	var before := SenateRules.eligible_offices(data, state, "red_rising")
	var by_id := {}
	for entry in before:
		by_id[entry["office"]] = entry["on_ladder"]
	t.check(by_id.has("consul") and not by_id["consul"], "a man of 34 may stand for consul only as a suffect")
	t.check(by_id.has("quaestor") and by_id["quaestor"], "and for quaestor outright")
	t.check(not by_id.has("censor"), "the censorship waits on his age")
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	var after := SenateRules.eligible_offices(data, state, "red_rising")
	var seen_consul := false
	for entry in after:
		if entry["office"] == "consul":
			seen_consul = true
			t.check(entry["on_ladder"], "a consular stands for consul on the ladder")
	t.check(seen_consul, "the consulship is on his list")


func test_election_notices_and_the_family_share_the_report(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	var report := game.end_turn()
	t.check(_count(report["senate"], "office_gained") >= 3, "the Senate's news carries the elections")
	for notice in report["senate"]:
		t.check(not ["trait", "ancillary"].has(String(notice.get("kind", ""))),
			"a trait earned in office is the family's news, not the Senate's")


func test_elections_replay_and_survive_a_save(t) -> void:
	var first := _world()
	var second := _world()
	for world in [first, second]:
		_men(world["state"])
		# The fixture factions carry no reign ledger (a real campaign builds
		# one); normalize both worlds the way a loaded save is normalized so
		# the lockstep compares the Republic, not the fixture's gaps.
		NewGame.ensure_state_keys(world["state"], world["data"])
	var games: Array = []
	for world in [first, second]:
		var game := Game.new()
		game.data = world["data"]
		game.state = world["state"]
		game.resolver = AutoResolver.new()
		games.append(game)
	for i in range(3):
		for game in games:
			game.end_turn()
	t.check_eq(JSON.stringify(games[0].state), JSON.stringify(games[1].state),
		"two identical worlds elect identically")
	var restored := SaveGame.from_json(SaveGame.to_json(games[0].state))
	NewGame.ensure_state_keys(restored, games[0].data)
	var resumed := Game.new()
	resumed.data = games[0].data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored
	games[0].end_turn()
	resumed.end_turn()
	t.check_eq(_canonical(games[0].state), _canonical(resumed.state), "a saved Republic marches in step")


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))


func test_seats_absorb_ambition(t) -> void:
	## Two identical houses, one with its men in office and one shut out of
	## the curia: the seated house ends the season with less Ambition, and the
	## society layer draws no randomness doing it.
	var seated := _world()
	var shut_out := _world()
	_men(seated["state"])
	_men(shut_out["state"])
	SenateRules.process_turn(seated["data"], seated["state"], CampaignRng.seeded(3))
	shut_out["state"]["season"] = "winter"
	SenateRules.process_turn(shut_out["data"], shut_out["state"], CampaignRng.seeded(3))
	t.check_eq(_office_of(shut_out["state"], "red_elder"), "", "the control house holds no seat")
	var rng_before: String = String(seated["state"]["rng_state"])
	SocietyRules.apply_faction_turn(seated["data"], seated["state"], "red")
	SocietyRules.apply_faction_turn(shut_out["data"], shut_out["state"], "red")
	var with_seats := float(SocietyRules.faction_stocks(seated["data"], seated["state"]["factions"]["red"])["elite_pressure"])
	var without := float(SocietyRules.faction_stocks(shut_out["data"], shut_out["state"]["factions"]["red"])["elite_pressure"])
	t.check(with_seats < without, "offices absorb ambition (%.3f with seats vs %.3f without)" % [with_seats, without])
	var society_rules: Dictionary = seated["data"].balance["society"]
	# The drain lands before the season's proportional decay, so the gap
	# between the two houses is the drain less one turn of decay on it.
	var expected_drain := float(society_rules["elite_office_absorption_per_seat_rank"]) * (6 + 5 + 1) \
		* (1.0 - float(society_rules["elite_decay_rate"]))
	t.check_near(without - with_seats, expected_drain, 0.0005, "by the summed rank of the seats held (censor, consul, quaestor)")
	t.check_eq(String(seated["state"]["rng_state"]), rng_before, "the society layer drew no randomness")
