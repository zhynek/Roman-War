class_name Game
extends RefCounted
## The campaign facade: everything the UI (and the test suite) talks to.
## Holds immutable GameData, the mutable GameState dict, and the injected
## BattleResolver. Player actions are methods; end_turn() resolves the world.

var data: GameData
var state: Dictionary = {}
var resolver: BattleResolver


static func new_campaign(player_faction: String, seed_value: int = 1, difficulty: String = "medium", campaign_mode: String = "long", guided: bool = true, data_dir: String = "res://data") -> Game:
	var game := Game.new()
	game.data = GameData.load_from(data_dir)
	game.resolver = AutoResolver.new()
	game.state = NewGame.build(game.data, player_faction, seed_value, difficulty, campaign_mode, guided)
	return game


func end_turn() -> Dictionary:
	return TurnEngine.end_turn(data, state, resolver)


## --- Settlement actions --------------------------------------------------

func set_tax_level(region_id: String, tax_level: String) -> bool:
	if not Constants.TAX_LEVELS.has(tax_level):
		return false
	state["settlements"][region_id]["tax_level"] = tax_level
	if state["settlements"][region_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "taxes_set")
	return true


func queue_building(region_id: String, chain_id: String) -> bool:
	var queued := ConstructionRules.queue_project(data, state, region_id, chain_id)
	if queued and state["settlements"][region_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "buildings_queued")
		var kind: String = data.chains.get(chain_id, {}).get("kind", "")
		if kind != "":
			GuidedRules.bump(state, "buildings_queued:%s" % kind)
	return queued


func demolish_building(region_id: String, chain_id: String) -> bool:
	return ConstructionRules.demolish(data, state, region_id, chain_id)


func queue_unit(region_id: String, template_id: String) -> bool:
	var queued := RecruitmentRules.queue_unit(data, state, region_id, template_id)
	if queued and state["settlements"][region_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "units_recruited")
	return queued


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
	if moved and state["armies"][army_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "army_moves")
	return moved


func move_fleet(fleet_id: String, to_zone: String) -> bool:
	return MovementRules.move_fleet(data, state, fleet_id, to_zone)


func attack_army(attacker_id: String, defender_id: String) -> Dictionary:
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
	var moved := MovementRules.sea_move_army(data, state, army_id, to_region)
	if moved and state["armies"][army_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "army_moves")
	return moved


func hire_mercenary(army_id: String, template_id: String) -> bool:
	var hired := MercenaryRules.hire(data, state, army_id, template_id)
	if hired and state["armies"][army_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "mercs_hired")
	return hired


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
	return SiegeRules.begin_siege(data, state, army_id, region_id)


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


func raise_army(region_id: String) -> String:
	## The whole garrison marches out as a field army under the best of the
	## house present (the AI musters through its own path). Returns the new
	## army id, or "" — the army moves next turn.
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != state["player_faction"]:
		return ""
	if settlement["garrison"].is_empty():
		return ""
	var general = CharacterRules.best_free_general(data, state, state["player_faction"], region_id)
	var cap := int(data.balance["recruitment"]["army_unit_cap"])
	var army_id := CombatRules.raise_army(data, state, region_id,
		range(mini(settlement["garrison"].size(), cap)), general)
	if army_id != "":
		GuidedRules.bump(state, "armies_raised")
	return army_id


func explore_site(army_id: String) -> Dictionary:
	## Search the point of interest in the army's region. Player armies only —
	## the map's finds are the player's reward for ranging out. Searching
	## spends the rest of the season's movement, and each site yields once,
	## ever. Returns {site, outcome} for the UI, or {} if nothing could be
	## searched.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or army["owner"] != state["player_faction"]:
		return {}
	var site: Dictionary = data.sites_by_region.get(army["region"], {})
	if site.is_empty():
		return {}
	if not state.has("sites_explored"):
		state["sites_explored"] = []
	if state["sites_explored"].has(site["id"]):
		return {}
	if float(army["movement_left"]) <= 0.0:
		return {}

	var rng := _rng()
	var total_weight := 0
	for outcome in site["outcomes"]:
		total_weight += int(outcome["weight"])
	var roll := rng.randi_range(1, total_weight)
	var picked: Dictionary = site["outcomes"][0]
	for outcome in site["outcomes"]:
		roll -= int(outcome["weight"])
		if roll <= 0:
			picked = outcome
			break

	var reward: Dictionary = picked.get("reward", {})
	var faction: Dictionary = state["factions"][army["owner"]]
	faction["treasury"] = int(faction["treasury"]) + int(reward.get("treasury", 0))
	# Found soldiers join the column; past the army cap they muster at home.
	var cap := int(data.balance["recruitment"]["army_unit_cap"])
	var overflow: Array = []
	for grant in reward.get("units", []):
		for i in range(int(grant["count"])):
			if army["units"].size() < cap:
				army["units"].append({
					"template": grant["template"], "experience": 0, "strength_pct": 100,
				})
			else:
				overflow.append({"template": grant["template"], "count": 1})
	if not overflow.is_empty():
		GuidedRules.grant_units_to_capital(state, army["owner"], overflow)
	var experience := int(reward.get("experience", 0))
	if experience > 0:
		var experience_max := int(data.balance["recruitment"]["experience_max"])
		for unit in army["units"]:
			unit["experience"] = mini(int(unit["experience"]) + experience, experience_max)

	state["sites_explored"].append(site["id"])
	army["movement_left"] = 0.0
	GuidedRules.bump(state, "sites_explored")
	state["rng_state"] = rng.state_string()
	return {"site": site, "outcome": picked}


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
