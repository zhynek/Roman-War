extends RefCounted
## The phenomena the societal layer exists to produce, asserted over real
## campaigns on the real data tables rather than on a fixture. These are the
## tests that would catch the model quietly ceasing to mean anything.
##
## Two campaigns run from the same seed and diverge only in what they build and
## what they tax: one invests in force, the other in its people.

const MILITARY := ["barracks", "walls", "stables", "archery_range", "execution", "siege_workshop"]
const CIVIC := ["health", "education", "temple", "roads", "farms", "market", "government"]
## Shortened from 80/40 with the branch merge. The horizon has to be one the
## house survives, and the world is lethal now: with the modular AI and a real
## diplomacy model, a house that only manages its own provinces for eighty
## turns is conquered outright, and every societal reading is then averaged
## over zero regions. Sixty turns still shows the whole arc this test exists
## for — force works, then it does not — with both houses still standing to be
## compared.
const HORIZON := 60
const MIDPOINT := 30


func _play(strategy: String, turns: int, snapshot_at: int) -> Dictionary:
	var game := Game.new_campaign("julii", 11)
	var snapshot := {}
	for turn in range(turns):
		var region_ids: Array = game.state["settlements"].keys()
		region_ids.sort()
		for region_id in region_ids:
			if game.state["settlements"][region_id]["owner"] != "julii":
				continue
			game.set_tax_level(region_id, "very_high" if strategy == "military" else "normal")
			var wanted: Array = MILITARY if strategy == "military" else CIVIC
			for project in game.available_buildings(region_id):
				if wanted.has(project["kind"]) and game.queue_building(region_id, project["chain"]):
					break
		game.end_turn()
		if turn + 1 == snapshot_at:
			snapshot = _measure(game)
	var final := _measure(game)
	final["at_snapshot"] = snapshot
	return final


func _measure(game: Game) -> Dictionary:
	var faction: Dictionary = game.state["factions"]["julii"]
	var stocks := SocietyRules.faction_stocks(game.data, faction)
	var regions := 0
	var legitimacy := 0.0
	var grievance := 0.0
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = game.state["settlements"][region_id]
		if settlement["owner"] != "julii":
			continue
		regions += 1
		var settlement_stocks := SocietyRules.stocks_of(game.data, settlement)
		legitimacy += float(settlement_stocks["legitimacy"])
		grievance += float(settlement_stocks["grievance"])
	return {
		"regions": regions,
		"treasury": int(faction["treasury"]),
		"legitimacy": legitimacy / float(maxi(regions, 1)),
		"grievance": grievance / float(maxi(regions, 1)),
		"craft": float(stocks["knowledge"]),
		"martial": float(stocks["martial_ethos"]),
		"advances": faction.get("advances", []).size(),
	}


func test_force_holds_for_a_while_and_then_does_not(t) -> void:
	## The phenomenon the whole layer exists for: investing only in force works,
	## and then it does not, and the bill arrives long after the decision.
	var military := _play("military", HORIZON, MIDPOINT)
	var civic := _play("civic", HORIZON, MIDPOINT)
	var military_mid: Dictionary = military["at_snapshot"]
	var civic_mid: Dictionary = civic["at_snapshot"]

	# Halfway, the militarist is still solvent and still holds everything.
	t.check_eq(int(military_mid["regions"]), int(civic_mid["regions"]),
		"at the midpoint both houses still hold their provinces")
	t.check(int(military_mid["treasury"]) > 0, "and the militarist is far from broke")

	# But the societal reading has already diverged sharply.
	t.check(float(military_mid["legitimacy"]) < float(civic_mid["legitimacy"]),
		"the militarist is already ruling on much less consent")
	t.check(float(military_mid["grievance"]) > float(civic_mid["grievance"]) * 2.0,
		"and has accumulated far more resentment than the civic house")
	t.check(float(military_mid["martial"]) > float(civic_mid["martial"]),
		"it is the more martial society, which is what it was buying")

	# By the horizon the bill has arrived.
	t.check(int(military["regions"]) < int(military_mid["regions"]),
		"the militarist loses provinces it held at the midpoint")
	# This used to also require the civic house to lose no provinces at all.
	# That held while the world was passive; it does not now, and it should not
	# have been the assertion anyway. Province count is a shared channel — with
	# real AI opponents both houses are conquered from by neighbours who owe
	# their society nothing, which swamps the signal.
	#
	# What this layer actually claims is about CONSENT, and that claim still
	# holds all the way to the horizon: the house that bought force is still
	# ruling on less of it, and still carrying the resentment it ran up. The
	# midpoint checks above show the divergence opening; these show it did not
	# close once the bill arrived.
	t.check(float(military["legitimacy"]) < float(civic["legitimacy"]),
		"at the horizon the militarist still rules on less consent (%.1f against %.1f)"
			% [military["legitimacy"], civic["legitimacy"]])
	t.check(float(military["grievance"]) > float(civic["grievance"]),
		"and is still carrying more of what it ran up (%.1f against %.1f)"
			% [military["grievance"], civic["grievance"]])


