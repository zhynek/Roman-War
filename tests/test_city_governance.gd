extends RefCounted
## City movement is deliberately absent: every civic effect has an explicit
## command, a budget consequence, and a deterministic save/replay boundary.


func _game() -> Game:
	return Game.new_campaign("senate", 42, "medium", "long", false)


func test_status_is_pure_and_has_named_unrest_factors(t) -> void:
	var game := _game()
	var before := JSON.stringify(game.state)
	var report := game.city_status("latium")
	var total := 0.0
	for factor in report["factors"]:
		t.check(String(factor["label"]) != "", "every factor has a content key")
		total += float(factor["value"])
	t.check_near(report["unrest"], clampf(total, 0.0, 100.0), 0.0001, "unrest is the sum of inspectable factors")
	for repeat in range(10):
		game.city_status("latium")
	t.check_eq(JSON.stringify(game.state), before, "repeated status/render queries change no state")
	t.check_eq(report["day"], 1, "the first local day is shown without storing it")
	t.check_eq(report["mood"], "restive", "the prototype opens with visible civic problems")


func test_status_does_not_expose_mutable_state_or_content_aliases(t) -> void:
	var game := _game()
	RomaCityRules.ensure_city(game.data, game.state, "latium")
	var before := JSON.stringify(game.state)
	var content_before := JSON.stringify(game.data.city_governance)
	var report := game.city_status("latium")
	report["policies"]["patrols"] = "heavy"
	report["projects"]["repair_streets"]["completed"] = true
	report["actions"][0]["cost"] = -1000
	report["factors"].clear()
	t.check_eq(JSON.stringify(game.state), before, "presentation may not rewrite persistent policies or projects through a report")
	t.check_eq(JSON.stringify(game.data.city_governance), content_before, "report mutations cannot alter immutable content")


func test_foreign_unknown_and_unsupported_city_actions_leave_state_unchanged(t) -> void:
	var game := _game()
	var before := JSON.stringify(game.state)
	for region in ["campania", "not_a_region"]:
		t.check(not game.city_action(region, "grain_relief"), "cannot spend on foreign or unknown city")
		t.check(not game.city_advance_day(region), "cannot advance foreign or unknown city")
		t.check(not RomaCityRules.ensure_city(game.data, game.state, region), "cannot initialize foreign city")
	t.check(not game.city_action("latium", "invented_action"), "unknown content IDs fail safely")
	t.check_eq(JSON.stringify(game.state), before, "every rejected command is atomic")
	game.state["settlements"]["campania"]["owner"] = "senate"
	before = JSON.stringify(game.state)
	t.check_eq(game.city_status("campania")["reason"], "unsupported_city", "only modeled city is supported")
	t.check(not game.city_action("campania", "grain_relief"), "ownership does not invent geometry")
	t.check_eq(JSON.stringify(game.state), before, "unsupported owned city also remains unchanged")


func test_insufficient_budget_does_not_create_city_or_charge_partial_cost(t) -> void:
	var game := _game()
	game.state["factions"]["senate"]["treasury"] = 0
	var before := JSON.stringify(game.state)
	t.check(not game.city_action("latium", "grain_relief"), "relief must be funded")
	t.check(not game.city_advance_day("latium"), "daily civic upkeep must be funded")
	t.check_eq(JSON.stringify(game.state), before, "failed funding leaves no partial changes")
	t.check_eq(game.city_status("latium")["advance_reason"], "insufficient_funds", "UI gets a refusal key")


