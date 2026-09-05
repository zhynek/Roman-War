class_name BuildingInfo
## Everything the building drawer says about a chain, a tier or a unit, computed
## here so every claim is testable without a scene tree. Scene-free, static-only,
## deterministic: no Node, no RNG, no wall clock.
##
## Three rules this module exists to honour:
##   1. A level's `effects` are the STANDING TOTAL at that tier, not an
##      increment, so "what does upgrading get me" is new - old.
##   2. Four keys reach the sim through SettlementRules.effect_max, not
##      effect_total. Their honest delta is measured against the best OTHER
##      chain in the town, or the drawer promises experience that never arrives.
##      (Weapon and armour upgrades sum across a town's forges and armouries
##      since the military layer — RecruitmentRules.upgrade_level.)
##   3. Lock reasons come from ConstructionRules.blockers_for — the same
##      function available_projects uses — so the drawer cannot disagree with
##      the engine about what may be built.
##
## Wording lives in data/effects_glossary.json. This module returns numbers and
## {kind, params}; it never authors an English sentence.

const MAX_AGGREGATED := ["recruit_xp", "wall_level", "road_level", "port_level"]


static func chain_list(data: GameData, state: Dictionary, region_id: String) -> Array:
	## Every chain this settlement could ever hold — buildable now, locked, or
	## standing as foreign work — in a stable order the UI can group by kind.
	var settlement: Dictionary = state["settlements"][region_id]
	var ctx := ConstructionRules.context(data, state, region_id)
	var culture: String = ctx["culture"]
	var rows: Array = []
	var chain_ids: Array = data.chains.keys()
	chain_ids.sort()
	for chain_id in chain_ids:
		var chain: Dictionary = data.chains[chain_id]
		var built_tier := int(settlement["buildings"].get(chain_id, 0))
		var mine: bool = chain["cultures"].has(culture)
		if not mine and built_tier <= 0:
			continue  # another people's building, not standing here: not our business
		rows.append({
			"chain": chain_id,
			"kind": chain["kind"],
			"name": chain["name"],
			"god": chain.get("god", ""),
			"built_tier": built_tier,
			"tier_count": (chain["levels"] as Array).size(),
			"foreign": not mine,
			"queued": ctx["queued"].has(chain_id),
			"framing": "upgrade" if built_tier > 0 else "found",
			"buildable_now": built_tier < (chain["levels"] as Array).size()
				and ConstructionRules.blockers_for(
					data, state, region_id, chain, built_tier + 1, ctx).is_empty(),
		})
	return rows


static func dossier(data: GameData, state: Dictionary, region_id: String, chain_id: String) -> Dictionary:
	## The whole ladder of one chain against one settlement: every tier, its
	## price, its standing effects, what it changes, what it unlocks, and for
	## the rungs out of reach, exactly what stands in the way.
	var chain: Dictionary = data.chains.get(chain_id, {})
	if chain.is_empty():
		return {}
	var settlement: Dictionary = state["settlements"][region_id]
	var ctx := ConstructionRules.context(data, state, region_id)
	var owner: String = settlement["owner"]
	var built_tier := int(settlement["buildings"].get(chain_id, 0))
	var levels: Array = chain["levels"]
	var built_effects: Dictionary = {}
	if built_tier > 0:
		built_effects = levels[built_tier - 1].get("effects", {})

	var tiers: Array = []
	for index in range(1, levels.size() + 1):
		var level: Dictionary = levels[index - 1]
		var quote := ConstructionRules.quoted_cost(data, state, state["settlements"][region_id], chain, level)
		var blockers: Array = []
		var state_name := "built"
		if index > built_tier:
			blockers = ConstructionRules.blockers_for(data, state, region_id, chain, index, ctx)
			if ctx["queued"].has(chain_id) and index == built_tier + 1:
				state_name = "in_progress"
			elif blockers.is_empty():
				state_name = "next"
			else:
				state_name = "locked"
		tiers.append({
			"index": index,
			"level_id": level["id"],
			"name": level["name"],
			"description": level["description"],
			"min_settlement_level": level["min_settlement_level"],
			"cost": quote["cost"],
			"build_turns": quote["build_turns"],
			"state": state_name,
			"blockers": blockers,
			"effects": level.get("effects", {}),
			"delta": effect_delta(built_effects, level.get("effects", {})),
			"steps_up": maxi(0, index - maxi(built_tier, 1)) if built_tier > 0 else 0,
			"unlocks": unlocked_by(data, state, region_id, chain, index),
			"lines": effect_lines(data, state, region_id, chain, built_tier, index),
		})

	var next_tier := built_tier + 1
	var action := {"can_queue": false, "cost": 0, "build_turns": 0,
		"affordable": false, "treasury": int(state["factions"][owner]["treasury"]),
		"reason": "complete"}
	if next_tier <= levels.size():
		var quote := ConstructionRules.quoted_cost(data, state, state["settlements"][region_id], chain, levels[next_tier - 1])
		var blockers := ConstructionRules.blockers_for(data, state, region_id, chain, next_tier, ctx)
		var affordable := int(state["factions"][owner]["treasury"]) >= int(quote["cost"])
		action = {
			"can_queue": blockers.is_empty() and affordable,
			"cost": quote["cost"],
			"build_turns": quote["build_turns"],
			"affordable": affordable,
			"treasury": int(state["factions"][owner]["treasury"]),
			# Affordability is not a blocker in the engine, so it is reported
			# apart from them — that is what stops the button going silently dead.
			"reason": "" if blockers.is_empty() else "blocked",
		}
		if blockers.is_empty() and not affordable:
			action["reason"] = "unaffordable"

	return {
		"chain": chain_id,
		"kind": chain["kind"],
		"name": chain["name"],
		"god": chain.get("god", ""),
		"archetype": chain.get("archetype", ""),
		"cultures": (chain["cultures"] as Array).duplicate(),
		"foreign": not chain["cultures"].has(ctx["culture"]),
		"indestructible": chain.get("indestructible", false),
		"built_tier": built_tier,
		"framing": "upgrade" if built_tier > 0 else "found",
		"tiers": tiers,
		"action": action,
		"kind_note": kind_note(data, chain["kind"]),
	}


