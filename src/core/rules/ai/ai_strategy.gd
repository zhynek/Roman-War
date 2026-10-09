class_name AiStrategy
## Force estimation for the campaign AI, the diplomacy layer and the knowledge
## layer: what a stack, a garrison or a whole faction is worth in a fight.
## Deterministic pure sums, no rng. AI targets are chosen by AiAssess; the
## unused persistent-objective planner was removed in the 2026-10 cleanup
## (recoverable from git history before that commit).


static func force_strength(data: GameData, units: Array) -> float:
	## Paper strength of a unit list: quality × soldiers × condition, with the
	## battle experience chevron bonus and the weapons/armor stamp counted the
	## way the resolver does — an AI that ignored arming would misjudge every
	## upgraded enemy.
	var ai_rules: Dictionary = data.balance["ai"]
	var chevron_pct := float(data.balance["battle"]["experience_strength_pct_per_chevron"])
	var weapon_pct := float(data.balance["battle"].get("weapon_upgrade_attack_pct", 0.0))
	var armor_pct := float(data.balance["battle"].get("armor_upgrade_defense_pct", 0.0))
	var total := 0.0
	for unit in units:
		var template: Dictionary = data.units.get(unit["template"], {})
		var weapon_bonus := 1.0 + float(unit.get("weapon", 0)) * weapon_pct / 100.0
		var armor_bonus := 1.0 + float(unit.get("armor", 0)) * armor_pct / 100.0
		var quality := float(template.get("attack", 0)) * weapon_bonus * float(ai_rules["strength_attack_weight"]) \
			+ float(template.get("defense", 0)) * armor_bonus * float(ai_rules["strength_defense_weight"]) \
			+ float(template.get("morale", 0)) * float(ai_rules["strength_morale_weight"])
		var condition := float(unit.get("strength_pct", 100)) / 100.0
		var experience := 1.0 + float(unit.get("experience", 0)) * chevron_pct / 100.0
		total += quality * float(template.get("soldiers", 0)) * condition * experience
	return total


static func settlement_defense(data: GameData, state: Dictionary, region_id: String) -> float:
	## Garrison strength behind its walls, plus any of the owner's field armies
	## standing in the region — what an attacker must expect to beat.
	## (A pure sum — iteration order cannot matter, so no sort is needed.)
	var settlement: Dictionary = state["settlements"][region_id]
	var wall_multipliers: Array = data.balance["battle"]["wall_defense_multiplier"]
	# Counting the defender's wallcraft technique keeps the AI's estimate
	# honest against rampart-holding cities (mirrors SiegeRules.assault).
	var wall_level := mini(int(SettlementRules.effect_max(data, settlement, "wall_level"))
		+ int(KnowledgeRules.faction_effect_total(data, state, settlement["owner"], "wall_level_bonus")),
		wall_multipliers.size() - 1)
	var defense := force_strength(data, settlement["garrison"]) * float(wall_multipliers[wall_level])
	for army in state["armies"].values():
		if army["region"] == region_id and army["owner"] == settlement["owner"]:
			defense += force_strength(data, army["units"])
	return defense


static func faction_field_strength(data: GameData, state: Dictionary, faction_id: String) -> float:
	## Total army strength (field only — garrisons defend, they do not project).
	## Pure sum: order-free, no sort.
	var total := 0.0
	for army in state["armies"].values():
		if army["owner"] == faction_id:
			total += force_strength(data, army["units"])
	return total


static func faction_total_strength(data: GameData, state: Dictionary, faction_id: String) -> float:
	## Field armies plus garrisons — the weight a faction throws on the scales
	## of diplomacy, where a wall of spears counts even if it never marches.
	## Pure sum: order-free, no sort.
	var total := faction_field_strength(data, state, faction_id)
	for settlement in state["settlements"].values():
		if settlement["owner"] == faction_id:
			total += force_strength(data, settlement["garrison"])
	return total


static func all_faction_strengths(data: GameData, state: Dictionary) -> Dictionary:
	## Every faction's total strength in ONE pass over the world — the per-turn
	## cache the diplomacy layer hands to attitude_total, which would otherwise
	## recompute strengths per faction pair.
	var strengths := {}
	for faction_id in state["factions"]:
		strengths[faction_id] = 0.0
	for army in state["armies"].values():
		strengths[army["owner"]] = float(strengths.get(army["owner"], 0.0)) \
			+ force_strength(data, army["units"])
	for settlement in state["settlements"].values():
		strengths[settlement["owner"]] = float(strengths.get(settlement["owner"], 0.0)) \
			+ force_strength(data, settlement["garrison"])
	return strengths
