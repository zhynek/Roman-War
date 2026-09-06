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
	if not _owns_settlement(region_id):
		return false
	var queued := ConstructionRules.queue_project(data, state, region_id, chain_id)
	if queued:
		GuidedRules.bump(state, "buildings_queued")
		var kind: String = data.chains.get(chain_id, {}).get("kind", "")
		if kind != "":
			GuidedRules.bump(state, "buildings_queued:%s" % kind)
	return queued


func demolish_building(region_id: String, chain_id: String) -> bool:
	if not _owns_settlement(region_id):
		return false
	return ConstructionRules.demolish(data, state, region_id, chain_id)


func queue_unit(region_id: String, template_id: String) -> bool:
	if not _owns_settlement(region_id):
		return false
	var queued := RecruitmentRules.queue_unit(data, state, region_id, template_id)
	if queued:
		GuidedRules.bump(state, "units_recruited")
	return queued


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
## Every relocating order refreshes governorship at once (_after_relocation):
## a general who marches out of his city stops governing it this turn, not
## at the next end of turn.

func move_army(army_id: String, to_region: String, forced_march: bool = false) -> bool:
	_cancel_march(army_id)
	if not _owns_army(army_id):
		return false
	var moved := MovementRules.move_army(data, state, army_id, to_region, forced_march)
	if moved:
		GuidedRules.bump(state, "army_moves")
		_after_relocation()
	return moved


func move_fleet(fleet_id: String, to_zone: String) -> bool:
	if not _owns_force(fleet_id):
		return false
	return MovementRules.move_fleet(data, state, fleet_id, to_zone)


func sail_fleet(fleet_id: String, to_zone: String) -> Dictionary:
	## Multi-lane voyage along the cheapest route (see MovementRules.sail).
	if not _owns_force(fleet_id):
		return {"ok": false, "arrived": false, "path": [], "stopped_at": ""}
	return MovementRules.sail(data, state, fleet_id, to_zone)


func attack_army(attacker_id: String, defender_id: String) -> Dictionary:
	## A battle takes the rest of the season: an army that has marched itself
	## out cannot attack, and no army fights twice in one turn. This is the
	## player's rule; the AI's own path (CombatRules.attack_army) sequences its
	## marches and battles itself — DESIGN §6.3.
	_cancel_march(attacker_id)
	if not _owns_army(attacker_id) or not state["armies"].has(defender_id):
		return {}
	var attacker: Dictionary = state["armies"][attacker_id]
	if float(attacker["movement_left"]) <= 0.0001:
		return {}
	# Striking across the border pays the step into the defender's region,
	# like the march it is (the winner ends up there); a siege laid from next
	# door pays the same. Fighting in the army's own region costs nothing.
	var defender_region := String(state["armies"][defender_id]["region"])
	if defender_region != attacker["region"] \
			and not MovementRules.can_afford_step(data, state, attacker, defender_region):
		return {}
	var rng := _rng()
	var result := CombatRules.attack_army(data, state, resolver, rng, attacker_id, defender_id)
	state["rng_state"] = rng.state_string()
	if not result.is_empty() and state["armies"].has(attacker_id):
		state["armies"][attacker_id]["movement_left"] = 0.0
	_after_relocation()
	return result


func declare_war(other_faction: String, faction_id: String = "") -> bool:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return DiplomacyRules.declare_war(data, state, fid, other_faction)


func set_stance(other_faction: String, stance: String, faction_id: String = "") -> bool:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	if stance == "war" and DiplomacyRules.roman_war_forbidden(data, state, fid, other_faction):
		return false
	if stance != "war" and DiplomacyRules.roman_peace_forbidden(data, state, fid, other_faction):
		return false
	return DiplomacyRules.set_stance(state, fid, other_faction, stance)


