extends "res://tools/visual_profile.gd"
const Driver=preload("res://tools/town_driver.gd")
func run() -> void:
	root.size=Vector2i(1280,800);app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame;ui=app.visual_commands
	ui.begin()
	var p=app.campaign
	var s: Dictionary=Driver.initial(p.rules)
	for i in range(300):
		var action: Dictionary=Driver.town_action(p.rules,s,true)
		if action.get("id")=="town_civic":break
		s=p.rules.advance(s).state if action.is_empty() else p.rules.command(s,action).state
	p.state=s;app.show_campaign(s,p.rules);ui.open();await process_frame
	await measure("lifecycle_open",ui.show_overlay.bind("lifecycle"))
	await measure("lifecycle_reopen",ui.show_overlay.bind("lifecycle"))
	await measure("commission",ui.execute.bind({"kind":"commission","id":"town_civic"}))
	results.commission_routes=app.campaign_view.life.last_refresh_profile.duplicate()
	await measure("seasonal_refresh",ui.advance)
	results.season_routes=app.campaign_view.life.last_refresh_profile.duplicate()
	for i in range(20):
		var d: Dictionary=ui.projects.describe(p.state,p.rules,"town_civic")
		if d.progress+d.work>=d.total:break
		ui.advance();await process_frame
	await measure("civic_completion",ui.advance)
	results.completion_routes=app.campaign_view.life.last_refresh_profile.duplicate()
	await measure("unchanged_refresh",app.show_campaign.bind(p.state,p.rules))
	results.completed=p.rules.has_project(p.state,"town_civic")
	print("TOWN PROFILE ",JSON.stringify(results));quit(0 if results.completed else 1)
