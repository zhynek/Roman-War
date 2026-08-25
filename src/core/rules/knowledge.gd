class_name KnowledgeRules
## Techniques — how knowledge moved in the ancient world (Phase 6).
##
## A technique is a real craft of the age (data/techniques.json, each entry
## carrying its historical_basis). The model follows how ancient innovation
## actually worked, not a research counter:
##
##   AWARE     the court knows the craft exists — free, gained by origination,
##             diffusion along contact, conquest, or espionage.
##   ADOPTING  the state is institutionalizing it — paid up front, takes turns,
##             one program at a time (max_concurrent_adoptions).
##   ADOPTED   practiced; its effects apply faction-wide via
##             faction_effect_total — the codebase's fourth effect accessor,
##             beside SettlementRules.effect_total / effect_max /
##             faction_owns_wonder_effect.
##
## Defeats accumulate reform_pressure, which discounts military-group adoption
## and quickens origination: Rome built the boarding bridge because she was
## losing at sea. Conquest transfers awareness of everything the fallen city's
## owner practiced (the Senate kept nothing of Carthage but Mago's books).
##
## Knowledge lives in state.factions[fid].knowledge as
##   {tid: {stage, turn, progress, discount_pct}}
## plus factions[fid].reform_pressure. All tunables: balance.json → knowledge.
## Rebels have no court: they neither originate, adopt, trade knowledge, nor
## feel reform pressure.

## Domain groups mirror the AI build-weight KIND_GROUPS shape; the reform
## discount applies to the "military" group, and personas weight the groups
## (K4). A domain missing here would silently fall outside every group, so
## keep this in step with the schema's domain enum.
const DOMAIN_GROUPS := {
	"military_engineering": "military",
	"naval": "military",
	"metallurgy_craft": "military",
	"agrarian": "economic",
	"logistics_trade": "economic",
	"hydraulic_civic": "civic",
	"medicine": "civic",
	"scholarship_statecraft": "civic",
}


static func knowledge_of(state: Dictionary, faction_id: String) -> Dictionary:
	## The faction's knowledge dict, created on first touch so writes never
	## land in a temporary (pre-knowledge saves lack the key until load
	## normalization runs).
	var faction: Dictionary = state["factions"][faction_id]
	if not faction.has("knowledge"):
		faction["knowledge"] = {}
	return faction["knowledge"]


static func build_caches(data: GameData, state: Dictionary) -> Dictionary:
	## ONE pass over settlements answering every prerequisite and contact
	## question for the turn (the AiStrategy.all_faction_strengths precedent):
	## per-faction best building level by kind, resources, hidden resources and
	## coastal access from owned regions, plus the set of faction pairs whose
	## lands touch ("a|b" keys with a < b).
	var kind_levels := {}
	var resources := {}
	var hidden := {}
	var coastal := {}
	var border_pairs := {}
	for region_id in state["settlements"]:  # pure aggregation — order-free
		var settlement: Dictionary = state["settlements"][region_id]
		var owner: String = settlement["owner"]
		if not kind_levels.has(owner):
			kind_levels[owner] = {}
			resources[owner] = {}
			hidden[owner] = {}
			coastal[owner] = false
		var owner_kinds: Dictionary = kind_levels[owner]
		for chain_id in settlement["buildings"]:
			var chain: Dictionary = data.chains.get(chain_id, {})
			if chain.is_empty():
				continue
			var tier := mini(int(settlement["buildings"][chain_id]), chain["levels"].size())
			var kind: String = chain["kind"]
			owner_kinds[kind] = maxi(int(owner_kinds.get(kind, 0)), tier)
		var region: Dictionary = data.regions.get(region_id, {})
		for resource in region.get("resources", []):
			resources[owner][resource] = true
		for resource in region.get("hidden_resources", []):
			hidden[owner][resource] = true
		if not region.get("sea_zones", []).is_empty():
			coastal[owner] = true
		for neighbor in region.get("adjacent", []):
			var other: Dictionary = state["settlements"].get(neighbor, {})
			if other.is_empty() or other["owner"] == owner:
				continue
			var pair: Array = [owner, other["owner"]]
			pair.sort()
			border_pairs["%s|%s" % [pair[0], pair[1]]] = true
	return {
		"kind_levels": kind_levels, "resources": resources, "hidden": hidden,
		"coastal": coastal, "border_pairs": border_pairs,
	}