func senate_overview() -> Dictionary:
	## The Senate scroll's reading: the houses and their standings, the ladder
	## and who sits on it, the player's own men and what they may stand for,
	## the standing charge, and where the house stands toward the break.
	## Read-only; draws nothing.
	var player := String(state["player_faction"])
	var senate_rules: Dictionary = data.balance["senate"]
	var holders_by_office := {}
	var seats_by_house := {}
	for seat in SenateRules.office_holders(data, state):
		var office_id := String(seat["office"])
		if not holders_by_office.has(office_id):
			holders_by_office[office_id] = []
		holders_by_office[office_id].append({"character": seat["holder"],
			"name": String(state["characters"][seat["holder"]]["name"]), "faction": seat["faction"]})
		seats_by_house[seat["faction"]] = int(seats_by_house.get(seat["faction"], 0)) + 1
	var houses: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var info: Dictionary = data.factions.get(faction_id, {})
		var faction: Dictionary = state["factions"][faction_id]
		if not info.get("is_roman_house", false) or not faction["alive"]:
			continue
		houses.append({"id": faction_id, "name": String(info.get("name", faction_id)),
			"color": String(info.get("color", "#808080")),
			"senate_standing": float(faction["senate_standing"]),
			"popular_standing": float(faction["popular_standing"]),
			"at_civil_war": bool(faction["at_civil_war"]), "outlawed": bool(faction.get("outlawed", false)),
			"seats": int(seats_by_house.get(faction_id, 0))})
	var ladder: Array = []
	var office_list: Array = data.offices.values()
	office_list.sort_custom(func(a, b): return int(a["rank"]) > int(b["rank"]))
	for office in office_list:
		ladder.append({"id": office["id"], "name": office["name"], "rank": int(office["rank"]),
			"seats": int(office["seats"]), "min_age": int(office["min_age"]),
			"holders": holders_by_office.get(office["id"], [])})
	var men: Array = []
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["faction"] != player or not character["alive"] \
				or String(character.get("gender", "male")) != "male" \
				or not ["leader", "heir", "family"].has(String(character["role"])):
			continue
		var eligible: Array = []
		for entry in SenateRules.eligible_offices(data, state, char_id):
			eligible.append({"office": entry["office"], "name": _office_name(entry["office"]),
				"on_ladder": bool(entry["on_ladder"])})
		# The ballot weighs a man without the office he holds today.
		var bare: Dictionary = character.duplicate()
		bare["office"] = null
		men.append({"id": char_id, "name": String(character["name"]), "age": int(character["age"]),
			"influence": CharacterRules.effective(data, bare, "influence"),
			"office": _office_name(character.get("office")), "eligible": eligible})
	var faction: Dictionary = state["factions"][player]
	var charge = null
	var mission = faction.get("mission")
	if mission != null:
		var template: Dictionary = data.missions.get(String(mission["template"]), {})
		var target := String(mission.get("target_character", ""))
		charge = {"name": String(template.get("name", mission["template"])),
			"text": String(template.get("text", "")), "kind": String(template.get("kind", "")),
			"turns_left": int(mission.get("turns_left", 0)),
			"is_demand": String(template.get("kind", "")) == "leader_suicide",
			"can_comply": target != "" and bool(state["characters"].get(target, {}).get("alive", false)),
			"target_name": String(state["characters"].get(target, {}).get("name", "")) if target != "" else ""}
	return {
		"senate_alive": SenateRules.senate_faction(data, state) != "",
		"is_roman_house": bool(data.factions.get(player, {}).get("is_roman_house", false)),
		"houses": houses, "ladder": ladder, "men": men, "charge": charge,
		"at_civil_war": bool(faction["at_civil_war"]), "outlawed": bool(faction.get("outlawed", false)),
		"demand_standing": float(senate_rules["leader_suicide_standing"]),
		"demand_popular": float(senate_rules["leader_suicide_popular_min"]),
		"ambition": float(SocietyRules.faction_stocks(data, faction)["elite_pressure"]),
		"ambition_break": float(data.balance["society"]["elite_civil_war_threshold"]),
	}


