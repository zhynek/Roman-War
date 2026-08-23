class_name CharacterRules
## The trait & ancillary engine (Phase 4). Characters hold trait POINTS
## ("trait_points": {trait_id: int}); a trait is active at the highest level
## whose threshold the points reach, and its level effects modify the
## character's attributes and the settlement/army they serve. Triggers follow
## the data tables' WhenToTest/Condition/Chance shape.


## --- Effective attributes -------------------------------------------------

static func active_trait_levels(data: GameData, character: Dictionary) -> Array:
	## [{trait: trait dict, level: level dict, level_number: int}] for display and effects.
	var active: Array = []
	var trait_ids: Array = character.get("trait_points", {}).keys()
	trait_ids.sort()
	for trait_id in trait_ids:
		var trait_def: Dictionary = data.traits.get(trait_id, {})
		if trait_def.is_empty():
			continue
		var points := int(character["trait_points"][trait_id])
		var reached := {}
		var level_number := 0
		for i in range(trait_def["levels"].size()):
			if points >= int(trait_def["levels"][i]["threshold"]):
				reached = trait_def["levels"][i]
				level_number = i + 1
		if level_number > 0:
			active.append({"trait": trait_def, "level": reached, "level_number": level_number})
	return active


static func effect_total(data: GameData, character: Dictionary, effect: String) -> float:
	var total := 0.0
	for entry in active_trait_levels(data, character):
		total += float(entry["level"].get("effects", {}).get(effect, 0.0))
	for ancillary_id in character.get("ancillaries", []):
		var ancillary: Dictionary = data.ancillaries.get(ancillary_id, {})
		total += float(ancillary.get("effects", {}).get(effect, 0.0))
	return total


static func effective(data: GameData, character: Dictionary, attribute: String) -> int:
	## command / management / influence, with trait and retinue modifiers.
	return maxi(0, int(character.get(attribute, 0)) + int(effect_total(data, character, attribute)))


static func battle_profile(data: GameData, character: Dictionary) -> Dictionary:
	## What the BattleResolver needs to know about a general.
	return {
		"command": effective(data, character, "command"),
		"troop_morale": effect_total(data, character, "troop_morale"),
	}


## --- Trait points ---------------------------------------------------------

static func award_points(data: GameData, character: Dictionary, trait_id: String, points: int) -> void:
	## Positive points erode the anti-trait first (a brave deed chips away at
	## cowardice before building bravery); negative points erode the trait itself.
	if points == 0 or not data.traits.has(trait_id):
		return
	var trait_points: Dictionary = character["trait_points"]
	if points < 0:
		var current := int(trait_points.get(trait_id, 0))
		var reduced := maxi(0, current + points)
		if reduced == 0:
			trait_points.erase(trait_id)
		else:
			trait_points[trait_id] = reduced
		return
	var anti: String = data.traits[trait_id].get("anti_trait", "")
	if anti != "" and int(trait_points.get(anti, 0)) > 0:
		var anti_points := int(trait_points[anti])
		var eroded := mini(points, anti_points)
		if anti_points - eroded == 0:
			trait_points.erase(anti)
		else:
			trait_points[anti] = anti_points - eroded
		points -= eroded
	if points > 0:
		trait_points[trait_id] = int(trait_points.get(trait_id, 0)) + points


## --- Triggers -------------------------------------------------------------

static func fire_trigger(data: GameData, state: Dictionary, char_id: String, when: String, context: Dictionary, rng: CampaignRng, notices: Array) -> void:
	var character: Dictionary = state["characters"].get(char_id, {})
	if character.is_empty() or not character.get("alive", false):
		return

	var trait_ids: Array = data.traits.keys()
	trait_ids.sort()
	for trait_id in trait_ids:
		var trait_def: Dictionary = data.traits[trait_id]
		for trigger in trait_def.get("triggers", []):
			if trigger["when"] != when:
				continue
			if not _condition_met(data, state, character, trigger.get("condition", {}), context):
				continue
			if not rng.chance(float(trigger["chance"])):
				continue
			var before := active_trait_levels(data, character).size()
			award_points(data, character, trait_id, int(trigger["points"]))
			if active_trait_levels(data, character).size() != before:
				notices.append({"kind": "trait", "character": char_id, "trait": trait_id})

	var ancillary_ids: Array = data.ancillaries.keys()
	ancillary_ids.sort()
	for ancillary_id in ancillary_ids:
		var ancillary: Dictionary = data.ancillaries[ancillary_id]
		for trigger in ancillary.get("triggers", []):
			if trigger["when"] != when:
				continue
			if character["ancillaries"].has(ancillary_id):
				continue
			if character["ancillaries"].size() >= int(data.balance["characters"]["ancillary_max"]):
				continue
			if ancillary.get("unique", false) and _ancillary_held_anywhere(state, ancillary_id):
				continue
			if not _condition_met(data, state, character, trigger.get("condition", {}), context):
				continue
			if not rng.chance(float(trigger["chance"])):
				continue
			character["ancillaries"].append(ancillary_id)
			notices.append({"kind": "ancillary", "character": char_id, "ancillary": ancillary_id})


