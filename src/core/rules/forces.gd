class_name ForceRules
## One view over every body of troops the campaign tracks — field armies,
## fleets, settlement garrisons and harbours — and the actions that regroup
## them: raise an army from a garrison, move units between co-located forces,
## merge, split, disband, give or take a general. Force ids are the army/fleet
## ids of the state ("army_3", "fleet_2") or the pseudo-ids "garrison:<region>"
## and "harbour:<region>".
##
## Every mutating action X has a pure sibling check_X that returns "" when the
## action is legal or an error code from the closed vocabulary below; X itself
## returns {ok: bool, error: String, ...extras}. Rules are owner-agnostic: the
## acting faction is the owner of the force. Deterministic, scene-free, and
## every loop that can steer a first-match decision walks sorted ids.

const ERR_NOT_FOUND := "not_found"
const ERR_WRONG_OWNER := "wrong_owner"
const ERR_NOT_COLOCATED := "not_colocated"
const ERR_OVER_CAP := "over_cap"
const ERR_EMPTY_SELECTION := "empty_selection"
const ERR_BAD_INDEX := "bad_index"
const ERR_LAST_UNIT := "last_unit"
const ERR_NOT_ELIGIBLE_GENERAL := "not_eligible_general"
const ERR_HAS_GENERAL := "has_general"
const ERR_NO_GENERAL := "no_general"
const ERR_TWO_GENERALS := "two_generals"
const ERR_NO_SETTLEMENT := "no_settlement"
const ERR_FOREIGN_SETTLEMENT := "foreign_settlement"
const ERR_SAME_FORCE := "same_force"
const ERR_IS_SHIP := "is_ship"
const ERR_NOT_SHIP := "not_ship"
const ERR_NOT_DOCKED := "not_docked"
const ERR_NOTHING_TO_DO := "nothing_to_do"
const ERR_NO_ZONE := "no_zone"
const ERR_BESIEGED := "besieged"
const ERR_NO_MOVEMENT := "no_movement"


## --- Resolution -------------------------------------------------------------

static func max_units(data: GameData) -> int:
	## The one home of the stack cap. balance.recruitment.army_unit_cap is the
	## key the rest of the engine already reads (mercenary hiring, site finds).
	return int(data.balance["recruitment"]["army_unit_cap"])


static func kind_of(force_id: String) -> String:
	if force_id.begins_with("army_"):
		return "army"
	if force_id.begins_with("fleet_"):
		return "fleet"
	if force_id.begins_with("garrison:"):
		return "garrison"
	if force_id.begins_with("harbour:"):
		return "harbour"
	return ""


static func exists(state: Dictionary, force_id: String) -> bool:
	match kind_of(force_id):
		"army":
			return state["armies"].has(force_id)
		"fleet":
			return state["fleets"].has(force_id)
		"garrison":
			return state["settlements"].has(force_id.trim_prefix("garrison:"))
		"harbour":
			return state["settlements"].has(force_id.trim_prefix("harbour:"))
	return false


static func resolve(state: Dictionary, force_id: String) -> Dictionary:
	## {kind, id, owner, region, sea_zone, units (LIVE array), container (LIVE dict)} or {}.
	match kind_of(force_id):
		"army":
			if not state["armies"].has(force_id):
				return {}
			var army: Dictionary = state["armies"][force_id]
			return {"kind": "army", "id": force_id, "owner": army["owner"], "region": army["region"],
				"sea_zone": "", "units": army["units"], "container": army}
		"fleet":
			if not state["fleets"].has(force_id):
				return {}
			var fleet: Dictionary = state["fleets"][force_id]
			return {"kind": "fleet", "id": force_id, "owner": fleet["owner"], "region": "",
				"sea_zone": fleet["sea_zone"], "units": fleet["ships"], "container": fleet}
		"garrison":
			var region_id := force_id.trim_prefix("garrison:")
			if not state["settlements"].has(region_id):
				return {}
			var settlement: Dictionary = state["settlements"][region_id]
			return {"kind": "garrison", "id": force_id, "owner": settlement["owner"], "region": region_id,
				"sea_zone": "", "units": settlement["garrison"], "container": settlement}
		"harbour":
			var region_id := force_id.trim_prefix("harbour:")
			if not state["settlements"].has(region_id):
				return {}
			var settlement: Dictionary = state["settlements"][region_id]
			return {"kind": "harbour", "id": force_id, "owner": settlement["owner"], "region": region_id,
				"sea_zone": "", "units": NavalRules.harbour_of(state, region_id), "container": settlement}
	return {}


