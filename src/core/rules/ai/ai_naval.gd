class_name AiNaval
## Bounded local captains, using the player's owner-agnostic rule commands.
## No RNG outside the injected resolver, hidden fleet reads, or private jobs.
## Orders already persist as voyages, trade services and blockade stations.

static func take_turn(data: GameData, state: Dictionary, owner: String, rng: CampaignRng, resolver: BattleResolver) -> void:
	var owned := AiAssess.owned_regions(state, owner)
	var ports: Array = []
	for region in owned:
		if PortRules.stage(data, state, region) > 0:
			ports.append(region)
	var sight := VisibilityRules.visible_sea_zones(data, state, owner)
	var enemies: Array = []
	var ids: Array = state["fleets"].keys()
	ids.sort()
	for id in ids:
		var fleet: Dictionary = state["fleets"][id]
		if sight.has(fleet["sea_zone"]) and DiplomacyRules.at_war(state, owner, fleet["owner"]):
			enemies.append(id)
	# Combine idle squadrons before selecting objectives, conserving movement.
	for id in ids:
		if not state["fleets"].has(id): continue
		var fleet: Dictionary = state["fleets"][id]
		if fleet["owner"] != owner or not _idle(fleet) or BlockadeRules.pressure(data, fleet) <= 0: continue
		for other in ids:
			if other <= id or not state["fleets"].has(other): continue
			var candidate: Dictionary = state["fleets"][other]
			if candidate["owner"] == owner and _idle(candidate) and BlockadeRules.pressure(data, candidate) > 0 and fleet["ships"].size() + candidate["ships"].size() <= int(BlockadeRules.rules(data)["ai_group_size"]):
				NavalRules.merge_fleets(data, state, other, id)
	for id in ids:
		if state["fleets"].get(id, {}).get("owner", "") == owner:
			_operate(data, state, id, ports, enemies, rng, resolver)
	# A returning damaged fleet is now in the same harbour service boundary.
	for region in ports:
		var offer := PortRules.repair_quote(data, state, region)
		if offer["ok"] and int(state["factions"][owner]["treasury"]) - int(offer["cost"]) >= int(BlockadeRules.rules(data)["ai_reserve"]):
			PortRules.repair_harbour(data, state, region)
		_launch(data, state, region)
	_procure(data, state, owner, owned, ports, not AiAssess.enemies_of(state, owner).is_empty())

static func _idle(fleet: Dictionary) -> bool:
	return fleet.get("cargo", {}).is_empty() and fleet.get("sail_path", []).is_empty() and fleet.get("trade_route", {}).is_empty() and fleet.get("blockade", {}).is_empty()

static func _damaged(data: GameData, fleet: Dictionary) -> bool:
	for ship in fleet["ships"]:
		if int(ship["strength_pct"]) < int(BlockadeRules.rules(data)["ai_repair_below"]): return true
	return false

static func _power(data: GameData, fleet: Dictionary) -> float:
	return BattleResolver.force_strength(data, fleet["ships"], null, float(data.balance["battle"]["experience_strength_pct_per_chevron"]))

static func _safe(data: GameData, state: Dictionary, fleet: Dictionary, path: Array, enemies: Array, combat: bool) -> bool:
	var locations := path.duplicate()
	locations.append(fleet["sea_zone"])
	var opposing := {}
	for id in enemies:
		var enemy: Dictionary = state["fleets"].get(id, {})
		if not enemy.is_empty() and locations.has(enemy["sea_zone"]):
			if not combat: return false
			var zone: String = enemy["sea_zone"]
			opposing[zone] = float(opposing.get(zone, 0)) + _power(data, enemy) * (1.0 + PortRules.defense(data, state, enemy) / 100.0)
	for power in opposing.values():
		if _power(data, fleet) < float(power) * float(BlockadeRules.rules(data)["ai_attack_ratio"]): return false
	return true

static func _operate(data: GameData, state: Dictionary, id: String, ports: Array, enemies: Array, rng: CampaignRng, resolver: BattleResolver) -> void:
	var fleet: Dictionary = state["fleets"][id]
	if not fleet.get("cargo", {}).is_empty(): return # Invasion planning is a later phase.
	if _damaged(data, fleet):
		_return_for_repairs(data, state, id, ports, enemies, rng, resolver)
		return
	if not fleet.get("blockade", {}).is_empty():
		if BlockadeRules.active(data, state, fleet): return
		fleet["blockade"] = {}
	if not fleet.get("trade_route", {}).is_empty() or not fleet.get("sail_path", []).is_empty(): return
	var military := BlockadeRules.pressure(data, fleet) > 0
	if military:
		# Visible threats to an owned waterfront outrank offensive stations.
		var best := {}
		for enemy_id in enemies:
			var enemy: Dictionary = state["fleets"].get(enemy_id, {})
			if enemy.is_empty(): continue
			var local := false
			for region in ports:
				if NavalRules.zones_touching(data, region).has(enemy["sea_zone"]): local = true
			if not local: continue
			var route := WaterwayRules.preview(data, state, id, enemy["sea_zone"])
			if route.is_empty() or int(route["turns"]) > int(BlockadeRules.rules(data)["ai_local_turns"]) or not _safe(data, state, fleet, route["path"], enemies, true): continue
			if best.is_empty() or route["cost"] < best["cost"]:
				best = {"enemy": enemy_id, "zone": enemy["sea_zone"], "cost": route["cost"]}
		if not best.is_empty():
			if fleet["sea_zone"] == best["zone"]:
				WaterwayRules.battle(data, state, id, best["enemy"], resolver, rng)
			else:
				WaterwayRules.order(data, state, id, best["zone"], "coastal", resolver, rng)
			return
		if _seek_blockade(data, state, id, enemies, rng, resolver): return
		# Idle guards stay near an owned port instead of being tied to freight.
		return
	_assign_trade(data, state, id, ports, enemies, rng, resolver)

