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
## Every player action verifies ownership first: the facade is the UI, test
## and mod surface, and must never let "player" input drive another faction's
## pieces (that would also perturb the deterministic simulation).

func set_tax_level(region_id: String, tax_level: String) -> bool:
	if not _owns_settlement(region_id) or not Constants.TAX_LEVELS.has(tax_level):
		return false
	state["settlements"][region_id]["tax_level"] = tax_level
	return true


func queue_building(region_id: String, chain_id: String) -> bool:
	if not _owns_settlement(region_id):
		return false
	return ConstructionRules.queue_project(data, state, region_id, chain_id)


func demolish_building(region_id: String, chain_id: String) -> bool:
	if not _owns_settlement(region_id):
		return false
	return ConstructionRules.demolish(data, state, region_id, chain_id)


func queue_unit(region_id: String, template_id: String) -> bool:
	if not _owns_settlement(region_id):
		return false
	return RecruitmentRules.queue_unit(data, state, region_id, template_id)


func retrain_garrison(region_id: String) -> int:
	if not _owns_settlement(region_id):
		return 0
	return RecruitmentRules.retrain_garrison(data, state, region_id)


func move_capital(region_id: String) -> bool:
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != state["player_faction"]:
		return false
	state["factions"][state["player_faction"]]["capital"] = region_id
	return true


## --- Army actions --------------------------------------------------------

func move_army(army_id: String, to_region: String, forced_march: bool = false) -> bool:
	if not _owns_army(army_id):
		return false
	return MovementRules.move_army(data, state, army_id, to_region, forced_march)


func move_fleet(fleet_id: String, to_zone: String) -> bool:
	if state["fleets"].get(fleet_id, {}).get("owner", "") != state["player_faction"]:
		return false
	return MovementRules.move_fleet(data, state, fleet_id, to_zone)


func attack_army(attacker_id: String, defender_id: String) -> Dictionary:
	if not _owns_army(attacker_id):
		return {}
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


## --- Diplomacy (Phase 5) ---------------------------------------------------

func attitude_of(other_faction: String) -> Array:
	## How the other faction currently feels about the player, as named factors.
	return DiplomacyRules.attitude_breakdown(data, state, other_faction, String(state["player_faction"]))


func preview_offer(offer: Dictionary) -> Dictionary:
	## Price an offer without proposing it — the negotiation dialog's live hint.
	offer["from"] = String(state["player_faction"])
	if not state["factions"].get(offer.get("to", ""), {}).get("alive", false):
		return {"accept": false, "score": 0.0, "breakdown": [], "vetoes": ["their_court_is_ashes"]}
	return DiplomacyRules.evaluate_offer(data, state, offer["from"], offer["to"], offer)


func propose_offer(offer: Dictionary) -> Dictionary:
	## Put the offer to the other side; it takes effect at once if accepted.
	offer["from"] = String(state["player_faction"])
	if not state["factions"].get(offer.get("to", ""), {}).get("alive", false):
		return {"accept": false, "score": 0.0, "breakdown": [], "vetoes": ["their_court_is_ashes"]}
	var verdict := DiplomacyRules.evaluate_offer(data, state, offer["from"], offer["to"], offer)
	if verdict["accept"]:
		DiplomacyRules.apply_offer(data, state, offer)
	return verdict


func pending_offers() -> Array:
	## Offers other factions have laid before the player, oldest first — only
	## those that still stand (the proposer alive, solvent, and not at a war
	## begun since the envoy set out).
	var mine: Array = []
	for offer in state["pending_offers"]:
		if offer.get("to", "") == state["player_faction"] \
				and DiplomacyRules.offer_still_stands(data, state, offer):
			mine.append(offer)
	return mine


func respond_offer(offer_id: String, accept: bool) -> bool:
	## Returns true when the offer was applied (or declined); false when it was
	## found but no longer stands — the envoy has quietly withdrawn.
	for i in range(state["pending_offers"].size()):
		var offer: Dictionary = state["pending_offers"][i]
		if offer.get("id", "") != offer_id or offer.get("to", "") != state["player_faction"]:
			continue
		state["pending_offers"].remove_at(i)
		if accept:
			if not DiplomacyRules.offer_still_stands(data, state, offer):
				return false
			DiplomacyRules.apply_offer(data, state, offer)
		return true
	return false


func sea_move_army(army_id: String, to_region: String) -> bool:
	if not _owns_army(army_id):
		return false
	return MovementRules.sea_move_army(data, state, army_id, to_region)


func hire_mercenary(army_id: String, template_id: String) -> bool:
	if not _owns_army(army_id):
		return false
	return MercenaryRules.hire(data, state, army_id, template_id)


func mercenaries_available(region_id: String) -> Array:
	return MercenaryRules.available(data, state, region_id)


## --- Agents (Phase 5) ------------------------------------------------------

func recruit_agent(region_id: String, kind: String) -> String:
	if state["settlements"].get(region_id, {}).get("owner", "") != state["player_faction"]:
		return ""
	return AgentRules.recruit_agent(data, state, region_id, kind)


func move_agent(agent_id: String, to_region: String) -> bool:
	if state["agents"].get(agent_id, {}).get("owner", "") != state["player_faction"]:
		return false
	return AgentRules.move_agent(data, state, agent_id, to_region)


