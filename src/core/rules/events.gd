class_name EventRules
## Date-triggered and condition-triggered events (including the marius-style
## army reform), plus regional disasters. Fired events are recorded in
## state.events_fired so once-only events never repeat.


static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	var fired: Array = []
	for event in data.events:
		if event.get("once", true) and state["events_fired"].has(event["id"]):
			continue
		var hit := _trigger_matches(data, state, event)
		if hit.is_empty():
			continue
		_apply_event(data, state, event, hit)
		state["events_fired"].append(event["id"])
		fired.append({"kind": "event", "id": event["id"], "faction": hit.get("faction", "")})

	for disaster in data.disasters:
		if not rng.chance(float(disaster["chance_per_turn"])):
			continue
		var region_id: String = rng.pick(disaster["regions"])
		if not state["settlements"].has(region_id):
			continue
		_apply_disaster(state, disaster, region_id, rng)
		fired.append({"kind": "disaster", "id": disaster["id"], "region": region_id})
	return fired


static func _trigger_matches(data: GameData, state: Dictionary, event: Dictionary) -> Dictionary:
	## Returns {} for no match, or {faction: fid} context when matched.
	var trigger: Dictionary = event["trigger"]

	if trigger.has("year"):
		if int(state["year"]) >= int(trigger["year"]) and state["season"] == "summer":
			return {"faction": trigger.get("faction", "")}
		return {}

	match trigger.get("condition", ""):
		"huge_city_with_hidden_resource":
			var resource: String = trigger.get("hidden_resource", "")
			var excluded: Array = trigger.get("exclude_regions", [])
			var required_culture: String = trigger.get("culture", "")
			for region_id in state["settlements"]:
				if excluded.has(region_id):
					continue
				var region: Dictionary = data.regions[region_id]
				if resource != "" and not region.get("hidden_resources", []).has(resource):
					continue
				var settlement: Dictionary = state["settlements"][region_id]
				if SettlementRules.settlement_level(data, settlement) != "huge_city":
					continue
				var owner: String = settlement["owner"]
				if required_culture != "" and data.culture_of_faction(owner) != required_culture:
					continue
				return {"faction": owner}
			return {}
		"faction_destroyed":
			var target: String = trigger.get("faction", "")
			if target != "" and state["factions"].has(target) and not state["factions"][target]["alive"]:
				return {"faction": target}
			return {}
		"first_civil_war":
			var faction_ids: Array = state["factions"].keys()
			faction_ids.sort()
			for faction_id in faction_ids:
				if state["factions"][faction_id]["at_civil_war"]:
					return {"faction": faction_id}
			return {}
		"faction_holds_regions":
			# The first power to hold this many regions (sorted id breaks ties).
			var wanted := int(trigger.get("count", 999))
			var counts := {}
			for settlement in state["settlements"].values():
				var owner: String = settlement["owner"]
				counts[owner] = int(counts.get(owner, 0)) + 1
			var owner_ids: Array = counts.keys()
			owner_ids.sort()
			for owner_id in owner_ids:
				if data.factions.get(owner_id, {}).get("is_rebel", false):
					continue
				if int(counts[owner_id]) >= wanted:
					return {"faction": owner_id}
			return {}
	return {}


static func _apply_event(data: GameData, state: Dictionary, event: Dictionary, context: Dictionary) -> void:
	var effects: Dictionary = event.get("effects", {})
	if effects.get("marian_reforms", false):
		# Every roman-culture faction crosses to the professional-army era.
		for faction_id in state["factions"]:
			if data.culture_of_faction(faction_id) == "roman":
				state["factions"][faction_id]["era"] = "post_marian"
	var target: String = context.get("faction", "")
	if effects.has("treasury"):
		# Targeted events pay one faction; global (dated) events touch everyone.
		for faction_id in state["factions"]:
			if target != "" and faction_id != target:
				continue
			var faction: Dictionary = state["factions"][faction_id]
			if faction["alive"] and not data.factions.get(faction_id, {}).get("is_rebel", false):
				faction["treasury"] = int(faction["treasury"]) + int(effects["treasury"])
	if effects.has("happiness_all_settlements"):
		state["event_happiness"] = {
			"value": float(effects["happiness_all_settlements"]),
			"turns": int(effects.get("happiness_turns", 2)),
		}


static func tick_event_happiness(state: Dictionary) -> void:
	var event_happiness = state.get("event_happiness")
	if event_happiness == null:
		return
	event_happiness["turns"] = int(event_happiness["turns"]) - 1
	if int(event_happiness["turns"]) <= 0:
		state["event_happiness"] = null


static func _apply_disaster(state: Dictionary, disaster: Dictionary, region_id: String, rng: CampaignRng) -> void:
	var settlement: Dictionary = state["settlements"][region_id]
	var loss_pct := float(disaster.get("population_loss_pct", 0.0))
	var floor_population := 400
	settlement["population"] = maxi(floor_population, int(round(settlement["population"] * (1.0 - loss_pct / 100.0))))
	if rng.chance(float(disaster.get("building_damage_chance", 0.0))):
		var chain_ids: Array = settlement["buildings"].keys()
		if not chain_ids.is_empty():
			chain_ids.sort()
			var chain_id: String = rng.pick(chain_ids)
			var tier := int(settlement["buildings"][chain_id]) - 1
			if tier <= 0:
				settlement["buildings"].erase(chain_id)
			else:
				settlement["buildings"][chain_id] = tier
