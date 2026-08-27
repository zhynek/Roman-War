class_name Game
extends RefCounted
## The campaign facade: everything the UI (and the test suite) talks to.
## Holds immutable GameData, the mutable GameState dict, and the injected
## BattleResolver. Player actions are methods; end_turn() resolves the world.

var data: GameData
var state: Dictionary = {}
var resolver: BattleResolver


static func new_campaign(player_faction: String, seed_value: int = 1, difficulty: String = "medium", campaign_mode: String = "long", data_dir: String = "res://data") -> Game:
	var game := Game.new()
	game.data = GameData.load_from(data_dir)
	game.resolver = AutoResolver.new()
	game.state = NewGame.build(game.data, player_faction, seed_value, difficulty, campaign_mode)
	return game


func end_turn() -> Dictionary:
	return TurnEngine.end_turn(data, state, resolver)


## --- Settlement actions --------------------------------------------------

func set_tax_level(region_id: String, tax_level: String) -> bool:
	if not Constants.TAX_LEVELS.has(tax_level):
		return false
	state["settlements"][region_id]["tax_level"] = tax_level
	return true


func queue_building(region_id: String, chain_id: String) -> bool:
	return ConstructionRules.queue_project(data, state, region_id, chain_id)


func demolish_building(region_id: String, chain_id: String) -> bool:
	return ConstructionRules.demolish(data, state, region_id, chain_id)


func queue_unit(region_id: String, template_id: String) -> bool:
	return RecruitmentRules.queue_unit(data, state, region_id, template_id)


func retrain_garrison(region_id: String) -> int:
	return RecruitmentRules.retrain_garrison(data, state, region_id)


func move_capital(region_id: String) -> bool:
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != state["player_faction"]:
		return false
	state["factions"][state["player_faction"]]["capital"] = region_id
	return true


## --- Army actions --------------------------------------------------------

func move_army(army_id: String, to_region: String, forced_march: bool = false) -> bool:
	_cancel_march(army_id)
	return MovementRules.move_army(data, state, army_id, to_region, forced_march)


func move_fleet(fleet_id: String, to_zone: String) -> bool:
	return MovementRules.move_fleet(data, state, fleet_id, to_zone)


func attack_army(attacker_id: String, defender_id: String) -> Dictionary:
	_cancel_march(attacker_id)
	var rng := _rng()
	var result := CombatRules.attack_army(data, state, resolver, rng, attacker_id, defender_id)
	state["rng_state"] = rng.state_string()
	return result


func declare_war(other_faction: String, faction_id: String = "") -> bool:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return DiplomacyRules.declare_war(state, fid, other_faction)


func set_stance(other_faction: String, stance: String, faction_id: String = "") -> bool:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return DiplomacyRules.set_stance(state, fid, other_faction, stance)


func sea_move_army(army_id: String, to_region: String) -> bool:
	_cancel_march(army_id)
	return MovementRules.sea_move_army(data, state, army_id, to_region)


func march_army(army_id: String, to_region: String, forced_march: bool = false) -> Dictionary:
	## Plot the cheapest route and set off at once; the remainder resumes each
	## end_turn. The route only ever takes plain move_army steps — combat
	## stays an explicit order — and it is plotted with the owner's own fog,
	## so it cannot navigate around enemies the owner has not seen.
	## -> advance_march's outcome plus cost/turns/blocked_destination; {} when
	## nothing leads toward the destination.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return {}
	var found := PathfindingRules.best_path(
		data, state, army_id, to_region, visible_regions(String(army["owner"])), forced_march)
	if found.is_empty():
		return {}
	if (found["path"] as Array).is_empty():
		if found.get("blocked_destination", false):
			# Already beside the target and the way in is barred: nothing to
			# march, but the caller deserves better than "unreachable".
			return {"moved": 0, "arrived": false, "halted": true,
				"blocked_destination": true, "cost": 0.0, "turns": 0}
		return {}
	army["march_path"] = (found["path"] as Array).duplicate()
	army["march_forced"] = forced_march
	var outcome := PathfindingRules.advance_march(data, state, army_id)
	outcome["cost"] = found["cost"]
	outcome["turns"] = found["turns"]
	outcome["blocked_destination"] = found["blocked_destination"]
	return outcome


func halt_march(army_id: String) -> bool:
	var army: Dictionary = state["armies"].get(army_id, {})
	if not army.has("march_path"):
		return false
	army.erase("march_path")
	army.erase("march_forced")
	return true


func army_reachable(army_id: String, forced_march: bool = false) -> Dictionary:
	## {region_id: cost} within this turn's remaining points, through the
	## owner's fog — the map's movement-range overlay.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return {}
	return PathfindingRules.reachable(
		data, state, army_id, -1.0, forced_march, visible_regions(String(army["owner"])))


