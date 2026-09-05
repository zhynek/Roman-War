extends RefCounted
## Harbours and fleets: ships finish in port (never on the walls), launch
## into a fleet, dock back, merge and split at sea; ships move between a
## harbour and a fleet on its sea; saves from before harbours existed load
## with their ships moved out of the garrison.


func _port_world() -> Array:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# epsilon (red's, coastal on test_sea) gets a shipyard.
	state["settlements"]["epsilon"]["buildings"]["test_naval"] = 1
	return [data, state]


func _ship() -> Dictionary:
	return {"template": "test_galley", "experience": 0, "strength_pct": 100}


func test_ships_finish_in_the_harbour_not_the_garrison(t) -> void:
	var world := _port_world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	t.check(RecruitmentRules.queue_unit(data, state, "epsilon", "test_galley"), "a shipyard builds galleys")
	t.check_eq(RecruitmentRules.advance_queues(data, state, "epsilon"), ["test_galley"], "the galley completes")
	t.check_eq(state["settlements"]["epsilon"]["garrison"].size(), 0, "no ship on the walls")
	t.check_eq(state["settlements"]["epsilon"]["harbour"].size(), 1, "the galley waits in the harbour")
	t.check_eq(SettlementRules.garrison_soldiers(data, state["settlements"]["epsilon"]), 0, "crews never count for public order")
	t.check_eq(EconomyRules.faction_upkeep(data, state, "red"), 100, "but the ship is still paid for")

	# Retraining in port repairs ships too.
	state["settlements"]["epsilon"]["harbour"][0]["strength_pct"] = 50
	t.check_eq(RecruitmentRules.retrain_garrison(data, state, "epsilon"), 1, "the harbour is retrained")
	t.check_eq(int(state["settlements"]["epsilon"]["harbour"][0]["strength_pct"]), 100, "the galley is repaired")

	var summary := ForceRules.summary(data, state, "harbour:epsilon")
	t.check_eq(summary["kind"], "harbour", "a harbour is a force the panels can describe")
	t.check_eq(summary["units"], 1, "with its ships counted")


func test_launch_dock_merge_split(t) -> void:
	var world := _port_world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var harbour: Array = state["settlements"]["epsilon"]["harbour"]
	for i in range(3):
		harbour.append(_ship())

	t.check_eq(NavalRules.check_launch_fleet(data, state, "epsilon", [0], "test_sea_3"), "no_zone", "only into a sea the port touches")
	t.check_eq(NavalRules.check_launch_fleet(data, state, "epsilon", [], "test_sea"), "empty_selection", "tick ships first")
	var launched := NavalRules.launch_fleet(data, state, "epsilon", [0, 1], "test_sea")
	t.check(launched["ok"], "two ships put to sea")
	var fleet_id: String = launched["fleet_id"]
	t.check_eq(state["fleets"][fleet_id]["ships"].size(), 2, "the fleet has two ships")
	t.check_eq(state["fleets"][fleet_id]["sea_zone"], "test_sea", "in the chosen sea")
	t.check_near(float(state["fleets"][fleet_id]["movement_left"]), 0.0, 0.0001, "launching spends the season")
	t.check_eq(harbour.size(), 1, "one ship stays in port")

	MovementRules.reset_movement(data, state)
	var split := NavalRules.split_fleet(data, state, fleet_id, [1])
	t.check(split["ok"], "a ship is detached")
	t.check_eq(NavalRules.check_split_fleet(data, state, fleet_id, [0]), "last_unit", "the last ship stays")
	t.check(NavalRules.merge_fleets(data, state, split["fleet_id"], fleet_id)["ok"], "and rejoins")
	t.check(not state["fleets"].has(split["fleet_id"]), "the detachment is gone")
	t.check_eq(state["fleets"][fleet_id]["ships"].size(), 2, "the fleet is whole")

	# Ships move between the harbour and a fleet on its sea; never to land forces.
	t.check(ForceRules.transfer_units(data, state, "harbour:epsilon", fleet_id, [0])["ok"], "the last harbour ship joins the fleet")
	t.check_eq(state["fleets"][fleet_id]["ships"].size(), 3, "three ships at sea")
	state["settlements"]["epsilon"]["garrison"].append({"template": "test_mob", "experience": 0, "strength_pct": 100})
	t.check_eq(ForceRules.check_transfer_units(data, state, "garrison:epsilon", fleet_id, [0]), "not_colocated", "land forces never meet fleets")
	t.check(ForceRules.transfer_units(data, state, fleet_id, "harbour:epsilon", [2])["ok"], "a ship returns to port")

	t.check_eq(NavalRules.check_dock_fleet(data, state, fleet_id, "alpha"), "foreign_settlement", "no docking in a foreign port")
	t.check_eq(NavalRules.check_dock_fleet(data, state, fleet_id, "beta"), "no_zone", "beta is landlocked")
	t.check(NavalRules.dock_fleet(data, state, fleet_id, "epsilon")["ok"], "the fleet docks at home")
	t.check(not state["fleets"].has(fleet_id), "the fleet is gone")
	t.check_eq(harbour.size(), 3, "all three ships are back in the harbour")