func test_public_investment_compounds(t) -> void:
	var civic := _play("civic", HORIZON, MIDPOINT)
	var mid: Dictionary = civic["at_snapshot"]
	t.check(int(civic["treasury"]) > int(mid["treasury"]),
		"a province that consents to being governed keeps paying")
	t.check(float(civic["craft"]) > float(mid["craft"]),
		"and its institutions accumulate craft")
	t.check(int(civic["advances"]) >= int(mid["advances"]),
		"which is never lost while the institutions stand")
	t.check(int(civic["advances"]) > 0, "the civic path actually works something out")


func test_craft_is_lost_when_its_institutions_are(t) -> void:
	## Nothing is destroyed; it simply stops being taught.
	var game := Game.new_campaign("julii", 11)
	var faction: Dictionary = game.state["factions"]["julii"]
	var first: String = AdvanceRules.available_to(game.data, "julii")[0]
	faction["society"]["knowledge"] = float(game.data.advances[first]["knowledge_threshold"]) + 5.0
	AdvanceRules.refresh(game.data, game.state, ["julii"])
	t.check(AdvanceRules.held(game.state, "julii").has(first), "the advance is known")

	# No institutions anywhere: craft decays, and the advance goes with it.
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if game.state["settlements"][region_id]["owner"] == "julii":
			game.state["settlements"][region_id]["buildings"] = {}
	for turn in range(60):
		SocietyRules.apply_faction_turn(game.data, game.state, "julii")
		AdvanceRules.refresh(game.data, game.state, ["julii"])
	t.check(not AdvanceRules.held(game.state, "julii").has(first),
		"a people who stop teaching a thing stop being able to do it")


func test_same_seed_reaches_the_same_society(t) -> void:
	var a := Game.new_campaign("julii", 23)
	var b := Game.new_campaign("julii", 23)
	for turn in range(25):
		a.end_turn()
		b.end_turn()
	t.check_eq(SaveGame.to_json(a.state), SaveGame.to_json(b.state),
		"the societal layer is deterministic end to end")


func test_a_campaign_in_crisis_survives_save_and_load(t) -> void:
	## Continuous stocks through a lossy JSON writer is exactly how a save starts
	## replaying differently from the live game. It must not.
	var game := Game.new_campaign("julii", 11)
	for turn in range(45):
		for region_id in game.state["settlements"]:
			if game.state["settlements"][region_id]["owner"] == "julii":
				game.set_tax_level(region_id, "very_high")
		game.end_turn()

	var restored := SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not restored.is_empty(), "the campaign saves and parses back")
	var resumed := Game.new()
	resumed.data = game.data
	resumed.resolver = AutoResolver.new()
	resumed.state = restored
	for turn in range(10):
		game.end_turn()
		resumed.end_turn()
	# Compared in canonical JSON form: a parsed state holds 2.0 where the live one
	# holds 2, which is meaningless — every reader coerces. What must match is the
	# societal stocks, which are continuous and would otherwise drift apart.
	t.check_eq(_canonical(game.state), _canonical(resumed.state),
		"a saved campaign mid-crisis marches in step with the live one")


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))
