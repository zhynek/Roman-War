class_name SenateRules
## Minimal senate loop for the foundation (full politics is a later phase, but
## the standing fields and mission state exist from day one so nothing needs a
## retrofit): standings drift with expansion, missions are issued from data
## templates, deadlines are enforced, and the civil-war threshold is evaluated.


static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	var senate_rules: Dictionary = data.balance["senate"]
	var notices: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction["alive"] or not data.factions.get(faction_id, {}).get("is_roman_house", false):
			continue

		# Expansion pleases the people and unsettles the senate.
		var region_count := _region_count(state, faction_id)
		faction["popular_standing"] = minf(
			float(senate_rules["max_standing"]),
			float(region_count) * float(senate_rules["popular_standing_per_region"]))

		var mission = faction["mission"]
		if mission == null:
			var new_mission := _issue_mission(data, state, faction_id, rng)
			if not new_mission.is_empty():
				faction["mission"] = new_mission
				notices.append({"kind": "mission_issued", "faction": faction_id, "mission": new_mission["template"]})
		else:
			mission["turns_left"] = int(mission["turns_left"]) - 1
			if _mission_complete(state, faction_id, mission):
				var template: Dictionary = data.missions[mission["template"]]
				var reward: Dictionary = template.get("reward", {})
				faction["treasury"] = int(faction["treasury"]) + int(reward.get("treasury", 0))
				faction["senate_standing"] = minf(float(senate_rules["max_standing"]),
					float(faction["senate_standing"]) + float(reward.get("senate_standing",
						senate_rules["mission_success_standing"])))
				_grant_reward_units(state, faction_id, reward)
				faction["mission"] = null
				notices.append({"kind": "mission_complete", "faction": faction_id, "mission": mission["template"]})
			elif int(mission["turns_left"]) <= 0:
				var template: Dictionary = data.missions[mission["template"]]
				var penalty: Dictionary = template.get("penalty", {})
				faction["senate_standing"] = maxf(float(senate_rules["min_standing"]),
					float(faction["senate_standing"]) + float(penalty.get("senate_standing",
						senate_rules["mission_fail_standing"])))
				faction["mission"] = null
				notices.append({"kind": "mission_failed", "faction": faction_id, "mission": mission["template"]})

		# Civil war becomes available (or is forced by outlawing) at the thresholds.
		if not faction["at_civil_war"] \
				and float(faction["popular_standing"]) >= float(senate_rules["civil_war_popular_threshold"]) \
				and float(faction["senate_standing"]) <= float(senate_rules["civil_war_senate_threshold"]):
			faction["at_civil_war"] = true
			_declare_civil_war(data, state, faction_id)
			notices.append({"kind": "civil_war", "faction": faction_id})
	return notices


static func _issue_mission(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng) -> Dictionary:
	## Foundation scope: take_region missions targeting a nearby rebel region.
	var candidates: Array = []
	for mission_id in data.missions:
		var template: Dictionary = data.missions[mission_id]
		if template["kind"] != "take_region":
			continue
		if template.has("min_year") and int(state["year"]) < int(template["min_year"]):
			continue
		candidates.append(mission_id)
	if candidates.is_empty():
		return {}

	var targets: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()  # canonical order — targets feed rng.pick
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] == "rebels":
			for neighbor in data.regions[region_id].get("adjacent", []):
				if state["settlements"].has(neighbor) and state["settlements"][neighbor]["owner"] == faction_id:
					targets.append(region_id)
					break
	if targets.is_empty():
		return {}

	var template_id: String = rng.pick(candidates)
	return {
		"template": template_id,
		"target_region": rng.pick(targets),
		"turns_left": int(data.missions[template_id]["deadline_turns"]),
	}


static func _grant_reward_units(state: Dictionary, faction_id: String, reward: Dictionary) -> void:
	## Granted units muster in the capital's garrison.
	var capital: String = state["factions"][faction_id]["capital"]
	if not state["settlements"].has(capital) or state["settlements"][capital]["owner"] != faction_id:
		return
	for grant in reward.get("units", []):
		for i in range(int(grant["count"])):
			state["settlements"][capital]["garrison"].append({
				"template": grant["template"], "experience": 0, "strength_pct": 100,
			})


static func _mission_complete(state: Dictionary, faction_id: String, mission: Dictionary) -> bool:
	var target: String = mission.get("target_region", "")
	return target != "" and state["settlements"].has(target) \
		and state["settlements"][target]["owner"] == faction_id


static func _region_count(state: Dictionary, faction_id: String) -> int:
	var count := 0
	for settlement in state["settlements"].values():
		if settlement["owner"] == faction_id:
			count += 1
	return count


static func _declare_civil_war(data: GameData, state: Dictionary, rebel_house: String) -> void:
	for other_id in state["factions"]:
		if other_id == rebel_house:
			continue
		var other: Dictionary = data.factions.get(other_id, {})
		if other.get("is_roman_house", false) or other.get("is_senate", false):
			state["factions"][rebel_house]["diplomacy"][other_id] = "war"
			state["factions"][other_id]["diplomacy"][rebel_house] = "war"
