class_name AiMilitary
## Field operations for one AI faction's turn: press ongoing sieges, relieve
## threatened settlements, fight or avoid field battles by odds, march on the
## chosen expansion target (over land, or by a sea crossing whenever that is
## the cheaper or only open road), and raise new field armies from garrison
## surpluses. All fighting resolves through the injected BattleResolver with
## the campaign RNG; every decision is a deterministic odds threshold from
## data/balance.json, evaluated in sorted order.


static func take_turn(data: GameData, state: Dictionary, faction_id: String, context: Dictionary, rng: CampaignRng, resolver: BattleResolver, ai_notices: Array, character_notices: Array) -> void:
	var handled := {}  # army_id -> true once an army has acted this turn

	for army_id in _own_armies(state, faction_id):
		RecruitmentRules.merge_units(state["armies"][army_id]["units"])
	_merge_colocated(data, state, faction_id)

	if context["is_rebel"]:
		# Rebels never expand — a siege inherited from a dead faction's
		# defecting army is lifted, not pressed.
		_abandon_rebel_sieges(state, faction_id)
	_press_sieges(data, state, faction_id, rng, resolver, handled, ai_notices, character_notices)
	_defend(data, state, faction_id, rng, resolver, handled, ai_notices, character_notices)
	if not context["is_rebel"]:
		_campaign_on_target(data, state, faction_id, context, rng, resolver, handled, ai_notices, character_notices)
		_send_idle_home(data, state, faction_id, context, handled)
		_muster(data, state, faction_id, context)


static func _own_armies(state: Dictionary, faction_id: String) -> Array:
	var found: Array = []
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		if state["armies"][army_id]["owner"] == faction_id:
			found.append(army_id)
	return found


static func _merge_colocated(data: GameData, state: Dictionary, faction_id: String) -> void:
	## Waves arriving at the same front combine into one striking force. The
	## besieging army (else the largest) receives; donors without generals fold
	## in up to the receiver's unit cap, and a generalled donor that fits whole
	## hands its general to a general-less receiver. Two generalled armies stay
	## separate commands.
	var cap := int(data.balance["ai"]["army_max_units"])
	var by_region := {}
	for army_id in _own_armies(state, faction_id):
		var region: String = state["armies"][army_id]["region"]
		if not by_region.has(region):
			by_region[region] = []
		by_region[region].append(army_id)
	var region_ids: Array = by_region.keys()
	region_ids.sort()
	for region_id in region_ids:
		var group: Array = by_region[region_id]
		if group.size() < 2:
			continue
		var receiver := ""
		var besieger := ""
		if state["settlements"].has(region_id) and state["settlements"][region_id]["siege"] != null:
			besieger = state["settlements"][region_id]["siege"]["besieger"]
		var best_size := -1
		for army_id in group:
			if army_id == besieger:
				receiver = army_id
				break
			var size: int = state["armies"][army_id]["units"].size()
			if size > best_size:
				receiver = army_id
				best_size = size
		for army_id in group:
			if army_id == receiver or not state["armies"].has(army_id):
				continue
			var donor: Dictionary = state["armies"][army_id]
			var into: Dictionary = state["armies"][receiver]
			var room: int = cap - into["units"].size()
			if room <= 0:
				break
			if donor["general"] == null:
				while room > 0 and not donor["units"].is_empty():
					into["units"].append(donor["units"].pop_back())
					room -= 1
				if donor["units"].is_empty():
					state["armies"].erase(army_id)
			elif into["general"] == null and donor["units"].size() <= room:
				into["units"].append_array(donor["units"])
				into["general"] = donor["general"]
				state["armies"].erase(army_id)


## --- Sieges ---------------------------------------------------------------

static func _abandon_rebel_sieges(state: Dictionary, faction_id: String) -> void:
	for army_id in _own_armies(state, faction_id):
		var region_id: String = state["armies"][army_id]["region"]
		if not state["settlements"].has(region_id):
			continue
		var siege = state["settlements"][region_id]["siege"]
		if siege != null and siege["besieger"] == army_id:
			state["settlements"][region_id]["siege"] = null


