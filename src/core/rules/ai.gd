class_name AiRules
## Phase 6: the AI that plays every non-player faction. Four modular
## behaviours run in a fixed order each turn — economy, defence, diplomacy,
## expansion — so the world builds, garrisons, declares its wars, and takes
## the field on its own. All tunables live in balance.json → ai; per-faction
## temperament (aggression, whether the faction expands at all) comes from
## factions.json → ai. Rebels only manage and defend what they hold.
##
## Determinism rules of the house apply throughout: every dictionary
## iteration that can steer an RNG draw or a decision walks its keys in
## sorted order, and every random draw goes through the campaign RNG.


static func take_turn(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng, resolver: BattleResolver, notices: Array) -> void:
	var faction: Dictionary = state["factions"][faction_id]
	if not faction["alive"]:
		return
	if not faction.has("ai_memory"):
		faction["ai_memory"] = {"target": null, "war_since": {}}
	var is_rebel: bool = data.factions.get(faction_id, {}).get("is_rebel", false)

	_economy(data, state, faction_id)
	_merge_field_armies(state, faction_id)
	_defence(data, state, faction_id, rng, resolver, notices)
	if not is_rebel:
		_diplomacy(data, state, faction_id, rng, notices)
		_expansion(data, state, faction_id, rng, resolver, notices)


static func _merge_field_armies(state: Dictionary, faction_id: String) -> void:
	## Battered same-template units in the field fold together for free.
	for army_id in _faction_army_ids(state, faction_id):
		RecruitmentRules.merge_units(state["armies"][army_id]["units"])


## --- Economy: taxes, construction, garrisons ------------------------------

static func _economy(data: GameData, state: Dictionary, faction_id: String) -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	for region_id in _owned_regions(state, faction_id):
		var settlement: Dictionary = state["settlements"][region_id]
		_tune_taxes(data, state, region_id, ai_rules)
		_queue_best_building(data, state, region_id, ai_rules)
		_keep_garrison_manned(data, state, region_id, ai_rules)
		RecruitmentRules.merge_units(settlement["garrison"])


static func _tune_taxes(data: GameData, state: Dictionary, region_id: String, ai_rules: Dictionary) -> void:
	var settlement: Dictionary = state["settlements"][region_id]
	var order := PublicOrderRules.total(data, state, region_id)
	var tax_index := Constants.TAX_LEVELS.find(String(settlement["tax_level"]))
	if order < float(ai_rules["tax_lower_below_order"]) and tax_index > 0:
		settlement["tax_level"] = Constants.TAX_LEVELS[tax_index - 1]
	elif order > float(ai_rules["tax_raise_above_order"]) and tax_index < Constants.TAX_LEVELS.size() - 1:
		settlement["tax_level"] = Constants.TAX_LEVELS[tax_index + 1]


static func _queue_best_building(data: GameData, state: Dictionary, region_id: String, ai_rules: Dictionary) -> void:
	var settlement: Dictionary = state["settlements"][region_id]
	if not settlement["construction_queue"].is_empty():
		return
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var priority: Dictionary = ai_rules["build_priority"]
	var best := {}
	var best_key: Array = []
	for project in ConstructionRules.available_projects(data, state, region_id):
		if int(faction["treasury"]) < int(project["cost"]) + int(ai_rules["build_reserve"]):
			continue
		var key := [float(priority.get(project["kind"], 99.0)), float(project["cost"]), String(project["chain"])]
		if best.is_empty() or key < best_key:
			best = project
			best_key = key
	if not best.is_empty():
		ConstructionRules.queue_project(data, state, region_id, best["chain"])


static func _keep_garrison_manned(data: GameData, state: Dictionary, region_id: String, ai_rules: Dictionary) -> void:
	var settlement: Dictionary = state["settlements"][region_id]
	if not settlement["recruitment_queue"].is_empty():
		return
	var faction: Dictionary = state["factions"][settlement["owner"]]
	var target := _garrison_target(data, settlement, ai_rules)
	if _threatened(data, state, region_id):
		target += int(ai_rules["threat_garrison_bonus_units"])
	if settlement["garrison"].size() >= target:
		return
	_queue_best_unit(data, state, region_id, int(ai_rules["recruit_reserve"]))


