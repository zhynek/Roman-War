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


## --- The Senate's demand, outlawry, and the civil war -----------------------

func _hated_and_great(state: Dictionary, faction_id: String) -> void:
	state["factions"][faction_id]["senate_standing"] = -6.0
	state["factions"][faction_id]["popular_standing"] = 6.0


func _charge_kind(data: GameData, state: Dictionary, faction_id: String) -> String:
	var mission = state["factions"][faction_id]["mission"]
	if mission == null:
		return ""
	return String(data.missions.get(String(mission["template"]), {}).get("kind", ""))


func test_the_senate_demands_a_life_when_a_house_is_great_and_hated(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	state["season"] = "winter"
	# A standing charge is swept aside by the demand.
	state["factions"]["red"]["mission"] = {"template": "annex_border_province", "turns_left": 6, "target_region": "gamma"}
	data.missions["annex_border_province"] = {"id": "annex_border_province", "kind": "take_region",
		"deadline_turns": 10, "reward": {"treasury": 100}}
	data.missions["the_senate_demands_your_life"] = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/missions.json"))["missions"].filter(
			func(m): return m["id"] == "the_senate_demands_your_life")[0]
	_hated_and_great(state, "red")
	var notices := SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	t.check_eq(_charge_kind(data, state, "red"), "leader_suicide", "the Senate demands the patriarch's life")
	t.check_eq(String(state["factions"]["red"]["mission"]["target_character"]), "red_elder", "and names him")
	t.check_eq(_count(notices, "mission_voided"), 1, "the province charge is void — the Senate has one demand now")
	t.check_eq(_count(notices, "mission_issued"), 1, "the demand is proclaimed")
	# The demand stands while it runs; it is not reissued or replaced.
	var again := SenateRules.process_turn(data, state, CampaignRng.seeded(4))
	t.check_eq(_count(again, "mission_issued"), 0, "one demand at a time")
	t.check_eq(int(state["factions"]["red"]["mission"]["turns_left"]), 3, "the clock runs")


func test_the_demand_waits_while_the_senate_is_still_content(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	state["season"] = "winter"
	data.missions["the_senate_demands_your_life"] = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/missions.json"))["missions"].filter(
			func(m): return m["id"] == "the_senate_demands_your_life")[0]
	state["factions"]["red"]["senate_standing"] = -2.0
	state["factions"]["red"]["popular_standing"] = 6.0
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	t.check(_charge_kind(data, state, "red") != "leader_suicide", "a house the Senate still tolerates is not asked to die")
	state["factions"]["red"]["senate_standing"] = -6.0
	state["factions"]["red"]["popular_standing"] = 1.0
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	t.check(_charge_kind(data, state, "red") != "leader_suicide", "nor a hated house too small to frighten it")
	t.check(not state["factions"]["red"]["at_civil_war"], "and no civil war is forced on the standings alone")


func _demand_world() -> Dictionary:
	## A world where the Senate has just demanded red's patriarch.
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	state["season"] = "winter"
	data.missions["the_senate_demands_your_life"] = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/missions.json"))["missions"].filter(
			func(m): return m["id"] == "the_senate_demands_your_life")[0]
	_hated_and_great(state, "red")
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	return world


func test_complying_kills_the_patriarch_and_the_senate_relents(t) -> void:
	var world := _demand_world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	var standing_before := float(state["factions"]["red"]["senate_standing"])
	t.check(game.comply_senate_demand(), "the house may comply")
	t.check(not state["characters"]["red_elder"]["alive"], "the patriarch is dead")
	t.check_eq(String(state["characters"]["red_rising"]["role"]), "leader", "the heir succeeds at once")
	t.check(not game.comply_senate_demand(), "there is no complying twice")
	var notices := SenateRules.process_turn(data, state, CampaignRng.seeded(5))
	t.check_eq(_count(notices, "mission_complete"), 1, "the Senate counts the demand met")
	t.check_near(float(state["factions"]["red"]["senate_standing"]), standing_before + 2.0, 0.001,
		"and relents by the authored two points")
	t.check(not state["factions"]["red"]["at_civil_war"], "no civil war")
	t.check_eq(state["factions"]["red"]["mission"], null, "the demand is discharged")


