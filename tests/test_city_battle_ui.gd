extends RefCounted

func _city() -> RomaCityScreen:
 var city := RomaCityScreen.new()
 city.standalone=false
 city.game=Game.new_campaign("senate",42,"medium","long",false)
 (Engine.get_main_loop() as SceneTree).root.add_child(city)
 return city

func test_battle_view_restore_and_refresh_are_presentation_only(t) -> void:
 var city:=_city()
 var view:=city.battle_panel
 var before:=JSON.stringify(city.game.state)
 var camera_transform:=city.survey_camera.transform
 view.open()
 t.check(view.visible and city.survey_camera.current,"battle uses Roma's actual camera and city")
 t.check(not city.command_bar.visible and not city.citizens.visible,"command view owns input")
 view.refresh()
 view.close()
 t.check_eq(JSON.stringify(city.game.state),before,"ready view cannot change campaign")
 t.check(city.command_bar.visible and city.camera.current and city.citizens.visible,"street controls restore")
 t.check_eq(city.survey_camera.transform,camera_transform,"city camera restores")
 city.free()

func test_worker_advances_without_frames_and_pause_is_exact(t) -> void:
 var city:=_city()
 var view:=city.battle_panel
 view.open()
 view.begin(true)
 var id:=view.selected
 view.order_to("gate_street")
 t.check_eq(view.selected_formation()["position"],[0,5900],"deploy command uses real ground coordinates")
 view.start()
 # This suite runs synchronously inside one frame: only the runtime worker
 # can advance the simulation while the main thread is blocked here.
 OS.delay_msec(350)
 view.host.invoke("control",["pause"])
 view.refresh()
 t.check(int(view.snapshot.tick)>=2,"runtime clock advances while no UI frame runs")
 var before:=JSON.stringify(city.game.state)
 view.select_formation(id)
 view.toggle_inspect()
 view.forces._process(1.0)
 view._process(1.0)
 OS.delay_msec(150)
 t.check_eq(JSON.stringify(city.game.state),before,"paused simulation is unaffected by rendering and elapsed wall time")
 view.close()
 view.open()
 t.check_eq(JSON.stringify(city.game.state),before,"leaving and reopening preserves paused simulation")
 view.dismiss_session()
 city.free()

func test_hidden_enemy_models_do_not_use_roster_or_equipment(t) -> void:
 var city:=_city()
 var view:=city.battle_panel
 view.open()
 view.begin(true)
 var live:=JSON.stringify(city.game.state)
 var mesh:Mesh=view.forces._meshes["enemy_unknown"]
 var count:int=view.forces.groups["attacker_0"].get_node("Troops").multimesh.instance_count
 var altered:=view.snapshot.duplicate(true)
 for f in altered.formations:
  if f.side=="attacker":
   f.template="elephant"
   f.unit.template="elephant"
   f.unit.armor=99
   f.soldiers=999
   f.unit.strength_pct=3
   f.role="cavalry"
 view.forces.sync(city.layout,altered)
 t.check(view.forces._meshes["enemy_unknown"]==mesh,"hidden classes and equipment cannot alter enemy representation")
 t.check_eq(view.forces.groups["attacker_0"].get_node("Troops").multimesh.instance_count,count,"unseen roster size cannot alter its generic silhouette")
 t.check_eq(JSON.stringify(city.game.state),live,"detached display cannot write battle state")
 city.free()

func test_recruited_archers_and_cavalry_are_visible_in_town(t) -> void:
 var city:=_city()
 var count:=city.garrison_view.groups.size()
 t.check(city.game.city_queue_unit("latium","roman_allied_bowmen",true),"Roma barracks accepts bowmen")
 for day in range(3): city.game.city_advance_day("latium")
 city.refresh_city()
 t.check_eq(city.garrison_view.groups.size(),count+1,"completed recruitment adds a real visible formation")
 t.check(city.garrison_view._meshes.has("own_archer"),"bowmen use visible bow equipment")
 city.game.state.settlements.latium.garrison.append({"template":"roman_equites","experience":0,"strength_pct":100,"weapon":0,"armor":0})
 city.refresh_city()
 t.check(city.garrison_view._meshes.has("own_cavalry"),"mounted units appear as cavalry in town")
 t.check(not SaveGame.from_json(SaveGame.to_json(city.game.state)).is_empty(),"daily recruiting remains saveable")
 city.free()

func test_barracks_exposes_and_wires_archer_recruitment(t) -> void:
 var city:=_city()
 city.standalone=true
 city.open_drawer("barracks")
 city._choose_dossier_tab("troops")
 var recruit:Button
 for child in city.drawer_body.get_children():
  if child is Button and child.text==city.w("troops_recruit")%city.game.data.units.roman_allied_bowmen.name:recruit=child
 t.check(recruit!=null,"new bowmen are reachable through the actual barracks UI")
 if recruit!=null:
  t.check(not recruit.disabled,"eligible bowmen can be recruited")
  recruit.pressed.emit()
  var queue:Array=city.game.state.settlements.latium.recruitment_queue
  t.check_eq(queue.back().template,"roman_allied_bowmen","actual recruit button queues bowmen")
  t.check_eq(queue.back().city_days_left,3,"standalone button uses civic days")
 city.free()