func test_grain_spends_once_and_changes_society_only_on_explicit_day(t) -> void:
	var game := _game()
	var before := game.city_status("latium")
	var rng: String = game.state["rng_state"]
	t.check(game.city_action("latium", "grain_relief"), "grant relief")
	var granted := game.city_status("latium")
	t.check_eq(granted["treasury"], int(before["treasury"]) - int(game.data.balance["city"]["action_costs"]["grain_relief"]), "grain purchases consume treasury")
	t.check_eq(granted["grievance"], before["grievance"], "ordering does not rewrite a slow stock")
	t.check(granted["unrest"] < before["unrest"], "the visible queue reduces immediate pressure")
	t.check(not game.city_action("latium", "grain_relief"), "cannot stack active grain grants")
	t.check(game.city_advance_day("latium"), "explicitly resolve local day")
	var after := game.city_status("latium")
	t.check(after["grievance"] < before["grievance"], "relief is felt after a day")
	t.check(after["legitimacy"] > before["legitimacy"], "provision builds consent slowly")
	t.check_eq(game.state["turn"], 0, "campaign seasons do not advance")
	t.check_eq(game.state["rng_state"], rng, "city actions and days never consume RNG")
	t.check_eq(after["grain_days"], int(granted["grain_days"]) - 1, "one daily ration is consumed")


func test_projects_have_real_delays_and_cannot_be_rebought(t) -> void:
	var game := _game()
	var before := game.city_status("latium")
	t.check(game.city_action("latium", "repair_streets"), "fund street repairs")
	t.check(game.city_action("latium", "clean_water"), "fund clean water")
	t.check_eq(game.city_status("latium")["street_condition"], before["street_condition"], "work order does not instantly rebuild roads")
	t.check(not game.city_action("latium", "repair_streets"), "active project cannot be duplicated")
	var street_days := int(game.data.balance["city"]["project_days"]["repair_streets"])
	for day in range(street_days - 1):
		game.city_advance_day("latium")
	t.check_eq(game.city_status("latium")["street_condition"], before["street_condition"], "road crews need every promised day")
	game.city_advance_day("latium")
	var repaired := game.city_status("latium")
	t.check(repaired["street_condition"] > before["street_condition"], "completed road works are visible")
	t.check(repaired["projects"]["repair_streets"]["completed"], "completion persists")
	t.check_eq(repaired["cleanliness"], before["cleanliness"], "water work has its own delay")
	t.check(not game.city_action("latium", "repair_streets"), "completed infrastructure cannot be rebought")
	game.city_advance_day("latium")
	t.check(game.city_status("latium")["cleanliness"] > before["cleanliness"], "sanitation improves after four funded days")


func test_patrols_reduce_visible_pressure_but_grow_grievance_and_cost_money(t) -> void:
	var regular := _game()
	var heavy := _game()
	var before := heavy.city_status("latium")
	t.check(heavy.city_action("latium", "patrols_increase"), "deploy extra patrols")
	var deployed := heavy.city_status("latium")
	t.check(deployed["unrest"] < before["unrest"], "patrols visibly suppress disorder")
	t.check(deployed["daily_cost"] > before["daily_cost"], "extra patrols carry recurring wages")
	regular.city_advance_day("latium")
	heavy.city_advance_day("latium")
	t.check(heavy.city_status("latium")["grievance"] > regular.city_status("latium")["grievance"], "coercion increases grievance despite quieter streets")
	t.check(heavy.city_status("latium")["legitimacy"] < regular.city_status("latium")["legitimacy"], "coercion erodes consent")


func test_tavern_licences_have_an_explicit_reversible_cost(t) -> void:
	var game := _game()
	var before := game.city_status("latium")
	t.check(game.city_action("latium", "close_taverns"), "close licences")
	var closed := game.city_status("latium")
	t.check_eq(closed["policies"]["taverns"], "closed", "patrons see a closed premises")
	t.check(closed["daily_cost"] > before["daily_cost"], "closed commerce costs upkeep support")
	t.check(not game.city_action("latium", "close_taverns"), "repeated same policy is refused")
	t.check(game.city_action("latium", "reopen_taverns"), "reopen licences")
	var reopened := game.city_status("latium")
	t.check_eq(reopened["policies"]["taverns"], "open", "tavern can recover")
	t.check_eq(reopened["grievance"], before["grievance"], "rapid toggles cannot farm societal changes")
	t.check(reopened["treasury"] < before["treasury"], "licence toggles cannot mint money")


