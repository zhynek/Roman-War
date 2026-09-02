class_name DoctrineRules
## Faction-level military doctrines (data/doctrines.json): reforms a faction
## adopts for denarii and turns once its prerequisites hold — buildings it has
## raised, resources it holds, its era, earlier doctrines, and its war record
## (what it has fought, won, lost and learned from). Adopted doctrines reach
## the battle estimator as one pre-merged ArmyMods dict and every other reader
## (upkeep, recruitment, sieges, order, movement, mercenaries) as scalars, so
## the resolver never touches game state and a save carries only the ids.

## Effect keys that are plain numbers summed across adopted doctrines.
const SCALAR_KEYS: Array[String] = [
	"strength_pct", "attacking_pct", "assault_pct", "wall_defense_pct", "pursuit_pct", "escape_pct",
	"upgrade_cap", "siege_equipment_turns", "garrison_order_pct", "levy_strain_pct", "movement",
	"mercenary_cost_pct",
]


static func eligible(data: GameData, _state: Dictionary, faction_id: String) -> Array:
	## Sorted ids of every doctrine this faction may ever pursue: its culture
	## must be listed, and if the doctrine names factions, it must be one.
	var culture := data.culture_of_faction(faction_id)
	var ids: Array = []
	for doctrine_id in data.doctrines:
		var doctrine: Dictionary = data.doctrines[doctrine_id]
		if not doctrine["cultures"].has(culture):
			continue
		var factions: Array = doctrine.get("factions", [])
		if not factions.is_empty() and not factions.has(faction_id):
			continue
		ids.append(doctrine_id)
	ids.sort()
	return ids


static func available(data: GameData, state: Dictionary, faction_id: String) -> Array:
	## One row per eligible doctrine, sorted by id — what the Reforms scroll shows:
	## {id, doctrine, status: adopted|in_progress|available|locked, unmet: [String], turns_left}
	var faction: Dictionary = state["factions"][faction_id]
	var rows: Array = []
	for doctrine_id in eligible(data, state, faction_id):
		var doctrine: Dictionary = data.doctrines[doctrine_id]
		var row := {"id": doctrine_id, "doctrine": doctrine, "status": "available", "unmet": [], "turns_left": 0}
		if faction.get("doctrines", []).has(doctrine_id):
			row["status"] = "adopted"
		else:
			var reform := _reform_of(faction, doctrine_id)
			if not reform.is_empty():
				row["status"] = "in_progress"
				row["turns_left"] = int(reform["turns_left"])
			else:
				row["unmet"] = prerequisites_unmet(data, state, faction_id, doctrine)
				if not row["unmet"].is_empty():
					row["status"] = "locked"
		rows.append(row)
	return rows


static func prerequisites_unmet(data: GameData, state: Dictionary, faction_id: String, doctrine: Dictionary) -> Array:
	## Human-readable reasons this faction cannot adopt the doctrine yet; empty
	## when it can. Every prerequisite key must hold (AND).
	var faction: Dictionary = state["factions"][faction_id]
	var reasons: Array = []
	var era: String = doctrine.get("era", "any")
	if era != "any" and String(faction.get("era", "")) != era:
		reasons.append("requires the %s era" % era.replace("_", "-"))
	var prerequisites: Dictionary = doctrine.get("prerequisites", {})
	for needed in prerequisites.get("doctrines", []):
		if not faction.get("doctrines", []).has(needed):
			reasons.append("requires %s" % data.doctrines.get(needed, {}).get("name", needed))
	var building: Dictionary = prerequisites.get("building", {})
	if not building.is_empty() and not _owns_building(data, state, faction_id, String(building["kind"]), int(building["level"])):
		reasons.append("needs a %s of tier %d in some town" % [String(building["kind"]).replace("_", " "), int(building["level"])])
	var resource: String = prerequisites.get("resource", "")
	if resource != "" and not _owns_resource(data, state, faction_id, resource):
		reasons.append("needs a region that yields %s" % resource.replace("_", " "))
	var record: Dictionary = faction.get("war_record", {})
	var won_needed := int(prerequisites.get("battles_won", 0))
	if won_needed > int(record.get("battles_won", 0)):
		reasons.append("needs %d battles won (%d so far)" % [won_needed, int(record.get("battles_won", 0))])
	var lost_needed := int(prerequisites.get("battles_lost", 0))
	if lost_needed > int(record.get("battles_lost", 0)):
		reasons.append("needs %d battles lost (%d so far)" % [lost_needed, int(record.get("battles_lost", 0))])
	var faced: Dictionary = prerequisites.get("faced", {})
	if not faced.is_empty():
		var fought := int(record.get("faced", {}).get(faced["class"], 0))
		if fought < int(faced["battles"]):
			reasons.append("needs %d battles against %s (%d so far)" % [int(faced["battles"]),
				String(faced["class"]).replace("_", " "), fought])
	return reasons


