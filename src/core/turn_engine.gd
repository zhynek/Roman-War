class_name TurnEngine
## End-turn resolution, in a fixed order so campaigns are reproducible:
##   1. AI stub turns (non-player factions)
##   2. Sieges progress (starve-outs resolve through the BattleResolver)
##   3. Construction and recruitment queues advance
##   4. Faction treasuries resolve (income - upkeep, debt disbandment)
##   5. Population growth, slaves, plague
##   6. Public order: riots and revolts
##   7. Events, disasters, senate politics
##   8. Date advances (2 turns/year), movement points reset, victory check
##
## Returns a report dict of everything notable that happened, for the UI's
## event scrolls.


static func end_turn(data: GameData, state: Dictionary, resolver: BattleResolver) -> Dictionary:
	var rng := CampaignRng.new()
	rng.set_state(int(state["rng_state"]))
	var report := {
		"turn": state["turn"], "sieges": [], "completed_buildings": {},
		"completed_units": {}, "rioted": [], "revolted": [], "events": [],
		"senate": [], "winner": null,
	}

	for faction_id in state["factions"]:
		if faction_id != state["player_faction"]:
			AiStub.take_turn(data, state, faction_id)

	report["sieges"] = SiegeRules.advance_sieges(data, state, rng, resolver)
	for siege_event in report["sieges"]:
		var result: Dictionary = siege_event.get("result", {})
		if result.get("captured", false):
			# AI-side starve-outs default to occupation; the player's own
			# assaults go through Game.assault_settlement, which asks.
			CombatRules.capture_settlement(data, state, rng,
				siege_event["region"], result["capture_pending_owner"], "occupy")

	for region_id in state["settlements"]:
		var completed_buildings := ConstructionRules.advance_queues(data, state, region_id)
		if not completed_buildings.is_empty():
			report["completed_buildings"][region_id] = completed_buildings
		var completed_units := RecruitmentRules.advance_queues(data, state, region_id)
		if not completed_units.is_empty():
			report["completed_units"][region_id] = completed_units

	for faction_id in state["factions"]:
		if state["factions"][faction_id]["alive"]:
			EconomyRules.apply_faction_turn(data, state, faction_id, rng)

	for region_id in state["settlements"]:
		GrowthRules.apply_turn(data, state, region_id, rng)

	for region_id in state["settlements"].keys():
		var order_result := PublicOrderRules.apply_turn(data, state, region_id, rng)
		if order_result["rioted"]:
			report["rioted"].append(region_id)
		if order_result["revolted"]:
			report["revolted"].append(region_id)

	report["events"] = EventRules.process_turn(data, state, rng)
	report["senate"] = SenateRules.process_turn(data, state, rng)

	state["turn"] = int(state["turn"]) + 1
	var turns_per_year := int(data.balance["time"]["turns_per_year"])
	if state["season"] == "summer":
		state["season"] = "winter"
	else:
		state["season"] = "summer"
	if int(state["turn"]) % turns_per_year == 0:
		state["year"] = int(state["year"]) + 1
		if int(state["year"]) == 0:
			state["year"] = 1  # no year zero
		_age_characters(state)

	MovementRules.reset_movement(data, state)
	report["winner"] = VictoryRules.check(data, state)

	state["rng_state"] = rng.get_state()
	return report


static func _age_characters(state: Dictionary) -> void:
	for character in state["characters"].values():
		if character["alive"]:
			character["age"] = int(character["age"]) + 1
