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
	return DiplomacyRules.declare_war(state, fid, other_faction, data)


func set_stance(other_faction: String, stance: String, faction_id: String = "") -> bool:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return DiplomacyRules.set_stance(state, fid, other_faction, stance)


func sea_move_army(army_id: String, to_region: String) -> bool:
	return MovementRules.sea_move_army(data, state, army_id, to_region)


func hire_mercenary(army_id: String, template_id: String) -> bool:
	return MercenaryRules.hire(data, state, army_id, template_id)


func mercenaries_available(region_id: String) -> Array:
	return MercenaryRules.available(data, state, region_id)


## --- Agents ------------------------------------------------------------------

func agent_kinds_available(region_id: String) -> Array:
	return AgentRules.kinds_available(data, state, region_id)


func recruit_agent(region_id: String, kind_id: String) -> String:
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != state["player_faction"]:
		return ""
	var rng := _rng()
	var agent_id := AgentRules.recruit(data, state, rng, region_id, kind_id)
	state["rng_state"] = rng.state_string()
	return agent_id


func agents_in(region_id: String, owner: String = "") -> Array:
	return AgentRules.agents_in(state, region_id, owner)


func move_agent(agent_id: String, to_region: String) -> bool:
	if not _own_agent(agent_id):
		return false
	return AgentRules.move(data, state, agent_id, to_region)


func sea_move_agent(agent_id: String, to_region: String) -> bool:
	if not _own_agent(agent_id):
		return false
	return AgentRules.sea_move(data, state, agent_id, to_region)


func can_open_gates(agent_id: String) -> bool:
	return _own_agent(agent_id) and AgentRules.can_open_gates(data, state, agent_id)


func open_gates(agent_id: String) -> Dictionary:
	if not _own_agent(agent_id):
		return {}
	var rng := _rng()
	var result := AgentRules.open_gates(data, state, rng, agent_id)
	state["rng_state"] = rng.state_string()
	return result


func assassination_targets(agent_id: String) -> Array:
	return AgentRules.assassination_targets(data, state, agent_id) if _own_agent(agent_id) else []


func assassinate(agent_id: String, target_id: String) -> Dictionary:
	if not _own_agent(agent_id):
		return {}
	var rng := _rng()
	var result := AgentRules.assassinate(data, state, rng, agent_id, target_id)
	state["rng_state"] = rng.state_string()
	return result


func sabotage_targets(agent_id: String) -> Array:
	return AgentRules.sabotage_targets(data, state, agent_id) if _own_agent(agent_id) else []


func sabotage(agent_id: String, chain_id: String) -> Dictionary:
	if not _own_agent(agent_id):
		return {}
	var rng := _rng()
	var result := AgentRules.sabotage(data, state, rng, agent_id, chain_id)
	state["rng_state"] = rng.state_string()
	return result


func bribe_army_cost(agent_id: String, army_id: String) -> int:
	return AgentRules.bribe_army_cost(data, state, agent_id, army_id) if _own_agent(agent_id) else -1


func bribe_army(agent_id: String, army_id: String) -> Dictionary:
	return AgentRules.bribe_army(data, state, agent_id, army_id) if _own_agent(agent_id) else {}


func bribe_settlement_cost(agent_id: String) -> int:
	return AgentRules.bribe_settlement_cost(data, state, agent_id) if _own_agent(agent_id) else -1


func bribe_settlement(agent_id: String) -> Dictionary:
	return AgentRules.bribe_settlement(data, state, agent_id) if _own_agent(agent_id) else {}


func factions_in_contact(agent_id: String) -> Array:
	return AgentRules.factions_in_contact(data, state, agent_id) if _own_agent(agent_id) else []


func dismiss_agent(agent_id: String) -> bool:
	return _own_agent(agent_id) and AgentRules.dismiss(state, agent_id)


func _own_agent(agent_id: String) -> bool:
	return state["agents"].get(agent_id, {}).get("owner", "") == state["player_faction"]


## --- Diplomacy ------------------------------------------------------------------

func best_envoy(other_faction: String, faction_id: String = "") -> String:
	## Our most skilled envoy in contact with the other power, or "".
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return AgentRules.best_envoy(data, state, fid, other_faction)


func attitude_of(other_faction: String, faction_id: String = "") -> Dictionary:
	## How the other power regards us: {total, label, factors}.
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	var factors := DiplomacyRules.attitude_breakdown(data, state, other_faction, fid)
	var total := 0.0
	for factor in factors:
		total += float(factor["value"])
	return {"total": total, "label": DiplomacyRules.attitude_label(data, total), "factors": factors}


func evaluate_proposal(proposal: Dictionary) -> Dictionary:
	## Preview an offer's balance without making it. Fills in the proposer and
	## the best envoy in contact when the caller leaves them out.
	return DiplomacyRules.evaluate(data, state, _complete_proposal(proposal))


func propose(proposal: Dictionary) -> Dictionary:
	## Make an offer through an envoy in contact with the other court and free
	## to speak this season. Without one there are no talks, whatever the
	## terms — except ending a treaty of ours, which needs nobody's consent.
	var full := _complete_proposal(proposal)
	var envoy_id: String = full.get("envoy", "")
	if envoy_id == "" and not _is_dissolution(full):
		var verdict := DiplomacyRules.evaluate(data, state, full)
		if verdict["reason"] != "":
			return {"accepted": false, "score": 0.0, "factors": [], "reason": verdict["reason"]}
		return {"accepted": false, "score": 0.0, "factors": [],
			"reason": "No envoy of ours is in contact with that court and free to speak this season."}
	if envoy_id != "" and not AgentRules.can_act(state["agents"].get(envoy_id, {})):
		return {"accepted": false, "score": 0.0, "factors": [],
			"reason": "Our envoy has already spoken this season."}
	return DiplomacyRules.propose(data, state, full)


func _is_dissolution(proposal: Dictionary) -> bool:
	## Ending our own trade rights, alliance or protectorate, asking nothing.
	if proposal.get("stance", "") != "neutral":
		return false
	var current := DiplomacyRules.stance_between(state, proposal["from"], proposal.get("to", ""))
	if current not in ["trade", "alliance", "protectorate"]:
		return false
	return int(proposal.get("demand", 0)) <= 0 and int(proposal.get("tribute_demanded_per_turn", 0)) <= 0 \
		and proposal.get("regions_demanded", []).is_empty()


func _complete_proposal(proposal: Dictionary) -> Dictionary:
	## The player speaks only for the player's house, whatever the dictionary
	## says; an AI entry point can supply its own proposer later.
	var full := proposal.duplicate(true)
	full["from"] = state["player_faction"]
	if not full.has("envoy") or full["envoy"] == "":
		full["envoy"] = AgentRules.best_envoy(data, state, full["from"], full.get("to", ""))
	return full


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
		"security": AgentRules.character_security(data, state, char_id),
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
