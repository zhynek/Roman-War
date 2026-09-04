class_name AiAgents
## The AI's agents. One spy keeps the home watch; the espionage-minded send
## the rest to sit in enemy cities and open a gate when their own army is
## outside it. Envoys walk to whichever court the diplomacy behaviour wants
## to address next. Assassins go for the nearest enemy capital and strike
## when the odds clear the personality's bar. Every action is the same call
## the player's panel makes.


static func act(data: GameData, state: Dictionary, rng: CampaignRng, brain: Dictionary, notices: Array) -> void:
	if brain["is_rebel"]:
		return
	var faction_id: String = brain["id"]
	var home := home_region(data, state, faction_id)
	var home_watch_kept := false
	for agent_id in AgentRules.agents_of(state, faction_id):
		if not state["agents"].has(agent_id):
			continue
		var agent: Dictionary = state["agents"][agent_id]
		if AgentRules.can(data, agent, "negotiate"):
			run_envoy(data, state, brain, agent_id)
		elif AgentRules.can(data, agent, "assassinate"):
			run_assassin(data, state, rng, brain, agent_id, notices)
		elif AgentRules.can(data, agent, "counter_espionage"):
			# The first spy at home stays there as the watch.
			if not home_watch_kept and agent["region"] == home:
				home_watch_kept = true
				continue
			run_spy(data, state, rng, brain, agent_id, home, notices)


static func home_region(data: GameData, state: Dictionary, faction_id: String) -> String:
	var capital: String = state["factions"][faction_id]["capital"]
	if state["settlements"].has(capital) and state["settlements"][capital]["owner"] == faction_id:
		return capital
	var owned := AiController.settlements_of(state, faction_id)
	return owned[0] if not owned.is_empty() else ""


## --- Envoys ---------------------------------------------------------------------------

static func run_envoy(data: GameData, state: Dictionary, brain: Dictionary, agent_id: String) -> void:
	var memory: Dictionary = brain["memory"]
	var target: String = memory.get("envoy_target", "")
	if target == "" or not state["factions"].has(target) or not state["factions"][target]["alive"]:
		memory["envoy_target"] = ""
		return
	if AgentRules.in_contact(data, state, agent_id, target):
		memory["envoy_target"] = ""
		return
	var destination := nearest_settlement_of(data, state, target, state["agents"][agent_id]["region"])
	if destination != "":
		walk_toward(data, state, agent_id, destination, true)
		if AgentRules.in_contact(data, state, agent_id, target):
			memory["envoy_target"] = ""


## --- Spies ------------------------------------------------------------------------------

static func run_spy(data: GameData, state: Dictionary, rng: CampaignRng, brain: Dictionary, agent_id: String, home: String, notices: Array) -> void:
	var rules: Dictionary = brain["rules"]
	var agent: Dictionary = state["agents"][agent_id]
	if AgentRules.can_open_gates(data, state, agent_id):
		var result := AgentRules.open_gates(data, state, rng, agent_id)
		if not result.is_empty():
			notices.append({"kind": "gates", "from": brain["id"], "region": result["region"],
				"success": result["success"], "caught": result["caught"]})
		return
	if AiController.weight(brain, "espionage") < float(rules["spy_abroad_min_espionage"]):
		if agent["region"] != home and home != "":
			walk_toward(data, state, agent_id, home, false)
		return
	var post := enemy_post(data, state, brain, agent["region"])
	if post != "" and agent["region"] != post:
		walk_toward(data, state, agent_id, post, false)


## --- Assassins -----------------------------------------------------------------------------

static func run_assassin(data: GameData, state: Dictionary, rng: CampaignRng, brain: Dictionary, agent_id: String, notices: Array) -> void:
	var rules: Dictionary = brain["rules"]
	var faction_id: String = brain["id"]
	var best := {}
	for target in AgentRules.assassination_targets(data, state, agent_id):
		if not DiplomacyRules.at_war(state, faction_id, target["faction"]):
			continue
		if float(target["chance"]) < float(rules["assassin_min_chance"]):
			continue
		if best.is_empty() or float(target["chance"]) > float(best["chance"]):
			best = target
	if not best.is_empty():
		var result := AgentRules.assassinate(data, state, rng, agent_id, best["id"])
		if not result.is_empty():
			notices.append({"kind": "assassination", "from": faction_id, "faction": best["faction"],
				"target": best["id"], "target_name": best["name"], "target_kind": best["kind"],
				"success": result["success"], "caught": result["caught"]})
		return
	var post := enemy_post(data, state, brain, state["agents"][agent_id]["region"])
	if post != "" and state["agents"][agent_id]["region"] != post:
		walk_toward(data, state, agent_id, post, false)


## --- Shared ----------------------------------------------------------------------------------

static func enemy_post(data: GameData, state: Dictionary, brain: Dictionary, from_region: String) -> String:
	## The nearest city of a power we are at war with; "" in peacetime.
	var hops := MapRules.hops_from(data, from_region)
	var best := ""
	var best_distance := 1 << 30
	for enemy in AiController.enemies_of(data, state, brain["id"]):
		for region_id in AiController.settlements_of(state, enemy):
			var distance := int(hops.get(region_id, -1))
			if distance >= 0 and distance < best_distance:
				best = region_id
				best_distance = distance
	return best


static func nearest_settlement_of(data: GameData, state: Dictionary, faction_id: String, from_region: String) -> String:
	var hops := MapRules.hops_from(data, from_region)
	var best := ""
	var best_distance := 1 << 30
	for region_id in AiController.settlements_of(state, faction_id):
		var distance := int(hops.get(region_id, -1))
		if distance >= 0 and distance < best_distance:
			best = region_id
			best_distance = distance
	return best


static func walk_toward(data: GameData, state: Dictionary, agent_id: String, target: String, stop_adjacent: bool) -> bool:
	## Agents cross every border, so the shortest land path is simply walked
	## while movement lasts.
	var moved := false
	var hops := MapRules.hops_from(data, target)
	while state["agents"].has(agent_id):
		var here: String = state["agents"][agent_id]["region"]
		if here == target or (stop_adjacent and MapRules.are_adjacent(data, here, target)):
			break
		var best := ""
		var best_hops := int(hops.get(here, 1 << 20))
		var neighbors: Array = data.regions[here].get("adjacent", []).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			var distance := int(hops.get(neighbor, 1 << 20))
			if distance < best_hops:
				best = neighbor
				best_hops = distance
		if best == "" or not AgentRules.move(data, state, agent_id, best):
			break
		moved = true
	return moved
