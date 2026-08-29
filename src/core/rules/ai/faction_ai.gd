class_name FactionAi
## Phase 6: one non-player faction's full turn, replacing the passive AiStub.
## Modular behaviors, all deterministic and tuned from data/balance.json "ai":
##
##   AiDiplomacy — deliberate war declarations, white peace for stalled AI wars
##   AiAssess    — power estimates, reachability, threat levels, target choice
##   AiMilitary  — sieges, defence, field battles, marching, mustering
##   AiEconomy   — capital, taxes, retraining, recruitment, construction
##
## Difficulty never makes the AI smarter — it stays the documented income
## multiplier and order bonus (EconomyRules / PublicOrderRules); a richer AI
## simply fields more of the same decisions. Rebels run defence and settlement
## upkeep only: they never expand, declare war, or make peace.
##
## Determinism contract: every loop iterates in sorted order, no randomness is
## drawn outside battle resolution, and all persistent memory lives in the
## state.ai ledger — war_turns (war staleness), targets (each faction's
## campaign goal), peace_turn (when pairs last made peace, for the
## re-declaration cooldown) — a plain JSON dict, so saves round-trip.


static func begin_round(data: GameData, state: Dictionary) -> void:
	## Once per world turn, before any faction acts.
	AiDiplomacy.tick_wars(data, state)


static func take_turn(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng, resolver: BattleResolver, ai_notices: Array, character_notices: Array) -> void:
	var faction: Dictionary = state["factions"][faction_id]
	if not faction["alive"]:
		return
	var is_rebel: bool = data.factions.get(faction_id, {}).get("is_rebel", false)
	var context := {
		"is_rebel": is_rebel,
		"target": "",
		"goal_costs": {},
		"staging": "",
		"wants_muster": false,
	}

	if not is_rebel:
		AiEconomy.fix_capital(data, state, faction_id)
		AiDiplomacy.consider_peace(data, state, faction_id, ai_notices)
		context["target"] = AiAssess.choose_target(data, state, faction_id)
		if context["target"] == "" and AiDiplomacy.consider_war(data, state, faction_id, ai_notices):
			context["target"] = AiAssess.choose_target(data, state, faction_id)
		# The ledger remembers what this house is campaigning for, so a war
		# being mustered for counts as prosecuted, not stalled.
		var targets: Dictionary = AiDiplomacy.ai_memory(state)["targets"]
		if context["target"] == "":
			targets.erase(faction_id)
		else:
			targets[faction_id] = context["target"]
			context["goal_costs"] = AiAssess.distance_map(data, state, faction_id, [context["target"]])
			context["staging"] = _staging_for(state, faction_id, context["goal_costs"])

	AiMilitary.take_turn(data, state, faction_id, context, rng, resolver, ai_notices, character_notices)
	AiEconomy.take_turn(data, state, faction_id, context)


static func _staging_for(state: Dictionary, faction_id: String, goal_costs: Dictionary) -> String:
	## The owned settlement nearest the target: recruits gather there and new
	## field armies raise there.
	var best := ""
	var best_cost := 1 << 30
	for region_id in AiAssess.owned_regions(state, faction_id):
		var cost := int(goal_costs.get(region_id, 1 << 30))
		if cost < best_cost:
			best = region_id
			best_cost = cost
	return best
