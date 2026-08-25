class_name AiRules
## Orchestrates one non-player faction's campaign turn (Phase 6). Runs at
## TurnEngine step 1 with the turn's live rng and resolver threaded in — inside
## end_turn the AI must call rules modules directly with that rng, never the
## Game facade (Game._rng() rebuilds from state["rng_state"], which is stale
## until end_turn writes it back, and a second stream breaks save determinism).
##
## The AI is deliberately omniscient: it reads true state, not VisibilityRules.
## Determinism is identical either way, fog-respecting target selection makes
## factions wander with no player-visible benefit, and difficulty stays
## "richer, never smarter" (income and order bonuses, not information). This is
## a revisitable decision, isolated behind this module.
##
## Temperament comes from data/ai.json personas (factions.json ai_persona,
## falling back to "default"); every numeric knob lives in balance.json → ai.
## Order within a faction's turn: strategy → military → economy, so armies act
## on this turn's objective and the treasury the military left is what the
## settlements spend. Rebels run the economy module only — their armies stand
## as threats, never campaign.


static func take_turn(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, faction_id: String) -> Array:
	var events: Array = []
	var faction: Dictionary = state["factions"][faction_id]
	if not faction["alive"]:
		return events
	if not faction.has("ai"):
		faction["ai"] = {}
	var persona := persona_for(data, faction_id)
	if data.factions.get(faction_id, {}).get("is_rebel", false):
		AiEconomy.run(data, state, faction_id, persona)
		return events

	AiStrategy.refresh_objective(data, state, faction_id, persona)
	AiMilitary.run(data, state, rng, resolver, faction_id, persona, events)
	AiEconomy.run(data, state, faction_id, persona, AiStrategy.muster_region(state, faction_id))
	return events


static func persona_for(data: GameData, faction_id: String) -> Dictionary:
	var persona_id: String = data.factions.get(faction_id, {}).get("ai_persona", "default")
	return data.ai_personas.get(persona_id, data.ai_personas.get("default", {}))
