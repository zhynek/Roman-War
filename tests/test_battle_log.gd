extends RefCounted
## The battle round log: a narrative synthesized from the single-shot
## resolution that adds NOTHING to the RNG stream, splits casualties across
## its phases so they sum exactly to the one-shot totals, walks the loser's
## morale to zero at the break, and reports every unit's fate.


func _army(templates: Array) -> Array:
	var units: Array = []
	for template in templates:
		units.append({"template": template, "experience": 0, "strength_pct": 100})
	return units


func test_round_log_shape_and_sums(t) -> void:
	var data := Fixtures.data()
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(99)
	var attacker := _army(["test_spears", "test_spears"])
	var defender := _army(["test_mob"])
	var result := resolver.resolve(data, rng, attacker, defender,
		{"terrain": "plains", "wall_level": 0})

	var rounds: Array = result.get("rounds", [])
	t.check_eq(rounds.size(), AutoResolver.ROUND_PHASES.size(), "one round per phase")
	for i in range(rounds.size()):
		t.check_eq(String(rounds[i]["phase"]), String(AutoResolver.ROUND_PHASES[i]),
			"phases run in their fixed order")

	var attacker_sum := 0.0
	var defender_sum := 0.0
	for round_entry in rounds:
		attacker_sum += float(round_entry["attacker_casualty_pct"])
		defender_sum += float(round_entry["defender_casualty_pct"])
	t.check(absf(attacker_sum - float(result["attacker_casualty_pct"])) < 0.0001,
		"attacker phase casualties sum to the single-shot total")
	t.check(absf(defender_sum - float(result["defender_casualty_pct"])) < 0.0001,
		"defender phase casualties sum to the single-shot total")

	var loser: String = "defender" if result["winner"] == "attacker" else "attacker"
	var saw_break := false
	for round_entry in rounds:
		var breaking := String(round_entry["breaking"])
		if round_entry["phase"] == "break":
			saw_break = true
			t.check_eq(breaking, loser, "the break round names the loser")
			t.check_eq(float(round_entry[loser + "_morale"]), 0.0,
				"whose morale hits zero at the break")
		else:
			t.check_eq(breaking, "", "no other round breaks anyone")
		var winner_morale := float(round_entry[String(result["winner"]) + "_morale"])
		t.check(winner_morale > 0.0, "the winner's line never dissolves")
	t.check(saw_break, "the log has its break moment")


func test_log_adds_no_rng_draws(t) -> void:
	## The load-bearing guarantee: with the log added, a battle consumes
	## exactly the draws it always did — 2 force rolls, one scatter per unit,
	## and the one general-death die the outcome calls for. A twin RNG
	## replaying that count lands on the identical state.
	var data := Fixtures.data()
	var resolver := AutoResolver.new()

	# No generals: 2 + units draws, nothing else.
	var rng := CampaignRng.seeded(1234)
	var twin := CampaignRng.seeded(1234)
	var attacker := _army(["test_spears", "test_spears"])
	var defender := _army(["test_mob", "test_mob", "test_mob"])
	resolver.resolve(data, rng, attacker, defender, {"terrain": "plains", "wall_level": 0})
	for draw in range(2 + 2 + 3):
		twin.randf()
	t.check_eq(rng.state_string(), twin.state_string(),
		"a generalless battle spends exactly 2 + one-per-unit draws")

	# Both generals present: exactly one death die more, whoever lost.
	rng = CampaignRng.seeded(4321)
	twin = CampaignRng.seeded(4321)
	attacker = _army(["test_spears"])
	defender = _army(["test_mob", "test_mob"])
	resolver.resolve(data, rng, attacker, defender, {
		"terrain": "plains", "wall_level": 0,
		"attacker_general": {"command": 2, "troop_morale": 1},
		"defender_general": {"command": 1, "troop_morale": 0},
	})
	for draw in range(2 + 1 + 2 + 1):
		twin.randf()
	t.check_eq(rng.state_string(), twin.state_string(),
		"generals add exactly the loser's one death die")


func test_unit_reports_reconcile_with_the_field(t) -> void:
	var data := Fixtures.data()
	var resolver := AutoResolver.new()
	var rng := CampaignRng.seeded(5)
	var attacker := _army(["test_spears", "test_spears"])
	var defender := _army(["test_mob"])
	var attacker_before := attacker.duplicate(true)
	var result := resolver.resolve(data, rng, attacker, defender,
		{"terrain": "plains", "wall_level": 0})

	var report: Array = result.get("attacker_report", [])
	t.check_eq(report.size(), attacker_before.size(), "every starting unit is reported")
	var survivors := 0
	for i in range(report.size()):
		var entry: Dictionary = report[i]
		t.check_eq(String(entry["template"]), String(attacker_before[i]["template"]),
			"reports keep pre-battle order")
		t.check_eq(int(entry["strength_before"]), int(attacker_before[i]["strength_pct"]),
			"strength_before is the pre-battle strength")
		if not entry["destroyed"]:
			t.check_eq(int(entry["strength_after"]), int(attacker[survivors]["strength_pct"]),
				"a survivor's strength_after matches the living unit")
			survivors += 1
		else:
			t.check_eq(int(entry["strength_after"]), 0, "the destroyed leave nothing")
	t.check_eq(survivors, attacker.size(), "reported survivors are the units still standing")
	t.check(result.get("defender_report", []).size() == 1, "the defender is reported too")
