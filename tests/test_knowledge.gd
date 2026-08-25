extends RefCounted
## The knowledge engine (Phase 6): the 270 BC endowment, prerequisite caches,
## origination, diffusion along contact, the awareness → adopting → adopted
## lifecycle, culture resistance and discounts, reform pressure (defeat as
## the teacher of military reform), conquest transfer, espionage, legacy-save
## seeding, and process_turn lockstep across a JSON round trip.


func test_start_adopted_seeds_the_world_of_270(t) -> void:
	var data := GameData.load_from("res://data")
	var state := NewGame.build(data, "julii", 42)
	var julii: Dictionary = state["factions"]["julii"]["knowledge"]
	t.check_eq(String(julii.get("marching_camps", {}).get("stage", "")), "adopted",
		"a Roman house opens with the entrenched camp")
	t.check_eq(String(state["factions"]["carthage"]["knowledge"].get("quinquereme_construction", {}).get("stage", "")),
		"adopted", "Carthage opens with the fivefold warship")
	t.check_eq(String(state["factions"]["egypt"]["knowledge"].get("museum_scholarship", {}).get("stage", "")),
		"adopted", "the Museum belongs to Egypt alone (faction start)")
	t.check(not julii.has("museum_scholarship"), "and no Roman court has heard of it")
	t.check_eq(state["factions"]["rebels"]["knowledge"].size(), 0, "rebels keep no ledger")
	t.check_near(float(state["factions"]["julii"]["reform_pressure"]), 0.0, 0.001,
		"no defeats yet, no pressure")


