extends RefCounted
## The day's transcript: it must be complete, bounded, reproducible, and
## survive a save — the Dispatch is read off it, and a divergent journal means
## a divergent campaign.


func test_the_journal_records_the_turn(t) -> void:
	var game := Game.new_campaign("julii", 42)
	game.end_turn()
	var journal := TurnJournal.of(game.state)
	t.check(not journal.is_empty(), "a resolved turn leaves a record")
	t.check_eq(int(game.state["journal"]["turn"]), int(game.state["turn"]),
		"the journal is stamped with the turn it belongs to")
	for beat in journal:
		t.check(TurnJournal.KINDS.has(String(beat["kind"])), "known beat kind: " + String(beat["kind"]))
		for key in ["kind", "faction", "other", "region", "subject", "value", "extra"]:
			t.check(beat.has(key), "beat carries %s" % key)


func test_the_journal_holds_only_today(t) -> void:
	## Bounded by construction: 568 turns of a long campaign must not pile up
	## in the save file.
	var game := Game.new_campaign("julii", 3)
	var sizes: Array = []
	for i in range(30):
		game.end_turn()
		sizes.append(TurnJournal.of(game.state).size())
		t.check_eq(int(game.state["journal"]["turn"]), int(game.state["turn"]),
			"the journal is rebuilt each turn, not appended to")
	var biggest := 0
	for size in sizes:
		biggest = maxi(biggest, int(size))
	t.check(biggest < 400, "a single day stays a readable size (largest was %d)" % biggest)


func test_the_journal_is_deterministic(t) -> void:
	var first := Game.new_campaign("julii", 909)
	var second := Game.new_campaign("julii", 909)
	for i in range(15):
		first.end_turn()
		second.end_turn()
		t.check_eq(JSON.stringify(first.state["journal"]), JSON.stringify(second.state["journal"]),
			"same seed, same day at turn %d" % i)


func test_the_journal_survives_a_save(t) -> void:
	var game := Game.new_campaign("julii", 55)
	for i in range(6):
		game.end_turn()
	var before := JSON.stringify(game.state["journal"])
	var restored := SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(restored.has("journal"), "the journal travels with the save")
	t.check_eq(JSON.stringify(JSON.parse_string(before)),
		JSON.stringify(restored["journal"]), "and comes back unchanged")


func test_a_save_without_a_journal_still_loads(t) -> void:
	## Saves written before the Dispatch existed must not be rejected — the
	## reader defaults rather than the format version bumping under the player.
	var game := Game.new_campaign("julii", 8)
	game.end_turn()
	var state: Dictionary = SaveGame.from_json(SaveGame.to_json(game.state))
	state.erase("journal")
	t.check_eq(TurnJournal.of(state).size(), 0, "an absent journal reads as an empty day")
	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = state
	resumed.end_turn()
	t.check(not TurnJournal.of(resumed.state).is_empty(), "and the next turn fills it again")


func test_decisions_and_diplomacy_are_recorded(t) -> void:
	## The gaps the Dispatch was built to close: the treasury moving, the
	## capital growing, and a war starting anywhere on the map.
	var game := Game.new_campaign("julii", 42)
	var found := {}
	for i in range(40):
		game.end_turn()
		for beat in TurnJournal.of(game.state):
			found[String(beat["kind"])] = beat
	for kind in ["treasury_change", "capital_growth", "war_declared", "building_completed"]:
		t.check(found.has(kind), "forty turns produce a %s beat" % kind)

	var purse: Dictionary = found.get("treasury_change", {})
	if not purse.is_empty():
		t.check(purse["extra"].has("income") and purse["extra"].has("upkeep"),
			"the treasury beat carries the income and upkeep behind the number")


func test_beats_carry_no_prose(t) -> void:
	## The engine emits ids and numbers; every word comes from the data table.
	## A beat that smuggled a sentence through would break that contract.
	var game := Game.new_campaign("julii", 17)
	for i in range(12):
		game.end_turn()
		for beat in TurnJournal.of(game.state):
			for field in ["faction", "other", "region", "subject"]:
				var value: String = String(beat[field])
				t.check(not value.contains(" "),
					"%s.%s is an id, not prose (%s)" % [beat["kind"], field, value])