static func _queue_best_unit(data: GameData, state: Dictionary, region_id: String, reserve: int) -> bool:
	var faction: Dictionary = state["factions"][state["settlements"][region_id]["owner"]]
	var best := {}
	var best_key: Array = []
	for unit in RecruitmentRules.available_units(data, state, region_id):
		if int(faction["treasury"]) < int(unit["cost"]) + reserve:
			continue
		# Best fighting value first; among equals the cheaper unit drills faster.
		var quality := float(unit["attack"]) + float(unit["defense"]) + float(unit["morale"])
		var key := [-quality, float(unit["cost"]), String(unit["id"])]
		if best.is_empty() or key < best_key:
			best = unit
			best_key = key
	if best.is_empty():
		return false
	return RecruitmentRules.queue_unit(data, state, region_id, best["id"])


static func _garrison_target(data: GameData, settlement: Dictionary, ai_rules: Dictionary) -> int:
	var level := SettlementRules.settlement_level(data, settlement)
	var targets: Array = ai_rules["garrison_units_by_level"]
	return int(targets[mini(Constants.level_index(level), targets.size() - 1)])


static func _threatened(data: GameData, state: Dictionary, region_id: String) -> bool:
	## A hostile army in the region or one step away means trouble is coming.
	var owner: String = state["settlements"][region_id]["owner"]
	for army in state["armies"].values():
		if not DiplomacyRules.at_war(state, owner, army["owner"]):
			continue
		if army["region"] == region_id or MapRules.are_adjacent(data, region_id, army["region"]):
			return true
	return false


## --- Defence: relieve besieged settlements --------------------------------

static func _defence(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng, resolver: BattleResolver, notices: Array) -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	for region_id in _owned_regions(state, faction_id):
		var settlement: Dictionary = state["settlements"][region_id]
		var siege = settlement["siege"]
		if siege == null:
			continue
		var besieger_id: String = siege["besieger"]
		if not state["armies"].has(besieger_id):
			continue
		var besieger_strength := _army_strength(data, state, state["armies"][besieger_id])
		for army_id in _faction_army_ids(state, faction_id):
			if not state["armies"].has(besieger_id):
				break
			if not state["armies"].has(army_id):
				continue
			var army: Dictionary = state["armies"][army_id]
			if army["region"] != region_id and not MapRules.are_adjacent(data, army["region"], region_id):
				continue
			# Relief attacks accept worse odds than conquest — the city is at stake.
			if _army_strength(data, state, army) < besieger_strength * float(ai_rules["defend_attack_ratio"]):
				continue
			var result := CombatRules.attack_army(data, state, resolver, rng, army_id, besieger_id)
			if not result.is_empty():
				_notice_battle(notices, state, region_id, faction_id, result)
			if not state["armies"].has(besieger_id):
				break


## --- Diplomacy: opening wars, tiring of them ------------------------------

