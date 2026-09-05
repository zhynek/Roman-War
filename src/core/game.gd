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
	var moved := MovementRules.move_army(data, state, army_id, to_region, forced_march)
	if moved:
		_after_relocation()
	return moved


func march_army(army_id: String, to_region: String, forced_march: bool = false) -> Dictionary:
	## Multi-step march along the cheapest path (see MovementRules.march).
	var result := MovementRules.march(data, state, army_id, to_region, forced_march)
	if not result["path"].is_empty():
		_after_relocation()
	return result


func move_fleet(fleet_id: String, to_zone: String) -> bool:
	return MovementRules.move_fleet(data, state, fleet_id, to_zone)


func sail_fleet(fleet_id: String, to_zone: String) -> Dictionary:
	return MovementRules.sail(data, state, fleet_id, to_zone)


func attack_army(attacker_id: String, defender_id: String) -> Dictionary:
	var rng := _rng()
	var result := CombatRules.attack_army(data, state, resolver, rng, attacker_id, defender_id)
	state["rng_state"] = rng.state_string()
	_after_relocation()
	return result


func declare_war(other_faction: String, faction_id: String = "") -> bool:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return DiplomacyRules.declare_war(state, fid, other_faction)


func set_stance(other_faction: String, stance: String, faction_id: String = "") -> bool:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return DiplomacyRules.set_stance(state, fid, other_faction, stance)


func sea_move_army(army_id: String, to_region: String) -> bool:
	var moved := MovementRules.sea_move_army(data, state, army_id, to_region)
	if moved:
		_after_relocation()
	return moved


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
	var laid := SiegeRules.begin_siege(data, state, army_id, region_id)
	if laid:
		_after_relocation()
	return laid


func assault_settlement(army_id: String, region_id: String, occupation: String = "occupy") -> Dictionary:
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
	return CombatRules.garrison_army(data, state, army_id, army["region"])


## --- Queries (for UI scrolls) --------------------------------------------

func force_summary(force_id: String) -> Dictionary:
	## One dictionary describing an army ("army_N"), a fleet ("fleet_N") or a
	## garrison ("garrison:<region>") — see ForceRules.summary.
	return ForceRules.summary(data, state, force_id)


func reachable_regions(army_id: String) -> Dictionary:
	## {reach, blocked} for an army, seen through its owner's fog.
	var owner: String = state["armies"].get(army_id, {}).get("owner", "")
	if owner == "":
		return {"reach": {}, "blocked": {}}
	return MovementRules.reachable(data, state, army_id, VisibilityRules.visible_regions(data, state, owner))


func targets_for(army_id: String) -> Dictionary:
	return MovementRules.targets_for(data, state, army_id)


func reachable_zones(fleet_id: String) -> Dictionary:
	return MovementRules.fleet_reachable(data, state, fleet_id)


func forces_awaiting_orders(faction_id: String = "") -> Array:
	## Own armies then fleets, numeric id order, that still have movement.
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	var waiting: Array = []
	var army_ids: Array = state["armies"].keys()
	army_ids.sort_custom(ForceRules.id_less)
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army["owner"] == fid and float(army["movement_left"]) > 0.0001:
			waiting.append(army_id)
	var fleet_ids: Array = state["fleets"].keys()
	fleet_ids.sort_custom(ForceRules.id_less)
	for fleet_id in fleet_ids:
		var fleet: Dictionary = state["fleets"][fleet_id]
		if fleet["owner"] == fid and float(fleet["movement_left"]) > 0.0001:
			waiting.append(fleet_id)
	return waiting


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


func visible_regions(faction_id: String = "") -> Dictionary:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return VisibilityRules.visible_regions(data, state, fid)


func visible_sea_zones(faction_id: String = "") -> Dictionary:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return VisibilityRules.visible_sea_zones(data, state, fid)


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


func _after_relocation() -> void:
	## Governorship follows presence: a general who marches out of his city
	## stops governing it this turn, not at the next end of turn. Derived
	## value, no randomness involved.
	SettlementRules.refresh_governors(data, state)


func _rng() -> CampaignRng:
	return CampaignRng.from_state_string(String(state["rng_state"]))
