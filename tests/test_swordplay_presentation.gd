extends RefCounted

func test_melee_attack_blocks_and_casualties_follow_contact_without_changing_rules(t) -> void:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	game.city_battle_begin("latium",true);game.city_battle_start("latium")
	var forces:=RomaCityBattleForces.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(forces)
	var snapshot:=game.city_battle_status("latium");snapshot.tick=1
	forces.sync(game.data.roma_city,snapshot)
	var own:Dictionary=snapshot.formations[-1];var foe:Dictionary=snapshot.formations[0]
	var before:=JSON.stringify(game.state)
	own.engaged=true;foe.engaged=true
	snapshot.events=[{"id":1,"kind":"clash","from":foe.position,"to":own.position,"source":foe.id,"target":own.id}]
	own.unit.strength_pct-=20
	forces.sync(game.data.roma_city,snapshot)
	t.check(forces.groups[foe.id].has_meta("strike_at") and forces.groups[own.id].has_meta("block_at"),"resolved melee events drive attack and defending poses")
	t.check(forces._fallen.is_empty(),"melee casualties wait for weapon contact")
	forces._process(0.35)
	t.check(not forces._fallen.is_empty(),"resolved losses become visible at contact")
	var troops:MultiMesh=forces.groups[own.id].get_node("Troops").multimesh
	t.check_eq(troops.get_instance_custom_data(5).g,0.0,"rear ranks cannot swing through the front rank")
	snapshot.paused=true;forces.sync(game.data.roma_city,snapshot)
	var clock:float=forces._clock
	forces._process(1.5)
	t.check_eq(forces._clock,clock,"paused combat freezes every articulated pose")
	t.check_eq(JSON.stringify(game.state),before,"animation and casualty display cannot advance combat or RNG")
	forces.free()

func test_hidden_specialists_remain_generic_and_regular_health_bars_are_full(t) -> void:
	var city:=RomaCityScreen.new();city.standalone=false
	city.game=Game.new_campaign("senate",42,"medium","long",false)
	(Engine.get_main_loop() as SceneTree).root.add_child(city)
	city.open_battle();city.battle_panel.begin(true)
	var panel:=city.battle_panel
	for f in panel.snapshot.formations:
		if f.side=="defender":t.check_eq(panel._roster_rows[f.id].bar.value,float(f.unit.strength_pct),"all formations show their actual strength")
	var mesh:Mesh=panel.forces._meshes.enemy_unknown
	var copy:=panel.snapshot.duplicate(true)
	for f in copy.formations:
		if f.side=="attacker":f.specialty="commander";f.role="cavalry";f.ability_remaining_ms=12000
	panel.forces.sync(city.layout,copy)
	t.check_eq(panel.forces.groups.attacker_0.get_node("Troops").multimesh.mesh,mesh,"unseen enemy powers cannot reveal a commander")
	t.check(not panel.forces.groups.attacker_0.get_node("Ability").visible,"unseen enemy ability insignia stays hidden")
	city.free()
