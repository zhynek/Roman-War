class_name AiPolicy
## The AI's statecraft step, run after AiEconomy: one deterministic "spend
## the surplus on the state itself" pass per turn — first the crafts the
## court knows of (technique adoption), then the book of policies (edict
## enactment). Sorted iteration, no rng draws; rebels never run this
## (AiRules routes them to economy only). All knobs: balance.json → ai and
## → edicts; temperament comes from the persona's knowledge_priorities and
## edict_priorities.
##
## The AI never manually repeals in v1 — the engine's insolvency rule prunes
## an overreaching book on its own, which is the historically honest failure.


static func run(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, events: Array) -> void:
	# One prerequisite-cache build serves both steps (it is the step's main
	# cost); a court below its reserve skips everything.
	if int(state["factions"][faction_id]["treasury"]) <= int(data.balance["ai"]["treasury_reserve"]):
		return
	var caches := KnowledgeRules.build_caches(data, state, false)
	_consider_adoption(data, state, faction_id, persona, caches)
	_consider_edict(data, state, faction_id, persona, events, caches)


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


static func _consider_edict(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, events: Array, caches: Dictionary) -> void:
	## At most one enactment per turn, capped by an upkeep share of last
	## turn's income so the book never outruns the purse — the insolvency
	## rule is the backstop, not the plan. Decrees are emergency levers:
	## weighed only when order is actually failing.
	var faction: Dictionary = state["factions"][faction_id]
	var ai_rules: Dictionary = data.balance["ai"]
	var edict_rules: Dictionary = data.balance["edicts"]
	var last_income := float(faction["ai"].get("last_income", 0.0))
	if last_income <= 0.0:
		return  # no measured income yet (first turn, or ruin) — hold
	if float(faction["ai"].get("last_net", 0.0)) <= 0.0:
		# A measured deficit means the wage bill already outruns the take:
		# enacting into it is the enact→collapse→re-enact spiral. Hold.
		return
	var upkeep_budget := last_income * float(edict_rules["ai_upkeep_income_share"])
	var current_upkeep := float(EdictRules.upkeep(data, state, faction_id))
	var population := 0
	for settlement in state["settlements"].values():  # pure sum
		if settlement["owner"] == faction_id:
			population += int(settlement["population"])

	var priorities: Dictionary = persona.get("edict_priorities", {})
	var at_war := _at_war_with_anyone(state, faction_id)
	var order_need: bool = float(faction["ai"].get("min_order", 200.0)) \
		< float(ai_rules["order_need_threshold"])

	var best_eid := ""
	var best_score := 0.0
	for entry in EdictRules.available(data, state, faction_id, caches):
		if String(entry["reason"]) != "":
			continue
		var edict: Dictionary = entry["edict"]
		if String(edict["kind"]) == "decree" and not order_need:
			continue  # games are for crises, not calm treasuries
		var cost := int(entry["cost"])
		if int(faction["treasury"]) - cost < int(ai_rules["treasury_reserve"]):
			continue
		var added_upkeep := float(edict.get("upkeep_per_turn", 0)) \
			+ float(edict.get("upkeep_per_1000_pop", 0.0)) * population / 1000.0
		if current_upkeep + added_upkeep > upkeep_budget:
			continue
		var score := float(priorities.get(String(edict["category"]), 1.0))
		if String(edict["category"]) == "military" and at_war:
			score *= float(ai_rules["knowledge_war_boost"])
		elif String(edict["category"]) in ["welfare", "religion", "citizenship"] and order_need:
			score *= float(ai_rules["knowledge_order_boost"])
		# Value per denarius over the holding horizon, not cheapness alone:
		# what the edict DOES (its effect magnitudes) against enact cost plus
		# upkeep carried for the standard horizon — so the dole, the census
		# and the colonies compete with the cheap flat acts.
		score = score * (1.0 + _effect_weight(edict)) * 100.0 \
			/ (float(cost) + added_upkeep * float(ai_rules["unit_value_upkeep_horizon_turns"]))
		if best_eid == "" or score > best_score:
			best_eid = String(entry["id"])
			best_score = score
	if best_eid != "":
		var verdict := EdictRules.enact(data, state, faction_id, best_eid, caches)
		if bool(verdict["ok"]):
			events.append({"kind": "edict_enacted", "faction": faction_id, "edict": best_eid})


static func _effect_weight(edict: Dictionary) -> float:
	## Crude magnitude sum across the edict's effects (decree moods included)
	## — units differ, but it separates substantial policy from token acts.
	var total := 0.0
	for key in edict.get("effects", {}):  # pure sum
		total += absf(float(edict["effects"][key]))
	total += absf(float(edict.get("timed_happiness", {}).get("value", 0.0)))
	return total


static func _at_war_with_anyone(state: Dictionary, faction_id: String) -> bool:
	var stances: Dictionary = state["factions"][faction_id]["diplomacy"]
	for other in stances:  # pure any-check — order-free
		if other != "rebels" and stances[other] == "war" \
				and state["factions"].get(other, {}).get("alive", false):
			return true
	return false
