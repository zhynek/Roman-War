class_name BlockadeRules
## Explicit fleet orders. All effects are derived from current position, war,
## readiness and the prepaid season; no second port ledger or combat model.

static func rules(data: GameData) -> Dictionary:
	return data.balance.get("naval_operations", {})

static func military(data: GameData, ship: Dictionary) -> bool:
	return data.ports.get("vessels", {}).get(ship["template"], {}).get("role", "") == "military"

static func pressure(data: GameData, fleet: Dictionary) -> float:
	var total := 0.0
	for ship in fleet.get("ships", []):
		if military(data, ship):
			total += float(ship.get("strength_pct", 100)) / 100.0
	return SocietyRules.quantize(total)

static func required(data: GameData, state: Dictionary, region: String) -> float:
	return SocietyRules.quantize(float(rules(data)["base_pressure"]) + float(PortRules.capabilities(data, state, region)["defense_pct"]) * float(rules(data)["pressure_per_defense"]))

static func cost(data: GameData, fleet: Dictionary) -> int:
	return fleet.get("ships", []).size() * int(rules(data)["station_cost_per_ship"])

static func station_valid(data: GameData, state: Dictionary, fleet: Dictionary, region: String) -> bool:
	var town: Dictionary = state.get("settlements", {}).get(region, {})
	return not town.is_empty() and PortRules.stage(data, state, region) > 0 \
		and DiplomacyRules.at_war(state, fleet.get("owner", ""), town["owner"]) \
		and NavalRules.zones_touching(data, region).has(fleet.get("sea_zone", "")) \
		and PortRules.supports_zone(data, fleet.get("ships", []), fleet.get("sea_zone", "")) \
		and fleet.get("cargo", {}).is_empty() and fleet.get("trade_route", {}).is_empty() \
		and fleet.get("sail_path", []).is_empty() and pressure(data, fleet) >= required(data, state, region)

static func active(data: GameData, state: Dictionary, fleet: Dictionary) -> bool:
	var order: Dictionary = fleet.get("blockade", {})
	return not order.is_empty() and int(order.get("paid_turn", -1)) == int(state["turn"]) \
		and station_valid(data, state, fleet, order.get("region", ""))

static func at_port(data: GameData, state: Dictionary, region: String) -> Array:
	var result: Array = []
	var ids: Array = state.get("fleets", {}).keys()
	ids.sort()
	for id in ids:
		var fleet: Dictionary = state["fleets"][id]
		if fleet.get("blockade", {}).get("region", "") == region and active(data, state, fleet):
			result.append(id)
	return result

static func blocked(data: GameData, state: Dictionary, region: String) -> bool:
	return not at_port(data, state, region).is_empty()

static func quote(data: GameData, state: Dictionary, fleet_id: String, region: String) -> Dictionary:
	var fleet: Dictionary = state.get("fleets", {}).get(fleet_id, {})
	var out := {"ok": false, "error": "blockade_station", "cost": cost(data, fleet),
		"pressure": pressure(data, fleet), "required": required(data, state, region),
		"movement": float(fleet.get("movement_left", 0)), "region": region}
	if fleet.is_empty() or not state.get("settlements", {}).has(region):
		return out
	if not fleet.get("blockade", {}).is_empty():
		out["error"] = "blockade_existing"
	elif not fleet.get("cargo", {}).is_empty() or not fleet.get("trade_route", {}).is_empty() or not fleet.get("sail_path", []).is_empty():
		out["error"] = "blockade_busy"
	elif not WaterwayRules.hostiles(state, fleet).is_empty():
		out["error"] = "blockade_contact_unresolved"
	elif out["pressure"] < out["required"]:
		out["error"] = "blockade_strength"
	elif not station_valid(data, state, fleet, region):
		pass
	elif float(fleet["movement_left"]) < float(rules(data)["station_movement"]) or int(fleet.get("naval_battle_turn", -1)) == int(state["turn"]):
		out["error"] = "no_movement"
	elif int(state["factions"][fleet["owner"]]["treasury"]) < out["cost"]:
		out["error"] = "funds"
	else:
		out["ok"] = true
		out["error"] = ""
	return out

static func begin(data: GameData, state: Dictionary, fleet_id: String, region: String) -> Dictionary:
	var offer := quote(data, state, fleet_id, region)
	if not offer["ok"]:
		return offer
	var fleet: Dictionary = state["fleets"][fleet_id]
	state["factions"][fleet["owner"]]["treasury"] -= offer["cost"]
	fleet["movement_left"] = 0.0
	fleet["blockade"] = {"region": region, "paid_turn": int(state["turn"])}
	return offer

static func maintain(data: GameData, state: Dictionary) -> void:
	# Called once on the fresh seasonal budget, before any shipping resumes.
	# paid_turn also makes explicit re-entry/save continuation idempotent.
	var ids: Array = state["fleets"].keys()
	ids.sort()
	for id in ids:
		var fleet: Dictionary = state["fleets"][id]
		var order: Dictionary = fleet.get("blockade", {})
		if order.is_empty():
			continue
		if not station_valid(data, state, fleet, order.get("region", "")):
			fleet["blockade"] = {}
			continue
		if int(order.get("paid_turn", -1)) < int(state["turn"]):
			var charge := cost(data, fleet)
			if int(state["factions"][fleet["owner"]]["treasury"]) < charge:
				fleet["blockade"] = {}
				continue
			state["factions"][fleet["owner"]]["treasury"] -= charge
			order["paid_turn"] = int(state["turn"])
		fleet["movement_left"] = 0.0

static func relief_quote(data: GameData, state: Dictionary, fleet_id: String, region: String) -> Dictionary:
	var out := {"ok": false, "error": "blockade_none", "region": region}
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	if fleet.is_empty() or state["settlements"].get(region, {}).get("owner", "") != fleet.get("owner", ""):
		out["error"] = "wrong_owner"
		return out
	if not fleet.get("cargo", {}).is_empty() or not fleet.get("trade_route", {}).is_empty() or not fleet.get("blockade", {}).is_empty():
		out["error"] = "blockade_busy"
		return out
	var best := INF
	var unavailable := "route_unavailable"
	for enemy in at_port(data, state, region):
		var zone: String = state["fleets"][enemy]["sea_zone"]
		var route := WaterwayRules.preview(data, state, fleet_id, zone, fleet.get("sail_mode", "coastal"))
		if not route.is_empty() and route["path"].is_empty():
			var error := WaterwayRules.encounter_error(state, fleet_id, enemy)
			if error != "":
				unavailable = error
				continue
		if not route.is_empty() and float(route["cost"]) < best:
			best = float(route["cost"])
			out = {"ok": true, "error": "", "region": region, "enemy": enemy, "zone": zone,
				"cost": route["cost"], "turns": route["turns"], "path": route["path"],
				"movement": fleet["movement_left"], "ships": fleet["ships"].duplicate(true)}
	if is_inf(best) and blocked(data, state, region):
		out["error"] = unavailable
	return out

static func relieve(data: GameData, state: Dictionary, fleet_id: String, region: String, resolver: BattleResolver, rng: CampaignRng) -> Dictionary:
	var offer := relief_quote(data, state, fleet_id, region)
	if not offer["ok"]:
		return offer
	if offer["path"].is_empty():
		var result := WaterwayRules.battle(data, state, fleet_id, offer["enemy"], resolver, rng)
		return {"ok": not result.is_empty(), "battle": result}
	return WaterwayRules.order(data, state, fleet_id, offer["zone"], state["fleets"][fleet_id].get("sail_mode", "coastal"), resolver, rng)
