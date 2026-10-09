extends RefCounted
## Additive campaign-save boundary checks. No broad tutorial/UI test suite.

func _game() -> Game:
	var game := Game.new()
	game.data = Fixtures.data()
	game.data.reactive_tutorial = JSON.parse_string(FileAccess.get_file_as_string("res://data/reactive_tutorial.json"))
	game.state = Fixtures.state(game.data)
	return game

func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func test_legacy_baseline_does_not_replay_history(t) -> void:
	var game := _game()
	game.state.turn = 12
	game.state.factions.red.treasury = -100
	game.state.erase("advisor_tutorial")
	var loaded := SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(loaded,game.data)
	game.state = loaded
	t.check_eq(game.state.advisor_tutorial.baseline_turn,12,"legacy baseline starts now")
	t.check(game.advisor_tutorial_status().eligible.is_empty(),"historical season and existing debt produce no flood")
	game.state.turn = 13
	AdvisorTutorialRules.reconcile(game.data,game.state,[])
	t.check(not game.state.advisor_tutorial.milestones.has("strain"),"continuing old debt is not a new crossing")
	game.state.factions.red.treasury = 1000
	game.data.balance.advisor_tutorial.strain_order_below = 0
	game.state.turn = 14
	AdvisorTutorialRules.reconcile(game.data,game.state,[])
	game.state.factions.red.treasury = -50
	game.state.turn = 15
	AdvisorTutorialRules.reconcile(game.data,game.state,[])
	t.check(game.state.advisor_tutorial.milestones.has("strain"),"new strain after recovery is recorded")

func test_save_round_trip_postpone_and_once_only_evidence(t) -> void:
	var game := _game()
	game.state.turn = 1
	var rng: String = game.state.rng_state
	var beats: Array = [{"kind":"building_completed","faction":"red","region":"beta","subject":"gov_3"},
		{"kind":"unit_mustered","faction":"blue","region":"alpha","subject":"enemy_unit"}]
	AdvisorTutorialRules.reconcile(game.data,game.state,beats)
	t.check(game.state.advisor_tutorial.milestones.has("construction"),"owned completion recorded")
	t.check(not game.state.advisor_tutorial.milestones.has("army"),"foreign recruitment excluded")
	t.check(game.advisor_tutorial_respond("construction","postpone"),"explicit postpone succeeds")
	t.check(not game.advisor_tutorial_respond("construction","postpone"),"same-season duplicate postpone is a no-op")
	var loaded := SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(loaded,game.data)
	t.check_eq(_canonical(loaded.advisor_tutorial),_canonical(game.state.advisor_tutorial),"saved pending invitation survives")
	var before := _canonical(game.state)
	game.advisor_tutorial_status()
	t.check_eq(_canonical(game.state),before,"pure status changes neither evidence nor RNG")
	game.state.turn = 2
	loaded.turn = 2
	AdvisorTutorialRules.reconcile(game.data,game.state,beats)
	AdvisorTutorialRules.reconcile(game.data,loaded,beats)
	t.check_eq(_canonical(loaded.advisor_tutorial),_canonical(game.state.advisor_tutorial),"loaded and live event continuations agree")
	t.check_eq(game.state.advisor_tutorial.milestones.construction.turn,1,"later completions cannot replace first evidence")
	t.check_eq(game.state.rng_state,rng,"tutorial consumes no campaign randomness")
	t.check(game.advisor_tutorial_respond("construction","acknowledge"),"acknowledgment is explicit")
	AdvisorTutorialRules.record(game.data,game.state,"construction",{"region":"epsilon"})
	t.check_eq(game.state.advisor_tutorial.milestones.construction.status,"acknowledged","acknowledged milestone cannot reopen")

func test_forks_and_response_guards_do_not_leak(t) -> void:
	var game := _game()
	AdvisorTutorialRules.record(game.data,game.state,"army",{"region":"beta"})
	var fork := SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(game.advisor_tutorial_respond("army","dismiss"),"dismiss once")
	t.check_eq(fork.advisor_tutorial.milestones.army.status,"pending","forked ledger is independent")
	game.state = fork
	game.state.city_battles = {"beta":{"phase":"fighting"}}
	t.check(not game.advisor_tutorial_respond("army","acknowledge"),"battle blocks response")
	t.check_eq(game.advisor_tutorial_status().blocked,"battle_active","battle status is limited")
	game.state.city_battles = {}
	game.data.roma_city.region = "beta"
	game.state.settlements.beta.garrison = [{}]
	game.state.settlements.beta.siege = {"besieger":"enemy","equipment_ready":true}
	game.state.armies.enemy = {"owner":"blue","region":"beta","units":[{}]}
	t.check(not game.advisor_tutorial_respond("army","dismiss"),"pending defense blocks response")
	t.check_eq(game.state.advisor_tutorial.milestones.army.status,"pending","blocked commands leave saved pending state intact")

func test_malformed_tutorial_save_is_rejected(t) -> void:
	var game := _game()
	AdvisorTutorialRules.record(game.data,game.state,"army")
	var pristine: Dictionary = game.state.advisor_tutorial.duplicate(true)
	for changes in [{"baseline_turn":-1},{"baseline_turn":1},{"last_checked_turn":1},
		{"strain_active":1},{"milestones":[]},{"milestones":{"army":null}}]:
		game.state.advisor_tutorial = pristine.duplicate(true)
		game.state.advisor_tutorial.merge(changes,true)
		t.check(SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(),"malformed ledger rejected before migration")
	for changes in [{"turn":1},{"turn":0.5},{"status":"unseen"},{"postponed_until":-1},
		{"params":{"region":"missing","subject":"","value":0}},
		{"params":{"region":"","subject":"","value":0.5}}]:
		game.state.advisor_tutorial = pristine.duplicate(true)
		game.state.advisor_tutorial.milestones.army.merge(changes,true)
		t.check(SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(),"malformed milestone rejected before migration")