static func units_of(state: Dictionary, force_id: String) -> Array:
	## The LIVE unit array behind a force id ([] when unknown): whoever mutates
	## it is mutating the campaign state.
	var force := resolve(state, force_id)
	return force["units"] if not force.is_empty() else []


static func owner_of(state: Dictionary, force_id: String) -> String:
	var force := resolve(state, force_id)
	return String(force["owner"]) if not force.is_empty() else ""


static func max_soldiers_in(data: GameData, units: Array) -> int:
	## Head count at full strength — the denominator of a strength percentage.
	var total := 0
	for unit in units:
		total += int(data.units.get(unit["template"], {}).get("soldiers", 0))
	return total


static func is_ship(data: GameData, unit: Dictionary) -> bool:
	return String(data.units.get(unit["template"], {}).get("class", "")) == "ship"


## --- Summary ------------------------------------------------------------------

static func summary(data: GameData, state: Dictionary, force_id: String) -> Dictionary:
	## Everything a banner or a roster panel needs, in one dictionary:
	##   id, kind ("army"|"fleet"|"garrison"|"harbour"), owner, region, sea_zone,
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
			result["movement_max"] = MovementRules.fleet_movement_points_for(data, state, fleet)
		"garrison":
			result["region"] = force_id.trim_prefix("garrison:")
		"harbour":
			result["region"] = force_id.trim_prefix("harbour:")
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
		"age": character.get("age", 30),
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


## --- Generals ---------------------------------------------------------------------

static func candidate_generals(data: GameData, state: Dictionary, region_id: String, faction_id: String) -> Array:
	## Sorted ids of the faction's men who could take command in a region:
	## alive, adult, male, of the family, standing there, leading no army.
	var found: Array = []
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["faction"] != faction_id or not CharacterRules.can_command(data, character):
			continue
		if character.get("location", "") != region_id:
			continue
		if _leads_army(state, char_id):
			continue
		found.append(char_id)
	return found


static func _leads_army(state: Dictionary, char_id: String) -> bool:
	for army in state["armies"].values():
		if army["general"] == char_id:
			return true
	return false


static func check_attach_general(data: GameData, state: Dictionary, army_id: String, char_id: String) -> String:
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return ERR_NOT_FOUND
	if army["general"] != null:
		return ERR_HAS_GENERAL
	if not candidate_generals(data, state, army["region"], army["owner"]).has(char_id):
		return ERR_NOT_ELIGIBLE_GENERAL
	return ""


static func attach_general(data: GameData, state: Dictionary, army_id: String, char_id: String) -> Dictionary:
	## The man remembers how far he has ridden this season: an army he takes
	## over marches no further than he could (see note_general_march).
	var error := check_attach_general(data, state, army_id, char_id)
	if error != "":
		return {"ok": false, "error": error}
	var army: Dictionary = state["armies"][army_id]
	army["general"] = char_id
	army["movement_left"] = minf(float(army["movement_left"]), general_march_cap(state, char_id))
	MovementRules.cap_movement(data, state, army)
	return {"ok": true, "error": ""}