static func _return_for_repairs(data: GameData, state: Dictionary, id: String, ports: Array, enemies: Array, rng: CampaignRng, resolver: BattleResolver) -> void:
	var fleet: Dictionary = state["fleets"][id]
	var best := {}
	for region in ports:
		if BlockadeRules.blocked(data, state, region): continue
		var eligible := true
		for ship in fleet["ships"]:
			if int(ship["strength_pct"]) < 100 and PortRules.ship_error(data, state, region, ship["template"], true) != "": eligible = false
		if not eligible: continue
		for zone in NavalRules.zones_touching(data, region):
			if not WaterwayRules.access(data, state, fleet["owner"], region, zone, true): continue
			var route := WaterwayRules.preview(data, state, id, zone)
			if route.is_empty() or not _safe(data, state, fleet, route["path"], enemies, false): continue
			if best.is_empty() or route["cost"] < best["cost"]: best = {"region": region, "zone": zone, "cost": route["cost"]}
	if best.is_empty(): return
	fleet["blockade"] = {}
	fleet["trade_route"] = {}
	if fleet["sea_zone"] == best["zone"]:
		fleet["sail_path"] = []
		NavalRules.dock_fleet(data, state, id, best["region"])
	else:
		WaterwayRules.order(data, state, id, best["zone"], "coastal", resolver, rng)

static func _seek_blockade(data: GameData, state: Dictionary, id: String, enemies: Array, rng: CampaignRng, resolver: BattleResolver) -> bool:
	var fleet: Dictionary = state["fleets"][id]
	var regions: Array = VisibilityRules.visible_regions(data, state, fleet["owner"]).keys()
	regions.sort()
	var best := {}
	for region in regions:
		var town: Dictionary = state["settlements"].get(region, {})
		if town.is_empty() or not DiplomacyRules.at_war(state, fleet["owner"], town["owner"]) or PortRules.stage(data, state, region) == 0 or BlockadeRules.blocked(data, state, region): continue
		if BlockadeRules.pressure(data, fleet) < BlockadeRules.required(data, state, region): continue
		for zone in NavalRules.zones_touching(data, region):
			var route := WaterwayRules.preview(data, state, id, zone)
			if route.is_empty() or int(route["turns"]) > int(BlockadeRules.rules(data)["ai_local_turns"]) or not _safe(data, state, fleet, route["path"], enemies, true): continue
			if best.is_empty() or route["cost"] < best["cost"]: best = {"region": region, "zone": zone, "cost": route["cost"]}
	if best.is_empty() or int(state["factions"][fleet["owner"]]["treasury"]) < int(BlockadeRules.rules(data)["ai_reserve"]) + BlockadeRules.cost(data, fleet): return false
	if fleet["sea_zone"] == best["zone"]:
		var contact := WaterwayRules.hostiles(state, fleet)
		if contact.is_empty():
			BlockadeRules.begin(data, state, id, best["region"])
		else:
			WaterwayRules.battle(data, state, id, contact[0], resolver, rng)
	else:
		WaterwayRules.order(data, state, id, best["zone"], "coastal", resolver, rng)
	return true

static func _assign_trade(data: GameData, state: Dictionary, id: String, ports: Array, enemies: Array, rng: CampaignRng, resolver: BattleResolver) -> void:
	var fleet: Dictionary = state["fleets"][id]
	var best := {}
	for region in ports:
		if not WaterwayRules.access(data, state, fleet["owner"], region, fleet["sea_zone"], true): continue
		for target in ports:
			var offer := WaterwayRules.trade_quote(data, state, id, region, target)
			if not offer["ok"] or int(offer["turns"]) > int(BlockadeRules.rules(data)["ai_trade_turns"]) or not _safe(data, state, fleet, offer["path"], enemies, false): continue
			if best.is_empty() or offer["cost"] < best["cost"]: best = offer
	if not best.is_empty():
		WaterwayRules.assign_trade(data, state, id, best["from"], best["to"])
		return
	# Reposition an unassigned merchant to the nearest accessible home port.
	var home := {}
	for region in ports:
		if BlockadeRules.blocked(data, state, region): continue
		for zone in NavalRules.zones_touching(data, region):
			if not WaterwayRules.access(data, state, fleet["owner"], region, zone, true): continue
			var route := WaterwayRules.preview(data, state, id, zone)
			if route.is_empty() or not _safe(data, state, fleet, route["path"], enemies, false): continue
			if home.is_empty() or route["cost"] < home["cost"]: home = {"zone": zone, "cost": route["cost"]}
	if not home.is_empty() and home["zone"] != fleet["sea_zone"]:
		WaterwayRules.order(data, state, id, home["zone"], "coastal", resolver, rng)

