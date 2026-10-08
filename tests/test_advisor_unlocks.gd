extends RefCounted
## Focused additive-save boundary checks, permitted by the migration exception.
func _data() -> GameData:
	var data := Fixtures.data()
	data.advisors={"lucius":{"id":"lucius","unlock":{"building_kind":"government","min_level":2}}}
	return data

func test_legacy_backfill_and_permanent_round_trip(t) -> void:
	var data:=_data()
	var state:=Fixtures.state(data)
	state.erase("advisor_unlocks")
	for id in state.settlements:
		if state.settlements[id].owner==state.player_faction:
			state.settlements[id].buildings={"test_government":2}
	var rng: String=state.rng_state
	NewGame.ensure_state_keys(state,data)
	t.check(AdvisorRules.status(data,state,"lucius").available,"legacy owned completed seat unlocks")
	t.check_eq(state.rng_state,rng,"migration consumes no RNG")
	for id in state.settlements:
		if state.settlements[id].owner==state.player_faction:state.settlements[id].buildings={}
	t.check(not AdvisorRules.status(data,state,"lucius").qualifies,"no qualifying seat remains")
	var loaded:=SaveGame.from_json(SaveGame.to_json(state))
	NewGame.ensure_state_keys(loaded,data)
	t.check(AdvisorRules.status(data,loaded,"lucius").available,"earned counsel survives save/load and building loss")

func test_current_locked_save_reads_do_not_award(t) -> void:
	var data:=_data()
	var state:=Fixtures.state(data)
	for id in state.settlements:
		state.settlements[id].buildings={"test_government":1}
		if state.settlements[id].owner!=state.player_faction:state.settlements[id].buildings.test_government=2
		state.settlements[id].construction_queue=[{"chain":"test_government","turns_left":1}]
	AdvisorRules.reconcile(data,state)
	t.check(state.advisor_unlocks.is_empty(),"foreign and queued seats do not unlock")
	for id in state.settlements:
		if state.settlements[id].owner==state.player_faction:state.settlements[id].buildings.test_government=2
	var before:=JSON.stringify(state)
	t.check(AdvisorRules.status(data,state,"lucius").qualifies,"completed seat qualifies")
	t.check_eq(JSON.stringify(state),before,"status read does not award or mutate")
	var loaded:=SaveGame.from_json(SaveGame.to_json(state))
	NewGame.ensure_state_keys(loaded,data)
	t.check(loaded.advisor_unlocks.is_empty(),"loading a current save cannot grant a pending unlock")
	AdvisorRules.reconcile(data,loaded)
	t.check(AdvisorRules.status(data,loaded,"lucius").available,"season reconciliation awards once")
	var record:=JSON.stringify(loaded.advisor_unlocks)
	loaded.turn+=1
	AdvisorRules.reconcile(data,loaded)
	t.check_eq(JSON.stringify(loaded.advisor_unlocks),record,"later seasons preserve original unlock")

func test_malformed_unlocks_are_rejected(t) -> void:
	var state:=Fixtures.state(Fixtures.shared_data())
	for unlocks in [[],{"lucius":null},{"lucius":{"turn":-1,"region":"alpha"}},
		{"lucius":{"turn":1,"region":"alpha"}},{"lucius":{"turn":0.5,"region":"alpha"}},
		{"lucius":{"turn":0,"region":"missing"}}]:
		state.advisor_unlocks=unlocks
		t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(),"invalid unlock record fails before migration")
