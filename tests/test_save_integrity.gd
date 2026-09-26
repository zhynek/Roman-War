extends RefCounted
## Uses the test runner's per-process user:// directory, never the live slot.


func _state() -> Dictionary:
	var state := Fixtures.state(Fixtures.shared_data())
	Fixtures.add_character(state, "red", "general")
	Fixtures.add_army(state, "red", "beta", ["test_spears"])
	Fixtures.add_fleet(state, "red", "test_sea", ["test_galley"])
	return state


func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))


func _raw_write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _clean(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		var file: String = path + suffix
		if FileAccess.file_exists(file) or DirAccess.dir_exists_absolute(file):
			DirAccess.remove_absolute(file)


func test_malformed_json_and_wrappers_fail_cleanly(t) -> void:
	for text in ["", "{", "null", "[]", "false", "{\"version\":2,\"state\":"]:
		t.check(SaveGame.from_json(text).is_empty(), "invalid document rejected: " + text)
	for version in [null, {}, [], "2", true, 1, 2.5, 3]:
		t.check(SaveGame.from_json(JSON.stringify({"version": version, "state": _state()})).is_empty(),
			"invalid or unsupported version rejected: " + str(version))
	for state in [null, [], true, 12, "state", {}]:
		t.check(SaveGame.from_json(JSON.stringify({"version": 2, "state": state})).is_empty(),
			"invalid state wrapper rejected: " + str(state))


func test_missing_core_state_is_rejected_before_migration(t) -> void:
	for key in ["turn", "year", "season", "rng_state", "player_faction", "next_id",
		"factions", "settlements", "armies", "fleets", "characters", "events_fired", "winner"]:
		var state := _state()
		state.erase(key)
		t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(), "missing core key rejected: " + key)
	var missing_player := _state()
	missing_player["player_faction"] = "absent"
	t.check(SaveGame.from_json(SaveGame.to_json(missing_player)).is_empty(), "unknown player rejected")
	for rng in [123, "not an integer", "1.5", null]:
		var state := _state()
		state["rng_state"] = rng
		t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(), "RNG must remain a decimal string")


func test_broken_entity_and_unit_containers_are_rejected(t) -> void:
	for table in ["factions", "settlements", "armies", "fleets", "characters", "agents", "watchposts"]:
		for value in [null, [], "broken", 12]:
			var state := _state()
			state[table]["broken"] = value
			t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(), "invalid entity rejected in " + table)
	for location in [["armies", "army_1", "units"], ["fleets", "fleet_2", "ships"],
		["settlements", "beta", "garrison"], ["settlements", "beta", "harbour"]]:
		for units in [null, {}, [null], [{}], [{"template": "test_spears", "strength_pct": "full", "experience": 0}]]:
			var state := _state()
			state[location[0]][location[1]][location[2]] = units
			t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(), "invalid roster rejected: " + str(location))
	var invalid_optional := _state()
	invalid_optional["cartography"] = []
	t.check(SaveGame.from_json(SaveGame.to_json(invalid_optional)).is_empty(), "present optional collection must have its proper type")
	for location in [["armies", "army_1", "general"], ["settlements", "beta", "governor"],
		["settlements", "beta", "siege"], ["factions", "red", "mission"]]:
		var state := _state()
		state[location[0]][location[1]].erase(location[2])
		t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(), "missing nullable core field rejected: " + str(location))


func test_older_additive_version_two_save_still_migrates(t) -> void:
	var state := _state()
	for key in ["world_seed", "modifiers", "chronicle", "wars", "event_cooldowns",
		"tributes", "pending_offers", "agents", "watchposts", "recon", "forest_patrols", "cartography", "map_access"]:
		state.erase(key)
	for faction in state["factions"].values():
		for key in ["ai", "attitude_memory", "knowledge", "edicts", "edict_cooldowns", "war_record", "war_mood", "reign"]:
			faction.erase(key)
	for settlement in state["settlements"].values():
		settlement.erase("harbour")
		settlement.erase("levy_strain")
	for key in ["deeds", "epithet", "office", "offices_held"]:
		state["characters"]["general"].erase(key)
	state["future_extension"] = {"unknown": ["preserved", 7]}
	var before := SaveGame.to_json(state)
	var restored := SaveGame.from_json(before)
	t.check(not restored.is_empty(), "old version-2 core is accepted")
	if restored.is_empty():
		return
	t.check_eq(SaveGame.to_json(state), before, "validation never changes its source")
	t.check_eq(_canonical(restored["future_extension"]), _canonical(state["future_extension"]), "unknown additive keys survive")
	NewGame.ensure_state_keys(restored, Fixtures.shared_data())
	NavalRules.normalise(Fixtures.shared_data(), restored)
	t.check(restored["settlements"]["beta"].has("harbour"), "old harbour data migrates")
	t.check(restored["factions"]["red"].has("war_record"), "old warcraft data migrates")
	t.check(restored["armies"]["army_1"]["units"][0].has("weapon"), "old units gain arming fields")
	t.check_eq(restored["rng_state"], state["rng_state"], "migration retains the saved random stream")


