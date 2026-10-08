extends "res://tools/defense_preview.gd"
func _initialize() -> void:
	out_dir="/tmp/village-fortification-controls"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;d=app.defense_panel;p.save_path=out_dir.path_join("plans.json")
	# Prepared fixture is itself a replay of ordinary public village commands.
	p.state=preload("res://tools/living_driver.gd").at_season(p.rules,12,true)
	app.show_campaign(p.state,p.rules);app.visual_commands.open()
	await click_button("DefenseEntry");await click_button("WarfareAdopt")
	for id in ["warfare_store_screen","warfare_landing_screen"]:
		var wood: int=int(p.state.wood)
		await click_button("WarfareBuild_"+id)
		check(p.state.wood==wood-int(p.rules.projects[id].wood),"actual fortification payment "+id)
		check(not p.rules.has_project(p.state,id),"payment creates no free completed defense")
		await shot(id+"-paid")
		for i in range(12):
			if p.rules.has_project(p.state,id):break
			await click_button("DefensePrepSeason")
		check(p.rules.has_project(p.state,id),"ordinary finite workforce finishes "+id)
	await choose_plan("important","store_stand")
	await choose_plan("reserve","landing_stand")
	await choose_plan("fallback","refuge")
	check(p.state.warfare.plans.important=="store_stand" and p.state.warfare.plans.reserve=="landing_stand","actual plan selection")
	await click_button("WarfareSavePreparation");var saved: Dictionary=p.state.duplicate(true)
	await choose_plan("important","stores");await click_button("WarfareLoadPreparation")
	check(p.state==saved,"preparation save restores paid projects and plans")
	await shot("03-complete-plans")
	await click_button("DefenseMobilize")
	check(d.battle.tactics.defenses.size()==2,"completed maintained screens protect actual battle positions")
	await click_button("WarfareUse_important");await click_button("DefenseSpread");await click_button("DefenseCloseView")
	await shot("04-store-gate-deployment")
	check(d.host.snapshot().groups[0].order=="defend","saved important place dispatches ordinary defender order")
	await click_button("WarfareUse_reserve");await click_button("DefenseCloseView");await shot("05-landing-gate-deployment")
	await click_button("DefenseStart");await click_button("DefensePause");await click_button("DefenseSave")
	var active: Dictionary=p.state.duplicate(true)
	await click_button("DefenseLoad");check(p.state==active,"active battle saves actual defense navigation and plans")
	await click_button("WarfareUse_fallback");await click_button("DefenseSpeed");await click_button("DefensePause")
	await ended();await click_button("DefenseFinish")
	for id in ["warfare_store_screen","warfare_landing_screen"]:check(p.rules.has_project(p.state,id),"battle preserves paid screen "+id)
	await click_button("VisualSeason");check(p.rules.validate_state(p.state),"continued life after constructed-defense battle")
	await shot("06-continued-village")
	FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures},"  "))
	print("FORTIFICATION CONTROLS: ",checks," checks, ",failures," failures");quit(1 if failures else 0)
func choose_plan(slot: String,place: String) -> void:
	for i in range(app.campaign.rules.warfare.forts.content.positions.size()):
		if app.campaign.state.warfare.plans[slot]==place:break
		await click_button("WarfarePlanNext_"+slot)
	check(app.campaign.state.warfare.plans[slot]==place,"plan controls chose "+slot+" "+place)
