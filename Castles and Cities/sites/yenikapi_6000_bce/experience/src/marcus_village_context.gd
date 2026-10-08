extends RefCounted
## Village-specific navigation and visible facts for the shared Marcus panel.
const ProjectPresentation=preload("project_presentation.gd")
var app
var content: Dictionary
var lessons: Array
var preference_path: String="user://marcus_preferences.cfg"
var copy: Dictionary

func _init(owner_app) -> void:
	app=owner_app
	content=JSON.parse_string(FileAccess.get_file_as_string("res://data/marcus.json"))
	copy=content
	lessons=app.visual_commands.copy.lessons

func w(id: String) -> String:
	return String(content.ui.get(id,id))

func prepare_open() -> void:
	app.hud.show()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	app._look_drag=false

func navigation_blocked(_lesson: Dictionary = {}) -> String:
	if app.campaign.state.is_empty() or not app.campaign_mode:return "active_village_needed"
	if app.defense_panel.active_ui or app.campaign.rules.defense.locked(app.campaign.state):return "battle_navigation_blocked"
	return ""

func navigate(lesson: Dictionary,index: int) -> void:
	app.visual_commands.open()
	app.visual_commands.lesson=index
	app.visual_commands.guide_destination(lesson)

func season_briefing() -> Dictionary:
	return {}

func _select_fields(source: Dictionary,keys: Array) -> Dictionary:
	var result: Dictionary={}
	for key in keys:
		if source.has(key):result[key]=source[key]
	return result

func _screen_snapshot() -> Dictionary:
	var p=app.campaign
	if app.defense_panel.active_ui:
		return {"surface":"defense","phase":app.defense_panel.phase}
	if p.visible:
		var ledger: Dictionary={"surface":"village_ledger"}
		if is_instance_valid(p.tabs) and p.tabs.current_tab>=0:
			ledger.tab=p.tabs.current_tab
			ledger.title=p.tabs.get_tab_title(p.tabs.current_tab)
		return ledger
	if not app.campaign_mode:return {"surface":"reference_village"}
	if app.visual_commands.visible:
		return {"surface":"village_commands","place":app.visual_commands.selected,"page":app.visual_commands.page,"overlay":app.visual_commands.overlay,"detail":_select_fields(app.visual_commands.detail,["kind","id"])}
	return {"surface":"village_walk"}

func context_snapshot() -> Dictionary:
	## Build a bounded, explicit read model at the player's request. In particular,
	## forecast.incidents and quote.state contain undiscovered/candidate state.
	## Never serialize those, full saves, tactical rosters or citizen histories.
	var p=app.campaign
	var rules=p.rules
	var state: Dictionary=p.state
	var result: Dictionary={
		"experience":"yenikapi_early_settlement",
		"mode":w("village_mode" if app.campaign_mode else "reference_mode"),
		"fiction":copy.fiction_note,
		"planned_story":copy.future_note,
		"screen":_screen_snapshot(),
		"guide":{}
	}
	if state.is_empty() or not app.campaign_mode:return result
	result.calendar={"turn":int(state.turn),"year":1+int(state.turn)/4,"season":p.copy.seasons[int(state.turn)%4]}
	result.village=_select_fields(state,["food","wood","wellbeing","cooperation","security","role"])
	result.village.population=rules.people(state).size()
	result.village.available_adults=rules.people(state,true).size()
	result.village.housing=rules.capacity(state)
	result.village.storage=rules.storage(state)
	result.chapters={"households":rules.households.active(state),"assets":rules.assets.active(state),"land":rules.land.active(state),"living":rules.living.active(state),"incidents":rules.incidents.active(state),"lifecycle":rules.lifecycle.active(state),"town":rules.lifecycle.town_active(state),"warfare":rules.warfare.active(state)}
	# Detached host status exposes the battle clock without hidden contacts.
	if app.defense_panel.host!=null:
		result.battle=_select_fields(app.defense_panel.host.status(),["phase","tick","quick"])
		return result
	var forecast: Dictionary=rules.forecast(state)
	result.forecast=_select_fields(forecast,["population","plan","gathered","used","unfed","overflow","spoil","food","food_delta","covered","wood","work","stocks"])
	result.forecast.factors={}
	for key in forecast.factors:
		result.forecast.factors[key]=[]
		for factor in forecast.factors[key]:result.forecast.factors[key].append({"name":p.copy.factor_names.get(factor.id,factor.id),"value":factor.value})
	if rules.assets.active(state):
		result.staffing=[]
		for request in forecast.assets.requests.slice(0,int(copy.limits.context_requests)):
			result.staffing.append(_select_fields(request,["id","asset","wanted","filled","reason"]))
		result.principles={}
		for spec in p.asset_panel.copy.principles:
			var index: int=rules.assets.principle(state,spec.id)
			result.principles[spec.label]=spec.options[index]
	if rules.living.active(state):result.living=_select_fields(state.living,["blanks","kits","prepare","training","repair","area","patrol","cooperate"])
	var presentation=ProjectPresentation.new()
	result.projects=[]
	var ids: Array=presentation.ids(state,rules)
	var detail: Dictionary=result.screen.get("detail",{})
	if detail.get("kind","")=="project" and detail.get("id","") in ids:
		ids.erase(detail.id)
		ids.push_front(detail.id)
	for id in ids.slice(0,int(copy.limits.context_projects)):
		var description: Dictionary=presentation.describe(state,rules,id,forecast)
		var project: Dictionary=_select_fields(description,["id","status","cause","cost_wood","cost_blanks","progress","total","remaining","crew","limit","work","paused","requires","benefit"])
		project.title=rules.projects[id].title
		project.refusal=p.reason(description.refusal) if description.refusal!="" else ""
		result.projects.append(project)
	if rules.lifecycle.active(state):
		var lifecycle: Dictionary=rules.lifecycle.status(state,rules)
		result.lifecycle=_select_fields(lifecycle,["stage","stage_name","project","ready","qualifying","seasons","required_seasons","upkeep"])
		result.lifecycle.factors=[]
		for factor in lifecycle.factors:
			var item: Dictionary=_select_fields(factor,["id","current","required","met","suspended","params","alternatives"])
			item.name=rules.lifecycle.content.factors.get(factor.id,rules.projects.get(factor.id,{}).get("title",factor.id))
			result.lifecycle.factors.append(item)
	if forecast.has("town"):result.town=_select_fields(forecast.town,["wanted","filled","condition","required","civic","maintained","service","service_wanted","prepared","saved"])
	var incident: Dictionary=rules.incidents.current(state)
	if not incident.is_empty() and int(incident.known)>=0:
		result.incident={"notice":p.incident_panel.notice(),"title":rules.incidents.specs[incident.id].title}
		if not incident.inspected.is_empty():result.incident.detail=rules.incidents.specs[incident.id].detail
	if not state.report.is_empty():result.last_season=_select_fields(state.report,["food","wood","gathered","used","unfed","overflow","spoil","losses","work"])
	return result