static func effect_delta(old_effects: Dictionary, new_effects: Dictionary) -> Dictionary:
	## Levels carry standing totals, not increments, so what a tier actually
	## changes is new - old across the union of both keys.
	var delta := {}
	var keys := {}
	for key in old_effects:
		keys[key] = true
	for key in new_effects:
		keys[key] = true
	var ordered: Array = keys.keys()
	ordered.sort()
	for key in ordered:
		var change := float(new_effects.get(key, 0.0)) - float(old_effects.get(key, 0.0))
		if not is_zero_approx(change):
			delta[key] = change
	return delta


static func effect_lines(data: GameData, state: Dictionary, region_id: String,
		chain: Dictionary, from_tier: int, to_tier: int) -> Array:
	## The player-facing account of moving this chain from one tier to another,
	## as {heading, text, value, status, note}. Wording comes from the glossary;
	## the numbers come from balance.json.
	var settlement: Dictionary = state["settlements"][region_id]
	var levels: Array = chain["levels"]
	var old_effects: Dictionary = levels[from_tier - 1].get("effects", {}) if from_tier > 0 else {}
	var new_effects: Dictionary = levels[to_tier - 1].get("effects", {}) if to_tier > 0 else {}
	var lines: Array = []

	for row in _glossary(data).get("effects", []):
		var key: String = row["key"]
		var old_value := float(old_effects.get(key, 0.0))
		var new_value := float(new_effects.get(key, 0.0))
		# A chain that never grants this key has nothing to say about it. Without
		# this, every max-aggregated effect the town already has from elsewhere
		# turned up on every building — a wall upgrade announcing the barracks'
		# recruit experience.
		if not (old_effects.has(key) or new_effects.has(key)):
			continue
		var rival := 0.0
		if row["aggregation"] == "max":
			# Only the town's best counts, so the honest delta is measured
			# against the best chain that is NOT this one.
			rival = best_elsewhere(data, settlement, key, chain["id"])
			old_value = maxf(old_value, rival)
			new_value = maxf(new_value, rival)
		if is_zero_approx(new_value - old_value) and is_zero_approx(new_value):
			continue
		var change := new_value - old_value
		var matched: bool = is_zero_approx(change) and String(row["aggregation"]) == "max"
		if is_zero_approx(change) and not matched:
			continue
		lines.append({
			"key": key,
			"heading": row["heading"],
			"status": row["status"],
			"text": _fill(row["line"], {
				"value": _number(change, int(row.get("precision", 0)), bool(row.get("signed", true))),
				"new": _number(new_value, int(row.get("precision", 0)), false),
				"old": _number(old_value, int(row.get("precision", 0)), false),
			}),
			"value": change,
			"matched": matched,
			"rival": _rival_name(data, settlement, key, chain["id"]) if matched else "",
			"note": row.get("note", ""),
		})
		for derived in row.get("derived", []):
			var extra := _derived_line(data, state, region_id, chain, derived,
				old_value, new_value, from_tier, to_tier)
			if not extra.is_empty():
				lines.append(extra)
	return lines


