extends SceneTree
## Real rendered input, continuous runtime, town recruitment and battle replay.
## QA captures remain outside the repository.
var city: RomaCityScreen
var failed := false
var out := "/tmp/roman-war-city-battle-live"

func _init() -> void:
 ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
 ProjectSettings.set_setting("application/config/custom_user_dir_name","Roman War Live Battle QA/%d"%OS.get_process_id())
 DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("out_dir="):out=arg.trim_prefix("out_dir=")
 _run.call_deferred()

func _run() -> void:
 root.mode=Window.MODE_WINDOWED
 root.size=Vector2i(1280,800)
 root.grab_focus()
 DirAccess.make_dir_recursive_absolute(out)
 city=RomaCityScreen.new()
 city.standalone=true
 city.game=Game.new_campaign("senate",42,"medium","long",false)
 root.add_child(city)
 await _frames(12)
 var before:=city.garrison_view.groups.size()
 # Test fixture provides the real campaign stables prerequisite.
 for chain in city.game.data.chains.values():
  if chain.get("kind","")=="stables" and chain.get("cultures",[]).has("roman"):
   city.game.state.settlements.latium.buildings[chain.id]=1
   break
 await _recruit("roman_allied_bowmen")
 for i in range(3):city.game.city_advance_day("latium")
 await _recruit("roman_equites")
 for i in range(3):city.game.city_advance_day("latium")
 city.refresh_city()
 _check(city.garrison_view.groups.size()==before+2,"new archer and cavalry formations appear in town")
 city.overview=true
 city.camera.current=false
 city.survey_camera.current=true
 city.survey_camera.position=Vector3(65,34,35)
 city.survey_camera.look_at(Vector3(43,0,0))
 city.survey_camera.size=42
 await _frames(12)
 await _shot("00-town-recruited-troops")
 var original:=_canon(city.game.state.settlements.latium.garrison)
 await _click(city.battle_button)
 var panel:=city.battle_panel
 await _shot("01-siege-command")
 await _click(panel.practice_button)
 _check(panel.snapshot.get("phase","")=="deployment","practice opens deployment")
 # Actual ground gestures on the tactical plan, with independent cohort orders.
 for f in panel.snapshot.formations:
  if f.side!="defender":continue
  panel.select_formation(f.id)
  var at:=Vector2(0,59) if f.role=="soldier" else Vector2(0,41) if f.role=="archer" else Vector2(0,24)
  if f.id=="defender_1":at=Vector2(-3,57)
  if f.id=="defender_2":at=Vector2(3,55)
  if f.id=="defender_3":at=Vector2(0,52)
  await _click_point(panel.plan.global_position+panel.plan.map_point(at),MOUSE_BUTTON_RIGHT)
  _check(CityBattleNavigation.point(panel.selected_formation().position).distance_to(at*100)<10,"ground gesture deploys "+f.id)
 panel.select_formation("defender_4")
 await _shot("02-deployment")
 await _click(panel.inspect_button)
 await _frames(36)
 await _shot("03-archer-inspection")
 root.size=Vector2i(1600,900)
 await _frames(8)
 await _shot("04-resized-inspection")
 root.size=Vector2i(1280,800)
 await _frames(8)
 await _click(panel.inspect_button)
 await _click(panel.start_button)
 await create_timer(1.2).timeout
 panel.refresh()
 _check(panel.snapshot.tick>5,"battle advances automatically without a step button")
 await _click(panel.step_button)
 var paused:=panel.host.snapshot()
 await create_timer(0.3).timeout
 _check(panel.host.snapshot().tick==paused.tick,"Pause stops exact simulation time")
 await _click(panel.save_button)
 var saved_tick:int=panel.snapshot.tick
 city.load_city()
 await _frames(8)
 _check(panel.visible and panel.snapshot.tick==saved_tick and panel.snapshot.paused,"save restores exact paused battle")
 await _click(panel.step_button)
 await _click(panel.speed_button)
 var breach:=false
 var combat:=false
 var start:=Time.get_ticks_msec()
 while panel.host.snapshot().get("phase","")=="fighting" and Time.get_ticks_msec()-start<210000:
  await create_timer(0.3).timeout
  panel.refresh()
  if not breach and panel.snapshot.gate_integrity<=0:
   breach=true
   await _shot("05-gate-breach")
   panel.select_formation("defender_5")
   panel._choose_order("charge")
   # Clicking the enemy marker submits a targeted charge during live combat.
   if panel.plan.formation_points.has("attacker_0"):
    await _click_point(panel.plan.global_position+panel.plan.formation_points.attacker_0,MOUSE_BUTTON_RIGHT)
   _check(panel.selected_formation().get("order","")=="charge","live enemy gesture issues cavalry charge")
  if not combat and int(panel.snapshot.elapsed_ms)>16000:
   combat=true
   panel.select_formation("defender_0")
   await _click(panel.order_buttons.attack_move)
   # Use empty ground away from the approaching enemy markers. The wider
   # plan deliberately interprets right-clicking an enemy as focus attack.
   await _click_point(panel.plan.global_position+panel.plan.map_point(Vector2(0,24)),MOUSE_BUTTON_RIGHT)
   _check(panel.selected_formation().get("order","")=="attack_move","live ground gesture issues attack move")
   await _click(panel.inspect_button)
   await _frames(36)
   await _shot("06-street-combat")
   # Commit the reserve soldiers as a group after viewing the engagement.
   panel.selected_ids=["defender_0","defender_1","defender_2","defender_3"]
   panel._issue("attack_move",[0,7000])
   _check(panel.message_label.text==panel.w("command_selection") % [panel.w("attack_move"), 4],"group attack order accepted")
 panel.host.stop()
 panel.refresh()
 _check(panel.snapshot.get("phase","")=="finished","full continuous battle reaches a result")
 _check(breach,"assault breaches the actual city gate")
 _check(_canon(city.game.state.settlements.latium.garrison)==original,"practice preserves actual trained garrison")
 await _shot("07-battle-result")
 await _click(panel.close_button)
 _check(not panel.visible and not city.game.city_battle_status("latium").active,"close report returns to town")
 if panel.visible:print("CLOSE DIAGNOSTIC ",panel.snapshot.get("phase")," ",panel.message_label.text)
 print("CITY BATTLE LIVE PLAYTEST ","FAILED" if failed else "PASSED"," · ",out)
 city.free()
 quit(1 if failed else 0)

