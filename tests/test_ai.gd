extends RefCounted
## The bounded opponent. The world used to be deliberately quiet — nothing
## marched, besieged or declared war — which left the day's sequence with an
## empty stage. These guard that it moves, that it moves within its rules, and
## that it moves the same way after a save.


func test_the_world_actually_moves(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var seen := {}
	for i in range(40):
		game.end_turn()
		for beat in TurnJournal.of(game.state):
			seen[String(beat["kind"])] = int(seen.get(String(beat["kind"]), 0)) + 1
	for kind in ["army_march", "siege_begun", "battle_fought", "settlement_captured", "war_declared"]:
		t.check(seen.has(kind), "forty turns produce a %s (the map changes hands)" % kind)


func test_the_ai_never_betrays_an_ally(t) -> void:
	## The Roman houses start allied to the Senate and to each other; nothing
	## the AI does may quietly turn that into a war.
	var game := Game.new_campaign("julii", 11)
	var allies: Array = []
	var faction_ids: Array = game.state["factions"].keys()
	faction_ids.sort()
	for a in faction_ids:
		for b in faction_ids:
			if a < b and DiplomacyRules.stance_between(game.state, a, b) == "alliance":
				allies.append([a, b])
	t.check(not allies.is_empty(), "the world starts with alliances in it")

	for i in range(30):
		game.end_turn()
	for pair in allies:
		# An alliance may end honestly — a civil war outlaws a house — but it
		# must never be the AI's own war declaration that did it.
		var stance := DiplomacyRules.stance_between(game.state, pair[0], pair[1])
		if stance == "war":
			t.check(bool(game.state["factions"][pair[0]]["at_civil_war"])
					or bool(game.state["factions"][pair[1]]["at_civil_war"]),
				"%s and %s only came to blows through civil war" % [pair[0], pair[1]])


func test_the_ai_holds_its_fire_at_the_start(t) -> void:
	## A new campaign must not catch fire on turn one. The grace period is a
	## balance constant, not a hard-coded number.
	var game := Game.new_campaign("julii", 42)
	var grace := int(game.data.balance["ai"]["war_grace_turns"])
	var before := _stances(game.state)
	for i in range(grace):
		game.end_turn()
	var declared := 0
	var now := _stances(game.state)
	for pair in now:
		if now[pair] == "war" and before.get(pair, "") != "war":
			declared += 1
	t.check_eq(declared, 0, "no wars are declared during the opening grace turns")


func test_the_ai_replays_identically_after_a_save(t) -> void:
	## The highest-risk part of the change: new loops and new rolls in the AI.
	## An unsorted key or an unseeded draw here desyncs a loaded campaign.
	var game := Game.new_campaign("julii", 2024)
	for i in range(12):
		game.end_turn()

	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not resumed.state.is_empty(), "the campaign saves and reloads")

	for i in range(10):
		game.end_turn()
		resumed.end_turn()
		t.check_eq(_canonical(game.state["journal"]), _canonical(resumed.state["journal"]),
			"turn %d plays out identically after a save" % i)
	t.check_eq(_canonical(game.state), _canonical(resumed.state), "and the worlds are the same world")


func test_the_ai_only_storms_what_it_outnumbers(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var ratio := float(game.data.balance["ai"]["march_strength_ratio"])
	var checked := 0
	for i in range(40):
		var garrisons := {}
		var region_ids: Array = game.state["settlements"].keys()
		region_ids.sort()
		for region_id in region_ids:
			garrisons[region_id] = CombatRules.soldiers_in(
				game.data, game.state["settlements"][region_id]["garrison"])
		game.end_turn()
		for beat in TurnJournal.of(game.state):
			if String(beat["kind"]) != "siege_begun":
				continue
			checked += 1
			var defenders := int(beat["extra"].get("garrison", 0))
			t.check(float(beat["value"]) >= float(defenders) * ratio,
				"an army of %s does not invest a garrison of %d" % [beat["value"], defenders])
	t.check(checked > 0, "sieges were actually begun and checked (%d)" % checked)


func test_ai_armies_are_reinforced(t) -> void:
	## The single change that makes the world move: an AI column resting in one
	## of its own cities draws the surplus garrison. Without it an AI army is
	## whatever it started as, takes casualties forever, and the map freezes.
	var game := Game.new_campaign("julii", 42)
	var starting := _biggest_ai_army(game)
	for i in range(40):
		game.end_turn()
	t.check(_biggest_ai_army(game) > starting,
		"AI columns grow over a campaign (%d -> %d)" % [starting, _biggest_ai_army(game)])

	# But never by stripping a city bare.
	var target := int(game.data.balance["ai"]["garrison_target"])
	var cap := int(game.data.balance["ai"]["field_army_max_units"])
	for region_id in game.state["settlements"]:
		var settlement: Dictionary = game.state["settlements"][region_id]
		var owner: String = String(settlement["owner"])
		if owner == "julii" or owner == "rebels" or settlement["siege"] != null:
			continue
		if _ai_army_in(game, owner, region_id) == "":
			continue
		t.check(settlement["garrison"].size() >= target or settlement["garrison"].is_empty(),
			"%s keeps its walls manned while feeding the column" % region_id)
	for army in game.state["armies"].values():
		if String(army["owner"]) == "julii":
			continue
		t.check(army["units"].size() <= cap, "no AI column grows past its cap")


func test_the_world_changes_hands(t) -> void:
	## A campaign the player never touches must still redraw its own borders —
	## that is the whole point of watching the day.
	var game := Game.new_campaign("julii", 4242)
	var before := _owner_counts(game)
	for i in range(80):
		game.end_turn()
	var after := _owner_counts(game)
	var moved := 0
	for faction_id in after:
		if int(after[faction_id]) != int(before.get(faction_id, 0)):
			moved += 1
	t.check(moved >= 4, "eighty turns move the borders of several powers (%d)" % moved)
	t.check(int(after.get("rebels", 0)) < int(before.get("rebels", 0)),
		"the independents lose ground to somebody")


func _biggest_ai_army(game: Game) -> int:
	var biggest := 0
	for army in game.state["armies"].values():
		if String(army["owner"]) != "julii":
			biggest = maxi(biggest, army["units"].size())
	return biggest


func _ai_army_in(game: Game, faction_id: String, region_id: String) -> String:
	for army_id in game.state["armies"]:
		var army: Dictionary = game.state["armies"][army_id]
		if army["owner"] == faction_id and String(army["region"]) == region_id:
			return army_id
	return ""


func _owner_counts(game: Game) -> Dictionary:
	var counts := {}
	for settlement in game.state["settlements"].values():
		var owner: String = String(settlement["owner"])
		counts[owner] = int(counts.get(owner, 0)) + 1
	return counts


func _stances(state: Dictionary) -> Dictionary:
	var stances := {}
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for i in range(faction_ids.size()):
		for j in range(i + 1, faction_ids.size()):
			stances["%s|%s" % [faction_ids[i], faction_ids[j]]] = \
				DiplomacyRules.stance_between(state, faction_ids[i], faction_ids[j])
	return stances


func _canonical(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))