static func _diplomacy(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng, notices: Array) -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	var faction: Dictionary = state["factions"][faction_id]
	var memory: Dictionary = faction["ai_memory"]
	var war_since: Dictionary = memory["war_since"]
	var turn := int(state["turn"])

	# Remember when each war began; forget wars that have ended — and wars
	# against the dead, which otherwise pin the war counter forever.
	var partner_ids: Array = state["factions"].keys()
	partner_ids.sort()
	for other_id in partner_ids:
		if other_id == faction_id or data.factions.get(other_id, {}).get("is_rebel", false):
			continue
		if state["factions"][other_id]["alive"] and DiplomacyRules.at_war(state, faction_id, other_id):
			if not war_since.has(other_id):
				war_since[other_id] = turn
		else:
			war_since.erase(other_id)

	# Weariness: a long war we are losing ends when the other side, also an AI,
	# does not smell victory — and any war old enough exhausts both thrones no
	# matter who is ahead. Peace with the player is a Phase 5 negotiation.
	var my_strength := _faction_strength(data, state, faction_id)
	for other_id in partner_ids:
		if not war_since.has(other_id) or other_id == state["player_faction"]:
			continue
		var at_war_for := turn - int(war_since[other_id])
		if at_war_for < int(ai_rules["war_weariness_turns"]):
			continue
		if at_war_for < int(ai_rules["war_exhaustion_turns"]):
			var their_strength := _faction_strength(data, state, other_id)
			if my_strength >= their_strength * float(ai_rules["peace_seek_ratio"]):
				continue
			if their_strength > my_strength * float(ai_rules["peace_accept_ratio"]):
				continue
		DiplomacyRules.set_stance(state, faction_id, other_id, "neutral")
		war_since.erase(other_id)
		var their_memory: Dictionary = state["factions"][other_id].get("ai_memory", {})
		if their_memory.has("war_since"):
			their_memory["war_since"].erase(faction_id)
		notices.append({"kind": "peace", "faction": faction_id, "other": other_id})

	# A new war wants an idle sword arm, a full treasury, and a weak neighbor.
	if war_since.size() >= int(ai_rules["max_active_wars"]):
		return
	if int(faction["treasury"]) < int(ai_rules["declare_war_min_treasury"]):
		return
	var aggression: float = _personality(data, faction_id, "aggression", float(ai_rules["default_aggression"]))
	if aggression <= 0.0:
		return
	var candidate := _war_candidate(data, state, faction_id, my_strength, ai_rules)
	if candidate == "":
		return
	if not rng.chance(aggression * float(ai_rules["declare_war_chance"])):
		return
	DiplomacyRules.declare_war(data, state, faction_id, candidate)
	war_since[candidate] = turn
	notices.append({"kind": "war_declared", "faction": faction_id, "other": candidate})


static func _war_candidate(data: GameData, state: Dictionary, faction_id: String, my_strength: float, ai_rules: Dictionary) -> String:
	## The weakest bordering faction we could plausibly beat. Roman houses and
	## the senate never turn on each other before a civil war; alliances and
	## protectorates hold until Phase 5 gives betrayal a price.
	var mine: Dictionary = data.factions.get(faction_id, {})
	var civil_war: bool = state["factions"][faction_id]["at_civil_war"]
	var best := ""
	var best_strength := 0.0
	var neighbor_factions := _bordering_factions(data, state, faction_id)
	for other_id in neighbor_factions:
		if not state["factions"][other_id]["alive"]:
			continue
		var other: Dictionary = data.factions.get(other_id, {})
		if other.get("is_rebel", false):
			continue
		var stance := DiplomacyRules.stance_between(state, faction_id, other_id)
		if stance in ["war", "alliance", "protectorate"]:
			continue
		if not civil_war and (mine.get("is_roman_house", false) or mine.get("is_senate", false)) \
				and (other.get("is_roman_house", false) or other.get("is_senate", false)):
			continue
		var their_strength := _faction_strength(data, state, other_id)
		if my_strength < their_strength * float(ai_rules["declare_war_strength_ratio"]):
			continue
		# Hated neighbors are struck first; among equals, the weakest.
		var attitude := NegotiationRules.attitude_total(data, state, other_id, faction_id)
		var score := their_strength * (1.0 + clampf(attitude, -100.0, 100.0) / 200.0)
		if best == "" or score < best_strength:
			best = other_id
			best_strength = score
	return best


static func _bordering_factions(data: GameData, state: Dictionary, faction_id: String) -> Array:
	var found := {}
	for region_id in _owned_regions(state, faction_id):
		for neighbor in data.regions[region_id].get("adjacent", []):
			if not state["settlements"].has(neighbor):
				continue
			var other: String = state["settlements"][neighbor]["owner"]
			if other != faction_id:
				found[other] = true
	var result: Array = found.keys()
	result.sort()
	return result


## --- Expansion: pick a target, muster, march, besiege, assault ------------

static func _expansion(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng, resolver: BattleResolver, notices: Array) -> void:
	if not bool(_personality(data, faction_id, "expands", 1.0)):
		return
	var ai_rules: Dictionary = data.balance["ai"]
	var memory: Dictionary = state["factions"][faction_id]["ai_memory"]

	var target := _validate_target(data, state, faction_id, memory.get("target"))
	if target == "":
		target = _pick_target(data, state, faction_id)
	memory["target"] = target if target != "" else null

	if target != "":
		_prepare_expedition(data, state, faction_id, target, ai_rules)
		_muster(data, state, faction_id, target, ai_rules)
		_march_armies(data, state, faction_id, target, rng, resolver, ai_rules, notices)
	else:
		_stand_down(data, state, faction_id)


