extends RefCounted

func _game() -> Game:
 return Game.new_campaign("senate",42,"medium","long",false)

func _duel(own: String, enemy: String, distance: int = 2000) -> Game:
 var game:=_game()
 game.state.settlements.latium.garrison=[{"template":own,"strength_pct":100,"experience":0,"weapon":0,"armor":0}]
 game.data.roma_city.battle.practice_attackers=[enemy]
 game.city_battle_begin("latium",true)
 var battle:Dictionary=game.state.city_battles.latium
 battle.gate_integrity=0
 for f in battle.formations:
  f.position=[0,1000] if f.side=="defender" else [0,1000+distance]
  f.destination=f.position.duplicate()
  f.path=[]
  f.power=1000 # Isolate role rules from template price/quality in these duels.
  f.order="attack_move"
 game.city_battle_start("latium")
 return game

func test_counter_cycle_wins_actual_spatial_duels(t) -> void:
 for pair in [["roman_allied_bowmen","roman_equites"],["roman_equites","roman_hastati"],["roman_hastati","roman_allied_bowmen"]]:
  var game:=_duel(pair[0],pair[1])
  for tick in range(2500):
   if game.state.city_battles.latium.phase=="finished":break
   game.city_battle_step("latium")
  t.check_eq(game.state.city_battles.latium.result.get("winner",""),"defender","counter wins duel: "+pair[0]+" vs "+pair[1])

func test_live_move_hold_attack_and_retreat_change_positions(t) -> void:
 var game:=_game()
 game.city_battle_begin("latium",true)
 t.check(game.city_battle_command("latium",["defender_1"],"move",[-300,5700]).ok,"clear street edge connects to navigation grid")
 game.city_battle_start("latium")
 t.check(game.city_battle_command("latium",["defender_0"],"move",[-1200,2400]).ok,"free ground move accepted")
 for i in range(20):game.city_battle_step("latium")
 var f:Dictionary=game.state.city_battles.latium.formations[4]
 t.check(f.position!=[-800,1600],"formation moves continuously between ground positions")
 t.check(game.city_battle_command("latium",["defender_0"],"hold").ok,"hold accepted during fighting")
 var at:Array=f.position.duplicate()
 for i in range(10):game.city_battle_step("latium")
 t.check_eq(f.position,at,"hold stops path movement")
 t.check(game.city_battle_command("latium",["defender_0"],"attack",[],"attacker_0").ok,"explicit enemy focus accepted")
 t.check_eq(f.target_id,"attacker_0","focused target persists")
 t.check(game.city_battle_command("latium",["defender_0"],"retreat",[-1800,1800]).ok,"withdrawal replaces focused attack")
 for i in range(20):game.city_battle_step("latium")
 t.check(f.position!=at,"withdrawal actually moves the troops")
 var before:=JSON.stringify(game.state)
 t.check(not game.city_battle_command("latium",["defender_0","attacker_0"],"move",[0,2400]).ok,"mixed ownership batch rejected")
 t.check_eq(JSON.stringify(game.state),before,"failed batch is atomic")

func test_archer_fire_control_and_house_occlusion(t) -> void:
 var game:=_duel("roman_allied_bowmen","roman_hastati",2000)
 game.city_battle_command("latium",["defender_0"],"hold")
 game.city_battle_command("latium",["defender_0"],"fire")
 game.city_battle_step("latium")
 var enemy:Dictionary=game.state.city_battles.latium.formations[0]
 t.check_eq(enemy.hp,100000,"cease fire prevents ranged damage")
 game.city_battle_command("latium",["defender_0"],"fire")
 game.city_battle_step("latium")
 t.check(enemy.hp<100000,"fire at will launches damaging volleys in range")
 t.check(game.state.city_battles.latium.events.any(func(e):return e.kind=="volley"),"volley event feeds cosmetic projectiles")
 var building:Dictionary=game.data.roma_city.buildings[0]
 var center:=CityBattleNavigation.point(building.position)*100
 var half:=CityBattleNavigation.point(building.size)*50
 t.check(not CityBattleNavigation.line_clear(game.data.roma_city,CityBattleSim.rules(game.data),center-Vector2(half.x+100,0),center+Vector2(half.x+100,0),true),"arrows cannot pass through buildings")
 t.check(not CityBattleNavigation.clear(game.data.roma_city,CityBattleSim.rules(game.data),center),"orders cannot place troops inside buildings")

func test_cavalry_charge_requires_runup_and_has_recovery(t) -> void:
 var game:=_duel("roman_equites","roman_hastati",1600)
 t.check(game.city_battle_command("latium",["defender_0"],"charge",[],"attacker_0").ok,"mounted charge command accepted")
 var own:Dictionary=game.state.city_battles.latium.formations[1]
 for tick in range(100):
  game.city_battle_step("latium")
  if own.charge_cooldown_ms>0:break
 t.check(own.charge_cooldown_ms>0,"successful run-up triggers a charge and its recovery")
 t.check_eq(own.runup_cm,0,"impact consumes accumulated run-up")
 t.check(not game.city_battle_command("latium",["defender_0"],"charge",[],"missing").ok,"charge needs a living enemy")