static func check_detach_general(_data: GameData, state: Dictionary, army_id: String) -> String:
	## A general steps down only inside one of his own faction's cities —
	## nobody is ever left standing in the wilderness without a banner.
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return ERR_NOT_FOUND
	if army["general"] == null:
		return ERR_NO_GENERAL
	return _own_settlement_here(state, army)


static func detach_general(data: GameData, state: Dictionary, army_id: String) -> Dictionary:
	var error := check_detach_general(data, state, army_id)
	if error != "":
		return {"ok": false, "error": error}
	var army: Dictionary = state["armies"][army_id]
	note_general_march(state, army["general"], float(army["movement_left"]))
	army["general"] = null
	MovementRules.cap_movement(data, state, army)
	return {"ok": true, "error": ""}


static func _own_settlement_here(state: Dictionary, army: Dictionary) -> String:
	var settlement: Dictionary = state["settlements"].get(army["region"], {})
	if settlement.is_empty():
		return ERR_NO_SETTLEMENT
	if settlement["owner"] != army["owner"]:
		return ERR_FOREIGN_SETTLEMENT
	return ""


## --- Raising, transferring, merging, splitting ------------------------------------

static func _check_indices(units: Array, indices: Array) -> String:
	if indices.is_empty():
		return ERR_EMPTY_SELECTION
	var seen := {}
	for index in indices:
		var i := int(index)
		if i < 0 or i >= units.size() or seen.has(i):
			return ERR_BAD_INDEX
		seen[i] = true
	return ""


static func _take_units(units: Array, indices: Array) -> Array:
	## Removes the chosen units (highest index first) and returns them in
	## their original order.
	var sorted: Array = []
	for index in indices:
		sorted.append(int(index))
	sorted.sort()
	var taken: Array = []
	for i in sorted:
		taken.append(units[i])
	for i in range(sorted.size() - 1, -1, -1):
		units.remove_at(sorted[i])
	return taken


static func _new_army(state: Dictionary, owner: String, region_id: String, units: Array, general, movement_left: float, forced_march: bool) -> String:
	var army_id := "army_%d" % int(state["next_id"])
	state["next_id"] = int(state["next_id"]) + 1
	state["armies"][army_id] = {
		"owner": owner, "region": region_id, "units": units, "general": general,
		"movement_left": movement_left, "forced_march": forced_march,
	}
	return army_id


static func check_raise_army(data: GameData, state: Dictionary, region_id: String, indices: Array, general_id: String = "") -> String:
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty():
		return ERR_NO_SETTLEMENT
	if settlement.get("siege") != null:
		return ERR_BESIEGED
	var error := _check_indices(settlement["garrison"], indices)
	if error != "":
		return error
	if indices.size() > max_units(data):
		return ERR_OVER_CAP
	for index in indices:
		if is_ship(data, settlement["garrison"][int(index)]):
			return ERR_IS_SHIP
	if general_id != "" and not candidate_generals(data, state, region_id, settlement["owner"]).has(general_id):
		return ERR_NOT_ELIGIBLE_GENERAL
	return ""


static func raise_army(data: GameData, state: Dictionary, region_id: String, indices: Array, general_id: String = "") -> Dictionary:
	## Garrison units march out as a new field army, with an optional general
	## who is standing in the city. Its movement is the full budget, capped by
	## the least movement of any army that dropped troops here this season and
	## by how far the general has already ridden. Nobody marches out of an
	## invested city: the siege lines are broken by a sally, not a parade.
	var error := check_raise_army(data, state, region_id, indices, general_id)
	if error != "":
		return {"ok": false, "error": error, "army_id": ""}
	var settlement: Dictionary = state["settlements"][region_id]
	var units := _take_units(settlement["garrison"], indices)
	var general = general_id if general_id != "" else null
	var army_id := _new_army(state, settlement["owner"], region_id, units, general, 0.0,
		bool(settlement.get("muster_fatigued", false)))
	var army: Dictionary = state["armies"][army_id]
	army["movement_left"] = SocietyRules.quantize(minf(MovementRules.movement_points_for(data, state, army),
		float(settlement.get("muster_march_left", INF))))
	if general_id != "":
		army["movement_left"] = minf(float(army["movement_left"]), general_march_cap(state, general_id))
	SettlementRules.refresh_governors(data, state)
	return {"ok": true, "error": "", "army_id": army_id}