static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	## Situation-based turn-end triggers for every living family character.
	var notices: Array = []
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if not character["alive"] or character["role"] in ["spouse", "child"]:
			continue
		var governed := _governed_settlement(state, char_id)
		if governed != "":
			# Public order is computed once here, not per trigger condition.
			fire_trigger(data, state, char_id, "turn_end_governing", {
				"region": governed,
				"public_order": PublicOrderRules.total(data, state, governed),
			}, rng, notices)
		elif _leads_army(state, char_id):
			fire_trigger(data, state, char_id, "turn_end_campaigning", {}, rng, notices)
		else:
			fire_trigger(data, state, char_id, "turn_end_idle", {}, rng, notices)
	return notices


## --- Lifecycle helpers (shared with combat and family) --------------------

static func kill(state: Dictionary, char_id: String) -> void:
	if state["characters"].has(char_id):
		state["characters"][char_id]["alive"] = false
	for settlement in state["settlements"].values():
		if settlement["governor"] == char_id:
			settlement["governor"] = null
	for army in state["armies"].values():
		if army["general"] == char_id:
			army["general"] = null


static func transfer_ancillary(data: GameData, state: Dictionary, from_id: String, to_id: String, ancillary_id: String) -> bool:
	## Retinue members change masters only between co-located, same-faction,
	## living characters, and only up to the retinue cap.
	var source: Dictionary = state["characters"].get(from_id, {})
	var target: Dictionary = state["characters"].get(to_id, {})
	if source.is_empty() or target.is_empty() or from_id == to_id:
		return false
	if not source["alive"] or not target["alive"]:
		return false
	if source["faction"] != target["faction"]:
		return false
	if source.get("location", "") != target.get("location", "") or source.get("location", "") == "":
		return false
	if not source["ancillaries"].has(ancillary_id):
		return false
	if target["ancillaries"].size() >= int(data.balance["characters"]["ancillary_max"]):
		return false
	source["ancillaries"].erase(ancillary_id)
	target["ancillaries"].append(ancillary_id)
	return true


## --- Internals ------------------------------------------------------------

static func _governed_settlement(state: Dictionary, char_id: String) -> String:
	for region_id in state["settlements"]:
		if state["settlements"][region_id]["governor"] == char_id:
			return region_id
	return ""


static func _leads_army(state: Dictionary, char_id: String) -> bool:
	for army in state["armies"].values():
		if army["general"] == char_id:
			return true
	return false


static func _ancillary_held_anywhere(state: Dictionary, ancillary_id: String) -> bool:
	for character in state["characters"].values():
		if character.get("ancillaries", []).has(ancillary_id):
			return true
	return false


static func _condition_met(data: GameData, state: Dictionary, character: Dictionary, condition: Dictionary, context: Dictionary) -> bool:
	if condition.is_empty():
		return true

	if condition.has("odds_against") and bool(condition["odds_against"]) != bool(context.get("odds_against", false)):
		return false

	# Settlement-scoped conditions only bind while actually governing.
	var region: String = context.get("region", "")
	var needs_settlement: bool = condition.has("min_tax_level") or condition.has("building_kind") \
		or condition.has("min_public_order") or condition.has("max_public_order")
	if needs_settlement:
		if region == "" or not state["settlements"].has(region):
			return false
		var settlement: Dictionary = state["settlements"][region]
		if condition.has("min_tax_level"):
			var wanted := Constants.TAX_LEVELS.find(String(condition["min_tax_level"]))
			if Constants.TAX_LEVELS.find(String(settlement["tax_level"])) < wanted:
				return false
		if condition.has("building_kind"):
			var min_level := int(condition.get("min_building_level", 1))
			var found := false
			for chain_id in settlement["buildings"]:
				var chain: Dictionary = data.chains.get(chain_id, {})
				if chain.get("kind", "") == String(condition["building_kind"]) \
						and int(settlement["buildings"][chain_id]) >= min_level:
					found = true
					break
			if not found:
				return false
		if condition.has("min_public_order") or condition.has("max_public_order"):
			var order: float = context["public_order"] if context.has("public_order") \
				else PublicOrderRules.total(data, state, region)
			if condition.has("min_public_order") and order < float(condition["min_public_order"]):
				return false
			if condition.has("max_public_order") and order > float(condition["max_public_order"]):
				return false
	return true
