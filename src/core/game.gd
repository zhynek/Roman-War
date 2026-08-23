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
	return MovementRules.move_army(data, state, army_id, to_region, forced_march)


func move_fleet(fleet_id: String, to_zone: String) -> bool:
	return MovementRules.move_fleet(data, state, fleet_id, to_zone)


func attack_army(attacker_id: String, defender_id: String) -> Dictionary:
	var rng := _rng()
	var result := CombatRules.attack_army(data, state, resolver, rng, attacker_id, defender_id)
	state["rng_state"] = rng.state_string()
	return result


func declare_war(other_faction: String, faction_id: String = "") -> bool:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return DiplomacyRules.declare_war(data, state, fid, other_faction)


func set_stance(other_faction: String, stance: String, faction_id: String = "") -> bool:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return DiplomacyRules.set_stance(state, fid, other_faction, stance)


func sea_move_army(army_id: String, to_region: String) -> bool:
	return MovementRules.sea_move_army(data, state, army_id, to_region)


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
	return SiegeRules.begin_siege(data, state, army_id, region_id)


func assault_settlement(army_id: String, region_id: String, occupation: String = "occupy") -> Dictionary:
	var rng := _rng()
	var result := CombatRules.assault_and_capture(
		data, state, rng, resolver, army_id, region_id, occupation)
	state["rng_state"] = rng.state_string()
	return result


func form_army(region_id: String, unit_indices: Array = [], general_id: String = "") -> String:
	## Field garrison units as a marching army; it moves next season.
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != state["player_faction"]:
		return ""
	return ArmyRules.form_army(data, state, region_id, unit_indices, general_id)


func garrison_army(army_id: String) -> bool:
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return false
	return CombatRules.garrison_army(data, state, army_id, army["region"])


## --- Senate (Phase 7) ------------------------------------------------------

func senate_overview() -> Dictionary:
	## Standings, office holders, and the player's current mission.
	var standings: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		if not data.factions.get(faction_id, {}).get("is_roman_house", false):
			continue
		var faction: Dictionary = state["factions"][faction_id]
		standings.append({
			"faction": faction_id, "alive": faction["alive"],
			"senate": float(faction["senate_standing"]),
			"popular": float(faction["popular_standing"]),
			"at_civil_war": faction["at_civil_war"],
		})
	var offices: Array = []
	for entry in SenateRules.office_holders(data, state):
		var character: Dictionary = state["characters"][entry["holder"]]
		offices.append({
			"office": entry["office"],
			"office_name": data.offices.get(entry["office"], {}).get("name", entry["office"]),
			"holder": entry["holder"], "holder_name": character["name"],
			"faction": character["faction"],
		})
	return {
		"senate_alive": state["factions"].has("senate") and state["factions"]["senate"]["alive"],
		"standings": standings,
		"offices": offices,
		"mission": state["factions"][state["player_faction"]]["mission"],
	}


func comply_senate_demand() -> bool:
	## The honorable exit: the leader falls on his sword, the house endures.
	var faction: Dictionary = state["factions"][state["player_faction"]]
	var mission = faction["mission"]
	if mission == null:
		return false
	var template: Dictionary = data.missions.get(mission.get("template", ""), {})
	if String(template.get("kind", "")) != "leader_suicide":
		return false
	var target: String = mission.get("target_char", "")
	if target == "" or not state["characters"].get(target, {}).get("alive", false):
		return false
	CharacterRules.kill(state, target, data)
	return true


## --- Agents & negotiation (Phase 5) ---------------------------------------

func agents_available(region_id: String) -> Array:
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != state["player_faction"]:
		return []
	return AgentRules.available_kinds(data, state, region_id)


func train_agent(region_id: String, kind_id: String) -> String:
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != state["player_faction"]:
		return ""
	var rng := _rng()
	var agent_id := AgentRules.train(data, state, region_id, kind_id, rng)
	state["rng_state"] = rng.state_string()
	return agent_id


func move_agent_towards(agent_id: String, target_region: String) -> String:
	var agent: Dictionary = state.get("agents", {}).get(agent_id, {})
	if agent.is_empty() or agent["owner"] != state["player_faction"]:
		return ""
	return AgentRules.move_towards(data, state, agent_id, target_region)


func dismiss_agent(agent_id: String) -> bool:
	## Strike an agent from the payroll wherever he stands.
	var agent: Dictionary = state.get("agents", {}).get(agent_id, {})
	if agent.is_empty() or agent["owner"] != state["player_faction"]:
		return false
	state["agents"].erase(agent_id)
	return true


func assassinate(agent_id: String, char_id: String) -> Dictionary:
	## Returns {attempted, killed, caught, notices}.
	var agent: Dictionary = state.get("agents", {}).get(agent_id, {})
	if agent.is_empty() or agent["owner"] != state["player_faction"]:
		return {"attempted": false, "killed": false, "caught": false, "notices": []}
	var rng := _rng()
	var notices: Array = []
	var result := AgentRules.assassinate(data, state, rng, agent_id, char_id, notices)
	result["notices"] = notices
	state["rng_state"] = rng.state_string()
	return result


func can_negotiate_with(other_faction: String) -> bool:
	## Treating with a foreign power needs an envoy of ours on their soil.
	return AgentRules.has_envoy_with(data, state, String(state["player_faction"]), other_faction)


func attitude_of(other_faction: String) -> Dictionary:
	## How they regard us: {total, factors}.
	var player := String(state["player_faction"])
	return {
		"total": NegotiationRules.attitude_total(data, state, player, other_faction),
		"factors": NegotiationRules.attitude_breakdown(data, state, player, other_faction),
	}


func propose(other_faction: String, offer: Dictionary) -> Dictionary:
	## Put an offer to a foreign power through our envoy. Offer kinds: peace,
	## trade, alliance, gift, demand_tribute, buy_region — see NegotiationRules.
	if not can_negotiate_with(other_faction):
		return {"accept": false, "reason": "no_envoy"}
	return NegotiationRules.execute(data, state, String(state["player_faction"]), other_faction, offer)


func preview_offer(other_faction: String, offer: Dictionary) -> Dictionary:
	if not can_negotiate_with(other_faction):
		return {"accept": false, "reason": "no_envoy"}
	return NegotiationRules.evaluate(data, state, String(state["player_faction"]), other_faction, offer)


func buyable_regions(other_faction: String) -> Array:
	## Their border towns an envoy could buy, with prices: [{region, price}].
	var offers: Array = []
	for region_id in NegotiationRules.sellable_regions(data, state, String(state["player_faction"]), other_faction):
		offers.append({"region": region_id, "price": NegotiationRules.region_price(data, state, region_id)})
	return offers


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
