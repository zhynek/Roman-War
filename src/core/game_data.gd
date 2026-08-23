class_name GameData
extends RefCounted
## Immutable game content loaded from data/*.json. The engine never mutates
## anything held here; all mutable campaign state lives in the GameState dict.

var balance: Dictionary = {}
var cultures: Dictionary = {}          # id -> culture dict
var factions: Dictionary = {}          # id -> faction dict
var chains: Dictionary = {}            # chain id -> chain dict (buildings + temples merged)
var building_levels: Dictionary = {}   # level id -> {chain, kind, index(1-based), level(dict)}
var units: Dictionary = {}             # id -> unit template dict
var regions: Dictionary = {}           # id -> region dict
var sea_zones: Dictionary = {}         # id -> sea zone dict
var traits: Dictionary = {}            # id -> trait dict
var ancillaries: Dictionary = {}       # id -> ancillary dict
var events: Array = []
var disasters: Array = []
var wonders: Dictionary = {}           # id -> wonder dict
var missions: Dictionary = {}          # id -> mission template dict
var win_conditions: Array = []
var names: Dictionary = {}             # culture -> {male, female, surnames}
var mercenary_pools: Array = []
var agent_kinds: Dictionary = {}       # id -> agent kind dict (diplomat/spy/assassin)
var campaign: Dictionary = {}

var load_errors: PackedStringArray = []


static func load_from(dir: String = "res://data") -> GameData:
	var data := GameData.new()
	data._load_all(dir)
	return data


func ok() -> bool:
	return load_errors.is_empty()


func _load_all(dir: String) -> void:
	balance = _read_json(dir + "/balance.json")
	campaign = _read_json(dir + "/campaign.json")

	for culture in _read_json(dir + "/cultures.json").get("cultures", []):
		cultures[culture["id"]] = culture
	for faction in _read_json(dir + "/factions.json").get("factions", []):
		factions[faction["id"]] = faction

	for file in ["/buildings.json", "/temples.json"]:
		for chain in _read_json(dir + file).get("chains", []):
			if chains.has(chain["id"]):
				load_errors.append("duplicate chain id: %s" % chain["id"])
			chains[chain["id"]] = chain
			var index := 1
			for level in chain["levels"]:
				if building_levels.has(level["id"]):
					load_errors.append("duplicate building level id: %s" % level["id"])
				building_levels[level["id"]] = {
					"chain": chain["id"], "kind": chain["kind"], "index": index, "level": level,
				}
				index += 1

	for unit in _read_json(dir + "/units.json").get("units", []):
		units[unit["id"]] = unit

	var map_data := _read_json(dir + "/regions.json")
	for region in map_data.get("regions", []):
		regions[region["id"]] = region
	for zone in map_data.get("sea_zones", []):
		sea_zones[zone["id"]] = zone

	for trait_def in _read_json(dir + "/traits.json").get("traits", []):
		traits[trait_def["id"]] = trait_def
	for ancillary in _read_json(dir + "/ancillaries.json").get("ancillaries", []):
		ancillaries[ancillary["id"]] = ancillary

	var event_data := _read_json(dir + "/events.json")
	events = event_data.get("events", [])
	disasters = event_data.get("disasters", [])

	for wonder in _read_json(dir + "/wonders.json").get("wonders", []):
		wonders[wonder["id"]] = wonder
	for mission in _read_json(dir + "/missions.json").get("missions", []):
		missions[mission["id"]] = mission

	win_conditions = _read_json(dir + "/win_conditions.json").get("conditions", [])
	names = _read_json(dir + "/names.json").get("pools", {})
	mercenary_pools = _read_json(dir + "/mercenaries.json").get("pools", [])
	for kind in _read_json(dir + "/agents.json").get("kinds", []):
		agent_kinds[kind["id"]] = kind


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		load_errors.append("missing data file: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		load_errors.append("invalid JSON in " + path)
		return {}
	return parsed


## --- Lookups -------------------------------------------------------------

func culture_of_faction(faction_id: String) -> String:
	return factions.get(faction_id, {}).get("culture", "neutral")


func chain_for(culture: String, kind: String) -> Dictionary:
	## The (single) non-temple chain of this kind buildable by this culture.
	for chain in chains.values():
		if chain["kind"] == kind and chain["cultures"].has(culture):
			return chain
	return {}


func temple_chains_for(culture: String) -> Array:
	var found: Array = []
	for chain in chains.values():
		if chain["kind"] == "temple" and chain["cultures"].has(culture):
			found.append(chain)
	return found


func settlement_level_for_population(population: int) -> String:
	var result := "village"
	for entry in balance["settlement_levels"]:
		if population >= int(entry["min_population"]):
			result = entry["id"]
	return result


func min_population_for_level(level: String) -> int:
	for entry in balance["settlement_levels"]:
		if entry["id"] == level:
			return int(entry["min_population"])
	return 0


func units_for_faction(faction_id: String) -> Array:
	var result: Array = []
	for unit in units.values():
		var owners: Array = unit["factions"]
		if owners.has("all") or owners.has(faction_id):
			result.append(unit)
	return result
