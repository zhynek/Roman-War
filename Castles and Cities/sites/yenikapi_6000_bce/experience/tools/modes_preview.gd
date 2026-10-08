extends "res://tools/defense_preview.gd"
const Living=preload("res://tools/living_driver.gd")
const ModesChecks=preload("res://tools/modes_host_checks.gd")
var durations: Array=[]
func _initialize() -> void:
	out_dir="/tmp/village-modes-controls"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func slow_host() -> void:
	# Slowing only the pacing makes the real progress/cancel controls reviewable.
	# The wrapper delegates every command and tick to the unchanged rules.
	d.host.pause();d.host.stop()
	var b: Dictionary=d.host.snapshot()
	d.host.attach({"defense":ModesChecks.SlowDefense.new(app.campaign.rules)},b);d.host.run()
func normal_host() -> void:
	d.host.pause();d.host.stop()
	var b: Dictionary=d.host.snapshot()
	d.host.attach(app.campaign.rules,b);d.host.run()
func readiness() -> void:
	var p=app.campaign
	for i in range(50):
		if p.rules.warfare.threats.ready(p.state,p.rules):return
		p.state=Living.orders(p.rules,p.state,true)
		await click_button("DefensePrepSeason")
	check(false,"threat warning and recovery bound")
func quick_end() -> void:
	for i in range(240):
		if d.battle.phase=="ended" and not d.quick_ui:return
		await create_timer(.05).timeout
	check(false,"quick UI completed in practical test bound")
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;d=app.defense_panel;p.save_path=out_dir.path_join("modes.json")
	p.state=Living.at_season(p.rules,12,true);app.show_campaign(p.state,p.rules);app.visual_commands.open()
	await click_button("DefenseEntry");await click_button("WarfareAdopt")
	var base_watch: int=p.rules.defense.quote(p.state,p.rules).count
	await click_button("WarfareMuster_4")
	check(p.state.warfare.muster==4 and p.rules.defense.quote(p.state,p.rules).count>base_watch,"additional named watch competes through actual workforce controls")
	await click_button("WarfareThreatsEnable")
	check(p.rules.warfare.threats.enabled(p.state),"explicit recurring-threat adoption through preparation control")
	check(d.find_child("DefenseMobilize",true,false).disabled,"quiet period permits ordinary preparation but no premature real battle")
	await shot("01-quiet-preparations")
	var before_practice: Dictionary=p.state.duplicate(true)
	await click_button("DefensePractice");check(d.practice and d.battle.phase=="deployment","isolated practice remains available while scheduler is quiet")
	await click_button("DefenseStart");await click_button("DefensePause")
	await click_button("DefenseDelegate");check(d.host.snapshot().tactics.encounter.mode=="delegated" and d.host.snapshot().paused,"handoff preserves pause")
	await shot("02-paused-delegation")
	await click_button("DefensePause");await create_timer(.25).timeout
	await click_button("DefenseTakeCommand");check(d.host.snapshot().tactics.encounter.mode=="direct","take back live command")
	await click_button("DefenseDelegate");await click_button("DefenseOrder_hold")
	check(d.host.snapshot().tactics.encounter.mode=="direct" and d.host.snapshot().commands.back().action.order=="hold","manual spatial order takes command before it can be overwritten")
	slow_host();await click_button("DefenseQuick")
	await shot("03-quick-progress")
	check(d.quick_ui and not app.world.visible and not d.view.visible,"quick mode omits village rendering while progress remains live")
	check(d.find_child("DefenseSave",true,false).disabled,"quick practice clearly disables continuing-village save")
	await click_button("DefenseQuickCancel")
	check(d.host.snapshot().paused and d.host.snapshot().phase=="fighting" and d.host.snapshot().tactics.encounter.mode=="delegated","actual cancellation pauses a resumable delegated fight")
	check(app.world.visible and d.view.visible,"cancellation restores battlefield presentation")
	await shot("04-cancelled-resumable")
	normal_host();await click_button("DefenseQuick");await quick_end();await click_button("DefenseFinish")
	check(p.state==before_practice,"all modes and cancellation on practice preserve continuing village exactly")
	# Three full cycles use the existing seasonal work pipeline and actual mode buttons.
	for index in range(3):
		await click_button("DefenseEntry")
		await readiness()
		var spec: Dictionary=p.rules.warfare.threats.spec(p.state)
		check(spec.id==["stores","landing","probe"][index],"successive objectives "+spec.id)
		await shot("05-warning-"+spec.id)
		var count: int=p.state.defense.get("reports",[]).size() if p.state.has("defense") else 0
		if index==0:
			await click_button("DefenseDelegateEncounter")
			check(d.battle.phase=="fighting" and d.command_mode()=="delegated","preparation delegates and begins actual battle")
			await create_timer(.35).timeout;await click_button("DefenseSave")
			var saved: Dictionary=p.state.duplicate(true)
			await click_button("DefenseLoad");check(p.state==saved,"delegated active save resumes exact orders and decisions")
			await click_button("DefenseTakeCommand");await click_button("DefenseOrder_hold")
			await shot("06-takeover-stores")
			await click_button("DefenseQuick")
		elif index==1:
			await click_button("DefenseMobilize")
			check(p.state.defense.completed and d.battle.phase=="deployment","later encounter exists alongside prior completed reports")
			# Closing an unresolved cycle used to discard it when completed was true.
			var before_close: Dictionary=d.host.snapshot();d.close()
			check(p.state.defense.battle==before_close,"closing preserves unresolved later-cycle deployment")
			await click_button("DefenseEntry");check(d.host.snapshot()==before_close,"reopening preserves exact later-cycle battle")
			await click_button("DefenseDelegate")
			await click_button("DefenseQuick")
		else:await click_button("DefenseQuickEncounter")
		await quick_end();durations.append({"objective":spec.id,"milliseconds":d.host.status().elapsed_ms,"ticks":d.battle.tick,"outcome":d.battle.outcome})
		await shot("07-ended-"+spec.id)
		await click_button("DefenseSave");var ended_saved: Dictionary=p.state.duplicate(true)
		await click_button("DefenseLoad");check(p.state==ended_saved and d.battle.phase=="ended","ended "+spec.id+" save awaits acceptance")
		await click_button("DefenseFinish")
		check(p.state.defense.reports.size()==count+1 and p.state.warfare.threats.cycle==index+1,"exactly one accepted consequence and schedule increment "+spec.id)
		check(p.state.defense.battle.is_empty() and p.rules.validate_state(p.state),"continuing state valid after "+spec.id)
		var turn: int=p.state.turn;await click_button("VisualSeason");check(p.state.turn==turn+1,"ordinary village development resumes after "+spec.id)
	root.size=Vector2i(1280,800);await click_button("DefenseEntry");await shot("08-small-recovery");await click_button("DefenseBack")
	FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"durations":durations},"  "))
	print("MODES CONTROLS: ",checks," checks, ",failures," failures; ",JSON.stringify(durations));quit(1 if failures else 0)
