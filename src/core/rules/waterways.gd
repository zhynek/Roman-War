class_name WaterwayRules
## Deterministic shipping on the same seasonal clock as armies. Cargo is held
## outside the land-army index, so embarked troops cannot scout, fight or govern.

static func rules(data: GameData) -> Dictionary:
	return data.balance.get("waterways", {})

static func ensure(state: Dictionary) -> void:
	if not state.has("waterworks"):
		state["waterworks"] = {"landings": {}, "bridges": {}, "projects": []}
	if not state.has("naval_report"):
		state["naval_report"] = {}
	for fleet in state.get("fleets", {}).values():
		ensure_fleet(fleet)

static func ensure_fleet(fleet: Dictionary) -> void:
	for key in ["cargo", "trade_route"]:
		if not fleet.has(key):
			fleet[key] = {}
	if not fleet.has("sail_path"):
		fleet["sail_path"] = []
	if not fleet.has("sail_mode"):
		fleet["sail_mode"] = "coastal"

static func river_access(data: GameData, region: String) -> Array:
	var out: Array = []
	for node in data.waterways.get("river_nodes", []):
		if node["regions"].has(region):
			out.append(node["id"])
	out.sort()
	return out

static func port(data: GameData, state: Dictionary, region: String) -> bool:
	return MapRules.coastal(data, region) and PortRules.stage(data, state, region) > 0

static func landing(data: GameData, state: Dictionary, region: String) -> bool:
	return PortRules.stage(data, state, region) > 0

static func access(data: GameData, state: Dictionary, owner: String, region: String, zone: String, own_only: bool = false) -> bool:
	var town: Dictionary = state["settlements"].get(region, {})
	if town.is_empty() or town.get("siege") != null or not NavalRules.zones_touching(data, region).has(zone):
		return false
	var stance := DiplomacyRules.stance_between(state, owner, town["owner"])
	if (own_only and stance != "self") or (not own_only and not stance in ["self", "trade", "alliance", "protectorate"]):
		return false
	if MovementRules.hostile_army_in(state, owner, region):
		return false
	return landing(data, state, region) and (river_access(data, region).has(zone) or port(data, state, region))

static func project_quote(data: GameData, state: Dictionary, region: String, kind: String, other: String = "") -> Dictionary:
	if kind == "landing":
		if landing(data, state, region) or river_access(data, region).is_empty():
			return {"ok": false, "error": "not_ready", "cost": 0, "turns": 0}
		return PortRules.project_quote(data, state, region)
	if kind == "boat":
		return PortRules.ship_quote(data, state, region, data.waterways["transport_template"])
	var town: Dictionary = state["settlements"].get(region, {})
	var out := {"ok": false, "error": "not_ready", "cost": 0, "turns": 0}
	if town.is_empty() or town.get("siege") != null or not kind in ["landing", "bridge", "boat"]:
		return out
	var key := TerrainRules.edge_key(region, other) if kind == "bridge" else region
	var works: Dictionary = state.get("waterworks", {})
	if kind == "landing" and (river_access(data, region).is_empty() or landing(data, state, region)):
		return out
	if kind == "bridge" and (TerrainRules.crossing_kind(data, region, other) != "river" or works.get("bridges", {}).has(key) or state["settlements"].get(other, {}).get("owner", "") != town["owner"] or state["settlements"].get(other, {}).get("siege") != null):
		out["error"] = "no_access"
		return out
	if kind == "boat" and not landing(data, state, region):
		out["error"] = "landing_required"
		return out
	for project in works.get("projects", []):
		if project["kind"] == kind and project["key"] == key:
			return out
	out["cost"] = int(data.units[data.waterways["transport_template"]]["cost"]) if kind == "boat" else int(rules(data)[kind + "_cost"])
	out["turns"] = int(rules(data)[kind + "_turns"])
	out["ok"] = int(state["factions"][town["owner"]]["treasury"]) >= out["cost"]
	if out["ok"]:
		out["error"] = ""
	return out

static func queue_project(data: GameData, state: Dictionary, region: String, kind: String, other: String = "") -> Dictionary:
	if kind == "landing":
		var landing_quote := project_quote(data, state, region, kind)
		return PortRules.queue_project(data, state, region) if landing_quote["ok"] else landing_quote
	if kind == "boat":
		var ship_quote := PortRules.ship_quote(data, state, region, data.waterways["transport_template"])
		if ship_quote["ok"]:
			ship_quote["ok"] = RecruitmentRules.queue_unit(data, state, region, data.waterways["transport_template"])
		return ship_quote
	var quote := project_quote(data, state, region, kind, other)
	if not quote["ok"]:
		return quote
	ensure(state)
	var owner: String = state["settlements"][region]["owner"]
	state["factions"][owner]["treasury"] -= quote["cost"]
	state["waterworks"]["projects"].append({"region": region, "other": other, "owner": owner, "kind": kind,
		"key": TerrainRules.edge_key(region, other) if kind == "bridge" else region, "turns": quote["turns"]})
	return quote

