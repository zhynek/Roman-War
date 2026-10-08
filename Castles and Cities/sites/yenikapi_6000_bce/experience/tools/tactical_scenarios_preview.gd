extends "res://tools/tactical_checks.gd"
## Explicit synthetic QA arenas. Obstacles are drawn from the actual nav mask;
## state changes only through serialized commands and production fixed ticks.
const BattleView=preload("res://src/defense_view.gd")
class FlatGround extends Node3D:
 func floor_height(_x: float,_z: float) -> float:return 0.0
var render: bool=false
var out_dir: String="/tmp/village-tactical-scenarios"
var world
var actors
var camera: Camera3D
var obstacles: MultiMeshInstance3D
var caption: Label
var status: Label
var action_button: Button
var current: Dictionary
var next_action: Dictionary
var last_error: String=""
var captures: Array=[]
func _initialize() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg=="render":render=true
  if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
 call_deferred("run")
func start(b: Dictionary) -> void:check(r.defense.control(b,{"kind":"defense_start"},r)=="","serialized start")
func command(b: Dictionary,order: String,ids: Array,at: Array=[]) -> String:
 var action: Dictionary={"kind":"defense_order","order":order,"ids":ids}
 if not at.is_empty():action.at=at
 return r.defense.control(b,action,r)
func stage() -> void:
 root.size=Vector2i(1280,800);root.content_scale_size=Vector2i(1280,800)
 if render:root.always_on_top=true;root.grab_focus()
 world=FlatGround.new();root.add_child(world)
 actors=BattleView.new();actors.world=world;root.add_child(actors)
 camera=Camera3D.new();world.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;camera.current=true
 camera.position=Vector3(8,18,23);camera.look_at(Vector3(0,0,4))
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);light.light_energy=1.2;world.add_child(light)
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("9fa7a0");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("e1dcc7");env.environment.ambient_light_energy=.8;world.add_child(env)
 actors.box(world,Vector3(0,-.11,0),actors.material("797e60"),Vector3(42,.2,42))
 obstacles=MultiMeshInstance3D.new();world.add_child(obstacles)
 var mesh=BoxMesh.new();mesh.size=Vector3(1,.65,1)
 obstacles.multimesh=MultiMesh.new();obstacles.multimesh.transform_format=MultiMesh.TRANSFORM_3D;obstacles.multimesh.mesh=mesh
 obstacles.material_override=actors.material("6b6555")
 var layer=CanvasLayer.new();root.add_child(layer)
 var top=ColorRect.new();top.color=Color(.04,.06,.05,.91);top.position=Vector2(12,12);top.size=Vector2(1256,108);layer.add_child(top)
 caption=Label.new();caption.position=Vector2(28,20);caption.size=Vector2(1210,58);caption.add_theme_font_size_override("font_size",19);layer.add_child(caption)
 action_button=Button.new();action_button.position=Vector2(28,80);action_button.size=Vector2(640,32);layer.add_child(action_button)
 action_button.pressed.connect(func():last_error=r.defense.control(current,next_action,r))
 var bottom=ColorRect.new();bottom.color=Color(.04,.06,.05,.91);bottom.position=Vector2(12,630);bottom.size=Vector2(1256,158);layer.add_child(bottom)
 status=Label.new();status.position=Vector2(28,638);status.size=Vector2(1210,145);status.add_theme_font_size_override("font_size",16);layer.add_child(status)
func show_arena(b: Dictionary,title: String,detail: String) -> void:
 current=b;caption.text="SYNTHETIC QA ARENA • "+title+"\n"+detail
 var blocked: Array=[]
 for y in range(int(b.nav.height)):
  for x in range(int(b.nav.width)):
   if b.nav.rows[y][x]=="#":blocked.append(Nav.at(b.nav,Vector2i(x,y)))
 obstacles.multimesh.instance_count=blocked.size()
 for i in range(blocked.size()):obstacles.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(float(blocked[i][0])/100.0,.325,float(blocked[i][1])/100.0)))
 draw(b,0)