func test_city_and_campaign_tax_views_share_one_policy(t) -> void:
	var game := _game()
	t.check(game.city_action("latium", "tax_low"), "set taxes in curia")
	t.check_eq(game.state["settlements"]["latium"]["tax_level"], "low", "curia changes real settlement tax")
	t.check(game.set_tax_level("latium", "very_high"), "existing campaign tax action remains valid")
	t.check_eq(game.city_status("latium")["policies"]["tax"], "very_high", "city reads changes from campaign")
	t.check(game.city_advance_day("latium"), "all existing tax levels are supported")


func test_mid_project_save_replays_identical_future_days(t) -> void:
	var game := _game()
	game.city_action("latium", "grain_relief")
	game.city_action("latium", "repair_streets")
	game.city_action("latium", "clean_water")
	for id in ["improve_tavern", "improve_barracks", "improve_market", "improve_curia"]:
		game.city_action("latium", id)
	game.city_action("latium", "tax_low")
	game.city_advance_day("latium")
	var replay := _game()
	replay.state = SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not replay.state.is_empty(), "mid-project state passes save boundary")
	NewGame.ensure_state_keys(replay.state, replay.data)
	for day in range(7):
		game.city_advance_day("latium")
		replay.city_advance_day("latium")
	t.check_eq(JSON.stringify(JSON.parse_string(JSON.stringify(replay.state))),
		JSON.stringify(JSON.parse_string(JSON.stringify(game.state))),
		"quantized stocks and project timers replay identically after normalizing JSON number types")
	t.check_eq(replay.city_status("latium"), game.city_status("latium"), "loaded visual reports also match")


func test_old_saves_migrate_city_state_additively(t) -> void:
	var game := _game()
	game.state.erase("city_governance")
	var old := SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not old.is_empty(), "older saves need no city field")
	NewGame.ensure_state_keys(old, game.data)
	t.check_eq(old["city_governance"], {}, "migration adds an empty local ledger")
	game.state = old
	t.check(game.city_action("latium", "clean_water"), "old campaign can start a city project")
	t.check_eq(game.state["city_governance"].size(), 1, "only entered city's discrete config is created")


func test_malformed_city_saves_fail_before_migration(t) -> void:
	var game := _game()
	game.city_action("latium", "repair_streets")
	for corruption in ["collection", "policies", "day", "project", "grain", "completed_timer", "future_funding", "false_completion_date", "fractional_date"]:
		var broken: Dictionary = game.state.duplicate(true)
		match corruption:
			"collection": broken["city_governance"] = []
			"policies": broken["city_governance"]["latium"]["policies"] = "heavy"
			"day": broken["city_governance"]["latium"]["day"] = 1.5
			"project": broken["city_governance"]["latium"]["projects"]["repair_streets"] = []
			"grain": broken["city_governance"]["latium"]["grain_days"] = -1
			"completed_timer": broken["city_governance"]["latium"]["projects"]["repair_streets"]["completed"] = true
			"future_funding": broken["city_governance"]["latium"]["projects"]["repair_streets"]["funded_day"] = 999
			"false_completion_date": broken["city_governance"]["latium"]["projects"]["repair_streets"]["completed_day"] = 1
			"fractional_date": broken["city_governance"]["latium"]["projects"]["repair_streets"]["funded_day"] = 0.5
		t.check(SaveGame.from_json(SaveGame.to_json(broken)).is_empty(), "reject malformed city " + corruption)


func test_retaken_ownership_is_checked_even_after_city_initialization(t) -> void:
	var game := _game()
	game.city_action("latium", "repair_streets")
	game.state["settlements"]["latium"]["owner"] = "julii"
	var before := JSON.stringify(game.state)
	t.check(not game.city_action("latium", "tax_high"), "former governor cannot issue orders")
	t.check(not game.city_advance_day("latium"), "former governor cannot advance new owner's civic economy")
	t.check_eq(JSON.stringify(game.state), before, "ownership loss cannot redirect costs")