static func _prepare_expedition(data: GameData, state: Dictionary, faction_id: String, target: String, ai_rules: Dictionary) -> void:
	## A war needs soldiers beyond the city watch: the settlement nearest the
	## front recruits past its defensive garrison until an expedition's worth
	## of surplus stands ready to be fielded.
	var muster_region := _muster_region(data, state, faction_id, target, ai_rules)
	if muster_region == "":
		return
	var settlement: Dictionary = state["settlements"][muster_region]
	if not settlement["recruitment_queue"].is_empty():
		return
	var wanted: int = _garrison_target(data, settlement, ai_rules) + int(ai_rules["expedition_units"])
	if settlement["garrison"].size() >= wanted:
		return
	_queue_best_unit(data, state, muster_region, int(ai_rules["war_chest_reserve"]))


static func _muster_region(data: GameData, state: Dictionary, faction_id: String, target: String, ai_rules: Dictionary) -> String:
	## The owned settlement nearest the target that can actually raise troops.
	var hops_to_target := MapRules.hops_from(data, target)
	var best := ""
	var best_key: Array = []
	for region_id in _owned_regions(state, faction_id):
		if RecruitmentRules.available_units(data, state, region_id).is_empty():
			continue
		var key := [int(hops_to_target.get(region_id, 98)), region_id]
		if best == "" or key < best_key:
			best = region_id
			best_key = key
	return best


static func _validate_target(data: GameData, state: Dictionary, faction_id: String, target) -> String:
	if target == null or not (target is String) or not state["settlements"].has(target):
		return ""
	var owner: String = state["settlements"][target]["owner"]
	if owner == faction_id or not DiplomacyRules.at_war(state, faction_id, owner):
		return ""
	return target


static func _pick_target(data: GameData, state: Dictionary, faction_id: String) -> String:
	## Nearest, weakest settlement of any faction we are at war with (the
	## rebels count — their lands are the natural first conquests).
	var owned := _owned_regions(state, faction_id)
	if owned.is_empty():
		return ""
	var best := ""
	var best_score := 0.0
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] == faction_id:
			continue
		if not DiplomacyRules.at_war(state, faction_id, settlement["owner"]):
			continue
		var hops := _nearest_hops(data, owned, region_id)
		if hops < 0:
			if not _sea_reachable(data, state, faction_id, region_id):
				continue
			hops = 6  # a sea crossing counts as a long march
		var garrison_strength := BattleResolver.force_strength(
			data, settlement["garrison"], null,
			float(data.balance["battle"]["experience_strength_pct_per_chevron"]))
		var score := float(hops) + garrison_strength / 2000.0
		if best == "" or score < best_score:
			best = region_id
			best_score = score
	return best


static func _nearest_hops(data: GameData, owned: Array, region_id: String) -> int:
	var hops := MapRules.hops_from(data, region_id)
	var best := -1
	for own_region in owned:
		var distance := int(hops.get(own_region, -1))
		if distance >= 0 and (best < 0 or distance < best):
			best = distance
	return best


static func _landing_zones(data: GameData, target: String) -> Dictionary:
	## Sea zones from which an army could land on or beside the target
	## (sea_move_army reaches the same or an adjacent zone).
	var zones := {}
	var shores: Array = [target]
	for neighbor in data.regions[target].get("adjacent", []):
		shores.append(neighbor)
	for region_id in shores:
		for zone in data.regions.get(region_id, {}).get("sea_zones", []):
			zones[zone] = true
	return zones


static func _zone_connects(data: GameData, region_id: String, landing_zones: Dictionary) -> bool:
	for zone in data.regions.get(region_id, {}).get("sea_zones", []):
		if landing_zones.has(zone):
			return true
		for adjacent_zone in data.sea_zones.get(zone, {}).get("adjacent", []):
			if landing_zones.has(adjacent_zone):
				return true
	return false


