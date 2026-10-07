extends SceneTree
var app
var ui
var results: Dictionary={}
func _initialize() -> void:call_deferred("run")
func measure(id: String,callback: Callable) -> void:
	var start: int=Time.get_ticks_usec();callback.call();var finished: int=Time.get_ticks_usec()
	await process_frame;RenderingServer.force_draw(true)
	await process_frame;RenderingServer.force_draw(true)
	results[id]={"callback_us":finished-start,"ready_us":Time.get_ticks_usec()-start}
func run() -> void:
	root.size=Vector2i(1600,1000);app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame;ui=app.visual_commands
	await measure("open",ui.begin)
	await measure("select_place",ui.select_place.bind("workroom"))
	await measure("preview_first",ui.show_project.bind("land_adapt_workroom"))
	await measure("preview_cached",ui.show_project.bind("land_adapt_workroom"))
	await measure("compare_growth",ui.show_overlay.bind("growth"))
	await measure("inspect",ui.inspect)
	await measure("prepare_order",ui.execute.bind({"kind":"living_order","id":"prepare","value":1}))
	await measure("commission",ui.execute.bind({"kind":"commission","id":"land_adapt_workroom"}))
	await measure("priority",ui.execute.bind({"kind":"asset_project","id":"land_adapt_workroom","crew":4,"priority":1,"paused":false}))
	await measure("completion_season",ui.advance)
	await measure("ordinary_season",ui.advance)
	await measure("watch_priority",ui.execute.bind({"kind":"asset_principle","id":"watch","value":1}))
	ui.begin();ui.execute({"kind":"living_order","id":"prepare","value":1})
	await measure("fresh_living_season",ui.advance)
	print("VISUAL INTERACTION PROFILE ",JSON.stringify(results));quit()