func test_refusal_outlaws_the_house_and_the_houses_take_sides(t) -> void:
	# Green stands with the Senate (standing 2 is above the join line)...
	var loyal := _demand_world()
	# ...unless the Senate has alienated it too.
	var joins := _demand_world()
	joins["state"]["factions"]["green"]["senate_standing"] = 0.0
	joins["state"]["factions"]["green"]["mission"] = {"template": "annex_border_province", "turns_left": 6, "target_region": "alpha"}
	joins["data"].missions["annex_border_province"] = {"id": "annex_border_province", "kind": "take_region",
		"deadline_turns": 10, "reward": {"treasury": 100}}
	for world in [loyal, joins]:
		var data: GameData = world["data"]
		var state: Dictionary = world["state"]
		var notices: Array = []
		for i in range(4):
			notices = SenateRules.process_turn(data, state, CampaignRng.seeded(10 + i))
		var red: Dictionary = state["factions"]["red"]
		t.check(red["outlawed"], "the house that refuses is outlawed")
		t.check(red["at_civil_war"], "and at war with the Republic")
		t.check(DiplomacyRules.at_war(state, "red", "senate"), "war with the Senate")
		t.check_eq(red["mission"], null, "the demand is spent")
		t.check_eq(_count(notices, "mission_failed"), 1, "refusal is a failed charge")
		t.check_eq(_count(notices, "civil_war"), 1, "and the civil war is proclaimed")
		t.check_eq(_office_of(state, "red_elder"), "", "a rebel holds no office")
		var recorded := false
		for entry in state["chronicle"]:
			if String(entry["kind"]) == "civil_war":
				recorded = true
				t.check_eq(String(entry["details"].get("cause", "")), "outlawed", "the annals know why")
		t.check(recorded, "the chronicle opens the war")
	var loyal_state: Dictionary = loyal["state"]
	t.check(DiplomacyRules.at_war(loyal_state, "green", "red"), "a house in good standing fights for the Senate")
	t.check(not loyal_state["factions"]["green"]["at_civil_war"], "and is not itself in rebellion")
	var joined_state: Dictionary = joins["state"]
	t.check_eq(DiplomacyRules.stance_between(joined_state, "green", "red"), "alliance", "an alienated house marches with the rebel")
	t.check(DiplomacyRules.at_war(joined_state, "green", "senate"), "against the Senate")
	t.check(joined_state["factions"]["green"]["at_civil_war"], "in rebellion itself")
	t.check_eq(joined_state["factions"]["green"]["mission"], null, "its own charge void")
	t.check_eq(_office_of(joined_state, "green_elder"), "", "and its offices stripped")


