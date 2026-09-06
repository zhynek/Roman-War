class_name SiegeRules
## Sieges: an army invests a hostile settlement, builds equipment over turns or
## starves the defenders out; assaults resolve through the BattleResolver with
## the wall tier stacked in the defenders' favor.


static func begin_siege(data: GameData, state: Dictionary, army_id: String, region_id: String) -> bool:
	var army: Dictionary = state["armies"][army_id]
	if not state["settlements"].has(region_id):
		return false
	var marching_in: bool = army["region"] != region_id
	if marching_in and not TerrainRules.land_connection(data, army["region"], region_id):
		return false
	var settlement: Dictionary = state["settlements"][region_id]
	if settlement["owner"] == army["owner"] or settlement["siege"] != null:
		return false
	# A relieving field army must be beaten before the walls can be invested —
	# an enemy's, or the city's own owner's, since the declaration below would
	# make it an enemy the moment the ladders went up — and marching up to the
	# walls costs the same step as any other march: a siege is never a free hop.
	if MovementRules.hostile_army_in(state, army["owner"], region_id) \
			or _owner_army_in(state, String(settlement["owner"]), region_id):
		return false
	if marching_in and MovementRules.step_cost(data, state, region_id, army["region"]) > float(army["movement_left"]) + 0.0001:
		return false
	# Investing a settlement IS a declaration of war — and one the Republic
	# forbids is refused here, before a single ladder is raised.
	if not DiplomacyRules.declare_war(data, state, army["owner"], settlement["owner"]):
		return false
	release(state, army_id)
	if marching_in:
		ReconRules.record_move(data, state, army_id, region_id)
	army["region"] = region_id
	MovementRules.sync_general_location(state, army)
	army["movement_left"] = 0.0
	settlement["siege"] = {"besieger": army_id, "turns": 0, "equipment_ready": false}
	return true


static func _owner_army_in(state: Dictionary, owner: String, region_id: String) -> bool:
	for army in state["armies"].values():
		if army["owner"] == owner and army["region"] == region_id:
			return true
	return false


static func hand_over(state: Dictionary, from_army_id: String, to_army_id: String) -> void:
	## The siege `from` holds passes to `to` (a merge into co-located
	## reinforcements): the clock and the engines stay, the besieger changes.
	for region_id in state["settlements"]:
		var siege = state["settlements"][region_id]["siege"]
		if siege != null and siege.get("besieger", "") == from_army_id:
			siege["besieger"] = to_army_id


static func release(state: Dictionary, army_id: String) -> void:
	## Lift whatever siege this army holds. Every path that moves, garrisons,
	## merges, dissolves or destroys an army calls this, so a settlement is
	## never marked as invested by an army that is no longer at its walls.
	for region_id in state["settlements"]:
		var siege = state["settlements"][region_id]["siege"]
		if siege != null and siege.get("besieger", "") == army_id:
			state["settlements"][region_id]["siege"] = null


static func advance_sieges(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver) -> Array:
	## Called once per turn end. Starvation forces the garrison to fight a
	## last sally at the walls once supplies run out. Returns event dicts.
	var siege_rules: Dictionary = data.balance["siege"]
	var results: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		var siege = settlement["siege"]
		if siege == null:
			continue
		if not state["armies"].has(siege["besieger"]) \
				or state["armies"][siege["besieger"]]["region"] != region_id:
			settlement["siege"] = null
			continue
		var besieger_owner: String = state["armies"][siege["besieger"]]["owner"]
		# Peace lifts a siege: nobody starves a city they are not at war with.
		if not DiplomacyRules.at_war(state, besieger_owner, settlement["owner"]):
			settlement["siege"] = null
			continue
		siege["turns"] = int(siege["turns"]) + 1
		var equipment_turns := equipment_turns_for(data, state, besieger_owner)
		if int(siege["turns"]) >= equipment_turns:
			siege["equipment_ready"] = true

		var level := SettlementRules.settlement_level(data, settlement)
		var starve_turns: Array = siege_rules["starve_turns_per_settlement_level"]
		var supplies := int(starve_turns[Constants.level_index(level)])
		# The besieger always gets one full turn with the engines ready to
		# choose an assault before the garrison's supplies decide the matter.
		var starve_at := maxi(supplies, equipment_turns + 1)
		if int(siege["turns"]) >= starve_at:
			results.append({
				"kind": "starved_out", "region": region_id,
				"previous_owner": settlement["owner"],
				"result": assault(data, state, rng, resolver, siege["besieger"], region_id, true),
			})
	return results


static func equipment_turns_for(data: GameData, state: Dictionary, faction_id: String) -> int:
	## Turns of investment before an assault can be launched: the base, less
	## what the besieger's practiced siegecraft (torsion engines, rolling
	## towers) shaves off — never below the floor, one season at the walls.
	var siege_rules: Dictionary = data.balance["siege"]
	var delta := int(KnowledgeRules.faction_effect_total(data, state, faction_id, "siege_equipment_turns_delta"))
	return maxi(int(siege_rules["equipment_turns"]) + delta, int(siege_rules["min_equipment_turns"]))


