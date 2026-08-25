extends RefCounted
## The chronicle (Phase 6): battles, captures and revolts recorded at the
## choke points; the war ledger opening mid-fight and closing into summaries;
## reigns detected by leader id (kill paths emit no notices); alliance and
## destruction diffs; technique and edict records with leaders' deeds; the
## per-turn cap and the compaction bound; resolved() as the narrator feed.


func test_battles_write_the_annals(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "red_general", {"location": "beta", "command": 5})
	var attacker := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	state["armies"][attacker]["general"] = "red_general"
	var defender := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	CombatRules.attack_army(data, state, AutoResolver.new(), CampaignRng.seeded(3), attacker, defender)

	var battle := _last_of(state, "battle")
	t.check(not battle.is_empty(), "the battle is chronicled")
	t.check_eq(String(battle["subjects"]["region"]), "alpha", "where it was fought")
	t.check_eq(String(battle["details"]["winner"]), "attacker", "and who prevailed")
	t.check_eq(state["wars"].size(), 1, "the fighting opened the war ledger")
	t.check_eq(int(state["wars"][0]["battles"]), 1, "and counted the battle")
	t.check_eq(bool(state["wars"][0]["logged"]), false, "the declaration entry waits for the scribes")
	t.check_eq(int(state["characters"]["red_general"].get("deeds", {}).get("battles_won", 0)), 1,
		"the victor's deed is written")


func test_captures_write_takings_and_sacks(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "blue", "blue_king", {"role": "leader", "location": "alpha"})
	var rng := CampaignRng.seeded(2)
	CombatRules.capture_settlement(data, state, rng, "alpha", "red", "occupy")
	var taken := _last_of(state, "city_taken")
	t.check(not taken.is_empty(), "the taking is chronicled")
	t.check_eq(String(taken["subjects"]["faction"]), "red", "by whom")
	t.check_eq(String(taken["details"]["occupation"]), "occupy", "and how")
	t.check_eq(int(state["wars"][0]["cities"]["red"]), 1, "the ledger counts the city")
	t.check_eq(int(state["characters"]["blue_king"].get("deeds", {}).get("cities_lost", 0)), 1,
		"the loser's king carries the loss")

	state["settlements"]["beta"]["owner"] = "blue"
	CombatRules.capture_settlement(data, state, rng, "beta", "red", "enslave")
	t.check(not _last_of(state, "city_sacked").is_empty(), "an enslavement is written as a sack")
	t.check_eq(int(_last_of(state, "city_sacked")["magnitude"]), 7, "and weighs heavier")


