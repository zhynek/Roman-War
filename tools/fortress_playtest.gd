extends SceneTree
## Original renderer QA; images and isolated saves remain outside the repo.
var city: RomaCityScreen
var failed:=false
var out:="/tmp/roman-war-fortress-qa"

func _init() -> void:
	preload("res://tools/render_qa_storage.gd").configure("Roman War Fortress QA/%d" % OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out=arg.trim_prefix("out_dir=")
	_run.call_deferred()

func _run() -> void:
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1280,800)
	root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out)
	city=RomaCityScreen.new();city.standalone=false
	root.add_child(city)
	await _frames(10)
	var original:=JSON.stringify(city.game.state)
	city.open_defenses()
	await _shot("01-defense-inspection")
	for point in city.game.data.city_governance.defense_inspections:
		city.visit_defense(point)
		await _frames(4)
		_check(Vector2(city.player.position.x,city.player.position.z).distance_to(Vector2(point.position[0],point.position[1]))<2,"inspection point reachable: "+point.id)
		await _shot("02-inspect-"+point.id)
	_check(JSON.stringify(city.game.state)==original,"inspection and relocation leave campaign and RNG unchanged")
	city.open_defenses()
	await _click_text(city.drawer_body,city.w("action_reinforce_gate"))
	await _click_text(city.drawer_body,city.w("action_prepare_fire_arrows"))
	_check(city.status.projects.reinforce_gate.remaining>0,"inspection button funds actual gate work")
	city.drawer.hide()
	_check(city.game.city_queue_unit("latium","roman_allied_bowmen",true),"archers recruited for actual garrison")
	for i in range(4):city.game.city_advance_day("latium")
	city.refresh_city()
	_check(city.world.gate_reinforcement.visible,"completed work appears on gate")
	city.visit_defense(city.game.data.city_governance.defense_inspections[0])
	await _shot("03-reinforced-gate")
	city.open_battle()
	var panel:=city.battle_panel
	await _click_text(panel,panel.w("practice"))
	if not panel.snapshot.get("active",false):
		_check(false,"practice siege opens");city.free();quit(1);return
	var archer:=""
	for f in panel.snapshot.formations:
		if f.side=="defender" and f.role=="archer":archer=f.id
	_check(archer!="","recruited bowmen enter defense")
	panel.select_formation(archer)
	panel._issue("move",[0,6800])
	await _click_text(panel,panel.w("attack_engine"))
	await _click_text(panel,panel.w("fire_arrows"))
	_check(panel.selected_formation().get("incendiary",false),"fire-arrow button changes the actual order")
	_check(panel.selected_formation().target_id=="siege_ram","target button orders fire at the ram")
	# Deterministic explicit ticks permit exact visual acceptance moments. The
	# runtime worker remains stopped; frames never generate combat outcomes.
	city.game.city_battle_start("latium")
	var gate_start:int=city.game.state.city_battles.latium.gate_integrity
	for i in range(35):city.game.city_battle_step("latium")
	panel.refresh()
	_check(panel.snapshot.siege_engine.burning,"real archers ignite the siege ram")
	city.survey_camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	city.survey_camera.position=Vector3(14,11,92)
	city.survey_camera.look_at(Vector3(0,2.5,81))
	panel.set_process(false)
	await _frames(20)
	await _shot("04-burning-siege-ram")
	# Show the full arrow trajectory from the defenders toward the machine.
	city.survey_camera.position=Vector3(18,20,68)
	city.survey_camera.look_at(Vector3(0,4,78))
	for i in range(12):city.game.city_battle_step("latium")
	panel.refresh()
	await _frames(8)
	await _shot("05-fire-arrow-volley")
	for i in range(220):
		if city.game.state.city_battles.latium.phase=="finished":break
		city.game.city_battle_step("latium")
	panel.refresh()
	_check(int(panel.snapshot.siege_engine.hp)==0,"ram burns down through simulation")
	_check(int(panel.snapshot.gate_integrity)<gate_start,"assault damages actual gate")
	city.survey_camera.position=Vector3(13,7,85)
	city.survey_camera.look_at(Vector3(0,1.3,79))
	await _frames(20)
	await _shot("06-destroyed-ram")
	# Continue the real assault until incoming troops take casualties.
	for i in range(1800):
		if city.game.state.city_battles.latium.phase=="finished":break
		city.game.city_battle_step("latium")
		if i%5==0:panel.refresh();await _frames(1)
	panel.refresh()
	city.survey_camera.position=Vector3(15,12,32)
	city.survey_camera.look_at(Vector3(0,1,22))
	await _frames(10)
	await _shot("07-troop-impacts")
	_check(not panel.forces._fallen.is_empty(),"resolved losses leave visible fallen representatives")
	city.free()
	print("FORTRESS PLAYTEST ","FAILED" if failed else "PASSED"," · ",out)
	quit(1 if failed else 0)

func _click_text(parent: Node,text: String) -> void:
	var found:=_find_button(parent,text)
	_check(found!=null,"button available: "+text)
	if found==null:return
	await city._scroll_to_control(found)
	await _frames(3)
	var point:=found.get_global_rect().get_center()
	Input.warp_mouse(point)
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion)
	await _frames(2)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
		root.push_input(event)
		await _frames(2)

func _find_button(parent: Node,text: String) -> Button:
	if parent is Button and parent.text==text and parent.is_visible_in_tree():return parent
	for child in parent.get_children():
		var found:=_find_button(child,text)
		if found!=null:return found
	return null

func _frames(count: int) -> void:
	for i in range(count):await process_frame

func _shot(name: String) -> void:
	await _frames(3)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out.path_join(name+".png"))

func _check(ok: bool,description: String) -> void:
	print("PASS " if ok else "FAIL ",description)
	failed=failed or not ok