static func best_elsewhere(data: GameData, settlement: Dictionary, key: String, except_chain: String) -> float:
	## The highest standing value of a max-aggregated effect from any OTHER
	## chain already built here — what this chain has to beat to change anything.
	var best := 0.0
	var chain_ids: Array = settlement["buildings"].keys()
	chain_ids.sort()
	for chain_id in chain_ids:
		if chain_id == except_chain:
			continue
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		var tier := mini(int(settlement["buildings"][chain_id]), (chain["levels"] as Array).size())
		if tier > 0:
			best = maxf(best, float(chain["levels"][tier - 1].get("effects", {}).get(key, 0.0)))
	return best


static func unlocked_by(data: GameData, state: Dictionary, region_id: String,
		chain: Dictionary, tier: int) -> Array:
	## The units this tier is the first to open. Mirrors RecruitmentRules
	## exactly — the faction whitelist and the era, NOT the unit's culture.
	## Joining on culture would promise a Roman player Greek pikemen and an
	## Eagle Cohort three centuries early.
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = settlement["owner"]
	var era: String = state["factions"][owner].get("era", "pre_marian")
	var found: Array = []
	for unit in data.units_for_faction(owner):
		# Mercenaries are hired, bodyguards come with the man: neither is
		# ever trained here, so neither is ever "unlocked".
		if unit["factions"].has("mercenary") or String(unit["class"]) == "general_bodyguard":
			continue
		var requirements: Dictionary = unit["requirements"]
		if requirements["building_kind"] != chain["kind"]:
			continue
		if int(requirements["building_level"]) != tier:
			continue
		var needed_god: String = requirements.get("temple_god", "")
		if needed_god != "" and chain.get("god", "") != needed_god:
			continue
		if chain["kind"] == "temple" and needed_god == "":
			continue
		var unit_era: String = unit.get("era", "any")
		found.append({
			"id": unit["id"],
			"name": unit["name"],
			"class": unit["class"],
			"cost": int(unit["cost"]),
			"upkeep": int(unit["upkeep"]),
			"soldiers": int(unit["soldiers"]),
			"era": unit_era,
			"era_locked": unit_era != "any" and unit_era != era,
		})
	found.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	return found


