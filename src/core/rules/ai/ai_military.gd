class_name AiMilitary
## The AI's armies: field armies are mustered from a city's surplus garrison
## near the current target, stacks in one region merge, and every army each
## season either presses its siege (assaulting when the odds are right),
## attacks an enemy army within reach, runs to a threatened city and mans its
## walls, marches on the nearest independent town or enemy city it can take,
## or goes home. All fighting goes through CombatRules and SiegeRules — the
## same paths, the same BattleResolver, the same occupation choice the
## player makes, decided here by the personality's cruelty.


static func act(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, brain: Dictionary, notices: Array) -> void:
	var faction_id: String = brain["id"]
	if not brain["is_rebel"]:
		muster(data, state, brain)
		merge_stacks(data, state, brain)
	for army_id in AiController.armies_of(state, faction_id):
		if state["armies"].has(army_id):
			order_army(data, state, rng, resolver, brain, army_id, notices)


## --- Threats and targets ---------------------------------------------------------

static func threat_at(data: GameData, state: Dictionary, faction_id: String, region_id: String) -> float:
	## Strength of hostile armies standing in or beside a region. Summed in
	## sorted order: the total gates decisions, and float sums depend on order.
	var total := 0.0
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if not DiplomacyRules.at_war(state, faction_id, army["owner"]):
			continue
		if army["region"] == region_id or MapRules.are_adjacent(data, army["region"], region_id):
			total += AiController.army_strength(data, state, army)
	return total


static func most_threatened(data: GameData, state: Dictionary, brain: Dictionary, from_region: String) -> String:
	## The nearest own settlement whose walls could not hold against what
	## stands outside them, within marching reach; "" if all is quiet.
	var rules: Dictionary = brain["rules"]
	var hops := MapRules.hops_from(data, from_region)
	var best := ""
	var best_distance := 1 << 30
	for region_id in AiController.settlements_of(state, brain["id"]):
		var distance := int(hops.get(region_id, -1))
		if distance < 0 or distance > int(rules["defend_max_hops"]):
			continue
		var threat := threat_at(data, state, brain["id"], region_id)
		if threat <= 0.0:
			continue
		if AiController.settlement_strength(data, state, region_id) >= threat * float(rules["defend_threat_ratio"]):
			continue
		if distance < best_distance:
			best = region_id
			best_distance = distance
	return best


static func expansion_target(data: GameData, state: Dictionary, brain: Dictionary, from_region: String, strength: float = -1.0) -> String:
	## The nearest settlement worth marching on: independent towns while the
	## personality expands, cities of powers we are at war with, all within a
	## few hops of our own lands and reachable by land. Nearest first, then
	## the weakest defended. Given an army's `strength`, only settlements that
	## army could take by the personality's siege margin count.
	var rules: Dictionary = brain["rules"]
	var faction_id: String = brain["id"]
	var hops := MapRules.hops_from(data, from_region)
	var needed := AiController.needed_ratio(brain, float(rules["siege_strength_ratio"]))
	var best := ""
	var best_key: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		var owner: String = settlement["owner"]
		if owner == faction_id:
			continue
		var is_rebel: bool = data.factions.get(owner, {}).get("is_rebel", false)
		if is_rebel and AiController.weight(brain, "expansion") <= 0.0:
			continue
		if not is_rebel and not DiplomacyRules.at_war(state, faction_id, owner):
			continue
		if settlement["siege"] != null:
			var besieger: Dictionary = state["armies"].get(settlement["siege"]["besieger"], {})
			if besieger.get("owner", "") != faction_id:
				continue
		var distance := int(hops.get(region_id, -1))
		if distance < 0:
			continue
		var from_lands := AiController.hops_to_lands(data, state, faction_id, region_id)
		if from_lands < 0 or from_lands > int(rules["expansion_target_max_hops"]):
			continue
		var defence := AiController.settlement_strength(data, state, region_id)
		if strength >= 0.0 and defence * needed > strength:
			continue
		var key := [distance, defence, region_id]
		if best == "" or key < best_key:
			best = region_id
			best_key = key
	return best


static func muster_city(data: GameData, state: Dictionary, brain: Dictionary) -> String:
	## The own settlement nearest the current target: where the field army
	## gathers and the recruiter over-provisions. "" when no army is wanted.
	var rules: Dictionary = brain["rules"]
	var faction_id: String = brain["id"]
	if brain["is_rebel"]:
		return ""
	# Ambition grows with the purse: a rich house fields more armies.
	var max_armies := int(rules["max_field_armies_base"]) \
		+ int(round(AiController.weight(brain, "expansion") * float(rules["max_field_armies_expansion_bonus"]))) \
		+ int(maxi(0, int(state["factions"][faction_id]["treasury"])) / int(rules["field_army_gold_per_extra"]))
	max_armies = mini(max_armies, int(rules["max_field_armies_cap"]))
	if AiController.armies_of(state, faction_id).size() >= max_armies:
		return ""
	var best := ""
	var best_distance := 1 << 30
	for region_id in AiController.settlements_of(state, faction_id):
		var target := expansion_target(data, state, brain, region_id)
		if target == "":
			continue
		var distance := MapRules.hops_between(data, region_id, target)
		if distance >= 0 and distance < best_distance:
			best = region_id
			best_distance = distance
	return best


