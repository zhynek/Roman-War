extends RefCounted

func _unit(template: String) -> Dictionary:
	return {"template":template,"strength_pct":100,"experience":0,"weapon":0,"armor":0}

func _battle(own: String = "roman_principes", enemy: String = "roman_hastati") -> Game:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	game.state.settlements.latium.garrison=[_unit(own)]
	game.data.roma_city.battle.practice_attackers=[enemy]
	game.city_battle_begin("latium",true)
	var battle:Dictionary=game.state.city_battles.latium
	battle.gate_integrity=0
	for f in battle.formations:
		f.position=[0,1000] if f.side=="defender" else [0,1300]
		f.destination=f.position.duplicate();f.goal=f.position.duplicate();f.path=[];f.order="hold"
	game.city_battle_start("latium")
	return game

func test_general_guards_are_mounted_and_ordinary_troops_have_no_power(t) -> void:
	var game:=_battle("roman_general_guard")
	for template in game.data.units:
		if game.data.units[template]["class"]=="general_bodyguard":
			t.check_eq(CityBattleSim.role(game.data,template),"cavalry","every general guard rides")
			t.check_eq(CityBattleSpecialists.specialty(game.data,template),"commander","every guard carries the rally ability")
	t.check_eq(game.state.city_battles.latium.formations[0].specialty,"","regular infantry have no special ability")
	var p:=CityBattleSpecialists.profile(game.data,game.state.city_battles.latium.formations[1])
	t.check(p.damage>1 and p.resistance<1,"escort has passive combat advantages in addition to template quality")

func test_abilities_are_atomic_and_have_real_duration_and_recovery(t) -> void:
	var game:=_battle()
	var b:Dictionary=game.state.city_battles.latium
	var own:Dictionary=b.formations[1]
	var before:=JSON.stringify(game.state)
	t.check(not game.city_battle_command("latium",["defender_0","attacker_0"],"ability").ok,"cannot issue powers to enemies")
	t.check_eq(JSON.stringify(game.state),before,"invalid selection is atomic")
	t.check(game.city_battle_command("latium",["defender_0"],"ability").ok,"specialist activates through the public command seam")
	var profile:=CityBattleSpecialists.profile(game.data,own)
	t.check_eq(own.ability_remaining_ms,profile.duration_ms,"full duration persists")
	before=JSON.stringify(game.state)
	t.check_eq(game.city_battle_command("latium",["defender_0"],"ability").reason,"ability_recovering","cannot spam ability")
	t.check_eq(JSON.stringify(game.state),before,"rejected reactivation spends nothing")
	for f in b.formations:f.position=[0,1000] if f.side=="defender" else [0,6000]
	for i in range(int(profile.duration_ms)/100):game.city_battle_step("latium")
	t.check_eq(own.ability_remaining_ms,0,"effect expires at its exact fixed quantum")
	t.check(own.ability_cooldown_ms>0,"recovery outlasts active effect")
	for i in range(int(own.ability_cooldown_ms)/100):game.city_battle_step("latium")
	t.check(game.city_battle_command("latium",["defender_0"],"ability").ok,"ability returns after full recovery")

func test_veteran_assault_changes_actual_damage_without_rng_or_healing(t) -> void:
	var plain:=_battle();var powered:=_battle()
	var rng:String=powered.state.rng_state
	powered.city_battle_command("latium",["defender_0"],"ability")
	plain.city_battle_step("latium");powered.city_battle_step("latium")
	t.check(powered.state.city_battles.latium.formations[0].hp<plain.state.city_battles.latium.formations[0].hp,"concentrated assault increases resolved damage")
	t.check_eq(powered.state.rng_state,rng,"ability consumes no campaign random draws")
	t.check_eq(powered.state.city_battles.latium.formations[1].hp,plain.state.city_battles.latium.formations[1].hp,"assault does not restore or fabricate troops")
	t.check_eq(powered.state.settlements.latium.garrison[0].strength_pct,100,"practice losses stay in the practice copy")

