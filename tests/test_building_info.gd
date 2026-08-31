extends RefCounted
## The building dossier: standing-total deltas, blockers that agree with the
## engine, unlock joins that agree with recruitment, and the two silent gates
## the old button never explained. Coverage tests run against the REAL tables,
## because Fixtures builds a GameData by hand and never loads the glossary.


func _real() -> Game:
	return Game.new_campaign("cornelii", 7, "medium", "long", false)


func test_delta_is_new_minus_old_not_the_standing_total(t) -> void:
	## A level's effects are the standing total AT that tier, so an upgrade is
	## worth the difference. roman_barracks: T4 recruit_xp 1, T5 recruit_xp 2.
	var game := _real()
	var region := _owned_region(game)
	var settlement: Dictionary = game.state["settlements"][region]
	settlement["buildings"]["roman_barracks"] = 4
	var sheet := game.building_dossier(region, "roman_barracks")
	var fifth := _tier(sheet, 5)
	t.check_eq(float(fifth["effects"]["recruit_xp"]), 2.0, "tier 5 stands at 2 experience")
	t.check_eq(float(fifth["delta"]["recruit_xp"]), 1.0, "but the upgrade is worth 1, not 2")


func test_max_aggregated_effects_are_measured_against_the_best_rival(t) -> void:
	## recruit_xp reaches the sim through effect_max, so a shipyard in a town
	## that already holds a Field of Mars changes nothing and must say so.
	var game := _real()
	var region := _coastal_region(game)
	var settlement: Dictionary = game.state["settlements"][region]
	settlement["buildings"]["roman_barracks"] = 5      # recruit_xp 2
	settlement["buildings"]["civic_naval"] = 1         # recruit_xp 0 -> tier 2 gives 1
	var sheet := game.building_dossier(region, "civic_naval")
	for line in _tier(sheet, 2)["lines"]:
		if line["key"] == "recruit_xp":
			t.check(line["matched"], "the shipyard's experience is already matched")
			t.check_eq(float(line["value"]), 0.0, "so the honest delta is nothing")
			t.check(String(line["rival"]) != "", "and the drawer can name what matches it")


func test_unlocks_follow_recruitment_not_culture(t) -> void:
	## Joining units to chains on unit.culture would promise a Roman player
	## Greek pikemen and a post-Marian Eagle Cohort in 270 BC. The join must
	## mirror RecruitmentRules: the faction whitelist and the era.
	var game := _real()
	var region := _owned_region(game)
	var chain: Dictionary = game.data.chains["roman_barracks"]
	var second := BuildingInfo.unlocked_by(game.data, game.state, region, chain, 2)
	var names := []
	for unit in second:
		names.append(unit["id"])
	t.check(names.has("roman_hastati"), "barracks 2 opens the hastati")
	t.check(not names.has("citizen_hoplites"),
		"but not the Greek hoplites a culture join would have promised")
	t.check(not names.has("punic_levy_spears"), "nor another people's levies")
	for unit in second:
		if unit["id"] == "auxilia_spearmen":
			t.check(bool(unit["era_locked"]),
				"a post-Marian unit is shown, but flagged as out of its age")

	var top := BuildingInfo.unlocked_by(game.data, game.state, region, chain, 5)
	t.check_eq(top.size(), 1, "barracks 5 opens exactly one unit")
	t.check(bool(top[0]["era_locked"]),
		"the Eagle Cohort is flagged as waiting on the Marian reform, not hidden")


