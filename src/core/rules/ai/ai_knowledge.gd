class_name AiKnowledge
## The AI's statecraft of knowledge, run after AiEconomy: each turn a court
## weighs the crafts it knows of and, when the purse allows, begins
## institutionalizing the best-scored one. Score = persona group priority ×
## need boost (war or reform pressure favors the arsenal, unrest favors civic
## works) ÷ adoption cost — cheap useful crafts first, dear prestige later.
## Fully deterministic: sorted iteration, no rng draws. Rebels never run this
## (AiRules routes them to economy only). All knobs: balance.json → ai.


static func run(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary) -> void:
	var faction: Dictionary = state["factions"][faction_id]
	var knowledge: Dictionary = faction.get("knowledge", {})
	var aware: Array = []
	for tid in knowledge:  # pure scan — order-free
		var stage = knowledge[tid].get("stage")
		if stage == "adopting":
			return  # hands full: one program at a time (the engine's gate too)
		if stage == "aware":
			aware.append(tid)
	if aware.is_empty():
		return
	var ai_rules: Dictionary = data.balance["ai"]
	if int(faction["treasury"]) <= int(ai_rules["treasury_reserve"]):
		return  # nothing is affordable; spare the cache build
	aware.sort()

	var priorities: Dictionary = persona.get("knowledge_priorities", {})
	var caches := KnowledgeRules.build_caches(data, state, false)
	var at_war := _at_war_with_anyone(state, faction_id)
	var pressed := KnowledgeRules.pressure_ratio(data, faction) > 0.0
	# AiEconomy already swept public order this turn; its minimum is the
	# civic-need signal (no second breakdown sweep).
	var order_need: bool = float(faction["ai"].get("min_order", 200.0)) \
		< float(ai_rules["order_need_threshold"])

	var best_tid := ""
	var best_score := 0.0
	for tid in aware:
		var technique: Dictionary = data.techniques.get(tid, {})
		if technique.is_empty():
			continue
		if not KnowledgeRules.prerequisites_met(data, state, caches, faction_id, technique):
			continue
		var cost := KnowledgeRules.adoption_cost(data, state, faction_id, tid)
		if int(faction["treasury"]) - cost < int(ai_rules["treasury_reserve"]):
			continue
		var group: String = KnowledgeRules.DOMAIN_GROUPS.get(String(technique["domain"]), "civic")
		var score := float(priorities.get(group, 1.0))
		if group == "military" and (at_war or pressed):
			score *= float(ai_rules["knowledge_war_boost"])
		elif group == "civic" and order_need:
			score *= float(ai_rules["knowledge_order_boost"])
		score = score * 1000.0 / maxf(float(cost), 1.0)
		if best_tid == "" or score > best_score:
			best_tid = tid
			best_score = score
	if best_tid != "":
		KnowledgeRules.begin_adoption(data, state, faction_id, best_tid, caches)


static func _at_war_with_anyone(state: Dictionary, faction_id: String) -> bool:
	var stances: Dictionary = state["factions"][faction_id]["diplomacy"]
	for other in stances:  # pure any-check — order-free
		if other != "rebels" and stances[other] == "war" \
				and state["factions"].get(other, {}).get("alive", false):
			return true
	return false
