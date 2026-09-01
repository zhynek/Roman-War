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
## Every player action verifies ownership first: the facade is the UI, test
## and mod surface, and must never let "player" input drive another faction's
## pieces (that would also perturb the deterministic simulation).

func set_tax_level(region_id: String, tax_level: String) -> bool:
	if not _owns_settlement(region_id) or not Constants.TAX_LEVELS.has(tax_level):
		return false
	state["settlements"][region_id]["tax_level"] = tax_level
	if state["settlements"][region_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "taxes_set")
	return true


func set_edict(region_id: String, edict_id: String) -> bool:
	## Issue the province's one standing order. It takes a few turns to take
	## hold — see EdictRules — which is fast against stocks that move over
	## decades, but is not a switch.
	return EdictRules.issue(data, state, region_id, edict_id)


func revoke_edict(region_id: String) -> bool:
	## Immediate, and followed by a cooldown. Whatever the edict moved decays at
	## its own pace: stopping the corn dole does not unmake the expectation.
	return EdictRules.revoke(data, state, region_id)


func available_edicts(region_id: String) -> Array:
	return EdictRules.available(data, state, region_id)


func edict_status(region_id: String) -> Dictionary:
	return EdictRules.status(data, state, region_id)


func queue_building(region_id: String, chain_id: String) -> bool:
	var queued := ConstructionRules.queue_project(data, state, region_id, chain_id)
	if queued and state["settlements"][region_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "buildings_queued")
		var kind: String = data.chains.get(chain_id, {}).get("kind", "")
		if kind != "":
			GuidedRules.bump(state, "buildings_queued:%s" % kind)
	return queued
	if not _owns_settlement(region_id):
		return false
	return ConstructionRules.queue_project(data, state, region_id, chain_id)


func demolish_building(region_id: String, chain_id: String) -> bool:
	if not _owns_settlement(region_id):
		return false
	return ConstructionRules.demolish(data, state, region_id, chain_id)


func queue_unit(region_id: String, template_id: String) -> bool:
	var queued := RecruitmentRules.queue_unit(data, state, region_id, template_id)
	if queued and state["settlements"][region_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "units_recruited")
	return queued
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
	_cancel_march(army_id)
	if not _owns_army(army_id):
		return false
	return MovementRules.move_army(data, state, army_id, to_region, forced_march)
	var moved := MovementRules.move_army(data, state, army_id, to_region, forced_march)
	if moved and state["armies"][army_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "army_moves")
	return moved


func move_fleet(fleet_id: String, to_zone: String) -> bool:
	if state["fleets"].get(fleet_id, {}).get("owner", "") != state["player_faction"]:
		return false
	return MovementRules.move_fleet(data, state, fleet_id, to_zone)


func attack_army(attacker_id: String, defender_id: String) -> Dictionary:
	_cancel_march(attacker_id)
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
	_cancel_march(army_id)
	if not _owns_army(army_id):
		return false
	return MovementRules.sea_move_army(data, state, army_id, to_region)
	var moved := MovementRules.sea_move_army(data, state, army_id, to_region)
	if moved and state["armies"][army_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "army_moves")
	return moved


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
	var hired := MercenaryRules.hire(data, state, army_id, template_id)
	if hired and state["armies"][army_id]["owner"] == state["player_faction"]:
		GuidedRules.bump(state, "mercs_hired")
	return hired
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


## The faction-scoped edict facade that lived here (edict_overview /
## enact_edict / repeal_edict, and a Book of Policies for the whole house)
## belonged to the other edicts engine. main holds edicts PER PROVINCE — see
## the province facade below and EdictRules.issue/revoke/status — so there is
## no faction-wide ledger for those methods to read.


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
	_cancel_march(army_id)
	if not _owns_army(army_id):
		return false
	return SiegeRules.begin_siege(data, state, army_id, region_id)


func assault_settlement(army_id: String, region_id: String, occupation: String = "occupy") -> Dictionary:
	_cancel_march(army_id)
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
	_cancel_march(army_id)
	var army: Dictionary = state["armies"][army_id]
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


