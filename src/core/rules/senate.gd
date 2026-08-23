class_name SenateRules
## The politics of the Republic (Phase 7 depth over the foundation loop):
## standings drift with expansion, the office ladder is filled each summer by
## standing and gravitas, missions of every authored kind are issued and
## judged, and the civil-war machinery decides who stands with whom when a
## house finally breaks with the Senate. Offices live on characters
## (character.office) and their effects flow through CharacterRules.


static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	var senate_rules: Dictionary = data.balance["senate"]
	var notices: Array = []

	var senate_alive: bool = state["factions"].has("senate") and state["factions"]["senate"]["alive"]
	if senate_alive and state["season"] == "summer":
		_assign_offices(data, state, rng, notices)

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

		if senate_alive and not faction["at_civil_war"]:
			_run_missions(data, state, faction_id, rng, notices)

		# Civil war becomes available (or is forced by outlawing) at the thresholds.
		if not faction["at_civil_war"] \
				and float(faction["popular_standing"]) >= float(senate_rules["civil_war_popular_threshold"]) \
				and float(faction["senate_standing"]) <= float(senate_rules["civil_war_senate_threshold"]):
			faction["at_civil_war"] = true
			_declare_civil_war(data, state, faction_id, notices)
			notices.append({"kind": "civil_war", "faction": faction_id})
	return notices


## --- Offices ---------------------------------------------------------------

static func _assign_offices(data: GameData, state: Dictionary, rng: CampaignRng, notices: Array) -> void:
	## Summer elections: every seat refilled from the houses in good standing.
	## Scored by house standing, then personal gravitas WITHOUT the office's
	## own bonus (a consulship must be defended, not inherited from itself).
	var candidates: Array = []  # [score_key, char_id]
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if not character["alive"] or character["role"] not in ["leader", "heir", "family"]:
			continue
		if character.get("gender", "male") != "male":
			continue
		var faction: Dictionary = state["factions"].get(character["faction"], {})
		var faction_def: Dictionary = data.factions.get(character["faction"], {})
		if not faction_def.get("is_roman_house", false):
			continue
		if not faction.get("alive", false) or faction.get("at_civil_war", false):
			continue
		var influence := CharacterRules.effective(data, character, "influence")
		var office = character.get("office")
		if office != null:
			influence -= int(data.offices.get(office, {}).get("effects", {}).get("influence", 0.0))
		candidates.append([[-float(faction["senate_standing"]), -float(influence),
			-float(character["age"]), char_id], char_id])
	candidates.sort()

	var previous := {}
	for char_id in char_ids:
		var office = state["characters"][char_id].get("office")
		if office != null:
			previous[char_id] = office
		state["characters"][char_id]["office"] = null

	var office_list: Array = data.offices.values()
	office_list.sort_custom(func(a, b): return int(a["rank"]) > int(b["rank"]))
	var taken := {}
	for office in office_list:
		var seats := int(office["seats"])
		for entry in candidates:
			if seats <= 0:
				break
			var char_id: String = entry[1]
			if taken.has(char_id):
				continue
			if int(state["characters"][char_id]["age"]) < int(office["min_age"]):
				continue
			taken[char_id] = true
			seats -= 1
			state["characters"][char_id]["office"] = office["id"]
			if previous.get(char_id, "") != office["id"]:
				CharacterRules.fire_trigger(data, state, char_id, "office_gained",
					{"office": office["id"]}, rng, notices)
				notices.append({"kind": "office_gained", "character": char_id,
					"faction": state["characters"][char_id]["faction"], "office": office["id"]})


## --- Missions --------------------------------------------------------------

static func _run_missions(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng, notices: Array) -> void:
	var senate_rules: Dictionary = data.balance["senate"]
	var faction: Dictionary = state["factions"][faction_id]
	var mission = faction["mission"]
	if mission == null:
		var new_mission := _issue_mission(data, state, faction_id, rng)
		if not new_mission.is_empty():
			faction["mission"] = new_mission
			notices.append({"kind": "mission_issued", "faction": faction_id,
				"mission": new_mission["template"]})
		return

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
		# Refusing the honorable exit is the end of patience: the house is
		# outlawed, and the civil war comes to it.
		if String(template["kind"]) == "leader_suicide" and not faction["at_civil_war"]:
			faction["at_civil_war"] = true
			_declare_civil_war(data, state, faction_id, notices)
			notices.append({"kind": "outlawed", "faction": faction_id})


