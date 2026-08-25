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
		if mission != null and _mission_target_gone(data, state, mission):
			# The senate does not punish a house for failing to court a corpse:
			# a courtship mission whose target power died is quietly voided.
			# (Assassination missions instead COMPLETE on the target's fall.)
			notices.append({"kind": "mission_voided", "faction": faction_id, "mission": mission["template"]})
			faction["mission"] = null
			mission = null
		if mission == null:
			var new_mission := _issue_mission(data, state, faction_id, rng)
			if not new_mission.is_empty():
				faction["mission"] = new_mission
				notices.append({"kind": "mission_issued", "faction": faction_id, "mission": new_mission["template"]})
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
	## take_region targets a nearby rebel region; make_alliance and
	## reach_trade_agreement court a bordering foreign power. The template is
	## drawn among kinds that currently have a valid target, then the target —
	## all candidate lists in canonical sorted order, since they feed rng.pick.
	var take_targets := _take_region_targets(data, state, faction_id)
	var alliance_targets := _courtship_targets(data, state, faction_id, ["neutral", "trade"])
	var trade_targets := _courtship_targets(data, state, faction_id, ["neutral"])
	var kill_targets := _assassination_targets(data, state, faction_id)

	var candidates: Array = []
	var mission_ids: Array = data.missions.keys()
	mission_ids.sort()
	for mission_id in mission_ids:
		var template: Dictionary = data.missions[mission_id]
		if template.has("min_year") and int(state["year"]) < int(template["min_year"]):
			continue
		match String(template["kind"]):
			"take_region":
				if not take_targets.is_empty():
					candidates.append(mission_id)
			"make_alliance":
				if not alliance_targets.is_empty():
					candidates.append(mission_id)
			"reach_trade_agreement":
				if not trade_targets.is_empty():
					candidates.append(mission_id)
			"assassinate_leader":
				if not kill_targets.is_empty():
					candidates.append(mission_id)
	if candidates.is_empty():
		return {}

	var template_id: String = rng.pick(candidates)
	var mission := {
		"template": template_id,
		"turns_left": int(data.missions[template_id]["deadline_turns"]),
	}
	match String(data.missions[template_id]["kind"]):
		"take_region":
			mission["target_region"] = rng.pick(take_targets)
		"make_alliance":
			mission["target_faction"] = rng.pick(alliance_targets)
		"reach_trade_agreement":
			mission["target_faction"] = rng.pick(trade_targets)
		"assassinate_leader":
			var target: Dictionary = rng.pick(kill_targets)
			mission["target_faction"] = target["faction"]
			mission["target_character"] = target["character"]
	return mission


static func _take_region_targets(data: GameData, state: Dictionary, faction_id: String) -> Array:
	var targets: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		if state["settlements"][region_id]["owner"] == "rebels":
			for neighbor in data.regions[region_id].get("adjacent", []):
				if state["settlements"].has(neighbor) and state["settlements"][neighbor]["owner"] == faction_id:
					targets.append(region_id)
					break
	return targets


static func _mission_target_gone(data: GameData, state: Dictionary, mission: Dictionary) -> bool:
	var target_faction: String = mission.get("target_faction", "")
	if target_faction == "" or state["factions"][target_faction]["alive"]:
		return false
	# Assassination completes on the power's fall; courtship cannot.
	return String(data.missions.get(mission["template"], {}).get("kind", "")) != "assassinate_leader"


static func _assassination_targets(data: GameData, state: Dictionary, faction_id: String) -> Array:
	## The senate points the house's blades at the crowned head of a foreign
	## power the house is already at war with. [{faction, character}]
	var targets: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == faction_id or not state["factions"][other_id]["alive"]:
			continue
		var info: Dictionary = data.factions.get(other_id, {})
		if info.get("is_rebel", false) or info.get("is_roman_house", false) or info.get("is_senate", false):
			continue
		if not DiplomacyRules.at_war(state, faction_id, other_id):
			continue
		var leader := _leader_of(state, other_id)
		if leader != "":
			targets.append({"faction": other_id, "character": leader})
	return targets


static func _leader_of(state: Dictionary, faction_id: String) -> String:
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["faction"] == faction_id and character["alive"] and character["role"] == "leader":
			return char_id
	return ""


static func _courtship_targets(data: GameData, state: Dictionary, faction_id: String, allowed_stances: Array) -> Array:
	## Foreign (non-Roman) bordering powers whose current stance leaves room
	## for the asked-for agreement.
	var targets: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == faction_id or not state["factions"][other_id]["alive"]:
			continue
		var info: Dictionary = data.factions.get(other_id, {})
		if info.get("is_rebel", false) or info.get("is_roman_house", false) or info.get("is_senate", false):
			continue
		if not allowed_stances.has(DiplomacyRules.stance_between(state, faction_id, other_id)):
			continue
		if not DiplomacyRules.share_border(data, state, faction_id, other_id):
			continue
		targets.append(other_id)
	return targets


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
	match String(data.missions.get(mission["template"], {}).get("kind", "")):
		"take_region":
			var target: String = mission.get("target_region", "")
			return target != "" and state["settlements"].has(target) \
				and state["settlements"][target]["owner"] == faction_id
		"make_alliance":
			var ally: String = mission.get("target_faction", "")
			return ally != "" and DiplomacyRules.stance_between(state, faction_id, ally) == "alliance"
		"reach_trade_agreement":
			var partner: String = mission.get("target_faction", "")
			# An alliance carries trade rights with it, so either seals the deal.
			return partner != "" and DiplomacyRules.stance_between(state, faction_id, partner) in ["trade", "alliance"]
		"assassinate_leader":
			# The named head must fall — by blade, battle or misadventure — or
			# the whole power be destroyed outright.
			var quarry: String = mission.get("target_character", "")
			var victim_faction: String = mission.get("target_faction", "")
			if victim_faction != "" and not state["factions"][victim_faction]["alive"]:
				return true
			return quarry != "" and state["characters"].has(quarry) \
				and not state["characters"][quarry]["alive"]
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
