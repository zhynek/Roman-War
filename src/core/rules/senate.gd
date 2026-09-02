class_name SenateRules
## The Senate: standings drift with expansion, missions are issued from data
## templates and their deadlines enforced, and — Phase 7 — the cursus honorum
## is filled every summer from the men of the Roman houses (data/offices.json;
## an office lives on the character as character.office and reaches his
## attributes through CharacterRules.effect_total). Late-game hostility lives
## here as well: a house grown too great and too hated is asked for its
## patriarch's life, and refusal is outlawry — a civil war in which every
## other house picks a side, and which no envoy can end. Ambition alone can
## force the same break.


## Mission kinds the engine can actually judge. The rest of missions.json is
## authored ahead of the systems that will resolve it — blockades need port
## blockade rules, the assassination charges need agents — and the validator
## allowlists them so they read as forward content, not dead content.
const LIVE_KINDS: Array[String] = ["take_region", "make_alliance", "reach_trade_agreement", "assassinate_leader", "leader_suicide"]


static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	var notices: Array = []
	# The cursus honorum: every summer the Senate refills its magistracies.
	# When the Senate itself has fallen, the Republic's offices end with it —
	# and so does any civil war over it.
	if senate_faction(data, state) == "":
		_dissolve_offices(state)
		_settle_civil_war(data, state, notices)
	elif String(state["season"]) == "summer":
		_hold_elections(data, state, rng, notices)
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction["alive"] or not data.factions.get(faction_id, {}).get("is_roman_house", false):
			continue
		_drift_popular_standing(data, faction, _region_count(state, faction_id))
		# A house in arms against the Republic gets no charges from it.
		if not faction["at_civil_war"]:
			_run_charge(data, state, faction_id, rng, notices)
		# Civil war also arrives on its own when there are simply more great
		# houses expecting a command than there are commands to give. A house
		# can win its way into this: conquest is what breeds the claimants.
		var elite := float(SocietyRules.faction_stocks(data, faction)["elite_pressure"])
		if not faction["at_civil_war"] \
				and elite >= float(data.balance["society"]["elite_civil_war_threshold"]):
			_declare_civil_war(data, state, faction_id, notices)
			notices.append({"kind": "civil_war", "faction": faction_id, "pattern": "elite_overproduction"})
	return notices


static func _drift_popular_standing(data: GameData, faction: Dictionary, region_count: int) -> void:
	## Expansion pleases the people — but the regional baseline is a DRIFT
	## target, never an overwrite: edict tension deltas and per-turn drips
	## (EdictRules) move the same number and must persist. The crowd's mood
	## settles toward what your empire earns, from wherever politics put it.
	var senate_rules: Dictionary = data.balance["senate"]
	var baseline := minf(float(senate_rules["max_standing"]),
		float(region_count) * float(senate_rules["popular_standing_per_region"]))
	var popular := float(faction["popular_standing"])
	# Quantized for the same reason the societal stocks are: this drifts
	# rather than being recomputed, and JSON cannot round-trip an arbitrary
	# double exactly. Left raw, a loaded save differs from the live game in
	# the last digits and the two diverge a turn later.
	faction["popular_standing"] = SocietyRules.quantize(popular \
		+ (baseline - popular) * float(senate_rules["popular_drift_factor"]))