static func check_transfer_units(data: GameData, state: Dictionary, from_id: String, to_id: String, indices: Array) -> String:
	if from_id == to_id:
		return ERR_SAME_FORCE
	var from := resolve(state, from_id)
	var to := resolve(state, to_id)
	if from.is_empty() or to.is_empty():
		return ERR_NOT_FOUND
	if from["owner"] != to["owner"]:
		return ERR_WRONG_OWNER
	if not _colocated(data, state, from, to):
		return ERR_NOT_COLOCATED
	for force in [from, to]:
		if force["kind"] == "garrison" and force["container"].get("siege") != null:
			return ERR_BESIEGED
	var error := _check_indices(from["units"], indices)
	if error != "":
		return error
	var to_holds_ships: bool = to["kind"] in ["fleet", "harbour"]
	for index in indices:
		var ship := is_ship(data, from["units"][int(index)])
		if ship and not to_holds_ships:
			return ERR_IS_SHIP
		if not ship and to_holds_ships:
			return ERR_NOT_SHIP
	if to["kind"] not in ["garrison", "harbour"] and to["units"].size() + indices.size() > max_units(data):
		return ERR_OVER_CAP
	if from["kind"] == "army" and from["container"]["general"] != null and indices.size() >= from["units"].size():
		return ERR_LAST_UNIT
	# Ships making port pay a sea lane exactly as a docking fleet does; a
	# fleet with no lane left cannot slip its ships into the harbour either.
	if from["kind"] == "fleet" and to["kind"] == "harbour" \
			and NavalRules.lane_cost(data) > float(from["container"]["movement_left"]) + 0.0001:
		return ERR_NO_MOVEMENT
	return ""