static func unit_dossier(data: GameData, state: Dictionary, region_id: String, template_id: String) -> Dictionary:
	## One unit against one settlement: its stats, what it needs, whether this
	## town can raise it, and if not, which of the two silent gates stops it.
	var unit: Dictionary = data.units.get(template_id, {})
	if unit.is_empty():
		return {}
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = settlement["owner"]
	var faction: Dictionary = state["factions"][owner]
	var requirements: Dictionary = unit["requirements"]
	var needed_kind: String = requirements["building_kind"]
	var needed_level := int(requirements["building_level"])
	var needed_god: String = requirements.get("temple_god", "")

	# Which chain of the right kind serves this unit here, and how far short.
	var best_tier := 0
	var serving_chain := ""
	var candidates: Array = []
	var chain_ids: Array = data.chains.keys()
	chain_ids.sort()
	for chain_id in chain_ids:
		var chain: Dictionary = data.chains[chain_id]
		if chain["kind"] != needed_kind:
			continue
		if needed_god != "" and chain.get("god", "") != needed_god:
			continue
		var built := int(settlement["buildings"].get(chain_id, 0))
		var reachable: bool = chain["cultures"].has(
			data.culture_of_faction(owner)) or built > 0
		if not reachable:
			continue
		candidates.append({
			"chain": chain_id, "name": chain["name"], "built_tier": built,
			"needs_tier": needed_level,
			"level_name": String(chain["levels"][mini(needed_level, (chain["levels"] as Array).size()) - 1]["name"]),
			"met": built >= needed_level,
		})
		if built > best_tier:
			best_tier = built
			serving_chain = chain_id

	var era: String = faction.get("era", "pre_marian")
	var unit_era: String = unit.get("era", "any")
	var era_ok: bool = unit_era == "any" or unit_era == era
	var building_ok := best_tier >= needed_level
	var affordable := int(faction["treasury"]) >= int(unit["cost"])
	var min_population := int(data.balance["growth"]["min_population"])
	var manpower_ok: bool = int(settlement["population"]) - int(unit["soldiers"]) >= min_population

	var reason := ""
	if not era_ok:
		reason = "era"
	elif not building_ok:
		reason = "building"
	elif not affordable:
		reason = "unaffordable"
	elif not manpower_ok:
		# queue_unit refuses on population too, not only on coin: a muster hall
		# that only checked the purse would keep the dead button this replaces.
		reason = "manpower"

	return {
		"id": template_id,
		"name": unit["name"],
		"class": unit["class"],
		"culture": unit["culture"],
		"description": unit["description"],
		"soldiers": int(unit["soldiers"]),
		"attack": int(unit["attack"]),
		"missile_attack": int(unit.get("missile_attack", 0)),
		"charge": int(unit.get("charge", 0)),
		"defense": int(unit["defense"]),
		"morale": int(unit["morale"]),
		"speed": int(unit.get("speed", 0)),
		"cost": int(unit["cost"]),
		"upkeep": int(unit["upkeep"]),
		"attributes": (unit.get("attributes", []) as Array).duplicate(),
		"era": unit_era,
		"requires": {
			"kind": needed_kind, "level": needed_level, "temple_god": needed_god,
			"chains": candidates, "best_tier": best_tier, "serving_chain": serving_chain,
		},
		"starts_with_experience": int(SettlementRules.effect_max(data, settlement, "recruit_xp")),
		"action": {
			"can_queue": era_ok and building_ok and affordable and manpower_ok,
			"affordable": affordable,
			"manpower": manpower_ok,
			"population": int(settlement["population"]),
			"min_population": min_population,
			"treasury": int(faction["treasury"]),
			"reason": reason,
		},
	}


static func unit_list(data: GameData, state: Dictionary, region_id: String) -> Array:
	## Every unit this settlement's owner could ever raise here, recruitable now
	## or not, so the player can see what a barracks upgrade is worth.
	var settlement: Dictionary = state["settlements"][region_id]
	var owner: String = settlement["owner"]
	var rows: Array = []
	for unit in data.units_for_faction(owner):
		if unit["factions"].has("mercenary") or String(unit["class"]) == "general_bodyguard":
			continue
		var sheet := unit_dossier(data, state, region_id, unit["id"])
		if sheet.is_empty() or (sheet["requires"]["chains"] as Array).is_empty():
			continue  # no chain of that kind is reachable for this culture
		rows.append(sheet)
	rows.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	return rows


static func blocker_text(data: GameData, blocker: Dictionary) -> String:
	## Turn a {kind, params} blocker into the authored sentence. Culture names
	## come from cultures.json so the drawer and the data never disagree.
	var params: Dictionary = (blocker.get("params", {}) as Dictionary).duplicate()
	if params.has("culture"):
		params["culture"] = data.cultures.get(params["culture"], {}).get("name", params["culture"])
	for key in ["needs", "have", "level", "cap"]:
		if params.has(key) and typeof(params[key]) == TYPE_STRING:
			params[key] = _level_name(String(params[key]))
	if params.has("resource"):
		params["resource"] = String(params["resource"]).replace("_", " ")
	for row in _glossary(data).get("blockers", []):
		if row["kind"] == blocker["kind"]:
			return _fill(row["line"], params)
	return String(blocker["kind"]).replace("_", " ")


static func caption(data: GameData, id: String, params: Dictionary = {}) -> String:
	for row in _glossary(data).get("captions", []):
		if row["id"] == id:
			return _fill(row["line"], params)
	return ""


static func kind_note(data: GameData, kind: String) -> Dictionary:
	for row in _glossary(data).get("kind_notes", []):
		if row["kind"] == kind:
			return {"heading": row["heading"], "text": row["line"]}
	return {}


static func headings(data: GameData) -> Array:
	return _glossary(data).get("headings", [])


static func growth_at_cap(data: GameData, state: Dictionary, region_id: String) -> bool:
	## GrowthRules clamps the total but not the factor list, so a growth line can
	## be true and still move nothing. The drawer has to say when that is so.
	var cap := float(data.balance["growth"]["max_growth_pct"])
	return GrowthRules.total_pct(data, state, region_id) >= cap - 0.0001


