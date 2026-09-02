extends RefCounted
## The kind-keyed building accessor every gate reads through: recruitment
## requirements, trait conditions, doctrine prerequisites and the settlement
## level itself all ask "does this town hold kind K at tier >= L?" one way.


func test_building_tier_by_kind(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var beta: Dictionary = state["settlements"]["beta"]
	t.check_eq(SettlementRules.building_tier(data, beta, "government"), 2, "government tier read")
	t.check_eq(SettlementRules.building_tier(data, beta, "barracks"), 1, "barracks tier read")
	t.check_eq(SettlementRules.building_tier(data, beta, "walls"), 0, "unbuilt kind is tier 0")
	t.check_eq(SettlementRules.building_tier(data, beta, "stables"), 0, "unknown-to-this-town kind is tier 0")


func test_building_tier_filters_temple_god(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.chains["test_mars"] = {
		"id": "test_mars", "kind": "temple", "god": "Mars", "cultures": ["roman"], "name": "Shrine of Mars",
		"levels": [{"id": "mars_1", "name": "Shrine", "min_settlement_level": "village", "cost": 300,
			"build_turns": 1, "effects": {}, "description": ""}],
	}
	var beta: Dictionary = state["settlements"]["beta"]
	beta["buildings"]["test_mars"] = 1
	t.check_eq(SettlementRules.building_tier(data, beta, "temple"), 1, "any temple counts without a god filter")
	t.check_eq(SettlementRules.building_tier(data, beta, "temple", "Mars"), 1, "the right god matches")
	t.check_eq(SettlementRules.building_tier(data, beta, "temple", "Jupiter"), 0, "another god does not")


func test_settlement_level_follows_government_tier(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var alpha: Dictionary = state["settlements"]["alpha"]
	t.check_eq(SettlementRules.settlement_level(data, alpha), "village", "tier 1 = village")
	alpha["buildings"]["tribal_government"] = 4
	t.check_eq(SettlementRules.settlement_level(data, alpha), "minor_city", "tier 4 = minor city")
	alpha["buildings"] = {}
	t.check_eq(SettlementRules.settlement_level(data, alpha), "village", "no government at all still reads as a village")
