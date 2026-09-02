class_name VictoryRules
## Victory/defeat evaluation against data/win_conditions.json, plus the
## campaign time limit. Long/short campaign choice lives in state.campaign_mode
## (default "long").


static func check(data: GameData, state: Dictionary) -> Variant:
	## Returns the winning faction id, "time_up" past the end year, or null.
	if state["winner"] != null:
		return state["winner"]
	var mode: String = state.get("campaign_mode", "long")

	for condition in data.win_conditions:
		if condition["campaign"] != mode:
			continue
		var faction_id: String = condition["faction"]
		if not state["factions"].has(faction_id) or not state["factions"][faction_id]["alive"]:
			continue
		if _satisfied(data, state, faction_id, condition):
			state["winner"] = faction_id
			return faction_id

	if int(state["year"]) > int(data.balance["time"]["end_year"]):
		state["winner"] = "time_up"
		return "time_up"
	return null


static func progress(data: GameData, state: Dictionary, faction_id: String) -> Dictionary:
	var mode: String = state.get("campaign_mode", "long")
	for condition in data.win_conditions:
		if condition["campaign"] == mode and condition["faction"] == faction_id:
			return {
				"regions_held": _regions_held(state, faction_id).size(),
				"regions_needed": int(condition["hold_regions_count"]),
				"satisfied": _satisfied(data, state, faction_id, condition),
			}
	return {}


static func _satisfied(data: GameData, state: Dictionary, faction_id: String, condition: Dictionary) -> bool:
	var held := _regions_held(state, faction_id)
	if held.size() < int(condition["hold_regions_count"]):
		return false
	for region_id in condition.get("must_hold_regions", []):
		if not held.has(region_id):
			return false
	for enemy_id in condition.get("outlive_factions", []):
		if state["factions"].has(enemy_id) and state["factions"][enemy_id]["alive"]:
			return false
	if condition.get("requires_civil_war_victory", false):
		# The Republic must be over: the Senate destroyed, by this house or by
		# any other that broke with it. A house that survives the Senate's
		# fall and holds Rome may claim the age.
		if SenateRules.senate_faction(data, state) != "":
			return false
	return true


static func _regions_held(state: Dictionary, faction_id: String) -> Dictionary:
	var held := {}
	for region_id in state["settlements"]:
		if state["settlements"][region_id]["owner"] == faction_id:
			held[region_id] = true
	return held
