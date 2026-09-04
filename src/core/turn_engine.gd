class_name TurnEngine
## End-turn resolution, in a fixed order so campaigns are reproducible:
##   1. AI turns: every non-player faction plays (AiController); offers
##      made to the player last season expire first, new ones queue
##   2. Sieges progress (starve-outs resolve through the BattleResolver)
##   3. Construction and recruitment queues advance
##   4. Faction treasuries resolve (income - upkeep, debt disbandment), then
##      diplomacy: opinions drift, tributes and protectorate dues are paid
##   5. Population growth, slaves, plague
##   6. Public order: riots and revolts
##   7. Events, disasters, senate politics
##   8. Character triggers, then covert agents abroad risk detection
##   9. Date advances (2 turns/year), movement points reset, victory check
##
## Returns a report dict of everything notable that happened, for the UI's
## event scrolls.


static func end_turn(data: GameData, state: Dictionary, resolver: BattleResolver) -> Dictionary:
	var rng := CampaignRng.from_state_string(String(state["rng_state"]))
	var report := {
		"turn": state["turn"], "sieges": [], "completed_buildings": {},
		"completed_units": {}, "rioted": [], "revolted": [], "events": [],
		"senate": [], "characters": [], "agents": [], "diplomacy": [], "ai": [], "offers": [],
		"winner": null,
	}

	# World loops iterate in sorted id order so the RNG stream is identical
	# no matter how the state dictionaries were built (fresh game or loaded
	# save — JSON round trips re-order keys).
	var faction_ids: Array = state["factions"].keys()
	faction_ids.sort()
	var region_ids: Array = state["settlements"].keys()
	region_ids.sort()

	# Offers the player left unanswered lapse with the season.
	state["pending_offers"] = []
	for faction_id in faction_ids:
		if faction_id != state["player_faction"]:
			AiController.take_turn(data, state, rng, resolver, faction_id, report["ai"])
	report["offers"] = state["pending_offers"].duplicate(true)
	# The AI's battles carry character news (traits, adoptions, successions)
	# that belongs with the rest of the family report.
	var ai_notices: Array = []
	for notice in report["ai"]:
		if notice.get("kind", "") in ["trait", "ancillary", "man_of_the_hour", "succession", "new_heir"]:
			report["characters"].append(notice)
		else:
			ai_notices.append(notice)
	report["ai"] = ai_notices

	# Governorship follows presence, so it is re-derived before anything reads it.
	SettlementRules.refresh_governors(data, state)

	report["sieges"] = SiegeRules.advance_sieges(data, state, rng, resolver)
	for siege_event in report["sieges"]:
		var result: Dictionary = siege_event.get("result", {})
		if result.get("captured", false):
			# A starved-out city falls to the player as an occupation (nobody
			# was asked); to an AI besieger by its personality's cruelty.
			# Either way the besieging general answers for how it was treated.
			var besieger = result.get("besieger_general")
			var new_owner: String = result["capture_pending_owner"]
			var occupation := "occupy"
			if new_owner != state["player_faction"]:
				occupation = AiMilitary.occupation_choice(data, state,
					AiController.context(data, state, new_owner), siege_event["region"])
			siege_event["occupation"] = occupation
			CombatRules.capture_settlement(data, state, rng, siege_event["region"], new_owner, occupation)
			CombatRules.fire_occupation_triggers(
				data, state, rng, besieger, occupation, report["characters"])

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
	report["diplomacy"] = DiplomacyRules.process_turn(data, state)

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
	report["agents"] = AgentRules.process_turn(data, state, rng)
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
	report["winner"] = VictoryRules.check(data, state)

	state["rng_state"] = rng.state_string()
	return report