static func _sea_reachable(data: GameData, state: Dictionary, faction_id: String, target: String) -> bool:
	## True when some settlement we hold sits on a coast whose sea zone reaches
	## the target's landing zones — the crossing sea_move_army can make.
	var landing_zones := _landing_zones(data, target)
	if landing_zones.is_empty():
		return false
	for region_id in _owned_regions(state, faction_id):
		if _zone_connects(data, region_id, landing_zones):
			return true
	return false


static func _embark_region(data: GameData, state: Dictionary, from_region: String, target: String) -> String:
	## The nearest land-reachable coast from which the crossing to the target
	## can be made. "" when no such coast exists.
	var landing_zones := _landing_zones(data, target)
	if landing_zones.is_empty():
		return ""
	var hops := MapRules.hops_from(data, from_region)
	var best := ""
	var best_hops := 1 << 20
	var region_ids: Array = data.regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		if not hops.has(region_id):
			continue
		if not _zone_connects(data, region_id, landing_zones):
			continue
		if int(hops[region_id]) < best_hops:
			best_hops = int(hops[region_id])
			best = region_id
	return best


static func _muster(data: GameData, state: Dictionary, faction_id: String, target: String, ai_rules: Dictionary) -> void:
	## Field the garrison surplus nearest the front. The strongest units march;
	## the defensive minimum stays home.
	var hops_to_target := MapRules.hops_from(data, target)
	var best_region := ""
	var best_key: Array = []
	for region_id in _owned_regions(state, faction_id):
		var settlement: Dictionary = state["settlements"][region_id]
		var surplus: int = settlement["garrison"].size() - _garrison_target(data, settlement, ai_rules)
		if surplus < 1:
			continue
		var distance := int(hops_to_target.get(region_id, 99))
		var key := [distance, -surplus, region_id]
		if best_region == "" or key < best_key:
			best_region = region_id
			best_key = key
	if best_region == "":
		return

	var settlement: Dictionary = state["settlements"][best_region]
	var keep := _garrison_target(data, settlement, ai_rules)
	var surplus: int = settlement["garrison"].size() - keep
	var indices := _strongest_indices(data, settlement["garrison"], surplus)

	# Reinforce an army already mustered here rather than splitting commands.
	var existing := ""
	for army_id in _faction_army_ids(state, faction_id):
		if state["armies"][army_id]["region"] == best_region:
			existing = army_id
			break
	if existing != "":
		var cap := int(ai_rules["army_unit_cap"])
		indices.sort()
		indices.reverse()
		for index in indices:
			if state["armies"][existing]["units"].size() >= cap:
				break
			state["armies"][existing]["units"].append(settlement["garrison"][index])
			settlement["garrison"].remove_at(index)
		return

	# A new expedition marches at full strength, not in dribs and drabs.
	if surplus < int(ai_rules["expedition_units"]):
		return
	var general := _idle_general_in(data, state, faction_id, best_region)
	ArmyRules.form_army(data, state, best_region, indices, general)


static func _strongest_indices(data: GameData, garrison: Array, count: int) -> Array:
	var scored: Array = []
	for i in range(garrison.size()):
		var template: Dictionary = data.units.get(garrison[i]["template"], {})
		var quality := float(template.get("attack", 0)) + float(template.get("defense", 0)) \
			+ float(template.get("morale", 0))
		scored.append([-quality, i])
	scored.sort()
	var indices: Array = []
	for i in range(mini(count, scored.size())):
		indices.append(scored[i][1])
	return indices


static func _idle_general_in(data: GameData, state: Dictionary, faction_id: String, region_id: String) -> String:
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	var best := ""
	var best_command := -1
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["faction"] != faction_id or not character["alive"]:
			continue
		if character.get("location", "") != region_id:
			continue
		if not ArmyRules._can_lead(data, state, faction_id, region_id, char_id):
			continue
		var command := CharacterRules.effective(data, character, "command")
		if command > best_command:
			best_command = command
			best = char_id
	return best


