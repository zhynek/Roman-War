extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func run() -> void:
	var app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;var ui=app.visual_commands
	ui.begin()
	var starting: String=JSON.stringify(p.state)
	var all: Dictionary={}
	for place in ui.copy.assets:
		ui.select_place(place.id)
		check(ui.selected==place.id,"stable selected asset "+place.id)
		for id in ui.project_ids(place.id):
			check(p.rules.assets.project_assets[id]==place.id,"project belongs to place "+id);all[id]=true
			ui.show_project(id)
			check(JSON.stringify(p.state)==starting,"project preview is pure "+id)
		ui.choose_page("orders")
		check(JSON.stringify(p.state)==starting,"orders browsing is pure "+place.id)
	check(all.has("land_outer_west") and all.has("living_watch_kits") and all.has("shared_store"),"housing and equipment reachable through buildings")
	ui.select_place("workroom");ui.show_order("living","prepare")
	ui.execute({"kind":"living_order","id":"prepare","value":ui.copy.living_orders[1].values[1]})
	check(p.state.living.prepare is int,"authored numeric choices canonicalized before commands")
	check(ui.copy.living_orders[1].values.find(p.state.living.prepare)==1,"displayed preparation option matches canonical state")
	check(ui.preview_mesh("land_outer_west",false)==null,"unbuilt site never previews another household as its current building")
	check(ui.preview_mesh("shared_store",false)==app.world.object_nodes.yk_store_01.mesh,"current store uses exact live mesh")
	var saves=preload("res://src/campaign_save.gd");var path: String="/tmp/yenikapi-visual-checks-save.json"
	check(saves.write(path,p.state,p.rules),"visual order saves")
	check(JSON.stringify(saves.read(path,p.rules))==JSON.stringify(p.state),"exact canonical state survives load")
	ui.execute({"kind":"commission","id":"land_cultivate"})
	var paid: String=JSON.stringify(p.state);ui.execute({"kind":"commission","id":"land_cultivate"})
	check(JSON.stringify(p.state)==paid,"duplicate purchase does not pay twice")
	ui.show_project("land_cultivate");check(ui.queued("land_cultivate").progress==0,"review shows queued progress")
	ui.execute({"kind":"asset_project","id":"land_cultivate","crew":3,"priority":2,"paused":true})
	check(ui.project_status("land_cultivate").begins_with(ui.w("paused")),"paused status explicit")
	ui.execute({"kind":"cancel","id":"land_cultivate"});check(p.state.wood==30,"unused cancellation refund uses real ledger")
	ui.execute({"kind":"role","role":"watch"});ui.show_project("land_cultivate")
	check(ui.find_child("VisualCommission",true,false).disabled,"office limits visible in review")
	ui.execute({"kind":"role","role":"god"})
	var old: Dictionary=p.rules.new_state();p.state=old;ui.open()
	check(not p.rules.assets.active(p.state) and not p.rules.living.active(p.state),"opening older save never adopts rules")
	ui.legacy();check(not ui.enabled,"detailed ledger remains available")
	check(p.rules.validate_state(p.state),"old save remains valid")
	app.queue_free();await process_frame
	print("VISUAL CHECKS: ",checks," checks, ",failures," failures");quit(1 if failures else 0)
