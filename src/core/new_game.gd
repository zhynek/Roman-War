class_name NewGame
## Builds the initial GameState Dictionary from data/campaign.json.
## GameState is a plain Dictionary (JSON-serializable, deep-comparable):
##
##  turn: int (0-based), year: int, season: "summer"|"winter"
##  rng_state: String (decimal — a 64-bit int loses precision through JSON)
##  player_faction: String
##  world_seed: int — the seed that built this world (0 = unknown, pre-seed save);
##      with it any playtest report replays exactly
##  factions: {fid: {treasury, capital, alive, era, senate_standing,
##                   popular_standing, diplomacy: {other_fid: stance},
##                   mission: null|{...}, at_civil_war: bool, outlawed: bool,
##                   society: {elite_pressure, martial_ethos, knowledge,
##                             civic_shock}, advances: [advance_id],
##                   war_record: {battles_won, battles_lost, faced: {class: battles}},
##                   war_mood: null|{label, value, turns}}}
##  settlements: {region_id: {owner, population, buildings: {chain_id: level_index},
##                tax_level, garrison: [unit], construction_queue: [...],
##                recruitment_queue: [...], governor: char_id|null,
##                slave_bonus_turns, plague_turns, recently_conquered,
##                low_order_streak, siege: null|{besieger, turns, equipment_ready},
##                levy_strain: float, edict: {id, turns_held, cooldown},
##                society: {legitimacy, grievance, assimilation, unrest_state,
##                          unrest_turns, survey: {}}}}
##  armies: {army_id: {owner, region, units: [unit], general: char_id|null,
##                     movement_left: float}}
##  fleets: {fleet_id: {owner, sea_zone, ships: [unit], movement_left}}
##  characters: {char_id: {faction, name, age, role, gender, father, command,
##                         management, influence, trait_points, ancillaries,
##                         location, alive, deeds, epithet,
##                         office: office_id|null, offices_held: [office_id]}}
##  events_fired: [event_id], winner: null|String, next_id: int
##  ai: {war_turns: {"a|b": int}, targets: {fid: region_id},
##       peace_turn: {"a|b": int}} — the AI's persistent memory (FactionAi):
##      war staleness, campaign goals, and when pairs last made peace
##  sites_explored: [site_id] — points of interest already searched
##  guided: {enabled: bool, counters: {key: int}, stages: {stage_id:
##           {status: "active"|"done"|"expired"|"cooldown", started_turn,
##            base: {counters snapshot}, target: String|null, fired,
##            cooldown_until}}} — the guided campaign trail (GuidedRules);
##          factions may also carry boons: {recruit_xp, income_pct, movement}
##          granted by trail rewards (created lazily on first grant)
##
## A "unit" is {template, experience, strength_pct, weapon, armor} — the arming
## levels (0-2) stamped by the recruiting settlement's forges and armouries.
##
## New state fields are ALWAYS initialised here and in ensure_state_keys, never
## lazily on first read: a live game and a loaded save must stringify with the
## same key order or the determinism tests cannot compare them.

const ConstantsScript = preload("res://src/core/constants.gd")