func agent_scout(agent_id: String) -> Dictionary:
	return AgentRules.scout_report(data, state, agent_id)


func agent_assassinate(agent_id: String, target_char_id: String) -> Dictionary:
	if state["agents"].get(agent_id, {}).get("owner", "") != state["player_faction"]:
		return {}
	var rng := _rng()
	var result := AgentRules.assassinate(data, state, rng, agent_id, target_char_id)
	state["rng_state"] = rng.state_string()
	return result


func agent_bribe(agent_id: String, army_id: String) -> Dictionary:
	if state["agents"].get(agent_id, {}).get("owner", "") != state["player_faction"]:
		return {}
	return AgentRules.bribe_army(data, state, agent_id, army_id)


func agent_steal_technique(agent_id: String, technique_id: String) -> Dictionary:
	if state["agents"].get(agent_id, {}).get("owner", "") != state["player_faction"]:
		return {}
	var rng := _rng()
	var result := AgentRules.steal_technique(data, state, rng, agent_id, technique_id)
	state["rng_state"] = rng.state_string()
	return result


func agents_in(region_id: String) -> Array:
	## Agents standing in a region, sorted by id — [{id, agent}] for the UI.
	var found: Array = []
	var agent_ids: Array = state["agents"].keys()
	agent_ids.sort()
	for agent_id in agent_ids:
		if state["agents"][agent_id]["region"] == region_id:
			found.append({"id": agent_id, "agent": state["agents"][agent_id]})
	return found


## --- Knowledge (Phase 6) ---------------------------------------------------

func technique_overview(faction_id: String = "") -> Dictionary:
	## Everything the knowledge panel shows for one court: what it practices,
	## what its craftsmen are institutionalizing, what it merely knows of (with
	## the price of taking it up), and the reform pressure on its arsenal.
	## Fog of knowledge: only techniques in the faction's own ledger appear.
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	if not state["factions"].has(fid):
		return {"entries": [], "reform_pressure": 0.0}
	var caches := KnowledgeRules.build_caches(data, state, false)
	var knowledge := KnowledgeRules.knowledge_of(state, fid)
	var entries: Array = []
	var tids: Array = knowledge.keys()
	tids.sort()
	for tid in tids:
		var technique: Dictionary = data.techniques.get(tid, {})
		if technique.is_empty():
			continue
		var entry: Dictionary = knowledge[tid]
		entries.append({
			"id": tid,
			"name": technique["name"],
			"domain": technique["domain"],
			"stage": entry["stage"],
			"progress": int(entry.get("progress", 0)),
			"turns": int(technique["adoption"]["turns"]),
			"cost": KnowledgeRules.adoption_cost(data, state, fid, tid),
			"ready": KnowledgeRules.prerequisites_met(data, state, caches, fid, technique),
			"effects": technique.get("effects", {}),
			"historical_basis": technique["historical_basis"],
		})
	return {
		"entries": entries,
		"reform_pressure": float(state["factions"][fid].get("reform_pressure", 0.0)),
	}


func begin_adoption(technique_id: String) -> Dictionary:
	return KnowledgeRules.begin_adoption(data, state, String(state["player_faction"]), technique_id)


## --- Edicts (Phase 6) -------------------------------------------------------

func edict_overview() -> Dictionary:
	## The book of policies: what the court holds (with its cost per turn) and
	## everything it could hold, each priced with the first bar named.
	var fid := String(state["player_faction"])
	var held: Dictionary = EdictRules.enacted(state, fid)
	var held_entries: Array = []
	var edict_ids: Array = held.keys()
	edict_ids.sort()
	for eid in edict_ids:
		held_entries.append({"id": eid, "edict": data.edicts.get(eid, {})})
	return {
		"held": held_entries,
		"available": EdictRules.available(data, state, fid),
		"upkeep": EdictRules.upkeep(data, state, fid),
		"max_enacted": int(data.balance["edicts"]["max_enacted"]),
	}


func enact_edict(edict_id: String) -> Dictionary:
	return EdictRules.enact(data, state, String(state["player_faction"]), edict_id)


func repeal_edict(edict_id: String) -> bool:
	return EdictRules.repeal(data, state, String(state["player_faction"]), edict_id)


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
	var epithet_id := String(character.get("epithet", ""))
	return {
		"id": char_id,
		"name": character["name"],
		"epithet": String(data.epithets.get(epithet_id, {}).get("name", "")) if epithet_id != "" else "",
		"deeds": character.get("deeds", {}),
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
	if not _owns_army(army_id):
		return false
	return SiegeRules.begin_siege(data, state, army_id, region_id)


func assault_settlement(army_id: String, region_id: String, occupation: String = "occupy") -> Dictionary:
	if not _owns_army(army_id):
		return {}
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
	if not _owns_army(army_id):
		return false
	var army: Dictionary = state["armies"][army_id]
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
	NewGame.ensure_state_keys(loaded, data)
	state = loaded
	return true


func _rng() -> CampaignRng:
	return CampaignRng.from_state_string(String(state["rng_state"]))


func _owns_army(army_id: String) -> bool:
	return state["armies"].get(army_id, {}).get("owner", "") == state["player_faction"]


func _owns_settlement(region_id: String) -> bool:
	return state["settlements"].get(region_id, {}).get("owner", "") == state["player_faction"]