static func _press_sieges(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng, resolver: BattleResolver, handled: Dictionary, ai_notices: Array, character_notices: Array) -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	var assault_odds := float(ai_rules["assault_odds"])
	var siege_odds := float(ai_rules["siege_odds"])
	for army_id in _own_armies(state, faction_id):
		var army: Dictionary = state["armies"][army_id]
		var region_id: String = army["region"]
		if not state["settlements"].has(region_id):
			continue
		var siege = state["settlements"][region_id]["siege"]
		if siege == null or siege["besieger"] != army_id:
			continue
		var attack_power := AiAssess.army_power(data, state, army)
		# A siege that would end in a slaughter at the walls when the garrison
		# finally sallies is lifted now — the army falls back through the
		# normal flow this turn instead of feeding the grinder.
		if attack_power < AiAssess.sally_defense_power(data, state, region_id) * siege_odds:
			state["settlements"][region_id]["siege"] = null
			continue
		# Holding the lines is always an action: the army neither marches nor
		# joins another task while its siege stands.
		handled[army_id] = true
		if not siege["equipment_ready"]:
			continue
		if attack_power >= AiAssess.assault_defense_power(data, state, region_id) * assault_odds:
			_assault(data, state, faction_id, army_id, region_id, rng, resolver, ai_notices, character_notices)


static func _assault(data: GameData, state: Dictionary, faction_id: String, army_id: String, region_id: String, rng: CampaignRng, resolver: BattleResolver, ai_notices: Array, character_notices: Array) -> void:
	var result := SiegeRules.assault(data, state, rng, resolver, army_id, region_id)
	if result.is_empty():
		return
	character_notices.append_array(result.get("character_notices", []))
	if result.get("captured", false):
		var general = state["armies"].get(army_id, {}).get("general")
		CombatRules.capture_settlement(data, state, rng, region_id,
			result["capture_pending_owner"], "occupy")
		var occupation_notices: Array = []
		CombatRules.fire_occupation_triggers(data, state, rng, general, "occupy", occupation_notices)
		character_notices.append_array(occupation_notices)
		ai_notices.append({"kind": "captured", "faction": faction_id, "region": region_id})
		_garrison_captured(data, state, army_id)
	else:
		ai_notices.append({"kind": "assault_repelled", "faction": faction_id, "region": region_id})


static func _garrison_captured(data: GameData, state: Dictionary, army_id: String) -> void:
	## Leave a holding force in a freshly taken settlement: the weakest units
	## stay to keep order, the strongest march on. A force too small to split
	## garrisons entirely.
	if not state["armies"].has(army_id):
		return
	var army: Dictionary = state["armies"][army_id]
	var ai_rules: Dictionary = data.balance["ai"]
	var keep := int(ai_rules["garrison_units_frontier"])
	if army["units"].size() <= keep + int(ai_rules["muster_min_units"]) - 1:
		CombatRules.garrison_army(data, state, army_id, army["region"])
		return
	var order := _indices_by_power(data, army["units"])  # ascending power
	CombatRules.detach_to_garrison(data, state, army_id, order.slice(0, keep))


static func _indices_by_power(data: GameData, units: Array) -> Array:
	var indices: Array = []
	for i in range(units.size()):
		indices.append(i)
	indices.sort_custom(func(a, b):
		var power_a := AiAssess.unit_power(data, [units[a]])
		var power_b := AiAssess.unit_power(data, [units[b]])
		return power_a < power_b if power_a != power_b else a < b)
	return indices


## --- Defence --------------------------------------------------------------

static func _defend(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng, resolver: BattleResolver, handled: Dictionary, ai_notices: Array, character_notices: Array) -> void:
	var relieve_odds := float(data.balance["ai"]["relieve_odds"])
	for region_id in AiAssess.owned_regions(state, faction_id):
		var intruders := AiAssess.hostile_armies_in(state, faction_id, region_id)
		if intruders.is_empty():
			continue
		var threat_power := AiAssess.hostile_power_in(data, state, faction_id, region_id)
		var defender := _nearest_able_army(data, state, faction_id, region_id, handled,
			threat_power * relieve_odds)
		if defender == "":
			continue
		handled[defender] = true
		var blocked := _march(data, state, defender,
			AiAssess.distance_map(data, state, faction_id, [region_id]))
		var army: Dictionary = state["armies"][defender]
		if army["region"] == region_id or MapRules.are_adjacent(data, army["region"], region_id):
			_attack_strongest(data, state, faction_id, defender, region_id, rng, resolver,
				ai_notices, character_notices, 0.0)  # committed: the relief odds were checked from home
		elif blocked != "":
			# The road to the besieged city is fought open at field odds.
			_attack_strongest(data, state, faction_id, defender, blocked, rng, resolver,
				ai_notices, character_notices, float(data.balance["ai"]["attack_odds"]))


