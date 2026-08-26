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
	var rng := CampaignRng.from_state_string(String(state["rng_state"]))
	var report := {
		"turn": state["turn"], "sieges": [], "completed_buildings": {},
		"completed_units": {}, "rioted": [], "revolted": [], "events": [],
		"senate": [], "characters": [], "marches": [], "winner": null,
	}

	# World loops iterate in sorted id order so the RNG stream is identical
	# no matter how the state dictionaries were built (fresh game or loaded
	# save — JSON round trips re-order keys).
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()

	for faction_id in faction_ids:
		if faction_id != state["player_faction"]:
			AiStub.take_turn(data, state, faction_id)

	# Governorship follows presence, so it is re-derived before anything reads it.
	SettlementRules.refresh_governors(data, state)

	report["sieges"] = SiegeRules.advance_sieges(data, state, rng, resolver)
	for siege_event in report["sieges"]:
		var result: Dictionary = siege_event.get("result", {})
		if result.get("captured", false):
			# Starve-outs default to occupation; the player's own assaults go
			# through Game.assault_settlement, which asks. Either way the
			# besieging general answers for how the city was treated.
			var besieger = result.get("besieger_general")
			CombatRules.capture_settlement(data, state, rng,
				siege_event["region"], result["capture_pending_owner"], "occupy")
			CombatRules.fire_occupation_triggers(
				data, state, rng, besieger, "occupy", report["characters"])

	for region_id in region_ids:
		var completed_buildings := ConstructionRules.advance_queues(data, state, region_id)
		if not completed_buildings.is_empty():
			report["completed_buildings"][region_id] = completed_buildings
		var completed_units := RecruitmentRules.advance_queues(data, state, region_id)
		if not completed_units.is_empty():
			report["completed_units"][region_id] = completed_units

	for faction_id in faction_ids:
		if state["factions"][faction_id]["alive"]:
			EconomyRules.apply_faction_turn(data, state, faction_id, rng)

	for region_id in region_ids:
		GrowthRules.apply_turn(data, state, region_id, rng)

	for region_id in region_ids:
		var order_result := PublicOrderRules.apply_turn(data, state, region_id, rng)
		if order_result["rioted"]:
			report["rioted"].append(region_id)
		if order_result["revolted"]:
			report["revolted"].append(region_id)

	report["events"] = EventRules.process_turn(data, state, rng)
	report["senate"] = SenateRules.process_turn(data, state, rng)
	report["characters"].append_array(CharacterRules.process_turn(data, state, rng))
	EventRules.tick_event_happiness(state)
	MercenaryRules.replenish(data, state)

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
		report["characters"].append_array(FamilyRules.process_year(data, state, rng))

	MovementRules.reset_movement(data, state)

	# Queued marches resume on the fresh points. No RNG is drawn here, but the
	# report order must not depend on dictionary order either — sorted ids.
	var army_ids: Array = state["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army: Dictionary = state["armies"][army_id]
		if army.get("march_path", []).is_empty():
			continue
		var destination := String(army["march_path"].back())
		var outcome := PathfindingRules.advance_march(data, state, army_id)
		report["marches"].append({
			"army": army_id, "owner": army["owner"], "region": army["region"],
			"destination": destination, "arrived": outcome["arrived"],
			"halted": outcome["halted"],
		})

	report["winner"] = VictoryRules.check(data, state)

	state["rng_state"] = rng.state_string()
	return report
