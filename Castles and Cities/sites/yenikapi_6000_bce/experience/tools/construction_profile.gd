extends "res://tools/visual_profile.gd"
func run() -> void:
	root.size=Vector2i(1600,1000);app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame;ui=app.visual_commands
	ui.begin()
	await measure("central_oversight",ui.show_overlay.bind("oversight"))
	await measure("enter_room",ui.enter_room)
	await measure("select_board_plan",ui.room().choose.bind("care_shelter"))
	await measure("enlarge_easel",ui.show_project.bind(ui.room().selected))
	await measure("compare_project",ui.show_project.bind("shared_store"))
	ui.leave_room();ui.execute({"kind":"commission","id":"care_shelter"})
	await measure("crew_limit",ui.execute.bind({"kind":"asset_project","id":"care_shelter","crew":1,"priority":2,"paused":false}))
	await measure("priority",ui.execute.bind({"kind":"asset_project","id":"care_shelter","crew":1,"priority":1,"paused":false}))
	await measure("pause",ui.execute.bind({"kind":"asset_project","id":"care_shelter","crew":1,"priority":1,"paused":true}))
	await measure("resume",ui.execute.bind({"kind":"asset_project","id":"care_shelter","crew":1,"priority":1,"paused":false}))
	var site: Dictionary=ui.construction().sites.care_shelter
	var target: Vector3=site.at+Basis(Vector3.UP,float(site.yaw))*Vector3(site.half.x-.28,.22,-site.half.y+.8)
	var origin: Vector3=target+Vector3(5,6,9)
	await measure("select_site",ui.pick.bind(origin,(target-origin).normalized()))
	await measure("construction_season",ui.advance)
	results.construction_routes=app.campaign_view.life.last_refresh_profile.duplicate()
	for i in range(10):
		var d: Dictionary=ui.projects.describe(app.campaign.state,app.campaign.rules,"care_shelter")
		if d.progress+d.work>=d.total:break
		ui.advance();await process_frame
	var before: int=app.world.get_instance_id()
	await measure("new_building_completion",ui.advance)
	results.completion_routes=app.campaign_view.life.last_refresh_profile.duplicate()
	results.world_reused=before==app.world.get_instance_id()
	results.building_completed=app.campaign.rules.has_project(app.campaign.state,"care_shelter")
	ui.execute({"kind":"commission","id":"land_adapt_workroom"});ui.execute({"kind":"asset_project","id":"land_adapt_workroom","crew":4,"priority":1,"paused":false})
	await measure("adaptation_completion",ui.advance)
	await measure("ordinary_season",ui.advance)
	print("CONSTRUCTION INTERACTION PROFILE ",JSON.stringify(results));quit()