func growth_breakdown(region_id: String) -> Array:
	return GrowthRules.breakdown(data, state, region_id)


func order_breakdown(region_id: String) -> Array:
	return PublicOrderRules.breakdown(data, state, region_id)


func income_breakdown(region_id: String) -> Array:
	return EconomyRules.settlement_income_breakdown(data, state, region_id)


func society_breakdown(region_id: String) -> Array:
	## The three provincial stocks, as the player is entitled to see them: exact
	## where the province is well administered, a stale rounded survey where it is
	## not, and nothing but the word "restive" where it is barely governed at all.
	return LegibilityRules.reported_breakdown(data, state, region_id)


func society_report(region_id: String) -> Dictionary:
	## The full reading behind society_breakdown, including how stale it is.
	return LegibilityRules.reported(data, state, region_id)


func strain_reading(region_id: String) -> Dictionary:
	## The comparison the whole model turns on, put in front of the player:
	## what the province is asked to bear, what it grants willingly, and the
	## remainder that has to be coerced — which is what charges Grievance.
	## `coerced` is null where you cannot see the province well enough to know.
	var report := LegibilityRules.reported(data, state, region_id)
	var asked := SocietyRules.load_total(data, state, region_id)
	var granted = report.get("legitimacy")
	return {
		"asked": asked,
		"granted": granted,
		"coerced": null if granted == null else maxf(0.0, asked - float(granted)),
	}


func load_breakdown(region_id: String) -> Array:
	## What the province is being asked to bear. Whatever this exceeds its
	## Standing by has to be coerced, and the coerced share charges Grievance.
	return SocietyRules.load_breakdown(data, state, region_id)


func legitimacy_target_breakdown(region_id: String) -> Array:
	## Where Standing is heading, which is not where it is — a province takes a
	## generation to become what you have built it to be.
	return SocietyRules.legitimacy_target_breakdown(data, state, region_id)


func clarity(region_id: String) -> float:
	return LegibilityRules.clarity(data, state, region_id)


func faction_society(faction_id: String = "") -> Array:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return SocietyRules.faction_breakdown(data, state, fid)


func advances(faction_id: String = "") -> Array:
	## Advances currently held. Craft that stops being taught is lost again, so
	## this can shrink.
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	var held: Array = []
	for advance_id in AdvanceRules.held(state, fid):
		var advance: Dictionary = data.advances.get(advance_id, {})
		held.append({"id": advance_id, "name": advance.get("name", advance_id),
			"description": advance.get("description", "")})
	return held


func society_pattern(pattern_id: String) -> Dictionary:
	## The historical mechanism a crisis illustrates, for the turn log and codex.
	for pattern in data.society.get("patterns", []):
		if pattern["id"] == pattern_id:
			return pattern
	return {}


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
func day_beats(faction_id: String = "") -> Array:
	## The turn just resolved, as this faction is entitled to know it.
	var viewer := faction_id if faction_id != "" else String(state["player_faction"])
	return DispatchRules.visible_beats(data, state, TurnJournal.of(state), viewer)
func building_chains(region_id: String) -> Array:
	return BuildingInfo.chain_list(data, state, region_id)


func building_dossier(region_id: String, chain_id: String) -> Dictionary:
	return BuildingInfo.dossier(data, state, region_id, chain_id)


func recruitable_units(region_id: String) -> Array:
	return BuildingInfo.unit_list(data, state, region_id)


func unit_dossier(region_id: String, template_id: String) -> Dictionary:
	return BuildingInfo.unit_dossier(data, state, region_id, template_id)


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


func _cancel_march(army_id: String) -> void:
	## Every explicit order supersedes a queued march — a besieger must not
	## walk away from its own siege next turn because an old road was queued.
	var army: Dictionary = state["armies"].get(army_id, {})
	army.erase("march_path")
	army.erase("march_forced")
func _owns_army(army_id: String) -> bool:
	return state["armies"].get(army_id, {}).get("owner", "") == state["player_faction"]


func _owns_settlement(region_id: String) -> bool:
	return state["settlements"].get(region_id, {}).get("owner", "") == state["player_faction"]