func test_braced_spears_cancel_charge_bonus_and_reduce_damage(t) -> void:
	var game:=_battle("roman_triarii","roman_equites")
	var b:Dictionary=game.state.city_battles.latium
	var own:Dictionary=b.formations[1];var enemy:Dictionary=b.formations[0]
	enemy.order="charge";enemy.runup_cm=1000
	var control:=game.state.duplicate(true)
	game.city_battle_command("latium",["defender_0"],"ability")
	game.city_battle_step("latium")
	var braced_damage:=100000-int(own.hp)
	game.state=control;game.city_battle_step("latium")
	var ordinary_damage:=100000-int(game.state.city_battles.latium.formations[1].hp)
	t.check(braced_damage<ordinary_damage*0.35,"brace resists damage and negates the charge multiplier")
	t.check_eq(CityBattleSpecialists.speed_multiplier(game.data,own),0.35,"brace trades mobility for protection")

func test_rally_is_local_friendly_nonstacking_and_ends_with_commander(t) -> void:
	var game:=_battle("roman_general_guard")
	var b:Dictionary=game.state.city_battles.latium
	var leader:Dictionary=b.formations[1]
	game.city_battle_command("latium",["defender_0"],"ability")
	var ally:Dictionary=leader.duplicate(true)
	ally.id="probe";ally.specialty="";ally.ability_remaining_ms=0;ally.position=[0,2000];ally.hp=18000;ally.unit.strength_pct=18
	var hp:int=ally.hp
	t.check_eq(CityBattleSpecialists.morale_bonus(game.data,b,ally),18,"nearby troops gain temporary morale")
	t.check_eq(CityBattleSpecialists.morale_bonus(game.data,b,b.formations[0]),0,"rally never helps opponents")
	b.formations.append(leader.duplicate(true))
	t.check_eq(CityBattleSpecialists.morale_bonus(game.data,b,ally),18,"multiple commanders do not stack")
	b.formations.pop_back()
	ally.position=[0,4000]
	t.check_eq(CityBattleSpecialists.morale_bonus(game.data,b,ally),0,"leaving command radius removes benefit")
	ally.position=[0,2000];ally.routed=true
	t.check_eq(CityBattleSpecialists.morale_bonus(game.data,b,ally),0,"routed troops cannot be resurrected by rally")
	ally.routed=false;leader.hp=0;leader.unit.strength_pct=0
	t.check_eq(CityBattleSpecialists.morale_bonus(game.data,b,ally),0,"fallen general cannot maintain rally")
	t.check_eq(ally.hp,hp,"morale never creates health")

func test_enemy_uses_same_power_and_recovery_at_contact(t) -> void:
	var game:=_battle("roman_hastati","gallic_oathsworn")
	game.city_battle_step("latium")
	var enemy:Dictionary=game.state.city_battles.latium.formations[0]
	t.check(enemy.ability_remaining_ms>0,"enemy elite activates at contact")
	var cooldown:int=enemy.ability_cooldown_ms
	game.city_battle_step("latium")
	t.check_eq(enemy.ability_cooldown_ms,cooldown-100,"AI cannot reset its recovery every tick")
	var both:=_battle("roman_principes","roman_principes")
	both.city_battle_command("latium",["defender_0"],"ability")
	both.city_battle_step("latium")
	t.check_eq(both.state.city_battles.latium.formations[0].ability_remaining_ms,both.state.city_battles.latium.formations[1].ability_remaining_ms,"player and AI receive exactly the same effect ticks")
	game=_battle("roman_hastati","roman_general_guard")
	var b:Dictionary=game.state.city_battles.latium
	b.gate_integrity=100;b.formations[0].position=[0,8400];b.formations[1].position=[0,7000]
	game.city_battle_step("latium")
	t.check_eq(b.formations[0].ability_cooldown_ms,0,"closed gate prevents premature enemy rally")

func test_active_ability_save_replays_exactly_and_malformed_extensions_fail(t) -> void:
	var game:=_battle("roman_general_guard","gallic_oathsworn")
	game.city_battle_command("latium",["defender_0"],"ability")
	for i in range(8):game.city_battle_step("latium")
	var checkpoint:=SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not checkpoint.is_empty(),"active powers cross save boundary")
	for i in range(40):game.city_battle_step("latium")
	var expected:=JSON.stringify(JSON.parse_string(SaveGame.to_json(game.state)))
	game.state=checkpoint
	NewGame.ensure_state_keys(game.state,game.data)
	for i in range(40):game.city_battle_step("latium")
	t.check_eq(JSON.stringify(JSON.parse_string(SaveGame.to_json(game.state))),expected,"mid-ability save resumes bit for bit")
	for fault in ["negative","fractional","unknown","partial","oversized","orphan"]:
		var state:=game.state.duplicate(true)
		var b:Dictionary=state.city_battles.latium
		match fault:
			"negative":b.formations[1].ability_cooldown_ms=-1
			"fractional":b.formations[1].ability_remaining_ms=1.5
			"unknown":b.formations[1].specialty="wizard"
			"partial":b.formations[1].erase("ability_remaining_ms")
			"oversized":b.formations[1].ability_cooldown_ms=9999999
			"orphan":b.erase("specialists_version")
		t.check(SaveGame.from_json(SaveGame.to_json(state)).is_empty(),"reject malformed ability: "+fault)