func test_every_offered_project_has_an_unblocked_tier(t) -> void:
	## The cross-check that stops the drawer and the engine drifting apart: if
	## available_projects offers it, the dossier must show it as "next" with no
	## blockers, and if it does not, the dossier must give a reason.
	var game := _real()
	for region_id in game.state["settlements"]:
		var settlement: Dictionary = game.state["settlements"][region_id]
		if settlement["owner"] != game.state["player_faction"]:
			continue
		var offered := {}
		for project in game.available_buildings(region_id):
			offered[project["chain"]] = project
		for row in game.building_chains(region_id):
			var sheet := game.building_dossier(region_id, row["chain"])
			var next_index := int(row["built_tier"]) + 1
			if next_index > int(row["tier_count"]):
				continue
			var tier := _tier(sheet, next_index)
			if offered.has(row["chain"]):
				t.check_eq(String(tier["state"]), "next",
					"%s is offered, so the ladder calls it next" % row["chain"])
				t.check((tier["blockers"] as Array).is_empty(),
					"%s is offered, so nothing blocks it" % row["chain"])
				t.check_eq(int(tier["cost"]), int(offered[row["chain"]]["cost"]),
					"%s quotes the same price as the button" % row["chain"])
				t.check_eq(int(tier["build_turns"]), int(offered[row["chain"]]["build_turns"]),
					"%s quotes the same turns as the button" % row["chain"])
			else:
				t.check(not (tier["blockers"] as Array).is_empty(),
					"%s is withheld, so the ladder can say why" % row["chain"])


func test_blockers_name_the_real_reason(t) -> void:
	var game := _real()
	var region := _owned_region(game)
	var settlement: Dictionary = game.state["settlements"][region]

	settlement["buildings"]["civic_education"] = 0
	settlement["buildings"].erase("civic_education")
	var learning := game.building_dossier(region, "civic_education")
	var first := _tier(learning, 1)
	if String(first["state"]) == "locked":
		t.check_eq(String(first["blockers"][0]["kind"]), "settlement",
			"a small town is told it is too small for a scribal school")
		t.check(BuildingInfo.blocker_text(game.data, first["blockers"][0]).contains("Needs"),
			"and the sentence names what it needs")

	var walls := game.building_dossier(region, "roman_walls")
	var top := _tier(walls, (walls["tiers"] as Array).size())
	var kinds := []
	for blocker in top["blockers"]:
		kinds.append(String(blocker["kind"]))
	t.check(kinds.has("predecessor"),
		"a far rung says which rung comes first, not merely 'locked'")


func test_a_second_temple_is_barred_by_the_first(t) -> void:
	var game := _real()
	var region := _owned_region(game)
	var settlement: Dictionary = game.state["settlements"][region]
	for chain_id in settlement["buildings"].keys():
		if game.data.chains[chain_id]["kind"] == "temple":
			settlement["buildings"].erase(chain_id)
	settlement["buildings"]["roman_mars"] = 1
	var sheet := game.building_dossier(region, "roman_jupiter")
	var kinds := []
	for blocker in _tier(sheet, 1)["blockers"]:
		kinds.append(String(blocker["kind"]))
	t.check(kinds.has("temple"), "the town already keeps a god")
	t.check(BuildingInfo.blocker_text(game.data,
		{"kind": "temple", "params": {"name": "Cult of Mars", "god": "Mars"}}).contains("Mars"),
		"and the sentence names which one")


func test_unaffordable_is_reported_apart_from_blockers(t) -> void:
	## available_projects never filtered on money and queue_project just returned
	## false, so the old button silently did nothing. The dossier separates them.
	var game := _real()
	var region := _owned_region(game)
	var chain := ""
	for row in game.building_chains(region):
		if row["buildable_now"]:
			chain = row["chain"]
			break
	t.check(chain != "", "the capital has something to build")
	game.state["factions"][game.state["player_faction"]]["treasury"] = 0
	var sheet := game.building_dossier(region, chain)
	t.check(not bool(sheet["action"]["affordable"]), "a bankrupt house cannot pay")
	t.check(not bool(sheet["action"]["can_queue"]), "so the button must not pretend")
	t.check_eq(String(sheet["action"]["reason"]), "unaffordable",
		"and the reason is money, not a building rule")
	t.check((_tier(sheet, int(sheet["built_tier"]) + 1)["blockers"] as Array).is_empty(),
		"poverty is not a blocker: the player may still plan and save")


func test_recruitment_reports_both_silent_gates(t) -> void:
	## queue_unit refuses on treasury AND on population. A drawer that modelled
	## only coin would rebuild the dead button in the muster hall.
	var game := _real()
	var region := _owned_region(game)
	var settlement: Dictionary = game.state["settlements"][region]
	settlement["buildings"]["roman_barracks"] = 5
	var sheet := game.unit_dossier(region, "roman_hastati")
	t.check(not sheet.is_empty(), "the hastati have a dossier")

	game.state["factions"][game.state["player_faction"]]["treasury"] = 1000000
	settlement["population"] = int(game.data.balance["growth"]["min_population"]) + 10
	sheet = game.unit_dossier(region, "roman_hastati")
	t.check(not bool(sheet["action"]["manpower"]), "an empty town has no men to give")
	t.check_eq(String(sheet["action"]["reason"]), "manpower", "and says so rather than money")
	t.check(not RecruitmentRules.queue_unit(game.data, game.state, region, "roman_hastati"),
		"which is exactly what the engine does")