func test_build_caches_reads_the_map_in_one_pass(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var caches := KnowledgeRules.build_caches(data, state)
	t.check_eq(int(caches["kind_levels"]["red"].get("barracks", 0)), 1, "red drills at beta")
	t.check_eq(int(caches["kind_levels"]["red"].get("government", 0)), 2, "best tier wins")
	t.check(caches["resources"]["blue"].has("grain"), "blue holds the grain of alpha")
	t.check(not caches["resources"]["red"].has("grain"), "red does not")
	t.check(bool(caches["coastal"]["red"]), "epsilon gives red a coast")
	t.check(bool(caches["coastal"]["blue"]), "alpha gives blue one")
	t.check(caches["border_pairs"].has("blue|red"), "alpha touches beta: the pair is recorded")


func test_prerequisites_gate_origination_and_adoption(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var caches := KnowledgeRules.build_caches(data, state)
	var letters: Dictionary = data.techniques["test_letters"]
	var irrigation: Dictionary = data.techniques["test_irrigation"]
	var greatworks: Dictionary = data.techniques["test_greatworks"]
	t.check(not KnowledgeRules.prerequisites_met(data, state, caches, "red", letters),
		"no school, no letters")
	state["settlements"]["beta"]["buildings"]["test_education"] = 1
	caches = KnowledgeRules.build_caches(data, state)
	t.check(KnowledgeRules.prerequisites_met(data, state, caches, "red", letters),
		"the school opens the door")
	t.check(not KnowledgeRules.prerequisites_met(data, state, caches, "red", irrigation),
		"farms without grain refuse the ditch")
	t.check(not KnowledgeRules.prerequisites_met(data, state, caches, "blue", irrigation),
		"grain without farms likewise")
	t.check(not KnowledgeRules.prerequisites_met(data, state, caches, "red", greatworks),
		"technique chains gate on ADOPTED prerequisites")
	state["factions"]["red"]["knowledge"]["test_letters"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	t.check(KnowledgeRules.prerequisites_met(data, state, caches, "red", greatworks),
		"and open once the prerequisite is practiced")


func test_effect_total_counts_adopted_only(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var knowledge: Dictionary = state["factions"]["red"]["knowledge"]
	knowledge["test_smithing"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	t.check_near(KnowledgeRules.faction_effect_total(data, state, "red", "weapon_upgrade"), 0.0, 0.001,
		"awareness grants nothing")
	knowledge["test_smithing"]["stage"] = "adopting"
	t.check_near(KnowledgeRules.faction_effect_total(data, state, "red", "weapon_upgrade"), 0.0, 0.001,
		"half-built programs grant nothing")
	knowledge["test_smithing"]["stage"] = "adopted"
	t.check_near(KnowledgeRules.faction_effect_total(data, state, "red", "weapon_upgrade"), 1.0, 0.001,
		"practice grants the edge")
	t.check_near(KnowledgeRules.faction_effect_total(data, state, "blue", "weapon_upgrade"), 0.0, 0.001,
		"and only to the court that practices it")


func test_adoption_cost_resistance_and_discounts(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	t.check_eq(KnowledgeRules.adoption_cost(data, state, "red", "test_letters"), 400,
		"a Roman court pays the base price for letters")
	t.check_eq(KnowledgeRules.adoption_cost(data, state, "blue", "test_letters"), 800,
		"a tribal court pays double — culture resistance")
	state["factions"]["blue"]["knowledge"]["test_letters"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 30.0}
	t.check_eq(KnowledgeRules.adoption_cost(data, state, "blue", "test_letters"), 560,
		"a stolen head start cuts the resisted price")
	state["factions"]["red"]["reform_pressure"] = float(data.balance["knowledge"]["reform_pressure_max"])
	t.check_eq(KnowledgeRules.adoption_cost(data, state, "red", "test_smithing"), 300,
		"at full reform pressure the arsenal is half price")
	t.check_eq(KnowledgeRules.adoption_cost(data, state, "red", "test_letters"), 400,
		"but scholarship is not — the discount is military-group only")


func test_begin_adoption_lifecycle(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var red: Dictionary = state["factions"]["red"]
	red["knowledge"]["test_smithing"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	var treasury_before := int(red["treasury"])
	var verdict := KnowledgeRules.begin_adoption(data, state, "red", "test_smithing")
	t.check(bool(verdict["ok"]), "the program begins")
	t.check_eq(int(red["treasury"]), treasury_before - 600, "paid up front")
	t.check_eq(String(red["knowledge"]["test_smithing"]["stage"]), "adopting", "craftsmen at work")
	t.check_eq(int(red["knowledge"]["test_smithing"]["progress"]), 2, "two seasons of it")

	var rng := CampaignRng.seeded(11)
	var events := KnowledgeRules.process_turn(data, state, rng)
	t.check_eq(String(red["knowledge"]["test_smithing"]["stage"]), "adopting", "one season down")
	events = KnowledgeRules.process_turn(data, state, rng)
	t.check_eq(String(red["knowledge"]["test_smithing"]["stage"]), "adopted", "and it is done")
	var adopted_event := false
	for event in events:
		if event.get("kind", "") == "technique_adopted" and event.get("faction", "") == "red":
			adopted_event = true
	t.check(adopted_event, "the completion is reported")
	t.check_near(KnowledgeRules.faction_effect_total(data, state, "red", "weapon_upgrade"), 1.0, 0.001,
		"the effect now applies")


func test_begin_adoption_gates(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	var red: Dictionary = state["factions"]["red"]
	t.check_eq(String(KnowledgeRules.begin_adoption(data, state, "red", "no_such")["reason"]), "unknown",
		"no such craft")
	t.check_eq(String(KnowledgeRules.begin_adoption(data, state, "red", "test_smithing")["reason"]), "not_aware",
		"a court cannot pursue what it has never heard of")
	red["knowledge"]["test_letters"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	t.check_eq(String(KnowledgeRules.begin_adoption(data, state, "red", "test_letters")["reason"]), "prerequisites",
		"awareness without the school is not enough")
	red["knowledge"]["test_smithing"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	red["treasury"] = 100
	t.check_eq(String(KnowledgeRules.begin_adoption(data, state, "red", "test_smithing")["reason"]), "treasury",
		"the purse refuses")
	red["treasury"] = 5000
	t.check(bool(KnowledgeRules.begin_adoption(data, state, "red", "test_smithing")["ok"]), "now it begins")
	red["knowledge"]["test_greatworks"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	t.check_eq(String(KnowledgeRules.begin_adoption(data, state, "red", "test_greatworks")["reason"]), "hands_full",
		"one program at a time")
	t.check_eq(String(KnowledgeRules.begin_adoption(data, state, "red", "test_smithing")["reason"]), "already_adopting",
		"no doubling the same program")
	red["knowledge"]["test_smithing"]["stage"] = "adopted"
	t.check_eq(String(KnowledgeRules.begin_adoption(data, state, "red", "test_smithing")["reason"]), "already_adopted",
		"nor re-buying a practiced craft")


func test_origination_respects_origin_cultures(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.balance["knowledge"]["origination_base_chance"] = 1.0
	# Schools on both sides; strip red's barracks so letters is its ONLY candidate.
	state["settlements"]["beta"]["buildings"].erase("test_barracks")
	state["settlements"]["beta"]["buildings"]["test_education"] = 1
	state["settlements"]["alpha"]["buildings"]["test_education"] = 1
	var rng := CampaignRng.seeded(3)
	var events := KnowledgeRules.process_turn(data, state, rng)
	t.check_eq(String(state["factions"]["red"]["knowledge"].get("test_letters", {}).get("stage", "")), "aware",
		"the Roman court devises letters — awareness, not adoption")
	t.check(not state["factions"]["blue"]["knowledge"].has("test_letters"),
		"the tribal court cannot originate a craft born elsewhere")
	var originated := false
	for event in events:
		if event.get("kind", "") == "technique_originated" and event.get("faction", "") == "red":
			originated = true
	t.check(originated, "the invention is reported")


func test_diffusion_spreads_along_contact(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.balance["knowledge"]["origination_base_chance"] = 0.0
	data.balance["knowledge"]["diffusion_base_chance"] = 1.0
	state["factions"]["blue"]["knowledge"]["test_smithing"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	var rng := CampaignRng.seeded(5)
	var events := KnowledgeRules.process_turn(data, state, rng)
	var entry: Dictionary = state["factions"]["red"]["knowledge"].get("test_smithing", {})
	t.check_eq(String(entry.get("stage", "")), "aware",
		"the craft crosses the border as awareness")
	t.check_near(float(entry.get("discount_pct", 0.0)), 0.0, 0.001, "rumor carries no discount")
	var spread_channel := ""
	for event in events:
		if event.get("kind", "") == "technique_spread" and event.get("faction", "") == "red":
			spread_channel = String(event.get("channel", ""))
	t.check_eq(spread_channel, "border", "shared lands are the strongest channel these two have")
	for i in range(5):
		KnowledgeRules.process_turn(data, state, rng)
	t.check_eq(state["factions"]["rebels"]["knowledge"].size(), 0,
		"rebels have no court — knowledge never flows to them")


func test_diffusion_needs_contact_and_names_the_channel(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.balance["knowledge"]["origination_base_chance"] = 0.0
	data.balance["knowledge"]["diffusion_base_chance"] = 1.0
	# Rearrange the line so red and blue no longer touch: a rebel wall at beta.
	state["settlements"]["beta"]["owner"] = "rebels"
	state["factions"]["red"]["diplomacy"]["blue"] = "neutral"
	state["factions"]["blue"]["diplomacy"]["red"] = "neutral"
	state["factions"]["blue"]["knowledge"]["test_smithing"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	var rng := CampaignRng.seeded(9)
	for i in range(5):
		KnowledgeRules.process_turn(data, state, rng)
	t.check(not state["factions"]["red"]["knowledge"].has("test_smithing"),
		"strangers with no border exchange nothing")
	state["factions"]["red"]["diplomacy"]["blue"] = "alliance"
	state["factions"]["blue"]["diplomacy"]["red"] = "alliance"
	var events := KnowledgeRules.process_turn(data, state, rng)
	var spread_channel := ""
	for event in events:
		if event.get("kind", "") == "technique_spread" and event.get("faction", "") == "red":
			spread_channel = String(event.get("channel", ""))
	t.check_eq(spread_channel, "alliance", "allied courts share freely, and the report says so")


func test_reform_pressure_accumulates_decays_and_discounts(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	KnowledgeRules.on_battle_lost(data, state, "red")
	t.check_near(float(state["factions"]["red"]["reform_pressure"]), 2.0, 0.001,
		"a lost battle leaves its mark")
	KnowledgeRules.on_settlement_lost(data, state, "red")
	t.check_near(float(state["factions"]["red"]["reform_pressure"]), 6.0, 0.001,
		"a lost city cuts deeper")
	for i in range(20):
		KnowledgeRules.on_battle_lost(data, state, "red")
	t.check_near(float(state["factions"]["red"]["reform_pressure"]), 20.0, 0.001,
		"pressure caps at the maximum")
	data.balance["knowledge"]["origination_base_chance"] = 0.0
	data.balance["knowledge"]["diffusion_base_chance"] = 0.0
	KnowledgeRules.process_turn(data, state, CampaignRng.seeded(1))
	t.check_near(float(state["factions"]["red"]["reform_pressure"]), 19.5, 0.001,
		"and fades as the defeats recede")
	KnowledgeRules.on_battle_lost(data, state, "rebels")
	t.check_near(float(state["factions"]["rebels"]["reform_pressure"]), 0.0, 0.001,
		"rebels feel no reform pressure")


func test_conquest_teaches_the_victor(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["factions"]["blue"]["knowledge"]["test_smithing"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	state["factions"]["blue"]["knowledge"]["test_letters"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	var rng := CampaignRng.seeded(2)
	CombatRules.capture_settlement(data, state, rng, "alpha", "red", "occupy")
	var entry: Dictionary = state["factions"]["red"]["knowledge"].get("test_smithing", {})
	t.check_eq(String(entry.get("stage", "")), "aware",
		"the victor learns what the fallen city practiced")
	t.check_near(float(entry.get("discount_pct", 0.0)), 40.0, 0.001,
		"with a conquest discount toward adopting it")
	t.check(not state["factions"]["red"]["knowledge"].has("test_letters"),
		"mere awareness does not transfer — only practiced crafts")
	t.check_near(float(state["factions"]["blue"]["reform_pressure"]), 4.0, 0.001,
		"the loser's court reels")


func test_steal_technique(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.balance["knowledge"]["steal_base_chance"] = 1.0
	data.balance["knowledge"]["steal_max_chance"] = 1.0
	state["factions"]["blue"]["knowledge"]["test_smithing"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	state["factions"]["blue"]["knowledge"]["test_letters"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	var spy_id := AgentRules.recruit_agent(data, state, "beta", "spy")
	state["agents"][spy_id]["region"] = "alpha"
	var rng := CampaignRng.seeded(4)
	t.check(not bool(AgentRules.steal_technique(data, state, rng, spy_id, "test_letters")["attempted"]),
		"the city cannot teach what its masters do not practice")
	var result := AgentRules.steal_technique(data, state, rng, spy_id, "test_smithing")
	t.check(bool(result["success"]), "the drawings come home")
	var entry: Dictionary = state["factions"]["red"]["knowledge"].get("test_smithing", {})
	t.check_eq(String(entry.get("stage", "")), "aware", "as awareness")
	t.check_near(float(entry.get("discount_pct", 0.0)), 30.0, 0.001, "with the espionage discount")
	t.check_eq(int(state["agents"][spy_id]["skill"]), 2, "the spy's craft sharpens")
	t.check(not bool(AgentRules.steal_technique(data, state, rng, spy_id, "test_smithing")["attempted"]),
		"nothing left to steal once the head start is home")

	var diplomat_id := AgentRules.recruit_agent(data, state, "beta", "diplomat")
	state["agents"][diplomat_id]["region"] = "alpha"
	t.check(not bool(AgentRules.steal_technique(data, state, rng, diplomat_id, "test_smithing")["attempted"]),
		"an envoy is no thief")

	data.balance["knowledge"]["steal_base_chance"] = 0.0
	data.balance["knowledge"]["steal_min_chance"] = 0.0
	data.balance["knowledge"]["steal_failure_death_chance"] = 1.0
	state["factions"]["blue"]["knowledge"]["test_greatworks"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	var doomed_id := AgentRules.recruit_agent(data, state, "beta", "spy")
	state["agents"][doomed_id]["region"] = "alpha"
	var failure := AgentRules.steal_technique(data, state, rng, doomed_id, "test_greatworks")
	t.check(bool(failure["agent_lost"]), "a botched theft costs the spy")
	t.check(not state["agents"].has(doomed_id), "he does not come home")
	t.check(float(state["factions"]["blue"]["attitude_memory"].get("red", 0.0)) < 0.0,
		"and the wronged court remembers whose coin paid him")


func test_ensure_state_keys_seeds_legacy_saves(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	for fid in state["factions"]:
		state["factions"][fid].erase("knowledge")
		state["factions"][fid].erase("reform_pressure")
	NewGame.ensure_state_keys(state)
	t.check_eq(state["factions"]["blue"]["knowledge"].size(), 0,
		"without data the ledger is merely created empty")
	t.check_near(float(state["factions"]["red"]["reform_pressure"]), 0.0, 0.001, "pressure defaults")
	for fid in state["factions"]:
		state["factions"][fid].erase("knowledge")
	NewGame.ensure_state_keys(state, data)
	t.check_eq(String(state["factions"]["blue"]["knowledge"].get("test_smithing", {}).get("stage", "")),
		"adopted", "with data a legacy save receives its culture's endowment")
	t.check_eq(state["factions"]["red"]["knowledge"].size(), 0,
		"and only its own — Rome starts with none of these")
	t.check_eq(state["factions"]["rebels"]["knowledge"].size(), 0, "rebels stay empty")


func test_process_turn_lockstep_after_json_round_trip(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"]["beta"]["buildings"]["test_education"] = 1
	state["factions"]["blue"]["knowledge"]["test_smithing"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	state["factions"]["red"]["knowledge"]["test_letters"] = {"stage": "aware", "turn": 0, "progress": 0, "discount_pct": 0.0}
	KnowledgeRules.begin_adoption(data, state, "red", "test_letters")
	var twin: Dictionary = JSON.parse_string(JSON.stringify(state))
	var rng_a := CampaignRng.seeded(77)
	var rng_b := CampaignRng.seeded(77)
	for i in range(6):
		KnowledgeRules.process_turn(data, state, rng_a)
		KnowledgeRules.process_turn(data, twin, rng_b)
	t.check_eq(_canonical(state), _canonical(twin),
		"a JSON round trip (re-ordered dictionaries) marches in lockstep")
	t.check_eq(rng_a.state_string(), rng_b.state_string(),
		"down to the very rng stream")


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)))

func test_effects_reach_growth_order_and_economy(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.techniques["test_omni"] = {
		"id": "test_omni", "name": "Omni", "domain": "scholarship_statecraft",
		"historical_basis": "fixture",
		"start_adopted": {"cultures": [], "factions": []}, "origin_cultures": [],
		"prerequisites": {"building_kind": "", "building_level": 0, "resource": "", "hidden_resource": "", "coastal": false, "techniques": []},
		"adoption": {"cost": 100, "turns": 1}, "culture_resistance": {},
		"effects": {"growth": 0.5, "happiness": 3, "trade_pct": 10, "farm_income_pct": 10,
			"mine_income_pct": 10, "corruption_reduction_pct": 50},
	}
	var farming_before := _factor(EconomyRules.settlement_income_breakdown(data, state, "beta"), "farming")
	state["factions"]["red"]["knowledge"]["test_omni"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}

	t.check_near(_factor(GrowthRules.breakdown(data, state, "beta"), "knowledge"), 0.5, 0.001,
		"growth breakdown carries a named knowledge factor")
	t.check_near(_factor(PublicOrderRules.breakdown(data, state, "beta"), "knowledge"), 3.0, 0.001,
		"public order likewise")
	t.check_near(_factor(GrowthRules.breakdown(data, state, "alpha"), "knowledge"), 0.0, 0.001,
		"and only for the court that practices it")
	var farming_after := _factor(EconomyRules.settlement_income_breakdown(data, state, "beta"), "farming")
	t.check_near(farming_after, farming_before * 1.1, 0.01, "farm income rises ten parts in a hundred")


func test_effects_reach_movement_and_siege(t) -> void:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	data.techniques["test_logistics"] = {
		"id": "test_logistics", "name": "Logistics", "domain": "logistics_trade",
		"historical_basis": "fixture",
		"start_adopted": {"cultures": [], "factions": []}, "origin_cultures": [],
		"prerequisites": {"building_kind": "", "building_level": 0, "resource": "", "hidden_resource": "", "coastal": false, "techniques": []},
		"adoption": {"cost": 100, "turns": 1}, "culture_resistance": {},
		"effects": {"movement_points": 0.25, "naval_movement_pct": 10, "siege_equipment_turns_delta": -1},
	}
	var army_id := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	state["fleets"]["fleet_1"] = {"owner": "red", "sea_zone": "test_sea", "ships": [], "movement_left": 0.0}
	MovementRules.reset_movement(data, state)
	t.check_near(float(state["armies"][army_id]["movement_left"]), 2.0, 0.001, "base march")
	t.check_near(float(state["fleets"]["fleet_1"]["movement_left"]), 2.0, 0.001, "base sailing")
	state["factions"]["red"]["knowledge"]["test_logistics"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	MovementRules.reset_movement(data, state)
	t.check_near(float(state["armies"][army_id]["movement_left"]), 2.25, 0.001,
		"practiced logistics stretch the column's march")
	t.check_near(float(state["fleets"]["fleet_1"]["movement_left"]), 2.2, 0.001,
		"and the season's sailing — the dormant naval effect lives")

	# Siege works: the delta shortens equipment building, never below one turn.
	var enemy_army := Fixtures.add_army(state, "red", "alpha", ["test_spears"])
	SiegeRules.begin_siege(data, state, enemy_army, "alpha")
	var quiet := QuietResolver.new()
	SiegeRules.advance_sieges(data, state, CampaignRng.seeded(1), quiet)
	var siege = state["settlements"]["alpha"]["siege"]
	t.check(siege != null and bool(siege["equipment_ready"]),
		"torsion-craft besiegers raise their works in a single season")

	# The defender's wallcraft raises the AI's honest estimate of the assault.
	var defense_before := AiStrategy.settlement_defense(data, state, "alpha")
	state["settlements"]["alpha"]["garrison"].append({"template": "test_mob", "experience": 0, "strength_pct": 100})
	defense_before = AiStrategy.settlement_defense(data, state, "alpha")
	state["factions"]["blue"]["knowledge"]["test_greatworks"] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	t.check(AiStrategy.settlement_defense(data, state, "alpha") > defense_before,
		"timber-laced ramparts fight a tier above the stones")


class QuietResolver:
	extends BattleResolver
	## A resolver that never fights — lets siege-progression tests advance
	## turns without a starve-out battle steering the assertions.
	func resolve(_data: GameData, _rng: CampaignRng, _attacker_units: Array, _defender_units: Array, _context: Dictionary) -> Dictionary:
		return {"winner": "defender", "attacker_casualty_pct": 0.0, "defender_casualty_pct": 0.0,
			"attacker_general_died": false, "defender_general_died": false, "experience_gained": 0}


func _factor(factors: Array, label: String) -> float:
	for factor in factors:
		if factor["label"] == label:
			return float(factor["value"])
	return 0.0