static func _issue_mission(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng) -> Dictionary:
	var senate_rules: Dictionary = data.balance["senate"]
	var faction: Dictionary = state["factions"][faction_id]
	var mission_ids: Array = data.missions.keys()
	mission_ids.sort()

	# At rock-bottom standing the senate has one demand left.
	if float(faction["senate_standing"]) <= float(senate_rules["leader_suicide_standing"]):
		for mission_id in mission_ids:
			var template: Dictionary = data.missions[mission_id]
			if String(template["kind"]) != "leader_suicide":
				continue
			var leader := _leader_of(state, faction_id)
			if leader == "":
				return {}
			return {"template": mission_id, "target_char": leader,
				"turns_left": int(template["deadline_turns"])}
		return {}

	var feasible: Array = []  # entries: {template, targets, key} — key names the target field
	for mission_id in mission_ids:
		var template: Dictionary = data.missions[mission_id]
		if template.has("min_year") and int(state["year"]) < int(template["min_year"]):
			continue
		match String(template["kind"]):
			"take_region":
				var targets := _rebel_neighbors(data, state, faction_id)
				if not targets.is_empty():
					feasible.append({"template": mission_id, "targets": targets, "key": "target_region"})
			"blockade_port":
				var targets := _enemy_ports(data, state, faction_id)
				if not targets.is_empty():
					feasible.append({"template": mission_id, "targets": targets, "key": "target_region"})
			"make_alliance":
				var targets := _courtable_factions(data, state, faction_id, false)
				if not targets.is_empty():
					feasible.append({"template": mission_id, "targets": targets, "key": "target_faction"})
			"reach_trade_agreement":
				var targets := _courtable_factions(data, state, faction_id, true)
				if not targets.is_empty():
					feasible.append({"template": mission_id, "targets": targets, "key": "target_faction"})
			"assassinate_leader":
				var targets := _enemy_leaders(data, state, faction_id)
				if not targets.is_empty():
					feasible.append({"template": mission_id, "targets": targets, "key": "target_char"})
	if feasible.is_empty():
		return {}

	var entry: Dictionary = rng.pick(feasible)
	var template: Dictionary = data.missions[entry["template"]]
	var mission := {"template": entry["template"], "turns_left": int(template["deadline_turns"])}
	mission[entry["key"]] = rng.pick(entry["targets"])
	return mission


static func _mission_complete(data: GameData, state: Dictionary, faction_id: String, mission: Dictionary) -> bool:
	var template: Dictionary = data.missions.get(mission["template"], {})
	match String(template.get("kind", "")):
		"take_region":
			var target: String = mission.get("target_region", "")
			return target != "" and state["settlements"].has(target) \
				and state["settlements"][target]["owner"] == faction_id
		"blockade_port":
			var target: String = mission.get("target_region", "")
			if target == "" or not state["settlements"].has(target):
				return false
			if state["settlements"][target]["owner"] == faction_id:
				return true  # taking the port outright serves
			var port_zones: Array = data.regions.get(target, {}).get("sea_zones", [])
			if not DiplomacyRules.at_war(state, faction_id, state["settlements"][target]["owner"]):
				return false
			for fleet in state["fleets"].values():
				if fleet["owner"] == faction_id and port_zones.has(fleet["sea_zone"]):
					return true
			return false
		"make_alliance":
			var other: String = mission.get("target_faction", "")
			return other != "" and DiplomacyRules.stance_between(state, faction_id, other) \
				in ["alliance", "protectorate"]
		"reach_trade_agreement":
			var other: String = mission.get("target_faction", "")
			return other != "" and DiplomacyRules.stance_between(state, faction_id, other) \
				in ["trade", "alliance", "protectorate"]
		"assassinate_leader", "leader_suicide":
			var target_char: String = mission.get("target_char", "")
			return target_char != "" and state["characters"].has(target_char) \
				and not state["characters"][target_char]["alive"]
	return false


