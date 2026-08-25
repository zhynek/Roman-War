class_name AiEconomy
## Settlement management for non-player factions: keep garrisons at the floor,
## build by need, nudge taxes toward stability, retrain when rich. Fully
## deterministic — weighted scoring with sorted tie-breaks, no rng draws.

## The AI's own taxonomy over building kinds (structural vocabulary, like
## Constants.BUILDING_KINDS); the per-group weights are persona content.
const KIND_GROUPS := {
	"government": "order", "temple": "order", "entertainment": "order", "execution": "order",
	"farms": "growth", "health": "growth",
	"education": "order",
	"market": "income", "port": "income", "roads": "income", "mines": "income",
	"barracks": "military", "stables": "military", "archery_range": "military",
	"siege_workshop": "military", "naval": "military",
	"walls": "walls",
}


static func run(data: GameData, state: Dictionary, faction_id: String, persona: Dictionary, muster_region: String = "") -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	# Public order per settlement is computed ONCE here and passed down —
	# construction scoring and tax policy read the same number, and the
	# faction-wide minimum lands in the ai scratch dict for AiKnowledge's
	# civic-need signal (so it never re-runs the breakdown sweep).
	var min_order := 200.0
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] != faction_id:
			continue
		var frontier := is_frontier(data, state, faction_id, region_id)
		_manage_garrison(data, state, faction_id, region_id, persona, frontier, muster_region)
		# After garrison queueing (which draws population), exactly where the
		# construction pass used to compute it — the dedupe changes no decision.
		var order := PublicOrderRules.total(data, state, region_id)
		# Freshly conquered cities are ALWAYS low — they would pin the
		# civic-need signal on permanently for any expanding court, so the
		# minimum tracks settled lands only.
		if int(settlement["recently_conquered"]) == 0:
			min_order = minf(min_order, order)
		_manage_construction(data, state, faction_id, region_id, persona, frontier, muster_region, order)
		_manage_taxes(data, state, region_id, order)
		if int(state["factions"][faction_id]["treasury"]) \
				> int(ai_rules["treasury_reserve"]) + int(ai_rules["retrain_treasury_margin"]):
			RecruitmentRules.retrain_garrison(data, state, region_id)
	state["factions"][faction_id]["ai"]["min_order"] = min_order


static func is_frontier(data: GameData, state: Dictionary, faction_id: String, region_id: String) -> bool:
	## A settlement is frontier when any neighbor is held by someone other than
	## the owner or an ally — those borders get bigger garrisons and walls.
	for neighbor in data.regions[region_id].get("adjacent", []):
		if not state["settlements"].has(neighbor):
			continue
		var owner: String = state["settlements"][neighbor]["owner"]
		if owner == faction_id:
			continue
		if DiplomacyRules.stance_between(state, faction_id, owner) != "alliance":
			return true
	return false


static func unit_value(data: GameData, template: Dictionary) -> float:
	## Fighting quality bought per denarius, amortizing upkeep over a horizon so
	## the AI does not fill its cities with the cheapest possible mob.
	var ai_rules: Dictionary = data.balance["ai"]
	var quality := float(template.get("attack", 0)) * float(ai_rules["strength_attack_weight"]) \
		+ float(template.get("defense", 0)) * float(ai_rules["strength_defense_weight"]) \
		+ float(template.get("morale", 0)) * float(ai_rules["strength_morale_weight"])
	var lifetime_cost := float(template.get("cost", 1)) \
		+ float(template.get("upkeep", 0)) * float(ai_rules["unit_value_upkeep_horizon_turns"])
	return quality * float(template.get("soldiers", 0)) / maxf(lifetime_cost, 1.0)


static func _manage_garrison(data: GameData, state: Dictionary, faction_id: String, region_id: String, persona: Dictionary, frontier: bool, muster_region: String) -> void:
	var settlement: Dictionary = state["settlements"][region_id]
	var faction: Dictionary = state["factions"][faction_id]
	var ai_rules: Dictionary = data.balance["ai"]
	var floor_units := int(persona.get("garrison_frontier_units", 4)) if frontier \
		else int(persona.get("garrison_min_units", 2))
	if region_id == muster_region:
		# The muster settlement over-recruits; the military module raises the
		# surplus into field armies.
		floor_units += int(ai_rules["muster_surplus_units"]) + int(persona.get("army_size_target", 8))
	var count: int = settlement["garrison"].size() + settlement["recruitment_queue"].size()
	if count >= floor_units:
		return
	var best := {}
	var best_value := 0.0
	var candidates := RecruitmentRules.available_units(data, state, region_id)
	candidates.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	for template in candidates:
		var value := unit_value(data, template)
		if best.is_empty() or value > best_value:
			best = template
			best_value = value
	if best.is_empty():
		return
	while count < floor_units:
		if int(faction["treasury"]) - int(best["cost"]) < int(ai_rules["treasury_reserve"]):
			return
		if not RecruitmentRules.queue_unit(data, state, region_id, best["id"]):
			return
		count += 1


static func _manage_construction(data: GameData, state: Dictionary, faction_id: String, region_id: String, persona: Dictionary, frontier: bool, muster_region: String, order: float) -> void:
	var settlement: Dictionary = state["settlements"][region_id]
	if not settlement["construction_queue"].is_empty():
		return
	var ai_rules: Dictionary = data.balance["ai"]
	var weights: Dictionary = persona.get("build_weights", {})
	var growth := GrowthRules.total_pct(data, state, region_id)

	var candidates := ConstructionRules.available_projects(data, state, region_id)
	candidates.sort_custom(func(a, b): return String(a["chain"]) < String(b["chain"]))
	var best := {}
	var best_score := 0.0
	for project in candidates:
		var group: String = KIND_GROUPS.get(project["kind"], "income")
		var score := float(weights.get(group, 1.0))
		if group == "order" and order < float(ai_rules["order_need_threshold"]):
			# Order needs outrank growth needs by constant design: an unhappy
			# city riots long before a slow-growing one stalls.
			score *= float(ai_rules["order_need_boost"])
		elif group == "growth" and growth < float(ai_rules["growth_need_threshold"]):
			score *= float(ai_rules["growth_need_boost"])
		elif group == "walls" and frontier:
			score *= float(ai_rules["walls_frontier_boost"])
		elif group == "military" and (frontier or region_id == muster_region):
			score *= float(ai_rules["military_muster_boost"])
		if best.is_empty() or score > best_score:
			best = project
			best_score = score
	if best.is_empty():
		return
	# Save toward the right building rather than buying whatever is affordable.
	var faction: Dictionary = state["factions"][faction_id]
	if int(faction["treasury"]) - int(best["cost"]) < int(ai_rules["treasury_reserve"]):
		return
	ConstructionRules.queue_project(data, state, region_id, best["chain"])


static func _manage_taxes(data: GameData, state: Dictionary, region_id: String, order: float) -> void:
	var settlement: Dictionary = state["settlements"][region_id]
	var ai_rules: Dictionary = data.balance["ai"]
	var index := Constants.TAX_LEVELS.find(String(settlement["tax_level"]))
	if index < 0:
		return
	if order < float(ai_rules["tax_lower_below_order"]) and index > 0:
		settlement["tax_level"] = Constants.TAX_LEVELS[index - 1]
	elif order > float(ai_rules["tax_raise_above_order"]) and index < Constants.TAX_LEVELS.size() - 1:
		settlement["tax_level"] = Constants.TAX_LEVELS[index + 1]