static func advance_projects(data: GameData, state: Dictionary) -> Array:
	ensure(state)
	var pending: Array = []
	var completed: Array = []
	for project in state["waterworks"]["projects"]:
		var town: Dictionary = state["settlements"].get(project["region"], {})
		if town.get("owner", "") != project["owner"]:
			continue
		var blocked: bool = town.get("siege") != null
		if project["kind"] == "bridge":
			var other: Dictionary = state["settlements"].get(project["other"], {})
			blocked = blocked or other.get("owner", "") != project["owner"] or other.get("siege") != null
		if not blocked:
			project["turns"] = int(project["turns"]) - 1
		if int(project["turns"]) > 0:
			pending.append(project)
			continue
		match project["kind"]:
			"boat":
				NavalRules.harbour_of(state, project["region"]).append({"template": data.waterways["transport_template"], "experience": 0, "strength_pct": 100, "weapon": 0, "armor": 0})
			"landing": state["waterworks"]["landings"][project["key"]] = true
			"bridge": state["waterworks"]["bridges"][project["key"]] = true
		completed.append(project.duplicate(true))
	state["waterworks"]["projects"] = pending
	return completed

static func capacity(data: GameData, fleet: Dictionary) -> int:
	return PortRules.fleet_capacity(data, fleet)

static func cargo_size(fleet: Dictionary) -> int:
	var army: Dictionary = fleet.get("cargo", {}).get("army", {})
	return army.get("units", []).size() + (1 if army.get("general") != null else 0)

static func embark_quote(data: GameData, state: Dictionary, fleet_id: String, army_id: String) -> Dictionary:
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	var army: Dictionary = state["armies"].get(army_id, {})
	if fleet.is_empty() or army.is_empty() or fleet["owner"] != army["owner"]:
		return {"ok": false, "error": "wrong_owner"}
	if not fleet.get("cargo", {}).is_empty() or not fleet.get("trade_route", {}).is_empty():
		return {"ok": false, "error": "cargo_aboard"}
	if not access(data, state, fleet["owner"], army["region"], fleet["sea_zone"], true):
		return {"ok": false, "error": "occupied"}
	var passengers := PortRules.passengers(data, army)
	if passengers > capacity(data, fleet):
		return {"ok": false, "error": "capacity_error"}
	if passengers > PortRules.handling_left(data, state, army["region"]):
		return {"ok": false, "error": "handling_full"}
	var cost := float(rules(data)["handling_cost"])
	if float(army["movement_left"]) < cost or float(fleet["movement_left"]) < cost:
		return {"ok": false, "error": "no_movement"}
	return {"ok": true, "passengers": passengers, "capacity": capacity(data,fleet), "cost": cost}

static func embark(data: GameData, state: Dictionary, fleet_id: String, army_id: String) -> Dictionary:
	var quote := embark_quote(data,state,fleet_id,army_id)
	if not quote["ok"]:
		return quote
	var fleet: Dictionary = state["fleets"][fleet_id]
	var army: Dictionary = state["armies"][army_id]
	var passengers := int(quote["passengers"])
	var cost := float(quote["cost"])
	PortRules.handle(state, army["region"], passengers)
	SiegeRules.release(state, army_id)
	army.erase("march_path")
	army.erase("march_forced")
	army["movement_left"] = 0.0
	fleet["movement_left"] = SocietyRules.quantize(float(fleet["movement_left"]) - cost)
	fleet["cargo"] = {"id": army_id, "army": army}
	fleet["sail_path"] = []
	state["armies"].erase(army_id)
	_sync_cargo(state, fleet)
	SettlementRules.refresh_governors(data, state)
	return {"ok": true}

static func can_land(data: GameData, state: Dictionary, fleet: Dictionary, region: String) -> bool:
	if access(data, state, fleet.get("owner", ""), region, fleet.get("sea_zone", "")):
		return true
	# Preserve unopposed amphibious landings. A landing does not capture a
	# settlement, fight its garrison, or grant an army a second movement budget.
	var town: Dictionary = state["settlements"].get(region, {})
	return not town.is_empty() and town.get("siege") == null \
		and data.regions.get(region, {}).get("sea_zones", []).has(fleet.get("sea_zone", "")) \
		and DiplomacyRules.at_war(state, fleet.get("owner", ""), town["owner"]) \
		and not MovementRules.hostile_army_in(state, fleet.get("owner", ""), region)

