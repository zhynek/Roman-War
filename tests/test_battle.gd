extends RefCounted
## The BattleResolver contract and the auto-resolver's statistical behavior:
## determinism under a fixed seed, strength usually prevailing, walls mattering.


func _army(templates: Array) -> Array:
	var units: Array = []
	for template in templates:
		units.append({"template": template, "experience": 0, "strength_pct": 100})
	return units


func test_deterministic_given_seed(t) -> void:
	var data := Fixtures.data()
	var resolver := AutoResolver.new()
	var results: Array = []
	for attempt in range(2):
		var rng := CampaignRng.seeded(99)
		var attacker := _army(["test_spears", "test_spears"])
		var defender := _army(["test_mob"])
		results.append(resolver.resolve(data, rng, attacker, defender, {"terrain": "plains", "wall_level": 0}))
	t.check_eq(JSON.stringify(results[0]), JSON.stringify(results[1]), "same seed, same battle")


func test_strength_usually_wins(t) -> void:
	var data := Fixtures.data()
	var resolver := AutoResolver.new()
	var strong_wins := 0
	for seed_value in range(30):
		var rng := CampaignRng.seeded(seed_value)
		var attacker := _army(["test_spears", "test_spears", "test_spears"])
		var defender := _army(["test_mob"])
		var result := resolver.resolve(data, rng, attacker, defender, {"terrain": "plains", "wall_level": 0})
		if result["winner"] == "attacker":
			strong_wins += 1
	t.check(strong_wins >= 27, "3:1 quality advantage wins at least 27 of 30 battles (won %d)" % strong_wins)


func test_walls_favor_defenders(t) -> void:
	var data := Fixtures.data()
	var resolver := AutoResolver.new()
	var field_wins := 0
	var wall_wins := 0
	for seed_value in range(30):
		var attacker := _army(["test_spears", "test_spears"])
		var defender := _army(["test_spears"])
		var rng := CampaignRng.seeded(seed_value)
		if resolver.resolve(data, rng, attacker.duplicate(true), defender.duplicate(true),
				{"terrain": "plains", "wall_level": 0})["winner"] == "attacker":
			field_wins += 1
		rng = CampaignRng.seeded(seed_value)
		if resolver.resolve(data, rng, attacker.duplicate(true), defender.duplicate(true),
				{"terrain": "plains", "wall_level": 4})["winner"] == "attacker":
			wall_wins += 1
	t.check(wall_wins < field_wins, "high walls turn assaults (field %d vs wall %d)" % [field_wins, wall_wins])


func test_casualties_applied_in_place(t) -> void:
	var data := Fixtures.data()
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(5)
	var attacker := _army(["test_spears", "test_spears"])
	var defender := _army(["test_mob"])
	resolver.resolve(data, rng, attacker, defender, {"terrain": "plains", "wall_level": 0})
	var attacker_intact := true
	for unit in attacker:
		if int(unit["strength_pct"]) < 100:
			attacker_intact = false
	t.check(not attacker_intact or defender.is_empty() or int(defender[0]["strength_pct"]) < 100,
		"somebody bled")


func test_field_battle_moves_winner(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(2)
	var attacker_id := Fixtures.add_army(state, "red", "beta", ["test_spears", "test_spears", "test_spears"])
	var defender_id := Fixtures.add_army(state, "blue", "alpha", ["test_mob"])
	var result := CombatRules.attack_army(data, state, resolver, rng, attacker_id, defender_id)
	if result["winner"] == "attacker":
		t.check_eq(state["armies"][attacker_id]["region"], "alpha", "victorious attacker advances")


func test_capture_occupation_choices(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var rng := CampaignRng.seeded(8)
	state["settlements"]["alpha"]["population"] = 10000

	var enslaved := CombatRules.capture_settlement(data, state, rng, "alpha", "red", "enslave")
	t.check_eq(state["settlements"]["alpha"]["owner"], "red", "ownership transfers")
	t.check_eq(int(state["settlements"]["alpha"]["population"]), 5000, "half the people enslaved")
	t.check(enslaved["loot"] > 0, "enslaving loots")

	state["settlements"]["alpha"]["population"] = 10000
	var exterminated := CombatRules.capture_settlement(data, state, rng, "alpha", "red", "exterminate")
	t.check_eq(int(state["settlements"]["alpha"]["population"]), 2500, "three quarters put to the sword")
	t.check(exterminated["loot"] > enslaved["loot"], "extermination loots hardest")
	t.check(int(state["settlements"]["alpha"]["recently_conquered"]) < 6, "fear keeps the survivors quiet")

func test_weapon_and_armor_stamps_raise_strength(t) -> void:
	var data := Fixtures.data()
	var bare := [{"template": "test_spears", "experience": 0, "strength_pct": 100}]
	var armed := [{"template": "test_spears", "experience": 0, "strength_pct": 100, "weapon": 1, "armor": 1}]
	var chevron_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	var bare_strength := BattleResolver.force_strength(data, bare, null, chevron_pct)
	var armed_strength := BattleResolver.force_strength(data, armed, null, chevron_pct)
	t.check(armed_strength > bare_strength,
		"the resolver counts the recruit-time stamp — 45 authored building effects finally live")
	# attack 6 and defense 8, each scaled by its own tuning knob, over 80 men.
	# Read from balance rather than hardcoded: this pins the SHAPE, so a
	# balance pass can retune the percentages without rewriting the test.
	var weapon_pct := float(data.balance["battle"]["weapon_upgrade_attack_pct"]) / 100.0
	var armor_pct := float(data.balance["battle"]["armor_upgrade_defense_pct"]) / 100.0
	t.check_near(armed_strength - bare_strength, 80.0 * (6.0 * weapon_pct + 8.0 * armor_pct), 0.01,
		"weapons scale attack, armor scales defense")
	t.check(AiStrategy.force_strength(data, armed) > AiStrategy.force_strength(data, bare),
		"and the AI's paper estimate agrees — it will not misjudge an upgraded enemy")