func test_old_saves_load_with_ships_moved_to_the_harbour(t) -> void:
	var world := _port_world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	# A version-1 world: no harbour key anywhere, and a galley recruited into the garrison.
	for settlement in state["settlements"].values():
		settlement.erase("harbour")
	state["settlements"]["epsilon"]["garrison"].append(_ship())
	var v1_json := SaveGame.to_json(state).replace('"version": 2', '"version": 1')
	t.check(v1_json.contains('"version": 1'), "a version-1 save was written")
	var loaded := SaveGame.from_json(v1_json)
	t.check(not loaded.is_empty(), "version 1 still loads")
	for region_id in loaded["settlements"]:
		t.check(loaded["settlements"][region_id].has("harbour"), "every settlement gains a harbour: " + region_id)
	t.check_eq(NavalRules.normalise(data, loaded), 1, "one ship moved out of a garrison")
	t.check_eq(loaded["settlements"]["epsilon"]["garrison"].size(), 0, "the garrison holds no ship")
	t.check_eq(loaded["settlements"]["epsilon"]["harbour"].size(), 1, "the galley is in the harbour")
	t.check_eq(NavalRules.normalise(data, loaded), 0, "normalising twice changes nothing")

	t.check(SaveGame.from_json(v1_json.replace('"version": 1', '"version": 3')).is_empty(), "a newer save is refused")
	t.check(SaveGame.from_json(v1_json.replace('"version": 1', '"version": 0')).is_empty(), "version 0 is refused")


func test_the_passive_ai_never_queues_ships(t) -> void:
	var world := _port_world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	state["player_faction"] = "blue"   # so the stub plays red
	data.units["test_galley"]["cost"] = 50   # cheaper than anything on land
	AiStub.take_turn(data, state, "red")
	var queued: Array = state["settlements"]["epsilon"]["recruitment_queue"]
	t.check(not queued.is_empty(), "the stub recruits for an empty garrison")
	for job in queued:
		t.check(job["template"] != "test_galley", "and never a ship it would never launch")


func test_ships_never_relay_through_ports_or_fleets(t) -> void:
	## Movement is conserved at sea as on land: a fleet taking ships aboard
	## keeps the lesser movement, making port costs a sea lane, and ships that
	## came in this season leave the harbour no fresher than they arrived.
	var world := _port_world()
	var data: GameData = world[0]
	var state: Dictionary = world[1]
	var spent := Fixtures.add_fleet(state, "red", "test_sea", ["test_galley", "test_galley", "test_galley"])
	var fresh := Fixtures.add_fleet(state, "red", "test_sea", ["test_galley"])
	MovementRules.reset_movement(data, state)
	state["fleets"][spent]["movement_left"] = 0.0

	t.check(ForceRules.transfer_units(data, state, spent, fresh, [0])["ok"], "a spent ship joins the fresh fleet")
	t.check_near(float(state["fleets"][fresh]["movement_left"]), 0.0, 0.0001, "which now sails no further than the ship can")
	t.check_eq(NavalRules.check_dock_fleet(data, state, spent, "epsilon"), "no_movement", "a spent fleet cannot make port")
	state["fleets"][spent]["movement_left"] = 1.0
	t.check(NavalRules.dock_fleet(data, state, spent, "epsilon")["ok"], "with a lane left it docks")
	t.check_near(float(state["settlements"]["epsilon"].get("muster_sail_left", -1.0)), 0.0, 0.0001,
		"the harbour remembers the ships arrived with nothing left")
	t.check_eq(state["settlements"]["epsilon"]["harbour"].size(), 2, "two ships are in port")
	var launched := NavalRules.launch_fleet(data, state, "epsilon", [0], "test_sea")
	t.check(launched["ok"], "it can still be launched")
	t.check_near(float(state["fleets"][launched["fleet_id"]]["movement_left"]), 0.0, 0.0001, "but a launched fleet waits for next season anyway")
	var other := Fixtures.add_fleet(state, "red", "test_sea", ["test_galley"])
	t.check(ForceRules.transfer_units(data, state, "harbour:epsilon", other, [0])["ok"], "a fresh fleet takes the other arrived ship aboard")
	t.check_near(float(state["fleets"][other]["movement_left"]), 0.0, 0.0001, "and is capped by what it had left")

	MovementRules.reset_movement(data, state)
	t.check(not state["settlements"]["epsilon"].has("muster_sail_left"), "the new season clears the harbour's memory")
	t.check_near(float(state["fleets"][other]["movement_left"]), 2.0, 0.0001, "and every fleet is fresh again")
