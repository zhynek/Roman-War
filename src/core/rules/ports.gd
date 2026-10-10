class_name PortRules
## Scene-free port development. All numbers come from balance; every quote is
## read-only. Old buildings remain valuable and map additively onto this system.

static func rules(data: GameData) -> Dictionary:
	return data.balance.get("ports", {})

static func site(data: GameData, region: String) -> Dictionary:
	return data.ports.get("sites", {}).get(region, {})

static func record(state: Dictionary, region: String) -> Dictionary:
	return state.get("ports", {}).get(region, {})

static func ensure(state: Dictionary) -> void:
	if not state.has("ports"):
		state["ports"] = {}

static func live(state: Dictionary, region: String) -> Dictionary:
	ensure(state)
	if not state["ports"].has(region):
		state["ports"][region] = {"stage": 0, "facilities": [], "project": {}, "handling_turn": -1, "handled": 0, "repair_turn": -1}
	return state["ports"][region]

static func stage(data: GameData, state: Dictionary, region: String) -> int:
	var town: Dictionary = state.get("settlements", {}).get(region, {})
	var legacy := int(SettlementRules.effect_max(data, town, "port_level")) if not town.is_empty() else 0
	var mapping: Array = rules(data).get("legacy_stages", [0])
	var inherited := int(mapping[mini(legacy, mapping.size() - 1)])
	if state.get("waterworks", {}).get("landings", {}).has(region):
		inherited = maxi(1, inherited)
	return maxi(inherited, int(record(state, region).get("stage", 0)))

static func facilities(data: GameData, state: Dictionary, region: String) -> Array:
	var out: Array = record(state, region).get("facilities", []).duplicate()
	var town: Dictionary = state.get("settlements", {}).get(region, {})
	# Paid legacy shipyards retain their military and repair capability.
	if not town.is_empty() and SettlementRules.building_tier(data, town, "naval") > 0:
		for id in ["repair_yard", "arsenal"]:
			if not out.has(id):
				out.append(id)
	out.sort()
	return out

static func stage_spec(data: GameData, rank: int) -> Dictionary:
	return data.ports.get("stages", [])[rank - 1] if rank > 0 and rank <= data.ports.get("stages", []).size() else {}