func comply_senate_demand() -> bool:
	## The patriarch dies for the house. Succession settles at once; the
	## Senate pays when it next judges the charge. No randomness is drawn.
	var notices: Array = []
	return SenateRules.comply_with_demand(data, state, String(state["player_faction"]), notices)


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
	var moved := MovementRules.sea_move_army(data, state, army_id, to_region)
	if moved:
		GuidedRules.bump(state, "army_moves")
		_after_relocation()
	return moved


func march_army(army_id: String, to_region: String, forced_march: bool = false) -> Dictionary:
	## Plot the cheapest route and set off at once; the remainder resumes each
	## end_turn. The route only ever takes plain move_army steps — combat
	## stays an explicit order — and it is plotted with the owner's own fog,
	## so it cannot navigate around enemies the owner has not seen.
	## -> advance_march's outcome plus cost/turns/blocked_destination; {} when
	## nothing leads toward the destination.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or not _owns_army(army_id):
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
	if int(outcome.get("moved", 0)) > 0:
		GuidedRules.bump(state, "army_moves")
		_after_relocation()
	return outcome


func halt_march(army_id: String) -> bool:
	if not _owns_army(army_id):
		return false
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
	if army.is_empty() or not _owns_army(army_id):
		return {}
	return PathfindingRules.reachable(
		data, state, army_id, -1.0, forced_march, visible_regions(String(army["owner"])))


func army_path_preview(army_id: String, to_region: String, forced_march: bool = false) -> Dictionary:
	## best_path through the owner's fog, without moving anything — the map's
	## hover preview. Route and turns account for a forced march when asked.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or not _owns_army(army_id):
		return {}
	return PathfindingRules.best_path(
		data, state, army_id, to_region, visible_regions(String(army["owner"])), forced_march)


func army_order_preview(army_id: String, to_region: String, forced: bool = false) -> Dictionary:
	return MapOrderRules.preview(data, state, army_id, to_region, forced, visible_regions())


func queued_march_preview(army_id: String) -> Dictionary:
	return MapOrderRules.queued(data, state, army_id, visible_regions())


func hire_mercenary(army_id: String, template_id: String) -> bool:
	if not _owns_army(army_id):
		return false
	var hired := MercenaryRules.hire(data, state, army_id, template_id)
	if hired:
		GuidedRules.bump(state, "mercs_hired")
	return hired


func mercenaries_available(region_id: String) -> Array:
	return MercenaryRules.available(data, state, region_id, String(state["player_faction"]))


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
		var blockers := KnowledgeRules.unmet_prerequisites(data, state, caches, fid, technique)
		entries.append({
			"id": tid,
			"name": technique["name"],
			"domain": technique["domain"],
			"description": String(technique.get("description", "")),
			"stage": entry["stage"],
			"progress": int(entry.get("progress", 0)),
			"turns": int(technique["adoption"]["turns"]),
			"cost": KnowledgeRules.adoption_cost(data, state, fid, tid),
			"ready": blockers.is_empty(),
			"blockers": blockers,
			"effects": technique.get("effects", {}),
			"war": technique.get("war", {}),
			"historical_basis": technique["historical_basis"],
		})
	var faction: Dictionary = state["factions"][fid]
	return {
		"entries": entries,
		"reform_pressure": float(faction.get("reform_pressure", 0.0)),
		"war_record": faction.get("war_record", NewGame.empty_war_record()),
		"war_mood": faction.get("war_mood"),
	}


func begin_adoption(technique_id: String) -> Dictionary:
	return KnowledgeRules.begin_adoption(data, state, String(state["player_faction"]), technique_id)


## --- Battle estimates (RNG-free; see BattleResolver.estimate) ---------------

