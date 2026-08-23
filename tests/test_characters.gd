extends RefCounted
## Phase 4: trait points/levels/effects, triggers, retinues, the family year
## (aging, succession, births, coming of age), and character effects flowing
## into order, income, movement, and battle.


func test_trait_levels_and_effective_attributes(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "gaius")
	var gaius: Dictionary = state["characters"]["gaius"]

	CharacterRules.award_points(data, gaius, "test_steward", 2)
	t.check_eq(CharacterRules.active_trait_levels(data, gaius).size(), 1, "threshold 2 reaches level 1")
	t.check_eq(CharacterRules.effective(data, gaius, "management"), 3, "base 2 + level-1 management")

	CharacterRules.award_points(data, gaius, "test_steward", 3)
	var active := CharacterRules.active_trait_levels(data, gaius)
	t.check_eq(active[0]["level_number"], 2, "threshold 5 reaches level 2")
	t.check_eq(CharacterRules.effective(data, gaius, "management"), 4, "level-2 management applies alone, not stacked")


func test_anti_trait_erosion(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "gaius")
	var gaius: Dictionary = state["characters"]["gaius"]
	gaius["trait_points"] = {"test_slacker": 2}

	CharacterRules.award_points(data, gaius, "test_steward", 3)
	t.check(not gaius["trait_points"].has("test_slacker"), "opposite deeds erode the anti-trait first")
	t.check_eq(int(gaius["trait_points"].get("test_steward", 0)), 1, "the remainder builds the trait")