static func _run_charge(data: GameData, state: Dictionary, faction_id: String, rng: CampaignRng, notices: Array) -> void:
	## The house's standing charge: issued, ticked, judged, and — when the
	## house has grown too great and too hated — replaced by the Senate's
	## demand for the patriarch's life, whatever charge stood before. The
	## conscript fathers do not ask you to take a province while demanding
	## your death.
	var senate_rules: Dictionary = data.balance["senate"]
	var faction: Dictionary = state["factions"][faction_id]
	var mission = faction["mission"]
	if _demand_due(data, state, faction_id) and not _is_kind(data, mission, "leader_suicide"):
		if mission != null:
			notices.append({"kind": "mission_voided", "faction": faction_id, "mission": mission["template"]})
		var demand := _demand_mission(data, state, faction_id)
		if not demand.is_empty():
			faction["mission"] = demand
			notices.append(_notice("mission_issued", faction_id, demand))
			return
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
			notices.append(_notice("mission_issued", faction_id, new_mission))
		return
	mission["turns_left"] = int(mission["turns_left"]) - 1
	var template: Dictionary = data.missions[mission["template"]]
	if _mission_complete(data, state, faction_id, mission):
		var reward: Dictionary = template.get("reward", {})
		faction["treasury"] = int(faction["treasury"]) + int(reward.get("treasury", 0))
		faction["senate_standing"] = SocietyRules.quantize(
			minf(float(senate_rules["max_standing"]),
				float(faction["senate_standing"]) + float(reward.get("senate_standing",
					senate_rules["mission_success_standing"]))))
		_grant_reward_units(state, faction_id, reward)
		notices.append(_notice("mission_complete", faction_id, mission))
		faction["mission"] = null
		if faction_id == state.get("player_faction", ""):
			GuidedRules.bump(state, "senate_missions")
	elif int(mission["turns_left"]) <= 0:
		var penalty: Dictionary = template.get("penalty", {})
		faction["senate_standing"] = SocietyRules.quantize(
			maxf(float(senate_rules["min_standing"]),
				float(faction["senate_standing"]) + float(penalty.get("senate_standing",
					senate_rules["mission_fail_standing"]))))
		notices.append(_notice("mission_failed", faction_id, mission))
		faction["mission"] = null
		if String(template.get("kind", "")) == "leader_suicide":
			# Refusal is answered with outlawry: the house is named an enemy
			# of the Republic, and the civil war begins.
			faction["outlawed"] = true
			_declare_civil_war(data, state, faction_id, notices)
			notices.append({"kind": "civil_war", "faction": faction_id, "pattern": "outlawed"})
	else:
		# A live charge reports itself every turn, so the player always
		# sees where the house stands toward its purpose.
		notices.append(_notice("mission_progress", faction_id, mission))


static func _demand_due(data: GameData, state: Dictionary, faction_id: String) -> bool:
	## "Your house has grown too great, and the conscript fathers are afraid":
	## popular standing high enough to frighten them, senate standing low
	## enough that no friend speaks for the house.
	var senate_rules: Dictionary = data.balance["senate"]
	var faction: Dictionary = state["factions"][faction_id]
	if faction["at_civil_war"] or senate_faction(data, state) == "":
		return false
	if float(faction["senate_standing"]) > float(senate_rules["leader_suicide_standing"]):
		return false
	if float(faction["popular_standing"]) < float(senate_rules["leader_suicide_popular_min"]):
		return false
	return _leader_of(state, faction_id) != "" and _demand_template(data, state) != ""


static func _demand_template(data: GameData, state: Dictionary) -> String:
	var mission_ids: Array = data.missions.keys()
	mission_ids.sort()
	for mission_id in mission_ids:
		var template: Dictionary = data.missions[mission_id]
		if String(template.get("kind", "")) != "leader_suicide":
			continue
		if template.has("min_year") and int(state["year"]) < int(template["min_year"]):
			continue
		return mission_id
	return ""


