extends RefCounted
## The event vocabulary (Phase 6, stage W): treasury_above and regions_held
## triggers, repeatable events resting on cooldowns, faction-scoped moods
## through the modifier container, scripted technique grants, and the
## obituary path on faction_destroyed.


func test_treasury_above_repeats_on_cooldown(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.events = [{
		"id": "test_windfall", "name": "Windfall",
		"trigger": {"condition": "treasury_above", "threshold": 4000},
		"effects": {"treasury": -1000},
		"once": false, "cooldown_turns": 2,
		"text": "",
	}]
	var rng := CampaignRng.seeded(1)
	var fired := EventRules.process_turn(data, state, rng)
	t.check_eq(fired.size(), 1, "a rich court trips the trigger")
	t.check_eq(String(fired[0]["faction"]), "blue", "the first sorted qualifying court is the subject")
	t.check_eq(int(state["event_cooldowns"]["test_windfall"]), 2, "and the event rests")
	t.check_eq(EventRules.process_turn(data, state, rng).size(), 0, "no refire while resting")
	# cooldown_turns is the minimum turns BETWEEN firings: two turns after the
	# first, it fires again — and the subject re-derives (blue's fortune was
	# spent, so the scribes now notice red's).
	var refired := EventRules.process_turn(data, state, rng)
	t.check_eq(refired.size(), 1, "rested: it fires again two turns apart")
	t.check_eq(String(refired[0]["faction"]), "red", "against the next qualifying court")
	t.check_eq(state["events_fired"].size(), 0, "repeatable events never clog events_fired")


func test_regions_held_trigger(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.events = [{
		"id": "test_dominion", "name": "Dominion",
		"trigger": {"condition": "regions_held", "count": 2, "faction": "red"},
		"effects": {},
		"text": "",
	}]
	var rng := CampaignRng.seeded(1)
	t.check_eq(EventRules.process_turn(data, state, rng).size(), 1,
		"red holds beta and epsilon: the condition is met")
	t.check_eq(EventRules.process_turn(data, state, rng).size(), 0, "once-only by default")

	data.events = [{
		"id": "test_empire", "name": "Empire",
		"trigger": {"condition": "regions_held", "count": 3, "faction": "red"},
		"effects": {},
		"text": "",
	}]
	t.check_eq(EventRules.process_turn(data, state, rng).size(), 0, "three is more than red holds")


func test_happiness_faction_lands_in_the_modifier_container(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.events = [{
		"id": "test_jubilee", "name": "Jubilee",
		"trigger": {"condition": "treasury_above", "threshold": 100, "faction": "red"},
		"effects": {"happiness_faction": {"value": 5, "turns": 3}},
		"text": "",
	}]
	EventRules.process_turn(data, state, CampaignRng.seeded(1))
	t.check_near(ModifierRules.sum_for(state, "red", "beta", "happiness"), 5.0, 0.001,
		"the mood is on the court's lands")
	t.check_near(ModifierRules.sum_for(state, "blue", "alpha", "happiness"), 0.0, 0.001,
		"and no one else's")


func test_grant_technique_is_scripted_history(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.events = [{
		"id": "test_gift_of_craft", "name": "Gift of Craft",
		"trigger": {"condition": "treasury_above", "threshold": 100, "faction": "red"},
		"effects": {"grant_technique": "test_smithing"},
		"text": "",
	}]
	EventRules.process_turn(data, state, CampaignRng.seeded(1))
	t.check(KnowledgeRules.adopted(state, "red", "test_smithing"),
		"the craft is practiced outright — no cost, no seasons")
	var chronicled := false
	for entry in state["chronicle"]:
		if String(entry["kind"]) == "technique_adopted" and bool(entry["details"].get("scripted", false)):
			chronicled = true
	t.check(chronicled, "and the annals mark it as scripted history")


func test_obituary_fires_on_faction_destruction(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.events = [{
		"id": "test_obituary", "name": "The Fall",
		"trigger": {"condition": "faction_destroyed", "faction": "blue"},
		"effects": {},
		"text": "So passes a people.",
	}]
	var rng := CampaignRng.seeded(1)
	t.check_eq(EventRules.process_turn(data, state, rng).size(), 0, "no obituary for the living")
	state["factions"]["blue"]["alive"] = false
	var fired := EventRules.process_turn(data, state, rng)
	t.check_eq(fired.size(), 1, "the obituary fires on destruction")
	t.check_eq(EventRules.process_turn(data, state, rng).size(), 0, "and only once")


func test_shipped_obituaries_exist_for_the_great_powers(t) -> void:
	var data := GameData.load_from("res://data")
	var found := {}
	for event in data.events:
		var trigger: Dictionary = event.get("trigger", {})
		if String(trigger.get("condition", "")) == "faction_destroyed":
			found[String(trigger.get("faction", ""))] = true
	for faction_id in ["carthage", "macedon", "seleucia", "egypt"]:
		t.check(found.has(faction_id), "an obituary awaits " + faction_id)
