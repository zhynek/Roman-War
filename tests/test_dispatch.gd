extends RefCounted
## Fog of war over the day's news, and the contract between the engine's beat
## kinds and the prose table that renders them.


func test_every_beat_kind_has_prose(t) -> void:
	## The validator enforces this at build time; the suite enforces it against
	## a live campaign, so a kind that only appears under rare conditions is
	## still covered.
	var data := GameData.load_from()
	t.check(data.ok(), "data loads")
	for kind in TurnJournal.KINDS:
		t.check(data.dispatch_beats.has(kind), "dispatch.json says what to print for " + kind)
	for kind in data.dispatch_beats:
		t.check(TurnJournal.KINDS.has(String(kind)), "no orphan prose for " + String(kind))
		var chapter: String = String(data.dispatch_beats[kind]["chapter"])
		t.check(not data.dispatch_chapter(chapter).is_empty(), "%s names a real chapter" % kind)


func test_every_beat_renders_without_leftover_tokens(t) -> void:
	var game := Game.new_campaign("julii", 42)
	var rendered := {}
	for i in range(60):
		game.end_turn()
		for beat in TurnJournal.of(game.state):
			if rendered.has(beat["kind"]):
				continue
			rendered[beat["kind"]] = true
			for text in [DispatchFormat.headline(game.data, game.state, beat),
					DispatchFormat.body(game.data, game.state, beat)]:
				t.check(text.length() > 0, "%s renders something" % beat["kind"])
				t.check(not text.contains("{"), "%s leaves no unresolved token: %s" % [beat["kind"], text])
	t.check(rendered.size() > 15, "a long campaign exercises most beat kinds (%d)" % rendered.size())


func test_private_news_never_leaks(t) -> void:
	var game := Game.new_campaign("julii", 42)
	for i in range(30):
		game.end_turn()
		var mine := game.day_beats("julii")
		for beat in mine:
			var rule: String = String(game.data.dispatch_beats[beat["kind"]]["visibility"])
			if rule != "own":
				continue
			t.check(String(beat["faction"]) == "julii" or String(beat["other"]) == "julii",
				"a rival's %s is not our business" % beat["kind"])


func test_the_fog_hides_distant_news(t) -> void:
	## A region-gated beat reaches us only where we have eyes. Checked against
	## the filter directly so the rule is proved even on a turn where no army
	## happens to march past our scouts.
	var game := Game.new_campaign("julii", 42)
	for i in range(25):
		game.end_turn()
	var seen := game.visible_regions("julii")

	var watched := ""
	var hidden := ""
	var region_ids: Array = game.state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if seen.has(region_id) and watched == "":
			watched = region_id
		elif not seen.has(region_id) and hidden == "":
			hidden = region_id
	t.check(watched != "" and hidden != "", "the map has both watched and unwatched ground")

	var march := {
		"kind": "army_march", "faction": "gaul", "other": "rebels",
		"region": watched, "subject": "", "value": 100, "extra": {},
	}
	t.check_eq(DispatchRules.visible_beats(game.data, game.state, [march], "julii").size(), 1,
		"a march into ground we watch is reported")
	march["region"] = hidden
	t.check_eq(DispatchRules.visible_beats(game.data, game.state, [march], "julii").size(), 0,
		"a march beyond our maps is not")

	# And the live journal obeys the same rule.
	for beat in game.day_beats("julii"):
		if String(game.data.dispatch_beats[beat["kind"]]["visibility"]) == "region":
			t.check(seen.has(String(beat["region"])),
				"we only hear about %s because we can see %s" % [beat["kind"], beat["region"]])


func test_wars_are_public_knowledge(t) -> void:
	## The player asked to be told when factions go to war — including wars
	## that are not theirs. A declaration is proclaimed, not discovered.
	var game := Game.new_campaign("julii", 42)
	var third_party_wars := 0
	for i in range(60):
		game.end_turn()
		var mine := game.day_beats("julii")
		for beat in TurnJournal.of(game.state):
			if String(beat["kind"]) != "war_declared":
				continue
			t.check(mine.has(beat), "we hear that %s and %s are at war"
				% [beat["faction"], beat["other"]])
			if String(beat["faction"]) != "julii" and String(beat["other"]) != "julii":
				third_party_wars += 1
	t.check(third_party_wars > 0, "the world goes to war around us and we hear of it")


func test_the_sequence_is_capped_and_ordered(t) -> void:
	var game := Game.new_campaign("julii", 42)
	for i in range(20):
		game.end_turn()
	var cap := int(game.data.balance["dispatch"]["max_sequence_beats"])
	var minimum := int(game.data.balance["dispatch"]["sequence_min_severity"])

	# A crowded day: every beat in the world, not just the ones we may know.
	var crowded := TurnJournal.of(game.state)
	var played := DispatchRules.sequence_beats(game.data, crowded)
	t.check(played.size() <= cap, "a busy day never outstays its welcome (%d)" % played.size())
	for beat in played:
		var template: Dictionary = game.data.dispatch_beats[beat["kind"]]
		t.check(bool(template["in_sequence"]), "%s is meant to be played" % beat["kind"])
		t.check(int(template["severity"]) >= minimum, "%s is worth watching" % beat["kind"])

	# Survivors keep journal order, so the day still reads as events in sequence.
	var last := -1
	for beat in played:
		var at := crowded.find(beat)
		t.check(at > last, "the day plays forwards, not by rank")
		last = at


func test_the_sequence_is_reproducible(t) -> void:
	## src/core/ has to replay identically, and sort_custom makes no stability
	## promise — the cap must break ties on position, not on dictionary order.
	var first := Game.new_campaign("julii", 909)
	var second := Game.new_campaign("julii", 909)
	for i in range(20):
		first.end_turn()
		second.end_turn()
	t.check_eq(JSON.stringify(DispatchRules.sequence_beats(first.data, TurnJournal.of(first.state))),
		JSON.stringify(DispatchRules.sequence_beats(second.data, TurnJournal.of(second.state))),
		"the same day plays the same way twice")


func test_every_icon_actually_renders(t) -> void:
	## The interface font is Open Sans, which has no Miscellaneous Symbols
	## block. A mark it cannot draw shows the player an empty box, and nothing
	## else in the suite would notice.
	var label := Label.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(label)
	var font: Font = label.get_theme_default_font()
	t.check(font != null, "the interface font resolves")

	var marks: Array = DispatchFormat.ICON_MARKS.values()
	marks.append_array([DispatchFormat.DAWN_MARK, DispatchFormat.DUSK_MARK,
		DispatchFormat.FALLBACK_MARK])
	for mark in marks:
		var drawable := true
		for i in range(String(mark).length()):
			if not font.has_char(String(mark).unicode_at(i)):
				drawable = false
		t.check(drawable, "the font can draw the mark '%s'" % mark)

	# And every icon key the data table names has a mark to draw.
	var data := GameData.load_from()
	for kind in data.dispatch_beats:
		var icon: String = String(data.dispatch_beats[kind]["icon"])
		t.check(DispatchFormat.ICON_MARKS.has(icon),
			"%s names icon '%s', which has a mark" % [kind, icon])

	label.free()
