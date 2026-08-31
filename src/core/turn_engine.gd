class_name TurnEngine
## End-turn resolution, in a fixed order so campaigns are reproducible:
##   1. AI turns (non-player factions): build, muster, march, besiege, declare
##   2. Sieges progress (starve-outs resolve through the BattleResolver)
##   3. Construction and recruitment queues advance
##   4. Faction treasuries resolve (income - upkeep, debt disbandment)
##   5. Population growth, slaves, plague
##   6. Public order: riots and revolts
##   7. Events, disasters, senate politics
##   8. Date advances (2 turns/year), movement points reset, victory check
##
## Every notable step appends a beat to the turn journal (see TurnJournal),
## which is stored in state["journal"] for the day's sequence and Dispatch and
## returned inside the report dict the UI already consumed.


static func end_turn(data: GameData, state: Dictionary, resolver: BattleResolver) -> Dictionary:
	var rng := CampaignRng.from_state_string(String(state["rng_state"]))
	var journal: Array = []
	var before := TurnJournal.snapshot(data, state)
	var report := {
		"turn": state["turn"], "sieges": [], "completed_buildings": {},
		"completed_units": {}, "rioted": [], "revolted": [], "events": [],
		"senate": [], "characters": [], "winner": null, "journal": journal,
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
			AiRules.take_turn(data, state, faction_id, rng, resolver, journal)

	# Governorship follows presence, so it is re-derived before anything reads it.
	SettlementRules.refresh_governors(data, state)

	report["sieges"] = SiegeRules.advance_sieges(data, state, rng, resolver)
	for siege_event in report["sieges"]:
		var result: Dictionary = siege_event.get("result", {})
		var region_id: String = siege_event["region"]
		var defender: String = String(state["settlements"][region_id]["owner"])
		TurnJournal.add(journal, "siege_starved", {
			"faction": defender, "region": region_id,
			"extra": {"captured": result.get("captured", false)},
		})
		if result.get("captured", false):
			# Starve-outs default to occupation; the player's own assaults go
			# through Game.assault_settlement, which asks. Either way the
			# besieging general answers for how the city was treated.
			var besieger = result.get("besieger_general")
			var new_owner: String = String(result["capture_pending_owner"])
			CombatRules.capture_settlement(data, state, rng,
				region_id, new_owner, "occupy")
			CombatRules.fire_occupation_triggers(
				data, state, rng, besieger, "occupy", report["characters"])
			TurnJournal.add(journal, "settlement_captured", {
				"faction": new_owner, "other": defender, "region": region_id,
				"extra": {"occupation": "occupy"},
			})

	for region_id in region_ids:
		var owner: String = String(state["settlements"][region_id]["owner"])
		var completed_buildings := ConstructionRules.advance_queues(data, state, region_id)
		if not completed_buildings.is_empty():
			report["completed_buildings"][region_id] = completed_buildings
			for level_id in completed_buildings:
				TurnJournal.add(journal, "building_completed", {
					"faction": owner, "region": region_id, "subject": level_id,
				})
		var completed_units := RecruitmentRules.advance_queues(data, state, region_id)
		if not completed_units.is_empty():
			report["completed_units"][region_id] = completed_units
			for template_id in completed_units:
				TurnJournal.add(journal, "unit_mustered", {
					"faction": owner, "region": region_id, "subject": template_id,
				})

	for faction_id in faction_ids:
		if state["factions"][faction_id]["alive"]:
			var purse := EconomyRules.apply_faction_turn(data, state, faction_id, rng)
			TurnJournal.add(journal, "treasury_change", {
				"faction": faction_id, "region": state["factions"][faction_id]["capital"],
				"value": int(round(float(purse["net"]))),
				"extra": {
					"income": int(round(float(purse["income"]))),
					"upkeep": int(purse["upkeep"]),
					"treasury": int(state["factions"][faction_id]["treasury"]),
				},
			})
			if purse.get("disbanded", false):
				TurnJournal.add(journal, "unit_disbanded", {"faction": faction_id})

	for region_id in region_ids:
		# A settlement outgrowing (or losing) its tier is caught by the
		# end-of-turn snapshot diff, which sees construction, riot damage and
		# conquest alike. Only the plague needs reporting from here — an
		# outbreak that starts and is survived leaves no trace in a before/after.
		var grew := GrowthRules.apply_turn(data, state, region_id, rng)
		if grew["plague_started"]:
			TurnJournal.add(journal, "plague_outbreak", {
				"faction": state["settlements"][region_id]["owner"], "region": region_id,
			})

	for region_id in region_ids:
		var owner: String = String(state["settlements"][region_id]["owner"])
		var order_result := PublicOrderRules.apply_turn(data, state, region_id, rng)
		if order_result["rioted"]:
			report["rioted"].append(region_id)
			TurnJournal.add(journal, "settlement_riot", {
				"faction": owner, "region": region_id,
				"value": int(round(float(order_result["order"]))),
			})
		if order_result["revolted"]:
			report["revolted"].append(region_id)
			TurnJournal.add(journal, "settlement_revolt", {
				"faction": owner, "region": region_id,
				"value": int(round(float(order_result["order"]))),
			})

	report["events"] = EventRules.process_turn(data, state, rng)
	for fired in report["events"]:
		if fired["kind"] == "event":
			TurnJournal.add(journal, "world_event", {
				"faction": fired.get("faction", ""), "subject": fired["id"],
			})
		else:
			TurnJournal.add(journal, "disaster", {
				"faction": state["settlements"].get(fired.get("region", ""), {}).get("owner", ""),
				"region": fired.get("region", ""), "subject": fired["id"],
			})

	report["senate"] = SenateRules.process_turn(data, state, rng)
	for notice in report["senate"]:
		_journal_senate_notice(data, journal, notice)

	var character_notices := CharacterRules.process_turn(data, state, rng)
	report["characters"].append_array(character_notices)
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

	for notice in report["characters"]:
		TurnJournal.add_character_notice(state, journal, notice)

	# Diplomacy, the treasuries and every capital are photographed rather than
	# instrumented: stances change hands in the player's panel, in the AI, and
	# implicitly whenever an army attacks, and a diff catches all three.
	TurnJournal.diff(data, state, before, journal)

	if report["winner"] != null:
		TurnJournal.add(journal, "campaign_decided", {"faction": String(report["winner"])})

	state["journal"] = {"turn": int(state["turn"]), "beats": journal}
	state["rng_state"] = rng.state_string()
	return report


static func _journal_senate_notice(data: GameData, journal: Array, notice: Dictionary) -> void:
	var kind: String = String(notice["kind"])
	if kind == "civil_war":
		TurnJournal.add(journal, "civil_war", {"faction": notice["faction"]})
		return
	if not ["mission_issued", "mission_progress", "mission_complete", "mission_failed"].has(kind):
		return
	var template_id: String = String(notice.get("mission", ""))
	var template: Dictionary = data.missions.get(template_id, {})
	TurnJournal.add(journal, kind, {
		"faction": notice["faction"],
		"region": String(notice.get("target_region", "")),
		"other": String(notice.get("target_faction", "")),
		"subject": template_id,
		"value": int(notice.get("turns_left", template.get("reward", {}).get("treasury", 0))),
		"extra": {"reward_treasury": int(template.get("reward", {}).get("treasury", 0))},
	})