static func adopt(data: GameData, state: Dictionary, faction_id: String, doctrine_id: String) -> bool:
	## Pay for a doctrine and start the reform; it completes after its turns.
	if not state["factions"].has(faction_id) or not data.doctrines.has(doctrine_id):
		return false
	var faction: Dictionary = state["factions"][faction_id]
	if not eligible(data, state, faction_id).has(doctrine_id):
		return false
	if faction["doctrines"].has(doctrine_id) or not _reform_of(faction, doctrine_id).is_empty():
		return false
	if faction["reforms"].size() >= int(data.balance["doctrines"]["max_concurrent_reforms"]):
		return false
	var doctrine: Dictionary = data.doctrines[doctrine_id]
	if not prerequisites_unmet(data, state, faction_id, doctrine).is_empty():
		return false
	if int(faction["treasury"]) < int(doctrine["cost"]):
		return false
	faction["treasury"] = int(faction["treasury"]) - int(doctrine["cost"])
	faction["reforms"].append({"doctrine": doctrine_id, "turns_left": int(doctrine["turns"])})
	return true


static func advance_reforms(data: GameData, state: Dictionary) -> Dictionary:
	## Once per turn end. Returns {faction_id: [completed doctrine ids]}.
	var completed := {}
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		var remaining: Array = []
		for reform in faction.get("reforms", []):
			reform["turns_left"] = int(reform["turns_left"]) - 1
			if int(reform["turns_left"]) <= 0:
				grant(faction, String(reform["doctrine"]))
				if not completed.has(faction_id):
					completed[faction_id] = []
				completed[faction_id].append(reform["doctrine"])
			else:
				remaining.append(reform)
		faction["reforms"] = remaining
	return completed


static func grant(faction: Dictionary, doctrine_id: String) -> void:
	## Add a doctrine outright (completed reform, campaign start, event); the
	## list stays sorted so every path writes the same state.
	var adopted: Array = faction["doctrines"]
	if not adopted.has(doctrine_id):
		adopted.append(doctrine_id)
		adopted.sort()


## --- Effects ---------------------------------------------------------------