static func _demand_mission(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	var template_id := _demand_template(data, state)
	if template_id == "":
		return {}
	return {
		"template": template_id,
		"turns_left": int(data.missions[template_id]["deadline_turns"]),
		"target_character": _leader_of(state, faction_id),
	}


static func _is_kind(data: GameData, mission, kind: String) -> bool:
	if mission == null:
		return false
	return String(data.missions.get(String(mission.get("template", "")), {}).get("kind", "")) == kind


static func comply_with_demand(data: GameData, state: Dictionary, faction_id: String, notices: Array) -> bool:
	## The patriarch opens his veins for the good of the Republic. Succession
	## settles at once (CharacterRules.kill with data); the Senate pays its
	## reward when it next judges the charge.
	var faction: Dictionary = state["factions"][faction_id]
	var mission = faction.get("mission")
	if not _is_kind(data, mission, "leader_suicide"):
		return false
	var patriarch := String(mission.get("target_character", ""))
	if patriarch == "" or not state["characters"].has(patriarch) \
			or not state["characters"][patriarch]["alive"]:
		return false
	CharacterRules.kill(state, patriarch, data, notices)
	return true


static func _notice(kind: String, faction_id: String, mission: Dictionary) -> Dictionary:
	return {
		"kind": kind, "faction": faction_id, "mission": mission["template"],
		"target_region": String(mission.get("target_region", "")),
		"target_faction": String(mission.get("target_faction", "")),
		"turns_left": int(mission.get("turns_left", 0)),
	}


## --- Offices: the cursus honorum ------------------------------------------

static func senate_faction(data: GameData, state: Dictionary) -> String:
	## The Senate's faction id while it lives, "" once it has fallen. Looked
	## up by flag, never by the literal id.
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		if data.factions.get(faction_id, {}).get("is_senate", false) \
				and state["factions"][faction_id]["alive"]:
			return faction_id
	return ""


static func office_holders(data: GameData, state: Dictionary) -> Array:
	## [{office, holder, faction}] for every filled seat, highest rank first,
	## then by holder id — the scroll's ladder.
	var holders: Array = []
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		var office = character.get("office")
		if character["alive"] and office != null:
			holders.append({"office": office, "holder": char_id, "faction": character["faction"]})
	holders.sort_custom(func(a, b):
		var rank_a := int(data.offices.get(a["office"], {}).get("rank", 0))
		var rank_b := int(data.offices.get(b["office"], {}).get("rank", 0))
		if rank_a != rank_b:
			return rank_a > rank_b
		return String(a["holder"]) < String(b["holder"]))
	return holders


static func eligible_offices(data: GameData, state: Dictionary, char_id: String) -> Array:
	## The magistracies a man may stand for at the next election, highest
	## first: [{office, on_ladder}] — on_ladder false where the cursus honorum
	## still bars him (he would only be seated as a suffect in a lean year).
	var out: Array = []
	if not state["characters"].has(char_id):
		return out
	var character: Dictionary = state["characters"][char_id]
	if not _stands_for_office(data, state, character):
		return out
	var office_list: Array = data.offices.values()
	office_list.sort_custom(func(a, b): return int(a["rank"]) > int(b["rank"]))
	for office in office_list:
		if int(character["age"]) < int(office["min_age"]):
			continue
		var needs_rank := int(office.get("requires_prior_rank", 0))
		out.append({"office": office["id"],
			"on_ladder": needs_rank <= 0 or _has_held_rank(data, character, needs_rank)})
	return out


static func _stands_for_office(data: GameData, state: Dictionary, character: Dictionary) -> bool:
	## A living man of a living Roman house that is not at war with the
	## Republic. Wives and children do not stand; nor does a house in rebellion.
	if not character["alive"] or String(character.get("gender", "male")) != "male":
		return false
	if not ["leader", "heir", "family"].has(String(character["role"])):
		return false
	var faction_id: String = character["faction"]
	if not data.factions.get(faction_id, {}).get("is_roman_house", false):
		return false
	var faction: Dictionary = state["factions"].get(faction_id, {})
	return bool(faction.get("alive", false)) and not bool(faction.get("at_civil_war", false))


static func _hold_elections(data: GameData, state: Dictionary, rng: CampaignRng, notices: Array) -> void:
	## Summer elections. Every seat is refilled from the men of the houses in
	## the Senate's good graces: a man's score is his house's standing with
	## the Senate (weighted) plus his own influence WITHOUT the office he holds
	## today — a consulship must be defended, not inherited from itself. Ties
	## break on age, then id, so a loaded save elects the same men. The highest
	## offices fill first; the cursus honorum (requires_prior_rank) is enforced
	## while a candidate on the ladder remains and waived after — the Senate
	## seats a suffect rather than leave a magistracy empty in a lean year.
	var weight := float(data.balance["senate"].get("election_standing_weight", 1.0))
	var previous := {}
	var candidates: Array = []  # [score, age, char_id]
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		var held = character.get("office")
		if held != null:
			previous[char_id] = held
			character["office"] = null
		if not _stands_for_office(data, state, character):
			continue
		# The office was cleared above, so effective() is the man without it.
		var score := float(state["factions"][character["faction"]]["senate_standing"]) * weight \
			+ float(CharacterRules.effective(data, character, "influence"))
		candidates.append([score, int(character["age"]), char_id])
	candidates.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] > b[0]
		if a[1] != b[1]:
			return a[1] > b[1]
		return String(a[2]) < String(b[2]))

	var office_list: Array = data.offices.values()
	office_list.sort_custom(func(a, b): return int(a["rank"]) > int(b["rank"]))
	var taken := {}
	for office in office_list:
		var seats := int(office["seats"])
		var needs_rank := int(office.get("requires_prior_rank", 0))
		# Pass one seats the men who climbed the ladder; pass two seats suffects
		# into whatever is still empty.
		for waived in [false, true]:
			for entry in candidates:
				if seats <= 0:
					break
				var char_id: String = entry[2]
				if taken.has(char_id):
					continue
				var character: Dictionary = state["characters"][char_id]
				if int(character["age"]) < int(office["min_age"]):
					continue
				if not waived and needs_rank > 0 and not _has_held_rank(data, character, needs_rank):
					continue
				taken[char_id] = true
				seats -= 1
				_seat(data, state, rng, char_id, office, previous, notices)