func test_building_dossiers_are_pure_complete_and_do_not_alias_content(t) -> void:
	var game := _game()
	var before := JSON.stringify(game.state)
	var content_before := JSON.stringify(game.data.city_governance)
	for site in ["forum", "fountain", "tavern", "barracks", "market", "curia"]:
		var dossier := RomaCityRules.building_info(game.data, game.state, "latium", site)
		t.check(dossier["available"], "modeled site has a dossier")
		t.check_eq(dossier["stage"], "current", "unfunded site shows its original condition")
		t.check_eq(dossier["evolution"].size(), 3, "evolution describes current, construction and improved stages")
		t.check(dossier["project"]["cost"] > 0 and dossier["project"]["days"] > 0 and dossier["project"]["maintenance"] > 0,
			"dossier exposes payment, delay and recurring upkeep before purchase")
		for action in dossier["actions"]:
			t.check_eq(action["site"], site, "context menu contains only this site's commands")
		dossier["evolution"][0]["key"] = "corrupt"
		dossier["project"]["cost"] = -1000
		dossier["actions"].clear()
		dossier["effects"]["grievance"][0]["value"] = -1000
	t.check_eq(JSON.stringify(game.state), before, "inspecting and editing returned dossiers never changes engine state")
	t.check_eq(JSON.stringify(game.data.city_governance), content_before, "dossiers do not expose mutable profile aliases")
	t.check_eq(RomaCityRules.building_info(game.data, game.state, "latium", "missing")["reason"], "unknown_site", "unknown site is safely refused")
	t.check_eq(RomaCityRules.building_info(game.data, game.state, "campania", "tavern")["reason"], "unauthorized", "foreign city dossiers remain inaccessible")


func test_building_improvements_charge_once_then_complete_with_paid_daily_effects(t) -> void:
	for site in ["tavern", "barracks", "market", "curia"]:
		var game := _game()
		var base := game.city_status("latium")
		var rules: Dictionary = game.data.balance["city"]
		var id: String = "improve_" + site
		t.check(game.city_action("latium", id), "building improvement can be commissioned")
		var funded := RomaCityRules.building_info(game.data, game.state, "latium", site)
		t.check_eq(funded["stage"], "construction", "construction starts only after an explicit order")
		t.check_eq(funded["project"]["funded_day"], 1, "funded date is recorded")
		t.check_eq(funded["project"]["completion_day"], 1 + int(rules["project_days"][id]), "completion schedule is shown before waiting")
		t.check_eq(game.city_status("latium")["treasury"], int(base["treasury"]) - int(rules["action_costs"][id]), "full capital cost paid once")
		var before := JSON.stringify(game.state)
		t.check(not game.city_action("latium", id), "stale enabled menu cannot pay for active project twice")
		t.check_eq(JSON.stringify(game.state), before, "revalidation refuses stale project atomically")
		for day in range(int(rules["project_days"][id])):
			t.check(game.city_advance_day("latium"), "funded day advances construction")
		var completed := RomaCityRules.building_info(game.data, game.state, "latium", site)
		var report := game.city_status("latium")
		t.check_eq(completed["stage"], "improved", "all promised days produce improved site")
		t.check_eq(completed["project"]["completion_day"], report["day"], "actual completion date retained")
		t.check_eq(report["daily_cost"], int(base["daily_cost"]) + int(rules["project_maintenance"][id]), "completed service needs recurring upkeep")
		for stock in ["grievance", "legitimacy"]:
			var actual := 0.0
			for factor in report["flows"][stock]:
				if factor["label"] == id:
					actual += float(factor["value"])
			t.check_near(actual, float(rules["project_effects"][id][stock]), 0.0001, "completed project has an inspectable civic stock effect")
		t.check(not game.city_action("latium", id), "completed building improvement cannot be bought again")
		t.check_eq(game.state["rng_state"], _game().state["rng_state"], "construction and upkeep consume no randomness")