func test_governing_trigger_and_ancillary(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(9)
	Fixtures.add_character(state, "red", "gaius", {"location": "beta"})
	state["settlements"]["beta"]["governor"] = "gaius"

	CharacterRules.process_turn(data, state, rng)
	var gaius: Dictionary = state["characters"]["gaius"]
	t.check_eq(int(gaius["trait_points"].get("test_steward", 0)), 1, "well-ordered governing earns steward points")
	t.check(gaius["ancillaries"].has("test_scribe"), "the scribe joins a governing master")

	CharacterRules.process_turn(data, state, rng)
	t.check_eq(gaius["ancillaries"].size(), 1, "no duplicate retinue member")
	t.check_eq(CharacterRules.active_trait_levels(data, gaius).size(), 1, "two turns of governing reach level 1")


func test_battle_trigger_odds_against(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(4)
	Fixtures.add_character(state, "red", "gaius")
	var notices: Array = []

	CharacterRules.fire_trigger(data, state, "gaius", "battle_won", {"odds_against": false}, rng, notices)
	t.check(state["characters"]["gaius"]["trait_points"].is_empty(), "an easy win teaches nothing")

	CharacterRules.fire_trigger(data, state, "gaius", "battle_won", {"odds_against": true}, rng, notices)
	t.check_eq(CharacterRules.effective(data, state["characters"]["gaius"], "command"), 3, "bravery raises command")
	var profile := CharacterRules.battle_profile(data, state["characters"]["gaius"])
	t.check_eq(int(profile["troop_morale"]), 2, "morale bonus reaches the battle profile")


func test_character_effects_reach_settlement_breakdowns(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "gaius", {
		"location": "beta", "trait_points": {"test_steward": 5}, "ancillaries": ["test_scribe"],
	})
	state["settlements"]["beta"]["governor"] = "gaius"

	var order_labels := {}
	for factor in PublicOrderRules.breakdown(data, state, "beta"):
		order_labels[factor["label"]] = factor["value"]
	t.check_near(order_labels.get("governor", 0.0), 10.0, 0.001, "influence 2 x 5% per point")
	t.check_near(order_labels.get("governor_traits", 0.0), 5.0, 0.001, "steward level-2 law")

	var income_labels := {}
	for factor in EconomyRules.settlement_income_breakdown(data, state, "beta"):
		income_labels[factor["label"]] = factor["value"]
	# management 2 base + 2 trait + 1 scribe = 5 -> 10% of gross
	t.check(income_labels.get("governor", 0.0) > 0.0, "able governor grows the take")


func test_general_movement_bonus(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "gaius", {"trait_points": {"test_pathfinder": 1}})
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	state["armies"][army_id]["general"] = "gaius"
	MovementRules.reset_movement(data, state)
	t.check_near(float(state["armies"][army_id]["movement_left"]), 3.0, 0.001, "pathfinder +50% movement")


func test_aging_death_and_succession(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(2)
	Fixtures.add_character(state, "red", "old_leader", {"role": "leader", "age": 84})
	Fixtures.add_character(state, "red", "the_heir", {"role": "heir", "age": 40})
	Fixtures.add_character(state, "red", "cousin", {"role": "family", "age": 30, "influence": 4})

	var notices := FamilyRules.process_year(data, state, rng)
	t.check(not state["characters"]["old_leader"]["alive"], "the old leader dies at the age cap")
	t.check_eq(state["characters"]["the_heir"]["role"], "leader", "the heir succeeds")
	t.check_eq(state["characters"]["cousin"]["role"], "heir", "the most influential adult becomes heir")
	var kinds := []
	for notice in notices:
		kinds.append(notice["kind"])
	t.check(kinds.has("death") and kinds.has("succession"), "the year's report tells the tale")


func test_coming_of_age(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(2)
	Fixtures.add_character(state, "red", "the_leader", {"role": "leader", "age": 40})
	Fixtures.add_character(state, "red", "the_boy", {"role": "child", "age": 15, "father": "the_leader"})
	FamilyRules.process_year(data, state, rng)
	t.check(state["characters"]["the_boy"]["role"] in ["family", "heir"],
		"sixteen and a man of the family (and heir apparent, being the only candidate)")


func test_births(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(2)
	data.balance["characters"]["birth_chance_per_year"] = 1.0
	Fixtures.add_character(state, "red", "the_leader", {"role": "leader", "age": 30})
	FamilyRules.process_year(data, state, rng)
	var born := ""
	for char_id in state["characters"]:
		if state["characters"][char_id].get("father") == "the_leader":
			born = char_id
	t.check(born != "", "a child is born")
	t.check_eq(int(state["characters"][born]["age"]), 0, "newborn")
	t.check_eq(state["characters"][born]["role"], "child", "in the nursery, not the senate")


func test_man_of_the_hour(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(3)
	data.balance["characters"]["man_of_the_hour_chance"] = 1.0
	var army_id := Fixtures.add_army(state, "red", "gamma", ["test_spears"])
	var notices: Array = []
	var new_general := FamilyRules.maybe_man_of_the_hour(
		data, state, rng, state["armies"][army_id], 80, 200, notices)
	t.check(new_general != "", "the captain is adopted")
	t.check_eq(state["armies"][army_id]["general"], new_general, "and takes command of the army he saved")
	t.check_eq(state["characters"][new_general]["faction"], "red", "into the red family")

	# But never for a stroll: outnumberING wins earn nothing.
	var other_id := Fixtures.add_army(state, "red", "delta", ["test_spears"])
	t.check_eq(FamilyRules.maybe_man_of_the_hour(
		data, state, rng, state["armies"][other_id], 200, 80, notices), "", "no glory without odds")


func test_set_heir_and_ancillary_transfer(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	Fixtures.add_character(state, "red", "the_leader", {"role": "leader", "age": 45})
	Fixtures.add_character(state, "red", "first_son", {"role": "heir", "age": 22, "location": "beta"})
	Fixtures.add_character(state, "red", "second_son", {"role": "family", "age": 20, "location": "beta", "ancillaries": ["test_scribe"]})
	Fixtures.add_character(state, "blue", "foreigner", {"role": "family", "age": 30, "location": "beta"})

	t.check(FamilyRules.set_heir(data, state, "red", "second_son"), "the father chooses")
	t.check_eq(state["characters"]["second_son"]["role"], "heir", "second son raised")
	t.check_eq(state["characters"]["first_son"]["role"], "family", "first son set aside")

	t.check(CharacterRules.transfer_ancillary(data, state, "second_son", "first_son", "test_scribe"),
		"the scribe changes masters in the same city")
	t.check(state["characters"]["first_son"]["ancillaries"].has("test_scribe"), "received")
	t.check(not CharacterRules.transfer_ancillary(data, state, "first_son", "foreigner", "test_scribe"),
		"never across factions")
