class_name AiRules
## Non-player faction behaviour. Deliberately bounded: this is the smallest AI
## that makes a turn worth watching, not the full Phase 6 opponent.
##
## Each faction, in sorted id order, does four things:
##   1. keeps a token garrison and builds the cheapest useful project
##   2. storms a city it has already invested, once the rams are ready
##   3. marches on a weaker hostile neighbour and lays siege
##   4. occasionally declares war on a weak neighbour it is not bound to
##
## Deliberately NOT here, and left to the real AI phase: economic planning
## beyond cheapest-first, diplomatic negotiation, naval and fleet behaviour,
## agents, coordinated multi-army operations, defensive stacking, and any
## notion of strategy longer than one turn.
##
## Determinism: every loop sorts its keys, every tie breaks on sorted id, and
## every roll goes through the CampaignRng the turn engine passes in. A loaded
## save must replay exactly, so nothing here may read wall-clock time or an
## unsorted dictionary.


static func take_turn(data: GameData, state: Dictionary, faction_id: String,
		rng: CampaignRng, resolver: BattleResolver, journal: Array) -> void:
	var faction: Dictionary = state["factions"][faction_id]
	if not faction["alive"]:
		return
	_manage_settlements(data, state, faction_id)
	_storm_invested_cities(data, state, faction_id, rng, resolver, journal)
	_march(data, state, faction_id, rng, resolver, journal)
	_consider_war(data, state, faction_id, rng, journal)


## --- 1. Settlements -------------------------------------------------------

static func _manage_settlements(data: GameData, state: Dictionary, faction_id: String) -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	var faction: Dictionary = state["factions"][faction_id]
	var garrison_target := int(ai_rules["garrison_target"])
	var army_cap := int(ai_rules["field_army_max_units"])
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] != faction_id:
			continue

		# A field army resting in one of our cities draws on it. Without this an
		# AI army is whatever it started the campaign as, forever — it takes
		# casualties and never replaces them, so the map stops moving after the
		# first few conquests. The walls are manned first, the column second.
		var army_id := _own_army_in(state, faction_id, region_id)
		var wants_men := garrison_target
		if army_id != "" and state["armies"][army_id]["units"].size() < army_cap:
			wants_men += 1

		if settlement["garrison"].size() < wants_men and settlement["recruitment_queue"].is_empty():
			var cheapest := {}
			for unit in RecruitmentRules.available_units(data, state, region_id):
				if cheapest.is_empty() or int(unit["cost"]) < int(cheapest["cost"]):
					cheapest = unit
			if not cheapest.is_empty() and int(faction["treasury"]) > int(cheapest["cost"]) + 2000:
				RecruitmentRules.queue_unit(data, state, region_id, cheapest["id"])

		if army_id != "":
			_reinforce_from_garrison(state, settlement, army_id, garrison_target, army_cap)

		if settlement["construction_queue"].is_empty():
			var best := {}
			for project in ConstructionRules.available_projects(data, state, region_id):
				if best.is_empty() or int(project["cost"]) < int(best["cost"]):
					best = project
			if not best.is_empty() and int(faction["treasury"]) > int(best["cost"]) + 1000:
				ConstructionRules.queue_project(data, state, region_id, best["chain"])


static func _reinforce_from_garrison(state: Dictionary, settlement: Dictionary,
		army_id: String, garrison_target: int, army_cap: int) -> void:
	## Everything above the token garrison marches out with the column. The
	## walls keep their minimum; the surplus is what the army is for.
	var army: Dictionary = state["armies"][army_id]
	while settlement["garrison"].size() > garrison_target and army["units"].size() < army_cap:
		army["units"].append(settlement["garrison"].pop_back())


static func _own_army_in(state: Dictionary, faction_id: String, region_id: String) -> String:
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()  # the first by id, so which army is fed never varies
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army["owner"] == faction_id and String(army["region"]) == region_id:
			return army_id
	return ""


## --- 2. Storming a city already under siege --------------------------------

static func _storm_invested_cities(data: GameData, state: Dictionary, faction_id: String,
		rng: CampaignRng, resolver: BattleResolver, journal: Array) -> void:
	var ratio := float(data.balance["ai"]["assault_strength_ratio"])
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		var siege = settlement["siege"]
		if siege == null or not bool(siege["equipment_ready"]):
			continue
		var army_id: String = String(siege["besieger"])
		if not state["armies"].has(army_id) or state["armies"][army_id]["owner"] != faction_id:
			continue
		var attackers := CombatRules.soldiers_in(data, state["armies"][army_id]["units"])
		var defenders := CombatRules.soldiers_in(data, settlement["garrison"])
		if float(attackers) < float(defenders) * ratio:
			continue

		var defender_faction: String = String(settlement["owner"])
		var result := SiegeRules.assault(data, state, rng, resolver, army_id, region_id)
		if result.is_empty():
			continue
		# A storm makes reputations on both sides of the wall, and the defender
		# may well be the player's own governor.
		for notice in result.get("character_notices", []):
			TurnJournal.add_character_notice(state, journal, notice)
		TurnJournal.add(journal, "battle_fought", {
			"faction": faction_id, "other": defender_faction, "region": region_id,
			"extra": {"assault": true, "won": result.get("captured", false)},
		})
		if result.get("captured", false):
			CombatRules.capture_settlement(data, state, rng, region_id, faction_id, "occupy")
			CombatRules.fire_occupation_triggers(
				data, state, rng, result.get("besieger_general"), "occupy", [])
			TurnJournal.add(journal, "settlement_captured", {
				"faction": faction_id, "other": defender_faction, "region": region_id,
				"extra": {"occupation": "occupy"},
			})


