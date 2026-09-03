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
				notices.append({"kind": "mission_issued", "faction": faction_id,
					"mission": new_mission["template"], "target": _target_of(new_mission)})
		else:
			mission["turns_left"] = int(mission["turns_left"]) - 1
			if _mission_complete(data, state, faction_id, mission):
				var template: Dictionary = data.missions[mission["template"]]
				var reward: Dictionary = template.get("reward", {})
				faction["treasury"] = int(faction["treasury"]) + int(reward.get("treasury", 0))
				faction["senate_standing"] = minf(float(senate_rules["max_standing"]),
					float(faction["senate_standing"]) + float(reward.get("senate_standing",
						senate_rules["mission_success_standing"])))
				_grant_reward_units(state, faction_id, reward)
				faction["mission"] = null
				notices.append({"kind": "mission_complete", "faction": faction_id,
					"mission": mission["template"], "target": _target_of(mission)})
			elif int(mission["turns_left"]) <= 0:
				var template: Dictionary = data.missions[mission["template"]]
				var penalty: Dictionary = template.get("penalty", {})
				faction["senate_standing"] = maxf(float(senate_rules["min_standing"]),
					float(faction["senate_standing"]) + float(penalty.get("senate_standing",
						senate_rules["mission_fail_standing"])))
				faction["mission"] = null
				notices.append({"kind": "mission_failed", "faction": faction_id,
					"mission": mission["template"], "target": _target_of(mission)})

		# Civil war becomes available (or is forced by outlawing) at the thresholds.
		if not faction["at_civil_war"] \
				and float(faction["popular_standing"]) >= float(senate_rules["civil_war_popular_threshold"]) \
				and float(faction["senate_standing"]) <= float(senate_rules["civil_war_senate_threshold"]):
			faction["at_civil_war"] = true
			_declare_civil_war(data, state, faction_id)
			notices.append({"kind": "civil_war", "faction": faction_id})
	return notices


static func _issue_mission(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng) -> Dictionary:
	## Every template whose kind the house can act on right now is in the
	## draw: a rebel border town to take, a foreign court within reach to
	## court or to open to trade, a hostile king to remove. The template is
	## drawn first, then its target, so a kind with many targets is no likelier
	## than one with a single target.
	var rebel_targets := _rebel_border_regions(data, state, faction_id)
	var courts := _courts_in_reach(data, state, faction_id)
	var options := {}  # template id -> [mission dicts]
	var mission_ids: Array = data.missions.keys()
	mission_ids.sort()
	for mission_id in mission_ids:
		var template: Dictionary = data.missions[mission_id]
		if template.has("min_year") and int(state["year"]) < int(template["min_year"]):
			continue
		var targets: Array = []
		match template["kind"]:
			"take_region":
				for region_id in rebel_targets:
					targets.append({"target_region": region_id})
			"make_alliance":
				for other in courts:
					if DiplomacyRules.stance_between(state, faction_id, other) not in ["alliance", "war"]:
						targets.append({"target_faction": other})
			"reach_trade_agreement":
				for other in courts:
					if DiplomacyRules.stance_between(state, faction_id, other) == "neutral":
						targets.append({"target_faction": other})
			"assassinate_leader":
				for other in courts:
					var leader := FamilyRules.leader_of(state, other)
					if leader != "" and DiplomacyRules.at_war(state, faction_id, other):
						targets.append({"target_faction": other, "target_character": leader})
		if not targets.is_empty():
			options[mission_id] = targets
	if options.is_empty():
		return {}
	var template_ids: Array = options.keys()
	template_ids.sort()
	var template_id: String = rng.pick(template_ids)
	var mission: Dictionary = rng.pick(options[template_id])
	mission["template"] = template_id
	mission["turns_left"] = int(data.missions[template_id]["deadline_turns"])
	return mission


static func _target_of(mission: Dictionary) -> String:
	## Region or faction id the mission is about, for the notices.
	return String(mission.get("target_region", mission.get("target_faction", "")))


static func _rebel_border_regions(data: GameData, state: Dictionary, faction_id: String) -> Array:
	var targets: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()  # canonical order — targets feed rng.pick
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] == "rebels":
			for neighbor in data.regions[region_id].get("adjacent", []):
				if state["settlements"].has(neighbor) and state["settlements"][neighbor]["owner"] == faction_id:
					targets.append(region_id)
					break
	return targets


static func _courts_in_reach(data: GameData, state: Dictionary, faction_id: String) -> Array:
	## Living foreign powers (not Roman, not the independents) holding a
	## settlement within a few hops of the house's own — the Senate does not
	## send anyone to treat with kings it has never heard of.
	var reach := int(data.balance["senate"].get("mission_court_reach_hops", 4))
	var near := {}
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] != faction_id:
			continue
		var hops := MapRules.hops_from(data, region_id)
		for other_region in hops:
			if int(hops[other_region]) <= reach and state["settlements"].has(other_region):
				near[state["settlements"][other_region]["owner"]] = true
	var courts: Array = []
	var faction_ids: Array = near.keys()
	faction_ids.sort()
	for other in faction_ids:
		if other == faction_id or not state["factions"][other]["alive"]:
			continue
		var faction_def: Dictionary = data.factions.get(other, {})
		if faction_def.get("is_rebel", false) or faction_def.get("is_roman_house", false) \
				or faction_def.get("is_senate", false):
			continue
		courts.append(other)
	return courts


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


static func _mission_complete(data: GameData, state: Dictionary, faction_id: String, mission: Dictionary) -> bool:
	var region: String = mission.get("target_region", "")
	if region != "":
		return state["settlements"].has(region) and state["settlements"][region]["owner"] == faction_id
	var character: String = mission.get("target_character", "")
	if character != "":
		return state["characters"].has(character) and not state["characters"][character]["alive"]
	var other: String = mission.get("target_faction", "")
	if other == "" or not state["factions"].has(other):
		return false
	var stance := DiplomacyRules.stance_between(state, faction_id, other)
	match data.missions.get(mission["template"], {}).get("kind", ""):
		"make_alliance":
			return stance == "alliance"
		"reach_trade_agreement":
			return stance in ["trade", "alliance", "protectorate"]
	return false


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
