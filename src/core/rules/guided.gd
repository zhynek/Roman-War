class_name GuidedRules
## The guided campaign trail: data-driven stages (data/guided_campaign.json)
## that teach the systems, react to the live world (wars declared on the
## player, sieges, intruders, debt), and pay rewards — gold, granted units,
## experience, and small permanent faction boons.
##
## Deterministic by construction: process_turn draws NO randomness, iterates
## the stages in authored array order, and scans state dicts in sorted order.
## Evaluation is two-phase — completion/expiry first, activation second — so a
## reactive stage can never activate and complete in the same turn. Player
## deeds are recorded as counters: intent-shaped ones bump in the Game facade
## (the AI never calls Game), while battles won and regions captured bump at
## CombatRules choke points so defensive victories and starve-out captures
## count too. Every bump routes through bump(), which no-ops unless the trail
## exists and is enabled — fixture states and pre-trail saves stay valid.

const COUNTER_KEYS := {
	"set_taxes": "taxes_set",
	"queue_building": "buildings_queued",
	"recruit_units": "units_recruited",
	"raise_army": "armies_raised",
	"move_army": "army_moves",
	"hire_mercenaries": "mercs_hired",
	"explore_sites": "sites_explored",
	"win_battles": "battles_won",
	"capture_regions": "regions_captured",
	"senate_missions": "senate_missions",
	"offices_won": "offices_won",
}


static func bump(state: Dictionary, key: String, amount: int = 1) -> void:
	var guided = state.get("guided")
	if guided == null or not guided.get("enabled", false):
		return
	var counters: Dictionary = guided["counters"]
	counters[key] = int(counters.get(key, 0)) + amount


static func process_turn(data: GameData, state: Dictionary) -> Array:
	var notices: Array = []
	var guided = state.get("guided")
	if guided == null or not guided.get("enabled", false) or data.guided_stages.is_empty():
		return notices
	var stage_states: Dictionary = guided["stages"]

	# Pass 1 — judge the active stages against the turn's final world.
	for stage in data.guided_stages:
		var inst = stage_states.get(stage["id"])
		if inst == null or inst["status"] != "active":
			continue
		if _stage_met(data, state, stage, inst):
			_grant_reward(data, state, stage.get("reward", {}))
			_close(state, stage, inst, "done")
			notices.append({"kind": "stage_complete", "stage": stage["id"]})
		elif stage.has("expires_turns") \
				and int(state["turn"]) - int(inst["started_turn"]) >= int(stage["expires_turns"]):
			_close(state, stage, inst, "expired")
			notices.append({"kind": "stage_expired", "stage": stage["id"]})

	# Pass 2 — open whatever the world now calls for.
	for stage in data.guided_stages:
		var inst = stage_states.get(stage["id"])
		if inst != null and inst["status"] != "cooldown":
			continue  # active, done, or expired — nothing to open
		if not _trigger_ready(data, state, stage, inst):
			continue
		stage_states[stage["id"]] = {
			"status": "active",
			"started_turn": int(state["turn"]),
			"base": guided["counters"].duplicate(true),
			"target": _instance_target(data, state, stage),
			"fired": (int(inst["fired"]) if inst != null else 0) + 1,
			"cooldown_until": 0,
		}
		notices.append({"kind": "stage_started", "stage": stage["id"]})
	return notices


static func overview(data: GameData, state: Dictionary) -> Dictionary:
	## Pure query for the UI: the live trail, per-objective progress, and a
	## suggested map target where one helps. Draws no randomness.
	var guided = state.get("guided")
	var result := {"enabled": false, "active": [], "done": 0, "total": 0}
	if guided == null or not guided.get("enabled", false):
		return result
	result["enabled"] = true
	var stage_states: Dictionary = guided["stages"]
	var player_is_roman: bool = data.factions.get(state["player_faction"], {}).get("is_roman_house", false)
	for stage in data.guided_stages:
		# Stages the player's faction can never open stay out of the tally.
		if stage["trigger"].get("roman_only", false) and not player_is_roman:
			continue
		if not stage.get("repeatable", false):
			result["total"] += 1
		var inst = stage_states.get(stage["id"])
		if inst == null:
			continue
		if inst["status"] == "done" and not stage.get("repeatable", false):
			result["done"] += 1
		if inst["status"] != "active":
			continue
		var objectives: Array = []
		var wants_capture_hint := false
		for objective in stage["objectives"]:
			var status := _objective_status(data, state, stage, objective, inst)
			status["kind"] = objective["kind"]
			objectives.append(status)
			if objective["kind"] == "capture_regions" and not status["met"]:
				wants_capture_hint = true
		var target = inst.get("target")
		if (target == null or target == "") and wants_capture_hint:
			target = AiAssess.choose_target(data, state, state["player_faction"])
		var expires_in = null
		if stage.has("expires_turns"):
			expires_in = int(stage["expires_turns"]) - (int(state["turn"]) - int(inst["started_turn"]))
		result["active"].append({
			"id": stage["id"], "name": stage["name"], "text": stage["text"],
			"complete": stage.get("complete", "all"),
			"objectives": objectives,
			"reward": stage.get("reward", {}),
			"target_region": target if target != null else "",
			"expires_in": expires_in,
		})
	return result


