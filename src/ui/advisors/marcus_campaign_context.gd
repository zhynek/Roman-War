extends RefCounted
## Read-only campaign adapter. No full saves, hidden rosters or raw journals
## leave this boundary. Navigation uses inspection entry points, never orders.
var session
var content: Dictionary
var lessons: Array
var preference_path := "user://marcus_campaign_preferences.cfg"
var _briefing: Dictionary = {}

func _init(owner_session) -> void:
	session = owner_session
	content = JSON.parse_string(FileAccess.get_file_as_string("res://data/marcus.json"))
	lessons = content.lessons
	capture_season()

func prepare_open() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(session.city):
		session.city._survey_dragging = false
		session.city.battle_panel._cancel_gesture()

func _battle_visible() -> bool:
	return session.active_view == "city" and is_instance_valid(session.city) and session.city.battle_panel.visible

func navigation_blocked(lesson: Dictionary = {}) -> String:
	if _battle_visible():return "battle_navigation_blocked"
	if CityBattleRules.locked(session.game.state):return "battle_navigation_blocked"
	if is_instance_valid(session.campaign):
		if session.campaign.turn_sequence.is_playing() or session.campaign.dispatch_panel.visible:
			return "presentation_navigation_blocked"
	if lesson.get("destination", "") == "city_ledger" and session.active_view != "city":
		return "city_view_needed"
	return ""

func navigate(lesson: Dictionary, _index: int) -> void:
	if navigation_blocked(lesson) != "":return
	var destination: String = lesson.destination
	if destination == "city_ledger":
		session.city.open_campaign_ledger()
		return
	session.show_campaign()
	var screen: CampaignScreen = session.campaign
	match destination:
		"dispatch": screen._show_dispatch()
		"orders": screen.show_controls()
		_:
			var capital: String = session.game.state.factions[session.game.state.player_faction].capital
			if not session.game.known_regions().has(capital):return
			screen._inspect_settlement(capital)
			screen.map_view.center_on(capital)
			if destination == "construction" and session.game.state.settlements.get(capital, {}).get("owner", "") == session.game.state.player_faction:
				screen.open_drawer()

