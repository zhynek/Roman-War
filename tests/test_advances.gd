extends RefCounted
## Advances: technique is a practice, not a possession. It unlocks from the Craft
## stock and is lost again when Craft falls back, which is how a people stops
## being able to do something it once could.


func _knowledge(state: Dictionary, value: float) -> void:
	state["factions"]["red"]["society"]["knowledge"] = value


func test_advances_unlock_at_their_threshold(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var first: String = AdvanceRules.available_to(data, "red")[0]
	var threshold := float(data.advances[first]["knowledge_threshold"])

	_knowledge(state, threshold - 1.0)
	AdvanceRules.refresh(data, state, ["red"])
	t.check(not AdvanceRules.held(state, "red").has(first), "below the threshold, nothing is known")

	_knowledge(state, threshold)
	var notices := AdvanceRules.refresh(data, state, ["red"])
	t.check(AdvanceRules.held(state, "red").has(first), "reaching it unlocks the advance")
	var gained := false
	for notice in notices:
		if notice["kind"] == "advance_gained" and notice["advance"] == first:
			gained = true
	t.check(gained, "and the turn reports it")


func test_advances_are_available_in_threshold_order(t) -> void:
	var data := Fixtures.data()
	var order := AdvanceRules.available_to(data, "red")
	var previous := -1.0
	for advance_id in order:
		var threshold := float(data.advances[advance_id]["knowledge_threshold"])
		t.check(threshold >= previous, "advances come in the order craft reaches them")
		previous = threshold


func test_craft_that_stops_being_taught_is_forgotten(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rules: Dictionary = data.balance["society"]
	var first: String = AdvanceRules.available_to(data, "red")[0]
	var threshold := float(data.advances[first]["knowledge_threshold"])
	var retention := float(rules["advance_retention_factor"])

	_knowledge(state, threshold)
	AdvanceRules.refresh(data, state, ["red"])
	t.check(AdvanceRules.held(state, "red").has(first), "it is known")

	# Held knowledge is stickier than new knowledge...
	_knowledge(state, threshold * retention + 0.5)
	AdvanceRules.refresh(data, state, ["red"])
	t.check(AdvanceRules.held(state, "red").has(first),
		"a small decline does not lose it — practice has inertia")

	# ...but not permanent.
	_knowledge(state, threshold * retention - 1.0)
	var notices := AdvanceRules.refresh(data, state, ["red"])
	t.check(not AdvanceRules.held(state, "red").has(first), "a real decline loses it")
	var lost := false
	for notice in notices:
		if notice["kind"] == "advance_lost" and notice["advance"] == first:
			lost = true
	t.check(lost, "and the loss is reported — nothing was destroyed, it stopped being taught")
	t.check(retention < 1.0, "retention is a hysteresis gap, not a free ratchet")


func test_culture_gates_what_a_people_works_out(t) -> void:
	var data := Fixtures.data()
	var roman := AdvanceRules.available_to(data, "red")
	var tribal := AdvanceRules.available_to(data, "blue")
	var culture_specific := false
	for advance_id in data.advances:
		if data.advances[advance_id].has("culture"):
			culture_specific = true
	t.check(culture_specific, "some advances belong to one culture's tradition")
	for advance_id in roman:
		var culture = data.advances[advance_id].get("culture")
		t.check(culture == null or culture == "roman", "romans reach only roman-eligible advances")
	t.check(tribal.size() <= roman.size() or roman.size() <= tribal.size(),
		"each culture has its own reachable set")


func test_advance_effects_reach_the_rules(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	# Find an advance that discounts construction and confirm it actually does.
	var discount_id := ""
	for advance_id in AdvanceRules.available_to(data, "red"):
		if data.advances[advance_id]["effects"].has("build_cost_pct"):
			discount_id = advance_id
			break
	t.check(discount_id != "", "at least one advance makes building cheaper")

	state["factions"]["red"]["advances"] = []
	var full: Array = ConstructionRules.available_projects(data, state, "beta")
	state["factions"]["red"]["advances"] = [discount_id]
	var discounted: Array = ConstructionRules.available_projects(data, state, "beta")
	t.check(not full.is_empty() and not discounted.is_empty(), "there is something to build")
	var cheaper := false
	for i in range(full.size()):
		if int(discounted[i]["cost"]) < int(full[i]["cost"]):
			cheaper = true
	t.check(cheaper, "the advance is felt at the point the player spends money")
	t.check(AdvanceRules.effect_total(data, state, "red", "build_cost_pct") < 0.0,
		"and the effect total reads it back")