static func landing_quote(data: GameData, state: Dictionary, fleet_id: String, region: String) -> Dictionary:
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	if fleet.get("cargo", {}).is_empty() or not can_land(data, state, fleet, region):
		return {"ok": false, "error": "occupied"}
	var cost := float(rules(data)["handling_cost"])
	if float(fleet["movement_left"]) < cost:
		return {"ok": false, "error": "no_movement"}
	var cargo: Dictionary = fleet["cargo"]
	var army: Dictionary = cargo["army"]
	var passengers := PortRules.passengers(data, army)
	if access(data, state, fleet["owner"], region, fleet["sea_zone"]):
		if passengers > PortRules.handling_left(data, state, region):
			return {"ok": false, "error": "handling_full"}
	return {"ok":true,"cost":cost,"passengers":passengers}

static func disembark(data: GameData, state: Dictionary, fleet_id: String, region: String) -> Dictionary:
	var quote := landing_quote(data,state,fleet_id,region)
	if not quote["ok"]:
		return quote
	var fleet: Dictionary = state["fleets"][fleet_id]
	var cargo: Dictionary = fleet["cargo"]
	var army: Dictionary = cargo["army"]
	var passengers := int(quote["passengers"])
	var cost := float(quote["cost"])
	if access(data,state,fleet["owner"],region,fleet["sea_zone"]):
		PortRules.handle(state, region, passengers)
	army["region"] = region
	army["movement_left"] = 0.0
	state["armies"][cargo["id"]] = army
	MovementRules.sync_general_location(state, army)
	fleet["cargo"] = {}
	fleet["sail_path"] = []
	fleet["movement_left"] = SocietyRules.quantize(float(fleet["movement_left"]) - cost)
	SettlementRules.refresh_governors(data, state)
	CartographyRules.record_reports(data, state)
	return {"ok": true, "army_id": cargo["id"]}

static func _sync_cargo(state: Dictionary, fleet: Dictionary) -> void:
	var army: Dictionary = fleet.get("cargo", {}).get("army", {})
	var general = army.get("general")
	if general != null and state["characters"].has(general):
		state["characters"][general]["location"] = fleet["sea_zone"]

static func edge(data: GameData, a: String, b: String) -> Dictionary:
	return data.waterway_links.get(TerrainRules.edge_key(a, b), {})

static func step_cost(data: GameData, fleet: Dictionary, a: String, b: String, mode: String) -> float:
	var link := edge(data, a, b)
	if link.is_empty():
		return INF
	for ship in fleet.get("ships", []):
		if not PortRules.permits_water(data, ship, link["kind"]):
			return INF
	if not PortRules.supports_zone(data, fleet.get("ships", []), b):
		return INF
	if link["kind"] == "open":
		if mode != "open":
			return INF
		for ship in fleet.get("ships", []):
			if data.waterways.get("shallow_templates", []).has(ship["template"]):
				return INF
	return SocietyRules.quantize(float(link["distance"]) * float(rules(data).get(link["kind"] + "_cost_multiplier", 1)))

static func preview(data: GameData, state: Dictionary, fleet_id: String, target: String, mode: String = "coastal") -> Dictionary:
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	if fleet.is_empty() or not data.sea_zones.has(target) or not mode in ["coastal", "open"]:
		return {}
	var origin: String = fleet["sea_zone"]
	var full := MovementRules.fleet_movement_points_for(data, state, fleet)
	var dist := {origin: 0.0}
	var previous := {}
	var done := {}
	while true:
		var current := ""
		var best := INF
		var keys: Array = dist.keys()
		keys.sort()
		for id in keys:
			if not done.has(id) and float(dist[id]) < best:
				best = float(dist[id])
				current = id
		if current == "" or current == target:
			break
		done[current] = true
		var neighbors: Array = data.sea_zones[current].get("adjacent", []).duplicate()
		neighbors.sort()
		for next in neighbors:
			var cost := step_cost(data, fleet, current, next, mode)
			if cost > full + 0.0001:
				continue
			if best + cost < float(dist.get(next, INF)):
				dist[next] = best + cost
				previous[next] = current
	if not dist.has(target):
		return {}
	var path: Array = []
	var cursor := target
	while cursor != origin:
		path.push_front(cursor)
		cursor = previous[cursor]
	var budget := float(fleet["movement_left"])
	var turns := 0 if path.is_empty() else 1
	var legs: Array = []
	cursor = origin
	for next in path:
		var cost := step_cost(data, fleet, cursor, next, mode)
		if cost > budget + 0.0001:
			turns += 1
			budget = full
		budget -= cost
		legs.append({"zone": next, "cost": cost, "kind": edge(data, cursor, next)["kind"], "turn": turns})
		cursor = next
	return {"path": path, "legs": legs, "cost": SocietyRules.quantize(dist[target]), "turns": turns, "mode": mode}

