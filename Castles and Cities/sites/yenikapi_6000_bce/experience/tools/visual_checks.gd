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
	p.asset_panel.begin()
	check(is_instance_valid(p.tabs),"direct legacy asset entry creates its ledger tabs")
	ui.begin()
	p.land_panel.inspect("north_west")
	check(is_instance_valid(p.tabs) and p.tabs.current_tab==7,"legacy world inspection restores hidden ledger content")
	ui.open()
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
	benefit_copy(p.rules,p.state)
	app.queue_free();await process_frame
	print("VISUAL CHECKS: ",checks," checks, ",failures," failures");quit(1 if failures else 0)

func benefit_copy(rules,state: Dictionary) -> void:
	var model=preload("res://src/project_presentation.gd")
	var frozen: String=JSON.stringify(state)
	for id in ["lifecycle_store","lifecycle_workroom"]:
		var spec: Dictionary=rules.projects[id]
		var values: Dictionary=model.benefit_values(rules,id)
		check(values.total==spec.benefit_target.total,"benefit matches validated cumulative target "+id)
		for template in [spec.body,spec.presentation.benefit]:
			var rendered: String=model.text_for(rules,id,template)
			check("{delta}" not in rendered and "{total}" not in rendered,"project prose resolves benefit placeholders "+id)
	check(model.text_for(rules,"shared_store",rules.projects.shared_store.body)==rules.projects.shared_store.body,"legacy project copy is unchanged")
	# Change only a private rules projection to prove the display reads numeric
	# effects/capacities instead of the authored assertion or hardcoded prose.
	var original_projects: Dictionary=rules.projects
	rules.projects=original_projects.duplicate(true)
	rules.projects.lifecycle_store.effects.storage+=7
	var storage: Dictionary=model.benefit_values(rules,"lifecycle_store")
	check(storage.delta==int(original_projects.lifecycle_store.effects.storage)+7,"displayed storage delta follows actual effects")
	check(storage.total==int(original_projects.shared_store.effects.storage)+storage.delta,"displayed storage total sums predecessor and new delta")
	rules.projects=original_projects
	var original_proposals: Dictionary=rules.land.proposals
	rules.land.proposals=original_proposals.duplicate(true)
	rules.land.proposals.lifecycle_workroom.work+=3
	var places: Dictionary=model.benefit_values(rules,"lifecycle_workroom")
	check(places.total==int(original_proposals.lifecycle_workroom.work)+3,"displayed workroom total follows actual site capacity")
	check(places.delta==places.total-int(original_proposals.land_adapt_workroom.work),"displayed workroom delta compares predecessor use")
	rules.land.proposals=original_proposals
	check(JSON.stringify(state)==frozen,"benefit reads do not mutate authoritative state")
	var config: Dictionary=rules.lifecycle.content.duplicate(true)
	config.transitions[0].to="town"
	for project in config.projects:
		if project.id=="lifecycle_store":project.stage_requires="town"
	var alternate=preload("res://src/core/lifecycle_rules.gd").new(config,rules.lifecycle.balance)
	var preview: Dictionary=alternate.status(state,rules)
	check("lifecycle_store" in preview.unlocks and "lifecycle_workroom" not in preview.unlocks,"inactive unlock preview follows authored transition target")

	config.transitions.append({"id":"later_test","from":"town","to":"large_town","project":"future_civic","readiness":config.transitions[0].readiness.duplicate(true)})
	var future=preload("res://src/core/lifecycle_rules.gd").new(config,rules.lifecycle.balance)
	var recognized: Dictionary=state.duplicate(true)
	recognized.lifecycle={"recognition":"town"}
	recognized.completed.append({"id":"future_civic","turn":int(state.turn)})
	check(future.stage(recognized,rules)=="large_town","legacy recognition is a starting rank for later authored civic work")