func test_unaffordable_building_order_and_unpaid_construction_day_are_atomic(t) -> void:
	var game := _game()
	game.state["factions"]["senate"]["treasury"] = 1
	var before := JSON.stringify(game.state)
	for id in ["improve_tavern", "improve_barracks", "improve_market", "improve_curia"]:
		t.check(not game.city_action("latium", id), "unaffordable improvements fail")
	t.check_eq(JSON.stringify(game.state), before, "unaffordable orders neither create projects nor charge partial payment")
	game.state["factions"]["senate"]["treasury"] = 1000
	game.city_action("latium", "improve_market")
	game.state["factions"]["senate"]["treasury"] = 0
	before = JSON.stringify(game.state)
	t.check(not game.city_advance_day("latium"), "a day requiring civic upkeep cannot pass without funds")
	t.check_eq(JSON.stringify(game.state), before, "unpaid civic day cannot finish construction or move social stocks")


func test_first_phase_city_save_migrates_without_resetting_running_works(t) -> void:
	var game := _game()
	game.city_action("latium", "clean_water")
	game.city_advance_day("latium")
	var first_phase: Dictionary = game.state.duplicate(true)
	var city: Dictionary = first_phase["city_governance"]["latium"]
	for id in ["improve_tavern", "improve_barracks", "improve_market", "improve_curia"]:
		city["projects"].erase(id)
	for project in city["projects"].values():
		project.erase("funded_day")
		project.erase("completed_day")
	var loaded := SaveGame.from_json(SaveGame.to_json(first_phase))
	t.check(not loaded.is_empty(), "first phase city saves retain compatibility")
	game.state = loaded
	var before := JSON.stringify(game.state)
	var dossier := RomaCityRules.building_info(game.data, game.state, "latium", "tavern")
	t.check_eq(dossier["stage"], "current", "pure readers tolerate project absent from old save")
	t.check_eq(JSON.stringify(game.state), before, "querying old saves does not implicitly migrate them")
	NewGame.ensure_state_keys(game.state, game.data)
	var projects: Dictionary = game.state["city_governance"]["latium"]["projects"]
	t.check_eq(projects.size(), game.data.balance["city"]["project_days"].size(), "migration explicitly creates every expected project key")
	t.check_eq(projects["clean_water"]["remaining"], 3, "old active project keeps remaining work")
	t.check_eq(projects["clean_water"]["funded_day"], 1, "active legacy project's funding day inferred from its timer")
	game.city_action("latium", "improve_tavern")
	var replay := _game()
	replay.state = SaveGame.from_json(SaveGame.to_json(game.state))
	NewGame.ensure_state_keys(replay.state, replay.data)
	for day in range(5):
		game.city_advance_day("latium")
		replay.city_advance_day("latium")
	t.check_eq(game.city_status("latium"), replay.city_status("latium"), "mid-construction old-save migration replays identical future effects and dates")
	t.check_eq(RomaCityRules.building_info(game.data, game.state, "latium", "tavern"),
		RomaCityRules.building_info(replay.data, replay.state, "latium", "tavern"), "reloaded building dossier keeps completion history")


func _finish_project(game: Game, id: String) -> void:
	game.city_action("latium", id)
	for day in range(int(game.data.balance["city"]["project_days"][id])):
		game.city_advance_day("latium")


func _same_snapshot(t, expected: Dictionary, actual: Dictionary, message: String) -> void:
	for key in expected:
		t.check_eq(actual[key], expected[key], message + " " + key)


func test_action_forecasts_match_actual_order_and_day_without_mutation(t) -> void:
	var catalogue := _game()
	for action in catalogue.data.city_governance["actions"]:
		var game := _game()
		if action.get("requires_project", "") != "":
			_finish_project(game, "improve_barracks")
			if action["id"] == "equip_maniples":
				_finish_project(game, "drill_maniples")
		var before := JSON.stringify(game.state)
		var content := JSON.stringify(game.data.balance)
		var forecast := game.city_action_forecast("latium", action["id"])
		t.check_eq(JSON.stringify(game.state), before, "preview cannot mutate state, reports, or RNG")
		t.check_eq(JSON.stringify(game.data.balance), content, "preview cannot modify balance")
		if not forecast["available"]:
			t.check(not game.city_action("latium", action["id"]), "unavailable preview matches execution")
			continue
		t.check(game.city_action("latium", action["id"]), "quoted order executes")
		_same_snapshot(t, forecast["immediate"], game.city_status("latium"), "actual immediate outcome matches forecast")
		t.check(game.city_advance_day("latium"), "quoted civic day executes")
		_same_snapshot(t, forecast["next_day"], game.city_status("latium"), "actual next-day outcome matches forecast")
		t.check_eq(game.city_status("latium")["last_day_report"]["events"], forecast["events"], "forecast events match actual events")


