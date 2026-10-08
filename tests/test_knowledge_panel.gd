extends RefCounted
## Knowledge wording follows the facade's unmet blockers without changing
## adoption rules, exposing other courts' ledgers, or mutating their inputs.


func _data() -> GameData:
	var data := Fixtures.data()
	data.effects_glossary = JSON.parse_string(FileAccess.get_file_as_string("res://data/effects_glossary.json"))
	return data


func test_every_existing_blocker_has_resolved_glossary_wording(t) -> void:
	var data := _data()
	var cases := [
		[{"kind": "tradition", "params": {"factions": ["red", "blue"]}}, "a tradition practiced by Red, Blue"],
		[{"kind": "building", "params": {"building_kind": "siege_workshop", "level": 3, "have": 1}}, "siege workshop (tier 3; current tier 1)"],
		[{"kind": "resource", "params": {"resource": "olive_oil"}}, "the olive oil trade"],
		[{"kind": "hidden_resource", "params": {"resource": "iron_ore"}}, "lands of iron ore"],
		[{"kind": "coastal", "params": {}}, "a coast"],
		[{"kind": "technique", "params": {"technique": "test_letters", "name": "Letters"}}, "practice of Letters"],
		[{"kind": "era", "params": {"era": "post_marian"}}, "the post-marian era"],
		[{"kind": "battles_won", "params": {"needs": 2, "have": 1}}, "2 battles won (1 recorded)"],
		[{"kind": "battles_lost", "params": {"needs": 1, "have": 0}}, "1 battle lost (0 recorded)"],
		[{"kind": "faced", "params": {"needs": 3, "have": 2, "unit_class": "heavy_cavalry"}}, "3 battles against heavy cavalry (2 recorded)"],
	]
	t.check_eq(cases.size(), data.effects_glossary.knowledge.blockers.size(), "all authored blocker kinds exercised")
	for row in cases:
		var before := JSON.stringify(row[0])
		t.check_eq(KnowledgePanel.blocker_text(data, row[0]), row[1], "wording for " + row[0].kind)
		t.check_eq(JSON.stringify(row[0]), before, "formatting preserves " + row[0].kind + " parameters")


func test_battle_counts_choose_authored_singular_and_plural(t) -> void:
	var data := _data()
	data.effects_glossary.knowledge.battle_one = "single encounter"
	data.effects_glossary.knowledge.battle_many = "encounters"
	for kind in ["battles_won", "battles_lost", "faced"]:
		for amount in [1, 2]:
			var text := KnowledgePanel.blocker_text(data, {"kind": kind,
				"params": {"needs": amount, "have": 0, "unit_class": "infantry"}})
			t.check(text.contains("single encounter" if amount == 1 else "encounters"),
				"plural wording is authored for %s %d" % [kind, amount])


func test_formatter_uses_glossary_and_preserves_engine_order(t) -> void:
	var data := _data()
	data.effects_glossary.knowledge.blockers.coastal = "COAST TEST"
	data.effects_glossary.knowledge.blockers.resource = "TRADE TEST {resource}"
	data.effects_glossary.knowledge.separator = " / "
	t.check_eq(KnowledgePanel.prerequisites_text(data, [
		{"kind": "resource", "params": {"resource": "grain"}},
		{"kind": "coastal", "params": {}},
	]), "TRADE TEST grain / COAST TEST", "authored text and separator preserve authoritative order")
	t.check_eq(KnowledgePanel.prerequisites_text(data, []), data.effects_glossary.knowledge.none,
		"empty blocker list uses authored wording")


func test_unknown_and_fixture_blockers_do_not_crash(t) -> void:
	var data := _data()
	t.check_eq(KnowledgePanel.blocker_text(data, {"kind": "future_requirement", "params": {}}),
		data.effects_glossary.knowledge.unknown, "unknown requirement uses authored fallback")
	data.effects_glossary = {}
	t.check_eq(KnowledgePanel.blocker_text(data, {"kind": "future_requirement", "params": {}}),
		"future requirement", "synthetic data without a glossary retains an identifier")
	t.check_eq(KnowledgePanel.prerequisites_text(data, []), "", "empty synthetic glossary is safe")


func test_panel_shows_only_actual_unmet_requirements_and_does_not_mutate(t) -> void:
	var game := Game.new()
	game.data = _data()
	game.state = Fixtures.state(game.data)
	# Red has a coast and a tier-one barracks, but has not won two battles.
	var technique: Dictionary = game.data.techniques.test_smithing
	technique.prerequisites.building_kind = "barracks"
	technique.prerequisites.building_level = 1
	technique.prerequisites.coastal = true
	technique.prerequisites.battles_won = 2
	game.state.factions.red.knowledge.test_smithing = {"stage": "aware", "progress": 0}
	var before := JSON.stringify(game.state)
	var overview := game.technique_overview("red")
	var entry: Dictionary = {}
	for item in overview.entries:
		if item.id == "test_smithing":
			entry = item
	t.check(not entry.is_empty(), "aware technique remains visible")
	t.check_eq(entry.blockers, [{"kind": "battles_won", "params": {"needs": 2, "have": 0}}],
		"the authoritative overview omits satisfied building and coastal requirements")
	var panel := KnowledgePanel.new()
	panel.game = game
	panel._build_aware_entry(entry, false, 10000)
	var wants := ""
	for child in panel._content.get_children():
		if child is Label and child.text.contains("Wants:"):
			wants = child.text
	t.check_eq(wants, "    Wants: 2 battles won (0 recorded)", "the actual panel shows only the remaining blocker")
	t.check_eq(JSON.stringify(game.state), before, "overview and panel leave state and RNG unchanged")
	panel.free()


func test_satisfied_requirements_remove_wants_and_allow_the_existing_action(t) -> void:
	var game := Game.new()
	game.data = _data()
	game.state = Fixtures.state(game.data)
	game.state.factions.red.knowledge.test_smithing = {"stage": "aware", "progress": 0}
	var entry: Dictionary = {}
	for item in game.technique_overview("red").entries:
		if item.id == "test_smithing":
			entry = item
	t.check(entry.ready and entry.blockers.is_empty(), "existing adoption rules deem this technique ready")
	var panel := KnowledgePanel.new()
	panel.game = game
	panel._build_aware_entry(entry, false, 10000)
	var wants := false
	var action := false
	for child in panel._content.get_children():
		if child is Label and child.text.contains("Wants:"):
			wants = true
		if child is HBoxContainer:
			for control in child.get_children():
				if control is Button:
					action = not control.disabled
	t.check(not wants, "no missing-requirement line is invented for a ready technique")
	t.check(action, "the existing adoption action remains available")
	panel.free()