## --- Mustering and merging ------------------------------------------------------------

static func muster(data: GameData, state: Dictionary, brain: Dictionary) -> String:
	## Takes the garrison's surplus above its own target into a new field
	## army, strongest units first, led by a family member present who is not
	## the governor. Returns the army id or "".
	var rules: Dictionary = brain["rules"]
	var city := muster_city(data, state, brain)
	if city == "":
		return ""
	# A city that cannot hold its own walls keeps every man on them.
	if most_threatened(data, state, brain, city) == city:
		return ""
	var settlement: Dictionary = state["settlements"][city]
	var keep := AiEconomy.desired_garrison(data, state, brain, city, false)
	var surplus: int = settlement["garrison"].size() - keep
	if surplus < int(rules["field_army_min_units"]):
		return ""
	var general = CombatRules.available_general(data, state, brain["id"], city)
	return CombatRules.raise_army(data, state, city, mini(surplus, int(rules["field_army_max_units"])), general)


static func merge_stacks(data: GameData, state: Dictionary, brain: Dictionary) -> void:
	## Two of our armies sharing a region become one, up to the stack cap,
	## unless either is pressing a siege. A captain's stack joins a general's;
	## two generals keep their own commands.
	var rules: Dictionary = brain["rules"]
	var army_ids := AiController.armies_of(state, brain["id"])
	for i in range(army_ids.size()):
		for j in range(i + 1, army_ids.size()):
			if not state["armies"].has(army_ids[i]) or not state["armies"].has(army_ids[j]):
				continue
			var first: Dictionary = state["armies"][army_ids[i]]
			var second: Dictionary = state["armies"][army_ids[j]]
			if second["region"] != first["region"]:
				continue
			if _is_besieging(state, army_ids[i]) or _is_besieging(state, army_ids[j]):
				continue
			if first["general"] != null and second["general"] != null:
				continue
			if first["units"].size() + second["units"].size() > int(rules["merge_stack_max_units"]):
				continue
			var keeper_id: String = army_ids[i] if second["general"] == null else army_ids[j]
			var other_id: String = army_ids[j] if keeper_id == army_ids[i] else army_ids[i]
			var keeper: Dictionary = state["armies"][keeper_id]
			var other: Dictionary = state["armies"][other_id]
			keeper["units"].append_array(other["units"])
			keeper["movement_left"] = minf(float(keeper["movement_left"]), float(other["movement_left"]))
			state["armies"].erase(other_id)


## --- Orders -----------------------------------------------------------------------------

static func order_army(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, brain: Dictionary, army_id: String, notices: Array) -> void:
	var rules: Dictionary = brain["rules"]
	var faction_id: String = brain["id"]
	var army: Dictionary = state["armies"][army_id]
	var here: String = army["region"]
	var faction: Dictionary = state["factions"][faction_id]

	# 1. A siege in hand: storm when the odds allow, otherwise keep starving them.
	if _is_besieging(state, army_id):
		var settlement: Dictionary = state["settlements"][here]
		if SiegeRules.can_assault(settlement["siege"]):
			var ours := AiController.army_strength(data, state, army)
			var theirs := AiController.settlement_strength(data, state, here)
			if ours >= theirs * AiController.needed_ratio(brain, float(rules["assault_strength_ratio"])):
				assault(data, state, rng, resolver, brain, army_id, here, notices)
		return

	# 2. An enemy army within reach — never for a house that starts nothing.
	var prey := weakest_enemy_army_near(data, state, faction_id, here) \
		if AiController.weight(brain, "aggression") > 0.0 else ""
	if prey != "":
		var enemy: Dictionary = state["armies"][prey]
		var ours := AiController.army_strength(data, state, army)
		var theirs := AiController.army_strength(data, state, enemy) \
			* float(data.balance["battle"]["terrain_defense_multiplier"].get(data.regions[enemy["region"]]["terrain"], 1.0))
		if ours >= theirs * AiController.needed_ratio(brain, float(rules["attack_strength_ratio"])):
			var enemy_owner: String = enemy["owner"]
			var battlefield: String = enemy["region"]
			var result := CombatRules.attack_army(data, state, resolver, rng, army_id, prey)
			if not result.is_empty():
				notices.append({"kind": "battle", "attacker": faction_id, "defender": enemy_owner,
					"region": battlefield, "winner": result["winner"],
					"defender_destroyed": not state["armies"].has(prey),
					"attacker_destroyed": not state["armies"].has(army_id),
					"defender_general_died": result.get("defender_general_died", false),
					"attacker_general_died": result.get("attacker_general_died", false)})
				notices.append_array(result.get("character_notices", []))
			if not state["armies"].has(army_id) or result.get("winner", "") == "attacker":
				return
			army = state["armies"][army_id]
			here = army["region"]

	# 3. A city of ours that cannot hold: run to it and man the walls.
	if not brain["is_rebel"]:
		var threatened := most_threatened(data, state, brain, here)
		if threatened != "":
			if here != threatened:
				march_toward(data, state, army_id, threatened, false)
			if state["armies"][army_id]["region"] == threatened:
				CombatRules.garrison_army(data, state, army_id, threatened)
			return

		# 4. The nearest town or city this army could take.
		var strength := AiController.army_strength(data, state, army)
		var target := expansion_target(data, state, brain, here, strength)
		if target != "":
			if here == target or MapRules.are_adjacent(data, here, target):
				var owner: String = state["settlements"][target]["owner"]
				if SiegeRules.begin_siege(data, state, army_id, target):
					notices.append({"kind": "siege_laid", "from": faction_id, "region": target, "owner": owner})
				return
			march_toward(data, state, army_id, target, true)
			return

	# 5. Nothing to do: go home, and stand down if the purse is thin.
	var home := AiController.nearest_own_settlement(data, state, faction_id, here)
	if home == "":
		return
	if here != home:
		march_toward(data, state, army_id, home, false)
		return
	var reserve := AiController.reserve_for(brain, AiController.settlements_of(state, faction_id).size())
	if int(faction["treasury"]) < reserve or brain["is_rebel"]:
		CombatRules.garrison_army(data, state, army_id, home)