func battle_estimate(attacker_id: String, defender_id: String) -> Dictionary:
	## The odds of a field battle before it is fought: {} when the two armies
	## cannot come to grips. Reads the same context the battle will use.
	var attacker: Dictionary = state["armies"].get(attacker_id, {})
	var defender: Dictionary = state["armies"].get(defender_id, {})
	if attacker.is_empty() or defender.is_empty() or attacker["owner"] == defender["owner"]:
		return {}
	if attacker["region"] != defender["region"] \
			and not TerrainRules.land_connection(data, attacker["region"], defender["region"]):
		return {}
	return BattleResolver.estimate(data, attacker["units"], defender["units"],
		CombatRules.battle_context(data, state, attacker, defender))


func assault_estimate(army_id: String, region_id: String) -> Dictionary:
	## Odds of storming a settlement this army is besieging; {} otherwise.
	var army: Dictionary = state["armies"].get(army_id, {})
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if army.is_empty() or settlement.is_empty():
		return {}
	var siege = settlement.get("siege")
	if siege == null or siege["besieger"] != army_id:
		return {}
	return BattleResolver.estimate(data, army["units"], settlement["garrison"],
		SiegeRules.assault_context(data, state, army, region_id, false))


func army_summary(army_id: String) -> Dictionary:
	## The army by arm: {units (cards), soldiers, classes: [{class, cards, soldiers, share}], owner}.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return {}
	var summary := ArmyRules.summary(data, army["units"])
	summary["owner"] = army["owner"]
	return summary


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
		"office": _office_name(character.get("office")),
		"offices_held": character.get("offices_held", []).map(func(id): return _office_name(id)),
	}


func _office_name(office_id) -> String:
	if office_id == null or String(office_id) == "":
		return ""
	return String(data.offices.get(String(office_id), {}).get("name", String(office_id)))


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
	if not _owns_army(army_id) or not state["settlements"].has(region_id):
		return false
	var laid := SiegeRules.begin_siege(data, state, army_id, region_id)
	if laid:
		_after_relocation()
	return laid


func assault_settlement(army_id: String, region_id: String, occupation: String = "occupy") -> Dictionary:
	## Storming the walls is a battle like any other: it needs movement left
	## and takes the rest of the season (the turn engine's starve-outs go
	## through SiegeRules directly and are not subject to this).
	_cancel_march(army_id)
	if not _owns_army(army_id) or not state["settlements"].has(region_id):
		return {}
	if float(state["armies"][army_id]["movement_left"]) <= 0.0001:
		return {}
	var rng := _rng()
	var result := SiegeRules.assault(data, state, rng, resolver, army_id, region_id)
	if not result.is_empty() and state["armies"].has(army_id):
		state["armies"][army_id]["movement_left"] = 0.0
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


## --- Regrouping (raise, transfer, merge, split, disband, generals) -----------
## Every action returns {ok, error, ...}; check(action, args) answers "would
## this be legal?" with the same error vocabulary, for greying buttons and
## explaining refusals — see ForceRules and NavalRules.

const _CHECK_ARITY := {
	"raise_army": 2, "transfer_units": 3, "merge_armies": 2, "split_army": 2,
	"disband_unit": 2, "attach_general": 2, "detach_general": 1, "consolidate": 1,
	"launch_fleet": 3, "dock_fleet": 2, "merge_fleets": 2, "split_fleet": 2,
}