static func _launch(data: GameData, state: Dictionary, region: String) -> void:
	var harbour: Array = state["settlements"][region].get("harbour", [])
	for zone in NavalRules.zones_touching(data, region):
		var indices: Array = []
		var role := ""
		for i in range(harbour.size()):
			var ship: Dictionary = harbour[i]
			if int(ship["strength_pct"]) < int(BlockadeRules.rules(data)["ai_launch_readiness"]) or not PortRules.supports_zone(data, [ship], zone): continue
			var next_role := "military" if BlockadeRules.military(data, ship) else "trade"
			if role != "" and role != next_role: continue
			role = next_role
			indices.append(i)
			if next_role == "trade" or indices.size() >= int(BlockadeRules.rules(data)["ai_group_size"]): break
		if not indices.is_empty() and NavalRules.launch_fleet(data, state, region, indices, zone)["ok"]: return

static func _procure(data: GameData, state: Dictionary, owner: String, owned: Array, ports: Array, war: bool) -> void:
	var rules := BlockadeRules.rules(data)
	var budget := int(state["factions"][owner]["treasury"]) - int(rules["ai_reserve"])
	var net := float(EconomyRules.faction_turn_breakdown(data, state, owner)["net"])
	var military := 0
	var traders := 0
	var ships: Array = []
	for fleet in state["fleets"].values():
		if fleet["owner"] == owner: ships.append_array(fleet["ships"])
	for region in owned:
		ships.append_array(state["settlements"][region].get("harbour", []))
		for job in state["settlements"][region]["recruitment_queue"]:
			net -= float(data.units[job["template"]]["upkeep"])
			if data.units[job["template"]].get("class", "") == "ship": ships.append(job)
	for ship in ships:
		if BlockadeRules.military(data, ship): military += 1
		else: traders += 1
	if budget <= 0 or net < float(rules["ai_min_net"]): return
	var guard_needed := war and military < int(rules["ai_military_hulls"])
	var trade_needed := traders < mini(maxi(0, ports.size() - 1), int(rules["ai_trade_hulls"]))
	var ids: Array = data.ports.get("vessels", {}).keys()
	ids.sort()
	var best := {}
	var score := -INF
	for region in ports:
		if not state["settlements"][region]["recruitment_queue"].is_empty(): continue
		for template in ids:
			var ship := {"template": template, "strength_pct": 100, "experience": 0}
			var is_guard := BlockadeRules.military(data, ship)
			if not (guard_needed if is_guard else trade_needed): continue
			var offer := PortRules.ship_quote(data, state, region, template)
			var unit: Dictionary = data.units[template]
			if not offer["ok"] or int(offer["cost"]) > budget or net - float(unit["upkeep"]) < float(rules["ai_min_net"]): continue
			var value := (_power(data, {"ships": [ship]}) if is_guard else float(PortRules.vessel(data, template)["cargo"])) / maxf(1, float(unit["upkeep"]))
			if best.is_empty() or (is_guard and not best["guard"]) or (is_guard == best["guard"] and value > score):
				best = {"region": region, "template": template, "guard": is_guard}
				score = value
	if not best.is_empty():
		RecruitmentRules.queue_unit(data, state, best["region"], best["template"])
		return
	# At most one investment per faction/season, using normal port prerequisites.
	for region in owned:
		var stage := PortRules.stage(data, state, region)
		var kind := ""
		if stage == 0 and ports.size() < int(rules["ai_trade_hulls"]): kind = "stage"
		elif guard_needed or trade_needed:
			if stage < _yard_stage(data): kind = "stage"
			elif not PortRules.facilities(data, state, region).has("repair_yard"): kind = "repair_yard"
			elif stage < int(rules["ai_development_stage"]): kind = "stage"
			elif guard_needed and not PortRules.facilities(data, state, region).has("arsenal"): kind = "arsenal"
			elif trade_needed and not PortRules.facilities(data, state, region).has("depot"): kind = "depot"
		if kind == "": continue
		var offer := PortRules.project_quote(data, state, region, kind)
		if offer["ok"] and int(offer["cost"]) <= budget:
			PortRules.queue_project(data, state, region, kind)
			return

static func _yard_stage(data: GameData) -> int:
	for facility in data.ports.get("facilities", []):
		if facility["id"] == "repair_yard": return int(facility["stage"])
	return 0
