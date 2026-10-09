extends RefCounted
## Focused additive-save and command boundary checks under migration exception.

func _game() -> Game:
	var game := Game.new()
	game.data = Fixtures.data()
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/patronage.json"))
	game.data.patronage_content = content
	for profile in content.patrons:game.data.patrons[profile.id] = profile
	var temples: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/temples.json"))
	for chain in temples.chains:
		game.data.chains[chain.id] = chain
	game.state = Fixtures.state(game.data)
	return game

func test_legacy_neutral_and_pure_status(t) -> void:
	var game := _game()
	game.state.settlements.beta.buildings.roman_jupiter = 1
	game.state.erase("patronage")
	var loaded := SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(loaded,game.data)
	t.check_eq(loaded.patronage,PatronageRules.neutral(),"legacy temple owners do not adopt a patron")
	game.state = loaded
	var before := JSON.stringify(game.state)
	var view := game.patronage_status()
	t.check_eq(view.chosen,"","legacy status remains neutral")
	t.check_eq(JSON.stringify(game.state),before,"status has no read-side mutation or RNG")
	view.completed["zeus"] = 0
	t.check(game.state.patronage.completed.is_empty(),"returned nested records do not alias saves")

func test_pledge_requires_completed_owned_temple_and_safe_commands(t) -> void:
	var game := _game()
	game.state.settlements.alpha.buildings.roman_jupiter = 1
	game.state.settlements.beta.construction_queue = [{"chain":"roman_jupiter","turns_left":1}]
	t.check(not game.pledge_patron("zeus","alpha"),"foreign temples cannot authorize a pledge")
	t.check(not game.pledge_patron("zeus","beta"),"queued temples cannot authorize a pledge")
	game.state.settlements.beta.buildings.roman_jupiter = 1
	t.check(game.pledge_patron("zeus","beta"),"completed owned temple authorizes explicit pledge")
	var before := JSON.stringify(game.state)
	t.check(not game.pledge_patron("zeus","beta"),"repeat pledge cannot reset progress")
	t.check(not game.pledge_patron("unknown","beta"),"unknown patron is rejected")
	t.check_eq(JSON.stringify(game.state),before,"rejected commands preserve all state")
	game.state.winner = "red"
	t.check(not game.renounce_patron(),"campaign end blocks patron changes")
	game.state.winner = null
	game.state.city_battles = {"beta":{"phase":"fighting"}}
	t.check(not game.renounce_patron(),"active battle blocks patron changes")
	t.check_eq(game.patronage_status().command_blocked,"battle_active","battle status avoids live economic reads")
	game.state.city_battles = {}
	game.data.roma_city.region = "beta"
	game.state.settlements.beta.garrison = [{}]
	game.state.settlements.beta.siege = {"besieger":"enemy","equipment_ready":true}
	game.state.armies.enemy = {"owner":"blue","region":"beta","units":[{}]}
	t.check(not game.renounce_patron(),"pending city defense blocks patron changes")
	t.check_eq(game.patronage_status().command_blocked,"defense_pending","pending defense is explained")

func test_stewardship_round_trip_once_per_season(t) -> void:
	var game := _game()
	game.state.settlements.beta.buildings.roman_jupiter = 1
	game.state.settlements.beta.tax_level = "low"
	# Fixture order isolates the save-boundary check from unrelated balance.
	game.data.balance.patronage.minimum_order = 0
	t.check(game.pledge_patron("zeus","beta"),"initial pledge succeeds")
	var rng: String = game.state.rng_state
	game.state.turn = 1
	PatronageRules.reconcile(game.data,game.state)
	t.check_eq(game.state.patronage.progress,1,"first resolved season counted")
	PatronageRules.reconcile(game.data,game.state)
	t.check_eq(game.state.patronage.progress,1,"same-season replay does not count twice")
	var loaded := SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(loaded,game.data)
	game.state.turn = 2
	loaded.turn = 2
	PatronageRules.reconcile(game.data,game.state)
	PatronageRules.reconcile(game.data,loaded)
	t.check_eq(JSON.stringify(JSON.parse_string(JSON.stringify(loaded.patronage))),
		JSON.stringify(JSON.parse_string(JSON.stringify(game.state.patronage))),
		"loaded and live progress agree")
	t.check_eq(int(loaded.patronage.completed.zeus),2,"second consecutive season records one honor")
	t.check_eq(game.state.rng_state,rng,"mission consumes no random draws")
	t.check(game.renounce_patron(),"explicit renunciation works")
	t.check(game.pledge_patron("zeus","beta"),"repledge is explicit")
	game.state.turn = 3
	PatronageRules.reconcile(game.data,game.state)
	t.check_eq(int(game.state.patronage.completed.zeus),2,"historical honor is never replaced")

func test_interrupted_progress_and_expansion_survive_reload(t) -> void:
	var game := _game()
	game.data.balance.patronage.minimum_order = 0
	game.state.settlements.beta.buildings.roman_jupiter = 1
	game.state.settlements.beta.buildings.roman_mars = 1
	t.check(game.pledge_patron("zeus","beta"),"stewardship pledge")
	game.state.turn = 1
	PatronageRules.reconcile(game.data,game.state)
	game.state.turn = 2
	game.state.settlements.beta.tax_level = "very_high"
	PatronageRules.reconcile(game.data,game.state)
	t.check_eq(game.state.patronage.progress,0,"high taxation breaks consecutive stewardship")
	t.check(game.pledge_patron("ares","beta"),"changing patron clears active progress")
	game.state = SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(game.state,game.data)
	game.state.settlements.alpha.owner = "red"
	game.state.turn = 3
	game.state.settlements.beta.buildings.erase("roman_mars")
	PatronageRules.reconcile(game.data,game.state)
	t.check(game.state.patronage.completed.is_empty(),"expansion without a retained temple cannot complete")
	game.state.settlements.beta.buildings.roman_mars = 1
	game.state.turn = 4
	PatronageRules.reconcile(game.data,game.state)
	t.check_eq(int(game.state.patronage.completed.ares),4,"loaded baseline supports expansion after temple restoration")

func test_malformed_patronage_rejected_before_migration(t) -> void:
	var game := _game()
	var records: Array = [[],{},null]
	for changes in [{"progress":-1},{"progress":0.5},{"chosen":"../../private"},
		{"pledged_turn":1},{"last_checked_turn":-1},{"completed":{"zeus":1}},
		{"completed":{"zeus":-1}},{"completed":{"zeus":null}},
		{"chosen":"zeus","baseline_owned":0},{"progress":1}]:
		var record := PatronageRules.neutral()
		record.merge(changes,true)
		records.append(record)
	for record in records:
		game.state.patronage = record
		t.check(SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(),"malformed patronage rejected")