static func _march_armies(data: GameData, state: Dictionary, faction_id: String, target: String, rng: CampaignRng, resolver: BattleResolver, ai_rules: Dictionary, notices: Array) -> void:
	var hops_to_target := MapRules.hops_from(data, target)
	for army_id in _faction_army_ids(state, faction_id):
		if not state["armies"].has(army_id):
			continue
		var army: Dictionary = state["armies"][army_id]
		# An army holding one of our own besieged cities' regions stays put.
		var here: Dictionary = state["settlements"].get(army["region"], {})
		if not here.is_empty() and here["owner"] == faction_id and here["siege"] != null:
			continue
		_march_one_army(data, state, army_id, target, hops_to_target, rng, resolver, ai_rules, notices)


static func _march_one_army(data: GameData, state: Dictionary, army_id: String, target: String, hops_to_target: Dictionary, rng: CampaignRng, resolver: BattleResolver, ai_rules: Dictionary, notices: Array) -> void:
	var guard := 0
	while state["armies"].has(army_id) and guard < 16:
		guard += 1
		var army: Dictionary = state["armies"][army_id]
		var region: String = army["region"]

		if region == target or MapRules.are_adjacent(data, region, target):
			_press_the_siege(data, state, army_id, target, rng, resolver, ai_rules, notices)
			return

		if float(army["movement_left"]) <= 0.0:
			return

		# When no land road leads to the target, march for the embarkation
		# coast instead and take ship from there.
		var gradient := hops_to_target
		var sailing := false
		if not hops_to_target.has(region):
			if _try_sea_leg(data, state, army_id, target):
				continue
			var embark := _embark_region(data, state, region, target)
			if embark == "":
				return
			if embark == region:
				return  # at the coast but the crossing is barred this season
			gradient = MapRules.hops_from(data, embark)
			sailing = true

		var current_hops := int(gradient.get(region, 1 << 20))
		var step := ""
		var blocked := ""
		var adjacent: Array = data.regions[region].get("adjacent", []).duplicate()
		adjacent.sort()
		var step_hops := current_hops
		for neighbor in adjacent:
			var neighbor_hops := int(gradient.get(neighbor, 1 << 20))
			if neighbor_hops >= step_hops:
				continue
			if MovementRules.can_enter(data, state, army_id, neighbor):
				step = neighbor
				step_hops = neighbor_hops
			elif blocked == "":
				blocked = neighbor

		if step != "":
			if not MovementRules.move_army(data, state, army_id, step):
				return
			continue

		# The road is barred. Fight through a hostile army if the odds serve;
		# otherwise try the sea; otherwise wait for a better season.
		if blocked != "":
			var enemy := _hostile_army_in(state, army["owner"], blocked)
			if enemy != "" and _army_strength(data, state, army) \
					>= _army_strength(data, state, state["armies"][enemy]) * float(ai_rules["attack_strength_ratio"]):
				var result := CombatRules.attack_army(data, state, resolver, rng, army_id, enemy)
				if not result.is_empty():
					_notice_battle(notices, state, blocked, army["owner"], result)
				return
		if not sailing and _try_sea_leg(data, state, army_id, target):
			continue
		return


static func _press_the_siege(data: GameData, state: Dictionary, army_id: String, target: String, rng: CampaignRng, resolver: BattleResolver, ai_rules: Dictionary, notices: Array) -> void:
	var army: Dictionary = state["armies"][army_id]
	var settlement: Dictionary = state["settlements"][target]
	if not DiplomacyRules.at_war(state, army["owner"], settlement["owner"]):
		return

	# Field enemies at the walls are dealt with before the siege lines close.
	var enemy := _hostile_army_in(state, army["owner"], target)
	if enemy != "" and settlement.get("siege") == null:
		if _army_strength(data, state, army) >= _army_strength(data, state, state["armies"][enemy]) \
				* float(ai_rules["attack_strength_ratio"]):
			var result := CombatRules.attack_army(data, state, resolver, rng, army_id, enemy)
			if not result.is_empty():
				_notice_battle(notices, state, target, army["owner"], result)
		return

	var siege = settlement["siege"]
	if siege == null:
		SiegeRules.begin_siege(data, state, army_id, target)
		return
	if siege["besieger"] != army_id:
		return
	if not siege.get("equipment_ready", false):
		return
	var wall_level := int(SettlementRules.effect_max(data, settlement, "wall_level"))
	var wall_multipliers: Array = data.balance["battle"]["wall_defense_multiplier"]
	var xp_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	var governor = settlement["governor"]
	var governor_profile = null
	if governor != null and state["characters"].has(governor):
		governor_profile = CharacterRules.battle_profile(data, state["characters"][governor])
	var defence := BattleResolver.force_strength(data, settlement["garrison"], governor_profile, xp_pct) \
		* float(wall_multipliers[mini(wall_level, wall_multipliers.size() - 1)])
	var offence := _army_strength(data, state, army)
	if offence < defence * float(ai_rules["assault_strength_ratio"]):
		return  # keep starving them out
	var owner: String = army["owner"]
	var defender: String = settlement["owner"]
	var result := CombatRules.assault_and_capture(data, state, rng, resolver, army_id, target, "occupy")
	if result.get("captured", false):
		notices.append({"kind": "captured", "faction": owner, "region": target, "from": defender})
		for notice in result.get("character_notices", []):
			notices.append(notice)
	elif not result.is_empty():
		_notice_battle(notices, state, target, owner, result)


