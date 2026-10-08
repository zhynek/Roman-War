extends "res://tools/defense_preview.gd"
func _initialize() -> void:
	out_dir="/tmp/village-warfare-camera"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,800);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;d=app.defense_panel
	p.state=preload("res://tools/living_driver.gd").at_season(p.rules,12,true)
	p.state=p.rules.command(p.state,{"kind":"warfare_begin"}).state
	app.show_campaign(p.state,p.rules);app.visual_commands.open()
	await click_button("DefenseEntry");await click_button("DefenseMobilize");await click_button("DefensePlace_stores");await click_button("DefenseCloseView")
	var before: Dictionary=d.host.snapshot()
	for factor in [100.0,.001,2.0,.5]:
		var e:=InputEventMagnifyGesture.new();e.position=Vector2(600,400);e.factor=factor;root.push_input(e,true);await process_frame
		check(app.camera.position.y+.001>=app.world.floor_height(app.camera.position.x,app.camera.position.z)+3,"pinch stays above terrain")
		check(app.camera.position.y<=180.001,"pinch stays in useful overhead range")
	check(d.host.snapshot()==before,"gestures preserve paused battle")
	await click_button("DefenseCloseView")
	var a:=InputEventMouseButton.new();a.button_index=MOUSE_BUTTON_MIDDLE;a.pressed=true;a.position=Vector2(500,450);root.push_input(a,true)
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(540,460);motion.relative=Vector2(40,10);root.push_input(motion,true)
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_MIDDLE;release.position=Vector2(1000,300);root.push_input(release,true);await process_frame
	check(not d.panning,"middle release over panel releases camera")
	await click_button("DefenseCloseView")
	var first: Vector2=app.camera.unproject_position(d.view.anchors[d.battle.groups[0].id]);var second: Vector2=app.camera.unproject_position(d.view.anchors[d.battle.groups[1].id])
	var press:=InputEventMouseButton.new();press.position=first.min(second)-Vector2(15,15);press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
	motion=InputEventMouseMotion.new();motion.position=first.max(second)+Vector2(15,15);root.push_input(motion,true)
	release=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=motion.position;root.push_input(release,true);await process_frame
	check(d.selected.size()==2,"drag selects both rendered anchors")
	await click_button("DefenseOrder_face");await ground_order([3000,3000])
	check(d.host.snapshot().groups[0].tactical.face_locked,"paused face command recorded")
	await shot("camera-and-facing")
	print("TACTICAL CAMERA: ",checks," checks, ",failures," failures");quit(1 if failures else 0)