static func build(data: GameData, player_faction: String, seed_value: int, difficulty: String = "medium", campaign_mode: String = "long", guided: bool = true) -> Dictionary:
	var rng := CampaignRng.seeded(seed_value)
	var state := {
		"turn": 0,
		"year": int(data.balance["time"]["start_year"]),
		"season": "summer",
		"rng_state": "0",
		"difficulty": difficulty,
		"campaign_mode": campaign_mode,
		"world_seed": seed_value,
		"event_happiness": null,
		"modifiers": [],
		"chronicle": [],
		"wars": [],
		"player_faction": player_faction,
		"factions": {},
		"settlements": {},
		"armies": {},
		"fleets": {},
		"characters": {},
		"events_fired": [],
		"journal": {"turn": 0, "beats": []},
		"winner": null,
		"next_id": 1,
		"ai": {"war_turns": {}, "targets": {}, "peace_turn": {}},
		"sites_explored": [],
		"guided": {"enabled": guided, "counters": {}, "stages": {}},
		"event_cooldowns": {},
		"tributes": [],
		"pending_offers": [],
		"agents": {},
	}

	for faction_setup in data.campaign["factions"]:
		var fid: String = faction_setup["id"]
		var senate_start := float(data.balance["senate"]["start_standing"])
		state["factions"][fid] = {
			"treasury": int(faction_setup["treasury"]),
			"capital": faction_setup["capital"],
			"alive": true,
			"era": "pre_marian",
			"senate_standing": senate_start,
			"popular_standing": 0.0,
			"diplomacy": {},
			"mission": null,
			"at_civil_war": false,
			"outlawed": false,
			"society": SocietyRules.new_faction_society(data),
			"advances": [],
			"war_cooldown": 0,
			"ai": {},
			"attitude_memory": {},
			"knowledge": _starting_knowledge(data, fid),
			"reform_pressure": 0.0,
			"edicts": {},
			"edict_cooldowns": {},
			"war_record": empty_war_record(),
			"war_mood": null,
		}
		for entry in faction_setup.get("diplomacy", []):
			state["factions"][fid]["diplomacy"][entry["faction"]] = entry["stance"]

		for settlement_setup in faction_setup.get("settlements", []):
			state["settlements"][settlement_setup["region"]] = _settlement(data, settlement_setup, fid)
		for army_setup in faction_setup.get("armies", []):
			_add_army(state, army_setup, fid)
		for fleet_setup in faction_setup.get("fleets", []):
			_add_fleet(state, fleet_setup, fid)
		for character_setup in faction_setup.get("characters", []):
			_add_character(data, state, character_setup, fid)

	var rebels := "rebels"
	state["factions"][rebels] = {
		"treasury": 0, "capital": "", "alive": true, "era": "pre_marian",
		"senate_standing": 0.0, "popular_standing": 0.0, "diplomacy": {},
		"mission": null, "at_civil_war": false, "outlawed": false, "war_cooldown": 0,
		"society": SocietyRules.new_faction_society(data),
		"ai": {}, "attitude_memory": {},
		"knowledge": {}, "reform_pressure": 0.0, "edicts": {}, "edict_cooldowns": {},
		"war_record": empty_war_record(), "war_mood": null,
	}
	for settlement_setup in data.campaign.get("rebel_settlements", []):
		state["settlements"][settlement_setup["region"]] = _settlement(data, settlement_setup, rebels)
	for army_setup in data.campaign.get("rebel_armies", []):
		_add_army(state, army_setup, rebels)

	# Make diplomacy symmetric; default stance between unrelated factions is neutral,
	# and everyone is at war with the rebels.
	for fid in state["factions"]:
		for other in state["factions"]:
			if fid == other:
				continue
			var stances: Dictionary = state["factions"][fid]["diplomacy"]
			var reverse: Dictionary = state["factions"][other]["diplomacy"]
			if stances.has(other) and not reverse.has(fid):
				reverse[fid] = stances[other]
			elif not stances.has(other):
				var default_stance := "war" if (fid == rebels or other == rebels) else "neutral"
				if not stances.has(other):
					stances[other] = reverse.get(fid, default_stance)

	# Governorship is derived from presence, so it is simply computed, never seeded.
	SettlementRules.refresh_governors(data, state)

	# Reign ledgers open with the founding leaders (the chronicle's collect
	# pass would seed the same values lazily; build states them outright).
	var reign_ids: Array = state["factions"].keys()
	reign_ids.sort()
	for fid in reign_ids:
		state["factions"][fid]["reign"] = {
			"leader": ChronicleRules.leader_of(state, fid), "since_turn": 0,
		}

	# Mercenary pools start at their initial counts (fractional replenishment
	# accumulates in the counts, so they are floats).
	var pools := {}
	for pool in data.mercenary_pools:
		var counts := {}
		for entry in pool["units"]:
			counts[entry["template"]] = float(entry.get("initial", 0))
		pools[pool["id"]] = counts
	state["mercenary_pools"] = pools

	MovementRules.reset_movement(data, state)

	# The trail greets the player from turn zero: start stages open now, so
	# deeds done before the first end-turn already count toward them.
	GuidedRules.process_turn(data, state)

	state["rng_state"] = rng.state_string()
	return state


