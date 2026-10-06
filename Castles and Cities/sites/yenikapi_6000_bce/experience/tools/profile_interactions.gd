extends SceneTree
var app
var results: Dictionary={}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000)
	app=load("res://main.tscn").instantiate();root.add_child(app)
	await process_frame
	var p=app.campaign
	var start: int=Time.get_ticks_msec()
	p.asset_panel.begin()
	results.open_assets_ms=Time.get_ticks_msec()-start
	measure("reserve",{"kind":"asset_principle","id":"reserve","value":2})
	p.state=preload("res://tools/asset_driver.gd").at_season(p.rules,11);app.show_campaign(p.state,p.rules);p.refresh()
	measure("grown_watch",{"kind":"asset_principle","id":"watch","value":0})
	measure("grown_reserve",{"kind":"asset_principle","id":"reserve","value":2})
	p.state=preload("res://tools/land_driver.gd").initial(p.rules);app.show_campaign(p.state,p.rules);p.refresh()
	measure("commission",{"kind":"commission","id":"land_adapt_workroom"})
	measure("priority",{"kind":"asset_project","id":"land_adapt_workroom","priority":1,"crew":4,"paused":false})
	measure("compare",{"kind":"land_inspect","id":"north_west"})
	start=Time.get_ticks_msec();p.resolve_season();results.season_ms=Time.get_ticks_msec()-start
	print("INTERACTION PROFILE ",JSON.stringify(results))
	quit()
func measure(id: String,action: Dictionary) -> void:
	var p=app.campaign
	var start: int=Time.get_ticks_usec()
	var response: Dictionary=p.rules.command(p.state,action)
	var command_us: int=Time.get_ticks_usec()-start
	assert(response.has("state"));p.state=response.state
	start=Time.get_ticks_usec();app.show_campaign(p.state,p.rules);var world_us: int=Time.get_ticks_usec()-start
	start=Time.get_ticks_usec();p.refresh();var ui_us: int=Time.get_ticks_usec()-start
	results[id]={"command_us":command_us,"world_us":world_us,"ui_us":ui_us,"life":app.campaign_view.life.last_refresh_profile}
