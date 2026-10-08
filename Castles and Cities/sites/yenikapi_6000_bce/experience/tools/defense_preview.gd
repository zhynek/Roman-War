extends "res://tools/visual_preview.gd"
var d
func _initialize() -> void:
	out_dir="/tmp/village-defense-render"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;d=app.defense_panel;p.save_path=out_dir.path_join("battle.json")
	if FileAccess.file_exists(p.save_path):DirAccess.remove_absolute(p.save_path)
	await click_button("VisualNew");await click_button("DefenseEntry");await shot("01-preparation")
	check(d.active_ui and p.rules.living.active(p.state),"discoverable ordinary village defense")
	await click_button("DefensePrep_prepare");await click_button("DefensePrep_shelter")
	for i in range(4):await click_button("DefensePrepSeason")
	check(p.rules.has_project(p.state,"watch_shelter"),"paid shelter through actual preparation controls")
	await click_button("DefensePrep_kits")
	for i in range(4):await click_button("DefensePrepSeason")
	await click_button("DefensePrep_training")
	for i in range(4):await click_button("DefensePrepSeason")
	check(p.state.living.kits>0 and p.state.living.readiness>0,"ordinary labor builds equipment and readiness")
	await shot("02-prepared-roster")
	var prepared: Dictionary=p.state.duplicate(true)
	await click_button("DefensePractice");check(d.practice,"practice branch")
	await click_button("DefensePlace_stores");await shot("03-deployment")
	await click_button("DefenseStart");await click_button("DefensePause")
	var paused: Dictionary=d.host.snapshot();await create_timer(.4).timeout
	check(d.host.snapshot()==paused,"actual pause")
	# Rectangle selection and shift click on the exact drawn anchors.
	await click_button("DefenseCloseView")
	var first: Dictionary=d.battle.groups[0];var second: Dictionary=d.battle.groups[1]
	var first_at: Vector2=app.camera.unproject_position(d.view.anchors[first.id])
	var second_at: Vector2=app.camera.unproject_position(d.view.anchors[second.id])
	await pointer(first_at,MOUSE_BUTTON_LEFT,false);check(first.id in d.selected,"click selection")
	await pointer(second_at,MOUSE_BUTTON_LEFT,true);check(d.selected.size()==2,"shift additive selection")
	var a:=first_at.min(second_at)-Vector2(20,20);var b:=first_at.max(second_at)+Vector2(20,20)
	var press:=InputEventMouseButton.new();press.position=a;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
	var motion:=InputEventMouseMotion.new();motion.position=b;motion.relative=b-a;root.push_input(motion,true)
	var release:=InputEventMouseButton.new();release.position=b;release.button_index=MOUSE_BUTTON_LEFT;root.push_input(release,true);await process_frame
	check(d.selected.size()==2,"drag selection")
	await click_button("DefenseOrder_face")
	await ground_order([0,2000]);check(d.host.snapshot().commands.back().action.order=="face","facing order while paused")
	for order in ["move","advance","defend"]:
		await click_button("DefenseOrder_"+order);await ground_order([-500,3300]);check(d.host.snapshot().commands.back().action.order==order,"actual "+order)
	await click_button("DefenseOrder_hold");check(d.host.snapshot().groups[0].order=="hold","hold works")
	await shot("04-paused-orders-close")
	var immutable: Dictionary=d.host.snapshot();var camera_before: Transform3D=app.camera.transform
	var wheel:=InputEventMouseButton.new();wheel.position=Vector2(700,500);wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;root.push_input(wheel,true);await process_frame
	check(app.camera.transform!=camera_before and d.host.snapshot()==immutable,"camera zoom never changes paused rules")
	await key(KEY_SPACE);await create_timer(.3).timeout;await key(KEY_SPACE)
	check(d.host.snapshot().tick>int(immutable.tick) and d.host.snapshot().paused,"keyboard pause/resume")
	await click_button("DefenseWithdrawAll");await click_button("DefenseSpeed");await click_button("DefensePause")
	await ended();check(d.battle.outcome=="withdrawal","practice withdrawal")
	await shot("05-withdrawal-report");await click_button("DefenseFinish")
	check(p.state==prepared,"practice leaves ongoing state byte-for-byte unchanged")
	# Real encounter, save and resume through exact controls.
	await click_button("DefenseEntry");await click_button("DefenseMobilize");await click_button("DefensePlace_stores")
	await click_button("DefenseStart");await click_button("DefenseSpeed")
	await create_timer(2).timeout;await click_button("DefenseSave")
	var saved: Dictionary=p.state.duplicate(true)
	await click_button("DefenseLoad");check(p.state==saved,"active battle orders survive actual save/load")
	await click_button("DefensePause");await shot("06-live-defense")
	# Attack a currently observed enemy through the same pointer path.
	for i in range(120):
		if d.battle.phase=="ended":break
		var enemy: Dictionary={}
		for f in d.battle.groups:
			if f.side=="raider" and f.revealed:enemy=f;break
		if not enemy.is_empty():
			await click_button("DefensePause");await click_button("DefenseOverhead");await click_button("DefenseOrder_attack")
			var at: Vector2=app.camera.unproject_position(d.view.anchors[enemy.id]);await pointer(at,MOUSE_BUTTON_RIGHT,false)
			check(d.host.snapshot().commands.back().action.order=="attack","selected observed enemy attack")
			await click_button("DefensePlace_stores");await click_button("DefenseCloseView");await shot("07-engagement-close");await click_button("DefensePause");break
		await create_timer(.25).timeout
	await ended();check(d.battle.outcome=="victory","prepared live victory")
	await shot("08-victory-report")
	await click_button("DefenseSave");var ended_save: Dictionary=p.state.duplicate(true)
	await click_button("DefenseLoad");check(p.state==ended_save and d.battle.phase=="ended","ended report saved before commit")
	await click_button("DefenseFinish")
	check(p.state.defense.completed and p.rules.validate_state(p.state),"outcome committed and continuing state valid")
	await click_button("VisualSeason");await shot("09-return-and-recovery")
	check(p.state.turn==int(prepared.turn)+1,"return to village seasonal life")
	# Isolated earlier village branch for rendered defeat; no user's save touched.
	p.state=prepared.duplicate(true);app.show_campaign(p.state,p.rules);app.visual_commands.open()
	await click_button("DefenseEntry");await click_button("DefenseMobilize");await click_button("DefensePlace_refuge");await click_button("DefenseOrder_hold")
	await click_button("DefenseStart");await click_button("DefenseSpeed");await ended()
	check(d.battle.outcome=="defeat","unopposed stores defeat")
	await shot("10-defeat-report");await click_button("DefenseFinish")
	check(p.state.food==int(prepared.food)-int(p.state.defense.reports[0].cost)-int(p.state.defense.reports[0].lost),"defeat stock consequence once")
	root.size=Vector2i(1280,800);await click_button("DefenseEntry");await shot("11-small-window-recovery");await click_button("DefenseBack")
	FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures},"  "))
	print("DEFENSE RENDER: ",checks," checks, ",failures," failures");quit(1 if failures else 0)
func pointer(at: Vector2,which: int,shift_: bool) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=which;e.pressed=pressed;e.shift_pressed=shift_;root.push_input(e,true)
	for i in range(3):await process_frame
func ground_order(at: Array) -> void:
	var pos:=Vector3(float(at[0])/100,0,float(at[1])/100);pos.y=app.world.floor_height(pos.x,pos.z)
	await pointer(app.camera.unproject_position(pos),MOUSE_BUTTON_RIGHT,false)
func ended() -> void:
	for i in range(720):
		if d.battle.phase=="ended":return
		await create_timer(.25).timeout
	check(false,"live encounter timeout")

func key(code: int) -> void:
	for pressed in [true,false]:
		var e:=InputEventKey.new();e.keycode=code;e.pressed=pressed;root.push_input(e,true)
	await process_frame
