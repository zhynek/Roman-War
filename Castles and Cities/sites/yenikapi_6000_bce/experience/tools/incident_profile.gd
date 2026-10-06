extends SceneTree
const Driver=preload("res://tools/incident_driver.gd")
var app
var results: Dictionary={}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign
	var start: int=Time.get_ticks_msec();p.incident_panel.begin();results.open_incidents_ms=Time.get_ticks_msec()-start
	p.state=Driver.at_season(p.rules,6,"underprepared");app.show_campaign(p.state,p.rules);p.refresh()
	measure("warning_inspection",{"kind":"incident_inspect","id":"north_wood"})
	start=Time.get_ticks_usec()
	for a in [{"kind":"commission","id":"incident_approach_prepare"},{"kind":"incident_restrict","enabled":true}]:p.rules.quote(p.state,a)
	results.compare_options_us=Time.get_ticks_usec()-start
	measure("response_commitment",{"kind":"commission","id":"incident_approach_prepare"})
	measure("watch_priority",{"kind":"asset_principle","id":"watch","value":1})
	measure("work_priority",{"kind":"living_order","id":"prepare","value":0})
	season("warning_season_ms");season("incident_season_ms")
	measure("recovery_commission",{"kind":"commission","id":"incident_approach_repair"})
	season("recovery_work_ms");season("recovery_completion_ms")
	start=Time.get_ticks_msec();app.campaign_view.life._routes.clear();app.campaign_view.life._signature="";app.show_campaign(p.state,p.rules);results.route_rebuild_ms=Time.get_ticks_msec()-start
	print("INCIDENT INTERACTION PROFILE ",JSON.stringify(results));quit()
func season(id: String) -> void:
	var start: int=Time.get_ticks_msec();app.campaign.resolve_season();results[id]=Time.get_ticks_msec()-start
func measure(id: String,a: Dictionary) -> void:
	var p=app.campaign;var start: int=Time.get_ticks_usec()
	var response: Dictionary=p.rules.command(p.state,a);var command_us: int=Time.get_ticks_usec()-start
	assert(response.has("state"));p.state=response.state
	start=Time.get_ticks_usec();app.show_campaign(p.state,p.rules);var world_us: int=Time.get_ticks_usec()-start
	start=Time.get_ticks_usec();p.refresh();var ui_us: int=Time.get_ticks_usec()-start
	results[id]={"command_us":command_us,"world_us":world_us,"ui_us":ui_us,"life":app.campaign_view.life.last_refresh_profile}