func test_successful_saves_keep_previous_generation_and_recover(t) -> void:
	var path := "user://integrity_generations.json"
	_clean(path)
	var first := _state()
	t.check(SaveGame.write_file(first, path), "first save succeeds")
	t.check_eq(_canonical(SaveGame.read_file(path)), _canonical(first), "first save round trips")
	var second := first.duplicate(true)
	second["turn"] = 1
	second["rng_state"] = "9223372036854775807"
	t.check(SaveGame.write_file(second, path), "replacement succeeds")
	t.check_eq(_canonical(SaveGame.read_file(path)), _canonical(second), "latest save takes priority")
	t.check_eq(_canonical(SaveGame.read_file(path + ".bak")), _canonical(first), "backup is previous generation")
	t.check(not FileAccess.file_exists(path + ".tmp"), "no staged file after success")
	t.check(_raw_write(path, "{\"version\":2,\"state\":"), "simulate interrupted external corruption")
	t.check_eq(_canonical(SaveGame.read_file(path)), _canonical(first), "truncated primary recovers previous save")
	t.check_eq(FileAccess.get_file_as_string(path), "{\"version\":2,\"state\":", "recovery does not erase damaged primary")
	DirAccess.remove_absolute(path)
	t.check_eq(_canonical(SaveGame.read_file(path)), _canonical(first), "missing primary recovers previous save")
	_clean(path)


func test_bad_primary_never_replaces_valid_backup(t) -> void:
	var path := "user://integrity_backup.json"
	_clean(path)
	var state := _state()
	t.check(SaveGame.write_file(state, path), "first generation saved")
	state["turn"] = 1
	t.check(SaveGame.write_file(state, path), "backup established")
	var backup := FileAccess.get_file_as_string(path + ".bak")
	t.check(_raw_write(path, "broken"), "damage primary")
	state["turn"] = 2
	t.check(SaveGame.write_file(state, path), "new valid save replaces damage")
	t.check_eq(FileAccess.get_file_as_string(path + ".bak"), backup, "last valid backup preserved")
	t.check_eq(int(SaveGame.read_file(path)["turn"]), 2, "new save loads")
	_clean(path)


func test_rejected_state_and_staging_failure_preserve_save(t) -> void:
	var path := "user://integrity_failure.json"
	_clean(path)
	var state := _state()
	t.check(SaveGame.write_file(state, path), "original save created")
	var original := FileAccess.get_file_as_string(path)
	t.check(not SaveGame.write_file({"turn": 99}, path), "broken incoming state refused")
	t.check_eq(FileAccess.get_file_as_string(path), original, "bad state cannot truncate save")
	# A directory at the stage location produces a real filesystem failure.
	t.check_eq(DirAccess.make_dir_absolute(path + ".tmp"), OK, "block stage file")
	state["turn"] = 3
	t.check(not SaveGame.write_file(state, path), "stage write failure reported")
	t.check_eq(FileAccess.get_file_as_string(path), original, "stage failure keeps original bytes")
	_clean(path)


func test_backup_failure_preserves_primary_and_previous_backup(t) -> void:
	var path := "user://integrity_backup_failure.json"
	_clean(path)
	var state := _state()
	t.check(SaveGame.write_file(state, path), "first generation saved")
	state["turn"] = 1
	t.check(SaveGame.write_file(state, path), "second generation saved")
	var original := FileAccess.get_file_as_string(path)
	var backup := FileAccess.get_file_as_string(path + ".bak")
	t.check_eq(DirAccess.make_dir_absolute(path + ".bak.tmp"), OK, "block backup stage")
	state["turn"] = 2
	t.check(not SaveGame.write_file(state, path), "backup staging failure reported")
	t.check_eq(FileAccess.get_file_as_string(path), original, "primary preserved on backup failure")
	t.check_eq(FileAccess.get_file_as_string(path + ".bak"), backup, "backup preserved on backup failure")
	_clean(path)


func test_failed_load_keeps_current_game_untouched(t) -> void:
	var path := "user://integrity_bad_load.json"
	_clean(path)
	var game := Game.new()
	game.data = Fixtures.shared_data()
	game.state = _state()
	var before := SaveGame.to_json(game.state)
	t.check(_raw_write(path, "{\"version\":2,\"state\":{\"turn\":99}}"), "malformed campaign staged")
	t.check(not game.load_from(path), "malformed campaign does not reach migrations")
	t.check_eq(SaveGame.to_json(game.state), before, "rejected load retains the live campaign")
	_clean(path)
