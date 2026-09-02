class_name SenateRules
## The Senate: standings drift with expansion, missions are issued from data
## templates and their deadlines enforced, and — Phase 7 — the cursus honorum
## is filled every summer from the men of the Roman houses (data/offices.json;
## an office lives on the character as character.office and reaches his
## attributes through CharacterRules.effect_total). The civil-war threshold on
## Ambition is evaluated here too.


## Mission kinds the engine can actually judge. The rest of missions.json is
## authored ahead of the systems that will resolve it — blockades need port
## blockade rules, the assassination charges need agents — and the validator
## allowlists them so they read as forward content, not dead content.
const LIVE_KINDS: Array[String] = ["take_region", "make_alliance", "reach_trade_agreement", "assassinate_leader"]


static func process_turn(data: GameData, state: Dictionary, rng: CampaignRng) -> Array:
	var senate_rules: Dictionary = data.balance["senate"]
	var notices: Array = []
	# The cursus honorum: every summer the Senate refills its magistracies.
	# When the Senate itself has fallen, the Republic's offices end with it.
	if senate_faction(data, state) == "":
		_dissolve_offices(state)
	elif String(state["season"]) == "summer":
		_hold_elections(data, state, rng, notices)
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction["alive"] or not data.factions.get(faction_id, {}).get("is_roman_house", false):
			continue

		# Expansion pleases the people — but the regional baseline is a DRIFT
		# target, never an overwrite: edict tension deltas and per-turn drips
		# (EdictRules) move the same number and must persist. The crowd's mood
		# settles toward what your empire earns, from wherever politics put it.
		var region_count := _region_count(state, faction_id)
		var baseline := minf(float(senate_rules["max_standing"]),
			float(region_count) * float(senate_rules["popular_standing_per_region"]))
		var popular := float(faction["popular_standing"])
		# Quantized for the same reason the societal stocks are: this drifts
		# rather than being recomputed, and JSON cannot round-trip an arbitrary
		# double exactly. Left raw, a loaded save differs from the live game in
		# the last digits and the two diverge a turn later.
		faction["popular_standing"] = SocietyRules.quantize(popular \
			+ (baseline - popular) * float(senate_rules["popular_drift_factor"]))

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
				notices.append(_notice("mission_issued", faction_id, new_mission))
		else:
			mission["turns_left"] = int(mission["turns_left"]) - 1
			if _mission_complete(data, state, faction_id, mission):
				var template: Dictionary = data.missions[mission["template"]]
				var reward: Dictionary = template.get("reward", {})
				faction["treasury"] = int(faction["treasury"]) + int(reward.get("treasury", 0))
				faction["senate_standing"] = SocietyRules.quantize(
					minf(float(senate_rules["max_standing"]),
						float(faction["senate_standing"]) + float(reward.get("senate_standing",
							senate_rules["mission_success_standing"]))))
				_grant_reward_units(state, faction_id, reward)
				notices.append(_notice("mission_complete", faction_id, mission))
				faction["mission"] = null
				notices.append({"kind": "mission_complete", "faction": faction_id, "mission": mission["template"]})
				if faction_id == state.get("player_faction", ""):
					GuidedRules.bump(state, "senate_missions")
			elif int(mission["turns_left"]) <= 0:
				var template: Dictionary = data.missions[mission["template"]]
				var penalty: Dictionary = template.get("penalty", {})
				faction["senate_standing"] = SocietyRules.quantize(
					maxf(float(senate_rules["min_standing"]),
						float(faction["senate_standing"]) + float(penalty.get("senate_standing",
							senate_rules["mission_fail_standing"]))))
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
