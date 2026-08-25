class_name SettlementRules
## Shared settlement queries used by growth, order, economy, construction.


static func settlement_level(data: GameData, settlement: Dictionary) -> String:
	## Settlement level IS the government building tier (index 1 = village).
	## A conquered settlement keeps its foreign government building's tier until
	## the new owner's own chain overtakes it, so captured cities never collapse
	## back to villages.
	var tier := 1
	for chain_id in settlement["buildings"]:
		if data.chains.get(chain_id, {}).get("kind", "") == "government":
			tier = maxi(tier, int(settlement["buildings"][chain_id]))
	return Constants.SETTLEMENT_LEVELS[mini(tier - 1, Constants.SETTLEMENT_LEVELS.size() - 1)]


static func effect_total(data: GameData, settlement: Dictionary, effect: String) -> float:
	## Sum an effect key across built chains. WITHIN a chain, each level's
	## effects value is the standing total at that tier (a level-3 market's
	## trade_pct replaces level 2's — it does not stack on top of it). That is
	## how the data tables are authored, matching the research report's shape
	## (e.g. a fertility temple's happiness reads 5/10/15 up its tiers).
	var total := 0.0
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		var built_tier := mini(int(settlement["buildings"][chain_id]), chain["levels"].size())
		if built_tier > 0:
			total += float(chain["levels"][built_tier - 1].get("effects", {}).get(effect, 0.0))
	return total


static func effect_max(data: GameData, settlement: Dictionary, effect: String) -> float:
	## Highest standing value of an effect key across built chains (for
	## tier-like effects such as wall_level, road_level, port_level).
	var best := 0.0
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		var built_tier := mini(int(settlement["buildings"][chain_id]), chain["levels"].size())
		if built_tier > 0:
			best = maxf(best, float(chain["levels"][built_tier - 1].get("effects", {}).get(effect, 0.0)))
	return best


static func refresh_governors(data: GameData, state: Dictionary) -> void:
	## Governorship is derived from presence, never stored independently: an
	## adult family member standing in a settlement his faction owns governs it.
	## March him away and the post falls vacant; no one governs two cities, and
	## the most influential claimant present holds the seat.
	var claims := {}  # region_id -> {char_id, influence}
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if not character["alive"] or character["role"] in ["spouse", "child"]:
			continue
		if character.get("gender", "male") != "male":
			continue
		if int(character["age"]) < int(data.balance["characters"]["come_of_age"]):
			continue
		var location: String = character.get("location", "")
		if location == "" or not state["settlements"].has(location):
			continue
		if state["settlements"][location]["owner"] != character["faction"]:
			continue
		var influence := CharacterRules.effective(data, character, "influence")
		if not claims.has(location) or influence > int(claims[location]["influence"]):
			claims[location] = {"char_id": char_id, "influence": influence}

	for region_id in state["settlements"]:
		var claim = claims.get(region_id)
		state["settlements"][region_id]["governor"] = claim["char_id"] if claim != null else null


static func garrison_soldiers(data: GameData, settlement: Dictionary) -> int:
	var soldiers := 0
	for unit in settlement["garrison"]:
		var template: Dictionary = data.units.get(unit["template"], {})
		soldiers += int(ceil(int(template.get("soldiers", 0)) * int(unit["strength_pct"]) / 100.0))
	return soldiers


static func culture_penalty_pct(data: GameData, state: Dictionary, region_id: String) -> float:
	## Penalty proportional to the share of buildings belonging to foreign cultures.
	var settlement: Dictionary = state["settlements"][region_id]
	var owner_culture := data.culture_of_faction(settlement["owner"])
	var cancelled_cultures := _cancelled_cultures(data, state, settlement["owner"])
	var total := 0
	var foreign := 0
	for chain_id in settlement["buildings"]:
		var chain: Dictionary = data.chains.get(chain_id, {})
		if chain.is_empty():
			continue
		total += 1
		var chain_cultures: Array = chain["cultures"]
		if not chain_cultures.has(owner_culture):
			var all_cancelled := true
			for culture in chain_cultures:
				if not cancelled_cultures.has(culture):
					all_cancelled = false
			if not all_cancelled:
				foreign += 1
	if total == 0:
		return 0.0
	var penalty := float(foreign) / float(total) * float(data.balance["public_order"]["culture_penalty_scale"])
	# The citizenship lever: franchise and cult edicts soften what foreign
	# stones cost in loyalty.
	penalty *= maxf(0.0, 1.0 - EdictRules.faction_effect_total(
		data, state, settlement["owner"], "culture_penalty_reduction_pct") / 100.0)
	return penalty


static func _cancelled_cultures(data: GameData, state: Dictionary, faction_id: String) -> Array:
	## Wonders can cancel the culture penalty for buildings of one culture.
	var cancelled: Array = []
	for wonder_id in data.wonders:
		var wonder: Dictionary = data.wonders[wonder_id]
		var wonder_region: String = wonder["region"]
		if not state["settlements"].has(wonder_region):
			continue
		if state["settlements"][wonder_region]["owner"] != faction_id:
			continue
		var culture = wonder.get("effects", {}).get("cancel_culture_penalty_culture")
		if culture != null:
			cancelled.append(culture)
	return cancelled


static func faction_owns_wonder_effect(data: GameData, state: Dictionary, faction_id: String, effect: String) -> float:
	var total := 0.0
	for wonder_id in data.wonders:
		var wonder: Dictionary = data.wonders[wonder_id]
		if not state["settlements"].has(wonder["region"]):
			continue
		if state["settlements"][wonder["region"]]["owner"] != faction_id:
			continue
		total += float(wonder.get("effects", {}).get(effect, 0.0))
	return total