func test_forecast_distinguishes_affordable_order_from_unaffordable_next_day(t) -> void:
	var game := _game()
	game.state["factions"]["senate"]["treasury"] = int(game.data.balance["city"]["action_costs"]["grain_relief"])
	var before := JSON.stringify(game.state)
	var quote := game.city_action_forecast("latium", "grain_relief")
	t.check(quote["available"], "the order itself can be funded")
	t.check(not quote["next_day_available"], "remaining budget cannot pay daily upkeep")
	t.check_eq(quote["next_day_reason"], "insufficient_funds", "UI receives the exact next-day refusal")
	t.check_eq(quote["next_day"], {}, "unfunded day has no invented result")
	t.check_eq(JSON.stringify(game.state), before, "even a failed predicted day remains pure")
	t.check(not game.city_action_forecast("campania", "grain_relief")["available"], "foreign city forecast is inaccessible")


func test_daily_report_records_orders_actual_deltas_and_expiry_once(t) -> void:
	var game := _game()
	game.city_action("latium", "grain_relief")
	game.city_action("latium", "close_taverns")
	game.city_action("latium", "reopen_taverns")
	game.city_action("latium", "close_taverns")
	var pending: Array = game.city_status("latium")["pending_orders"]
	t.check_eq(pending.size(), 3, "repeat orders aggregate by authored action rather than growing an unbounded log")
	var prediction := game.city_day_forecast("latium")
	game.city_advance_day("latium")
	var report: Dictionary = game.city_status("latium")["last_day_report"]
	var expected_cost := int(game.data.balance["city"]["action_costs"]["grain_relief"]) + 3 * int(game.data.balance["city"]["action_costs"]["close_taverns"])
	t.check_eq(report["order_cost"], expected_cost, "capital orders are recorded separately from daily upkeep")
	t.check_eq(report["treasury_spent"], prediction["immediate"]["daily_cost"], "report daily payment matches treasury change")
	t.check_eq(game.city_status("latium")["pending_orders"], [], "orders are consumed into one daily report")
	_same_snapshot(t, prediction["next_day_delta"], report["deltas"], "actual report deltas match promised changes")
	var before := JSON.stringify(game.state)
	report["orders_issued"].clear()
	report["flows"]["grievance"].clear()
	report["before"]["treasury"] = -1000
	t.check_eq(JSON.stringify(game.state), before, "report consumers cannot alter persistent history")
	for day in range(int(game.data.balance["city"]["grain_duration_days"]) - 1):
		game.city_advance_day("latium")
	var kinds: Array = []
	for event in game.city_status("latium")["last_day_report"]["events"]:
		kinds.append(event["kind"])
	t.check(kinds.has("relief_expired"), "last ration causes a concrete after-action event")
	game.city_advance_day("latium")
	t.check_eq(game.city_status("latium")["last_day_report"]["events"], [], "expired relief is not announced repeatedly")