static func ensure_state_keys(state: Dictionary, data: GameData = null) -> void:
	## Fill state keys added by later phases with their defaults, so a save
	## written before those phases loads cleanly (save compatibility is
	## additive; SAVE_VERSION stays 2). Every new engine reader ALSO tolerates
	## the missing key via .get — this just normalizes eagerly on load.
	## With `data` supplied, a pre-knowledge save's factions receive their
	## culture's 270 BC technique endowment instead of an empty ledger.
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction.has("ai"):
			faction["ai"] = {}
		if not faction.has("attitude_memory"):
			faction["attitude_memory"] = {}
		if not faction.has("reform_pressure"):
			faction["reform_pressure"] = 0.0
		if not faction.has("knowledge"):
			faction["knowledge"] = {} if (data == null or faction_id == "rebels") \
				else _starting_knowledge(data, faction_id)
		if not faction.has("edicts"):
			faction["edicts"] = {}
		if not faction.has("edict_cooldowns"):
			faction["edict_cooldowns"] = {}
		if not faction.has("outlawed"):
			faction["outlawed"] = false
		if not faction.has("war_record"):
			faction["war_record"] = empty_war_record()
		if not faction.has("war_mood"):
			faction["war_mood"] = null
	for settlement in state["settlements"].values():  # pure key-add — order-free
		if not settlement.has("levy_strain"):
			settlement["levy_strain"] = 0.0
	if not state.has("modifiers"):
		state["modifiers"] = []
	if not state.has("chronicle"):
		state["chronicle"] = []
	if not state.has("wars"):
		state["wars"] = []
	if not state.has("event_cooldowns"):
		state["event_cooldowns"] = {}
	if not state.has("world_seed"):
		# Saves written before the seed travelled cannot recover it; 0 reads
		# as "unknown" everywhere the seed is shown.
		state["world_seed"] = 0
	# Chronicle-era per-entity keys (reigns, deeds, epithets, unit arming) are
	# created lazily by their writers, but the save contract wants them
	# normalized on load too. Reign fills with the TRUE current leader — a
	# placeholder would make the first collect() read a false succession.
	for faction_id in faction_ids:
		var faction: Dictionary = state["factions"][faction_id]
		if not faction.has("reign"):
			faction["reign"] = {
				"leader": ChronicleRules.leader_of(state, faction_id),
				"since_turn": int(state.get("turn", 0)),
			}
	var char_ids: Array = state["characters"].keys()
	char_ids.sort()
	for char_id in char_ids:
		var character: Dictionary = state["characters"][char_id]
		if not character.has("deeds"):
			character["deeds"] = {}
		if not character.has("epithet"):
			character["epithet"] = ""
		if not character.has("office"):
			character["office"] = null
		if not character.has("offices_held"):
			character["offices_held"] = []
	for army in state["armies"].values():  # pure key-add — order-free
		_ensure_unit_arms(army["units"])
	for fleet in state["fleets"].values():
		_ensure_unit_arms(fleet["ships"])
	for settlement in state["settlements"].values():
		_ensure_unit_arms(settlement["garrison"])
	if not state.has("tributes"):
		state["tributes"] = []
	if not state.has("pending_offers"):
		state["pending_offers"] = []
	if not state.has("agents"):
		state["agents"] = {}


static func _ensure_unit_arms(units: Array) -> void:
	for unit in units:
		if not unit.has("weapon"):
			unit["weapon"] = 0
		if not unit.has("armor"):
			unit["armor"] = 0


static func empty_war_record() -> Dictionary:
	## Battles won and lost, and how many battles were fought against each unit
	## class — the record military techniques read as prerequisites.
	return {"battles_won": 0, "battles_lost": 0, "faced": {}}


static func _starting_knowledge(data: GameData, faction_id: String) -> Dictionary:
	## The 270 BC endowment: crafts this court's culture (or the court itself,
	## by faction id) already practices when the campaign opens.
	var culture := data.culture_of_faction(faction_id)
	var knowledge := {}
	var technique_ids: Array = data.techniques.keys()
	technique_ids.sort()
	for tid in technique_ids:
		var start: Dictionary = data.techniques[tid].get("start_adopted", {})
		if start.get("cultures", []).has(culture) or start.get("factions", []).has(faction_id):
			knowledge[tid] = {"stage": "adopted", "turn": 0, "progress": 0, "discount_pct": 0.0}
	return knowledge