func test_old_battles_keep_original_rules_and_new_battles_gain_abilities(t) -> void:
	var game:=_battle()
	var b:Dictionary=game.state.city_battles.latium
	b.erase("specialists_version")
	for f in b.formations:
		for key in ["specialty","ability_remaining_ms","ability_cooldown_ms"]:f.erase(key)
	var loaded:=SaveGame.from_json(SaveGame.to_json(game.state))
	t.check(not loaded.is_empty(),"pre-specialist battle still loads")
	NewGame.ensure_state_keys(loaded,game.data)
	t.check(not loaded.city_battles.latium.has("specialists_version"),"migration never changes ongoing combat balance")
	game.state=loaded
	t.check_eq(game.city_battle_command("latium",["defender_0"],"ability").reason,"no_ability","old session explains unavailable ability")
	game.city_battle_step("latium")
	t.check(not SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(),"old session continues and saves normally")
	game.state.city_battles.latium.formations[0]="malformed"
	t.check(SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(),"malformed old formation rejects without accessing dictionary fields")

func test_roma_can_muster_one_paid_mounted_escort_through_normal_recruitment(t) -> void:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	var cash:int=game.state.factions.senate.treasury
	var population:int=game.state.settlements.latium.population
	var cost:=RecruitmentRules.recruit_cost(game.data,game.state,"senate",game.data.units.roman_command_escort)
	t.check(not game.queue_unit("latium","roman_general_guard"),"legacy zero-cost bodyguards remain unrecruitable")
	t.check(game.city_queue_unit("latium","roman_command_escort",true),"normal Senate Roma can muster a commander escort")
	t.check_eq(game.state.factions.senate.treasury,cash-cost,"muster charges the real treasury")
	t.check_eq(game.state.settlements.latium.population,population-40,"muster draws real recruits")
	var paid:=JSON.stringify(game.state)
	t.check(not game.city_queue_unit("latium","roman_command_escort",true),"queued guard counts toward faction limit")
	t.check_eq(JSON.stringify(game.state),paid,"blocked duplicate cannot spend more")
	for i in range(3):game.city_advance_day("latium")
	t.check_eq(game.state.settlements.latium.garrison[-1].template,"roman_command_escort","trained escort joins actual garrison")
	t.check(not game.city_queue_unit("latium","roman_command_escort",true),"completed escort counts toward limit")
	game.city_battle_begin("latium",true)
	var f:Dictionary=game.state.city_battles.latium.formations[-1]
	t.check_eq(f.specialty,"commander","recruited escort gains command ability")
	t.check_eq(f.role,"cavalry","recruited guard appears as cavalry")
	t.check(not SaveGame.from_json(SaveGame.to_json(game.state)).is_empty(),"recruited guard and power save normally")

func test_existing_escort_receives_completed_military_training_despite_recruit_cap(t) -> void:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	game.city_queue_unit("latium","roman_command_escort",true)
	for i in range(3):game.city_advance_day("latium")
	var escort:Dictionary=game.state.settlements.latium.garrison[-1]
	var experience:int=escort.experience
	var equipment:int=escort.weapon+escort.armor
	for project in ["improve_barracks","drill_maniples","equip_maniples"]:
		t.check(game.city_action("latium",project),"fund escort training programme: "+project)
		for i in range(int(game.data.balance.city.project_days[project])):game.city_advance_day("latium")
	t.check(escort.experience>experience,"standing escort receives drills despite recruitment cap")
	t.check(escort.weapon+escort.armor>equipment,"standing escort receives funded equipment")

func test_optional_legacy_queue_fields_do_not_break_faction_escort_queries(t) -> void:
	var game:=Game.new_campaign("senate",42,"medium","long",false)
	game.state.settlements.latium.recruitment_queue.append({})
	t.check(RecruitmentRules.city_escort_available(game.data,game.state,"latium"),"incomplete optional legacy queue record cannot crash roster query")
