extends RefCounted

func _game() -> Game:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	game.city_battle_drill("latium")
	return game

func _own(game: Game, index: int = 0) -> Dictionary:
	for f in game.state.city_battles.latium.formations:
		if f.id=="defender_%d"%index:return f
	return {}

func _isolate(game: Game) -> void:
	var b: Dictionary=game.state.city_battles.latium
	b.gate_integrity=0
	for f in b.formations:
		f.position=[0,1000] if f.side=="defender" else [0,6000]
		f.destination=f.position.duplicate();f.goal=f.position.duplicate();f.path=[];f.order="hold"

func test_drill_supplies_trained_combined_arms_without_campaign_cost(t) -> void:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	var before:=game.state.duplicate(true)
	t.check(game.city_battle_drill("latium").ok,"drill is accessible through facade")
	t.check(CityBattleTactics.phalanx_eligible(game.data,_own(game)),"drill starts with trained hoplites")
	t.check_eq(_own(game,1).role,"cavalry","drill supplies cavalry")
	t.check_eq(_own(game,2).role,"archer","drill supplies archers")
	t.check_eq(game.state.settlements,before.settlements,"drill never alters garrison or recruitment")
	t.check_eq(game.state.rng_state,before.rng_state,"drill consumes no RNG")

func test_split_preserves_health_capacity_cooldowns_and_campaign_unit_count(t) -> void:
	var game:=_game();_isolate(game)
	var f:=_own(game)
	f.hp=81123;f.unit.strength_pct=82;f.cooldown_ms=800;f.charge_cooldown_ms=5000
	var health:=int(f.hp)
	t.check(game.city_battle_command("latium",[f.id],"split").ok,"unengaged battalion splits")
	var hp:=0;var capacity:=0;var parts:=0
	for part in game.state.city_battles.latium.formations:
		if part.source_id!=f.source_id:continue
		hp+=int(part.hp);capacity+=int(part.initial_strength);parts+=1
		t.check_eq(part.cooldown_ms,800,"cannot reset weapon cooldown by splitting")
		t.check_eq(part.charge_cooldown_ms,5000,"cannot reset charge recovery")
	t.check_eq(hp,health,"health conserved exactly, including fractions")
	t.check_eq(capacity,100,"source capacity conserved")
	t.check_eq(parts,3,"exactly three independent platoons")
	var survivors:=CityBattleTactics.survivors(game.state.city_battles.latium,"defender")
	t.check_eq(survivors.size(),3,"three original battalions restored")
	t.check_eq(survivors[0].strength_pct,82,"aggregate rounding cannot create strength")
	t.check(not SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(),"split state passes save boundary")
	var saved:=JSON.stringify(game.state)
	t.check_eq(game.city_battle_command("latium",[f.id],"split").reason,"cannot_split","no recursive split exploit")
	t.check_eq(JSON.stringify(game.state),saved,"rejected split atomic")

func test_training_and_mixed_selection_are_atomic(t) -> void:
	var game:=_game()
	var before:=JSON.stringify(game.state)
	t.check_eq(game.city_battle_command("latium",["defender_0","defender_1"],"phalanx").reason,"phalanx_training","horses cannot form phalanx")
	t.check_eq(JSON.stringify(game.state),before,"invalid batch cannot partially form hoplites")
	_own(game).unit.experience=0
	t.check_eq(game.city_battle_command("latium",["defender_0"],"phalanx").reason,"phalanx_training","raw recruits lack formation discipline")

func test_reform_clock_movement_and_bounded_turning(t) -> void:
	var game:=_game();_isolate(game)
	game.city_battle_start("latium")
	game.city_battle_command("latium",["defender_0"],"phalanx")
	var f:=_own(game)
	t.check_eq(f.reform_ms,3000,"live reform has real cost")
	t.check_eq(CityBattleTactics.speed_multiplier(game.data,f),0.25,"disordered movement is slow")
	var frozen:=JSON.stringify(game.state)
	game.city_battle_status("latium");game.city_battle_status("latium")
	t.check_eq(JSON.stringify(game.state),frozen,"queries cannot advance clocks")
	for i in range(30):game.city_battle_step("latium")
	t.check_eq(f.reform_ms,0,"formation ready after exactly three seconds")
	t.check_eq(CityBattleTactics.speed_multiplier(game.data,f),0.45,"formed phalanx slows movement")
	game.city_battle_command("latium",[f.id],"face",[0,-3000])
	var old:=CityBattleNavigation.point(f.facing)
	game.city_battle_step("latium")
	t.check(absf(rad_to_deg(old.angle_to(CityBattleNavigation.point(f.facing))))<2.0,"phalanx cannot spin instantly")
	t.check(CityBattleNavigation.point(f.facing).y>0,"rear remains exposed during wheel")