static func _colocated(data: GameData, state: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	## Armies share a region; a garrison meets armies in its region when the
	## owner holds the city; fleets share a sea zone; a harbour meets fleets
	## in a sea its port touches (and is never reachable from land forces).
	var kinds := [a["kind"], b["kind"]]
	if kinds.has("harbour"):
		var harbour: Dictionary = a if a["kind"] == "harbour" else b
		var other: Dictionary = b if a["kind"] == "harbour" else a
		if other["kind"] != "fleet":
			return false
		if state["settlements"][harbour["region"]]["owner"] != other["owner"]:
			return false
		return data.regions.get(harbour["region"], {}).get("sea_zones", []).has(other["sea_zone"])
	if kinds.has("fleet"):
		return a["kind"] == "fleet" and b["kind"] == "fleet" and a["sea_zone"] == b["sea_zone"]
	if a["region"] == "" or a["region"] != b["region"]:
		return false
	for force in [a, b]:
		if force["kind"] == "garrison" and state["settlements"][force["region"]]["owner"] != a["owner"]:
			return false
	return true


static func transfer_units(data: GameData, state: Dictionary, from_id: String, to_id: String, indices: Array) -> Dictionary:
	## Move chosen units between two co-located forces of one owner. Movement
	## is conserved: an army (or fleet) receiving troops keeps the lesser
	## movement of the two; a garrison (or harbour) remembers the least
	## movement of any force that dropped units into it this season and caps
	## what is raised (or put to sea) from it.
	var error := check_transfer_units(data, state, from_id, to_id, indices)
	if error != "":
		return {"ok": false, "error": error}
	var from := resolve(state, from_id)
	var to := resolve(state, to_id)
	var moved := _take_units(from["units"], indices)
	for unit in moved:
		to["units"].append(unit)
	if from["kind"] == "army" and to["kind"] == "army":
		to["container"]["movement_left"] = minf(float(to["container"]["movement_left"]), float(from["container"]["movement_left"]))
		to["container"]["forced_march"] = bool(to["container"].get("forced_march", false)) or bool(from["container"].get("forced_march", false))
	elif from["kind"] == "army" and to["kind"] == "garrison":
		note_muster(state, to["region"], float(from["container"]["movement_left"]))
		note_fatigue(state, to["region"], bool(from["container"].get("forced_march", false)))
	elif from["kind"] == "garrison" and to["kind"] == "army":
		var settlement: Dictionary = from["container"]
		to["container"]["movement_left"] = minf(float(to["container"]["movement_left"]), float(settlement.get("muster_march_left", INF)))
		to["container"]["forced_march"] = bool(to["container"].get("forced_march", false)) or bool(settlement.get("muster_fatigued", false))
	elif from["kind"] == "fleet" and to["kind"] == "fleet":
		to["container"]["movement_left"] = minf(float(to["container"]["movement_left"]), float(from["container"]["movement_left"]))
	elif from["kind"] == "fleet" and to["kind"] == "harbour":
		# Making port costs the ships a lane (NavalRules.dock_fleet's rule),
		# so a port on two seas is a crossing, never a free jump.
		note_sail_muster(state, to["region"], float(from["container"]["movement_left"]) - NavalRules.lane_cost(data))
	elif from["kind"] == "harbour" and to["kind"] == "fleet":
		var settlement: Dictionary = from["container"]
		to["container"]["movement_left"] = minf(float(to["container"]["movement_left"]), float(settlement.get("muster_sail_left", INF)))
	if to["kind"] == "army":
		MovementRules.cap_movement(data, state, to["container"])
	_erase_if_empty(data, state, from_id)
	return {"ok": true, "error": ""}


static func _erase_if_empty(data: GameData, state: Dictionary, force_id: String) -> void:
	## A captain's army or a fleet with nothing left in it ceases to exist.
	var force := resolve(state, force_id)
	if force.is_empty() or force["kind"] in ["garrison", "harbour"] or not force["units"].is_empty():
		return
	if force["kind"] == "army":
		SiegeRules.release(state, force_id)
		state["armies"].erase(force_id)
		SettlementRules.refresh_governors(data, state)
	else:
		state["fleets"].erase(force_id)


static func check_merge_armies(data: GameData, state: Dictionary, from_id: String, into_id: String) -> String:
	if from_id == into_id:
		return ERR_SAME_FORCE
	var from: Dictionary = state["armies"].get(from_id, {})
	var into: Dictionary = state["armies"].get(into_id, {})
	if from.is_empty() or into.is_empty():
		return ERR_NOT_FOUND
	if from["owner"] != into["owner"]:
		return ERR_WRONG_OWNER
	if from["region"] != into["region"]:
		return ERR_NOT_COLOCATED
	if from["units"].size() + into["units"].size() > max_units(data):
		return ERR_OVER_CAP
	if from["general"] != null and into["general"] != null and _own_settlement_here(state, into) != "":
		return ERR_TWO_GENERALS
	return ""


static func merge_armies(data: GameData, state: Dictionary, from_id: String, into_id: String) -> Dictionary:
	## Everything in `from` joins `into`, which keeps its id. `into` keeps its
	## general; a captain's `into` takes `from`'s general; two led armies merge
	## only inside one of their own cities, where the displaced general stays
	## and governs by presence. Movement is the lesser of the two.
	var error := check_merge_armies(data, state, from_id, into_id)
	if error != "":
		return {"ok": false, "error": error}
	var from: Dictionary = state["armies"][from_id]
	var into: Dictionary = state["armies"][into_id]
	for unit in from["units"]:
		into["units"].append(unit)
	if into["general"] == null and from["general"] != null:
		into["general"] = from["general"]
	elif from["general"] != null:
		note_general_march(state, from["general"], float(from["movement_left"]))
	into["movement_left"] = minf(float(into["movement_left"]), float(from["movement_left"]))
	MovementRules.cap_movement(data, state, into)
	into["forced_march"] = bool(into.get("forced_march", false)) or bool(from.get("forced_march", false))
	# A besieger that merges into the reinforcements hands the siege — and its
	# clock — to the army that stays at the walls; it is never lifted by a merge.
	SiegeRules.hand_over(state, from_id, into_id)
	state["armies"].erase(from_id)
	SettlementRules.refresh_governors(data, state)
	return {"ok": true, "error": ""}


static func check_split_army(data: GameData, state: Dictionary, army_id: String, indices: Array, general_choice: String = "") -> String:
	var army: Dictionary = state["armies"].get(army_id, {})
	if army.is_empty():
		return ERR_NOT_FOUND
	var error := _check_indices(army["units"], indices)
	if error != "":
		return error
	if indices.size() >= army["units"].size():
		return ERR_LAST_UNIT
	if general_choice == "source":
		if army["general"] == null:
			return ERR_NO_GENERAL
	elif general_choice != "" and not candidate_generals(data, state, army["region"], army["owner"]).has(general_choice):
		return ERR_NOT_ELIGIBLE_GENERAL
	return ""


static func split_army(data: GameData, state: Dictionary, army_id: String, indices: Array, general_choice: String = "") -> Dictionary:
	## The chosen units march on as a new army in the same region, under a
	## captain (""), the source's own general ("source"), or a family member
	## standing there. Movement and fatigue are copied — same road walked.
	var error := check_split_army(data, state, army_id, indices, general_choice)
	if error != "":
		return {"ok": false, "error": error, "army_id": ""}
	var army: Dictionary = state["armies"][army_id]
	var units := _take_units(army["units"], indices)
	var general = null
	if general_choice == "source":
		general = army["general"]
		army["general"] = null
	elif general_choice != "":
		general = general_choice
	var movement := float(army["movement_left"])
	if general_choice != "" and general_choice != "source":
		movement = minf(movement, general_march_cap(state, general_choice))
	var new_id := _new_army(state, army["owner"], army["region"], units, general,
		movement, bool(army.get("forced_march", false)))
	SettlementRules.refresh_governors(data, state)
	MovementRules.cap_movement(data, state, army)
	MovementRules.cap_movement(data, state, state["armies"][new_id])
	return {"ok": true, "error": "", "army_id": new_id}


static func check_disband_unit(data: GameData, state: Dictionary, force_id: String, index: int) -> String:
	var force := resolve(state, force_id)
	if force.is_empty():
		return ERR_NOT_FOUND
	if index < 0 or index >= force["units"].size():
		return ERR_BAD_INDEX
	if force["kind"] == "army" and force["container"]["general"] != null and force["units"].size() == 1:
		return ERR_LAST_UNIT
	if force["kind"] == "fleet" and not _fleet_touches_own_port(data, state, force["container"]):
		return ERR_NOT_DOCKED
	return ""


static func _fleet_touches_own_port(data: GameData, state: Dictionary, fleet: Dictionary) -> bool:
	for region_id in state["settlements"]:
		if state["settlements"][region_id]["owner"] == fleet["owner"] \
				and data.regions.get(region_id, {}).get("sea_zones", []).has(fleet["sea_zone"]):
			return true
	return false


static func disband_unit(data: GameData, state: Dictionary, force_id: String, index: int) -> Dictionary:
	## Send a unit home. Inside one of the owner's own cities the men rejoin
	## its population (mercenaries excepted); no denarii ever come back.
	var error := check_disband_unit(data, state, force_id, index)
	if error != "":
		return {"ok": false, "error": error, "returned": 0}
	var force := resolve(state, force_id)
	var unit: Dictionary = force["units"][index]
	var template: Dictionary = data.units.get(unit["template"], {})
	var returned := 0
	var settlement: Dictionary = state["settlements"].get(force["region"], {})
	if not settlement.is_empty() and settlement["owner"] == force["owner"] \
			and not template.get("factions", []).has("mercenary") and not is_ship(data, unit):
		var pct := float(data.balance["forces"]["disband_population_return_pct"])
		returned = int(round(int(template.get("soldiers", 0)) * int(unit["strength_pct"]) / 100.0 * pct / 100.0))
		settlement["population"] = int(settlement["population"]) + returned
	force["units"].remove_at(index)
	_erase_if_empty(data, state, force_id)
	return {"ok": true, "error": "", "returned": returned}


static func check_consolidate(_data: GameData, state: Dictionary, force_id: String) -> String:
	var units := units_of(state, force_id)
	if units.is_empty() and not exists(state, force_id):
		return ERR_NOT_FOUND
	var depleted_by_template := {}
	for unit in units:
		if int(unit["strength_pct"]) < 100:
			depleted_by_template[unit["template"]] = int(depleted_by_template.get(unit["template"], 0)) + 1
	for template in depleted_by_template:
		if int(depleted_by_template[template]) >= 2:
			return ""
	return ERR_NOTHING_TO_DO


static func consolidate(data: GameData, state: Dictionary, force_id: String) -> Dictionary:
	## Fold depleted same-template units into each other (the higher
	## experience survives). Destructive, so it is a deliberate order.
	var error := check_consolidate(data, state, force_id)
	if error != "":
		return {"ok": false, "error": error}
	RecruitmentRules.merge_units(units_of(state, force_id))
	return {"ok": true, "error": ""}


## --- The season's memory of who marched how far ----------------------------------

static func note_muster(state: Dictionary, region_id: String, movement_left: float) -> void:
	## A garrison that received marching troops this season remembers their
	## remaining march, so the same men cannot be raised again as fresh.
	_note(state["settlements"].get(region_id, {}), "muster_march_left", movement_left)


static func note_fatigue(state: Dictionary, region_id: String, fatigued: bool) -> void:
	## ... and whether they came in weary: men who forced-marched into the
	## city march out of it weary too, whoever raises them.
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if fatigued and not settlement.is_empty():
		settlement["muster_fatigued"] = true


static func note_sail_muster(state: Dictionary, region_id: String, movement_left: float) -> void:
	## The harbour's twin: ships that made port this season leave it no
	## fresher than they arrived (transfers out of the harbour are capped).
	_note(state["settlements"].get(region_id, {}), "muster_sail_left", movement_left)


static func note_general_march(state: Dictionary, general_id, movement_left: float) -> void:
	## A general who leaves an army this season (steps down, garrisons, is
	## displaced by a merge, loses his last unit) remembers how far it had
	## marched, so he cannot relay across fresh armies at no cost.
	if general_id == null:
		return
	_note(state["characters"].get(general_id, {}), "march_left", movement_left)


static func general_march_cap(state: Dictionary, general_id) -> float:
	## How far an army this man takes over may still march: INF if he has
	## not ridden with one this season.
	if general_id == null:
		return INF
	return float(state["characters"].get(general_id, {}).get("march_left", INF))


static func _note(record: Dictionary, key: String, movement_left: float) -> void:
	if record.is_empty():
		return
	# Quantized like every stored float: a remainder such as 0.6000000000000001
	# would otherwise reload as 0.6 and make the raised army step differently.
	record[key] = SocietyRules.quantize(minf(float(record.get(key, INF)), maxf(movement_left, 0.0)))


static func clear_musters(state: Dictionary) -> void:
	## The season's memory of who marched how far, forgotten at the reset.
	for settlement in state["settlements"].values():
		settlement.erase("muster_march_left")
		settlement.erase("muster_sail_left")
		settlement.erase("muster_fatigued")
	for character in state["characters"].values():
		character.erase("march_left")