## --- Stage judgement -------------------------------------------------------

static func _stage_met(data: GameData, state: Dictionary, stage: Dictionary, inst: Dictionary) -> bool:
	var mode: String = stage.get("complete", "all")
	for objective in stage["objectives"]:
		var met: bool = _objective_status(data, state, stage, objective, inst)["met"]
		if mode == "any" and met:
			return true
		if mode == "all" and not met:
			return false
	return mode == "all"


static func _objective_status(data: GameData, state: Dictionary, stage: Dictionary, objective: Dictionary, inst: Dictionary) -> Dictionary:
	var kind: String = objective["kind"]
	var player: String = state["player_faction"]
	if COUNTER_KEYS.has(kind):
		var key: String = COUNTER_KEYS[kind]
		if kind == "queue_building" and objective.has("building_kind"):
			key = "%s:%s" % [key, objective["building_kind"]]
		var counters: Dictionary = state["guided"]["counters"]
		var have := int(counters.get(key, 0))
		# Recurring challenges demand fresh deeds — repeatable stages, and any
		# objective flagged fresh, measure from their opening snapshot. The
		# rest of the tutorial arc credits the whole campaign's history, so a
		# battle won or a site searched before its stage opens still counts.
		if stage.get("repeatable", false) or objective.get("fresh", false):
			have -= int(inst["base"].get(key, 0))
		var need := int(objective.get("count", 1))
		return {"met": have >= need, "have": maxi(have, 0), "need": need}
	match kind:
		"hold_regions":
			var have := AiAssess.owned_regions(state, player).size()
			var need := int(objective.get("count", 1))
			return {"met": have >= need, "have": have, "need": need}
		"treasury_at_least":
			var have := int(state["factions"][player]["treasury"])
			var need := int(objective.get("amount", 1))
			return {"met": have >= need, "have": have, "need": need}
		"governor_in_capital":
			var capital: String = state["factions"][player]["capital"]
			var met: bool = state["settlements"].has(capital) \
				and state["settlements"][capital]["owner"] == player \
				and state["settlements"][capital]["governor"] != null
			return {"met": met, "have": 1 if met else 0, "need": 1}
		"no_siege_on_target":
			var target = inst.get("target")
			var met: bool = target != null and target != "" \
				and state["settlements"].has(target) \
				and state["settlements"][target]["owner"] == player \
				and state["settlements"][target]["siege"] == null
			return {"met": met, "have": 1 if met else 0, "need": 1}
		"no_intruders":
			var met := _first_intruded_region(data, state) == ""
			return {"met": met, "have": 1 if met else 0, "need": 1}
	return {"met": false, "have": 0, "need": 1}


## --- Triggers --------------------------------------------------------------

static func _trigger_ready(data: GameData, state: Dictionary, stage: Dictionary, inst) -> bool:
	if inst != null and int(state["turn"]) < int(inst["cooldown_until"]):
		return false
	var trigger: Dictionary = stage["trigger"]
	if trigger.has("min_turn") and int(state["turn"]) < int(trigger["min_turn"]):
		return false
	if trigger.get("roman_only", false) \
			and not data.factions.get(state["player_faction"], {}).get("is_roman_house", false):
		return false
	for ref in trigger.get("requires", []):
		if not _closed(state, ref):
			return false
	match trigger["kind"]:
		"start":
			return true
		"after":
			for ref in trigger["stages"]:
				if not _closed(state, ref):
					return false
			return true
		"player_at_war":
			# Stances are symmetric and record no declarer, so this honestly
			# means "a war with a living non-rebel faction is under way" —
			# the player's own declarations open it too.
			return not _non_rebel_enemies(data, state).is_empty()
		"player_settlement_besieged":
			return _besieged_player_region(state) != ""
		"intruders_in_player_lands":
			return _first_intruded_region(data, state) != ""
		"player_in_debt":
			return int(state["factions"][state["player_faction"]]["treasury"]) < 0
	return false