func test_front_phalanx_beats_charge_but_rear_cavalry_is_dangerous(t) -> void:
	var game:=_game();_isolate(game)
	var spear:=_own(game);var horse:=_own(game,1)
	spear.position=[0,1000];spear.facing=[0,1000];horse.position=[0,1300];horse.facing=[0,-1000]
	var plain:=CityBattleTactics.damage_multiplier(game.data,horse,spear,true)
	game.city_battle_command("latium",[spear.id],"phalanx")
	var front:=CityBattleTactics.damage_multiplier(game.data,horse,spear,true)
	t.check(front<plain*0.3,"frontal spears resist and cancel impact")
	var spear_attack:=CityBattleTactics.damage_multiplier(game.data,spear,horse,false)
	t.check(spear_attack>1,"formed frontal attack improves")
	horse.position=[0,700]
	var rear:=CityBattleTactics.damage_multiplier(game.data,horse,spear,true)
	t.check(rear>front*8,"cavalry behind a phalanx is dangerous")
	t.check(CityBattleTactics.damage_multiplier(game.data,spear,horse,false)<1,"spears cannot use frontal attack bonus backwards")

func test_frontage_is_atomic_has_unique_slots_and_persistent_facing(t) -> void:
	var game:=_game();_isolate(game)
	game.city_battle_command("latium",["defender_0"],"split")
	var ids: Array=["defender_0","defender_0_p2","defender_0_p3"]
	var result:=game.city_battle_command("latium",ids,"assault_line",[-700,1000,700,1000])
	t.check(result.ok,"drag frontage assigns clear square slots")
	var positions: Array=[]
	for f in game.state.city_battles.latium.formations:
		if not ids.has(f.id):continue
		t.check(not positions.has(f.position),"each platoon receives separate ground")
		positions.append(f.position)
		t.check_eq(f.facing,[0,1000],"drag direction defines frontage facing")
	var before:=JSON.stringify(game.state)
	t.check(not game.city_battle_command("latium",ids,"assault_line",[0,0,100,0]).ok,"too little frontage refused")
	t.check_eq(JSON.stringify(game.state),before,"no partial deployment on failed batch")

func test_split_does_not_multiply_damage_or_prematurely_rout(t) -> void:
	var game:=_game();_isolate(game)
	var whole:=_own(game).duplicate(true);var enemy: Dictionary=game.state.city_battles.latium.formations[0]
	whole.position=[0,1000];enemy.position=[0,1300];enemy.facing=[0,-1000]
	var full:=CityBattleTactics.damage_multiplier(game.data,whole,enemy,false)
	enemy.position=[0,6000]
	game.city_battle_command("latium",["defender_0"],"split")
	enemy.position=[0,1300]
	var divided:=0.0
	for f in game.state.city_battles.latium.formations:
		if f.source_id==whole.source_id:divided+=CityBattleTactics.damage_multiplier(game.data,f,enemy,false)
	t.check(absf(full-divided)<0.00001,"three platoons deal same aggregate damage budget")
	enemy.position=[0,6000]
	game.city_battle_start("latium");game.city_battle_step("latium")
	t.check(_own(game).morale>=99,"full platoon retains full morale despite smaller strength share")

func test_mid_reform_split_save_replays_and_malformed_extensions_reject(t) -> void:
	var game:=_game();_isolate(game)
	game.city_battle_command("latium",["defender_0"],"split")
	game.city_battle_start("latium")
	game.city_battle_command("latium",["defender_0"],"phalanx")
	for i in range(8):game.city_battle_step("latium")
	var saved:=SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not saved.is_empty(),"mid-reform platoon save accepted")
	for i in range(45):game.city_battle_step("latium")
	var expected:=JSON.stringify(JSON.parse_string(SaveGame.to_json(game.state)))
	game.state=saved;NewGame.ensure_state_keys(game.state,game.data)
	for i in range(45):game.city_battle_step("latium")
	t.check_eq(JSON.stringify(JSON.parse_string(SaveGame.to_json(game.state))),expected,"fixed tick replay exact after split and reform")
	for fault in ["orphan","capacity","part","facing","clock","source","partial"]:
		var bad:=game.state.duplicate(true);var b: Dictionary=bad.city_battles.latium
		var f: Dictionary=b.formations[-1]
		match fault:
			"orphan":b.erase("tactics_version")
			"capacity":f.initial_strength+=1
			"part":f.platoon=2
			"facing":f.facing_goal=[0,0]
			"clock":f.reform_ms=-1
			"source":f.source_id="attacker_0"
			"partial":f.erase("formation")
		t.check(SaveGame.from_json(SaveGame.to_json(bad)).is_empty(),"malformed tactics rejected: "+fault)