static func _try_sea_leg(data: GameData, state: Dictionary, army_id: String, target: String) -> bool:
	## Cross the water toward the target: land on the target's coast, or on a
	## friendly/neutral coastal region beside it.
	var candidates: Array = [target]
	for neighbor in data.regions[target].get("adjacent", []):
		candidates.append(neighbor)
	candidates.sort()
	for candidate in candidates:
		if candidate == state["armies"][army_id]["region"]:
			continue
		if MovementRules.sea_move_army(data, state, army_id, candidate):
			return true
	return false


static func _stand_down(data: GameData, state: Dictionary, faction_id: String) -> void:
	## No war to fight: armies standing in their own cities disperse into the
	## garrison, sparing the treasury their field upkeep.
	for army_id in _faction_army_ids(state, faction_id):
		if not state["armies"].has(army_id):
			continue
		var army: Dictionary = state["armies"][army_id]
		var here: Dictionary = state["settlements"].get(army["region"], {})
		if not here.is_empty() and here["owner"] == faction_id:
			CombatRules.garrison_army(data, state, army_id, army["region"])


## --- Shared helpers -------------------------------------------------------

static func _owned_regions(state: Dictionary, faction_id: String) -> Array:
	var owned: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] == faction_id:
			owned.append(region_id)
	return owned


static func _faction_army_ids(state: Dictionary, faction_id: String) -> Array:
	var ids: Array = []
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		if state["armies"][army_id]["owner"] == faction_id:
			ids.append(army_id)
	return ids


static func _army_strength(data: GameData, state: Dictionary, army: Dictionary) -> float:
	return BattleResolver.force_strength(data, army["units"],
		CombatRules.general_profile(data, state, army),
		float(data.balance["battle"]["experience_strength_pct_per_chevron"]))


static func _faction_strength(data: GameData, state: Dictionary, faction_id: String) -> float:
	## Field armies plus garrisons — the whole war-making weight of a faction.
	var xp_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	var total := 0.0
	for army_id in _faction_army_ids(state, faction_id):
		total += _army_strength(data, state, state["armies"][army_id])
	for region_id in _owned_regions(state, faction_id):
		total += BattleResolver.force_strength(
			data, state["settlements"][region_id]["garrison"], null, xp_pct)
	return total


static func _hostile_army_in(state: Dictionary, faction_id: String, region_id: String) -> String:
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army["region"] == region_id and DiplomacyRules.at_war(state, faction_id, army["owner"]):
			return army_id
	return ""


static func _personality(data: GameData, faction_id: String, key: String, fallback: Variant) -> Variant:
	return data.factions.get(faction_id, {}).get("ai", {}).get(key, fallback)


static func _notice_battle(notices: Array, state: Dictionary, region_id: String, attacker_faction: String, result: Dictionary) -> void:
	notices.append({
		"kind": "battle", "region": region_id, "faction": attacker_faction,
		"winner": result.get("winner", ""),
	})
	# Character news from AI battles (traits earned, men of the hour) still
	# matters when the player's own army was the defender.
	for notice in result.get("character_notices", []):
		notices.append(notice)