func check(action: String, args: Array) -> String:
	## "" when the order would be taken; else an error code (ForceRules.ERR_*,
	## plus wrong_owner / bad_args / unknown_action from the facade itself).
	if not _CHECK_ARITY.has(action):
		return "unknown_action"
	if args.size() < int(_CHECK_ARITY[action]):
		return "bad_args"
	var subject := String(args[0])
	if action in ["raise_army", "launch_fleet"]:
		if not _owns_settlement(subject):
			return ForceRules.ERR_WRONG_OWNER
	elif not _owns_force(subject):
		return ForceRules.ERR_WRONG_OWNER
	match action:
		"raise_army":
			return ForceRules.check_raise_army(data, state, args[0], args[1], args[2] if args.size() > 2 else "")
		"transfer_units":
			return ForceRules.check_transfer_units(data, state, args[0], args[1], args[2])
		"merge_armies":
			return ForceRules.check_merge_armies(data, state, args[0], args[1])
		"split_army":
			return ForceRules.check_split_army(data, state, args[0], args[1], args[2] if args.size() > 2 else "")
		"disband_unit":
			return ForceRules.check_disband_unit(data, state, args[0], int(args[1]))
		"attach_general":
			return ForceRules.check_attach_general(data, state, args[0], args[1])
		"detach_general":
			return ForceRules.check_detach_general(data, state, args[0])
		"consolidate":
			return ForceRules.check_consolidate(data, state, args[0])
		"launch_fleet":
			return NavalRules.check_launch_fleet(data, state, args[0], args[1], args[2])
		"dock_fleet":
			return NavalRules.check_dock_fleet(data, state, args[0], args[1])
		"merge_fleets":
			return NavalRules.check_merge_fleets(data, state, args[0], args[1])
		"split_fleet":
			return NavalRules.check_split_fleet(data, state, args[0], args[1])
	return "unknown_action"


func raise_units(region_id: String, indices: Array, general_id: String = "") -> Dictionary:
	## The ticked garrison units march out as a new army under a captain or a
	## man standing in the city (raise_army below takes the whole garrison).
	if not _owns_settlement(region_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER, "army_id": ""}
	var result := ForceRules.raise_army(data, state, region_id, indices, general_id)
	if result["ok"]:
		GuidedRules.bump(state, "armies_raised")
		_after_relocation()
	return result


func transfer_units(from_id: String, to_id: String, indices: Array) -> Dictionary:
	if not _owns_force(from_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER}
	var result := ForceRules.transfer_units(data, state, from_id, to_id, indices)
	if result["ok"]:
		_after_relocation()
	return result


func merge_armies(from_id: String, into_id: String) -> Dictionary:
	if not _owns_force(from_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER}
	_cancel_march(from_id)
	var result := ForceRules.merge_armies(data, state, from_id, into_id)
	if result["ok"]:
		_after_relocation()
	return result


func split_army(army_id: String, indices: Array, general_choice: String = "") -> Dictionary:
	if not _owns_force(army_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER, "army_id": ""}
	var result := ForceRules.split_army(data, state, army_id, indices, general_choice)
	if result["ok"]:
		_after_relocation()
	return result


func disband_unit(force_id: String, index: int) -> Dictionary:
	if not _owns_force(force_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER, "returned": 0}
	var result := ForceRules.disband_unit(data, state, force_id, index)
	if result["ok"]:
		_after_relocation()
	return result


func attach_general(army_id: String, char_id: String) -> Dictionary:
	if not _owns_force(army_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER}
	var result := ForceRules.attach_general(data, state, army_id, char_id)
	if result["ok"]:
		_after_relocation()
	return result


func detach_general(army_id: String) -> Dictionary:
	if not _owns_force(army_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER}
	var result := ForceRules.detach_general(data, state, army_id)
	if result["ok"]:
		_after_relocation()
	return result


func consolidate_units(force_id: String) -> Dictionary:
	if not _owns_force(force_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER}
	return ForceRules.consolidate(data, state, force_id)


## --- Fleets (launch, dock, merge, split) --------------------------------------

func launch_fleet(region_id: String, indices: Array, zone_id: String) -> Dictionary:
	if not _owns_settlement(region_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER, "fleet_id": ""}
	return NavalRules.launch_fleet(data, state, region_id, indices, zone_id)


func dock_fleet(fleet_id: String, region_id: String) -> Dictionary:
	if not _owns_force(fleet_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER}
	return NavalRules.dock_fleet(data, state, fleet_id, region_id)


