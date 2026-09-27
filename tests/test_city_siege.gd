extends RefCounted

func _game(prepared: bool = false) -> Game:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	game.state.settlements.latium.garrison=[{"template":"roman_allied_bowmen","strength_pct":100,"experience":0,"weapon":0,"armor":0}]
	if prepared:
		game.city_action("latium","prepare_fire_arrows")
		for i in range(3):game.city_advance_day("latium")
	game.city_battle_begin("latium",true)
	game.city_battle_command("latium",["defender_0"],"move",[0,6800])
	return game

func test_fire_requires_preparation_and_commands_are_atomic(t) -> void:
	var game:=_game()
	var before:=JSON.stringify(game.state)
	t.check_eq(game.city_battle_command("latium",["defender_0"],"fire_arrows").reason,"fire_unprepared","unprepared archers cannot invent incendiaries")
	t.check_eq(JSON.stringify(game.state),before,"rejection is atomic")
	t.check(not game.city_action("latium","prepare_fire_arrows"),"cannot fund defenses after entering a battle")

func test_archers_ignite_and_destroy_actual_equipment_without_rng(t) -> void:
	var game:=_game(true)
	var rng: String=game.state.rng_state
	var campaign:=JSON.stringify(game.state.settlements.latium.garrison)
	t.check(game.city_battle_command("latium",["defender_0"],"fire_arrows").ok,"prepared archers select incendiaries")
	t.check(game.city_battle_command("latium",["defender_0"],"attack_engine").ok,"ram can be targeted before the assault")
	game.city_battle_start("latium")
	var battle:Dictionary=game.state.city_battles.latium
	var burned:=false
	var volley:=false
	for i in range(230):
		if battle.phase=="finished":break
		game.city_battle_step("latium")
		burned=burned or battle.siege_engine.burning
		for event in battle.events:volley=volley or event.kind=="fire_volley"
	t.check(burned and volley,"actual volleys ignite exposed timber")
	t.check_eq(battle.siege_engine.hp,0,"burning destroys the ram")
	t.check_eq(game.state.rng_state,rng,"siege and fire consume no campaign RNG")
	t.check_eq(JSON.stringify(game.state.settlements.latium.garrison),campaign,"practice preserves actual garrison")

func test_ram_requires_crew_and_destroying_it_stops_its_gate_damage(t) -> void:
	var game:=_game()
	var battle:Dictionary=game.state.city_battles.latium
	battle.siege_engine.position=[0,8160]
	for f in battle.formations:
		if f.side=="attacker":f.position=[-6000,8400]
	var gate:int=battle.gate_integrity
	CitySiegeRules.tick(game.data,battle)
	t.check_eq(battle.gate_integrity,gate,"abandoned ram cannot strike")
	battle.formations[0].position=[0,8400]
	CitySiegeRules.tick(game.data,battle)
	t.check(battle.gate_integrity<gate,"nearby crew operates the ram")
	gate=battle.gate_integrity
	battle.siege_engine.hp=0
	for i in range(50):CitySiegeRules.tick(game.data,battle)
	t.check_eq(battle.gate_integrity,gate,"destroyed equipment cannot attack")

func test_funded_defenses_have_delayed_benefits_and_additive_save_keys(t) -> void:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	var before:=JSON.stringify(game.state)
	var base:=CitySiegeRules.defenses(game.data,game.state,"latium")
	t.check_eq(JSON.stringify(game.state),before,"defense inspection is pure")
	t.check(game.city_action("latium","reinforce_gate"),"gate reinforcement uses paid civic works")
	t.check_eq(CitySiegeRules.defenses(game.data,game.state,"latium"),base,"unfinished gate has no bonus")
	for i in range(4):game.city_advance_day("latium")
	game.city_battle_begin("latium",true)
	t.check_eq(game.state.city_battles.latium.gate_integrity,180,"completed gate changes actual battle integrity")
	var loaded:=SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not loaded.is_empty(),"new equipment and defenses cross save boundary")
	var old:Dictionary=game.state.duplicate(true)
	old.city_battles.latium.erase("siege_engine")
	old.city_battles.latium.erase("fire_prepared")
	old.city_battles.latium.erase("gate_max_integrity")
	old.city_governance.latium.projects.erase("reinforce_gate")
	old.city_governance.latium.projects.erase("prepare_fire_arrows")
	loaded=SaveGame.from_json(SaveGame.to_json(old))
	t.check(not loaded.is_empty(),"older continuous battles still load")
	NewGame.ensure_state_keys(loaded,game.data)
	t.check(loaded.city_governance.latium.projects.has("reinforce_gate"),"old civic ledger gains unfunded defense projects")
	t.check(not loaded.city_battles.latium.has("siege_engine"),"old fights never acquire a new siege machine mid-fight")

func test_burning_save_replays_identically_and_malformed_equipment_rejects(t) -> void:
	var game:=_game(true)
	game.city_battle_command("latium",["defender_0"],"fire_arrows")
	game.city_battle_command("latium",["defender_0"],"attack_engine")
	game.city_battle_start("latium")
	for i in range(45):game.city_battle_step("latium")
	var copy:=Game.new();copy.data=game.data
	copy.state=SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not copy.state.is_empty(),"burning battle can be saved")
	if copy.state.is_empty():return
	for i in range(80):
		game.city_battle_step("latium");copy.city_battle_step("latium")
	t.check_eq(JSON.stringify(JSON.parse_string(JSON.stringify(copy.state))),JSON.stringify(JSON.parse_string(JSON.stringify(game.state))),"burning saved siege resumes in lockstep")
	for key in ["hp","heat","cooldown_ms"]:
		var broken:Dictionary=game.state.duplicate(true)
		broken.city_battles.latium.siege_engine[key]="invalid"
		t.check(SaveGame.from_json(SaveGame.to_json(broken)).is_empty(),"invalid engine numeric field rejects: "+key)

func test_arc_respects_buildings_and_gate_height(t) -> void:
	var game:=_game()
	t.check(CitySiegeRules.arrow_clear(game.data,Vector2(0,6800),Vector2(0,8600)),"high volley clears the closed gate")
	t.check(not CitySiegeRules.arrow_clear(game.data,Vector2(0,7700),Vector2(0,8600)),"low point of arc cannot shoot through nearby gate")
	t.check(not CitySiegeRules.arrow_clear(game.data,Vector2(4600,-2250),Vector2(4600,-2000)),"arrows cannot pass through barracks roof")

func test_depleted_archers_cannot_ignite_as_fast_as_full_cohorts(t) -> void:
	var game:=_game(true)
	var battle:Dictionary=game.state.city_battles.latium
	var f:Dictionary=battle.formations[-1]
	f.unit.strength_pct=13;f.initial_strength=13;f.hp=13000
	f.target_id="siege_ram";f.incendiary=true
	CitySiegeRules.archer_shot(game.data,battle,f)
	t.check(battle.siege_engine.heat<10,"depleted cohort's fire scales with present troops")

func test_malformed_legacy_siege_extension_is_rejected_before_migration(t) -> void:
	var game:=_game()
	var old:Dictionary=game.state.duplicate(true)
	old.city_battles.latium.erase("model_version")
	old.city_battles.latium.siege_engine="broken"
	t.check(SaveGame.from_json(SaveGame.to_json(old)).is_empty(),"legacy model cannot bypass siege validation")
