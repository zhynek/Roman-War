extends RefCounted
## ForceRules: the one summary every banner and roster reads, and the
## regrouping actions — raise, transfer, merge, split, disband, generals —
## over armies, fleets, garrisons and harbours of the synthetic fixture world,
## plus the facade's ownership guards on the real campaign.


func _garrison(state: Dictionary, region: String, templates: Array) -> void:
	for template in templates:
		state["settlements"][region]["garrison"].append({"template": template, "experience": 0, "strength_pct": 100})


func _facade(data: GameData, state: Dictionary) -> Game:
	var game := Game.new()
	game.data = data
	game.state = state
	game.resolver = AutoResolver.new()
	return game


func test_summary_counts_units_soldiers_and_upkeep(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears", "test_spears"])
	state["armies"][army_id]["units"][1]["strength_pct"] = 50
	MovementRules.reset_movement(data, state)

	var summary := ForceRules.summary(data, state, army_id)
	t.check_eq(summary["kind"], "army", "an army id is an army")
	t.check_eq(summary["owner"], "red", "owner read from the army")
	t.check_eq(summary["region"], "gamma", "region read from the army")
	t.check_eq(summary["units"], 2, "unit count")
	t.check_eq(summary["max_units"], int(data.balance["recruitment"]["army_unit_cap"]), "cap from balance")
	t.check_near(float(summary["fill"]), 0.1, 0.0001, "fill is units over the cap")
	t.check_eq(summary["soldiers"], 120, "80 + 40 men present")
	t.check_eq(summary["max_soldiers"], 160, "160 men at full strength")
	t.check_eq(summary["strength_pct"], 75, "three quarters strength")
	t.check_eq(summary["upkeep"], 240, "upkeep sums both units")
	t.check(summary["general"] == null, "a captain's army has no general")
	t.check_near(float(summary["movement_left"]), 2.0, 0.0001, "movement left after reset")
	t.check_near(float(summary["movement_max"]), 2.0, 0.0001, "movement budget")
	t.check(float(summary["strength"]) > 0.0, "the resolver's estimate is exposed")
	t.check(summary["besieging"] == null, "not besieging")


func test_summary_with_general_and_siege(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var general := Fixtures.add_character(state, "red", "red_marcus", {"command": 4, "location": "beta", "role": "leader"})
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	state["armies"][army_id]["general"] = general
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, army_id, "alpha"), "siege laid")

	var summary := ForceRules.summary(data, state, army_id)
	t.check_eq(summary["general"]["id"], general, "general id")
	t.check_eq(summary["general"]["command"], 4, "effective command")
	t.check(summary["general"]["is_leader"], "the leader is flagged")
	t.check_eq(summary["besieging"], "alpha", "besieging the region it invests")
	t.check_near(float(summary["movement_left"]), 0.0, 0.0001, "the siege took the turn")