func merge_fleets(from_id: String, into_id: String) -> Dictionary:
	if not _owns_force(from_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER}
	return NavalRules.merge_fleets(data, state, from_id, into_id)


func split_fleet(fleet_id: String, indices: Array) -> Dictionary:
	if not _owns_force(fleet_id):
		return {"ok": false, "error": ForceRules.ERR_WRONG_OWNER, "fleet_id": ""}
	return NavalRules.split_fleet(data, state, fleet_id, indices)


func own_ports_on_zone(zone_id: String, faction_id: String = "") -> Array:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return NavalRules.own_ports_on_zone(state, data, fid, zone_id)


func candidate_generals(region_id: String, faction_id: String = "") -> Array:
	var fid := faction_id if faction_id != "" else String(state["player_faction"])
	return ForceRules.candidate_generals(data, state, region_id, fid)


## --- Force queries (banners, the force card, keyboard cycling) ----------------

func force_summary(force_id: String) -> Dictionary:
	## One dictionary describing an army ("army_N"), a fleet ("fleet_N"), a
	## garrison ("garrison:<region>") or a harbour ("harbour:<region>") — see
	## ForceRules.summary.
	return ForceRules.summary(data, state, force_id)


func reachable_regions(army_id: String) -> Dictionary:
	## {reach: {region_id: {cost, forced}}, blocked: {region_id: reason}} for an
	## army, seen through its owner's fog: where it can get this season on its
	## plain budget, where only a forced march reaches, and what bars the way
	## beside them. Nothing the fog hides ever reports a reason.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty() or not _owns_army(army_id):
		return {"reach": {}, "blocked": {}}
	var owner := String(army["owner"])
	var visible := visible_regions(owner)
	var plain := PathfindingRules.reachable(data, state, army_id, -1.0, false, visible)
	var forced := PathfindingRules.reachable(data, state, army_id, -1.0, true, visible)
	var reach := {}
	var region_ids: Array = forced.keys()
	region_ids.sort()
	for region_id in region_ids:
		reach[region_id] = {"cost": float(forced[region_id]), "forced": not plain.has(region_id)}
	var blocked := {}
	var frontier: Array = reach.keys()
	frontier.append(army["region"])
	frontier.sort()
	for region_id in frontier:
		for neighbor in data.regions.get(region_id, {}).get("adjacent", []):
			if reach.has(neighbor) or blocked.has(neighbor):
				continue
			var reason := MovementRules.block_reason(state, owner, String(neighbor), visible.has(neighbor))
			if reason != "":
				blocked[neighbor] = reason
	return {"reach": reach, "blocked": blocked}


func targets_for(army_id: String) -> Dictionary:
	## {region_id: "attack"|"siege"} one of the player's armies can strike
	## from where it stands — nothing for a foreign army, whose reach is its
	## own business behind its own fog.
	if not _owns_army(army_id):
		return {}
	return MovementRules.targets_for(data, state, army_id)


func reachable_zones(fleet_id: String) -> Dictionary:
	## {zone_id: {cost, via}} for the seas one of the player's fleets can
	## reach this season.
	if not _owns_force(fleet_id):
		return {}
	return MovementRules.fleet_reachable(data, state, fleet_id)


func forces_awaiting_orders(faction_id: String = "") -> Array:
	## The player's armies then fleets, numeric id order, that still have
	## movement (a faction_id is accepted for tests and tools; the UI never
	## asks about anyone else).
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


func raise_army(region_id: String) -> String:
	## The whole garrison (up to the stack cap) marches out as a field army
	## under the best of the house present — the same rules, the same
	## movement, as raising ticked units (the AI musters through its own
	## path). Returns the new army id, or "".
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty() or settlement["owner"] != state["player_faction"]:
		return ""
	if settlement["garrison"].is_empty():
		return ""
	var general = CharacterRules.best_free_general(data, state, state["player_faction"], region_id)
	var general_id := String(general) if general != null else ""
	if general_id != "" and not candidate_generals(region_id).has(general_id):
		general_id = ""
	var indices: Array = range(mini(settlement["garrison"].size(), ForceRules.max_units(data)))
	var result := raise_units(region_id, indices, general_id)
	return String(result["army_id"]) if result["ok"] else ""


