extends RefCounted
## The info-card data readers (visual layer step 1): unit and building
## profiles with glossary-named classes, skills and effects, and the
## class-to-building correspondence computed from the data — nothing
## authored twice, nothing shown as a raw id.


func test_unit_profile_names_everything(t) -> void:
	var game := Game.new()
	game.data = GameData.load_from("res://data")

	var levies := game.unit_profile("rural_levies")
	t.check(not levies.is_empty(), "a real template profiles")
	t.check_eq(levies["class_entry"]["name"], "Levies", "class named through the glossary")
	t.check(String(levies["class_entry"]["blurb"]) != "", "and explained")
	t.check_eq(levies["trained_at"]["kind"], "farms", "training building read from requirements")
	t.check(String(levies["trained_at"]["kind_entry"]["blurb"]) != "", "and explained too")
	t.check(int(levies["speed"]) > 0, "speed finally has a reader")

	# Some phalanx unit exists; its skill must arrive named and explained.
	var unit_ids: Array = game.data.units.keys()
	unit_ids.sort()
	var phalanx_profile := {}
	for unit_id in unit_ids:
		if game.data.units[unit_id].get("attributes", []).has("phalanx"):
			phalanx_profile = game.unit_profile(unit_id)
			break
	t.check(not phalanx_profile.is_empty(), "a phalanx unit exists in the roster")
	var named := false
	for skill in phalanx_profile["attributes"]:
		if skill["id"] == "phalanx":
			named = skill["name"] == "Phalanx" and String(skill["blurb"]) != ""
	t.check(named, "the phalanx skill is named and explained")

	t.check(game.unit_profile("no_such_unit").is_empty(), "unknown templates profile empty")


func test_building_profile_explains_effects_and_unlocks(t) -> void:
	var game := Game.new()
	game.data = GameData.load_from("res://data")

	# Every roman barracks tier must unlock something, and every unlock must
	# genuinely require that kind and tier in the unit data.
	var chain_ids: Array = game.data.chains.keys()
	chain_ids.sort()
	var barracks_id := ""
	for chain_id in chain_ids:
		var chain: Dictionary = game.data.chains[chain_id]
		if chain["kind"] == "barracks" and chain.get("cultures", []).has("roman"):
			barracks_id = chain_id
			break
	t.check(barracks_id != "", "a roman barracks chain exists")
	var barracks := game.building_profile(barracks_id)
	t.check_eq(barracks["kind_entry"]["name"], "Barracks", "kind named through the glossary")
	var total_unlocks := 0
	for level in barracks["levels"]:
		for unlock in level["unlocks"]:
			total_unlocks += 1
			var template: Dictionary = game.data.units[unlock["id"]]
			t.check_eq(template["requirements"]["building_kind"], "barracks",
				"unlock really trains here: " + String(unlock["id"]))
			t.check_eq(int(template["requirements"]["building_level"]), int(level["index"]),
				"unlock really opens at this tier: " + String(unlock["id"]))
			t.check(String(unlock["class_entry"]["name"]) != "", "unlock class is named")
	t.check(total_unlocks > 0, "the barracks unlocks units")

	# Effects arrive as named, explained breakdowns — every entry, no free
	# passes, and at least one exists to prove the walk saw anything at all.
	var effect_entries := 0
	for level in barracks["levels"]:
		for effect in level["effects"]:
			effect_entries += 1
			t.check(String(effect["name"]) != "" and String(effect["blurb"]) != ""
				and effect.has("value"),
				"effect entry carries name, blurb and value: " + String(effect["id"]))
	t.check(effect_entries > 0, "the barracks chain has effects to explain")

	# A temple with god-gated units only unlocks them under the right god.
	for chain_id in chain_ids:
		var chain: Dictionary = game.data.chains[chain_id]
		if chain["kind"] != "temple":
			continue
		var temple := game.building_profile(chain_id)
		for level in temple["levels"]:
			for unlock in level["unlocks"]:
				var need: Dictionary = game.data.units[unlock["id"]]["requirements"]
				var god := String(need.get("temple_god", ""))
				if god != "":
					t.check_eq(god, String(temple["god"]),
						"god-gated unit only listed under its god: " + String(unlock["id"]))

	t.check(game.building_profile("no_such_chain").is_empty(), "unknown chains profile empty")


func test_every_class_attribute_and_kind_is_covered(t) -> void:
	## The validator enforces this on the data side; this pins the engine's
	## view of the same contract, so a drift fails in both gates.
	var game := Game.new()
	game.data = GameData.load_from("res://data")
	var unit_ids: Array = game.data.units.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var profile := game.unit_profile(unit_id)
		t.check(String(profile["class_entry"]["blurb"]) != "",
			"class explained for " + String(unit_id))
		for skill in profile["attributes"]:
			t.check(String(skill["blurb"]) != "", "skill explained on " + String(unit_id))
	var chain_ids: Array = game.data.chains.keys()
	chain_ids.sort()
	for chain_id in chain_ids:
		var profile := game.building_profile(chain_id)
		t.check(String(profile["kind_entry"]["blurb"]) != "",
			"kind explained for " + String(chain_id))
		for level in profile["levels"]:
			for effect in level["effects"]:
				t.check(String(effect["blurb"]) != "",
					"effect %s explained on %s" % [effect["id"], chain_id])


func test_profiles_fall_back_without_a_glossary(t) -> void:
	var game := Game.new()
	game.data = Fixtures.data()
	game.state = Fixtures.state(game.data)

	var spears := game.unit_profile("test_spears")
	t.check_eq(spears["class_entry"]["name"], "Spear", "fixture classes prettify their id")
	t.check_eq(String(spears["class_entry"]["blurb"]), "", "with no invented blurb")
	var government := game.building_profile("test_government")
	t.check_eq(government["kind_entry"]["name"], "Government", "fixture kinds prettify too")
	t.check_eq(government["levels"].size(), 4, "levels enumerate")
	# test_mob demands government tier 1 but is neutral-culture, and the
	# fixture government is roman: the unlock walk must come back EMPTY —
	# the culture gate holds even in fixture worlds.
	t.check((government["levels"][0]["unlocks"] as Array).is_empty(),
		"the culture gate holds on fixture unlocks")