func draw(b: Dictionary,delta: float=.1) -> void:
 var untouched: Dictionary=b.duplicate(true)
 actors.update(b,["watch_1","watch_2"],r.defense.content.ui,t,delta)
 check(untouched==b,"rendering never mutates tactical state")
 var lines: Array=["Tick %d  |  %s  |  %s %s  |  Last command: %s"%[b.tick,b.phase,b.outcome,b.reason,"accepted" if last_error.is_empty() else last_error]]
 for f in b.groups:
  if f.exited:continue
  lines.append("%s  %s%s  at %s  morale %d  fatigue %d  %s"%[f.id,f.order," / RETREAT" if f.routed else "",f.position,f.morale,f.tactical.fatigue,f.tactical.blocked])
 status.text="\n".join(lines)
func press(b: Dictionary,action: Dictionary,label_: String) -> void:
 current=b;next_action=action;last_error="not_triggered";action_button.text=label_;await process_frame
 if render:
  var at: Vector2=action_button.get_global_rect().get_center()
  var motion=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
  var down=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=at;down.global_position=at;root.push_input(down,true);await process_frame
  var up=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.position=at;up.global_position=at;root.push_input(up,true);await process_frame
 else:action_button.pressed.emit()
 check(last_error!="not_triggered","actual command button callback")
 draw(b,0)
func step_frame(b: Dictionary) -> void:
 r.defense.step(b,r);draw(b)
 if int(b.tick)%4==0:await process_frame
func shot(name_: String) -> void:
 if not render:return
 for i in range(5):await process_frame;RenderingServer.force_draw(true)
 check(root.get_texture().get_image().save_png(out_dir.path_join(name_+".png"))==OK,"capture "+name_);captures.append(name_+".png")