static func _nearest_able_army(data: GameData, state: Dictionary, faction_id: String, region_id: String, handled: Dictionary, needed_power: float) -> String:
	var costs := AiAssess.distance_map(data, state, faction_id, [region_id])
	var best := ""
	var best_cost := 1 << 30
	for army_id in _own_armies(state, faction_id):
		if handled.has(army_id):
			continue
		var army: Dictionary = state["armies"][army_id]
		if AiAssess.army_power(data, state, army) < needed_power:
			continue
		var cost := int(costs.get(army["region"], 1 << 30))
		if cost < best_cost:
			best = army_id
			best_cost = cost
	return best


## --- The campaign against the chosen target -------------------------------

static func _campaign_on_target(data: GameData, state: Dictionary, faction_id: String, context: Dictionary, rng: CampaignRng, resolver: BattleResolver, handled: Dictionary, ai_notices: Array, character_notices: Array) -> void:
	var goal: String = context["target"]
	if goal == "":
		return
	var attack_odds := float(data.balance["ai"]["attack_odds"])
	var siege_odds := float(data.balance["ai"]["siege_odds"])
	for army_id in _own_armies(state, faction_id):
		if handled.has(army_id):
			continue
		if not state["armies"].has(army_id):
			continue
		handled[army_id] = true
		var army: Dictionary = state["armies"][army_id]
		# A column caught by a stronger force pulls back toward friendly walls
		# rather than pressing the advance.
		if _should_retreat(data, state, faction_id, army):
			_march(data, state, army_id,
				AiAssess.distance_map(data, state, faction_id,
					AiAssess.owned_regions(state, faction_id)))
			continue
		# An army the goal map cannot even see is stranded — the passable road
		# net to this target does not touch it. Walking at the goal is
		# hopeless; fold back toward home and let the garrison absorb it.
		if not context["goal_costs"].has(army["region"]):
			_march(data, state, army_id,
				AiAssess.distance_map(data, state, faction_id,
					AiAssess.owned_regions(state, faction_id)))
			army = state["armies"][army_id]
			if state["settlements"].has(army["region"]) \
					and state["settlements"][army["region"]]["owner"] == faction_id:
				CombatRules.garrison_army(data, state, army_id, army["region"])
			continue
		var blocked := _march(data, state, army_id, context["goal_costs"])
		if not state["armies"].has(army_id):
			continue
		army = state["armies"][army_id]
		# Fight for the approaches: clear hostile field armies off the army's
		# own ground, the goal, or the road that blocked the march.
		var fought := _attack_strongest(data, state, faction_id, army_id, army["region"],
			rng, resolver, ai_notices, character_notices, attack_odds)
		if not fought and MapRules.are_adjacent(data, army["region"], goal):
			fought = _attack_strongest(data, state, faction_id, army_id, goal,
				rng, resolver, ai_notices, character_notices, attack_odds)
		if not fought and blocked != "" and blocked != goal:
			_attack_strongest(data, state, faction_id, army_id, blocked,
				rng, resolver, ai_notices, character_notices, attack_odds)
		if not state["armies"].has(army_id):
			continue
		army = state["armies"][army_id]
		if (army["region"] == goal or MapRules.are_adjacent(data, army["region"], goal)) \
				and state["settlements"].has(goal):
			# Invest only with the strength to survive the eventual sally —
			# anything less feeds the garrison a victory at the walls.
			var strong_enough := AiAssess.army_power(data, state, army) \
				>= AiAssess.sally_defense_power(data, state, goal) * siege_odds
			if strong_enough and AiAssess.hostile_armies_in(state, faction_id, goal).is_empty() \
					and state["settlements"][goal]["siege"] == null \
					and SiegeRules.begin_siege(data, state, army_id, goal):
				ai_notices.append({"kind": "siege_laid", "faction": faction_id, "region": goal})
			elif not strong_enough and army["region"] == goal:
				# A mauled remnant standing in the hostile region falls back
				# to friendly ground to meet the next wave.
				_march(data, state, army_id,
					AiAssess.distance_map(data, state, faction_id,
						AiAssess.owned_regions(state, faction_id)))


