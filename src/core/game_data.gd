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
var grain_regions: Array = []          # sorted region ids producing grain (hot-path index)
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
var glossary: Dictionary = {}          # section -> {id -> {id, name, blurb}}
var advances: Dictionary = {}          # id -> advance dict
var edicts: Dictionary = {}            # id -> edict dict (one standing order per province)
var society: Dictionary = {}           # axes, unrest states, historical patterns
var ai_personas: Dictionary = {}       # id -> persona dict
var agent_kinds: Dictionary = {}       # id -> agent kind dict (diplomat/spy/assassin)
var techniques: Dictionary = {}        # id -> technique dict (the knowledge of the age)
var epithets: Dictionary = {}          # id -> epithet dict (names earned by deeds)
var offices: Dictionary = {}           # id -> senate office dict (the cursus honorum)
var annals: Dictionary = {}            # chronicle kind -> [prose template variants]
var campaign: Dictionary = {}
var dispatch_beats: Dictionary = {}    # beat kind -> presentation entry
var dispatch_chapters: Array = []      # the day's acts, in playing order
var sites: Dictionary = {}             # id -> point-of-interest dict
var sites_by_region: Dictionary = {}   # region id -> point-of-interest dict
var guided_stages: Array = []          # guided-campaign stages, authored order
var guided_stage_index: Dictionary = {}  # stage id -> stage dict
var effects_glossary: Dictionary = {}  # the player-facing wording for building effects

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

	var glossary_doc := _read_json(dir + "/glossary.json")
	for section in ["unit_classes", "attributes", "effects", "building_kinds"]:
		var entries := {}
		for entry in glossary_doc.get(section, []):
			entries[entry["id"]] = entry
		glossary[section] = entries
	effects_glossary = _read_json(dir + "/effects_glossary.json")

	var map_data := _read_json(dir + "/regions.json")
	for region in map_data.get("regions", []):
		regions[region["id"]] = region
	for zone in map_data.get("sea_zones", []):
		sea_zones[zone["id"]] = zone
	index_grain_regions()

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
	for persona in _read_json(dir + "/ai.json").get("personas", []):
		ai_personas[persona["id"]] = persona
	for agent_kind in _read_json(dir + "/agents.json").get("agents", []):
		agent_kinds[agent_kind["id"]] = agent_kind
	for technique in _read_json(dir + "/techniques.json").get("techniques", []):
		techniques[technique["id"]] = technique
	for edict in _read_json(dir + "/edicts.json").get("edicts", []):
		if edicts.has(edict["id"]):
			load_errors.append("duplicate edict id: %s" % edict["id"])
		edicts[edict["id"]] = edict
	for epithet in _read_json(dir + "/epithets.json").get("epithets", []):
		epithets[epithet["id"]] = epithet
	annals = _read_json(dir + "/annals.json").get("templates", {})
	for office in _read_json(dir + "/offices.json").get("offices", []):
		if offices.has(office["id"]):
			load_errors.append("duplicate office id: %s" % office["id"])
		offices[office["id"]] = office

	for advance in _read_json(dir + "/advances.json").get("advances", []):
		if advances.has(advance["id"]):
			load_errors.append("duplicate advance id: %s" % advance["id"])
		advances[advance["id"]] = advance
	society = _read_json(dir + "/society.json")
	var dispatch_data := _read_json(dir + "/dispatch.json")
	dispatch_chapters = dispatch_data.get("chapters", [])
	for beat in dispatch_data.get("beats", []):
		dispatch_beats[beat["id"]] = beat
	for site in _read_json(dir + "/sites.json").get("sites", []):
		if sites.has(site["id"]):
			load_errors.append("duplicate site id: %s" % site["id"])
		sites[site["id"]] = site
		sites_by_region[site["region"]] = site
	guided_stages = _read_json(dir + "/guided_campaign.json").get("stages", [])
	for stage in guided_stages:
		guided_stage_index[stage["id"]] = stage


func index_grain_regions() -> void:
	## The grain map is immutable data; growth's grain-route scan runs against
	## this short index instead of every settlement (a real hot-path saving —
	## order breakdowns recompute growth constantly). Fixture builders that
	## fill `regions` by hand call this afterward.
	grain_regions = []
	var region_ids: Array = regions.keys()
	region_ids.sort()
	for region_id in region_ids:
		if regions[region_id].get("resources", []).has("grain"):
			grain_regions.append(region_id)



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

func dispatch_chapter(chapter_id: String) -> Dictionary:
	for chapter in dispatch_chapters:
		if chapter["id"] == chapter_id:
			return chapter
	return {}


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