func test_ambition_alone_still_forces_the_break(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	state["season"] = "winter"
	state["factions"]["red"]["society"]["elite_pressure"] = float(data.balance["society"]["elite_civil_war_threshold"]) + 1.0
	var notices := SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	t.check(state["factions"]["red"]["at_civil_war"], "too many claimants and the house breaks with the Senate")
	t.check(not state["factions"]["red"]["outlawed"], "of its own accord, not by decree")
	var proclaimed := false
	for notice in notices:
		if String(notice.get("kind", "")) == "civil_war":
			proclaimed = true
			t.check_eq(String(notice.get("pattern", "")), "elite_overproduction", "the beat names the pattern")
	t.check(proclaimed, "the civil war is proclaimed")


func test_no_war_on_rome_before_the_break(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	t.check(not game.declare_war("senate"), "no herald may carry war to the Senate")
	t.check(not game.declare_war("green"), "nor to a sister house")
	t.check(not game.set_stance("senate", "war"), "not by the raw stance either")
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(not SiegeRules.begin_siege(data, state, army_id, "gamma"), "no ladder goes up against a Senate town")
	t.check(not DiplomacyRules.at_war(state, "red", "senate"), "and no war follows the refused siege")
	var senate_army := Fixtures.add_army(state, "senate", "gamma", ["test_spears"])
	t.check(CombatRules.attack_army(data, state, AutoResolver.new(), CampaignRng.seeded(1), army_id, senate_army).is_empty(),
		"no blade starts what no herald may")
	t.check(game.declare_war("blue"), "war with a foreign power is another matter")
	state["factions"]["red"]["at_civil_war"] = true
	t.check(DiplomacyRules.declare_war(data, state, "red", "senate"), "after the break the sword is free")


func test_a_civil_war_is_never_talked_away(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	state["factions"]["red"]["at_civil_war"] = true
	DiplomacyRules.declare_war(data, state, "red", "senate")
	state["factions"]["green"]["at_civil_war"] = true
	DiplomacyRules.declare_war(data, state, "green", "senate")
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	# The player's own envoy.
	var peace := {"from": "red", "to": "senate", "stance": "neutral", "give_payment": 4000,
		"give_tribute": null, "give_regions": [], "ask_payment": 0, "ask_tribute": null, "ask_regions": []}
	var verdict := DiplomacyRules.evaluate_offer(data, state, "red", "senate", peace)
	t.check(not verdict["accept"] and verdict["vetoes"].has("the_republic_is_at_war_with_itself"),
		"silver buys no peace in a civil war")
	t.check(not game.set_stance("senate", "neutral"), "nor does the raw stance")
	# An envoy already on the road is recalled.
	var envoy := {"id": "o1", "from": "senate", "to": "red", "stance": "neutral", "give_payment": 0,
		"give_tribute": null, "give_regions": [], "ask_payment": 0, "ask_tribute": null, "ask_regions": [],
		"expires_turn": 99}
	t.check(not DiplomacyRules.offer_still_stands(data, state, envoy), "the Senate's own envoy is recalled")
	# The AI's two quiet roads to peace are closed.
	var memory := AiDiplomacy.ai_memory(state)
	memory["war_turns"][AiDiplomacy.war_key("green", "senate")] = 999
	AiDiplomacy.white_peace_stalled(data, state, "senate", [])
	t.check(DiplomacyRules.at_war(state, "green", "senate"), "the war does not gutter out")
	var events: Array = []
	AiDiplomacy._consider_peace(data, state, "senate", data.ai_personas["default"], events,
		{"senate": 1.0, "red": 100.0, "green": 100.0, "blue": 1.0, "rebels": 1.0})
	t.check(state["pending_offers"].is_empty() and events.is_empty(), "a losing Senate sends no envoy to the rebels")
	# Foreign wars are untouched by any of this.
	var foreign := {"from": "red", "to": "blue", "stance": "neutral", "give_payment": 9000,
		"give_tribute": null, "give_regions": [], "ask_payment": 0, "ask_tribute": null, "ask_regions": []}
	t.check(not DiplomacyRules.evaluate_offer(data, state, "red", "blue", foreign)["vetoes"].has("the_republic_is_at_war_with_itself"),
		"peace with a foreign power is still for sale")


func test_the_war_ends_when_the_senate_falls(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	state["factions"]["red"]["at_civil_war"] = true
	state["factions"]["red"]["outlawed"] = true
	DiplomacyRules.declare_war(data, state, "red", "senate")
	DiplomacyRules.declare_war(data, state, "green", "red")
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))  # red_elder etc. hold nothing — rebels; green elects
	state["factions"]["senate"]["alive"] = false
	var notices := SenateRules.process_turn(data, state, CampaignRng.seeded(4))
	t.check(not state["factions"]["red"]["at_civil_war"] and not state["factions"]["red"]["outlawed"],
		"with the Senate gone there is nothing to rebel against")
	t.check_eq(DiplomacyRules.stance_between(state, "red", "green"), "neutral", "the houses' war lapses")
	t.check_eq(_count(notices, "civil_war_over"), 1, "and the age turns")
	t.check_eq(_office_of(state, "green_elder"), "", "the magistracies end with the Republic")
	t.check(DiplomacyRules.declare_war(data, state, "red", "green"), "the houses are now powers like any other")


func test_the_ai_house_complies_on_the_last_turn(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	state["season"] = "winter"
	data.missions["the_senate_demands_your_life"] = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/missions.json"))["missions"].filter(
			func(m): return m["id"] == "the_senate_demands_your_life")[0]
	_hated_and_great(state, "green")
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	t.check_eq(_charge_kind(data, state, "green"), "leader_suicide", "the Senate demands green's patriarch")
	var notices: Array = []
	AiPolitics.take_turn(data, state, "green", notices)
	t.check(state["characters"]["green_elder"]["alive"], "the house waits out the term")
	state["factions"]["green"]["mission"]["turns_left"] = 1
	AiPolitics.take_turn(data, state, "green", notices)
	t.check(not state["characters"]["green_elder"]["alive"], "and complies on the last turn")
	var judged := SenateRules.process_turn(data, state, CampaignRng.seeded(4))
	t.check_eq(_count(judged, "mission_complete"), 1, "which the Senate accepts")
	t.check(not state["factions"]["green"]["at_civil_war"], "no civil war")


## --- Presentation ----------------------------------------------------------

func test_political_beats_render_without_leftover_tokens(t) -> void:
	## The five Phase 7 beats, rendered through the real prose table.
	var game := Game.new_campaign("julii", 42)
	var leader := ChronicleRules.leader_of(game.state, "julii")
	var journal: Array = []
	TurnJournal.add(journal, "office_gained", {"faction": "julii", "subject": leader, "extra": {"detail": "consul"}})
	TurnJournal.add(journal, "consuls_elected", {"faction": "julii", "subject": leader})
	TurnJournal.add(journal, "house_joins_rebellion", {"faction": "junii", "other": "julii"})
	TurnJournal.add(journal, "house_stays_loyal", {"faction": "cornelii", "other": "julii"})
	TurnJournal.add(journal, "civil_war_over", {})
	t.check_eq(journal.size(), 5, "every political kind is a known beat")
	for beat in journal:
		for text in [DispatchFormat.headline(game.data, game.state, beat), DispatchFormat.body(game.data, game.state, beat)]:
			t.check(text.length() > 0 and not text.contains("{"), "%s renders cleanly: %s" % [beat["kind"], text])
	var headline := DispatchFormat.headline(game.data, game.state, journal[0])
	t.check(headline.contains("Consul"), "the office is named, not its id: " + headline)


func test_the_senate_overview_reads_the_republic(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	_men(state)
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	SenateRules.process_turn(data, state, CampaignRng.seeded(3))
	var overview := game.senate_overview()
	t.check(overview["senate_alive"] and overview["is_roman_house"], "a Roman house before a living Senate")
	t.check_eq(overview["houses"].size(), 2, "both houses are read")
	var red_row: Dictionary = overview["houses"].filter(func(h): return h["id"] == "red")[0]
	t.check_eq(int(red_row["seats"]), 3, "red holds three seats")
	var censor: Dictionary = overview["ladder"][0]
	t.check_eq(String(censor["id"]), "censor", "the ladder reads from the top")
	t.check_eq(String(censor["holders"][0]["name"]), "Red Elder", "and names the holder")
	var men: Array = overview["men"]
	t.check_eq(men.size(), 3, "the house's men stand before the Senate; the wife does not")
	t.check_eq(String(men[0]["office"]), "Censor", "an office is shown by name")
	t.check(overview["charge"] == null or not overview["charge"]["is_demand"], "no demand yet")
	_hated_and_great(state, "red")
	data.missions["the_senate_demands_your_life"] = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/missions.json"))["missions"].filter(
			func(m): return m["id"] == "the_senate_demands_your_life")[0]
	state["season"] = "winter"
	SenateRules.process_turn(data, state, CampaignRng.seeded(4))
	overview = game.senate_overview()
	t.check(overview["charge"] != null and overview["charge"]["is_demand"], "the demand is on the scroll")
	t.check_eq(String(overview["charge"]["target_name"]), "Red Elder", "with the man it names")
