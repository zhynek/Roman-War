class_name SenateRules
## Minimal senate loop for the foundation (full politics is a later phase, but
## the standing fields and mission state exist from day one so nothing needs a
## retrofit): standings drift with expansion, missions are issued from data
## templates, deadlines are enforced, and the civil-war threshold is evaluated.


## Mission kinds the engine can actually judge. The rest of missions.json is
## authored ahead of the systems that will resolve it — blockades need port
## blockade rules, the assassination charges need agents — and the validator
## allowlists them so they read as forward content, not dead content.
const LIVE_KINDS: Array[String] = ["take_region", "make_alliance", "reach_trade_agreement"]


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
				notices.append(_notice("mission_issued", faction_id, new_mission))
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
				notices.append(_notice("mission_complete", faction_id, mission))
				faction["mission"] = null
				notices.append({"kind": "mission_complete", "faction": faction_id, "mission": mission["template"]})
				if faction_id == state.get("player_faction", ""):
					GuidedRules.bump(state, "senate_missions")
			elif int(mission["turns_left"]) <= 0:
				var template: Dictionary = data.missions[mission["template"]]
				var penalty: Dictionary = template.get("penalty", {})
				faction["senate_standing"] = maxf(float(senate_rules["min_standing"]),
					float(faction["senate_standing"]) + float(penalty.get("senate_standing",
						senate_rules["mission_fail_standing"])))
				notices.append(_notice("mission_failed", faction_id, mission))
				faction["mission"] = null
			else:
				# A live charge reports itself every turn, so the player always
				# sees where the house stands toward its purpose.
				notices.append(_notice("mission_progress", faction_id, mission))

		# Civil war becomes available (or is forced by outlawing) at the thresholds
		# — or arrives on its own when there are simply more great houses
		# expecting a command than there are commands to give. A house can win
		# its way into this: conquest is what breeds the claimants.
		var elite := float(SocietyRules.faction_stocks(data, faction)["elite_pressure"])
		var elite_forced: bool = elite >= float(data.balance["society"]["elite_civil_war_threshold"])
		var standings_met: bool = \
			float(faction["popular_standing"]) >= float(senate_rules["civil_war_popular_threshold"]) \
			and float(faction["senate_standing"]) <= float(senate_rules["civil_war_senate_threshold"])
		if not faction["at_civil_war"] and (standings_met or elite_forced):
			faction["at_civil_war"] = true
			_declare_civil_war(data, state, faction_id)
			notices.append({
				"kind": "civil_war", "faction": faction_id,
				"pattern": "elite_overproduction" if elite_forced else "",
			})
	return notices


static func _notice(kind: String, faction_id: String, mission: Dictionary) -> Dictionary:
	return {
		"kind": kind, "faction": faction_id, "mission": mission["template"],
		"target_region": String(mission.get("target_region", "")),
		"target_faction": String(mission.get("target_faction", "")),
		"turns_left": int(mission.get("turns_left", 0)),
	}


static func _issue_mission(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng) -> Dictionary:
	## One charge at a time, drawn from whichever live kinds have a legal target
	## right now. Candidate lists are sorted before any draw — they feed rng.pick,
	## so an unsorted list would make a loaded save diverge from the live game.
	var candidates: Array = []
	var mission_ids: Array = data.missions.keys()
	mission_ids.sort()
	for mission_id in mission_ids:
		var template: Dictionary = data.missions[mission_id]
		if not LIVE_KINDS.has(String(template["kind"])):
			continue
		if template.has("min_year") and int(state["year"]) < int(template["min_year"]):
			continue
		if _targets_for(data, state, faction_id, String(template["kind"])).is_empty():
			continue
		candidates.append(mission_id)
	if candidates.is_empty():
		return {}

	var template_id: String = rng.pick(candidates)
	var kind: String = String(data.missions[template_id]["kind"])
	var target: String = rng.pick(_targets_for(data, state, faction_id, kind))
	var mission := {
		"template": template_id,
		"turns_left": int(data.missions[template_id]["deadline_turns"]),
		"target_region": "",
		"target_faction": "",
	}
	if kind == "take_region":
		mission["target_region"] = target
	else:
		mission["target_faction"] = target
	return mission


static func _targets_for(data: GameData, state: Dictionary, faction_id: String, kind: String) -> Array:
	var targets: Array = []
	if kind == "take_region":
		var region_ids: Array = state["settlements"].keys()
		region_ids.sort()
		for region_id in region_ids:
			if state["settlements"][region_id]["owner"] != "rebels":
				continue
			for neighbor in data.regions[region_id].get("adjacent", []):
				if state["settlements"].has(neighbor) \
						and state["settlements"][neighbor]["owner"] == faction_id:
					targets.append(region_id)
					break
		return targets

	# The diplomatic charges want a living foreign power we are not already
	# bound to in the way the Senate is asking for.
	var wanted := "alliance" if kind == "make_alliance" else "trade"
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == faction_id or not state["factions"][other_id]["alive"]:
			continue
		var other: Dictionary = data.factions.get(other_id, {})
		if other.get("is_rebel", false) or other.get("is_senate", false):
			continue
		var stance := DiplomacyRules.stance_between(state, faction_id, other_id)
		if stance != wanted and stance != "war":
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
	var kind: String = String(data.missions.get(mission["template"], {}).get("kind", ""))
	if kind == "take_region":
		var target: String = String(mission.get("target_region", ""))
		return target != "" and state["settlements"].has(target) \
			and state["settlements"][target]["owner"] == faction_id
	if kind == "make_alliance" or kind == "reach_trade_agreement":
		var other: String = String(mission.get("target_faction", ""))
		if other == "" or not state["factions"].has(other):
			return false
		var wanted := "alliance" if kind == "make_alliance" else "trade"
		return DiplomacyRules.stance_between(state, faction_id, other) == wanted
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