func test_legacy_battle_retains_old_rules(t) -> void:
	var game:=_game();var b: Dictionary=game.state.city_battles.latium
	b.erase("tactics_version")
	for f in b.formations:
		for key in ["source_id","source_strength","platoon","formation","reform_ms","ai_reform_ms","facing_goal","facing_locked"]:f.erase(key)
	var loaded:=SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not loaded.is_empty(),"legacy session still loads")
	NewGame.ensure_state_keys(loaded,game.data);game.state=loaded
	t.check(not loaded.city_battles.latium.has("tactics_version"),"legacy balance is not silently upgraded")
	t.check_eq(game.city_battle_command("latium",["defender_0"],"phalanx").reason,"no_tactics","old session explains unavailable feature")

func test_real_siege_recombines_platoons_and_commits_once(t) -> void:
	var game:=preload("res://tests/test_city_battle_campaign.gd").new()._ready_siege()
	game.city_battle_begin("latium",false)
	var b: Dictionary=game.state.city_battles.latium
	var before_count:int=game.state.settlements.latium.garrison.size()
	t.check(game.city_battle_command("latium",["defender_0"],"split").ok,"real garrison splits through public command")
	var source_hp:=0
	for f in b.formations:
		if f.source_id=="defender_0":
			f.hp-=1234;f.unit.strength_pct=ceili(float(f.hp)/1000);source_hp+=int(f.hp)
		if f.side=="attacker":f.hp=0;f.unit.strength_pct=0
	game.city_battle_start("latium");game.city_battle_step("latium")
	t.check(b.committed,"tactical victory commits through resolver")
	t.check_eq(game.state.settlements.latium.garrison.size(),before_count,"campaign cannot gain extra unit slots by splitting")
	t.check_eq(game.state.settlements.latium.garrison[0].strength_pct,ceili(float(source_hp)/1000),"campaign receives exact combined platoon casualties")
	t.check_eq(b.result.defender_report.size(),before_count,"report remains one row per original unit")
	var finished:=JSON.stringify(game.state)
	t.check(not game.city_battle_step("latium").ok,"finished battle cannot commit twice")
	t.check_eq(JSON.stringify(game.state),finished,"no second losses or rewards")
	t.check(not SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(),"committed split battle saves")

func test_actual_ticks_resolve_rear_damage_without_array_order_bias(t) -> void:
	var game:=_game();_isolate(game)
	var b:Dictionary=game.state.city_battles.latium
	var own:=_own(game)
	game.city_battle_command("latium",[own.id],"phalanx")
	game.city_battle_command("latium",[own.id],"face",[0,3000])
	var enemy: Dictionary=b.formations[0]
	enemy.position=[0,1300];enemy.role="cavalry";enemy.order="charge";enemy.runup_cm=1000
	game.city_battle_start("latium")
	var start:=game.state.duplicate(true)
	game.city_battle_step("latium")
	var front_loss:=100000-int(own.hp)
	game.state=start.duplicate(true)
	game.state.city_battles.latium.formations[0].position=[0,700]
	game.city_battle_step("latium")
	var rear_loss:=100000-int(_own(game).hp)
	t.check(rear_loss>front_loss*6,"rear cavalry advantage reaches actual health resolution")
	var expected:int=_own(game).hp
	game.state=start.duplicate(true)
	game.state.city_battles.latium.formations[0].position=[0,700]
	game.state.city_battles.latium.formations.reverse()
	game.city_battle_step("latium")
	t.check_eq(_own(game).hp,expected,"damage reads the same pre-tick facing in either iteration order")

func test_enemy_phalanx_and_cavalry_use_live_orders(t) -> void:
	var game:=_game();_isolate(game)
	var b:Dictionary=game.state.city_battles.latium
	var enemy:Dictionary=b.formations[0]
	enemy.template="chosen_hoplites";enemy.unit.template="chosen_hoplites";enemy.unit.experience=2
	enemy.position=[0,3000];enemy.order="attack_move"
	game.city_battle_start("latium");game.city_battle_step("latium")
	t.check_eq(enemy.formation,"phalanx","trained AI spears form before closing")
	t.check_eq(enemy.reform_ms,2900,"AI pays same reform time")
	enemy.role="cavalry";enemy.formation="line";enemy.reform_ms=0;enemy.order="attack_move"
	game.city_battle_step("latium")
	t.check_eq(enemy.order,"charge","enemy horses receive a real charge order")
	t.check(enemy.runup_cm>0,"AI charge accumulates actual travel")

func test_frontage_retains_move_and_retreat_modes(t) -> void:
	var game:=_game();_isolate(game)
	game.city_battle_start("latium")
	for mode in ["move","retreat","attack_move"]:
		t.check(game.city_battle_command("latium",["defender_0"],"assault_line",[-700,2000,700,2000],mode).ok,"mode-aware frontage accepted")
		t.check_eq(_own(game).order,mode,"drag retains chosen movement intent")

