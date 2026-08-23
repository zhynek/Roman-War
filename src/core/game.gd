class_name Game
extends RefCounted
## The campaign facade: everything the UI (and the test suite) talks to.
## Holds immutable GameData, the mutable GameState dict, and the injected
## BattleResolver. Player actions are methods; end_turn() resolves the world.

var data: GameData
var state: Dictionary = {}
var resolver: BattleResolver


static func new_campaign(player_faction: String, seed_value: int = 1, data_dir: String = "res://data") -> Game:
	var game := Game.new()
	game.data = GameData.load_from(data_dir)
	game.resolver = AutoResolver.new()
	game.state = NewGame.build(game.data, player_faction, seed_value)
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
	state["rng_state"] = rng.get_state()
	return result


func besiege(army_id: String, region_id: String) -> bool:
	return SiegeRules.begin_siege(data, state, army_id, region_id)


func assault_settlement(army_id: String, region_id: String, occupation: String = "occupy") -> Dictionary:
	var rng := _rng()
	var result := SiegeRules.assault(data, state, rng, resolver, army_id, region_id)
	if result.get("captured", false):
		result["capture"] = CombatRules.capture_settlement(
			data, state, rng, region_id, result["capture_pending_owner"], occupation)
	state["rng_state"] = rng.get_state()
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
	var rng := CampaignRng.new()
	rng.set_state(int(state["rng_state"]))
	return rng