func _fields(source: Dictionary, keys: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in keys:
		if source.has(key):result[key] = source[key]
	return result.duplicate(true)

func _screen() -> Dictionary:
	if session.active_view == "city":
		var city: RomaCityScreen = session.city
		return {"surface":"roma_city", "region":"latium", "site":city.selected_site,
			"building":city.selected_building, "drawer":city.drawer.visible,
			"governance_tab":city._govern_tab, "ledger":city.campaign_panel.visible,
			"ledger_tab":city.campaign_panel.tab, "daily_report":city.dawn.visible}
	var screen: CampaignScreen = session.campaign
	var result := {"surface":"campaign_map", "region":screen.map_view.selected_region,
		"force":screen.selected_force(), "drawer":screen.drawer_open,
		"drawer_tab":screen.drawer_tab, "planning_order":screen._planning_order,
		"turn_playback":screen.turn_sequence.is_playing(), "dispatch":screen.dispatch_panel.visible}
	for key in ["family_panel", "diplomacy_panel", "senate_panel", "knowledge_panel", "annals_panel"]:
		if screen.get(key).visible:result["panel"] = key
	return result

func context_snapshot() -> Dictionary:
	var result := {"experience":"roman_campaign", "fiction":content.fiction_note,
		"planned_story":content.future_note, "screen":_screen()}
	# A live tactical worker owns simulation access. Read only its detached,
	# already-presented snapshot; do not derive economy or visibility concurrently.
	if _battle_visible():
		result.battle = _fields(session.city.battle_panel.snapshot,
			["active", "phase", "paused", "elapsed_ms", "gate_integrity", "objective_progress", "practice"])
		result.scope = content.ui.battle_context_note
		return result
	var game: Game = session.game
	var player: String = game.state.player_faction
	result.calendar = _fields(game.state, ["turn", "year", "season"])
	result.faction = _fields(game.state.factions[player], ["treasury", "capital"])
	result.faction.id = player
	result.faction.name = game.data.factions[player].name
	var region: String = result.screen.get("region", "")
	var known: Dictionary = game.known_regions()
	if not known.has(region):result.screen.region = ""
	if known.has(region):
		result.selection = _settlement(region)
		if game.state.settlements.get(region, {}).get("owner", "") == player:
			result.selection.factors = {
				"public_order":_factors(game.order_breakdown(region)),
				"growth":_factors(game.growth_breakdown(region)),
				"income":_factors(game.income_breakdown(region))}
			result.selection.society = _fields(game.society_report(region),
				["level", "stale_turns", "unrest_state", "legitimacy", "grievance", "standing"])
			result.selection.tax_level = game.state.settlements[region].tax_level
	result.known_settlements = []
	var regions: Array = known.keys()
	regions.sort()
	for id in regions.slice(0,int(content.limits.context_settlements)):
		result.known_settlements.append(_settlement(id))
	result.known_settlements_omitted = maxi(0,regions.size()-result.known_settlements.size())
	result.observed_armies = []
	var visible: Dictionary = game.visible_armies()
	var ids: Array = visible.keys()
	ids.sort()
	var selected: String = result.screen.get("force", "")
	if selected in ids:
		ids.erase(selected)
		ids.push_front(selected)
	for id in ids.slice(0,int(content.limits.context_forces)):
		var army: Dictionary = game.state.armies[id]
		# Presence is visible; enemy roster, exact strength and commander stats
		# are deliberately not inferred from the engine's full force summary.
		var force := {"id":id, "owner":army.owner, "region":army.region}
		if army.owner == player:
			force.merge(_fields(game.force_summary(id), ["kind", "soldiers", "units", "upkeep", "movement_left", "movement_max", "forced_march", "besieging"]))
		result.observed_armies.append(force)
	result.observed_armies_omitted = maxi(0,ids.size()-result.observed_armies.size())
	if game.state.fleets.get(selected, {}).get("owner", "") == player:
		result.selected_fleet = _fields(game.force_summary(selected), ["id", "kind", "sea_zone", "units", "soldiers", "movement_left", "movement_max", "upkeep"])
	if session.active_view == "campaign" and game.state.armies.get(selected, {}).get("owner", "") == player:
		var screen: CampaignScreen = session.campaign
		var preview: Dictionary = {}
		if not screen._pinned_target.is_empty() and known.has(screen._pinned_target):
			preview = game.army_order_preview(selected,screen._pinned_target,screen._forced_order)
		else:preview = game.queued_march_preview(selected)
		result.order_preview = _fields(preview,["action", "from", "target", "forced", "cost", "turns", "blocked", "reason", "uncertain", "crossing"])
		result.order_preview.path = preview.get("path",[]).slice(0,24)
	result.last_resolved_season = season_briefing()
	return result

func _settlement(region: String) -> Dictionary:
	var game: Game = session.game
	var report: Dictionary = game.settlement_report(region)
	var result := {"region":region,"name":game.data.regions[region].get("settlement_name", region)}
	result.merge(_fields(report,["owner", "level", "population", "turn", "observed", "buildings", "construction"]))
	return result

func _factors(factors: Array) -> Array:
	var result: Array = []
	for factor in factors.slice(0,int(content.limits.context_factors)):
		result.append(_fields(factor,["label", "value"]))
	return result

func capture_season() -> bool:
	if _battle_visible():return false
	var game: Game = session.game
	var journal: Dictionary = game.state.get("journal", {})
	if not journal.has("turn") or int(journal.turn) <= 0 or int(journal.turn) != int(game.state.turn):
		_briefing = {}
		return true
	var lines: Array = []
	var eligible := 0
	for beat in game.day_beats():
		if not DispatchFormat.template_for(game.data,beat).get("in_dispatch",false):continue
		eligible += 1
		if lines.size() < int(content.limits.context_reports):
			lines.append(DispatchFormat.headline(game.data,game.state,beat))
	_briefing = {"turn":int(journal.turn),"date":DispatchFormat.date_line(game.state),
		"scope":"latest_resolved_season", "lines":lines,"omitted":maxi(0,eligible-lines.size())}
	return true

func season_briefing() -> Dictionary:
	return _briefing.duplicate(true)
