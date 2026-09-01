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
## The AI is deliberately omniscient: it reads true state, not VisibilityRules.
## Determinism is identical either way, fog-respecting target selection makes
## factions wander with no player-visible benefit, and difficulty stays
## "richer, never smarter" (income and order bonuses, not information).
##
## Every numeric knob lives in balance.json -> ai and -> diplomacy. The turn
## itself is ordered by FactionAi.take_turn, not here.


static func persona_for(data: GameData, faction_id: String) -> Dictionary:
	var persona_id: String = data.factions.get(faction_id, {}).get("ai_persona", "default")
	return data.ai_personas.get(persona_id, data.ai_personas.get("default", {}))