## --- 3. Marching ----------------------------------------------------------

static func _march(data: GameData, state: Dictionary, faction_id: String,
		rng: CampaignRng, resolver: BattleResolver, journal: Array) -> void:
	var ai_rules: Dictionary = data.balance["ai"]
	var strength_ratio := float(ai_rules["march_strength_ratio"])
	var marches_left := int(ai_rules["max_marches_per_turn"])

	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		if marches_left <= 0:
			return
		if not state["armies"].has(army_id):
			continue  # destroyed by an earlier engagement this same turn
		var army: Dictionary = state["armies"][army_id]
		if army["owner"] != faction_id or float(army["movement_left"]) <= 0.0:
			continue
		# An army already investing a city stays where it is.
		if _is_besieging(state, army_id):
			continue

		var soldiers := CombatRules.soldiers_in(data, army["units"])
		if soldiers <= 0:
			continue

		# A hostile army in the way is fought first — you cannot invest a city
		# with an enemy column standing between you and its walls.
		var enemy_army := _weakest_hostile_army(data, state, faction_id, String(army["region"]))
		if enemy_army != "":
			var enemy: Dictionary = state["armies"][enemy_army]
			if float(soldiers) >= float(CombatRules.soldiers_in(data, enemy["units"])) * strength_ratio:
				var defender: String = String(enemy["owner"])
				var where: String = String(enemy["region"])
				var result := CombatRules.attack_army(
					data, state, resolver, rng, army_id, enemy_army)
				if not result.is_empty():
					for notice in result.get("character_notices", []):
						TurnJournal.add_character_notice(state, journal, notice)
					marches_left -= 1
					TurnJournal.add(journal, "battle_fought", {
						"faction": faction_id, "other": defender, "region": where,
						"value": soldiers,
						"extra": {"assault": false, "won": result.get("winner", "") == "attacker"},
					})
					continue

		# Otherwise, the weakest enemy city we can reasonably storm.
		var target := _weakest_hostile_neighbour(data, state, faction_id, String(army["region"]))
		if target == "":
			# Nothing hostile next door. Take one step toward a war that is
			# further off, through our own or neutral ground. This is the whole
			# of the AI's ambition — one step, re-decided every turn — but it is
			# what keeps a faction from sitting still once it has eaten the
			# rebels on its doorstep.
			var step := _approach_step(data, state, faction_id, army_id, soldiers)
			if step != "" and MovementRules.move_army(data, state, army_id, step):
				marches_left -= 1
				TurnJournal.add(journal, "army_march", {
					"faction": faction_id, "region": step, "value": soldiers,
					"extra": {"from": String(army["region"])},
				})
			continue
		var garrison := CombatRules.soldiers_in(data, state["settlements"][target]["garrison"])
		if float(soldiers) < float(garrison) * strength_ratio:
			continue

		var from_region: String = String(army["region"])
		var besieged: String = String(state["settlements"][target]["owner"])
		# begin_siege handles adjacency and spends the army's movement. It is
		# NOT a MovementRules.move_army: entering a hostile region is an act of
		# war, which move_army refuses by design.
		if not SiegeRules.begin_siege(data, state, army_id, target):
			continue
		marches_left -= 1
		TurnJournal.add(journal, "army_march", {
			"faction": faction_id, "other": besieged, "region": target,
			"value": soldiers, "extra": {"from": from_region},
		})
		TurnJournal.add(journal, "siege_begun", {
			"faction": faction_id, "other": besieged, "region": target,
			"value": soldiers, "extra": {"garrison": garrison},
		})


static func _approach_step(data: GameData, state: Dictionary, faction_id: String,
		army_id: String, soldiers: int) -> String:
	## The neighbouring region that shortens the road to the nearest enemy city
	## this army could plausibly take. Returns "" when there is nothing worth
	## walking to, or no legal step toward it.
	var ai_rules: Dictionary = data.balance["ai"]
	var ratio := float(ai_rules["march_strength_ratio"])
	var max_hops := int(ai_rules["march_search_hops"])
	var here: String = String(state["armies"][army_id]["region"])
	var hops := MapRules.hops_from(data, here)

	var target := ""
	var target_hops := max_hops + 1
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()  # ties break on the sorted id, so the road is reproducible
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		var owner: String = String(settlement["owner"])
		if owner == faction_id or not DiplomacyRules.at_war(state, faction_id, owner):
			continue
		var distance := int(hops.get(region_id, -1))
		if distance <= 0 or distance >= target_hops:
			continue
		if float(soldiers) < float(CombatRules.soldiers_in(data, settlement["garrison"])) * ratio:
			continue
		target = region_id
		target_hops = distance
	if target == "":
		return ""

	var toward := MapRules.hops_from(data, target)
	var neighbors: Array = data.regions.get(here, {}).get("adjacent", []).duplicate()
	neighbors.sort()
	for neighbor in neighbors:
		if int(toward.get(neighbor, target_hops)) >= target_hops:
			continue
		# can_enter refuses hostile ground on purpose — investing a city is a
		# siege, handled above. This step only ever crosses friendly or neutral
		# land, which is what an approach march is.
		if MovementRules.can_enter(data, state, army_id, neighbor):
			return neighbor
	return ""