static func prerequisites_met(data: GameData, state: Dictionary, caches: Dictionary, faction_id: String, technique: Dictionary) -> bool:
	## Awareness is free of prerequisites — you can hear of the watermill
	## without owning a millstream. These gate ORIGINATION and ADOPTION.
	var prereq: Dictionary = technique["prerequisites"]
	var kind := String(prereq["building_kind"])
	if kind != "" and int(caches["kind_levels"].get(faction_id, {}).get(kind, 0)) < int(prereq["building_level"]):
		return false
	var resource := String(prereq["resource"])
	if resource != "" and not caches["resources"].get(faction_id, {}).has(resource):
		return false
	var hidden := String(prereq["hidden_resource"])
	if hidden != "" and not caches["hidden"].get(faction_id, {}).has(hidden):
		return false
	if bool(prereq["coastal"]) and not bool(caches["coastal"].get(faction_id, false)):
		return false
	var knowledge: Dictionary = state["factions"][faction_id].get("knowledge", {})
	for needed in prereq["techniques"]:
		if String(knowledge.get(needed, {}).get("stage", "")) != "adopted":
			return false
	return true


static func faction_effect_total(data: GameData, state: Dictionary, faction_id: String, effect: String) -> float:
	## Sum an effect key across the faction's ADOPTED techniques only —
	## awareness and half-built programs grant nothing.
	var total := 0.0
	var knowledge: Dictionary = state["factions"].get(faction_id, {}).get("knowledge", {})
	for tid in knowledge:  # pure sum — iteration order cannot steer anything
		if String(knowledge[tid].get("stage", "")) != "adopted":
			continue
		total += float(data.techniques.get(tid, {}).get("effects", {}).get(effect, 0.0))
	return total


static func adoption_cost(data: GameData, state: Dictionary, faction_id: String, technique_id: String) -> int:
	## base cost × culture resistance × (1 − conquest/espionage discount)
	## × the reform discount on military-group crafts. Exposed so the UI can
	## price the decision before it is made.
	var technique: Dictionary = data.techniques.get(technique_id, {})
	if technique.is_empty():
		return 0
	var rules: Dictionary = data.balance["knowledge"]
	var cost := float(technique["adoption"]["cost"])
	cost *= float(technique.get("culture_resistance", {}).get(data.culture_of_faction(faction_id), 1.0))
	var entry: Dictionary = state["factions"][faction_id].get("knowledge", {}).get(technique_id, {})
	cost *= 1.0 - float(entry.get("discount_pct", 0.0)) / 100.0
	if DOMAIN_GROUPS.get(String(technique["domain"]), "") == "military":
		cost *= 1.0 - float(rules["reform_military_discount_pct_at_max"]) / 100.0 \
			* _pressure_ratio(data, state["factions"][faction_id])
	return int(ceil(maxf(cost, 0.0)))


static func begin_adoption(data: GameData, state: Dictionary, faction_id: String, technique_id: String, caches: Dictionary = {}) -> Dictionary:
	## Institutionalize a craft the court is aware of: paid up front, one
	## program at a time. Returns {ok, reason, cost}; no rng.
	var refused := {"ok": false, "reason": "", "cost": 0}
	var technique: Dictionary = data.techniques.get(technique_id, {})
	var faction: Dictionary = state["factions"].get(faction_id, {})
	if technique.is_empty() or faction.is_empty() or not faction.get("alive", false):
		refused["reason"] = "unknown"
		return refused
	var knowledge := knowledge_of(state, faction_id)
	var stage := String(knowledge.get(technique_id, {}).get("stage", ""))
	if stage != "aware":
		refused["reason"] = "not_aware" if stage == "" else "already_" + stage
		return refused
	var adopting := 0
	for tid in knowledge:  # pure count
		if String(knowledge[tid].get("stage", "")) == "adopting":
			adopting += 1
	if adopting >= int(data.balance["knowledge"]["max_concurrent_adoptions"]):
		refused["reason"] = "hands_full"
		return refused
	var effective_caches := caches if not caches.is_empty() else build_caches(data, state)
	if not prerequisites_met(data, state, effective_caches, faction_id, technique):
		refused["reason"] = "prerequisites"
		return refused
	var cost := adoption_cost(data, state, faction_id, technique_id)
	refused["cost"] = cost
	if int(faction["treasury"]) < cost:
		refused["reason"] = "treasury"
		return refused
	faction["treasury"] = int(faction["treasury"]) - cost
	var entry: Dictionary = knowledge[technique_id]
	entry["stage"] = "adopting"
	entry["progress"] = int(technique["adoption"]["turns"])
	entry["turn"] = int(state["turn"])
	return {"ok": true, "reason": "", "cost": cost}


