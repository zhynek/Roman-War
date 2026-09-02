extends RefCounted
## Army composition queries: slot shares (one unit card = one slot, scaled by
## strength), soldier counts, and the scroll summary.


func _unit(template: String, strength: int = 100, experience: int = 0) -> Dictionary:
	return {"template": template, "experience": experience, "strength_pct": strength}


func test_shares_are_slot_weighted(t) -> void:
	var data := Fixtures.data()
	var units := [_unit("test_spears"), _unit("test_spears"), _unit("test_mob", 50)]
	var shares := ArmyRules.shares(data, units)
	# 2 full spear slots + half a peasant slot: 2 / 2.5 and 0.5 / 2.5.
	t.check_near(shares.get("spear", 0.0), 0.8, 0.0001, "two full spear cards")
	t.check_near(shares.get("peasant", 0.0), 0.2, 0.0001, "a half-strength mob is half a card")
	t.check_eq(ArmyRules.shares(data, []).size(), 0, "empty force has no shares")
	t.check_eq(ArmyRules.shares(data, [_unit("no_such_template")]).size(), 0, "unknown templates are ignored")


func test_composition_counts_soldiers(t) -> void:
	var data := Fixtures.data()
	var units := [_unit("test_spears"), _unit("test_spears", 50), _unit("test_mob")]
	var composition := ArmyRules.composition(data, units)
	t.check_eq(int(composition["spear"]["soldiers"]), 120, "80 + 40 spearmen")
	t.check_near(float(composition["spear"]["units"]), 1.5, 0.0001, "one and a half spear cards")
	t.check_eq(int(composition["peasant"]["soldiers"]), 60, "the mob at full strength")
	t.check_near(float(composition["peasant"]["share"]), 0.4, 0.0001, "1 of 2.5 slots")
	t.check_eq(ArmyRules.soldiers(data, units), 180, "soldiers total")


func test_summary_averages_kit_and_experience(t) -> void:
	var data := Fixtures.data()
	var veteran := _unit("test_spears", 100, 4)
	veteran["weapon"] = 2
	var summary := ArmyRules.summary(data, [veteran, _unit("test_mob")])
	t.check_eq(int(summary["units"]), 2, "two cards")
	t.check_eq(int(summary["soldiers"]), 140, "80 + 60 men")
	t.check_near(float(summary["avg_experience"]), 2.0, 0.0001, "(4 + 0) / 2 chevrons")
	t.check_near(float(summary["weapon_avg"]), 1.0, 0.0001, "missing weapon keys read as 0")
	t.check_near(float(summary["armor_avg"]), 0.0, 0.0001, "no armour anywhere")