static func _glossary(data: GameData) -> Dictionary:
	# Fixtures build a GameData by hand and never load this table, so every
	# read has to survive it being absent.
	return data.effects_glossary if data.effects_glossary != null else {}


static func _derived_line(data: GameData, state: Dictionary, region_id: String,
		chain: Dictionary, derived: Dictionary, old_value: float, new_value: float,
		from_tier: int, to_tier: int) -> Dictionary:
	## Every derived number is read out of balance.json, never hardcoded here.
	## Each id needs a branch; tests/test_building_info.gd asserts the data
	## never names one this match has no case for.
	var precision := int(derived.get("precision", 0))
	var signed := bool(derived.get("signed", true))
	var old_out := 0.0
	var new_out := 0.0
	match String(derived["id"]):
		"corruption_relief_pct":
			# Corruption is exactly zero in the capital and within the free hops,
			# so a flat "law cuts corruption" line would be a lie in most early
			# cities. Measure the settlement's real corruption both ways instead.
			old_out = _corruption_with(data, state, region_id, chain, from_tier)
			new_out = _corruption_with(data, state, region_id, chain, to_tier)
			if is_equal_approx(old_out, new_out):
				return {}
			return _line(derived, old_out - new_out, new_out, old_out, precision, signed)
		"recruit_xp_cap":
			new_out = float(data.balance["recruitment"]["experience_max"])
			old_out = new_out
		"wall_defence_multiplier":
			var table: Array = data.balance["battle"]["wall_defense_multiplier"]
			old_out = float(table[clampi(int(old_value), 0, table.size() - 1)])
			new_out = float(table[clampi(int(new_value), 0, table.size() - 1)])
			if is_equal_approx(old_out, new_out):
				return {}
		"sea_routes":
			var per_level := float(data.balance["economy"]["sea_routes_per_port_level"])
			old_out = old_value * per_level
			new_out = new_value * per_level
			if is_equal_approx(old_out, new_out):
				return {}
		_:
			return {}
	return _line(derived, new_out - old_out, new_out, old_out, precision, signed)


static func _line(derived: Dictionary, change: float, new_out: float, old_out: float,
		precision: int, signed: bool) -> Dictionary:
	return {
		"key": String(derived["id"]),
		"heading": String(derived["heading"]),
		"status": "live",
		"text": _fill(String(derived["line"]), {
			"value": _number(change, precision, signed),
			"new": _number(new_out, precision, false),
			"old": _number(old_out, precision, false),
		}),
		"value": change,
		"matched": false,
		"rival": "",
		"note": "",
	}


static func _corruption_with(data: GameData, state: Dictionary, region_id: String,
		chain: Dictionary, tier: int) -> float:
	## Re-run the engine's own corruption maths on a copy of the settlement with
	## this chain at that tier, rather than reimplementing the formula here.
	var probe := state.duplicate(true)
	var settlement: Dictionary = probe["settlements"][region_id]
	if tier > 0:
		settlement["buildings"][chain["id"]] = tier
	else:
		settlement["buildings"].erase(chain["id"])
	return EconomyRules.corruption_pct(data, probe, region_id)


static func _rival_name(data: GameData, settlement: Dictionary, key: String, except_chain: String) -> String:
	var best := 0.0
	var name := ""
	var chain_ids: Array = settlement["buildings"].keys()
	chain_ids.sort()
	for chain_id in chain_ids:
		if chain_id == except_chain:
			continue
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		var tier := mini(int(settlement["buildings"][chain_id]), (chain["levels"] as Array).size())
		if tier <= 0:
			continue
		var value := float(chain["levels"][tier - 1].get("effects", {}).get(key, 0.0))
		if value > best:
			best = value
			name = String(chain["levels"][tier - 1]["name"])
	return name


static func _level_name(id: String) -> String:
	return id.replace("_", " ").capitalize()


static func _number(value: float, precision: int, signed: bool) -> String:
	var text := String.num(absf(value), precision)
	if signed:
		return ("+" if value >= 0.0 else "-") + text
	return ("-" if value < 0.0 else "") + text


static func _fill(template: String, params: Dictionary) -> String:
	## Authored lines carry {tokens}, never printf verbs: a data file must not be
	## able to crash the game with a bad format string.
	var text := template
	for key in params:
		text = text.replace("{%s}" % key, str(params[key]))
	return text
