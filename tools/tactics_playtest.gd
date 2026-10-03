extends SceneTree
## Controlled combat fixtures use real recruited troops and command buttons.
## Output and isolated QA saves stay outside the repository.
var city: RomaCityScreen
var out:="/tmp/roman-war-tactics-qa"
var failed:=false

func _init() -> void:
	preload("res://tools/render_qa_storage.gd").configure("Roman War Tactics QA/%d" % OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out=arg.trim_prefix("out_dir=")
	_run.call_deferred()

func _run() -> void:
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,800);root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out)
	city=RomaCityScreen.new();city.standalone=false;city.shared_session=true
	city.game=Game.new_campaign("senate",42,"medium","long",false)
	root.add_child(city)
	await _frames(12)
	city.open_battle()
	var panel:=city.battle_panel
	await _click(panel,panel.w("drill"))
	city.game.city_battle_command("latium",["defender_1"],"move",[0,-2000])
	city.game.city_battle_command("latium",["defender_2"],"move",[0,-3000])
	panel.refresh()
	panel.select_formation("defender_0")
	await _click(panel,panel.w("split"))
	await _click(panel,panel.w("battalion_select"))
	_check(panel._selection().size()==3,"select battalion groups all three platoons")
	panel.camera_rig.center(Vector3(0,0,10));panel.camera_rig.target_span=55
	panel.camera_rig.target_elevation=deg_to_rad(65);panel.camera_rig.target_yaw=0
	await _seconds(1)
	var a:=panel._project(Vector3(-7,0,10));var b:=panel._project(Vector3(7,0,10))
	_check(panel.battle_rect().has_point(a) and panel.battle_rect().has_point(b),"frontage is visible within battlefield")
	await _mouse(a,true)
	var motion:=InputEventMouseMotion.new();motion.position=b;motion.global_position=b;root.push_input(motion)
	await _frames(3);await _shot("01-drag-frontage")
	await _mouse(b,false)
	var battle:Dictionary=city.game.state.city_battles.latium
	var slots:Array=[]
	for f in battle.formations:
		if f.get("source_id","")=="defender_0":
			_check(not slots.has(f.position),"drag places an individual platoon slot")
			slots.append(f.position)
	await _click(panel,panel.w("phalanx"))
	_check(panel.selected_formation().formation=="phalanx","phalanx button sets real formation")
	await _shot("02-deployed-phalanx")
	# Run the actual host while issuing orders; no step UI participates.
	await _click(panel,panel.w("start"))
	await _seconds(1)
	var tick:int=panel.host.snapshot().tick
	await _click(panel,panel.w("column"))
	await _seconds(0.4)
	_check(panel.host.snapshot().tick>tick,"worker advances while command UI remains interactive")
	_check(panel.selected_formation().reform_ms>0,"formation change takes live battle time")
	await _shot("03-live-reforming")
	await _click(panel,panel.w("pause"))
	var frozen:=JSON.stringify(city.game.state)
	await _seconds(0.3)
	_check(JSON.stringify(city.game.state)==frozen,"paused animation and camera do not advance state")
	await _click(panel,panel.w("save"))
	_check(not SaveGame.from_json(SaveGame.to_json(city.game.state)).is_empty(),"split live battle saves")
	# Freeze scheduler, stage a reproducible contact view, advance only through
	# deterministic simulation commands for the captured close engagement.
	panel.host.stop();panel.set_process(false)
	for i in range(35):city.game.city_battle_step("latium")
	city.game.city_battle_command("latium",["defender_0","defender_0_p2","defender_0_p3"],"phalanx")
	for i in range(30):city.game.city_battle_step("latium")
	battle.paused=false;panel.refresh()
	_camera(Vector3(9,6,18),Vector3(0,1,10))
	panel.hide();panel.forces.show()
	await _seconds(0.3);await _shot("04-phalanx-close")
	panel.show();panel.refresh()
	city.free()
	print("TACTICS PLAYTEST ","FAILED" if failed else "PASSED"," · ",out)
	quit(1 if failed else 0)

func _mouse(point: Vector2, pressed: bool) -> void:
	Input.warp_mouse(point)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=pressed;event.position=point;event.global_position=point;root.push_input(event)
	await _frames(3)

func _camera(at: Vector3, toward: Vector3) -> void:
	city.survey_camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	city.survey_camera.position=at;city.survey_camera.look_at(toward)

func _frames(count: int) -> void:
	for i in range(count):await process_frame

func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func _shot(name: String) -> void:
	await _frames(2);RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out.path_join(name+".png"))

func _click(parent: Node, text: String) -> void:
	var button:=_find(parent,text)
	_check(button!=null,"button available: "+text)
	if button==null:return
	await city._scroll_to_control(button);await _frames(3)
	var p:=button.get_global_rect().get_center()
	Input.warp_mouse(p)
	var motion:=InputEventMouseMotion.new();motion.position=p;motion.global_position=p;root.push_input(motion)
	await _frames(2)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=p;event.global_position=p;root.push_input(event)
		await _frames(2)

func _find(parent: Node, text: String) -> Button:
	if parent is Button and parent.text==text and parent.is_visible_in_tree():return parent
	for child in parent.get_children():
		var button:=_find(child,text)
		if button!=null:return button
	return null

func _check(ok: bool, detail: String) -> void:
	print("PASS " if ok else "FAIL ",detail);failed=failed or not ok