static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	## Once per end_turn, in fixed order: adoption programs tick → origination
	## → diffusion along contact → reform pressure decays. Returns report
	## events ({kind: technique_adopted|technique_originated|technique_spread}).
	var rules: Dictionary = data.balance["knowledge"]
	var events: Array = []
	var caches := build_caches(data, state)
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()

	# 1. Programs in progress tick toward completion.
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction["alive"]:
			continue
		var knowledge := knowledge_of(state, faction_id)
		var tids: Array = knowledge.keys()
		tids.sort()
		for tid in tids:
			var entry: Dictionary = knowledge[tid]
			if String(entry["stage"]) != "adopting":
				continue
			entry["progress"] = int(entry["progress"]) - 1
			if int(entry["progress"]) <= 0:
				entry["stage"] = "adopted"
				entry["progress"] = 0
				entry["turn"] = int(state["turn"])
				events.append({"kind": "technique_adopted", "faction": faction_id, "technique": tid})

	# 2. Origination: a court meeting a craft's prerequisites (and, where the
	# table names origin cultures, born to the right tradition) may devise it —
	# gaining AWARENESS, not adoption; institutionalizing still costs. One rng
	# draw per faction, and only when candidates exist. Education buildings and
	# practiced scholarship raise the odds; reform pressure quickens invention
	# and steers the pick toward the arsenal.
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction["alive"] or faction_id == "rebels":
			continue
		var culture := data.culture_of_faction(faction_id)
		var knowledge := knowledge_of(state, faction_id)
		var candidates: Array = []
		var technique_ids: Array = data.techniques.keys()
		technique_ids.sort()
		for tid in technique_ids:
			if knowledge.has(tid):
				continue
			var technique: Dictionary = data.techniques[tid]
			var origins: Array = technique["origin_cultures"]
			if not origins.is_empty() and not origins.has(culture):
				continue
			if prerequisites_met(data, state, caches, faction_id, technique):
				candidates.append(tid)
		if candidates.is_empty():
			continue
		var pressure_ratio := _pressure_ratio(data, faction)
		var education := int(caches["kind_levels"].get(faction_id, {}).get("education", 0))
		var scholarship := faction_effect_total(data, state, faction_id, "scholarship")
		var chance := (float(rules["origination_base_chance"]) \
				+ education * float(rules["origination_education_bonus_per_level"])) \
			* (1.0 + scholarship * float(rules["origination_scholarship_mult_per_point"])) \
			+ float(rules["reform_origination_bonus_at_max"]) * pressure_ratio
		if not rng.chance(chance):
			continue
		var pick_list: Array = []
		for tid in candidates:
			pick_list.append(tid)
			if pressure_ratio >= 0.5 \
					and DOMAIN_GROUPS.get(String(data.techniques[tid]["domain"]), "") == "military":
				pick_list.append(tid)  # crisis doubles the arsenal's weight
		var chosen: String = rng.pick(pick_list)
		knowledge[chosen] = {"stage": "aware", "turn": int(state["turn"]), "progress": 0, "discount_pct": 0.0}
		events.append({"kind": "technique_originated", "faction": faction_id, "technique": chosen})

	# 3. Diffusion: knowledge moves along contact — allies and trade partners
	# freely, neighbors by proximity, enemies by hard lessons (Rome copied the
	# grounded quinquereme). ONE rng draw per contact pair per turn; on
	# success, one candidate craft (adopted by one side, unheard-of by the
	# other) crosses as awareness. A learned court on either side quickens the
	# exchange. Rebels have no court to trade with.
	for i in range(faction_ids.size()):
		for j in range(i + 1, faction_ids.size()):
			var a: String = faction_ids[i]
			var b: String = faction_ids[j]
			if a == "rebels" or b == "rebels":
				continue
			if not state["factions"][a]["alive"] or not state["factions"][b]["alive"]:
				continue
			var channel := _contact_channel(state, caches, a, b)
			if channel == "":
				continue
			var mult := float(rules["diffusion_%s_mult" % channel])
			if data.culture_of_faction(a) == data.culture_of_faction(b):
				mult *= float(rules["diffusion_same_culture_mult"])
			var scholarship := maxf(faction_effect_total(data, state, a, "scholarship"),
				faction_effect_total(data, state, b, "scholarship"))
			var chance := float(rules["diffusion_base_chance"]) * mult \
				* (1.0 + scholarship * float(rules["diffusion_scholarship_mult_per_point"]))
			if not rng.chance(chance):
				continue
			var candidates: Array = []
			_spread_candidates(state, a, b, candidates)
			_spread_candidates(state, b, a, candidates)
			if candidates.is_empty():
				continue
			var chosen: Dictionary = rng.pick(candidates)
			knowledge_of(state, String(chosen["to"]))[chosen["tid"]] = {
				"stage": "aware", "turn": int(state["turn"]), "progress": 0, "discount_pct": 0.0,
			}
			events.append({"kind": "technique_spread", "faction": chosen["to"],
				"from": chosen["from"], "technique": chosen["tid"], "channel": channel})

	# 4. Reform pressure fades as the defeats recede.
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		var pressure := float(faction.get("reform_pressure", 0.0))
		if pressure > 0.0:
			faction["reform_pressure"] = maxf(0.0, pressure - float(rules["reform_pressure_decay_per_turn"]))

	return events


