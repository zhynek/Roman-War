class_name SiegeRules
## Sieges: an army invests a hostile settlement, builds equipment over turns or
## starves the defenders out; assaults resolve through the BattleResolver with
## the wall tier stacked in the defenders' favor.


static func begin_siege(data: GameData, state: Dictionary, army_id: String, region_id: String) -> bool:
	var army: Dictionary = state["armies"][army_id]
	if not state["settlements"].has(region_id):
		return false
	var marching_in: bool = army["region"] != region_id
	if marching_in and not MapRules.are_adjacent(data, army["region"], region_id):
		return false
	var settlement: Dictionary = state["settlements"][region_id]
	if settlement["owner"] == army["owner"] or settlement["siege"] != null:
		return false
	# A relieving field army must be beaten before the walls can be invested,
	# and marching up to the walls costs the same step as any other march —
	# a siege is never a free hop.
	if MovementRules.hostile_army_in(state, army["owner"], region_id):
		return false
	if marching_in and MovementRules.step_cost(data, state, region_id) > float(army["movement_left"]) + 0.0001:
		return false
	# Investing a settlement IS a declaration of war.
	DiplomacyRules.declare_war(state, army["owner"], settlement["owner"])
	release(state, army_id)
	army["region"] = region_id
	MovementRules.sync_general_location(state, army)
	army["movement_left"] = 0.0
	settlement["siege"] = {"besieger": army_id, "turns": 0, "equipment_ready": false}
	return true


static func release(state: Dictionary, army_id: String) -> void:
	## Lift whatever siege this army holds. Every path that moves, garrisons,
	## dissolves or destroys an army calls this, so a settlement is never
	## marked as invested by an army that is no longer at its walls.
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
		# Peace lifts a siege: nobody starves a city they are not at war with.
		if not DiplomacyRules.at_war(state, state["armies"][siege["besieger"]]["owner"], settlement["owner"]):
			settlement["siege"] = null
			continue
		siege["turns"] = int(siege["turns"]) + 1
		var equipment_turns := int(siege_rules["equipment_turns"])
		if int(siege["turns"]) >= equipment_turns:
			siege["equipment_ready"] = true

		var level := SettlementRules.settlement_level(data, settlement)
		var starve_turns: Array = siege_rules["starve_turns_per_settlement_level"]
		var supplies := int(starve_turns[Constants.level_index(level)])
		# The besieger always gets one full turn with the equipment ready to
		# choose an assault before the garrison's supplies decide the matter.
		var starve_at := maxi(supplies, equipment_turns + 1)
		if int(siege["turns"]) >= starve_at:
			results.append({
				"kind": "starved_out", "region": region_id,
				"result": assault(data, state, rng, resolver, siege["besieger"], region_id, true),
			})
	return results


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

	var wall_level := int(SettlementRules.effect_max(data, settlement, "wall_level"))
	if starving:
		wall_level = maxi(0, wall_level - 1)

	var governor = settlement["governor"]
	var governor_profile = null
	if governor != null and state["characters"].has(governor):
		governor_profile = CharacterRules.battle_profile(data, state["characters"][governor])
	var result := resolver.resolve(data, rng, army["units"], settlement["garrison"], {
		"terrain": data.regions[region_id]["terrain"],
		"wall_level": wall_level,
		"attacker_general": CombatRules.general_profile(data, state, army),
		"defender_general": governor_profile,
		"attacker_fatigued": false,
		"sally": starving,
	})

	if result.get("attacker_general_died", false) and army["general"] != null:
		CharacterRules.kill(state, army["general"], data)
	if result.get("defender_general_died", false) and governor != null:
		CharacterRules.kill(state, governor, data)

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
		if army["general"] != null:
			var notices: Array = []
			CharacterRules.fire_trigger(data, state, army["general"], "siege_won", {}, rng, notices)
			result["character_notices"] = notices
	else:
		settlement["siege"] = null
	return result