func test_daily_recruitment_is_paid_once_and_seasons_do_not_double_train(t) -> void:
 var game:=_game()
 var count:int=game.state.settlements.latium.garrison.size()
 var treasury:int=game.state.factions.senate.treasury
 var cost:int=game.data.units.roman_allied_bowmen.cost
 t.check(game.city_queue_unit("latium","roman_allied_bowmen",true),"recruit early bowmen at Roma")
 t.check_eq(game.state.factions.senate.treasury,treasury-cost,"recruitment charges shared treasury once")
 RecruitmentRules.advance_queues(game.data,game.state,"latium")
 t.check_eq(game.state.settlements.latium.garrison.size(),count,"season cannot prematurely finish daily training")
 var loaded:=SaveGame.from_json(SaveGame.to_json(game.state))
 t.check(not loaded.is_empty(),"in-progress daily training saves")
 for i in range(2):game.city_advance_day("latium")
 t.check_eq(game.state.settlements.latium.garrison.size(),count,"training waits its full duration")
 game.city_advance_day("latium")
 t.check_eq(game.state.settlements.latium.garrison.size(),count+1,"third civic day delivers actual archers")
 game.city_advance_day("latium")
 t.check_eq(game.state.settlements.latium.garrison.size(),count+1,"completed cohort is not duplicated")

func test_malformed_realtime_state_is_rejected(t) -> void:
 var game:=_game()
 game.city_battle_begin("latium",true)
 for field in ["position","hp","path","speed","role","city_days_left"]:
  var state:=game.state.duplicate(true)
  var b:Dictionary=state.city_battles.latium
  match field:
   "position":b.formations[0].position=[0,"bad"]
   "hp":b.formations[0].hp=200000
   "path":b.formations[0].path=[[0,0],{}]
   "speed":b.speed=1.5
   "role":b.formations[0].role="tank"
   "city_days_left":state.settlements.latium.recruitment_queue=[{"city_days_left":-1}]
  t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(),"reject malformed continuous state: "+field)

func test_legacy_battle_migrates_without_restoring_casualties(t) -> void:
 var game:=_game()
 game.city_battle_begin("latium",true)
 var b:Dictionary=game.state.city_battles.latium
 for key in ["model_version","paused","speed","elapsed_ms","capture_ms","events","event_seq","layout_signature"]:b.erase(key)
 b.formations[0].unit.strength_pct=65
 for f in b.formations:
  for key in ["position","goal","destination","path","role","order","target_id","fire_at_will","hp","soldiers","revealed","cooldown_ms","charge_cooldown_ms","runup_cm","facing","morale","routed","engaged","moving","power","attack_seq"]:f.erase(key)
 var loaded:=SaveGame.from_json(SaveGame.to_json(game.state))
 NewGame.ensure_state_keys(loaded,game.data)
 t.check_eq(loaded.city_battles.latium.model_version,2,"old tactical save upgrades additively")
 t.check_eq(loaded.city_battles.latium.formations[0].hp,65000,"migration retains battle casualties")
 t.check(loaded.city_battles.latium.paused,"migrated battle starts paused for commander")
 t.check(not SaveGame.from_json(SaveGame.to_json(loaded)).is_empty(),"migrated battle passes the new save boundary")

func test_full_armies_spawn_on_reachable_ground(t) -> void:
 var game:=_game()
 var templates:Array=[]
 for i in range(20):templates.append("tribal_warband")
 game.data.roma_city.battle.practice_attackers=templates
 game.city_battle_begin("latium",true)
 for f in game.state.city_battles.latium.formations:
  t.check(CityBattleNavigation.clear(game.data.roma_city,CityBattleSim.rules(game.data),CityBattleNavigation.point(f.position)),"full army formation starts on actual traversable ground")
  if f.side=="attacker":t.check(not f.path.is_empty(),"full army cohort has a route through the gate")

func test_attack_move_resumes_its_ground_goal_after_contact(t) -> void:
 var game:=_duel("roman_hastati","roman_equites",2000)
 game.city_battle_command("latium",["defender_0"],"attack_move",[0,6500])
 game.city_battle_step("latium")
 var b:Dictionary=game.state.city_battles.latium
 var own:Dictionary=b.formations[1]
 t.check_eq(own.goal,[0,6500],"engaging an enemy retains the original ground order")
 t.check(own.destination!=own.goal,"attack move temporarily pursues the enemy")
 # Move the opponent outside acquisition range, as a withdrawing cohort.
 b.formations[0].position=[-6000,-4000]
 b.formations[0].order="hold"
 b.formations[0].path=[]
 game.city_battle_step("latium")
 t.check_eq(own.destination,own.goal,"after contact breaks, troops continue to commanded ground")

func test_movement_reaches_exact_corners_at_gate_without_stalling(t) -> void:
 var game:=_game()
 game.city_battle_begin("latium",true)
 game.city_battle_command("latium",["defender_0"],"move",[200,7300])
 game.city_battle_start("latium")
 var b:Dictionary=game.state.city_battles.latium
 b.gate_integrity=0
 for f in b.formations:
  if f.side=="attacker":
   f.position=[-2000,8600]
   f.order="hold"
   f.path=[]
 t.check(game.city_battle_command("latium",["defender_0"],"move",[400,8200]).ok,"command can pass through opened gate")
 for i in range(100):game.city_battle_step("latium")
 var own:Dictionary=b.formations[4]
 t.check_eq(own.position,[400,8200],"formation reaches the exact bend before turning, without rounding into the wall")