## --- Civil war -------------------------------------------------------------

static func _declare_civil_war(data: GameData, state: Dictionary, rebel_house: String, notices: Array) -> void:
	## The break decides every Roman heart: houses in the Senate's good graces
	## stand loyal; houses with little to lose join the rebellion.
	var join_threshold := float(data.balance["senate"]["civil_war_join_threshold"])
	var loyalists: Array = []
	var joiners: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == rebel_house:
			continue
		var other: Dictionary = data.factions.get(other_id, {})
		if not state["factions"][other_id]["alive"]:
			continue
		if other.get("is_senate", false):
			loyalists.append(other_id)
		elif other.get("is_roman_house", false):
			if not state["factions"][other_id]["at_civil_war"] \
					and float(state["factions"][other_id]["senate_standing"]) <= join_threshold:
				state["factions"][other_id]["at_civil_war"] = true
				joiners.append(other_id)
				notices.append({"kind": "joins_rebellion", "faction": other_id})
			else:
				loyalists.append(other_id)

	for loyal_id in loyalists:
		DiplomacyRules.declare_war(data, state, rebel_house, loyal_id)
		for joiner_id in joiners:
			DiplomacyRules.declare_war(data, state, joiner_id, loyal_id)
	for joiner_id in joiners:
		DiplomacyRules.set_stance(state, rebel_house, joiner_id, "alliance")


## --- Queries (facade/UI) ---------------------------------------------------

static func office_holders(data: GameData, state: Dictionary) -> Array:
	## [{office, holder}] for every filled seat, highest rank first.
	var holders: Array = []
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["alive"] and character.get("office") != null:
			holders.append({"office": character["office"], "holder": char_id})
	holders.sort_custom(func(a, b):
		var rank_a := int(data.offices.get(a["office"], {}).get("rank", 0))
		var rank_b := int(data.offices.get(b["office"], {}).get("rank", 0))
		return rank_a > rank_b if rank_a != rank_b else String(a["holder"]) < String(b["holder"]))
	return holders


## --- Internals -------------------------------------------------------------

static func _rebel_neighbors(data: GameData, state: Dictionary, faction_id: String) -> Array:
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


static func _enemy_ports(data: GameData, state: Dictionary, faction_id: String) -> Array:
	var targets: Array = []
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()
	for region_id in region_ids:
		var owner: String = state["settlements"][region_id]["owner"]
		if not DiplomacyRules.at_war(state, faction_id, owner):
			continue
		if MapRules.coastal(data, region_id) \
				and SettlementRules.effect_max(data, state["settlements"][region_id], "port_level") > 0.0:
			targets.append(region_id)
	return targets


static func _courtable_factions(data: GameData, state: Dictionary, faction_id: String, for_trade: bool) -> Array:
	var targets: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == faction_id or not state["factions"][other_id]["alive"]:
			continue
		var other: Dictionary = data.factions.get(other_id, {})
		if other.get("is_rebel", false) or other.get("is_senate", false) \
				or other.get("is_roman_house", false):
			continue
		var stance := DiplomacyRules.stance_between(state, faction_id, other_id)
		if for_trade:
			if stance == "neutral":
				targets.append(other_id)
		else:
			if stance in ["neutral", "trade"]:
				targets.append(other_id)
	return targets


static func _enemy_leaders(data: GameData, state: Dictionary, faction_id: String) -> Array:
	var targets: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == faction_id or not state["factions"][other_id]["alive"]:
			continue
		if data.factions.get(other_id, {}).get("is_rebel", false):
			continue
		if not DiplomacyRules.at_war(state, faction_id, other_id):
			continue
		var leader := _leader_of(state, other_id)
		if leader != "":
			targets.append(leader)
	return targets


static func _leader_of(state: Dictionary, faction_id: String) -> String:
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["faction"] == faction_id and character["alive"] and character["role"] == "leader":
			return char_id
	return ""


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


static func _region_count(state: Dictionary, faction_id: String) -> int:
	var count := 0
	for settlement in state["settlements"].values():
		if settlement["owner"] == faction_id:
			count += 1
	return count
