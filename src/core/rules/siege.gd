class_name SiegeRules
## Sieges: an army invests a hostile settlement, builds equipment over turns or
## starves the defenders out; assaults resolve through the BattleResolver with
## the wall tier stacked in the defenders' favor.


static func begin_siege(data: GameData, state: Dictionary, army_id: String, region_id: String) -> bool:
	var army: Dictionary = state["armies"][army_id]
	if not state["settlements"].has(region_id):
		return false
	if not MapRules.are_adjacent(data, army["region"], region_id) and army["region"] != region_id:
		return false
	var settlement: Dictionary = state["settlements"][region_id]
	if settlement["owner"] == army["owner"] or settlement["siege"] != null:
		return false
	# Investing a settlement IS a declaration of war.
	DiplomacyRules.declare_war(state, army["owner"], settlement["owner"])
	army["region"] = region_id
	MovementRules.sync_general_location(state, army)
	army["movement_left"] = 0.0
	settlement["siege"] = {"besieger": army_id, "turns": 0, "equipment_ready": false}
	return true


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
		siege["turns"] = int(siege["turns"]) + 1
		if int(siege["turns"]) >= int(siege_rules["equipment_turns"]):
			siege["equipment_ready"] = true

		var level := SettlementRules.settlement_level(data, settlement)
		var starve_turns: Array = siege_rules["starve_turns_per_settlement_level"]
		var supplies := int(starve_turns[Constants.level_index(level)])
		if int(siege["turns"]) >= supplies:
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

	# Siege battles count for the player's trail too: storming a wall or
	# throwing an assault back is as much a victory as any field battle.
	var player: String = state.get("player_faction", "")
	if result["winner"] == "attacker" and army["owner"] == player:
		GuidedRules.bump(state, "battles_won")
	elif result["winner"] == "defender" and settlement["owner"] == player:
		GuidedRules.bump(state, "battles_won")

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