func _click(control: Control) -> void:
 await _frames(2)
 _check(control.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(control.get_global_rect()),"command visible within window: "+control.text)
 await _click_point(control.get_global_rect().get_center())

func _click_point(point: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
 Input.warp_mouse(point)
 var motion:=InputEventMouseMotion.new()
 motion.position=point
 motion.global_position=point
 root.push_input(motion)
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new()
  event.button_index=button
  event.pressed=pressed
  event.position=point
  event.global_position=point
  root.push_input(event)
  await _frames(2)
 await _frames(4)

func _shot(name: String) -> void:
 RenderingServer.force_draw(false)
 root.get_texture().get_image().save_png(out.path_join(name+".png"))

func _frames(count: int) -> void:
 for i in range(count):await process_frame

func _check(ok: bool,description: String) -> void:
 print("PASS " if ok else "FAIL ",description)
 failed=failed or not ok

func _canon(value: Variant) -> String:
 return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func _recruit(template: String) -> void:
 city.open_drawer("barracks")
 city._choose_dossier_tab("troops")
 var recruit:Button
 for child in city.drawer_body.get_children():
  if child is Button and child.text==city.w("troops_recruit")%city.game.data.units[template].name:recruit=child
 _check(recruit!=null,"barracks displays recruitment for "+template)
 if recruit!=null:
  await city._scroll_to_control(recruit)
  await _frames(4)
  await _shot("recruit-"+template)
  await _click(recruit)
  _check(city.game.state.settlements.latium.recruitment_queue.any(func(job):return job.template==template),"actual barracks button queues "+template)
 city.drawer.hide()