func test_unit_dossier_names_the_building_it_wants(t) -> void:
	var game := _real()
	var region := _owned_region(game)
	var settlement: Dictionary = game.state["settlements"][region]
	settlement["buildings"]["roman_barracks"] = 1
	var sheet := game.unit_dossier(region, "roman_principes")
	t.check_eq(String(sheet["requires"]["kind"]), "barracks", "principes want a barracks")
	t.check_eq(int(sheet["requires"]["level"]), 3, "at tier 3")
	t.check_eq(int(sheet["requires"]["best_tier"]), 1, "and the town has tier 1")
	t.check(not bool(sheet["action"]["can_queue"]), "so they cannot be raised yet")
	t.check_eq(String(sheet["action"]["reason"]), "building", "for want of a building")


func test_glossary_covers_every_effect_the_data_uses(t) -> void:
	var game := _real()
	var described := {}
	var inert := {}
	for row in game.data.effects_glossary["effects"]:
		described[String(row["key"])] = true
		if String(row["status"]) == "inert":
			inert[String(row["key"])] = true
			t.check(String(row.get("note", "")) != "",
				"%s is read by no engine call site, so it must carry a note" % row["key"])
	var used := {}
	for chain_id in game.data.chains:
		for level in game.data.chains[chain_id]["levels"]:
			for key in level.get("effects", {}):
				used[String(key)] = true
	for key in used:
		t.check(described.has(key), "the glossary explains '%s'" % key)
	t.check(inert.has("weapon_upgrade") and inert.has("armor_upgrade"),
		"the two effects with no engine reader are marked inert, not sold as bonuses")


func test_every_derived_id_has_an_engine_branch(t) -> void:
	## The glossary may only name a derived number BuildingInfo can compute;
	## otherwise a line would silently vanish.
	var game := _real()
	var region := _coastal_region(game)
	var known := ["corruption_relief_pct", "recruit_xp_cap",
		"wall_defence_multiplier", "sea_routes"]
	for row in game.data.effects_glossary["effects"]:
		for derived in row.get("derived", []):
			t.check(known.has(String(derived["id"])),
				"BuildingInfo computes '%s'" % derived["id"])
	# and the walls case from the complaint actually produces its line
	var settlement: Dictionary = game.state["settlements"][region]
	settlement["buildings"]["roman_walls"] = 3
	var sheet := game.building_dossier(region, "roman_walls")
	var found := false
	for line in _tier(sheet, 4)["lines"]:
		if line["key"] == "wall_defence_multiplier":
			found = true
			t.check(String(line["text"]).contains("2.5"), "walls 4 reads x2.5")
			t.check(String(line["text"]).contains("2.0"), "up from x2.0")
	t.check(found, "the walls upgrade explains what it buys")


func test_dossier_is_deterministic(t) -> void:
	var game := _real()
	var region := _owned_region(game)
	var once := game.building_dossier(region, "roman_walls")
	var twice := game.building_dossier(region, "roman_walls")
	t.check_eq(str(once), str(twice), "the same state describes itself the same way")


func _tier(sheet: Dictionary, index: int) -> Dictionary:
	for tier in sheet["tiers"]:
		if int(tier["index"]) == index:
			return tier
	return {}


func _owned_region(game: Game) -> String:
	return String(game.state["factions"][game.state["player_faction"]]["capital"])


func _coastal_region(game: Game) -> String:
	var owned: Array = []
	for region_id in game.state["settlements"]:
		if game.state["settlements"][region_id]["owner"] == game.state["player_faction"]:
			owned.append(region_id)
	owned.sort()
	for region_id in owned:
		if MapRules.coastal(game.data, region_id):
			return region_id
	return _owned_region(game)
