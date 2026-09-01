class_name AiRules
## The AI's temperament, and nothing else.
##
## This module used to orchestrate a whole faction turn. main drives turns with
## FactionAi instead (see the AI determination in DESIGN §6), but the persona
## table it introduced is the better idea and survives here: temperament comes
## from data/ai.json (factions.json ai_persona, falling back to "default"),
## which is what the diplomacy and negotiation layers read to decide how
## aggressive or trusting a house is. Content in data, not in GDScript.
##
## The orchestration that lived here (Phase 6). Runs at
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
## falling back to "default"); every numeric knob lives in balance.json → ai
## and → diplomacy. Order within a faction's turn: diplomacy → strategy →
## military → economy, so a fresh war shapes this turn's objective, armies act
## on that objective, and the settlements spend whatever the war effort left.
## Rebels run the economy module only — their armies stand as threats, never
## campaign.


static func persona_for(data: GameData, faction_id: String) -> Dictionary:
	var persona_id: String = data.factions.get(faction_id, {}).get("ai_persona", "default")
	return data.ai_personas.get(persona_id, data.ai_personas.get("default", {}))