static func _should_retreat(data: GameData, state: Dictionary, faction_id: String, army: Dictionary) -> bool:
	var local_threat := AiAssess.hostile_power_in(data, state, faction_id, army["region"])
	if local_threat <= 0.0:
		return false
	var retreat_odds := float(data.balance["ai"]["retreat_odds"])
	return AiAssess.army_power(data, state, army) < local_threat * retreat_odds


static func _attack_strongest(data: GameData, state: Dictionary, faction_id: String, army_id: String, region_id: String, rng: CampaignRng, resolver: BattleResolver, ai_notices: Array, character_notices: Array, required_odds: float) -> bool:
	## Attack the strongest at-war army in a region (they would reinforce each
	## other anyway; beat the biggest and the rest are cleaned up next turns).
	## required_odds 0 means committed — attack whatever stands there.
	var targets := AiAssess.hostile_armies_in(state, faction_id, region_id)
	if targets.is_empty():
		return false
	var army: Dictionary = state["armies"][army_id]
	if army["region"] != region_id and not MapRules.are_adjacent(data, army["region"], region_id):
		return false
	var strongest := ""
	var strongest_power := -1.0
	for target_id in targets:
		var power := AiAssess.field_defense_power(data, state, state["armies"][target_id])
		if power > strongest_power:
			strongest = target_id
			strongest_power = power
	if required_odds > 0.0 \
			and AiAssess.army_power(data, state, army) < strongest_power * required_odds:
		return false
	var defender_owner: String = state["armies"][strongest]["owner"]
	var result := CombatRules.attack_army(data, state, resolver, rng, army_id, strongest)
	if result.is_empty():
		return false
	character_notices.append_array(result.get("character_notices", []))
	ai_notices.append({
		"kind": "battle", "faction": faction_id, "against": defender_owner,
		"region": region_id, "winner": result["winner"],
	})
	return true


## --- Marching -------------------------------------------------------------

static func _march(data: GameData, state: Dictionary, army_id: String, goal_costs: Dictionary) -> String:
	## Walk down the cost-to-goal map while movement lasts. When the land route
	## is blocked or absent, try one sea crossing toward the goal. Armies never
	## force-march (the fatigue malus is not worth arriving a season early).
	## Returns the region whose hostile occupiers stopped the march ("" when
	## the march simply ended) so the caller can decide to fight for the road.
	var army: Dictionary = state["armies"][army_id]
	for i in range(16):  # hard cap; each step spends movement so this terminates
		var here: String = army["region"]
		var here_cost := int(goal_costs.get(here, 1 << 30))
		if here_cost == 0:
			return ""
		var next_step := ""
		var next_cost := here_cost
		for neighbor in data.regions[here].get("adjacent", []):
			if not goal_costs.has(neighbor):
				continue
			var cost := int(goal_costs[neighbor])
			if cost < next_cost:
				next_step = neighbor
				next_cost = cost
		if next_step != "" and MovementRules.move_army(data, state, army_id, next_step):
			continue
		# Blocked on land (hostile army, no budget, no route): try the sea once.
		if _sea_step(data, state, army_id, goal_costs, here_cost):
			return ""  # a crossing spends the whole turn's movement
		if next_step != "" and not AiAssess.hostile_armies_in(state, army["owner"], next_step).is_empty():
			return next_step
		return ""
	return ""


