class_name EventRules
## Date-triggered and condition-triggered events (including the marius-style
## army reform), plus regional disasters. Fired events are recorded in
## state.events_fired so once-only events never repeat.


static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	# Repeatable events rest between firings; their cooldowns tick first.
	if state.has("event_cooldowns"):
		var cooldowns: Dictionary = state["event_cooldowns"]
		var cooling_ids: Array = cooldowns.keys()
		cooling_ids.sort()
		for event_id in cooling_ids:
			cooldowns[event_id] = int(cooldowns[event_id]) - 1
			if int(cooldowns[event_id]) <= 0:
				cooldowns.erase(event_id)

	var fired: Array = []
	for event in data.events:
		var event_id: String = event["id"]
		var once: bool = event.get("once", true)
		if once and state["events_fired"].has(event_id):
			continue
		if not once and int(state.get("event_cooldowns", {}).get(event_id, 0)) > 0:
			continue
		var hit := _trigger_matches(data, state, event)
		if hit.is_empty():
			continue
		_apply_event(data, state, event, hit)
		if once:
			state["events_fired"].append(event_id)
		else:
			if not state.has("event_cooldowns"):
				state["event_cooldowns"] = {}
			state["event_cooldowns"][event_id] = int(event.get("cooldown_turns", 8))
		fired.append({"kind": "event", "id": event_id, "faction": hit.get("faction", "")})

	for disaster in data.disasters:
		if not rng.chance(float(disaster["chance_per_turn"])):
			continue
		var region_id: String = rng.pick(disaster["regions"])
		if not state["settlements"].has(region_id):
			continue
		_apply_disaster(state, disaster, region_id, rng)
		fired.append({"kind": "disaster", "id": disaster["id"], "region": region_id})
		ChronicleRules.record(data, state, "disaster",
			{"faction": state["settlements"][region_id]["owner"], "region": region_id},
			5, {"disaster": String(disaster["id"])})
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
			for faction_id in state["factions"]:
				if state["factions"][faction_id]["at_civil_war"]:
					return {"faction": faction_id}
			return {}
		"treasury_above":
			# A named faction's fortune, or the first (sorted) court so rich.
			var threshold := int(trigger.get("threshold", 0))
			var wanted := String(trigger.get("faction", ""))
			if wanted != "":
				if state["factions"].get(wanted, {}).get("alive", false) \
						and int(state["factions"][wanted]["treasury"]) > threshold:
					return {"faction": wanted}
				return {}
			var faction_ids: Array = state["factions"].keys()
			faction_ids.sort()  # first-match steers the context — sorted
			for faction_id in faction_ids:
				var faction: Dictionary = state["factions"][faction_id]
				if faction_id != "rebels" and faction["alive"] \
						and int(faction["treasury"]) > threshold:
					return {"faction": faction_id}
			return {}
		"regions_held":
			var needed := int(trigger.get("count", 0))
			var wanted := String(trigger.get("faction", ""))
			var counts := {}
			for settlement in state["settlements"].values():  # pure counting
				counts[settlement["owner"]] = int(counts.get(settlement["owner"], 0)) + 1
			if wanted != "":
				if state["factions"].get(wanted, {}).get("alive", false) \
						and int(counts.get(wanted, 0)) >= needed:
					return {"faction": wanted}
				return {}
			var faction_ids: Array = state["factions"].keys()
			faction_ids.sort()
			for faction_id in faction_ids:
				if faction_id != "rebels" and state["factions"][faction_id]["alive"] \
						and int(counts.get(faction_id, 0)) >= needed:
					return {"faction": faction_id}
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
	if effects.has("happiness_faction") and target != "":
		# A mood on ONE court's lands — the stacking modifier container, so
		# several such moods coexist (unlike the legacy single slot above).
		var mood: Dictionary = effects["happiness_faction"]
		ModifierRules.add(state, target, "", "happiness",
			float(mood["value"]), int(mood.get("turns", 4)), "event:" + String(event["id"]))
	if effects.has("grant_technique") and target != "":
		# Scripted historical spread: the craft becomes PRACTICED outright,
		# however the court stood with it before.
		var technique_id := String(effects["grant_technique"])
		if data.techniques.has(technique_id) and not KnowledgeRules.adopted(state, target, technique_id):
			KnowledgeRules.knowledge_of(state, target)[technique_id] = {
				"stage": "adopted", "turn": int(state["turn"]), "progress": 0, "discount_pct": 0.0,
			}
			ChronicleRules.record(data, state, "technique_adopted",
				{"faction": target, "technique": technique_id}, 4, {"scripted": true})


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
