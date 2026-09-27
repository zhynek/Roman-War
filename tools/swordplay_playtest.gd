extends SceneTree
## Controlled combat fixtures use real recruited troops and command buttons.
## Output and isolated QA saves stay outside the repository.
var city: RomaCityScreen
var out:="/tmp/roman-war-swordplay-qa"
var failed:=false

func _init() -> void:
	preload("res://tools/render_qa_storage.gd").configure("Roman War Swordplay QA/%d" % OS.get_process_id())
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
	var before:int=city.game.state.factions.senate.treasury
	city.open_drawer("barracks");city._choose_dossier_tab("troops")
	var name:String=city.game.data.units.roman_command_escort.name
	await _click(city.drawer_body,city.w("troops_recruit")%name)
	_check(city.game.state.settlements.latium.recruitment_queue[-1].template=="roman_command_escort","actual barracks button queues mounted escort")
	_check(city.game.state.factions.senate.treasury<before,"guard recruitment spends campaign treasury")
	for i in range(3):city.game.city_advance_day("latium")
	city.drawer.hide();city.refresh_city()
	city.game.data.roma_city.battle.practice_attackers=["gallic_oathsworn","roman_equites","tribal_warlord_guard"]
	city.open_battle()
	var panel:=city.battle_panel
	await _click(panel,panel.w("practice"))
	panel.set_process(false)
	_check(panel.snapshot.formations.any(func(f):return f.side=="defender" and f.get("specialty","")=="commander"),"paid guard appears in battle as a mounted commander")
	city.game.city_battle_start("latium")
	var battle:Dictionary=city.game.state.city_battles.latium
	battle.gate_integrity=0
	var own:Dictionary={};var enemy:Dictionary=battle.formations[0]
	for f in battle.formations:
		f.position=[0,-6000+int(f.id.get_slice("_",1))*600] if f.side=="defender" else [6000,-6000+int(f.id.get_slice("_",1))*600]
		f.destination=f.position.duplicate();f.goal=f.position.duplicate();f.path=[];f.order="hold"
		if f.template=="roman_principes" and f.side=="defender":own=f
	own.position=[0,1600];enemy.position=[0,1920]
	panel.refresh();panel.select_formation(own.id)
	await _click(panel,panel.ability_button.text)
	panel.host.stop();battle.paused=false;panel.refresh()
	_check(own.ability_remaining_ms>0,"veteran button activates an actual battle ability")
	_camera(Vector3(6.9,3.2,17.4),Vector3(0,1.25,17.4))
	for i in range(15):
		city.game.city_battle_step("latium");panel.refresh();await _seconds(0.1)
	await _shot("01-veteran-swordplay")
	for i in range(3):city.game.city_battle_step("latium");panel.refresh();await _seconds(0.1)
	await _shot("02-shield-block-and-thrust")
	# Capture clean close views, with the same live troop renderer and no UI
	# occlusion, at several points in a genuine resolved clash.
	panel.hide();panel.forces.show()
	var sequence:int=own.attack_seq
	for i in range(12):
		city.game.city_battle_step("latium")
		if own.attack_seq>sequence:break
	panel.refresh();panel.forces.show();panel.forces.set_process(false)
	for point in [0.08,0.20,0.32]:
		panel.forces._process(point)
		await _shot("03-swordplay-pose-%02d"%roundi(point*100))
	panel.forces.set_process(true)
	panel.show()
	# Mounted general remains the unit recruited via the barracks above.
	var guard:Dictionary=battle.formations[-1]
	own.position=[0,-4800];enemy.position=[6000,-4800]
	guard.position=[0,3300];guard.facing=[0,1000]
	panel.refresh();panel.select_formation(guard.id)
	await _click(panel,panel.ability_button.text)
	panel.host.stop();battle.paused=false;panel.refresh()
	_check(guard.role=="cavalry" and guard.ability_remaining_ms>0,"mounted escort carries an active rally")
	_camera(Vector3(6.2,3.6,35.4),Vector3(0,1.4,33.0))
	await _seconds(0.4)
	await _shot("04-mounted-general-rally")
	panel.hide();panel.forces.show()
	await _shot("05-mounted-escort-close")
	panel.show()
	var spear_guard:Dictionary=battle.formations[3]
	panel.select_formation(spear_guard.id)
	await _click(panel,panel.ability_button.text)
	panel.host.stop()
	_check(spear_guard.ability_remaining_ms>0,"brace order is reachable from actual spear guard UI")
	var frozen:=JSON.stringify(city.game.state)
	await _seconds(0.4)
	_check(JSON.stringify(city.game.state)==frozen,"camera and articulated animation leave paused battle unchanged")
	_check(not SaveGame.from_json(SaveGame.to_json(city.game.state)).is_empty(),"active abilities save correctly")
	city.free()
	print("SWORDPLAY PLAYTEST ","FAILED" if failed else "PASSED"," · ",out)
	quit(1 if failed else 0)

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
