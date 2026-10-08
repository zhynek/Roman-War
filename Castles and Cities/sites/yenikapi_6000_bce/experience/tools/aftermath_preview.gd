extends "res://tools/modes_preview.gd"
func _initialize() -> void:
	out_dir="/tmp/village-aftermath-controls"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func text_content(node: Node) -> String:
	var result: String=node.text+"\n" if node is Label else ""
	for child in node.get_children():result+=text_content(child)
	return result
func check_resting(patients: Array) -> void:
	for id in patients:
		var found: bool=false
		for routine in app.campaign_view.life.routines:
			if routine.id!=id:continue
			found=true
			check(routine.activity=="battle_recovery" and routine.job=="rest" and routine.pose=="sit" and routine.route.size()==1 and routine.station=="home_"+routine.household,"injured resident rests at their own home: "+id)
		check(found,"injured named resident remains in village: "+id)
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;d=app.defense_panel;p.save_path=out_dir.path_join("aftermath.json")
	p.state=Living.at_season(p.rules,12,true);app.show_campaign(p.state,p.rules);app.visual_commands.open()
	await click_button("DefenseEntry");await click_button("WarfareAdopt");await click_button("WarfareMuster_4");await click_button("WarfareThreatsEnable")
	await readiness()
	var wood: int=p.state.wood
	await click_button("WarfareBuild_warfare_store_screen")
	check(p.state.wood==wood-int(p.rules.projects.warfare_store_screen.wood),"unrelated defense project pays ordinary materials before battle")
	var paid_queue: Array=p.state.queue.duplicate(true)
	await click_button("DefenseDelegateEncounter");await create_timer(.35).timeout;await click_button("DefenseSave");await click_button("DefenseLoad")
	await click_button("DefenseTakeCommand");await click_button("DefenseOrder_hold");await click_button("DefenseQuick");await quick_end()
	var pending: Dictionary=p.rules.defense.outcome(d.battle,p.rules)
	check(pending.has("aftermath") and pending.aftermath.participants.size()==6,"pending outcome exposes actual six named participants")
	check(not pending.wounded.is_empty() and int(pending.aftermath.kit_wear)>0,"real battle causes recoverable wounds and equipment wear")
	check(p.state.warfare.aftermath.people.is_empty(),"pending preview has applied no personal consequences")
	await shot("01-pending-named-report")
	await click_button("DefenseSave");var pending_save: Dictionary=p.state.duplicate(true)
	await click_button("DefenseLoad");check(p.state==pending_save,"ended named aftermath resumes exactly before acceptance")
	await click_button("DefenseFinish")
	check(p.state.defense.reports.size()==1 and not p.state.defense.recovery.is_empty(),"actual report acceptance commits named recovery exactly once")
	check(p.state.queue==paid_queue,"acceptance preserves unrelated paid work")
	var accepted: Dictionary=p.state.defense.reports.back().duplicate(true)
	var patients: Array=p.state.defense.recovery.keys();patients.sort()
	var memory: Dictionary=p.state.warfare.aftermath.people.duplicate(true)
	check_resting(patients)
	await shot("02-ordinary-village-after-acceptance")
	await click_button("VisualAftermath")
	var body: String=text_content(d)
	for person in accepted.aftermath.participants:
		check(not person.name.is_empty() and person.name in body,"persistent aftermath contains stamped name "+person.name)
		check(d.home_label(person.household) in body,"persistent aftermath contains household "+person.household)
	check("Treatment workers:" in body and "condition:" in body,"ordinary aftermath explains finite care and equipment repair")
	await shot("03-persistent-recovery-work")
	# Pausing treatment changes finite allocation; it does not erase injuries.
	await click_button("AftermathCare")
	if p.state.living.repair:await click_button("AftermathRepair")
	var recovery_before: Dictionary=p.state.defense.recovery.duplicate(true)
	var condition_before: int=p.state.warfare.aftermath.equipment_condition
	await click_button("AftermathSeason")
	check(p.state.defense.recovery==recovery_before,"a fed season without allocated treatment leaves recovery outstanding")
	check(p.state.warfare.aftermath.equipment_condition==condition_before,"disabled ordinary repair cannot restore battle condition")
	await click_button("AftermathCare");await click_button("AftermathReleaseWatch");await click_button("AftermathPrepare");await click_button("AftermathRepair")
	check(p.state.warfare.aftermath.care and p.state.warfare.muster==0 and p.state.living.prepare>0 and p.state.living.repair,"recovery controls use existing duties and release extra watch")
	await click_button("AftermathBack")
	await click_button("VisualSave");var saved: Dictionary=p.state.duplicate(true)
	await click_button("VisualLoad");check(p.state==saved,"ordinary village save preserves care, injuries, experience and kit condition")
	await click_button("VisualMenu");await click_button("VisualMenuLedger")
	for tab_index in range(6):
		var tabbar: TabBar=p.tabs.get_tab_bar()
		await pointer(tabbar.global_position+tabbar.get_tab_rect(p.tabs.current_tab).get_center(),MOUSE_BUTTON_LEFT,false)
		await key(KEY_RIGHT)
		for i in range(4):await process_frame
		if p.tabs.current_tab==3:
			check(d.w("muster_heading") in text_content(p) and d.w("aftermath_care_heading") in text_content(p),"ordinary journal describes muster and treatment decisions without raw action IDs")
	check(p.tabs.current_tab==6,"normal household tab opened through actual controls")
	if p.tabs.current_tab!=6:
		await shot("failed-household-navigation");quit(1);return
	body=text_content(p)
	for id in patients:check(d.recorded_person(id).name in body,"normal household memories retain injured resident "+id)
	check("fed treatment seasons remain" in body,"normal household interface shows current recovery duration")
	var link: Control=p.find_child("HouseholdAftermath",true,false)
	if link!=null:p.tabs.get_child(6).ensure_control_visible(link)
	await shot("04-household-history-and-care")
	await click_button("HouseholdAftermath")
	var repaired: bool=false
	for season in range(6):
		if p.state.defense.recovery.is_empty() and int(p.state.warfare.aftermath.equipment_condition)==100:break
		var f: Dictionary=p.rules.forecast(p.state);var before: Dictionary=p.state.duplicate(true)
		await click_button("AftermathSeason")
		if int(f.living.repaired)>0:
			repaired=true
			check(p.state.warfare.aftermath.equipment_condition==mini(100,int(before.warfare.aftermath.equipment_condition)+int(p.rules.warfare.aftermath.tuning.equipment_repair_gain)),"paid ordinary repair restores the defined equipment condition")
		check(p.state.defense.reports[0]==accepted,"seasonal care preserves immutable encounter record")
	check(p.state.defense.recovery.is_empty() and repaired and int(p.state.warfare.aftermath.equipment_condition)==100,"food, finite care and paid repair complete recovery")
	check(p.state.warfare.aftermath.people.keys()==memory.keys(),"recovery never deletes participants or their experience")
	await shot("05-recovered-and-recorded")
	await click_button("AftermathBack")
	# Practice after real history must retain its actual skill inputs yet commit nothing.
	var before_practice: Dictionary=p.state.duplicate(true)
	await click_button("DefenseEntry");await click_button("DefensePractice")
	for group in d.battle.groups:
		if group.side!="watch":continue
		var skill: int=0
		for id in group.members:skill+=p.rules.warfare.aftermath.skill(before_practice,id,p.rules)
		check(group.tactical.skill==skill/group.members.size(),"practice uses actual accumulated resident skill")
	await click_button("DefenseQuick");await quick_end();await click_button("DefenseFinish")
	check(p.state==before_practice,"post-history practice changes no continuing recovery or experience")
	await click_button("DefenseEntry");await readiness();await click_button("WarfareMuster_4")
	await click_button("DefenseQuickEncounter");await quick_end();await click_button("DefenseFinish")
	check(p.state.warfare.threats.cycle==2 and p.state.defense.reports.size()==2,"another objective remains playable after named recovery")
	check(p.rules.has_project(p.state,"warfare_store_screen"),"ordinary work completed the previously paid screen during continuing life")
	await click_button("VisualSeason");check(p.rules.validate_state(p.state),"continued village development after second accepted encounter")
	root.size=Vector2i(1280,800);await click_button("VisualAftermath");await shot("06-small-persistent-history")
	var scroll: ScrollContainer=d.find_child("AftermathScroll",true,false);scroll.scroll_vertical=100000
	for i in range(5):await process_frame
	await shot("07-small-history-records")
	await click_button("AftermathBack")
	FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"patients":patients},"  "))
	print("AFTERMATH CONTROLS: ",checks," checks, ",failures," failures");quit(1 if failures else 0)