func test_drill_works_without_garrison_but_preserves_ownership(t) -> void:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	game.state.settlements.latium.garrison=[]
	t.check(game.city_battle_status("latium").can_drill,"supplied troops make empty-garrison drill available")
	t.check(not game.city_battle_status("latium").can_practice,"ordinary garrison practice still needs actual troops")
	t.check(game.city_battle_drill("latium").ok,"empty city can run supplied troop drill")
	game.city_battle_close("latium");game.state.player_faction="julii"
	t.check(not game.city_battle_drill("latium").ok,"foreign ruler cannot enter drill")

func test_malformed_tactical_fields_reject_without_dereferencing_them(t) -> void:
	var game:=_game()
	for fault in ["source_type","missing_hp","hp_type","empty_unit","strength_type"]:
		var bad:=game.state.duplicate(true)
		var f:Dictionary=bad.city_battles.latium.formations[0]
		match fault:
			"source_type":f.source_id=[]
			"missing_hp":f.erase("hp")
			"hp_type":f.hp=[]
			"empty_unit":f.unit={}
			"strength_type":f.unit.strength_pct=[]
		t.check(SaveGame.from_json(SaveGame.to_json(bad)).is_empty(),"invalid field rejected cleanly: "+fault)

func test_narrow_street_forces_ai_out_of_phalanx(t) -> void:
	var game:=_game();_isolate(game)
	var b:Dictionary=game.state.city_battles.latium
	var enemy:Dictionary=b.formations[0]
	enemy.template="chosen_hoplites";enemy.unit.template="chosen_hoplites";enemy.unit.experience=2
	enemy.position=[-6000,2400];enemy.destination=[-6000,400];enemy.goal=enemy.destination.duplicate()
	enemy.order="attack_move";enemy.path=CityBattleNavigation.route(CityBattleSim.navigation(game.data),Vector2(-6000,2400),Vector2(-6000,400))
	_own(game).position=[-6000,400]
	game.city_battle_start("latium")
	for i in range(150):game.city_battle_step("latium")
	t.check(int(enemy.position[1])<2000,"AI passes the narrow lane instead of stalling in phalanx")

func test_ram_volley_uses_pre_tick_facing_for_incoming_damage(t) -> void:
	var game:=_game();_isolate(game)
	var b:Dictionary=game.state.city_battles.latium
	var archer:=_own(game,2)
	archer.position=[0,6600];archer.facing=[0,-1000];archer.facing_goal=[0,-1000];archer.facing_locked=true;archer.target_id="siege_ram"
	var enemy:Dictionary=b.formations[0]
	enemy.position=[0,6300];enemy.role="cavalry";enemy.order="charge";enemy.runup_cm=1000;enemy.target_id=archer.id
	game.city_battle_start("latium")
	var checkpoint:=game.state.duplicate(true)
	game.city_battle_step("latium")
	var hp:int=archer.hp
	t.check(archer.attack_seq>0,"fixture actually fires at ram")
	t.check_eq(archer.facing,[0,-1000],"firing cannot override the locked orientation")
	game.state=checkpoint;game.state.city_battles.latium.formations.reverse()
	game.city_battle_step("latium")
	t.check_eq(_own(game,2).hp,hp,"ram volleys cannot bias incoming damage by array order")

func test_ai_does_not_repeatedly_reform_and_backtrack_at_street_corner(t) -> void:
	var game:=_game();_isolate(game)
	var b:Dictionary=game.state.city_battles.latium
	var enemy:Dictionary=b.formations[0]
	enemy.template="chosen_hoplites";enemy.unit.template="chosen_hoplites";enemy.unit.experience=2
	enemy.position=[-6000,-1300];enemy.order="attack_move";enemy.goal=[0,0];enemy.destination=enemy.goal.duplicate();enemy.formation="phalanx";enemy.facing=[0,-1000]
	for f in b.formations:
		if f.side=="defender":f.position=[-4000,-2800];f.destination=f.position.duplicate();f.goal=f.position.duplicate()
	game.city_battle_start("latium")
	for i in range(600):game.city_battle_step("latium")
	t.check(int(enemy.position[0])>-4500,"AI traverses the corner and slow straight approach without repath oscillation")

func test_slow_pursuit_connector_preserves_forward_progress(t) -> void:
	var game:=_game()
	var result:=CityBattleTactics.forward_connector(game.data,Vector2(0,1550),[[0,1600],[0,1400],[0,1200]])
	t.check_eq(result[0],[0,1400],"changing target can replan without pulling slow troops backward")