static func capabilities(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var rank := stage(data, state, region)
	if rank == 0:
		return {"troop_handling": 0, "cargo_handling": 0, "repair_pct": 0, "support": 0, "defense_pct": 0, "upkeep": 0}
	var out: Dictionary = rules(data)["stages"][rank - 1].duplicate()
	for id in facilities(data, state, region):
		var f: Dictionary = rules(data)["facilities"].get(id, {})
		out["upkeep"] += int(f.get("upkeep", 0))
		out["cargo_handling"] += int(f.get("cargo_bonus", 0))
		out["repair_pct"] += int(f.get("repair_bonus", 0))
		out["support"] += int(f.get("support_bonus", 0))
		out["defense_pct"] += int(f.get("defense_bonus", 0))
	return out

static func snapshot(data: GameData, state: Dictionary, region: String) -> Dictionary:
	# Public architecture only; no queues, crew, treasury or hidden roster.
	return {"stage": stage(data, state, region), "facilities": facilities(data, state, region),
		"setting": site(data, region).get("setting", "riverbank"), "project": record(state, region).get("project", {}).get("kind", "")}

static func project_quote(data: GameData, state: Dictionary, region: String, kind: String = "stage") -> Dictionary:
	var out := {"ok": false, "error": "no_water", "cost": 0, "turns": 0, "rank": 0, "level": ""}
	if site(data, region).is_empty() or not state.get("settlements", {}).has(region):
		return out
	var town: Dictionary = state["settlements"][region]
	var rank := stage(data, state, region)
	var numbers := {}
	if kind == "stage":
		if rank >= data.ports["stages"].size():
			out["error"] = "complete"
			return out
		out["rank"] = rank + 1
		out["level"] = stage_spec(data, rank + 1)["min_settlement"]
		numbers = rules(data)["stages"][rank]
	else:
		if not rules(data)["facilities"].has(kind):
			return out
		numbers = rules(data)["facilities"][kind]
	out["cost"] = int(numbers["cost"])
	out["turns"] = int(numbers["turns"])
	out["error"] = ""
	if town.get("siege") != null:
		out["error"] = "besieged"
	elif not record(state, region).get("project", {}).is_empty() or _legacy_project(data, state, region):
		out["error"] = "busy"
	elif kind == "stage" and not Constants.level_at_most(out["level"], SettlementRules.settlement_level(data, town)):
		out["error"] = "settlement_required"
	elif kind != "stage":
		for definition in data.ports["facilities"]:
			if definition["id"] == kind and rank < int(definition["stage"]):
				out["error"] = "stage_required"
		if facilities(data, state, region).has(kind):
			out["error"] = "already_built"
	if out["error"] == "" and int(state["factions"][town["owner"]]["treasury"]) < out["cost"]:
		out["error"] = "funds"
	out["ok"] = out["error"] == ""
	return out

static func _legacy_project(data: GameData, state: Dictionary, region: String) -> bool:
	for job in state["settlements"].get(region, {}).get("construction_queue", []):
		if data.chains.get(job["chain"], {}).get("kind", "") in ["port", "naval"]:
			return true
	for work in state.get("waterworks", {}).get("projects", []):
		if work["region"] == region and work["kind"] == "landing":
			return true
	return false

static func queue_project(data: GameData, state: Dictionary, region: String, kind: String = "stage") -> Dictionary:
	var quote := project_quote(data, state, region, kind)
	if not quote["ok"]:
		return quote
	var owner: String = state["settlements"][region]["owner"]
	state["factions"][owner]["treasury"] -= quote["cost"]
	live(state, region)["project"] = {"kind": kind, "rank": quote["rank"], "turns": quote["turns"], "owner": owner}
	return quote

static func advance(data: GameData, state: Dictionary) -> Array:
	ensure(state)
	var completed: Array = []
	var ids: Array = state["ports"].keys()
	ids.sort()
	for region in ids:
		var port: Dictionary = state["ports"][region]
		var job: Dictionary = port.get("project", {})
		if job.is_empty():
			continue
		var town: Dictionary = state["settlements"].get(region, {})
		if town.get("owner", "") != job["owner"]:
			port["project"] = {} # captured works are cancelled, never gifted to the old payer
			continue
		if town.get("siege") != null:
			continue
		job["turns"] = int(job["turns"]) - 1
		if int(job["turns"]) > 0:
			continue
		if job["kind"] == "stage":
			port["stage"] = maxi(int(port["stage"]), int(job["rank"]))
		else:
			if not port["facilities"].has(job["kind"]):
				port["facilities"].append(job["kind"])
		completed.append({"region": region, "owner": job["owner"], "kind": job["kind"], "rank": job["rank"]})
		port["project"] = {}
	return completed

static func vessel(data: GameData, template: String) -> Dictionary:
	return rules(data).get("vessels", {}).get(template, {})

static func ship_error(data: GameData, state: Dictionary, region: String, template: String, repair: bool = false) -> String:
	var definition: Dictionary = data.ports.get("vessels", {}).get(template, {})
	if definition.is_empty() or site(data, region).is_empty():
		return "ship_required"
	if stage(data, state, region) < int(definition["repair_stage"] if repair else definition["stage"]):
		return "stage_required"
	var have := facilities(data, state, region)
	var needs: Array = ["repair_yard"] if repair and int(definition["stage"]) >= 3 else ([] if repair else definition["facilities"])
	for id in needs:
		if not have.has(id):
			return "facility_required"
	if definition["deep_water"] and not site(data, region).get("deep_water", false):
		return "deep_required"
	if not MapRules.coastal(data, region) and not definition["waters"].has("river"):
		return "water_required"
	if MapRules.coastal(data, region) and WaterwayRules.river_access(data, region).is_empty() and not definition["waters"].has("coastal"):
		return "water_required"
	return ""

static func ship_quote(data: GameData, state: Dictionary, region: String, template: String) -> Dictionary:
	var unit: Dictionary = data.units.get(template, {})
	var out := {"ok": false, "error": "ship_required", "cost": 0, "turns": int(vessel(data, template).get("turns", 1))}
	var town: Dictionary = state["settlements"].get(region, {})
	if unit.is_empty() or town.is_empty() or unit.get("class") != "ship":
		return out
	out["cost"] = RecruitmentRules.recruit_cost(data, state, town["owner"], unit)
	out["error"] = ship_error(data, state, region, template)
	if out["error"] == "":
		if not unit["factions"].has("all") and not unit["factions"].has(town["owner"]):
			out["error"] = "wrong_owner"
		elif town.get("siege") != null:
			out["error"] = "besieged"
		elif town["recruitment_queue"].size() >= int(rules(data)["queue_limit"]):
			out["error"] = "queue_full"
		elif int(state["factions"][town["owner"]]["treasury"]) < out["cost"]:
			out["error"] = "funds"
		elif int(town["population"]) - int(unit["soldiers"]) < int(data.balance["growth"]["min_population"]):
			out["error"] = "population"
	out["ok"] = out["error"] == ""
	return out

static func migrate_navigation(data: GameData, state: Dictionary) -> void:
	if data == null or state.has("port_navigation_version"):
		return
	for fleet in state.get("fleets", {}).values():
		var river_voyage := bool(data.sea_zones.get(fleet["sea_zone"], {}).get("river", false))
		for zone in fleet.get("sail_path", []):
			river_voyage = river_voyage or bool(data.sea_zones.get(zone, {}).get("river", false))
		if river_voyage:
			for ship in fleet.get("ships", []):
				ship["legacy_river_access"] = true
	for region in state.get("settlements", {}):
		if not MapRules.coastal(data, region) and not WaterwayRules.river_access(data, region).is_empty():
			for ship in state["settlements"][region].get("harbour", []):
				ship["legacy_river_access"] = true
	state["port_navigation_version"] = 1

static func permits_water(data: GameData, ship: Dictionary, kind: String) -> bool:
	return (kind == "river" and ship.get("legacy_river_access", false)) or data.ports.get("vessels", {}).get(ship["template"], {}).get("waters", ["river", "coastal", "open"]).has(kind)

static func supports_zone(data: GameData, ships: Array, zone: String) -> bool:
	var kind := "river" if data.sea_zones.get(zone, {}).get("river", false) else "coastal"
	for ship in ships:
		if not permits_water(data, ship, kind):
			return false
	return true

static func fleet_capacity(data: GameData, fleet: Dictionary, kind: String = "troops") -> int:
	var total := 0
	for ship in fleet.get("ships", []):
		total += int(floor(float(vessel(data, ship["template"]).get(kind, 0)) * float(ship.get("strength_pct", 100)) / 100.0))
	return total

static func passengers(data: GameData, army: Dictionary) -> int:
	return CombatRules.soldiers_in(data, army.get("units", [])) + (int(rules(data).get("commander_passengers", 1)) if army.get("general") != null else 0)

static func handling_left(data: GameData, state: Dictionary, region: String) -> int:
	var port := record(state, region)
	var used := int(port.get("handled", 0)) if int(port.get("handling_turn", -1)) == int(state["turn"]) else 0
	return maxi(0, int(capabilities(data, state, region)["troop_handling"]) - used)

static func handle(state: Dictionary, region: String, troops: int) -> void:
	var port := live(state, region)
	if int(port["handling_turn"]) != int(state["turn"]):
		port["handled"] = 0
	port["handling_turn"] = int(state["turn"])
	port["handled"] += troops

static func delivery_capacity(data: GameData, state: Dictionary, fleet: Dictionary, route: Dictionary) -> int:
	return mini(fleet_capacity(data, fleet, "cargo"), mini(int(capabilities(data, state, route["from"])["cargo_handling"]), int(capabilities(data, state, route["to"])["cargo_handling"])))

static func defense(data: GameData, state: Dictionary, fleet: Dictionary) -> float:
	var best := 0.0
	for region in NavalRules.own_ports_on_zone(state, data, fleet["owner"], fleet["sea_zone"]):
		best = maxf(best, float(capabilities(data, state, region)["defense_pct"]))
	return best

static func repair_quote(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var out := {"ok": false, "error": "no_repairs", "count": 0, "cost": 0, "crew": 0, "ships": []}
	var town: Dictionary = state["settlements"].get(region, {})
	if town.is_empty():
		return out
	if town.get("siege") != null:
		out["error"] = "besieged"
		return out
	if int(record(state, region).get("repair_turn", -1)) == int(state["turn"]):
		out["error"] = "repair_spent"
		return out
	var caps := capabilities(data, state, region)
	var treasury := int(state["factions"][town["owner"]]["treasury"])
	var population := int(town["population"])
	for i in range(town.get("harbour", []).size()):
		var ship: Dictionary = town["harbour"][i]
		var row := {"index": i, "error": ship_error(data,state,region,ship["template"],true), "gained":0, "cost":0, "crew":0}
		var gained := mini(100-int(ship["strength_pct"]),int(caps["repair_pct"]))
		if row["error"] == "" and gained <= 0:
			row["error"] = "ready"
		if row["error"] == "":
			var template: Dictionary = data.units[ship["template"]]
			row["gained"] = gained
			row["cost"] = maxi(1,ceili(float(template["cost"])*gained/100.0*float(rules(data)["repair_cost_factor"])))
			row["crew"] = ceili(float(template["soldiers"])*(int(ship["strength_pct"])+gained)/100.0)-ceili(float(template["soldiers"])*int(ship["strength_pct"])/100.0)
			if out["count"] >= int(caps["support"]):
				row["error"] = "repair_limit"
			elif treasury < row["cost"]:
				row["error"] = "funds"
			elif population-row["crew"] < int(data.balance["growth"]["min_population"]):
				row["error"] = "population"
		if row["error"] == "":
			treasury -= row["cost"]
			population -= row["crew"]
			out["count"] += 1
			out["cost"] += row["cost"]
			out["crew"] += row["crew"]
		out["ships"].append(row)
	out["ok"] = out["count"] > 0
	if out["ok"]:
		out["error"] = ""
	return out

static func repair_harbour(data: GameData, state: Dictionary, region: String) -> Dictionary:
	var quote := repair_quote(data,state,region)
	if not quote["ok"]:
		return {"count":0,"cost":0}
	var town: Dictionary = state["settlements"][region]
	for row in quote["ships"]:
		if row["error"] != "":
			continue
		state["factions"][town["owner"]]["treasury"] -= row["cost"]
		RecruitmentRules.add_levy_strain(data,state,region,row["crew"])
		town["population"] -= row["crew"]
		SocietyRules.record_recruitment(data,state,region,row["crew"])
		town["harbour"][row["index"]]["strength_pct"] += row["gained"]
	live(state,region)["repair_turn"] = int(state["turn"])
	return {"count":quote["count"],"cost":quote["cost"]}