func army_path_preview(army_id: String, to_region: String, forced_march: bool = false) -> Dictionary:
	## best_path through the owner's fog, without moving anything — the map's
	## hover preview. Route and turns account for a forced march when asked.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return {}
	return PathfindingRules.best_path(
		data, state, army_id, to_region, visible_regions(String(army["owner"])), forced_march)


func hire_mercenary(army_id: String, template_id: String) -> bool:
	return MercenaryRules.hire(data, state, army_id, template_id)


func mercenaries_available(region_id: String) -> Array:
	return MercenaryRules.available(data, state, region_id)


## --- Family & characters --------------------------------------------------

func family_of(faction_id: String = "") -> Array:
	## Living characters of a faction, leader first, then heir, then the rest
	## by id — the family panel's listing order.
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	var members: Array = []
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["faction"] == fid and character["alive"]:
			members.append({"id": char_id, "character": character})
	var role_rank := {"leader": 0, "heir": 1, "family": 2, "child": 3, "spouse": 4}
	members.sort_custom(func(a, b):
		var rank_a: int = role_rank.get(a["character"]["role"], 5)
		var rank_b: int = role_rank.get(b["character"]["role"], 5)
		return rank_a < rank_b if rank_a != rank_b else String(a["id"]) < String(b["id"]))
	return members


func character_sheet(char_id: String) -> Dictionary:
	## Everything the UI shows for one character: effective attributes and
	## named traits/ancillaries.
	var character: Dictionary = state["characters"].get(char_id, {})
	if character.is_empty():
		return {}
	var traits: Array = []
	for entry in CharacterRules.active_trait_levels(data, character):
		traits.append({"name": entry["level"]["name"], "effects": entry["level"].get("effects", {})})
	var ancillaries: Array = []
	for ancillary_id in character["ancillaries"]:
		ancillaries.append(data.ancillaries.get(ancillary_id, {}).get("name", ancillary_id))
	return {
		"id": char_id,
		"name": character["name"],
		"age": character["age"],
		"role": character["role"],
		"faction": character["faction"],
		"command": CharacterRules.effective(data, character, "command"),
		"management": CharacterRules.effective(data, character, "management"),
		"influence": CharacterRules.effective(data, character, "influence"),
		"traits": traits,
		"ancillaries": ancillaries,
		"location": character.get("location", ""),
	}


func set_heir(char_id: String) -> bool:
	return FamilyRules.set_heir(data, state, String(state["player_faction"]), char_id)


func transfer_ancillary(from_char: String, to_char: String, ancillary_id: String) -> bool:
	## Player-only convenience, per the design: the AI never shuffles retinues.
	var source: Dictionary = state["characters"].get(from_char, {})
	if source.is_empty() or source["faction"] != state["player_faction"]:
		return false
	return CharacterRules.transfer_ancillary(data, state, from_char, to_char, ancillary_id)


func besiege(army_id: String, region_id: String) -> bool:
	_cancel_march(army_id)
	return SiegeRules.begin_siege(data, state, army_id, region_id)


func assault_settlement(army_id: String, region_id: String, occupation: String = "occupy") -> Dictionary:
	_cancel_march(army_id)
	var rng := _rng()
	var result := SiegeRules.assault(data, state, rng, resolver, army_id, region_id)
	if result.get("captured", false):
		var general = state["armies"].get(army_id, {}).get("general")
		result["capture"] = CombatRules.capture_settlement(
			data, state, rng, region_id, result["capture_pending_owner"], occupation)
		var notices: Array = result.get("character_notices", [])
		CombatRules.fire_occupation_triggers(data, state, rng, general, occupation, notices)
		result["character_notices"] = notices
	state["rng_state"] = rng.state_string()
	return result


func garrison_army(army_id: String) -> bool:
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return false
	_cancel_march(army_id)
	return CombatRules.garrison_army(data, state, army_id, army["region"])


## --- Queries (for UI scrolls) --------------------------------------------

func growth_breakdown(region_id: String) -> Array:
	return GrowthRules.breakdown(data, state, region_id)


func order_breakdown(region_id: String) -> Array:
	return PublicOrderRules.breakdown(data, state, region_id)


func income_breakdown(region_id: String) -> Array:
	return EconomyRules.settlement_income_breakdown(data, state, region_id)


func available_buildings(region_id: String) -> Array:
	return ConstructionRules.available_projects(data, state, region_id)


func available_units(region_id: String) -> Array:
	return RecruitmentRules.available_units(data, state, region_id)


## --- Info-card queries (the visual layer: R1-R3) --------------------------