static func assault_context(data: GameData, state: Dictionary, army: Dictionary, region_id: String, starving: bool) -> Dictionary:
	## The resolver context for storming (or, starving, being sallied from) a
	## settlement: its wall tier, the governor as the defending general, both
	## societies' martial ethos and both sides' practiced warcraft, pre-merged
	## so the resolver stays state-free. Shared by assault and the odds preview.
	var settlement: Dictionary = state["settlements"][region_id]
	var wall_level := int(SettlementRules.effect_max(data, settlement, "wall_level"))
	# The defender's practiced wallcraft (timber-laced ramparts) fights a tier
	# above the stones themselves; the resolver contract is untouched — only
	# the wall_level context it receives changes.
	wall_level += int(KnowledgeRules.faction_effect_total(data, state, settlement["owner"], "wall_level_bonus"))
	# A spy of the attacker inside the city opens a gate for the storming party.
	wall_level = maxi(0, wall_level - AgentRules.infiltration_bonus(data, state, region_id, army["owner"]))
	if starving:
		wall_level = maxi(0, wall_level - 1)

	var governor = settlement["governor"]
	var governor_profile = null
	if governor != null and state["characters"].has(governor):
		governor_profile = CharacterRules.battle_profile(data, state["characters"][governor])
	return {
		"terrain": data.regions[region_id]["terrain"],
		"wall_level": wall_level,
		"attacker_general": CombatRules.general_profile(data, state, army),
		"defender_general": governor_profile,
		"attacker_fatigued": false,
		"sally": starving,
		"attacker_martial": SocietyRules.faction_stocks_for(data, state, String(army["owner"]))["martial_ethos"],
		"defender_martial": SocietyRules.faction_stocks_for(data, state, String(settlement["owner"]))["martial_ethos"],
		"attacker_mods": KnowledgeRules.army_mods(data, state, String(army["owner"])),
		"defender_mods": KnowledgeRules.army_mods(data, state, String(settlement["owner"])),
	}


static func assault(data: GameData, state: Dictionary, rng: CampaignRng, resolver: BattleResolver, army_id: String, region_id: String, starving: bool = false) -> Dictionary:
	var army: Dictionary = state["armies"][army_id]
	var settlement: Dictionary = state["settlements"][region_id]
	var siege = settlement["siege"]
	if siege == null or siege["besieger"] != army_id:
		return {}
	if not DiplomacyRules.at_war(state, army["owner"], settlement["owner"]):
		return {}
	# Without equipment you can only assault once the garrison is starving.
	if not siege["equipment_ready"] and not starving:
		return {}

	var governor = settlement["governor"]
	var soldiers_before := CombatRules.soldiers_in(data, army["units"]) + CombatRules.soldiers_in(data, settlement["garrison"])
	var attacker_classes: Array = ArmyRules.shares(data, army["units"]).keys()
	var defender_classes: Array = ArmyRules.shares(data, settlement["garrison"]).keys()
	var result := resolver.resolve(data, rng, army["units"], settlement["garrison"],
		assault_context(data, state, army, region_id, starving))
	CombatRules.record_battle(data, state, army["owner"], settlement["owner"], attacker_classes, defender_classes,
		soldiers_before, result, army["units"], settlement["garrison"])

	if result.get("attacker_general_died", false) and army["general"] != null:
		CharacterRules.kill(state, army["general"], data)
	if result.get("defender_general_died", false) and governor != null:
		CharacterRules.kill(state, governor, data)

	# Siege battles count for the player's trail too: storming a wall or
	# throwing an assault back is as much a victory as any field battle.
	var player: String = state.get("player_faction", "")
	if result["winner"] == "attacker" and army["owner"] == player:
		GuidedRules.bump(state, "battles_won")
	elif result["winner"] == "defender" and settlement["owner"] == player:
		GuidedRules.bump(state, "battles_won")
	# A bloody repulse at the walls teaches the attacker (the defender's own
	# reckoning, if the city falls, comes through capture_settlement). Either
	# way a storming is a battle for the war ledger; a repulse gets its own
	# annals entry here, while a taken city's entry comes from the capture.
	ChronicleRules.on_battle(state, String(army["owner"]), String(settlement["owner"]))
	if result["winner"] != "attacker":
		KnowledgeRules.on_battle_lost(data, state, String(army["owner"]))
		ChronicleRules.record(data, state, "battle", {
			"faction": army["owner"], "other_faction": settlement["owner"],
			"region": region_id,
		}, 5, {"winner": "defender", "assault": true})
		ChronicleRules.add_deed(state, army["general"], "battles_lost")
		ChronicleRules.add_deed(state, governor, "battles_won")

	# Settle the attacker's fate BEFORE any laurels: an assault that leaves no
	# man standing takes nothing, and its dead general wins no honours.
	if army["units"].is_empty():
		if army["general"] != null:
			CharacterRules.kill(state, army["general"], data)
		state["armies"].erase(army_id)
		settlement["siege"] = null
		result["captured"] = false
		return result

	if result["winner"] == "attacker":
		result["captured"] = true
		result["capture_pending_owner"] = army["owner"]
		result["besieger_general"] = army["general"]
		# Caller (Game.assault_settlement / turn engine) applies the
		# occupy/enslave/exterminate decision via CombatRules.capture_settlement,
		# and fires the siege_won / settlement_* triggers for the general.
		ChronicleRules.add_deed(state, army["general"], "sieges_won")
		ChronicleRules.add_deed(state, army["general"], "battles_won")
		if army["general"] != null:
			var notices: Array = []
			CharacterRules.fire_trigger(data, state, army["general"], "siege_won", {}, rng, notices)
			result["character_notices"] = notices
	else:
		settlement["siege"] = null
	return result
