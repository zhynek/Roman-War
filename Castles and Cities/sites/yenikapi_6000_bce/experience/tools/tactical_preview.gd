extends "res://tools/defense_preview.gd"
func _initialize() -> void:
	out_dir="/tmp/village-warfare-phase1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1600,1000);root.always_on_top=true;root.grab_focus();DirAccess.make_dir_recursive_absolute(out_dir)
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
	var p=app.campaign;d=app.defense_panel;p.save_path=out_dir.path_join("battle.json")
	await click_button("VisualNew");await click_button("DefenseEntry")
	await click_button("DefensePrep_prepare");await click_button("DefensePrep_shelter")
	for i in range(4):await click_button("DefensePrepSeason")
	await click_button("DefensePrep_kits")
	for i in range(4):await click_button("DefensePrepSeason")
	await click_button("DefensePrep_training")
	for i in range(4):await click_button("DefensePrepSeason")
	await click_button("WarfareAdopt")
	check(p.rules.warfare.active(p.state),"explicit tactical adoption via actual control")
	await shot("01-prepared")
	var prepared: Dictionary=p.state.duplicate(true)
	await click_button("DefensePractice");await click_button("DefensePlace_stores")
	check(d.battle.has("tactics"),"new tactics in actual deployment")
	await click_button("DefenseColumn");check(d.host.snapshot().groups[0].tactical.width==1,"column control")
	await click_button("DefenseSpread");check(d.host.snapshot().groups[0].tactical.width==2,"spread control")
	await click_button("DefenseCloseView");await shot("02-deployment-close")
	var first: Dictionary=d.battle.groups[0];var second: Dictionary=d.battle.groups[1]
	var first_at: Vector2=app.camera.unproject_position(d.view.anchors[first.id]);var second_at: Vector2=app.camera.unproject_position(d.view.anchors[second.id])
	await pointer(first_at,MOUSE_BUTTON_LEFT,false);check(first.id in d.selected,"click exact rendered anchor")
	await pointer(second_at,MOUSE_BUTTON_LEFT,true);check(d.selected.size()==2,"additive selection")
	await click_button("DefenseStart");await click_button("DefensePause")
	var before: Dictionary=d.host.snapshot()
	var middle:=InputEventMouseButton.new();middle.button_index=MOUSE_BUTTON_MIDDLE;middle.pressed=true;middle.position=Vector2(500,450);root.push_input(middle,true)
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(530,460);motion.relative=Vector2(30,10);root.push_input(motion,true)
	middle=InputEventMouseButton.new();middle.button_index=MOUSE_BUTTON_MIDDLE;middle.position=Vector2(530,460);root.push_input(middle,true);await process_frame
	check(d.host.snapshot()==before,"camera pan never issues orders or advances rules")
	var pinch:=InputEventMagnifyGesture.new();pinch.position=Vector2(600,400);pinch.factor=100
	root.push_input(pinch,true);await process_frame
	check(app.camera.position.y>=app.world.floor_height(app.camera.position.x,app.camera.position.z)+3,"pinch camera respects terrain floor")
	check(d.host.snapshot()==before,"pinch is presentation only")
	await click_button("DefenseOverhead")
	for order in ["move","advance","defend","face"]:
		await click_button("DefenseOrder_"+order);await ground_order([-500,3300])
		check(d.host.snapshot().commands.back().action.order==order,"actual "+order)
	await click_button("DefenseOrder_hold")
	check(d.host.snapshot().groups[0].order=="hold","hold")
	await click_button("DefensePlace_stores");await click_button("DefenseCloseView");await shot("03-orders")
	await click_button("DefenseWithdrawAll");await click_button("DefensePause");await click_button("DefenseSpeed");await ended()
	check(d.battle.outcome=="withdrawal","tactical withdrawal")
	await click_button("DefenseFinish");check(p.state==prepared,"practice isolation")
	await click_button("DefenseEntry");await click_button("DefenseMobilize");await click_button("DefensePlace_stores")
	await click_button("DefenseStart");await click_button("DefenseSpeed")
	await create_timer(1).timeout;await click_button("DefenseSave")
	var saved: Dictionary=p.state.duplicate(true)
	await click_button("DefenseLoad");check(p.state==saved,"tactical active save/resume")
	await click_button("DefensePause")
	for i in range(220):
		if d.battle.phase=="ended":break
		var target: Dictionary={}
		for f in d.battle.groups:
			if f.side=="raider" and f.revealed and f.hp>0 and not f.routed:target=f;break
		if not target.is_empty():
			await click_button("DefensePause");await click_button("DefenseOverhead")
			check(await frame_target(str(target.id)),"observed target framed clear of battle controls")
			await click_button("DefenseOrder_attack")
			await pointer(app.camera.unproject_position(d.view.anchors[target.id]),MOUSE_BUTTON_RIGHT,false)
			check(d.host.snapshot().commands.back().action.order=="attack","attack observed enemy")
			await click_button("DefensePlace_stores");await click_button("DefenseCloseView");await shot("04-contact");await click_button("DefensePause");break
		await create_timer(.25).timeout
	await create_timer(7).timeout;await shot("05-engagement")
	await ended();check(d.battle.phase=="ended","bounded tactical outcome")
	await shot("06-report");await click_button("DefenseSave");await click_button("DefenseLoad");await click_button("DefenseFinish")
	check(p.rules.validate_state(p.state),"tactical acceptance valid")
	await click_button("VisualSeason");check(p.state.turn==int(prepared.turn)+1,"continued village season")
	await click_button("DefenseEntry");root.size=Vector2i(1280,800);await shot("07-recovery")
	FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures},"  "))
	print("TACTICAL RENDER: ",checks," checks, ",failures," failures");quit(1 if failures else 0)
func frame_target(id: String) -> bool:
	# The earliest visible approach can project beneath the HUD. Exercise the
	# public camera gesture to bring its actual anchor into clickable ground.
	var before: Dictionary=d.host.snapshot()
	var size_: Vector2=root.get_visible_rect().size
	var field:=Rect2(Vector2(40,130),Vector2(size_.x-400,size_.y-310))
	for i in range(12):
		if not d.view.anchors.has(id):return false
		var at: Vector2=app.camera.unproject_position(d.view.anchors[id])
		if field.has_point(at):
			check(d.host.snapshot()==before,"target framing is presentation only")
			return d.picked(at,true)==id
		var delta: Vector2=(field.get_center()-at)*.5
		delta.x=clampf(delta.x,-150,150);delta.y=clampf(delta.y,-150,150)
		var origin: Vector2=field.get_center()
		var press:=InputEventMouseButton.new();press.position=origin;press.button_index=MOUSE_BUTTON_MIDDLE;press.pressed=true;root.push_input(press,true)
		var motion:=InputEventMouseMotion.new();motion.position=origin+delta;motion.relative=delta;motion.button_mask=MOUSE_BUTTON_MASK_MIDDLE;root.push_input(motion,true)
		var release:=InputEventMouseButton.new();release.position=origin+delta;release.button_index=MOUSE_BUTTON_MIDDLE;root.push_input(release,true)
		for frame in range(3):await process_frame
	return false