func unit_profile(template_id: String) -> Dictionary:
	## Everything the unit card shows, with classes, skills and training
	## buildings explained through the glossary. {} for unknown templates.
	var template: Dictionary = data.units.get(template_id, {})
	if template.is_empty():
		return {}
	var skills: Array = []
	for attribute_id in template.get("attributes", []):
		skills.append(_glossary_entry("attributes", String(attribute_id)))
	var need: Dictionary = template["requirements"]
	return {
		"id": template_id,
		"name": String(template["name"]),
		"class_id": String(template["class"]),
		"class_entry": _glossary_entry("unit_classes", String(template["class"])),
		"culture": String(template["culture"]),
		"soldiers": int(template["soldiers"]),
		"attack": int(template["attack"]),
		"charge": int(template.get("charge", 0)),
		"missile_attack": int(template.get("missile_attack", 0)),
		"defense": int(template["defense"]),
		"morale": int(template["morale"]),
		"speed": int(template.get("speed", 0)),
		"cost": int(template["cost"]),
		"upkeep": int(template["upkeep"]),
		"era": String(template.get("era", "any")),
		"attributes": skills,
		"trained_at": {
			"kind": String(need["building_kind"]),
			"kind_entry": _glossary_entry("building_kinds", String(need["building_kind"])),
			"level": int(need["building_level"]),
			"temple_god": String(need.get("temple_god", "")),
		},
		"description": String(template.get("description", "")),
	}


func building_profile(chain_id: String) -> Dictionary:
	## The building card: the chain, its kind explained, every level's effects
	## as named breakdowns, and the units each level unlocks — the class-to-
	## building correspondence computed from the data, never authored twice.
	var chain: Dictionary = data.chains.get(chain_id, {})
	if chain.is_empty():
		return {}
	var levels: Array = []
	for i in range(chain["levels"].size()):
		var level: Dictionary = chain["levels"][i]
		var effects: Array = []
		var effect_ids: Array = level.get("effects", {}).keys()
		effect_ids.sort()
		for effect_id in effect_ids:
			var entry := _glossary_entry("effects", String(effect_id))
			entry["value"] = level["effects"][effect_id]
			effects.append(entry)
		levels.append({
			"id": String(level["id"]),
			"name": String(level["name"]),
			"index": i + 1,
			"cost": int(level["cost"]),
			"build_turns": int(level["build_turns"]),
			"min_settlement_level": String(level["min_settlement_level"]),
			"effects": effects,
			"unlocks": _units_unlocked_at(chain, i + 1),
			"description": String(level.get("description", "")),
		})
	return {
		"id": chain_id,
		"name": String(chain["name"]),
		"kind": String(chain["kind"]),
		"kind_entry": _glossary_entry("building_kinds", String(chain["kind"])),
		# duplicated: profiles are consumer-owned, the content table is not
		"cultures": (chain.get("cultures", []) as Array).duplicate(),
		"god": String(chain.get("god", "")),
		"levels": levels,
	}


func _units_unlocked_at(chain: Dictionary, tier: int) -> Array:
	## Templates this exact chain begins to satisfy at `tier`: kind and level
	## match, the chain serves the unit's culture, and a demanded temple god
	## matches. Mercenary-only templates never appear — they are hired, not
	## trained.
	var unlocked: Array = []
	var unit_ids: Array = data.units.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var template: Dictionary = data.units[unit_id]
		var need: Dictionary = template["requirements"]
		if String(need["building_kind"]) != String(chain["kind"]):
			continue
		if int(need["building_level"]) != tier:
			continue
		if template["factions"] == ["mercenary"]:
			continue
		if not chain.get("cultures", []).has(template["culture"]):
			continue
		var god_needed := String(need.get("temple_god", ""))
		if god_needed != "" and god_needed != String(chain.get("god", "")):
			continue
		unlocked.append({
			"id": unit_id,
			"name": String(template["name"]),
			"class_id": String(template["class"]),
			"class_entry": _glossary_entry("unit_classes", String(template["class"])),
		})
	return unlocked


func _glossary_entry(section: String, entry_id: String) -> Dictionary:
	## Glossary text with a graceful fallback for worlds without a glossary
	## (the synthetic fixtures): the id prettified, an empty blurb.
	var entry: Dictionary = data.glossary.get(section, {}).get(entry_id, {})
	if entry.is_empty():
		return {"id": entry_id, "name": entry_id.capitalize(), "blurb": ""}
	return {"id": entry_id, "name": String(entry["name"]), "blurb": String(entry["blurb"])}


func visible_regions(faction_id: String = "") -> Dictionary:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return VisibilityRules.visible_regions(data, state, fid)


func victory_progress(faction_id: String = "") -> Dictionary:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return VictoryRules.progress(data, state, fid)


## --- Save / load ----------------------------------------------------------

func save_to(path: String) -> bool:
	return SaveGame.write_file(state, path)


func load_from(path: String) -> bool:
	var loaded := SaveGame.read_file(path)
	if loaded.is_empty():
		return false
	state = loaded
	return true


func _rng() -> CampaignRng:
	return CampaignRng.from_state_string(String(state["rng_state"]))


func _cancel_march(army_id: String) -> void:
	## Every explicit order supersedes a queued march — a besieger must not
	## walk away from its own siege next turn because an old road was queued.
	var army: Dictionary = state["armies"].get(army_id, {})
	army.erase("march_path")
	army.erase("march_forced")
