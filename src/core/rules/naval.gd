class_name NavalRules
## Ships and fleets. A finished warship waits in its port's HARBOUR (the ship
## analogue of the garrison: never on the walls, never in a land battle, but
## still paid for); the player launches ships from a harbour into a fleet in
## a sea the port touches, docks fleets back, and merges or splits fleets in
## one sea. Every action has a pure check_X sibling using ForceRules' error
## vocabulary. Deterministic and owner-agnostic, like the rest of src/core.


static func zones_touching(data: GameData, region_id: String) -> Array:
	var zones: Array = data.regions.get(region_id, {}).get("sea_zones", []).duplicate()
	zones.sort()
	return zones


static func harbour_of(state: Dictionary, region_id: String) -> Array:
	## The live harbour array (created on demand for older states).
	var settlement: Dictionary = state["settlements"][region_id]
	if not settlement.has("harbour"):
		settlement["harbour"] = []
	return settlement["harbour"]


static func own_ports_on_zone(state: Dictionary, data: GameData, faction_id: String, zone_id: String) -> Array:
	## Sorted region ids of the faction's coastal settlements touching a sea.
	var ports: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] == faction_id \
				and data.regions.get(region_id, {}).get("sea_zones", []).has(zone_id):
			ports.append(region_id)
	return ports


## --- Launch and dock ------------------------------------------------------------

static func check_launch_fleet(data: GameData, state: Dictionary, region_id: String, indices: Array, zone_id: String) -> String:
	if not state["settlements"].has(region_id):
		return ForceRules.ERR_NO_SETTLEMENT
	var harbour := harbour_of(state, region_id)
	var error := ForceRules._check_indices(harbour, indices)
	if error != "":
		return error
	if not zones_touching(data, region_id).has(zone_id):
		return ForceRules.ERR_NO_ZONE
	if indices.size() > ForceRules.max_units(data):
		return ForceRules.ERR_OVER_CAP
	return ""


static func launch_fleet(data: GameData, state: Dictionary, region_id: String, indices: Array, zone_id: String) -> Dictionary:
	## Harbour ships put to sea as a new fleet. Launching spends the season:
	## the fleet moves next turn (so dock/launch cannot relay a fleet along).
	var error := check_launch_fleet(data, state, region_id, indices, zone_id)
	if error != "":
		return {"ok": false, "error": error, "fleet_id": ""}
	var settlement: Dictionary = state["settlements"][region_id]
	var ships := ForceRules._take_units(harbour_of(state, region_id), indices)
	var fleet_id := "fleet_%d" % int(state["next_id"])
	state["next_id"] = int(state["next_id"]) + 1
	state["fleets"][fleet_id] = {
		"owner": settlement["owner"], "sea_zone": zone_id, "ships": ships, "movement_left": 0.0,
	}
	return {"ok": true, "error": "", "fleet_id": fleet_id}


static func check_dock_fleet(data: GameData, state: Dictionary, fleet_id: String, region_id: String) -> String:
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	if fleet.is_empty():
		return ForceRules.ERR_NOT_FOUND
	var settlement: Dictionary = state["settlements"].get(region_id, {})
	if settlement.is_empty():
		return ForceRules.ERR_NO_SETTLEMENT
	if settlement["owner"] != fleet["owner"]:
		return ForceRules.ERR_FOREIGN_SETTLEMENT
	if not zones_touching(data, region_id).has(fleet["sea_zone"]):
		return ForceRules.ERR_NO_ZONE
	return ""


static func dock_fleet(data: GameData, state: Dictionary, fleet_id: String, region_id: String) -> Dictionary:
	## The fleet's ships return to one of the owner's ports on its sea; the
	## fleet ceases to exist.
	var error := check_dock_fleet(data, state, fleet_id, region_id)
	if error != "":
		return {"ok": false, "error": error}
	var harbour := harbour_of(state, region_id)
	for ship in state["fleets"][fleet_id]["ships"]:
		harbour.append(ship)
	state["fleets"].erase(fleet_id)
	return {"ok": true, "error": ""}


## --- Merge and split ----------------------------------------------------------------

static func check_merge_fleets(data: GameData, state: Dictionary, from_id: String, into_id: String) -> String:
	if from_id == into_id:
		return ForceRules.ERR_SAME_FORCE
	var from: Dictionary = state["fleets"].get(from_id, {})
	var into: Dictionary = state["fleets"].get(into_id, {})
	if from.is_empty() or into.is_empty():
		return ForceRules.ERR_NOT_FOUND
	if from["owner"] != into["owner"]:
		return ForceRules.ERR_WRONG_OWNER
	if from["sea_zone"] != into["sea_zone"]:
		return ForceRules.ERR_NOT_COLOCATED
	if from["ships"].size() + into["ships"].size() > ForceRules.max_units(data):
		return ForceRules.ERR_OVER_CAP
	return ""


static func merge_fleets(data: GameData, state: Dictionary, from_id: String, into_id: String) -> Dictionary:
	var error := check_merge_fleets(data, state, from_id, into_id)
	if error != "":
		return {"ok": false, "error": error}
	var from: Dictionary = state["fleets"][from_id]
	var into: Dictionary = state["fleets"][into_id]
	for ship in from["ships"]:
		into["ships"].append(ship)
	into["movement_left"] = minf(float(into["movement_left"]), float(from["movement_left"]))
	state["fleets"].erase(from_id)
	return {"ok": true, "error": ""}


static func check_split_fleet(data: GameData, state: Dictionary, fleet_id: String, indices: Array) -> String:
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	if fleet.is_empty():
		return ForceRules.ERR_NOT_FOUND
	var error := ForceRules._check_indices(fleet["ships"], indices)
	if error != "":
		return error
	if indices.size() >= fleet["ships"].size():
		return ForceRules.ERR_LAST_UNIT
	return ""


static func split_fleet(data: GameData, state: Dictionary, fleet_id: String, indices: Array) -> Dictionary:
	## The chosen ships form a new fleet in the same sea with the same movement.
	var error := check_split_fleet(data, state, fleet_id, indices)
	if error != "":
		return {"ok": false, "error": error, "fleet_id": ""}
	var fleet: Dictionary = state["fleets"][fleet_id]
	var ships := ForceRules._take_units(fleet["ships"], indices)
	var new_id := "fleet_%d" % int(state["next_id"])
	state["next_id"] = int(state["next_id"]) + 1
	state["fleets"][new_id] = {
		"owner": fleet["owner"], "sea_zone": fleet["sea_zone"], "ships": ships,
		"movement_left": float(fleet["movement_left"]),
	}
	return {"ok": true, "error": "", "fleet_id": new_id}


## --- Repair ----------------------------------------------------------------------------

static func normalise(data: GameData, state: Dictionary) -> int:
	## Load-time repair for states written before harbours existed: any ship
	## found in a garrison moves to that settlement's harbour, order kept.
	## Idempotent; returns the number of ships moved.
	var moved := 0
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		var harbour := harbour_of(state, region_id)
		var keep: Array = []
		for unit in settlement["garrison"]:
			if ForceRules.is_ship(data, unit):
				harbour.append(unit)
				moved += 1
			else:
				keep.append(unit)
		settlement["garrison"] = keep
	return moved