static func _sea_step(data: GameData, state: Dictionary, army_id: String, goal_costs: Dictionary, here_cost: int) -> bool:
	## Cross to the cheapest reachable shore that genuinely shortens the road,
	## trying candidates in cost order — the nearest berth can be blocked (a
	## hostile army, an unconnected zone) while the next one is open.
	var army: Dictionary = state["armies"][army_id]
	if data.regions[army["region"]].get("sea_zones", []).is_empty():
		return false
	var ceiling := here_cost - AiAssess.sea_hop_cost(data) + 1
	var candidates: Array = []
	for region_id in AiAssess.sea_neighbors(data, army["region"]):
		if goal_costs.has(region_id) and int(goal_costs[region_id]) < ceiling:
			candidates.append({"cost": int(goal_costs[region_id]), "region": region_id})
	candidates.sort_custom(func(a, b):
		return a["cost"] < b["cost"] if a["cost"] != b["cost"] else String(a["region"]) < String(b["region"]))
	for candidate in candidates:
		if MovementRules.sea_move_army(data, state, army_id, candidate["region"]):
			return true
	return false


## --- Homecoming and mustering ---------------------------------------------

static func _send_idle_home(data: GameData, state: Dictionary, faction_id: String, context: Dictionary, handled: Dictionary) -> void:
	## With no war to fight, field armies fold back into the nearest city's
	## garrison, where they keep order and can be retrained.
	if context["target"] != "":
		return
	var owned := AiAssess.owned_regions(state, faction_id)
	if owned.is_empty():
		return
	var home_costs := AiAssess.distance_map(data, state, faction_id, owned)
	for army_id in _own_armies(state, faction_id):
		if handled.has(army_id):
			continue
		var army: Dictionary = state["armies"][army_id]
		_march(data, state, army_id, home_costs)
		if state["settlements"].has(army["region"]) \
				and state["settlements"][army["region"]]["owner"] == faction_id:
			CombatRules.garrison_army(data, state, army_id, army["region"])


static func _muster(data: GameData, state: Dictionary, faction_id: String, context: Dictionary) -> void:
	## Raise one new field army a turn from the staging settlement's garrison
	## surplus while the campaign against the target is under-strength.
	var goal: String = context["target"]
	if goal == "" or context["staging"] == "":
		return
	var ai_rules: Dictionary = data.balance["ai"]

	# The assault is carried by ONE army, so the muster stops only when the
	# strongest single force suffices — split waves don't add up at the walls.
	var offensive_power := 0.0
	for army_id in _own_armies(state, faction_id):
		offensive_power = maxf(offensive_power,
			AiAssess.army_power(data, state, state["armies"][army_id]))
	var needed := AiAssess.assault_defense_power(data, state, goal) * float(ai_rules["assault_odds"])
	if offensive_power > 0.0 and offensive_power >= needed:
		return  # a standing field force already suffices — even for an open gate
	context["wants_muster"] = true

	var staging: String = context["staging"]
	var settlement: Dictionary = state["settlements"][staging]
	var floor_units := garrison_floor(data, state, staging)
	var garrison: Array = settlement["garrison"]
	var surplus := garrison.size() - floor_units
	var muster_min := int(ai_rules["muster_min_units"])
	if surplus < muster_min:
		return
	var take := mini(surplus, int(ai_rules["army_max_units"]))
	var order := _indices_by_power(data, garrison)
	order.reverse()  # strongest units take the field, the rest keep order at home
	CombatRules.raise_army(data, state, staging, order.slice(0, take),
		_best_general(data, state, faction_id, staging))


static func garrison_floor(data: GameData, state: Dictionary, region_id: String) -> int:
	var ai_rules: Dictionary = data.balance["ai"]
	match AiAssess.threat_level(data, state, region_id):
		"threatened":
			return int(ai_rules["garrison_units_threatened"])
		"frontier":
			return int(ai_rules["garrison_units_frontier"])
		_:
			return int(ai_rules["garrison_units_interior"])


static func _best_general(data: GameData, state: Dictionary, faction_id: String, region_id: String) -> Variant:
	## The highest-command adult male of the house standing in the settlement
	## and not already leading an army. null means a captain takes the column.
	var leading := {}
	for army in state["armies"].values():
		if army["general"] != null:
			leading[army["general"]] = true
	var best = null
	var best_command := -1
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if not character["alive"] or character["faction"] != faction_id:
			continue
		if character.get("location", "") != region_id or leading.has(char_id):
			continue
		if character.get("gender", "male") != "male" or character["role"] in ["spouse", "child"]:
			continue
		if int(character["age"]) < int(data.balance["characters"]["come_of_age"]):
			continue
		var command := CharacterRules.effective(data, character, "command")
		if command > best_command:
			best = char_id
			best_command = command
	return best
