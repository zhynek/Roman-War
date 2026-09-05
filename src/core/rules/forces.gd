class_name ForceRules
## One view over every body of troops the campaign tracks — field armies,
## fleets and settlement garrisons — so the map, the panels and (later) the AI
## ask one question, "what is this force?", and get one answer. Force ids are
## the army/fleet ids of the state ("army_3", "fleet_2") or the pseudo-id
## "garrison:<region_id>". Everything here is read-only.


static func max_units(data: GameData) -> int:
	return int(data.balance["forces"]["max_units_per_force"])


static func kind_of(force_id: String) -> String:
	if force_id.begins_with("army_"):
		return "army"
	if force_id.begins_with("fleet_"):
		return "fleet"
	if force_id.begins_with("garrison:"):
		return "garrison"
	return ""


static func exists(state: Dictionary, force_id: String) -> bool:
	match kind_of(force_id):
		"army":
			return state["armies"].has(force_id)
		"fleet":
			return state["fleets"].has(force_id)
		"garrison":
			return state["settlements"].has(force_id.trim_prefix("garrison:"))
	return false


static func units_of(state: Dictionary, force_id: String) -> Array:
	## The LIVE unit array behind a force id ([] when unknown): whoever mutates
	## it is mutating the campaign state.
	match kind_of(force_id):
		"army":
			return state["armies"].get(force_id, {}).get("units", [])
		"fleet":
			return state["fleets"].get(force_id, {}).get("ships", [])
		"garrison":
			return state["settlements"].get(force_id.trim_prefix("garrison:"), {}).get("garrison", [])
	return []


static func owner_of(state: Dictionary, force_id: String) -> String:
	match kind_of(force_id):
		"army":
			return String(state["armies"].get(force_id, {}).get("owner", ""))
		"fleet":
			return String(state["fleets"].get(force_id, {}).get("owner", ""))
		"garrison":
			return String(state["settlements"].get(force_id.trim_prefix("garrison:"), {}).get("owner", ""))
	return ""


static func max_soldiers_in(data: GameData, units: Array) -> int:
	## Head count at full strength — the denominator of a strength percentage.
	var total := 0
	for unit in units:
		total += int(data.units.get(unit["template"], {}).get("soldiers", 0))
	return total


static func summary(data: GameData, state: Dictionary, force_id: String) -> Dictionary:
	## Everything a banner or a roster panel needs, in one dictionary:
	##   id, kind ("army"|"fleet"|"garrison"), owner, region, sea_zone,
	##   units, max_units, fill (units / cap, 0..1), soldiers, max_soldiers,
	##   strength_pct, strength (the resolver's estimate), upkeep,
	##   general (null | {id, name, role, command, is_leader}),
	##   movement_left, movement_max, forced_march, besieging (region | null).
	## {} for an unknown force.
	var kind := kind_of(force_id)
	if kind == "" or not exists(state, force_id):
		return {}
	var units := units_of(state, force_id)
	var soldiers := CombatRules.soldiers_in(data, units)
	var max_soldiers := max_soldiers_in(data, units)
	var cap := max_units(data)
	var result := {
		"id": force_id,
		"kind": kind,
		"owner": owner_of(state, force_id),
		"region": "",
		"sea_zone": "",
		"units": units.size(),
		"max_units": cap,
		"fill": clampf(float(units.size()) / float(cap), 0.0, 1.0),
		"soldiers": soldiers,
		"max_soldiers": max_soldiers,
		"strength_pct": int(round(100.0 * soldiers / max_soldiers)) if max_soldiers > 0 else 0,
		"upkeep": EconomyRules.army_upkeep(data, units),
		"general": null,
		"movement_left": 0.0,
		"movement_max": 0.0,
		"forced_march": false,
		"besieging": null,
	}
	var general_profile = null
	match kind:
		"army":
			var army: Dictionary = state["armies"][force_id]
			result["region"] = army["region"]
			result["movement_left"] = float(army["movement_left"])
			result["movement_max"] = MovementRules.movement_points_for(data, state, army)
			result["forced_march"] = bool(army.get("forced_march", false))
			result["general"] = general_summary(data, state, army["general"])
			general_profile = CombatRules.general_profile(data, state, army)
			result["besieging"] = besieging(state, force_id)
		"fleet":
			var fleet: Dictionary = state["fleets"][force_id]
			result["sea_zone"] = fleet["sea_zone"]
			result["movement_left"] = float(fleet["movement_left"])
			result["movement_max"] = float(data.balance["movement"]["base_movement_points"])
		"garrison":
			result["region"] = force_id.trim_prefix("garrison:")
	result["strength"] = BattleResolver.force_strength(data, units, general_profile,
		float(data.balance["battle"]["experience_strength_pct_per_chevron"]))
	return result


static func general_summary(data: GameData, state: Dictionary, general_id) -> Variant:
	if general_id == null or not state["characters"].has(general_id):
		return null
	var character: Dictionary = state["characters"][general_id]
	return {
		"id": general_id,
		"name": character["name"],
		"role": character["role"],
		"command": CharacterRules.effective(data, character, "command"),
		"is_leader": character["role"] == "leader",
	}


static func besieging(state: Dictionary, army_id: String) -> Variant:
	## The region an army is investing, or null.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return null
	var siege = state["settlements"].get(army["region"], {}).get("siege")
	if siege != null and siege.get("besieger", "") == army_id:
		return army["region"]
	return null


static func armies_in(state: Dictionary, region_id: String) -> Array:
	## Army ids standing in a region, in numeric id order (army_2 before army_10).
	var found: Array = []
	for army_id in state["armies"]:
		if state["armies"][army_id]["region"] == region_id:
			found.append(army_id)
	found.sort_custom(id_less)
	return found


static func fleets_in(state: Dictionary, zone_id: String) -> Array:
	## Fleet ids in a sea zone, in numeric id order.
	var found: Array = []
	for fleet_id in state["fleets"]:
		if state["fleets"][fleet_id]["sea_zone"] == zone_id:
			found.append(fleet_id)
	found.sort_custom(id_less)
	return found


static func id_less(a: String, b: String) -> bool:
	## Numeric-suffix ordering for "prefix_N" ids; plain string order otherwise.
	var a_prefix := a.get_slice("_", 0)
	var b_prefix := b.get_slice("_", 0)
	var a_suffix := a.trim_prefix(a_prefix + "_")
	var b_suffix := b.trim_prefix(b_prefix + "_")
	if a_prefix == b_prefix and a_suffix.is_valid_int() and b_suffix.is_valid_int():
		return a_suffix.to_int() < b_suffix.to_int()
	return a < b
