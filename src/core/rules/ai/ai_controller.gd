class_name AiController
## Phase 6: the campaign AI. Every non-player faction plays through the same
## rules the player uses, in a fixed order — diplomacy, economy, armies,
## agents — steered by data-tunable personality weights
## (data/ai_personalities.json) and thresholds (balance.json → ai). Decisions
## are pure functions of the game state, walking sorted ids; the only dice are
## the battles and agent attempts they start, which draw from the turn's
## CampaignRng like everyone else's, so a loaded save replays exactly.
##
## The "brain" handed to each behaviour is a plain dictionary:
##   {id, p: personality weights, rules: balance.ai, memory: the faction's
##    persistent "ai" record, aggression_multiplier (difficulty), turn, is_rebel}


static func take_turn(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, faction_id: String, notices: Array) -> void:
	var faction: Dictionary = state["factions"][faction_id]
	if not faction["alive"] or faction_id == state["player_faction"]:
		return
	var brain := context(data, state, faction_id)
	AiDiplomacy.act(data, state, brain, notices)
	AiEconomy.act(data, state, rng, brain, notices)
	AiMilitary.act(data, state, rng, resolver, brain, notices)
	AiAgents.act(data, state, rng, brain, notices)


static func context(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	var faction: Dictionary = state["factions"][faction_id]
	if not faction.has("ai") or not (faction["ai"] is Dictionary):
		faction["ai"] = {"offers": {}, "last_war_turn": -999, "envoy_target": ""}
	var rules: Dictionary = data.balance["ai"]
	var difficulty: String = state.get("difficulty", "medium")
	return {
		"id": faction_id,
		"p": data.personality_of(faction_id),
		"rules": rules,
		"memory": faction["ai"],
		"aggression_multiplier": float(rules["difficulty_aggression_multiplier"].get(difficulty, 1.0)),
		"turn": int(state["turn"]),
		"is_rebel": data.factions.get(faction_id, {}).get("is_rebel", false),
	}


## --- Shared queries ---------------------------------------------------------------

static func weight(brain: Dictionary, key: String) -> float:
	return float(brain["p"].get(key, 0.5))


static func settlements_of(state: Dictionary, faction_id: String) -> Array:
	var result: Array = []
	for region_id in state["settlements"]:
		if state["settlements"][region_id]["owner"] == faction_id:
			result.append(region_id)
	result.sort()
	return result


static func armies_of(state: Dictionary, faction_id: String) -> Array:
	var result: Array = []
	for army_id in state["armies"]:
		if state["armies"][army_id]["owner"] == faction_id:
			result.append(army_id)
	result.sort()
	return result


static func strength_of(data: GameData, units: Array, general: Variant = null) -> float:
	var experience_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	return BattleResolver.force_strength(data, units, general, experience_pct)


static func army_strength(data: GameData, state: Dictionary, army: Dictionary) -> float:
	return strength_of(data, army["units"], CombatRules.general_profile(data, state, army))


static func settlement_strength(data: GameData, state: Dictionary, region_id: String) -> float:
	## What an assault would meet: the garrison behind its walls on its ground,
	## led by the governor. Open gates count for nothing.
	var settlement: Dictionary = state["settlements"][region_id]
	var battle_rules: Dictionary = data.balance["battle"]
	var governor_profile = null
	if settlement["governor"] != null and state["characters"].has(settlement["governor"]):
		governor_profile = CharacterRules.battle_profile(data, state["characters"][settlement["governor"]])
	var strength := strength_of(data, settlement["garrison"], governor_profile)
	var wall_level := int(SettlementRules.effect_max(data, settlement, "wall_level"))
	if settlement["siege"] != null and settlement["siege"].get("gates_open", false):
		wall_level = 0
	var walls: Array = battle_rules["wall_defense_multiplier"]
	strength *= float(walls[mini(wall_level, walls.size() - 1)])
	strength *= float(battle_rules["terrain_defense_multiplier"].get(data.regions[region_id]["terrain"], 1.0))
	return strength


static func needed_ratio(brain: Dictionary, base: float) -> float:
	## The strength edge this personality wants before it fights: cautious
	## houses demand more, aggressive ones less, higher difficulties less still.
	var rules: Dictionary = brain["rules"]
	var ratio := base * (1.0 + (weight(brain, "caution") - 0.5) * float(rules["caution_ratio_weight"]))
	ratio /= 1.0 + (weight(brain, "aggression") - 0.5) * float(rules["aggression_ratio_weight"])
	ratio /= maxf(float(brain["aggression_multiplier"]), 0.1)
	return maxf(ratio, float(rules["needed_ratio_floor"]))


static func reserve_for(brain: Dictionary, settlement_count: int) -> int:
	## Gold kept back from every purchase; the greedy keep less.
	var rules: Dictionary = brain["rules"]
	var reserve := float(rules["treasury_reserve"]) + float(rules["reserve_per_settlement"]) * float(settlement_count)
	return int(round(reserve * (float(rules["reserve_greed_offset"]) - weight(brain, "greed"))))


static func enemies_of(data: GameData, state: Dictionary, faction_id: String) -> Array:
	## Living non-rebel factions we are at war with, sorted.
	var result: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other in faction_ids:
		if other == faction_id or not state["factions"][other]["alive"]:
			continue
		if data.factions.get(other, {}).get("is_rebel", false):
			continue
		if DiplomacyRules.at_war(state, faction_id, other):
			result.append(other)
	return result


static func hops_to_lands(data: GameData, state: Dictionary, faction_id: String, region_id: String) -> int:
	## Land hops from a region to the nearest settlement of the faction; -1 if none.
	var hops := MapRules.hops_from(data, region_id)
	var best := -1
	for owned in settlements_of(state, faction_id):
		var distance := int(hops.get(owned, -1))
		if distance >= 0 and (best < 0 or distance < best):
			best = distance
	return best


static func nearest_own_settlement(data: GameData, state: Dictionary, faction_id: String, from_region: String) -> String:
	var hops := MapRules.hops_from(data, from_region)
	var best := ""
	var best_distance := 1 << 30
	for owned in settlements_of(state, faction_id):
		var distance := int(hops.get(owned, -1))
		if distance >= 0 and distance < best_distance:
			best = owned
			best_distance = distance
	return best