func guided_enabled() -> bool:
	var guided = state.get("guided")
	return guided is Dictionary and bool(guided.get("enabled", false))


func set_guided(enabled: bool) -> void:
	## The guided mode is a switch, not a campaign setting: off, the trail
	## stops issuing objectives and rewards; on again, it resumes from the
	## stage it had reached. Travels with the save like the rest of the trail.
	if not (state.get("guided") is Dictionary):
		state["guided"] = {"enabled": enabled, "counters": {}, "stages": {}}
	state["guided"]["enabled"] = enabled


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
		GuidedRules.grant_units_to_capital(data, state, army["owner"], overflow)
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


func recruit_profile(region_id: String, template_id: String = "") -> Dictionary:
	## {experience, weapon, armor} a recruit raised (or refitted) here would carry.
	return RecruitmentRules.recruit_profile(data, state, region_id, template_id)


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
		# A general's bodyguard is never trained either: it comes with the man.
		if String(template["class"]) == "general_bodyguard":
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


func known_regions(faction_id: String = "") -> Dictionary:
	return CartographyRules.known_regions(data, state, faction_id if faction_id != "" else String(state["player_faction"]))


func terrain_report(region_id: String, from_region: String = "") -> Dictionary:
	if not known_regions().has(region_id):
		return {}
	var terrain := String(data.regions[region_id]["terrain"])
	return {"terrain": terrain, "movement": PathfindingRules.known_step_cost(data, state, region_id, visible_regions(), from_region),
		"defense": float(data.balance["battle"]["terrain_defense_multiplier"].get(terrain, 1.0)),
		"crossing": TerrainRules.crossing_kind(data, from_region, region_id),
		"observed": visible_regions().has(region_id)}


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
	NewGame.ensure_state_keys(loaded, data)
	# Saves from before harbours existed keep their warships in the garrison;
	# they move to the port now that the unit table is at hand.
	NavalRules.normalise(data, loaded)
	state = loaded
	return true


func _rng() -> CampaignRng:
	return CampaignRng.from_state_string(String(state["rng_state"]))


func _cancel_march(army_id: String) -> void:
	if not _owns_army(army_id):
		return
	## Every explicit order supersedes a queued march — a besieger must not
	## walk away from its own siege next turn because an old road was queued.
	var army: Dictionary = state["armies"].get(army_id, {})
	army.erase("march_path")
	army.erase("march_forced")
func _owns_army(army_id: String) -> bool:
	return state["armies"].get(army_id, {}).get("owner", "") == state["player_faction"]


func _owns_force(force_id: String) -> bool:
	## Armies, fleets, garrisons and harbours alike: an unknown or foreign id
	## is refused (false / {} / wrong_owner), never a script error.
	return ForceRules.exists(state, force_id) \
		and ForceRules.owner_of(state, force_id) == String(state["player_faction"])


func _after_relocation() -> void:
	## Governorship follows presence: a general who marches out of his city
	## stops governing it this turn, not at the next end of turn. Derived
	## value, no randomness involved.
	SettlementRules.refresh_governors(data, state)

	ReconRules.refresh_contacts(data, state)

func _owns_settlement(region_id: String) -> bool:
	return state["settlements"].get(region_id, {}).get("owner", "") == state["player_faction"]


func watchpost_quote(army_id: String) -> Dictionary:
	return ReconRules.post_quote(data, state, army_id)


func build_watchpost(army_id: String) -> Dictionary:
	return ReconRules.build_post(data, state, army_id)