func test_revolt_is_chronicled(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	PublicOrderRules._revolt(data, state, "beta")
	var entry := _last_of(state, "city_revolted")
	t.check(not entry.is_empty(), "the rising is chronicled")
	t.check_eq(String(entry["subjects"]["faction"]), "red", "against its old master")


func test_war_ledger_opens_and_closes(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var pre := ChronicleRules.snapshot(state)
	ChronicleRules.collect(data, state, {}, pre)
	t.check(not _last_of(state, "war_declared").is_empty(), "the scribes record the war")
	t.check_eq(state["wars"].size(), 1, "one open ledger entry for the pair")
	ChronicleRules.collect(data, state, {}, ChronicleRules.snapshot(state))
	t.check_eq(state["wars"].size(), 1, "and never a duplicate")

	ChronicleRules.on_battle(state, "red", "blue")
	ChronicleRules.on_battle(state, "blue", "red")
	state["factions"]["red"]["diplomacy"]["blue"] = "neutral"
	state["factions"]["blue"]["diplomacy"]["red"] = "neutral"
	ChronicleRules.collect(data, state, {}, ChronicleRules.snapshot(state))
	t.check(not _last_of(state, "peace_made").is_empty(), "peace is recorded")
	var summary := _last_of(state, "war_summary")
	t.check(not summary.is_empty(), "and the war is summarized from the ledger")
	t.check_eq(int(summary["details"]["battles"]), 2, "with its battles counted")
	t.check(state["wars"][0]["ended_turn"] != null, "the ledger entry is closed")


func test_reigns_change_hands_by_id(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "old_king", {"role": "leader"})
	Fixtures.add_character(state, "red", "young_heir", {"role": "heir"})
	ChronicleRules.add_deed(state, "old_king", "battles_won", 3)
	ChronicleRules.collect(data, state, {}, ChronicleRules.snapshot(state))
	t.check(_last_of(state, "succession").is_empty(), "the first pass only seeds the reign ledger")

	# A kill-path death: no notice fires anywhere — the ledger still sees it.
	state["characters"]["old_king"]["alive"] = false
	state["characters"]["young_heir"]["role"] = "leader"
	ChronicleRules.collect(data, state, {}, ChronicleRules.snapshot(state))
	t.check(not _last_of(state, "leader_died").is_empty(), "the death is inferred by id")
	var reign := _last_of(state, "reign_summary")
	t.check_eq(int(reign["details"]["battles_won"]), 3, "the reign summary carries the deeds")
	t.check_eq(String(_last_of(state, "succession")["subjects"]["character"]), "young_heir",
		"and the heir's succession is recorded")
	t.check_eq(String(state["factions"]["red"]["reign"]["leader"]), "young_heir",
		"the ledger now names the new leader")


func test_destruction_diff_and_alliance_signing(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var pre := ChronicleRules.snapshot(state)
	state["factions"]["blue"]["alive"] = false
	ChronicleRules.collect(data, state, {}, pre)
	t.check(not _last_of(state, "faction_destroyed").is_empty(),
		"a faction's fall is recorded from the alive diff")

	var fresh := Fixtures.state(data)
	fresh["factions"]["red"]["diplomacy"]["blue"] = "neutral"
	fresh["factions"]["blue"]["diplomacy"]["red"] = "neutral"
	DiplomacyRules.apply_offer(data, fresh, {"from": "red", "to": "blue", "stance": "alliance"})
	t.check(not _last_of(fresh, "alliance_made").is_empty(),
		"an alliance is chronicled at the signing itself")


func test_technique_and_edict_records_credit_the_leader(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "the_king", {"role": "leader"})
	state["factions"]["red"]["knowledge"]["test_smithing"] = {"stage": "adopting", "turn": 0, "progress": 1, "discount_pct": 0.0}
	data.balance["knowledge"]["origination_base_chance"] = 0.0
	data.balance["knowledge"]["diffusion_base_chance"] = 0.0
	KnowledgeRules.process_turn(data, state, CampaignRng.seeded(1))
	t.check(not _last_of(state, "technique_adopted").is_empty(), "the adoption is chronicled")
	t.check_eq(int(state["characters"]["the_king"].get("deeds", {}).get("techniques_completed", 0)), 1,
		"and glorifies the reign")

	EdictRules.enact(data, state, "red", "test_dole")
	t.check(not _last_of(state, "edict_enacted").is_empty(), "the enactment is chronicled")
	t.check_eq(int(state["characters"]["the_king"].get("deeds", {}).get("edicts_enacted", 0)), 1,
		"to the king's name")
	state["factions"]["red"]["treasury"] = -100
	EdictRules.process_turn(data, state)
	t.check(not _last_of(state, "edict_lapsed").is_empty(), "and so is the collapse")


func test_per_turn_cap_keeps_the_heaviest(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.balance["chronicle"]["per_turn_cap"] = 3
	for i in range(3):
		ChronicleRules.record(data, state, "battle", {"faction": "red"}, 2, {"index": i})
	ChronicleRules.record(data, state, "city_taken", {"faction": "red"}, 8)
	t.check_eq(state["chronicle"].size(), 3, "a crowded season stays capped")
	t.check_eq(String(state["chronicle"][2]["kind"]), "city_taken",
		"the heavy record displaced the first light one")
	ChronicleRules.record(data, state, "battle", {"faction": "red"}, 1)
	t.check_eq(state["chronicle"].size(), 3, "a lighter record than any kept is turned away")


func test_compaction_bounds_the_annals(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.balance["chronicle"]["max_entries"] = 10
	for i in range(15):
		state["turn"] = i  # each on its own turn, dodging the per-turn cap
		ChronicleRules.record(data, state, "battle", {"faction": "red"},
			1 if i % 2 == 0 else 5)
	state["turn"] = 15
	ChronicleRules.collect(data, state, {}, ChronicleRules.snapshot(state))
	t.check(state["chronicle"].size() <= 10, "the annals never outgrow the bound")
	var heavies := 0
	for entry in state["chronicle"]:
		if int(entry["magnitude"]) == 5:
			heavies += 1
	t.check_eq(heavies, 7, "every weighty record survived; the oldest minor ones went")


func test_resolved_is_the_narrator_feed(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "hero", {"name": "Testus Magnus"})
	ChronicleRules.record(data, state, "battle",
		{"faction": "red", "other_faction": "blue", "region": "alpha", "character": "hero"}, 4,
		{"winner": "attacker"})
	var feed := ChronicleRules.resolved(data, state)
	t.check_eq(feed.size(), 1, "one entry, resolved")
	var names: Dictionary = feed[0]["names"]
	t.check_eq(String(names["faction"]), "Red", "faction ids resolve to names")
	t.check_eq(String(names["character"]), "Testus Magnus", "characters too — dead or alive")
	t.check_eq(String(names["region"]), "Alpha", "and regions to their settlements")
	t.check_eq(String(state["chronicle"][0]["subjects"]["faction"]), "red",
		"while the stored entry keeps stable ids (the save IS the contract)")


func _last_of(state: Dictionary, kind: String) -> Dictionary:
	var found := {}
	for entry in state["chronicle"]:
		if String(entry["kind"]) == kind:
			found = entry
	return found

func test_epithets_are_earned_once_by_precedence(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "hero", {})
	Fixtures.add_character(state, "red", "burned_hand", {})
	Fixtures.add_character(state, "red", "young_blade", {})
	ChronicleRules.add_deed(state, "hero", "battles_won", 2)
	ChronicleRules.add_deed(state, "burned_hand", "battles_won", 1)
	ChronicleRules.add_deed(state, "burned_hand", "cities_lost", 1)
	ChronicleRules.add_deed(state, "young_blade", "battles_won", 1)
	var report := {"characters": []}
	ChronicleRules.collect(data, state, report, ChronicleRules.snapshot(state))

	t.check_eq(String(state["characters"]["hero"].get("epithet", "")), "test_victor",
		"two victories earn the Victor — precedence picks it over the Guardian")
	t.check_eq(String(state["characters"]["young_blade"].get("epithet", "")), "test_guardian",
		"one victory and nothing lost earns the Guardian")
	t.check_eq(String(state["characters"]["burned_hand"].get("epithet", "")), "",
		"a lost city bars the Guardian's spotless record")
	t.check(not _last_of(state, "epithet_earned").is_empty(), "the naming is chronicled")
	t.check_eq(report["characters"].size(), 2, "and carried to the player's log")

	ChronicleRules.add_deed(state, "young_blade", "battles_won", 5)
	ChronicleRules.collect(data, state, {}, ChronicleRules.snapshot(state))
	t.check_eq(String(state["characters"]["young_blade"].get("epithet", "")), "test_guardian",
		"one name per man, ever — the first earned sticks for life")


func test_annals_render_prose(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "hero", {"name": "Testus"})
	ChronicleRules.record(data, state, "battle",
		{"faction": "red", "other_faction": "blue", "region": "alpha"}, 4, {"winner": "attacker"})
	var battle: Dictionary = state["chronicle"][0]
	t.check_eq(ChronicleRules.render_entry(data, state, battle),
		"Red and Blue met in battle near Alpha.", "templates fill from resolved names")
	t.check_eq(ChronicleRules.render_entry(data, state, battle),
		ChronicleRules.render_entry(data, state, battle), "and render the same twice — no rng")

	ChronicleRules.record(data, state, "city_taken",
		{"faction": "red", "other_faction": "blue", "region": "alpha"}, 6, {})
	ChronicleRules.record(data, state, "city_taken",
		{"faction": "red", "other_faction": "blue", "region": "alpha"}, 6, {})
	var first := ChronicleRules.render_entry(data, state, state["chronicle"][1])
	var second := ChronicleRules.render_entry(data, state, state["chronicle"][2])
	t.check(first != second, "consecutive ids pick different variants — stable, not random")

	state["characters"]["hero"]["epithet"] = "test_victor"
	ChronicleRules.record(data, state, "epithet_earned",
		{"character": "hero", "faction": "red", "epithet": "test_victor"}, 5, {})
	t.check_eq(ChronicleRules.render_entry(data, state, state["chronicle"][3]),
		"Testus of Red was named the Victor.", "epithet names resolve too")

	ChronicleRules.record(data, state, "succession", {"faction": "red"}, 5, {})
	t.check_eq(ChronicleRules.render_entry(data, state, state["chronicle"][4]),
		"succession", "a kind without templates falls back to its plain name")