func test_workforce_changes_actual_project_rate_cost_and_named_social_flows(t) -> void:
	var paid := _game()
	var forced := _game()
	for game in [paid, forced]:
		game.city_action("latium", "repair_streets")
	paid.city_action("latium", "workforce_paid")
	forced.city_action("latium", "workforce_requisition")
	var paid_status := paid.city_status("latium")
	var forced_status := forced.city_status("latium")
	t.check(paid_status["daily_cost"] > forced_status["daily_cost"], "voluntary extra crews cost more than compulsory labor")
	var dossier := paid.city_building_info("latium", "forum")
	t.check_eq(dossier["project"]["estimated_days_remaining"], 2, "three ordinary work days need two days with extra crews")
	t.check_eq(dossier["project"]["completion_day"], 3, "completion estimate uses actual rate")
	paid.city_advance_day("latium")
	forced.city_advance_day("latium")
	t.check_eq(paid.city_status("latium")["projects"]["repair_streets"]["remaining"], 1, "two units of real work complete")
	t.check(forced.city_status("latium")["grievance"] > paid.city_status("latium")["grievance"], "requisition builds resentment")
	t.check(forced.city_status("latium")["legitimacy"] < paid.city_status("latium")["legitimacy"], "fair wages protect consent")
	paid.city_advance_day("latium")
	t.check(paid.city_status("latium")["projects"]["repair_streets"]["completed"], "extra work completes on forecast day")
	var before := JSON.stringify(forced.state)
	forced.city_action_forecast("latium", "workforce_normal")
	t.check_eq(JSON.stringify(forced.state), before, "labor-policy forecasts do not silently apply their effects")


func test_military_programs_gate_real_training_equipment_and_campaign_recruits(t) -> void:
	var game := _game()
	var initial: Array = game.city_troop_status("latium")["garrison"]
	var initial_profile := game.recruit_profile("latium", "roman_hastati")
	var before := JSON.stringify(game.state)
	t.check(not game.city_action("latium", "drill_maniples"), "drill requires restored barracks")
	t.check(not game.city_action("latium", "equip_maniples"), "equipment requires drill programme")
	t.check_eq(JSON.stringify(game.state), before, "missing military prerequisites cannot spend money")
	_finish_project(game, "improve_barracks")
	game.city_action("latium", "drill_maniples")
	game.city_action("latium", "workforce_paid")
	game.city_advance_day("latium")
	t.check_eq(game.city_status("latium")["projects"]["drill_maniples"]["remaining"], 2, "extra labor does not accelerate soldiers' training")
	game.city_advance_day("latium")
	game.city_advance_day("latium")
	var trained: Array = game.city_troop_status("latium")["garrison"]
	for i in range(initial.size()):
		t.check_eq(trained[i]["experience"], int(initial[i]["experience"]) + 1, "training advances real standing garrison experience")
	t.check_eq(game.recruit_profile("latium", "roman_hastati")["experience"], int(initial_profile["experience"]) + 1, "campaign recruit profile includes completed training")
	_finish_project(game, "equip_maniples")
	var equipped: Array = game.city_troop_status("latium")["garrison"]
	var profile := game.recruit_profile("latium", "roman_hastati")
	for unit in equipped:
		t.check(unit["weapon"] >= profile["weapon"] and unit["armor"] >= profile["armor"], "equipment stamps real unit kit used by BattleResolver")
	t.check(profile["weapon"] > initial_profile["weapon"] and profile["armor"] > initial_profile["armor"], "future recruits receive the improved campaign equipment standard")
	t.check(game.city_queue_unit("latium", "roman_hastati"), "campaign entry delegates to real recruitment queue")
	var queued: Array = game.state["settlements"]["latium"]["recruitment_queue"].duplicate(true)
	game.city_advance_day("latium")
	t.check_eq(game.state["settlements"]["latium"]["recruitment_queue"], queued, "a civic day cannot also advance the seasonal recruitment clock")
	RecruitmentRules.advance_queues(game.data, game.state, "latium")
	var recruited: Dictionary = game.state["settlements"]["latium"]["garrison"].back()
	t.check_eq(recruited["experience"], profile["experience"], "actual recruited unit inherits city training")
	t.check_eq(recruited["weapon"], profile["weapon"], "actual recruited unit inherits city weapons")
	t.check_eq(recruited["armor"], profile["armor"], "actual recruited unit inherits city armor")
	t.check_eq(game.state["rng_state"], _game().state["rng_state"], "military programs and recruitment consume no RNG")