func test_summary_for_garrison_and_fleet(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["beta"]["garrison"].append({"template": "test_mob", "experience": 0, "strength_pct": 100})
	var garrison := ForceRules.summary(data, state, "garrison:beta")
	t.check_eq(garrison["kind"], "garrison", "garrison pseudo-id resolves")
	t.check_eq(garrison["region"], "beta", "garrison region")
	t.check_eq(garrison["units"], 1, "garrison unit count")
	t.check_eq(garrison["soldiers"], 60, "garrison head count")

	var fleet_id := Fixtures.add_fleet(state, "red", "test_sea", ["test_galley", "test_galley"])
	MovementRules.reset_movement(data, state)
	var fleet := ForceRules.summary(data, state, fleet_id)
	t.check_eq(fleet["kind"], "fleet", "fleet id resolves")
	t.check_eq(fleet["sea_zone"], "test_sea", "fleet zone")
	t.check_eq(fleet["units"], 2, "ships counted as units")
	t.check_eq(fleet["upkeep"], 200, "fleet upkeep")
	t.check_near(float(fleet["movement_max"]), float(fleet["movement_left"]), 0.0001,
		"a fresh fleet's budget and its movement left agree (same rule, wonder bonus included)")

	t.check(ForceRules.summary(data, state, "army_999").is_empty(), "unknown ids give an empty summary")
	t.check(ForceRules.summary(data, state, "nonsense").is_empty(), "garbage ids give an empty summary")


func test_forces_in_region_are_numerically_ordered(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["next_id"] = 9
	var first := Fixtures.add_army(state, "red", "gamma", ["test_spears"])   # army_9
	var second := Fixtures.add_army(state, "blue", "gamma", ["test_mob"])    # army_10
	Fixtures.add_army(state, "red", "delta", ["test_spears"])
	t.check_eq(ForceRules.armies_in(state, "gamma"), [first, second], "army_9 sorts before army_10")
	t.check(ForceRules.id_less("army_2", "army_10"), "numeric suffix order")
	t.check(not ForceRules.id_less("fleet_1", "army_1"), "different prefixes fall back to string order")


func test_raise_army_from_garrison_with_a_general(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_garrison(state, "beta", ["test_spears", "test_mob", "test_spears"])
	var general := Fixtures.add_character(state, "red", "red_gaius", {"location": "beta", "age": 30})
	Fixtures.add_character(state, "red", "red_boy", {"location": "beta", "age": 10, "role": "child"})
	Fixtures.add_character(state, "red", "red_far", {"location": "epsilon", "age": 30})
	t.check_eq(ForceRules.candidate_generals(data, state, "beta", "red"), ["red_gaius"], "only the adult man standing here may lead")

	t.check_eq(ForceRules.check_raise_army(data, state, "beta", []), "empty_selection", "nothing chosen")
	t.check_eq(ForceRules.check_raise_army(data, state, "beta", [0, 0]), "bad_index", "duplicate index")
	t.check_eq(ForceRules.check_raise_army(data, state, "beta", [7]), "bad_index", "index out of range")
	t.check_eq(ForceRules.check_raise_army(data, state, "beta", [0], "red_far"), "not_eligible_general", "a man elsewhere cannot lead")
	t.check_eq(ForceRules.check_raise_army(data, state, "gamma", [0]), "no_settlement", "no city, no garrison")

	var result := ForceRules.raise_army(data, state, "beta", [2, 0], general)
	t.check(result["ok"], "the army is raised")
	var army: Dictionary = state["armies"][result["army_id"]]
	t.check_eq(army["units"].size(), 2, "two units marched out")
	t.check_eq(army["units"][0]["template"], "test_spears", "original order kept")
	t.check_eq(state["settlements"]["beta"]["garrison"].size(), 1, "one unit stays behind")
	t.check_eq(state["settlements"]["beta"]["garrison"][0]["template"], "test_mob", "the right one stays")
	t.check_eq(army["general"], general, "led by the chosen general")
	t.check_near(float(army["movement_left"]), 2.0, 0.0001, "fresh troops have the full budget")
	t.check_eq(ForceRules.check_raise_army(data, state, "beta", [0], general), "not_eligible_general", "he already leads")

	# Ships in a garrison never march out as infantry.
	_garrison(state, "beta", ["test_galley"])
	t.check_eq(ForceRules.check_raise_army(data, state, "beta", [1]), "is_ship", "a galley is not a field unit")


func test_transfer_conserves_movement_and_respects_cap(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var fresh := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	var tired := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	state["armies"][tired]["movement_left"] = 0.5
	_garrison(state, "beta", ["test_mob"])

	t.check_eq(ForceRules.check_transfer_units(data, state, fresh, fresh, [0]), "same_force", "not to itself")
	t.check_eq(ForceRules.check_transfer_units(data, state, fresh, "army_99", [0]), "not_found", "unknown target")
	var elsewhere := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	t.check_eq(ForceRules.check_transfer_units(data, state, fresh, elsewhere, [0]), "not_colocated", "different regions")
	var foreign := Fixtures.add_army(state, "blue", "beta", ["test_mob"])
	t.check_eq(ForceRules.check_transfer_units(data, state, fresh, foreign, [0]), "wrong_owner", "not to another faction")

	# Tired men join the fresh army: it now marches at their pace.
	t.check(ForceRules.transfer_units(data, state, tired, fresh, [1])["ok"], "one tired unit moves over")
	t.check_eq(state["armies"][fresh]["units"].size(), 2, "received")
	t.check_near(float(state["armies"][fresh]["movement_left"]), 0.5, 0.0001, "movement is the lesser of the two")

	# Into the garrison, then raised again: still tired.
	t.check(ForceRules.transfer_units(data, state, tired, "garrison:beta", [0])["ok"], "into the garrison")
	t.check(not state["armies"].has(tired), "an emptied captain's army is gone")
	t.check_near(float(state["settlements"]["beta"].get("muster_march_left", -1.0)), 0.5, 0.0001, "the garrison remembers the march")
	var raised := ForceRules.raise_army(data, state, "beta", [0, 1])
	t.check(raised["ok"], "raised again")
	t.check_near(float(state["armies"][raised["army_id"]]["movement_left"]), 0.5, 0.0001, "no fresh legs from a relay")
	MovementRules.reset_movement(data, state)
	t.check(not state["settlements"]["beta"].has("muster_march_left"), "the new season forgets the muster")

	# The cap holds on the receiving army.
	var big := Fixtures.add_army(state, "red", "beta", [])
	for i in range(ForceRules.max_units(data)):
		state["armies"][big]["units"].append({"template": "test_mob", "experience": 0, "strength_pct": 100})
	t.check_eq(ForceRules.check_transfer_units(data, state, fresh, big, [0]), "over_cap", "the cap is the limit")
	t.check(ForceRules.transfer_units(data, state, big, "garrison:beta", [0, 1, 2])["ok"], "garrisons are uncapped")


func test_merge_general_precedence(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var a := Fixtures.add_character(state, "red", "red_a", {"location": "gamma"})
	var b := Fixtures.add_character(state, "red", "red_b", {"location": "gamma"})
	var led := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	state["armies"][led]["general"] = a
	var captain := Fixtures.add_army(state, "red", "gamma", ["test_mob", "test_mob"])
	state["armies"][captain]["movement_left"] = 1.0

	# A captain's army takes the general who joins it.
	t.check(ForceRules.merge_armies(data, state, led, captain)["ok"], "led merges into captain")
	t.check(not state["armies"].has(led), "the source is gone")
	t.check_eq(state["armies"][captain]["general"], a, "the general takes command")
	t.check_eq(state["armies"][captain]["units"].size(), 3, "units combined")
	t.check_near(float(state["armies"][captain]["movement_left"]), 1.0, 0.0001, "the slower pace holds")

	# Two led armies in the field: refused. In their own city: allowed, the displaced man stays.
	var other := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	state["armies"][other]["general"] = b
	t.check_eq(ForceRules.check_merge_armies(data, state, other, captain), "two_generals", "two generals cannot share a field camp")
	for army_id in [captain, other]:
		state["armies"][army_id]["region"] = "beta"
	state["characters"][a]["location"] = "beta"
	state["characters"][b]["location"] = "beta"
	t.check(ForceRules.merge_armies(data, state, other, captain)["ok"], "in their own city they may merge")
	t.check_eq(state["armies"][captain]["general"], a, "the receiving general keeps command")
	t.check_eq(state["characters"][b]["location"], "beta", "the other stays in the city")
	t.check(not ForceRules._leads_army(state, b), "unattached")

	# Cap and ownership.
	var blue := Fixtures.add_army(state, "blue", "beta", ["test_mob"])
	t.check_eq(ForceRules.check_merge_armies(data, state, blue, captain), "wrong_owner", "no merging with strangers")


func test_split_and_disband(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var general := Fixtures.add_character(state, "red", "red_a", {"location": "beta"})
	var spare := Fixtures.add_character(state, "red", "red_b", {"location": "beta"})
	var army := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_mob", "test_spears"])
	state["armies"][army]["general"] = general
	state["armies"][army]["movement_left"] = 1.5

	t.check_eq(ForceRules.check_split_army(data, state, army, [0, 1, 2]), "last_unit", "something must stay")
	t.check_eq(ForceRules.check_split_army(data, state, army, [0], "red_nobody"), "not_eligible_general", "unknown general")
	var split := ForceRules.split_army(data, state, army, [1], spare)
	t.check(split["ok"], "a detachment marches on")
	var detachment: Dictionary = state["armies"][split["army_id"]]
	t.check_eq(detachment["units"][0]["template"], "test_mob", "the chosen unit")
	t.check_eq(detachment["general"], spare, "under the man who was standing here")
	t.check_near(float(detachment["movement_left"]), 1.5, 0.0001, "movement copied")
	t.check_eq(state["armies"][army]["units"].size(), 2, "the rest stays")
	var took_general := ForceRules.split_army(data, state, army, [0], "source")
	t.check(took_general["ok"] and state["armies"][took_general["army_id"]]["general"] == general, "the source general can go with the detachment")
	t.check(state["armies"][army]["general"] == null, "leaving a captain behind")

	# Disbanding in an own city returns the men to the population.
	var population_before := int(state["settlements"]["beta"]["population"])
	state["armies"][army]["units"][0]["strength_pct"] = 50
	var result := ForceRules.disband_unit(data, state, army, 0)
	t.check(result["ok"], "disbanded")
	t.check_eq(int(result["returned"]), 40, "half of 80 spears go home")
	t.check_eq(int(state["settlements"]["beta"]["population"]), population_before + 40, "population grows")
	t.check(not state["armies"].has(army), "the last unit of a captain's army dissolves it")

	# A led army keeps its last unit; mercenaries return nobody.
	var mercs := Fixtures.add_army(state, "red", "beta", ["test_merc", "test_merc"])
	state["armies"][mercs]["general"] = general
	population_before = int(state["settlements"]["beta"]["population"])
	t.check_eq(int(ForceRules.disband_unit(data, state, mercs, 0)["returned"]), 0, "sellswords do not settle")
	t.check_eq(int(state["settlements"]["beta"]["population"]), population_before, "no population change")
	t.check_eq(ForceRules.check_disband_unit(data, state, mercs, 0), "last_unit", "the general keeps his last unit")


func test_attach_detach_and_consolidate(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var general := Fixtures.add_character(state, "red", "red_a", {"location": "gamma"})
	var army := Fixtures.add_army(state, "red", "gamma", ["test_spears", "test_spears"])
	t.check_eq(ForceRules.check_detach_general(data, state, army), "no_general", "nobody to detach")
	t.check(ForceRules.attach_general(data, state, army, general)["ok"], "the general takes the army")
	t.check_eq(ForceRules.check_attach_general(data, state, army, general), "has_general", "one general per army")
	t.check_eq(ForceRules.check_detach_general(data, state, army), "no_settlement", "no stepping down in the field")
	state["armies"][army]["region"] = "alpha"
	state["characters"][general]["location"] = "alpha"
	t.check_eq(ForceRules.check_detach_general(data, state, army), "foreign_settlement", "nor in an enemy city")
	state["armies"][army]["region"] = "beta"
	state["characters"][general]["location"] = "beta"
	t.check(ForceRules.detach_general(data, state, army)["ok"], "he steps down at home")
	t.check(state["armies"][army]["general"] == null, "the army is a captain's now")

	state["armies"][army]["units"][0]["strength_pct"] = 40
	state["armies"][army]["units"][1]["strength_pct"] = 50
	t.check_eq(ForceRules.check_consolidate(data, state, army), "", "two depleted spears can be folded")
	t.check(ForceRules.consolidate(data, state, army)["ok"], "consolidated")
	t.check_eq(state["armies"][army]["units"].size(), 1, "one unit remains")
	t.check_eq(int(state["armies"][army]["units"][0]["strength_pct"]), 90, "at combined strength")
	t.check_eq(ForceRules.check_consolidate(data, state, army), "nothing_to_do", "nothing left to fold")


func test_regrouping_replays_identically_after_a_save(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	_garrison(state, "beta", ["test_spears", "test_spears", "test_mob"])
	Fixtures.add_character(state, "red", "red_a", {"location": "beta"})
	var army := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	Fixtures.round_trip_equal(t, data, state, func(s: Dictionary):
		var raised := ForceRules.raise_army(data, s, "beta", [0, 2], "red_a")
		ForceRules.transfer_units(data, s, raised["army_id"], army, [1])
		ForceRules.merge_armies(data, s, army, raised["army_id"])
		ForceRules.split_army(data, s, raised["army_id"], [0])
		ForceRules.disband_unit(data, s, "garrison:beta", 0),
		"raise, transfer, merge, split and disband replay identically from a save")


func test_facade_refuses_foreign_and_unknown_ids(t) -> void:
	## The map feeds ids straight into the facade, so the facade itself must
	## refuse anything the player does not own — and never crash.
	var game := Game.new_campaign("julii", 42)
	var foreign := ""
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		if game.state["armies"][army_id]["owner"] == "carthage":
			foreign = army_id
	t.check(foreign != "", "Carthage fields an army")
	if foreign == "":
		return
	var foreign_region: String = game.state["armies"][foreign]["region"]
	var neighbor: String = game.data.regions[foreign_region]["adjacent"][0]
	t.check(not game.move_army(foreign, neighbor), "cannot march another house's army")
	t.check(game.march_army(foreign, neighbor).is_empty(), "nor order it on the road")
	t.check(not game.set_tax_level(foreign_region, "very_high"), "cannot tax another house's city")
	t.check(not game.queue_unit(foreign_region, "roman_hastati"), "nor recruit there")
	t.check_eq(game.retrain_garrison(foreign_region), 0, "nor retrain there")
	t.check(not game.garrison_army(foreign), "nor garrison their army")
	t.check(game.attack_army(foreign, foreign).is_empty(), "nor attack with it")
	t.check_eq(game.check("merge_armies", [foreign, foreign]), "wrong_owner", "the oracle names the reason")
	t.check_eq(game.raise_units(foreign_region, [0])["error"], "wrong_owner", "no raising from their garrison")
	t.check_eq(game.transfer_units(foreign, foreign, [0])["error"], "wrong_owner", "nor moving their men")
	t.check(not game.move_army("army_999", neighbor), "unknown army refused, not crashed")
	t.check(not game.besiege("army_999", neighbor), "unknown besieger refused")
	t.check(game.assault_settlement("army_999", "nowhere").is_empty(), "unknown assault refused")
	t.check(not game.set_tax_level("nowhere", "high"), "unknown region refused")
	t.check_eq(game.check("split_army", []), "bad_args", "empty arguments are refused, not crashed")
	t.check_eq(game.check("transfer_units", ["army_1", "army_2"]), "bad_args", "so are missing ones")
	t.check_eq(game.check("nonsense", []), "unknown_action", "unknown actions are named")


func test_facade_check_explains_refusals_and_raises(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var army_id := ""
	var army_ids: Array = game.state["armies"].keys()
	army_ids.sort()
	for candidate in army_ids:
		if game.state["armies"][candidate]["owner"] == "julii":
			army_id = candidate
	t.check(army_id != "", "the Julii field an army")
	if army_id == "":
		return
	var army: Dictionary = game.state["armies"][army_id]
	var region: String = army["region"]
	if army["general"] != null and game.state["settlements"].get(region, {}).get("owner", "") == "julii":
		t.check_eq(game.check("detach_general", [army_id]), "", "the general may step down in his own city")
	t.check_eq(game.check("merge_armies", [army_id, army_id]), "same_force", "an army cannot merge with itself")
	t.check_eq(game.check("split_army", [army_id, []]), "empty_selection", "nothing chosen to split")
	var garrison_size: int = game.state["settlements"].get(region, {}).get("garrison", []).size()
	if garrison_size > 0 and game.state["settlements"][region]["owner"] == "julii":
		var raised := game.raise_units(region, [0])
		t.check(raised["ok"], "the facade raises an army from the garrison")
		t.check_eq(game.state["settlements"][region]["garrison"].size(), garrison_size - 1, "one unit fewer in the garrison")
		t.check(game.merge_armies(raised["army_id"], army_id)["ok"], "and merges it into the field army")
		t.check(not game.state["armies"].has(raised["army_id"]), "the detachment is gone")


func test_a_besieged_garrison_stays_behind_its_walls(t) -> void:
	## Nobody marches out past the siege lines: raising an army from an
	## invested city, or drawing its garrison into the field, is refused
	## until the siege is lifted.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["alpha"]["garrison"].append({"template": "test_mob", "experience": 0, "strength_pct": 100})
	var before: int = state["settlements"]["alpha"]["garrison"].size()
	var besieger := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	MovementRules.reset_movement(data, state)
	t.check_eq(ForceRules.check_raise_army(data, state, "alpha", [0]), "", "before the siege the garrison may march out")
	t.check(SiegeRules.begin_siege(data, state, besieger, "alpha"), "red invests alpha")
	t.check_eq(ForceRules.check_raise_army(data, state, "alpha", [0]), "besieged", "under siege it stays behind the walls")
	t.check(not ForceRules.raise_army(data, state, "alpha", [0])["ok"], "raising is refused")
	t.check_eq(state["settlements"]["alpha"]["garrison"].size(), before, "and the garrison is untouched")
	SiegeRules.release(state, besieger)
	t.check_eq(ForceRules.check_raise_army(data, state, "alpha", [0]), "", "once lifted, the garrison marches again")


func test_a_general_carries_his_march_between_armies(t) -> void:
	## A general who leaves a spent army cannot lead a fresh one further this
	## season: the man remembers how far he has ridden, whether he stepped
	## down, was displaced by a merge, or is raised again from the garrison.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var marcus := Fixtures.add_character(state, "red", "red_marcus", {"command": 4, "location": "beta"})
	var titus := Fixtures.add_character(state, "red", "red_titus", {"command": 3, "location": "beta"})
	state["settlements"]["beta"]["garrison"].append({"template": "test_mob", "experience": 0, "strength_pct": 100})
	var spent := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	var fresh := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	var other := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	state["armies"][spent]["general"] = marcus
	MovementRules.reset_movement(data, state)
	state["armies"][spent]["movement_left"] = 0.5

	t.check(ForceRules.detach_general(data, state, spent)["ok"], "Marcus steps down in his city")
	t.check(ForceRules.attach_general(data, state, fresh, marcus)["ok"], "and takes the fresh army")
	t.check_near(float(state["armies"][fresh]["movement_left"]), 0.5, 0.0001, "which now marches no further than he already has")
	t.check_near(float(state["armies"][other]["movement_left"]), 2.0, 0.0001, "an army he does not lead is untouched")

	# Raised from the garrison under him, the new army is capped the same way.
	var raised := ForceRules.raise_army(data, state, "beta", [0], titus)
	t.check(raised["ok"], "Titus, who has not ridden today, raises the garrison")
	t.check_near(float(state["armies"][raised["army_id"]]["movement_left"]), 2.0, 0.0001, "with fresh legs")
	t.check(ForceRules.detach_general(data, state, fresh)["ok"], "Marcus steps down again")
	state["settlements"]["beta"]["garrison"].append({"template": "test_mob", "experience": 0, "strength_pct": 100})
	var raised_tired := ForceRules.raise_army(data, state, "beta", [0], marcus)
	t.check(raised_tired["ok"], "and raises the rest")
	t.check_near(float(state["armies"][raised_tired["army_id"]]["movement_left"]), 0.5, 0.0001, "no fresher than he is")

	# Displaced by a merge in the city, Titus remembers the merged army's march.
	state["armies"][raised["army_id"]]["movement_left"] = 0.25
	t.check(ForceRules.merge_armies(data, state, raised["army_id"], raised_tired["army_id"])["ok"], "Titus's army joins Marcus's")
	t.check(ForceRules.attach_general(data, state, other, titus)["ok"], "the displaced Titus takes the other army")
	t.check_near(float(state["armies"][other]["movement_left"]), 0.25, 0.0001, "which inherits his ride")

	MovementRules.reset_movement(data, state)
	t.check(not state["characters"][marcus].has("march_left"), "the new season forgets the ride")
	t.check(not state["characters"][titus].has("march_left"), "for everyone")


func test_garrisoning_and_battle_release_a_siege(t) -> void:
	## Every path that takes the besieger away from the walls lifts the siege
	## at once: garrisoning, merging away, a lost last unit, a march.
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var besieger := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears"])
	var second := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, besieger, "alpha"), "siege laid")
	state["armies"][second]["region"] = "alpha"
	t.check(ForceRules.merge_armies(data, state, besieger, second)["ok"], "the besieger merges into the newcomer")
	t.check(state["settlements"]["alpha"]["siege"] == null, "the siege is lifted when the besieger merges away")
	MovementRules.reset_movement(data, state)
	t.check(SiegeRules.begin_siege(data, state, second, "alpha"), "the merged army invests again")
	t.check(ForceRules.transfer_units(data, state, second, "garrison:alpha", [0])["error"] != "",
		"nobody transfers into a foreign city's garrison")
	state["armies"][second]["units"] = [state["armies"][second]["units"][0]]
	t.check(ForceRules.disband_unit(data, state, second, 0)["ok"], "the last unit is sent home")
	t.check(not state["armies"].has(second), "the captain's army is gone")
	t.check(state["settlements"]["alpha"]["siege"] == null, "and the siege with it")