static func _settlement(data: GameData, setup: Dictionary, owner: String) -> Dictionary:
	var buildings := {}
	for level_id in setup.get("buildings", []):
		var info: Dictionary = data.building_levels.get(level_id, {})
		if info.is_empty():
			push_warning("campaign.json references unknown building level: " + str(level_id))
			continue
		var chain_id: String = info["chain"]
		buildings[chain_id] = maxi(int(buildings.get(chain_id, 0)), int(info["index"]))
	var settlement := {
		"owner": owner,
		"population": int(setup["population"]),
		"buildings": buildings,
		"tax_level": setup.get("tax_level", "normal"),
		"garrison": _units(setup.get("garrison", [])),
		"construction_queue": [],
		"recruitment_queue": [],
		"governor": null,
		"slave_bonus_turns": 0,
		"plague_turns": 0,
		"recently_conquered": 0,
		"low_order_streak": 0,
		"siege": null,
		"levy_strain": 0.0,
		"edict": EdictRules.new_record(),
	}
	# Starting garrisons were raised by the city they stand in, so they carry its
	# forges and armouries just as newly recruited units do.
	var weapon := int(SettlementRules.effect_max(data, settlement, "weapon_upgrade"))
	var armor := int(SettlementRules.effect_max(data, settlement, "armor_upgrade"))
	for unit in settlement["garrison"]:
		unit["weapon"] = weapon
		unit["armor"] = armor
	# At the campaign start every people is ruled by its own kind; conquest is
	# what makes a province a stranger to its masters (see record_conquest).
	var dominant := SocietyRules.dominant_culture(data, settlement)
	var native: bool = dominant == "" or data.culture_of_faction(owner) == dominant
	settlement["society"] = SocietyRules.new_settlement_society(
		data, native, SocietyRules.provision(data, settlement))
	return settlement


static func _units(setups: Array) -> Array:
	var result: Array = []
	for setup in setups:
		result.append({
			"template": setup["template"],
			"experience": int(setup.get("experience", 0)),
			"strength_pct": int(setup.get("strength_pct", 100)),
			"weapon": int(setup.get("weapon", 0)),
			"armor": int(setup.get("armor", 0)),
		})
	return result


static func _add_army(state: Dictionary, setup: Dictionary, owner: String) -> void:
	var army_id := "army_%d" % state["next_id"]
	state["next_id"] += 1
	state["armies"][army_id] = {
		"owner": owner,
		"region": setup["region"],
		"units": _units(setup["units"]),
		"general": setup.get("general", null),
		"movement_left": 0.0,
	}


static func _add_fleet(state: Dictionary, setup: Dictionary, owner: String) -> void:
	var fleet_id := "fleet_%d" % state["next_id"]
	state["next_id"] += 1
	state["fleets"][fleet_id] = {
		"owner": owner,
		"sea_zone": setup["sea_zone"],
		"ships": _units(setup["ships"]),
		"movement_left": 0.0,
	}


static func _add_character(data: GameData, state: Dictionary, setup: Dictionary, owner: String) -> void:
	# Starting trait ids become just enough points to hold the trait's first level.
	var trait_points := {}
	for trait_id in setup.get("traits", []):
		var trait_def: Dictionary = data.traits.get(trait_id, {})
		if not trait_def.is_empty():
			trait_points[trait_id] = int(trait_def["levels"][0]["threshold"])
	state["characters"][setup["id"]] = {
		"faction": owner,
		"name": setup["name"],
		"age": int(setup["age"]),
		"role": setup["role"],
		"gender": setup.get("gender", "female" if setup["role"] == "spouse" else "male"),
		"father": setup.get("father", null),
		"command": int(setup.get("command", 0)),
		"management": int(setup.get("management", 0)),
		"influence": int(setup.get("influence", 0)),
		"trait_points": trait_points,
		"ancillaries": [],
		"location": setup.get("location", ""),
		"alive": true,
		"deeds": {},
		"epithet": "",
		"office": null,
		"offices_held": [],
	}
