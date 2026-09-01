class_name AiPolicy
## The court's statecraft step: which craft the house takes up next.
##
## Score = persona group priority x need boost (war or reform pressure favors
## the arsenal, unrest favors civic works) / adoption cost — cheap useful
## crafts first, dear prestige later, one programme at a time.
##
## This module also chose the house's edicts on the branch it came from. main
## holds edicts PER PROVINCE under a different engine, so that half is gone;
## without this half the knowledge layer would be inert for every AI court,
## which is what dropping the module whole cost until this was restored.


static func run(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary) -> void:
	# One prerequisite-cache build serves both steps (it is the step's main
	# cost); a court below its reserve skips everything.
	if int(state["factions"][faction_id]["treasury"]) <= int(data.balance["ai"]["treasury_reserve"]):
		return
	var caches := KnowledgeRules.build_caches(data, state, false)
	_consider_adoption(data, state, faction_id, persona, caches)


static func _consider_adoption(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, caches: Dictionary) -> void:
	## Score = persona group priority × need boost (war or reform pressure
	## favors the arsenal, unrest favors civic works) ÷ adoption cost — cheap
	## useful crafts first, dear prestige later. One program at a time.
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
	aware.sort()

	var priorities: Dictionary = persona.get("knowledge_priorities", {})
	var at_war := _at_war_with_anyone(state, faction_id)
	var pressed := KnowledgeRules.pressure_ratio(data, faction) > 0.0
	# A court in measured deficit funds no new programs — UNLESS reform
	# pressure is on it: crisis rearmament is the whole point of the corvus
	# law, and Rome built her fleet while losing the war that paid for it.
	if float(faction["ai"].get("last_net", 0.0)) <= 0.0 and not pressed:
		return
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
