extends RefCounted

func _ready_siege() -> Game:
	var game := Game.new_campaign("senate", 42, "medium", "long", false)
	game.state["armies"]["army_roma_test_invader"] = {
		"owner": "gaul", "region": "latium", "general": null,
		"movement_left": 0.0, "forced_march": false,
		"units": [{"template": "tribal_warband", "experience": 0,
			"strength_pct": 100, "weapon": 0, "armor": 0}],
	}
	DiplomacyRules.declare_war(game.data, game.state, "gaul", "senate")
	game.state["settlements"]["latium"]["siege"] = {
		"besieger": "army_roma_test_invader", "turns": 3, "equipment_ready": true,
	}
	return game

func test_campaign_end_turn_routes_pending_defense_to_shared_city(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Control.new()
	tree.root.add_child(holder)
	var game := _ready_siege()
	var screen := CampaignScreen.create(game)
	holder.add_child(screen)
	t.check(screen.city_defense_button.visible, "a ready campaign siege has a prominent command entry")
	var turn := int(game.state["turn"])
	var troops := JSON.stringify(game.state["settlements"]["latium"]["garrison"])
	screen._end_turn()
	t.check_eq(holder.get_child_count(), 2, "End Turn opens the awaited battle surface")
	var city := holder.get_child(1) as RomaCityScreen
	t.check(city != null and city.battle_panel.visible, "city opens directly into siege command")
	t.check(city.game == game, "defence commands use the campaign facade")
	t.check_eq(int(game.state["turn"]), turn, "opening defence cannot advance another season")
	t.check_eq(JSON.stringify(game.state["settlements"]["latium"]["garrison"]), troops, "opening command cannot consume troops")
	holder.free()

func test_foreign_roma_never_exposes_defense_button(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game := _ready_siege()
	game.state["player_faction"] = "julii"
	var screen := CampaignScreen.create(game)
	tree.root.add_child(screen)
	t.check(not screen.city_defense_button.visible, "another faction cannot command Roma's garrison")
	screen.free()

func test_gate_visual_and_collision_change_together_without_simulation(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var city := RomaCityScreen.new()
	city.standalone = false
	city.game = Game.new_campaign("senate", 42, "medium", "long", false)
	tree.root.add_child(city)
	var before := JSON.stringify(city.game.state)
	t.check(city.world.battle_gate.visible, "the undamaged city gate is drawn closed")
	city.world.set_battle_gate_breached(true)
	t.check(not city.world.battle_gate.visible, "breach removes the closed gate leaves")
	for shape in city.world.gate_collisions:
		t.check(shape.disabled, "breached visible opening has no invisible gate collider")
	city.world.set_battle_gate_breached(false)
	for shape in city.world.gate_collisions:
		t.check(not shape.disabled, "returning to the civic scene restores the normal gate")
	t.check_eq(JSON.stringify(city.game.state), before, "gate rendering never resolves siege damage")
	city.free()


func _leave_city_in_test(city: RomaCityScreen) -> void:
	# The production return handler is deferred to let input dispatch finish.
	# This runner executes tests synchronously, so invoke the same connected
	# handler synchronously rather than leave it queued past fixture cleanup.
	for connection in city.get_signal_connection_list("main_menu_requested"):
		var callback: Callable = connection["callable"]
		city.main_menu_requested.disconnect(callback)
		city.main_menu_requested.connect(callback)
	city.leave_city()


func test_retained_defeat_report_returns_to_campaign_and_does_not_block_next_season(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Control.new()
	tree.root.add_child(holder)
	var game := _ready_siege()
	# Keep a second settlement so this checks continuing a surviving campaign,
	# rather than the separate last-settlement defeat presentation.
	game.state["settlements"]["campania"]["owner"] = "senate"
	game.state["settlements"]["latium"]["garrison"] = [{"template": "roman_town_watch",
		"experience": 0, "strength_pct": 10, "weapon": 0, "armor": 0}]
	game.state["armies"]["army_roma_test_invader"]["units"] = []
	for card in range(4):
		game.state["armies"]["army_roma_test_invader"]["units"].append({"template": "gallic_long_swords",
			"experience": 0, "strength_pct": 100, "weapon": 0, "armor": 0})
	var screen := CampaignScreen.create(game)
	screen.playback_enabled = false
	holder.add_child(screen)
	screen._end_turn()
	var city := holder.get_child(1) as RomaCityScreen
	city.battle_panel.begin(false)
	city.battle_panel.start()
	# The real-time host normally owns Game while running. Join it before
	# driving deterministic steps synchronously in this one-frame test.
	city.battle_panel.host.stop()
	for tick in range(int(CityBattleSim.rules(game.data)["maximum_ms"])/int(CityBattleSim.rules(game.data)["tick_ms"]) + 1):
		if game.city_battle_status("latium").get("phase", "") == "finished":
			break
		game.city_battle_step("latium")
	city.battle_panel.refresh()
	t.check_eq(game.state["settlements"]["latium"]["owner"], "gaul", "actual tactical loss transfers Roma before leaving its view")
	t.check_eq(game.city_battle_status("latium")["phase"], "finished", "loss leaves a readable completed report")
	city.battle_panel.close()
	_leave_city_in_test(city)
	t.check(screen.visible and screen.process_mode == Node.PROCESS_MODE_INHERIT, "city Leave restores the campaign after losing ownership")
	t.check(screen.city_defense_button.visible, "the player's retained defeat report stays accessible in foreign Roma")
	t.check_eq(screen.city_defense_button.text, game.data.effects_glossary["city_battle"]["campaign_report"], "completed result is labeled as a report")
	var children_before := holder.get_child_count()
	var turn_before := int(game.state["turn"])
	screen._end_turn()
	t.check_eq(int(game.state["turn"]), turn_before + 1, "a retained loss report cannot silently block the next campaign season")
	t.check_eq(holder.get_child_count(), children_before, "End Turn does not reopen a finished foreign-city session")
	holder.free()


func test_foreign_city_stale_session_can_be_reopened_and_discarded_by_its_owner(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Control.new()
	tree.root.add_child(holder)
	var game := _ready_siege()
	game.city_battle_begin("latium", false)
	game.city_battle_start("latium")
	game.state["settlements"]["latium"]["owner"] = "gaul"
	var screen := CampaignScreen.create(game)
	holder.add_child(screen)
	t.check(screen.city_defense_button.visible, "an owned stale session has a recovery entry even after the city's owner changes")
	screen._end_turn()
	var city := holder.get_child(1) as RomaCityScreen
	t.check(city != null and city.battle_panel.visible, "End Turn routes the stale session to recovery instead of refusing city access")
	t.check_eq(city.battle_panel.snapshot["reason"], "stale_battle", "the panel explains the stale source")
	t.check(city.battle_panel.close_button.visible and city.battle_panel.step_button.disabled, "stale defense exposes discard and disables further simulation")
	city.battle_panel.dismiss_session()
	t.check(not game.state["city_battles"].has("latium"), "discard removes the stale campaign lock")
	t.check_eq(game.state["settlements"]["latium"]["owner"], "gaul", "discard never reclaims the captured city")
	_leave_city_in_test(city)
	t.check(screen.visible and not screen.city_defense_button.visible, "recovery returns to campaign without exposing foreign-city command")
	holder.free()
