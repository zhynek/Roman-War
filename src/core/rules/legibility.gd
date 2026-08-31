class_name LegibilityRules
## A state can only act on what it can see, and seeing is infrastructure. Clarity
## is DERIVED — never stored — from distance to the capital, roads, the tier of
## the government building, and whether anyone of yours is actually standing
## there. Where clarity is low the player is shown a stale, rounded survey rather
## than the live stock.
##
## This is lag, not lying: the reported figure is a real reading from a real
## earlier turn. It is fully deterministic, replays identically from a save, and
## consumes NO randomness — which matters, because these queries are called from
## the UI arbitrarily often and must never touch state.rng_state.

const LEVEL_EXACT := "exact"
const LEVEL_BANDED := "banded"
const LEVEL_RUMOUR := "rumour"


static func clarity(data: GameData, state: Dictionary, region_id: String) -> float:
	var settlement: Dictionary = state["settlements"][region_id]
	var rules: Dictionary = data.balance["society"]
	var owner: String = settlement["owner"]
	var capital: String = state["factions"].get(owner, {}).get("capital", "")

	var value := 1.0
	if capital != "" and capital != region_id:
		var hops := MapRules.hops_between(data, capital, region_id)
		if hops < 0:
			hops = int(data.balance["distance_to_capital"]["max_penalty_pct"] \
				/ maxf(float(data.balance["distance_to_capital"]["pct_per_hop"]), 1.0))
		value -= float(hops) * float(rules["clarity_per_hop"])

	value += SettlementRules.effect_max(data, settlement, "road_level") * float(rules["clarity_road_bonus"])
	value += float(SocietyRules.government_tier(data, settlement)) * float(rules["clarity_government_tier_bonus"])

	var governor = settlement["governor"]
	if governor != null and state["characters"].has(governor):
		var management := CharacterRules.effective(data, state["characters"][governor], "management")
		value += float(management) * float(rules["clarity_governor_management_bonus"])

	value += AdvanceRules.effect_total(data, state, owner, "clarity_bonus")
	return clampf(value, float(rules["clarity_min"]), 1.0)


static func level_for(data: GameData, state: Dictionary, region_id: String) -> String:
	var rules: Dictionary = data.balance["society"]
	var value := clarity(data, state, region_id)
	if value >= float(rules["clarity_exact_threshold"]):
		return LEVEL_EXACT
	if value >= float(rules["clarity_banded_threshold"]):
		return LEVEL_BANDED
	return LEVEL_RUMOUR


static func survey_interval(data: GameData, state: Dictionary, region_id: String) -> int:
	## How many turns pass between readings. A well-administered province reports
	## every turn; a barely-governed one reports when word happens to arrive.
	var rules: Dictionary = data.balance["society"]
	var span := float(rules["survey_interval_turns_max"]) * (1.0 - clarity(data, state, region_id))
	return maxi(1, int(round(span)))


static func refresh_surveys(data: GameData, state: Dictionary, region_ids: Array) -> void:
	## Take a reading wherever one is due. Runs after the stocks have moved, so a
	## survey always records a real state the province was actually in.
	var turn := int(state["turn"])
	for region_id in region_ids:
		var settlement: Dictionary = state["settlements"][region_id]
		var society: Dictionary = settlement.get("society", {})
		if society.is_empty():
			continue
		var survey: Dictionary = society.get("survey", {})
		var due: bool = survey.is_empty() \
			or turn - int(survey.get("turn", turn)) >= survey_interval(data, state, region_id)
		if not due:
			continue
		society["survey"] = {
			"turn": turn,
			"legitimacy": float(society.get("legitimacy", 0.0)),
			"grievance": float(society.get("grievance", 0.0)),
			"assimilation": float(society.get("assimilation", 0.0)),
			"unrest_state": String(society.get("unrest_state", SocietyRules.UNREST_CALM)),
		}


static func reported(data: GameData, state: Dictionary, region_id: String) -> Dictionary:
	## What the player is entitled to know about this province right now:
	##   {level, stale_turns, exact: bool, legitimacy, grievance, assimilation,
	##    unrest_state}
	## Values are banded at middling clarity and withheld entirely at low clarity,
	## where only the unrest state — the thing travellers gossip about — survives.
	var settlement: Dictionary = state["settlements"][region_id]
	var rules: Dictionary = data.balance["society"]
	var society: Dictionary = settlement.get("society", {})
	var live := SocietyRules.stocks_of(data, settlement)
	var level := level_for(data, state, region_id)
	var survey: Dictionary = society.get("survey", {})

	if level == LEVEL_EXACT or survey.is_empty():
		return {
			"level": level,
			"stale_turns": 0,
			"exact": level == LEVEL_EXACT,
			"legitimacy": live["legitimacy"],
			"grievance": live["grievance"],
			"assimilation": live["assimilation"],
			"unrest_state": live["unrest_state"],
		}

	var stale := maxi(0, int(state["turn"]) - int(survey.get("turn", 0)))
	var band := float(rules["clarity_band_size"])
	var result := {
		"level": level,
		"stale_turns": stale,
		"exact": false,
		"unrest_state": String(survey.get("unrest_state", live["unrest_state"])),
	}
	if level == LEVEL_BANDED:
		for key in ["legitimacy", "grievance", "assimilation"]:
			result[key] = round(float(survey.get(key, 0.0)) / band) * band
	else:
		# Barely governed: no figures at all, only what is said about the place.
		for key in ["legitimacy", "grievance", "assimilation"]:
			result[key] = null
	return result