static func effects_for(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	## The faction's adopted doctrines merged, in sorted id order: per-class
	## tables (stat deltas, matchup and terrain percentages, upkeep, recruit
	## experience) and summed scalars.
	var merged := {
		"class_stats": {}, "matchups": {}, "terrain": {}, "upkeep_pct": {}, "recruit_xp": {},
		"scalars": {}, "fatigue_immune": false,
	}
	var faction: Dictionary = state["factions"].get(faction_id, {})
	var adopted: Array = faction.get("doctrines", []).duplicate()
	adopted.sort()
	for doctrine_id in adopted:
		var effects: Dictionary = data.doctrines.get(doctrine_id, {}).get("effects", {})
		for entry in effects.get("class_stats", []):
			var stats: Dictionary = merged["class_stats"].get(entry["class"], {})
			for stat in ["attack", "defense", "morale", "charge", "missile_attack"]:
				if entry.has(stat):
					stats[stat] = float(stats.get(stat, 0.0)) + float(entry[stat])
			merged["class_stats"][entry["class"]] = stats
		for entry in effects.get("matchups", []):
			var versus: Dictionary = merged["matchups"].get(entry["class"], {})
			versus[entry["versus"]] = float(versus.get(entry["versus"], 0.0)) + float(entry["pct"])
			merged["matchups"][entry["class"]] = versus
		for entry in effects.get("terrain", []):
			var terrains: Dictionary = merged["terrain"].get(entry["class"], {})
			terrains[entry["terrain"]] = float(terrains.get(entry["terrain"], 0.0)) + float(entry["pct"])
			merged["terrain"][entry["class"]] = terrains
		for entry in effects.get("upkeep_pct", []):
			merged["upkeep_pct"][entry["class"]] = float(merged["upkeep_pct"].get(entry["class"], 0.0)) + float(entry["pct"])
		for entry in effects.get("recruit_xp", []):
			merged["recruit_xp"][entry["class"]] = int(merged["recruit_xp"].get(entry["class"], 0)) + int(entry["xp"])
		if bool(effects.get("fatigue_immune", false)):
			merged["fatigue_immune"] = true
		for key in SCALAR_KEYS:
			if effects.has(key):
				merged["scalars"][key] = float(merged["scalars"].get(key, 0.0)) + float(effects[key])
	return merged


static func army_mods(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	## The ArmyMods dict the BattleResolver contract expects (see battle_resolver.gd).
	var effects := effects_for(data, state, faction_id)
	var scalars: Dictionary = effects["scalars"]
	return {
		"class_stats": effects["class_stats"],
		"matchup_pct": effects["matchups"],
		"terrain_pct": effects["terrain"],
		"strength_pct": float(scalars.get("strength_pct", 0.0)),
		"attacking_pct": float(scalars.get("attacking_pct", 0.0)),
		"assault_pct": float(scalars.get("assault_pct", 0.0)),
		"wall_defense_pct": float(scalars.get("wall_defense_pct", 0.0)),
		"pursuit_pct": float(scalars.get("pursuit_pct", 0.0)),
		"escape_pct": float(scalars.get("escape_pct", 0.0)),
		"fatigue_immune": bool(effects["fatigue_immune"]),
	}


static func scalar(data: GameData, state: Dictionary, faction_id: String, key: String) -> float:
	return float(effects_for(data, state, faction_id)["scalars"].get(key, 0.0))


static func upkeep_pct_by_class(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	return effects_for(data, state, faction_id)["upkeep_pct"]


static func recruit_xp_for(data: GameData, state: Dictionary, faction_id: String, unit_class: String) -> int:
	var table: Dictionary = effects_for(data, state, faction_id)["recruit_xp"]
	return int(table.get("all", 0)) + int(table.get(unit_class, 0))


## --- AI -----------------------------------------------------------------------

static func ai_pick(data: GameData, state: Dictionary, faction_id: String) -> String:
	## The cheapest doctrine the faction can adopt while keeping a reserve;
	## ties fall to the lowest id (rows are sorted). "" when nothing qualifies.
	var faction: Dictionary = state["factions"][faction_id]
	var reserve := int(data.balance["doctrines"]["ai_reserve"])
	var best := ""
	var best_cost := 1 << 30
	for row in available(data, state, faction_id):
		if row["status"] != "available":
			continue
		var cost := int(row["doctrine"]["cost"])
		if int(faction["treasury"]) < cost + reserve:
			continue
		if cost < best_cost:
			best = row["id"]
			best_cost = cost
	return best


## --- Helpers ------------------------------------------------------------------

static func _reform_of(faction: Dictionary, doctrine_id: String) -> Dictionary:
	for reform in faction.get("reforms", []):
		if reform["doctrine"] == doctrine_id:
			return reform
	return {}


static func _owns_building(data: GameData, state: Dictionary, faction_id: String, kind: String, level: int) -> bool:
	for region_id in state["settlements"]:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] == faction_id and SettlementRules.building_tier(data, settlement, kind) >= level:
			return true
	return false


static func _owns_resource(data: GameData, state: Dictionary, faction_id: String, resource: String) -> bool:
	for region_id in state["settlements"]:
		if state["settlements"][region_id]["owner"] != faction_id:
			continue
		if data.regions.get(region_id, {}).get("resources", []).has(resource):
			return true
	return false