static func _seat(data: GameData, state: Dictionary, rng: CampaignRng, char_id: String, office: Dictionary, previous: Dictionary, notices: Array) -> void:
	var character: Dictionary = state["characters"][char_id]
	var office_id := String(office["id"])
	character["office"] = office_id
	if String(previous.get(char_id, "")) == office_id:
		return  # returned to the same seat: no new laurels, no new trigger
	if not character.has("offices_held"):
		character["offices_held"] = []
	character["offices_held"].append(office_id)
	ChronicleRules.add_deed(state, char_id, "offices_held")
	if int(office["rank"]) >= int(data.balance["senate"].get("annals_office_min_rank", 3)):
		# Only the higher magistracies make the annals — a dozen quaestors a
		# year would displace real history from the chronicle's per-turn cap.
		ChronicleRules.record(data, state, "office_taken",
			{"character": char_id, "faction": character["faction"], "office": office_id}, 3)
	CharacterRules.fire_trigger(data, state, char_id, "office_gained", {"office": office_id}, rng, notices)
	notices.append({"kind": "office_gained", "character": char_id,
		"faction": character["faction"], "office": office_id, "rank": int(office["rank"])})
	if character["faction"] == state.get("player_faction", ""):
		GuidedRules.bump(state, "offices_won")


static func _has_held_rank(data: GameData, character: Dictionary, rank: int) -> bool:
	for office_id in character.get("offices_held", []):
		if int(data.offices.get(office_id, {}).get("rank", 0)) >= rank:
			return true
	return false


static func _dissolve_offices(state: Dictionary) -> void:
	## With the Senate gone there is no one to fill the magistracies.
	for character in state["characters"].values():  # pure clear — order-free
		if character.get("office") != null:
			character["office"] = null


## --- Missions --------------------------------------------------------------

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


static func _grant_reward_units(state: Dictionary, faction_id: String, reward: Dictionary) -> void:
	## Granted units muster in the capital's garrison.
	var capital: String = state["factions"][faction_id]["capital"]
	if not state["settlements"].has(capital) or state["settlements"][capital]["owner"] != faction_id:
		return
	for grant in reward.get("units", []):
		for i in range(int(grant["count"])):
			state["settlements"][capital]["garrison"].append({
				"template": grant["template"], "experience": 0, "strength_pct": 100,
				"weapon": 0, "armor": 0,
			})


static func _mission_complete(data: GameData, state: Dictionary, faction_id: String, mission: Dictionary) -> bool:
	match String(data.missions.get(mission["template"], {}).get("kind", "")):
		"take_region":
			var target: String = String(mission.get("target_region", ""))
			return target != "" and state["settlements"].has(target) \
				and state["settlements"][target]["owner"] == faction_id
		"make_alliance":
			var ally: String = String(mission.get("target_faction", ""))
			return ally != "" and DiplomacyRules.stance_between(state, faction_id, ally) == "alliance"
		"reach_trade_agreement":
			# An alliance carries trade rights with it, so either seals the deal.
			var partner: String = String(mission.get("target_faction", ""))
			return partner != "" \
				and DiplomacyRules.stance_between(state, faction_id, partner) in ["trade", "alliance"]
		"assassinate_leader":
			# The named head must fall — by blade, battle or misadventure — or
			# the whole power be destroyed outright.
			var quarry: String = String(mission.get("target_character", ""))
			var victim_faction: String = String(mission.get("target_faction", ""))
			if victim_faction != "" and not state["factions"][victim_faction]["alive"]:
				return true
			return quarry != "" and state["characters"].has(quarry) \
				and not state["characters"][quarry]["alive"]
		"leader_suicide":
			# The patriarch named in the decree is dead — by his own hand or
			# any other; the Senate does not ask how.
			var patriarch: String = String(mission.get("target_character", ""))
			return patriarch != "" and state["characters"].has(patriarch) \
				and not state["characters"][patriarch]["alive"]
	return false