static func on_battle_lost(data: GameData, state: Dictionary, faction_id: String) -> void:
	## Called from every battle's loser path (field battles and failed
	## assaults). Defeat is the great teacher of military reform.
	_add_pressure(data, state, faction_id, float(data.balance["knowledge"]["reform_pressure_per_battle_loss"]))


static func on_settlement_lost(data: GameData, state: Dictionary, faction_id: String) -> void:
	## Called from CombatRules.capture_settlement for the previous owner —
	## losing a city cuts deeper than losing a battle.
	_add_pressure(data, state, faction_id, float(data.balance["knowledge"]["reform_pressure_per_settlement_lost"]))


static func on_settlement_captured(data: GameData, state: Dictionary, new_owner: String, previous_owner: String) -> void:
	## The victor walks the fallen city's yards and archives: every craft its
	## late owner PRACTICED becomes known to the conqueror, with a conquest
	## discount toward adopting it. Deterministic — no rng. Covers every
	## capture path because CombatRules.capture_settlement is the choke point.
	if new_owner == "rebels" or new_owner == previous_owner:
		return
	if not state["factions"].has(new_owner) or not state["factions"].has(previous_owner):
		return
	var discount := float(data.balance["knowledge"]["conquest_discount_pct"])
	var source: Dictionary = state["factions"][previous_owner].get("knowledge", {})
	var target := knowledge_of(state, new_owner)
	var tids: Array = source.keys()
	tids.sort()
	for tid in tids:
		if String(source[tid].get("stage", "")) != "adopted":
			continue
		var stage := String(target.get(tid, {}).get("stage", ""))
		if stage == "adopted" or stage == "adopting":
			continue
		if stage == "aware":
			var entry: Dictionary = target[tid]
			entry["discount_pct"] = maxf(float(entry.get("discount_pct", 0.0)), discount)
		else:
			target[tid] = {"stage": "aware", "turn": int(state["turn"]), "progress": 0, "discount_pct": discount}


static func _add_pressure(data: GameData, state: Dictionary, faction_id: String, amount: float) -> void:
	if faction_id == "rebels" or not state["factions"].has(faction_id):
		return
	var faction: Dictionary = state["factions"][faction_id]
	var cap := float(data.balance["knowledge"]["reform_pressure_max"])
	faction["reform_pressure"] = clampf(float(faction.get("reform_pressure", 0.0)) + amount, 0.0, cap)


static func _pressure_ratio(data: GameData, faction: Dictionary) -> float:
	var cap := float(data.balance["knowledge"]["reform_pressure_max"])
	if cap <= 0.0:
		return 0.0
	return clampf(float(faction.get("reform_pressure", 0.0)) / cap, 0.0, 1.0)


static func _contact_channel(state: Dictionary, caches: Dictionary, a: String, b: String) -> String:
	## The strongest channel between two courts, by diffusion multiplier:
	## alliance (protectorates included) > trade > shared border > war.
	## "" means no contact — no draw. a < b (callers iterate sorted pairs).
	var stance := String(state["factions"][a]["diplomacy"].get(b, "neutral"))
	if stance == "alliance" or stance == "protectorate":
		return "alliance"
	if stance == "trade":
		return "trade"
	if caches["border_pairs"].has("%s|%s" % [a, b]):
		return "border"
	if stance == "war":
		return "war"
	return ""


static func _spread_candidates(state: Dictionary, from_id: String, to_id: String, out: Array) -> void:
	## Crafts adopted by one court and wholly unknown to the other (already-
	## aware receivers gain nothing from rumor twice). Sorted for determinism —
	## rng.pick indexes into this list.
	var source: Dictionary = state["factions"][from_id].get("knowledge", {})
	var target: Dictionary = state["factions"][to_id].get("knowledge", {})
	var tids: Array = source.keys()
	tids.sort()
	for tid in tids:
		if String(source[tid].get("stage", "")) != "adopted":
			continue
		if target.has(tid):
			continue
		out.append({"to": to_id, "from": from_id, "tid": tid})