static func _closed(state: Dictionary, stage_id: String) -> bool:
	## Done, expired, or resting between firings — expiry closes a stage
	## without failing the trail, so followers still open.
	var inst = state["guided"]["stages"].get(stage_id)
	return inst != null and inst["status"] in ["done", "expired", "cooldown"]


static func _close(state: Dictionary, stage: Dictionary, inst: Dictionary, outcome: String) -> void:
	if stage.get("repeatable", false):
		inst["status"] = "cooldown"
		inst["cooldown_until"] = int(state["turn"]) + int(stage.get("cooldown_turns", 1))
	else:
		inst["status"] = outcome


static func _instance_target(data: GameData, state: Dictionary, stage: Dictionary) -> Variant:
	## Only REGION ids belong here — the UI feeds the target straight into the
	## map's highlight ring. A war stage carries no region of its own; leaving
	## its target empty lets the capture-hint fallback suggest one.
	match stage["trigger"]["kind"]:
		"player_settlement_besieged":
			return _besieged_player_region(state)
		"intruders_in_player_lands":
			return _first_intruded_region(data, state)
	return null


## --- World scans (sorted, deterministic) ----------------------------------

static func _non_rebel_enemies(data: GameData, state: Dictionary) -> Array:
	var found: Array = []
	for enemy_id in AiAssess.enemies_of(state, state["player_faction"]):
		if not data.factions.get(enemy_id, {}).get("is_rebel", false):
			found.append(enemy_id)
	return found


static func _besieged_player_region(state: Dictionary) -> String:
	var player: String = state["player_faction"]
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		if settlement["owner"] == player and settlement["siege"] != null:
			return region_id
	return ""


static func _first_intruded_region(data: GameData, state: Dictionary) -> String:
	## The first (sorted) player region with an at-war army standing in it or
	## next door — the display target for border-defence objectives.
	var player: String = state["player_faction"]
	for region_id in AiAssess.owned_regions(state, player):
		if not AiAssess.hostile_armies_in(state, player, region_id).is_empty():
			return region_id
		for neighbor in data.regions[region_id].get("adjacent", []):
			if data.regions.has(neighbor) \
					and not AiAssess.hostile_armies_in(state, player, neighbor).is_empty():
				return region_id
	return ""


## --- Rewards ---------------------------------------------------------------

static func _grant_reward(data: GameData, state: Dictionary, reward: Dictionary) -> void:
	var player: String = state["player_faction"]
	var faction: Dictionary = state["factions"][player]
	faction["treasury"] = int(faction["treasury"]) + int(reward.get("treasury", 0))
	grant_units_to_capital(state, player, reward.get("units", []))

	var experience := int(reward.get("experience", 0))
	if experience > 0:
		var cap := int(data.balance["recruitment"]["experience_max"])
		var army_ids: Array = state["armies"].keys()
		army_ids.sort()
		for army_id in army_ids:
			var army: Dictionary = state["armies"][army_id]
			if army["owner"] != player:
				continue
			for unit in army["units"]:
				unit["experience"] = mini(int(unit["experience"]) + experience, cap)

	var boon: Dictionary = reward.get("boon", {})
	if not boon.is_empty():
		if not faction.has("boons"):
			faction["boons"] = {}
		var keys: Array = boon.keys()
		keys.sort()
		for key in keys:
			faction["boons"][key] = float(faction["boons"].get(key, 0.0)) + float(boon[key])


static func grant_units_to_capital(state: Dictionary, faction_id: String, grants: Array) -> void:
	## The senate-mission pattern: granted units muster in the capital's
	## garrison, silently lost if the capital is not held.
	var capital: String = state["factions"][faction_id]["capital"]
	if not state["settlements"].has(capital) or state["settlements"][capital]["owner"] != faction_id:
		return
	for grant in grants:
		for i in range(int(grant["count"])):
			state["settlements"][capital]["garrison"].append({
				"template": grant["template"], "experience": 0, "strength_pct": 100,
			})