static func _region_count(state: Dictionary, faction_id: String) -> int:
	var count := 0
	for settlement in state["settlements"].values():
		if settlement["owner"] == faction_id:
			count += 1
	return count


static func _declare_civil_war(data: GameData, state: Dictionary, rebel_house: String, notices: Array) -> void:
	## The house breaks with the Republic: war with the Senate, and every other
	## house chooses — those the Senate has already alienated march with the
	## rebel, the rest stand with the conscript fathers. Offices are stripped,
	## standing charges are void, and the chronicle opens the war. Stances go
	## through DiplomacyRules so the grudges are remembered like any war's.
	var senate_rules: Dictionary = data.balance["senate"]
	var rebel: Dictionary = state["factions"][rebel_house]
	rebel["at_civil_war"] = true
	rebel["mission"] = null
	var senate_id := senate_faction(data, state)
	if senate_id != "":
		DiplomacyRules.declare_war(data, state, rebel_house, senate_id)
	var joiners: Array = []
	var loyalists: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for other_id in faction_ids:
		if other_id == rebel_house or not data.factions.get(other_id, {}).get("is_roman_house", false):
			continue
		var other: Dictionary = state["factions"][other_id]
		if not other["alive"]:
			continue
		if other["at_civil_war"]:
			# Already in arms against the Republic: brothers in rebellion.
			DiplomacyRules.set_stance(state, rebel_house, other_id, "alliance")
			continue
		if float(other["senate_standing"]) <= float(senate_rules["civil_war_join_standing"]):
			other["at_civil_war"] = true
			other["mission"] = null
			DiplomacyRules.set_stance(state, rebel_house, other_id, "alliance")
			if senate_id != "":
				DiplomacyRules.declare_war(data, state, other_id, senate_id)
			joiners.append(other_id)
			notices.append({"kind": "house_joins_rebellion", "faction": other_id, "other": rebel_house})
		else:
			DiplomacyRules.declare_war(data, state, other_id, rebel_house)
			loyalists.append(other_id)
			notices.append({"kind": "house_stays_loyal", "faction": other_id, "other": rebel_house})
	for joiner_id in joiners:
		for loyal_id in loyalists:
			DiplomacyRules.declare_war(data, state, loyal_id, joiner_id)
	_strip_offices(state, [rebel_house] + joiners)
	ChronicleRules.record(data, state, "civil_war", {"faction": rebel_house}, 8,
		{"joiners": joiners.size(), "cause": "outlawed" if rebel.get("outlawed", false) else "ambition"})


static func _settle_civil_war(data: GameData, state: Dictionary, notices: Array) -> void:
	## With the Senate gone there is nothing left to rebel against: every
	## surviving house is a power like any other, its wars with the other
	## houses lapse into neutrality (alliances stand), and the flags clear.
	var roman_ids: Array = []
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	var changed := false
	for faction_id in faction_ids:
		if not data.factions.get(faction_id, {}).get("is_roman_house", false):
			continue
		roman_ids.append(faction_id)
		var faction: Dictionary = state["factions"][faction_id]
		if faction.get("at_civil_war", false) or faction.get("outlawed", false):
			faction["at_civil_war"] = false
			faction["outlawed"] = false
			changed = true
	if not changed:
		return
	for i in range(roman_ids.size()):
		for j in range(i + 1, roman_ids.size()):
			if DiplomacyRules.at_war(state, roman_ids[i], roman_ids[j]):
				DiplomacyRules.set_stance(state, roman_ids[i], roman_ids[j], "neutral")
	notices.append({"kind": "civil_war_over"})


static func _strip_offices(state: Dictionary, faction_ids: Array) -> void:
	## A house in arms holds no magistracy.
	for character in state["characters"].values():  # pure clear — order-free
		if faction_ids.has(character["faction"]) and character.get("office") != null:
			character["office"] = null


static func _mission_target_gone(data: GameData, state: Dictionary, mission: Dictionary) -> bool:
	var target_faction: String = mission.get("target_faction", "")
	if target_faction == "" or state["factions"][target_faction]["alive"]:
		return false
	# Assassination completes on the power's fall; courtship cannot.
	return String(data.missions.get(mission["template"], {}).get("kind", "")) != "assassinate_leader"


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


static func _leader_of(state: Dictionary, faction_id: String) -> String:
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if character["faction"] == faction_id and character["alive"] and character["role"] == "leader":
			return char_id
	return ""