static func assault(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, brain: Dictionary, army_id: String, region_id: String, notices: Array) -> Dictionary:
	var settlement: Dictionary = state["settlements"][region_id]
	var previous_owner: String = settlement["owner"]
	var occupation := occupation_choice(data, state, brain, region_id)
	var result := SiegeRules.assault_and_capture(data, state, rng, resolver, army_id, region_id, occupation)
	if not result.is_empty():
		notices.append({"kind": "assault", "from": brain["id"], "region": region_id, "owner": previous_owner,
			"captured": result.get("captured", false), "occupation": occupation,
			"defender_general_died": result.get("defender_general_died", false)})
		notices.append_array(result.get("character_notices", []))
	return result


static func occupation_choice(data: GameData, state: Dictionary, brain: Dictionary, region_id: String) -> String:
	## Cruel personalities put foreign cities to the sword and sell large
	## ones into slavery; everyone else occupies.
	var rules: Dictionary = brain["rules"]
	var settlement: Dictionary = state["settlements"][region_id]
	var cruelty := AiController.weight(brain, "cruelty")
	var foreign := data.culture_of_faction(settlement["owner"]) != data.culture_of_faction(brain["id"])
	if cruelty >= float(rules["exterminate_cruelty_threshold"]) and foreign:
		return "exterminate"
	if cruelty >= float(rules["enslave_cruelty_threshold"]) \
			and int(settlement["population"]) >= int(rules["enslave_min_population"]):
		return "enslave"
	return "occupy"


static func weakest_enemy_army_near(data: GameData, state: Dictionary, faction_id: String, region_id: String) -> String:
	## The weakest army we are at war with, standing here or beside us.
	var best := ""
	var best_strength := 0.0
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if not DiplomacyRules.at_war(state, faction_id, army["owner"]):
			continue
		if army["region"] != region_id and not MapRules.are_adjacent(data, region_id, army["region"]):
			continue
		var strength := AiController.army_strength(data, state, army)
		if best == "" or strength < best_strength:
			best = army_id
			best_strength = strength
	return best


static func march_toward(data: GameData, state: Dictionary, army_id: String, target: String, stop_adjacent: bool) -> bool:
	## Steps along the shortest land path while movement lasts, never into a
	## region MovementRules would refuse. Returns true if any step was taken.
	var moved := false
	var hops := MapRules.hops_from(data, target)
	while state["armies"].has(army_id):
		var army: Dictionary = state["armies"][army_id]
		var here: String = army["region"]
		if here == target or (stop_adjacent and MapRules.are_adjacent(data, here, target)):
			break
		var best := ""
		var best_hops := int(hops.get(here, 1 << 20))
		var neighbors: Array = data.regions[here].get("adjacent", []).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			var distance := int(hops.get(neighbor, 1 << 20))
			if distance < best_hops and MovementRules.can_enter(data, state, army_id, neighbor):
				best = neighbor
				best_hops = distance
		if best == "" or not MovementRules.move_army(data, state, army_id, best):
			break
		moved = true
	return moved


## --- Internals ------------------------------------------------------------------------------

static func _is_besieging(state: Dictionary, army_id: String) -> bool:
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return false
	var settlement: Dictionary = state["settlements"].get(army["region"], {})
	return not settlement.is_empty() and settlement["siege"] != null and settlement["siege"]["besieger"] == army_id