static func _weakest_hostile_army(data: GameData, state: Dictionary,
		faction_id: String, from_region: String) -> String:
	## An enemy column standing here or one region away, smallest first. Ties
	## break on the sorted army id so the choice is reproducible.
	var reachable := {from_region: true}
	for neighbor in data.regions.get(from_region, {}).get("adjacent", []):
		reachable[neighbor] = true
	var best := ""
	var best_soldiers := 0
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army["owner"] == faction_id or not reachable.has(String(army["region"])):
			continue
		if not DiplomacyRules.at_war(state, faction_id, String(army["owner"])):
			continue
		var soldiers := CombatRules.soldiers_in(data, army["units"])
		if soldiers <= 0:
			continue
		if best == "" or soldiers < best_soldiers:
			best = army_id
			best_soldiers = soldiers
	return best


static func _weakest_hostile_neighbour(data: GameData, state: Dictionary,
		faction_id: String, from_region: String) -> String:
	## The adjacent enemy settlement holding the fewest men. Ties break on the
	## sorted region id, so the choice never depends on dictionary order.
	var best := ""
	var best_garrison := 0
	var neighbors: Array = data.regions.get(from_region, {}).get("adjacent", []).duplicate()
	neighbors.sort()
	for neighbor in neighbors:
		if not state["settlements"].has(neighbor):
			continue
		var settlement: Dictionary = state["settlements"][neighbor]
		var owner: String = String(settlement["owner"])
		if owner == faction_id or not DiplomacyRules.at_war(state, faction_id, owner):
			continue
		if settlement["siege"] != null:
			continue
		var garrison := CombatRules.soldiers_in(data, settlement["garrison"])
		if best == "" or garrison < best_garrison:
			best = neighbor
			best_garrison = garrison
	return best


static func _is_besieging(state: Dictionary, army_id: String) -> bool:
	for settlement in state["settlements"].values():
		var siege = settlement["siege"]
		if siege != null and String(siege["besieger"]) == army_id:
			return true
	return false


## --- 4. Declaring war -----------------------------------------------------

static func _consider_war(data: GameData, state: Dictionary, faction_id: String,
		rng: CampaignRng, journal: Array) -> void:
	## War is declared at the END of the faction's turn, so the armies march on
	## it next turn rather than the same one. That paces the escalation and
	## keeps a new campaign from catching fire on turn one.
	var ai_rules: Dictionary = data.balance["ai"]
	if int(state["turn"]) < int(ai_rules["war_grace_turns"]):
		return
	var faction: Dictionary = state["factions"][faction_id]
	if int(faction.get("war_cooldown", 0)) > 0:
		faction["war_cooldown"] = int(faction.get("war_cooldown", 0)) - 1
		return
	if data.factions.get(faction_id, {}).get("is_rebel", false):
		return
	if not rng.chance(float(ai_rules["war_declare_chance"])):
		return

	var target := _war_candidate(data, state, faction_id, rng)
	if target == "":
		return
	DiplomacyRules.declare_war(state, faction_id, target)
	faction["war_cooldown"] = int(ai_rules["war_cooldown_turns"])
	# The beat itself comes from the end-of-turn stance diff, which catches
	# player declarations and battlefield betrayals the same way.


static func _war_candidate(data: GameData, state: Dictionary, faction_id: String,
		rng: CampaignRng) -> String:
	## A neighbour we border, are not bound to, and outweigh on the frontier.
	var candidates: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if String(state["settlements"][region_id]["owner"]) != faction_id:
			continue
		var neighbors: Array = data.regions.get(region_id, {}).get("adjacent", []).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if not state["settlements"].has(neighbor):
				continue
			var owner: String = String(state["settlements"][neighbor]["owner"])
			if owner == faction_id or not state["factions"].has(owner):
				continue
			if not state["factions"][owner]["alive"]:
				continue
			var stance := DiplomacyRules.stance_between(state, faction_id, owner)
			# Never betray an ally or a protector, and never turn on the Senate.
			if stance != "neutral" or data.factions.get(owner, {}).get("is_senate", false):
				continue
			if not candidates.has(owner):
				candidates.append(owner)
	if candidates.is_empty():
		return ""
	candidates.sort()  # canonical order — candidates feed rng.pick
	return rng.pick(candidates)