static func order(data: GameData, state: Dictionary, fleet_id: String, target: String, mode: String, resolver: BattleResolver, rng: CampaignRng) -> Dictionary:
	var quote := preview(data, state, fleet_id, target, mode)
	if quote.is_empty() or quote["path"].is_empty():
		return {"ok": false, "error": "route_unavailable"}
	var fleet: Dictionary = state["fleets"][fleet_id]
	fleet["trade_route"] = {}
	fleet["sail_path"] = quote["path"].duplicate()
	fleet["sail_mode"] = mode
	return advance(data, state, fleet_id, resolver, rng)

static func advance(data: GameData, state: Dictionary, fleet_id: String, resolver: BattleResolver, rng: CampaignRng) -> Dictionary:
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	var out := {"ok": true, "arrived": false, "path": [], "battles": [], "stopped_at": fleet.get("sea_zone", "")}
	if fleet.is_empty():
		return out
	var path: Array = fleet.get("sail_path", [])
	while not path.is_empty():
		var cost := step_cost(data, fleet, fleet["sea_zone"], path[0], fleet.get("sail_mode", "coastal"))
		if is_inf(cost) or cost > MovementRules.fleet_movement_points_for(data, state, fleet) + 0.0001:
			path.clear()
			out["ok"] = false
			break
		if cost > float(fleet["movement_left"]) + 0.0001:
			break
		# A fleet already in contact must resolve that encounter before sailing away.
		var enemies := hostiles(state, fleet)
		if not enemies.is_empty():
			out["battles"].append(battle(data, state, fleet_id, enemies[0], resolver, rng, true))
			break
		fleet["movement_left"] = SocietyRules.quantize(float(fleet["movement_left"]) - cost)
		fleet["sea_zone"] = path.pop_front()
		out["path"].append(fleet["sea_zone"])
		out["stopped_at"] = fleet["sea_zone"]
		_sync_cargo(state, fleet)
		CartographyRules.record_reports(data, state)
		enemies = hostiles(state, fleet)
		if not enemies.is_empty():
			out["battles"].append(battle(data, state, fleet_id, enemies[0], resolver, rng, true))
			break
	out["arrived"] = path.is_empty() and state["fleets"].has(fleet_id)
	return out

static func hostiles(state: Dictionary, fleet: Dictionary) -> Array:
	var ids: Array = []
	for id in state["fleets"]:
		var other: Dictionary = state["fleets"][id]
		if other["sea_zone"] == fleet["sea_zone"] and DiplomacyRules.at_war(state, fleet["owner"], other["owner"]):
			ids.append(id)
	ids.sort()
	return ids

static func battle(data: GameData, state: Dictionary, attacker_id: String, defender_id: String, resolver: BattleResolver, rng: CampaignRng, intercept: bool = false) -> Dictionary:
	var attacker: Dictionary = state["fleets"].get(attacker_id, {})
	var defender: Dictionary = state["fleets"].get(defender_id, {})
	if attacker.is_empty() or defender.is_empty() or (not intercept and float(attacker["movement_left"]) <= 0) or not hostiles(state, attacker).has(defender_id):
		return {}
	var result := resolver.resolve(data, rng, attacker["ships"], defender["ships"], {"terrain": "plains", "wall_level": 0, "fort_defense_pct": PortRules.defense(data, state, defender),
		"attacker_mods": KnowledgeRules.army_mods(data, state, attacker["owner"]), "defender_mods": KnowledgeRules.army_mods(data, state, defender["owner"])})
	for id in [attacker_id, defender_id]:
		var fleet: Dictionary = state["fleets"][id]
		fleet["movement_left"] = 0.0
		fleet["sail_path"] = []
		fleet["trade_route"] = {}
		var cargo: Dictionary = fleet.get("cargo", {}).get("army", {})
		while PortRules.passengers(data, cargo) > capacity(data, fleet) and not cargo.get("units", []).is_empty():
			cargo["units"].pop_back()
		if fleet["ships"].is_empty():
			if cargo.get("general") != null:
				CharacterRules.kill(state, cargo["general"], data)
			state["fleets"].erase(id)
	state["naval_report"] = {"turn": state["turn"], "zone": attacker["sea_zone"], "winner": attacker["owner"] if result.get("winner") == "attacker" else defender["owner"]}
	return result