func run() -> void:
 r=Driver.rules();t=r.defense.battle_tuning({"tactics":{}});DirAccess.make_dir_recursive_absolute(out_dir);stage()
 # Opposing physical traffic must use a real passing place, not overlap.
 var b:=arena();empty_enemy_orders(b)
 for y in range(41):b.nav.rows[y]=".".repeat(41) if y==25 else "#".repeat(41)
 for y in [26,27]:b.nav.rows[y]="#".repeat(20)+".."+"#".repeat(19)
 for p in b.nav.places.values()+[b.groups[2].position,b.groups[3].position]:
  var c:=Nav.cell(b.nav,p);var row: String=b.nav.rows[c.y];b.nav.rows[c.y]=row.substr(0,c.x)+"."+row.substr(c.x+1)
 b.nav.signature=JSON.stringify(b.nav.rows).sha256_text()
 b.groups[0].position=[-600,500];b.groups[0].goal=[-600,500];b.groups[1].position=[600,500];b.groups[1].goal=[600,500]
 start(b);show_arena(b,"Opposing traffic through a narrow lane","Gray blocks are impassable; the two-cell passing place permits a physical queue.")
 await press(b,{"kind":"defense_order","order":"move","ids":["watch_1"],"at":[1100,500]},"Move the first group east through the lane")
 check(last_error=="","eastbound command through button")
 await press(b,{"kind":"defense_order","order":"move","ids":["watch_2"],"at":[-1100,500]},"Move the second group west through the same lane")
 check(last_error=="","westbound command through button")
 var yielded: bool=false;var congested: bool=false
 for i in range(500):
  await step_frame(b);check(separation(b),"lane spacing remains physical")
  congested=congested or b.groups[0].tactical.blocked=="congestion" or b.groups[1].tactical.blocked=="congestion"
  if not yielded and not b.groups[1].tactical.yield_goal.is_empty():yielded=true;await shot("01-congestion-and-passing-place")
  if b.groups[0].position==b.groups[0].goal and b.groups[1].position==b.groups[1].goal:break
 check(congested and yielded,"real congestion triggers passing-place decision")
 check(b.groups[0].position==b.groups[0].goal and b.groups[1].position==b.groups[1].goal,"both opposing orders complete")
 await shot("02-lane-orders-completed")
 # A complete wall refuses the command atomically and leaves its cause visible.
 b=arena();empty_enemy_orders(b);wall(b,20);b.groups[0].position=[-500,500];b.groups[0].goal=[-500,500];b.groups[1].position=[-700,500];b.groups[1].goal=[-700,500]
 start(b);show_arena(b,"Disconnected destination","The solid wall has no passage. The rejected command changes neither positions nor orders.")
 var previous: Dictionary=b.duplicate(true)
 await press(b,{"kind":"defense_order","order":"move","ids":["watch_1","watch_2"],"at":[900,500]},"Attempt to move both groups through the solid wall")
 check(not last_error.is_empty() and b==previous,"blocked route rejects entire batch atomically")
 await shot("03-blocked-route-rejected")
 # A blocked pursuit must close to actual melee, preserving separation.
 b=arena();start(b)
 for index in [1,3]:b.groups[index].exited=true
 b.groups[0].position=[-700,500];b.groups[0].goal=[-700,500];b.groups[0].tactical.wait=int(t.blocked_repath_ticks)
 b.groups[2].position=[700,500];b.groups[2].goal=[700,500];b.groups[2].order="hold"
 Tactical._observe(b,t);show_arena(b,"Observed target and melee approach","The attacker approaches a visible hostile position; the occupied target is not an impassable ring.")
 await press(b,{"kind":"defense_order","order":"attack","ids":["watch_1"],"target":"raider_1"},"Attack the observed raider group")
 check(last_error=="","visible pursuit command")
 for i in range(200):
  await step_frame(b);check(separation(b),"pursuit keeps separation")
  if int(b.groups[0].attack_seq)>0:break
 check(int(b.groups[0].attack_seq)>0,"pursuit reaches a real attack event")
 camera.size=12;camera.position=Vector3(10,11,16);camera.look_at(Vector3(5,0,5));draw(b,0);await shot("04-pursuit-reaches-melee")
 # Low starting morale is an explicit fixture condition; real received damage
 # crosses the normal morale threshold and fixed movement carries the retreat.
 b=arena();b.groups[0].position=[0,500];b.groups[0].goal=[0,500];b.groups[0].morale=int(t.route_morale)+1
 b.groups[1].position=[1700,1700];b.groups[1].goal=[1700,1700]
 b.groups[2].position=[150,500];b.groups[2].goal=[150,500];b.groups[2].order="hold";b.groups[2].facing=[-1000,0]
 b.groups[3].position=[-1700,-1700];b.groups[3].goal=[-1700,-1700];b.groups[3].order="hold"
 start(b);show_arena(b,"Morale failure under an actual attack","The marked resident begins shaken. A normal hit causes routing; retreat uses the normal exit route.")
 await press(b,{"kind":"defense_order","order":"hold","ids":["watch_1"]},"Hold with the shaken resident")
 var routed_from: Array=[]
 for i in range(180):
  await step_frame(b)
  if b.groups[0].routed:
   routed_from=b.groups[0].position.duplicate();break
 check(b.groups[0].routed and int(b.groups[0].hit_seq)>0,"actual hit causes morale failure")
 for i in range(25):await step_frame(b)
 check(Nav.point(routed_from).distance_to(Nav.point(b.groups[0].position))>int(t.cell_cm),"routed resident moves toward refuge")
 camera.size=18;camera.position=Vector3(7,16,23);camera.look_at(Vector3(0,0,9));draw(b,0);await shot("05-morale-break-and-retreat")
 # All groups hold beyond reach. Run the full ordinary idle clock from zero.
 b=arena();empty_enemy_orders(b)
 for f in b.groups:f.order="hold"
 start(b);show_arena(b,"Bounded stalled battle","Separated groups hold beyond melee range. The full 700-tick idle clock is simulated from zero.")
 await press(b,{"kind":"defense_order","order":"hold","ids":["watch_1","watch_2"]},"Hold without a reachable engagement")
 for i in range(int(t.idle_ticks)+1):
  await step_frame(b)
  if b.phase=="ended":break
 check(b.tick==int(t.idle_ticks) and b.reason=="unreachable" and b.outcome=="stalemate","full unchanged idle clock ends as an explicit stalemate")
 camera.size=35;camera.position=Vector3(10,28,30);camera.look_at(Vector3(0,0,0));draw(b,0);await shot("06-stalled-battle-terminates")
 print("TACTICAL SCENARIOS: ",checks," checks, ",failures," failures")
 FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"synthetic_qa_arena":true,"captures":captures,"stall_ticks":b.tick},"  "))
 quit(1 if failures else 0)