func test_siege_pauses_programs_and_revalidates_recruitment_without_spending(t) -> void:
	var game := _game()
	_finish_project(game, "improve_barracks")
	game.city_action("latium", "drill_maniples")
	game.state["settlements"]["latium"]["siege"] = {"army": "test", "turns": 0}
	var before := JSON.stringify(game.state)
	t.check(not game.city_queue_unit("latium", "roman_hastati"), "siege blocks existing recruitment seam")
	t.check(not game.city_action("latium", "equip_maniples"), "military orders blocked under siege")
	t.check_eq(JSON.stringify(game.state), before, "siege refusal spends nothing")
	var predicted := game.city_day_forecast("latium")
	game.city_advance_day("latium")
	t.check_eq(game.city_status("latium")["projects"]["drill_maniples"]["remaining"], 3, "a besieged program does not advance")
	t.check_eq(game.city_status("latium")["last_day_report"]["events"], predicted["events"], "siege delay appears in accurate forecast and aftermath")


func test_phase_two_saves_migrate_reports_workforce_and_military_additively(t) -> void:
	var game := _game()
	game.city_action("latium", "clean_water")
	game.city_advance_day("latium")
	var city: Dictionary = game.state["city_governance"]["latium"]
	city.erase("last_day_report")
	city.erase("pending_orders")
	city["policies"].erase("workforce")
	city["projects"].erase("drill_maniples")
	city["projects"].erase("equip_maniples")
	var loaded := SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not loaded.is_empty(), "phase two saves pass additive save boundary")
	var before := JSON.stringify(loaded)
	var report := RomaCityRules.status(game.data, loaded, "latium")
	t.check_eq(report["last_day_report"], {}, "pure old-save reader has no invented history")
	t.check_eq(report["policies"]["workforce"], "normal", "pure old-save reader uses ordinary crews")
	t.check_eq(JSON.stringify(loaded), before, "pure reads cannot apply migration")
	NewGame.ensure_state_keys(loaded, game.data)
	t.check(loaded["city_governance"]["latium"].has("last_day_report"), "migration explicitly adds daily report")
	t.check_eq(loaded["city_governance"]["latium"]["pending_orders"], [], "migration never invents unrecorded orders")
	t.check_eq(loaded["city_governance"]["latium"]["projects"]["clean_water"]["remaining"], 3, "migration preserves unfinished old works")


func test_report_and_program_save_replay_and_malformed_history_boundary(t) -> void:
	var game := _game()
	_finish_project(game, "improve_barracks")
	game.city_action("latium", "drill_maniples")
	game.city_action("latium", "grain_relief")
	game.city_action("latium", "workforce_requisition")
	game.city_advance_day("latium")
	var replay := _game()
	replay.state = SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not replay.state.is_empty(), "active program, pending orders and report survive save boundary")
	NewGame.ensure_state_keys(replay.state, replay.data)
	for day in range(4):
		game.city_advance_day("latium")
		replay.city_advance_day("latium")
	t.check_eq(game.city_status("latium"), replay.city_status("latium"), "saved daily reports and quantized flows replay identically")
	t.check_eq(game.city_troop_status("latium"), replay.city_troop_status("latium"), "actual troops replay identically")
	for corruption in ["workforce", "orders", "report", "date", "flow", "event", "cost"]:
		var broken: Dictionary = game.state.duplicate(true)
		var city: Dictionary = broken["city_governance"]["latium"]
		match corruption:
			"workforce": city["policies"]["workforce"] = "invented"
			"orders": city["pending_orders"] = [{"id": "grain_relief", "count": -1, "cost": 0}]
			"report": city["last_day_report"] = []
			"date": city["last_day_report"]["day_after"] = 999
			"flow": city["last_day_report"]["flows"]["grievance"] = "not_factors"
			"event": city["last_day_report"]["events"] = [{"kind": "troops_trained", "params": {"count": -5}}]
			"cost": city["last_day_report"]["order_cost"] = 999
		t.check(SaveGame.from_json(SaveGame.to_json(broken)).is_empty(), "malformed city report rejected before migration: " + corruption)
