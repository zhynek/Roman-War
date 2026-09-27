extends RefCounted

func test_loaded_ram_starts_at_saved_position(t) -> void:
	var visuals:=RomaCitySiegeVisual.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(visuals)
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	game.city_battle_begin("latium",true)
	game.city_battle_start("latium")
	game.city_battle_step("latium")
	var snapshot:=game.city_battle_status("latium")
	var before:=JSON.stringify(game.state)
	visuals.sync(snapshot)
	t.check_eq(visuals.ram.position,Vector3(snapshot.siege_engine.position[0]/100.0,0,snapshot.siege_engine.position[1]/100.0),"first late snapshot places the ram at its saved location")
	visuals._process(0.5)
	t.check_eq(JSON.stringify(game.state),before,"ram and fire animation cannot change authoritative state")
	visuals.free()

func test_volley_loss_presentation_waits_for_impact_and_respects_pause(t) -> void:
	var forces:=RomaCityBattleForces.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(forces)
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	game.city_battle_begin("latium",true)
	game.city_battle_start("latium")
	var snapshot:=game.city_battle_status("latium")
	snapshot.tick=1
	forces.sync(game.data.roma_city,snapshot)
	var target:Dictionary=snapshot.formations[-1]
	var count:int=forces.groups[target.id].get_node("Troops").multimesh.instance_count
	target.unit.strength_pct-=20
	snapshot.events=[{"id":1,"kind":"volley","from":[0,3000],"to":target.position,"target":target.id}]
	forces.sync(game.data.roma_city,snapshot)
	t.check_eq(forces.groups[target.id].get_node("Troops").multimesh.instance_count,count,"rank losses do not precede the visible arrow arrival")
	t.check(forces._fallen.is_empty(),"falling bodies wait for impact")
	snapshot.paused=true
	forces.sync(game.data.roma_city,snapshot)
	forces._process(2.0)
	forces.sync(game.data.roma_city,snapshot)
	t.check(forces._fallen.is_empty(),"paused volley keeps its pending impacts frozen")
	snapshot.paused=false
	forces.sync(game.data.roma_city,snapshot)
	forces._process(0.85)
	forces.sync(game.data.roma_city,snapshot)
	t.check(not forces._fallen.is_empty(),"fallen representatives appear when the volley lands")
	forces.free()