static func trade_valid(data: GameData, state: Dictionary, fleet: Dictionary, route: Dictionary) -> bool:
	if route.is_empty():
		return false
	for end in ["from", "to"]:
		if not access(data, state, fleet["owner"], route[end], route[end + "_zone"]):
			return false
	return true

static func trade_quote(data: GameData, state: Dictionary, fleet_id: String, from: String, to: String, mode: String = "coastal") -> Dictionary:
	var fleet: Dictionary = state["fleets"].get(fleet_id, {})
	if fleet.is_empty() or not fleet.get("cargo", {}).is_empty() or from == to:
		return {"ok": false, "error": "cargo_aboard"}
	if PortRules.fleet_capacity(data, fleet, "cargo") <= 0:
		return {"ok": false, "error": "cargo_empty"}
	if not access(data, state, fleet["owner"], from, fleet["sea_zone"], true):
		return {"ok": false, "error": "occupied"}
	var best := {}
	var target := ""
	for zone in NavalRules.zones_touching(data, to):
		if zone == fleet["sea_zone"] or not access(data, state, fleet["owner"], to, zone):
			continue
		var quote := preview(data, state, fleet_id, zone, mode)
		if not quote.is_empty() and (best.is_empty() or quote["cost"] < best["cost"]):
			best = quote
			target = zone
	if best.is_empty():
		return {"ok": false, "error": "route_unavailable"}
	return {"ok":true,"from":from,"to":to,"to_zone":target,"from_zone":fleet["sea_zone"],"path":best["path"].duplicate(),"turns":best["turns"],"cost":best["cost"],"capacity":PortRules.delivery_capacity(data,state,fleet,{"from":from,"to":to})}

static func assign_trade(data: GameData, state: Dictionary, fleet_id: String, from: String, to: String, mode: String = "coastal") -> Dictionary:
	var best := trade_quote(data,state,fleet_id,from,to,mode)
	if not best["ok"]:
		return best
	var fleet: Dictionary = state["fleets"][fleet_id]
	var target: String = best["to_zone"]
	fleet["sail_mode"] = mode
	fleet["trade_route"] = {"from": from, "to": to, "from_zone": fleet["sea_zone"], "to_zone": target, "heading": "to", "paid_turn": int(state["turn"]), "paused": false}
	fleet["sail_path"] = best["path"].duplicate()
	return {"ok": true}

static func advance_season(data: GameData, state: Dictionary, resolver: BattleResolver, rng: CampaignRng) -> Array:
	var reports: Array = []
	var ids: Array = state["fleets"].keys()
	ids.sort()
	for id in ids:
		if not state["fleets"].has(id):
			continue
		var fleet: Dictionary = state["fleets"][id]
		var trade: Dictionary = fleet.get("trade_route", {})
		if not trade.is_empty():
			trade["paused"] = not trade_valid(data, state, fleet, trade)
			if trade["paused"]:
				continue
		if fleet.get("sail_path", []).is_empty():
			continue
		var origin: String = fleet["sea_zone"]
		var report := advance(data, state, id, resolver, rng)
		report["fleet"] = id
		report["from"] = origin
		reports.append(report)
		if not state["fleets"].has(id) or fleet.get("trade_route", {}).is_empty() or not report["battles"].is_empty():
			continue
		if report["arrived"] and int(trade["paid_turn"]) < int(state["turn"]):
			var premium := 0
			var origin_resources: Array = data.regions[trade["from"]].get("resources", [])
			for resource in data.regions[trade["to"]].get("resources", []):
				if not origin_resources.has(resource):
					premium += int(rules(data)["trade_resource_bonus"])
			var volume := PortRules.delivery_capacity(data, state, fleet, trade)
			var income := int(round(volume * float(PortRules.rules(data)["trade_income_per_cargo"]))) + (premium if volume > 0 else 0)
			state["factions"][fleet["owner"]]["treasury"] += income
			trade["paid_turn"] = int(state["turn"])
			report["income"] = income
			trade["heading"] = "from" if trade["heading"] == "to" else "to"
			var quote := preview(data, state, id, trade[trade["heading"] + "_zone"], fleet.get("sail_mode", "coastal"))
			fleet["sail_path"] = quote.get("path", []).duplicate()
	return reports
