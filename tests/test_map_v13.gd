extends RefCounted

func _world() -> Dictionary:
	var data := Fixtures.data()
	var state := Fixtures.state(data)
	state["settlements"].erase("epsilon")
	return {"data": data, "state": state}


func test_slowest_company_sets_range_and_cavalry_scouts_further(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	var horse := Fixtures.add_army(state, "red", "beta", ["test_horse"])
	var foot := Fixtures.add_army(state, "red", "beta", ["test_spears"])
	var horse_army: Dictionary = state["armies"][horse]
	var foot_army: Dictionary = state["armies"][foot]
	MovementRules.reset_movement(data, state)
	t.check(float(horse_army["movement_left"]) > float(foot_army["movement_left"]), "pure cavalry travels further than heavy foot")
	t.check(PathfindingRules.reachable(data, state, horse).has("epsilon"), "horse can reach three plains steps")
	t.check(not PathfindingRules.reachable(data, state, foot).has("epsilon"), "heavy foot cannot cover the same ground")
	t.check_eq(ReconRules.army_sight(data, horse_army), 2, "mounted scouts see two provinces away")
	t.check_eq(ReconRules.army_sight(data, foot_army), 1, "foot provides local observation")
	horse_army["units"].append(foot_army["units"][0].duplicate(true))
	MovementRules.cap_movement(data, state, horse_army)
	t.check_eq(horse_army["movement_left"], foot_army["movement_left"], "one slow company slows the entire mixed column")
	t.check_eq(ReconRules.army_sight(data, horse_army), 1, "mixed troops do not receive the cavalry scout bonus")


func test_artillery_remains_able_to_cross_mountain_passes(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	data.units["test_engine"] = data.units["test_spears"].duplicate(true)
	data.units["test_engine"]["class"] = "siege"
	var id := Fixtures.add_army(state,"red","alpha",["test_engine"])
	MovementRules.reset_movement(data,state)
	t.check(MovementRules.move_army(data,state,id,"zeta"), "heavy train can spend its season crossing a mountain")
	t.check_eq(state["armies"][id]["movement_left"],0.0,"crossing uses its entire base budget")


func test_reinforcement_and_general_changes_cannot_launder_movement(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	var horse := Fixtures.add_army(state,"red","beta",["test_horse"])
	MovementRules.reset_movement(data,state)
	state["settlements"]["beta"]["garrison"] = [{"template":"test_spears","experience":0,"strength_pct":100}]
	var transfer := ForceRules.transfer_units(data,state,"garrison:beta",horse,[0])
	t.check(transfer["ok"],"garrison joins the column")
	t.check_near(state["armies"][horse]["movement_left"],2.0,0.001,"slow reinforcements cap a fresh cavalry budget")
	state["armies"][horse]["movement_left"] = 0.5
	var split := ForceRules.split_army(data,state,horse,[1])
	t.check(split["ok"],"the heavy company can separate")
	t.check_eq(state["armies"][horse]["movement_left"],0.5,"separating foot grants no free movement this season")
	t.check_eq(state["armies"][split["army_id"]]["movement_left"],0.5,"the detached company remembers the march too")


func test_watchtower_and_fort_extend_sight_and_spend_only_on_success(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	var id := Fixtures.add_army(state,"red","beta",["test_spears"])
	state["factions"]["red"]["treasury"] = 3000
	t.check(not VisibilityRules.visible_regions(data,state,"red").has("delta"),"distant road starts hidden")
	var before := state.duplicate(true)
	var quote := ReconRules.post_quote(data,state,id)
	t.check(quote["ok"],"tower can be built here")
	t.check_eq(state,before,"quoting a post is read-only")
	t.check(ReconRules.build_post(data,state,id)["ok"],"tower built")
	t.check_eq(state["factions"]["red"]["treasury"],2400,"tower spends 600")
	t.check_eq(state["armies"][id]["movement_left"],1.0,"tower spends one point")
	t.check(VisibilityRules.visible_regions(data,state,"red").has("delta"),"tower watches two land steps")
	t.check(ReconRules.build_post(data,state,id)["ok"],"post fortified")
	t.check(VisibilityRules.visible_regions(data,state,"red").has("epsilon"),"fort observes three steps")
	t.check_eq(ReconRules.fort_defense(data,state,state["armies"][id]),20.0,"fort strengthens defenders")
	before = state.duplicate(true)
	t.check(not ReconRules.build_post(data,state,id)["ok"],"duplicate fort rejected")
	t.check_eq(state,before,"rejected construction spends nothing")
	state["armies"].erase(id)
	t.check(VisibilityRules.visible_regions(data,state,"red").has("epsilon"),"lookouts remain after the army leaves")
	state["settlements"]["beta"]["owner"] = "blue"
	t.check(not VisibilityRules.visible_regions(data,state,"red").has("epsilon"),"losing the province removes its observation coverage")


func test_enemy_land_and_exhausted_armies_cannot_build(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	var id := Fixtures.add_army(state,"red","alpha",["test_spears"])
	var before := state.duplicate(true)
	t.check_eq(ReconRules.post_quote(data,state,id)["reason"],"post_own_land","enemy land cannot host our permanent post")
	t.check(not ReconRules.build_post(data,state,id)["ok"],"foreign construction refused")
	t.check_eq(state,before,"refusal is inert")
	state["armies"][id]["region"] = "beta"
	state["armies"][id]["movement_left"] = 0
	t.check_eq(ReconRules.post_quote(data,state,id)["reason"],"post_no_movement","exhausted column waits for a fresh season")


func test_observed_enemy_steps_omit_hidden_endpoints_and_rosters(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	var id := Fixtures.add_army(state,"blue","gamma",["test_horse"])
	var before_rng: String = state["rng_state"]
	t.check(MovementRules.move_army(data,state,id,"delta"),"enemy leaves the visible road")
	var sightings: Array = state["recon"]["movements"]
	t.check_eq(sightings.size(),1,"a departure was recorded")
	t.check_eq(sightings[0]["from"],"gamma","last visible position is recorded")
	t.check_eq(sightings[0]["to"],"","hidden destination is absent")
	t.check(not JSON.stringify(sightings[0]).contains("delta"),"no nested field leaks the hidden endpoint")
	t.check(not JSON.stringify(sightings[0]).contains("test_horse"),"snapshot exposes no enemy roster")
	t.check(MovementRules.move_army(data,state,id,"epsilon"),"enemy continues out of sight")
	t.check_eq(sightings.size(),1,"wholly hidden travel is not recorded")
	state["armies"][id]["region"] = "delta"
	state["armies"][id]["movement_left"] = 2.0
	t.check(MovementRules.move_army(data,state,id,"gamma"),"column enters view")
	t.check_eq(sightings[1]["from"],"","entry does not expose the hidden origin")
	t.check_eq(sightings[1]["to"],"gamma","entry records the observed destination")
	t.check_eq(state["rng_state"],before_rng,"observation never draws campaign RNG")


func test_spies_and_past_contacts_have_real_limits(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	state["agents"]["scout"] = {"owner":"red","region":"beta","kind":"spy"}
	t.check(VisibilityRules.visible_regions(data,state,"red").has("delta"),"a positioned spy extends observation")
	state["agents"].clear()
	var enemy := Fixtures.add_army(state,"blue","gamma",["test_spears"])
	ReconRules.refresh_contacts(data,state)
	t.check(state["recon"]["contacts"].has(enemy),"current sight records a contact")
	state["settlements"]["beta"]["owner"] = "blue"
	state["armies"][enemy]["region"] = "delta"
	ReconRules.refresh_contacts(data,state)
	t.check_eq(state["recon"]["contacts"][enemy]["summary"]["region"],"gamma","lost contact stays at its old observed position")
	state["turn"] = 4
	ReconRules.refresh_contacts(data,state)
	t.check(state["recon"]["contacts"].is_empty(),"stale intelligence expires")


func test_fortification_is_shared_by_preview_resolver_and_ai(t) -> void:
	var world := _world()
	var data: GameData = world["data"]
	var state: Dictionary = world["state"]
	var attacker := Fixtures.add_army(state,"blue","gamma",["test_spears"])
	var defender := Fixtures.add_army(state,"red","beta",["test_spears"])
	var base_power := AiAssess.field_defense_power(data,state,state["armies"][defender])
	state["watchposts"]["beta"] = {"owner":"red","level":2}
	var context := CombatRules.battle_context(data,state,state["armies"][attacker],state["armies"][defender])
	t.check_eq(context["fort_defense_pct"],20.0,"battle seam receives the real field fort")
	t.check_near(AiAssess.field_defense_power(data,state,state["armies"][defender]),base_power*1.2,0.001,"AI values the same defense")


func test_commander_identity_is_stable_personal_and_faction_specific(t) -> void:
	var game := Game.new_campaign("julii",42)
	var before := game.state.duplicate(true)
	var general := {"id":"a","name":"Test General","age":32}
	var a := CommanderArt.profile(game.data,"julii",general)
	var again := CommanderArt.profile(game.data,"julii",general)
	t.check_eq(a,again,"same person wears the same face and equipment")
	general["id"] = "b"
	var b := CommanderArt.profile(game.data,"julii",general)
	t.check(a["face_width"] != b["face_width"] or a["hair"] != b["hair"],"different generals have individual features")
	var eastern := CommanderArt.profile(game.data,"parthia",general)
	t.check(a["helmet"] != eastern["helmet"],"Roman and Parthian commanders have distinct silhouettes")
	t.check_eq(UnitArt.for_data(game.data).commanders.size(),game.data.factions.size(),"every faction has an authored commander style")
	t.check_eq(game.state,before,"procedural portraits are presentation only")


func test_legacy_save_backfill_and_observation_roundtrip(t) -> void:
	var game := Game.new_campaign("julii",42)
	var state := game.state.duplicate(true)
	state.erase("watchposts")
	state.erase("recon")
	NewGame.ensure_state_keys(state,game.data)
	t.check_eq(state["watchposts"],{},"old saves receive empty posts")
	t.check_eq(state["recon"],{"contacts":{},"movements":[]},"old saves receive normalized observation state")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(game.state))
	NewGame.ensure_state_keys(loaded,game.data)
	t.check_eq(JSON.stringify(loaded["recon"]),JSON.stringify(JSON.parse_string(JSON.stringify(game.state["recon"]))),"new contacts survive additive save normalization")


func _screen() -> CampaignScreen:
	return load("res://tests/test_map_experience.gd").new()._screen()


func _target(screen: CampaignScreen) -> String:
	return load("res://tests/test_map_experience.gd").new()._destination(screen)


func _button(pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	return event


func _motion(at: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	return event


func test_single_click_marches_and_remains_ready_for_next_order(t) -> void:
	var screen := _screen()
	var id := screen.selected_army
	var target := _target(screen)
	screen._on_region_clicked(target)
	t.check_eq(screen.game.state["armies"][id]["region"],target,"single destination click executes a reachable march")
	t.check_eq(screen.selected_army,id,"army remains ready for another destination")
	t.check(not screen._planning_order,"one-season march needs no separate plan mode")
	t.check(screen.command_bar.title.get_combined_minimum_size().y > 10,"commander heading retains a readable line height")
	t.check(screen.command_bar.detail.get_combined_minimum_size().y > 10,"movement details cannot collapse to a one-pixel row")
	screen.free()


func test_army_drag_previews_without_panning_and_drop_issues_once(t) -> void:
	var screen := _screen()
	var view := screen.map_view
	var id := screen.selected_army
	var target := _target(screen)
	view.set_zoom_level(1.8)
	var start_world := view.force_world_position(id)
	var end_world := view.world_pos(screen.game.data.regions[target])
	view._camera_offset = -(start_world+end_world)*0.5+Vector2(450,180)/view._zoom
	view._banner_dirty = true
	var start := view.to_screen(start_world)
	var end := view.to_screen(end_world)
	var before := screen.game.state.duplicate(true)
	var camera := view._camera_offset
	t.check_eq(view._pick(start)["id"],id,"test starts on the painted army")
	view._gui_input(_button(true,start))
	view._gui_input(_motion(end,end-start))
	t.check_eq(screen.game.state,before,"dragging only previews")
	t.check_eq(view._camera_offset,camera,"dragging a force does not pan the camera")
	t.check_eq(view.path_preview.get("target",""),target,"drag previews its destination")
	t.check(view._drop_on_map(end),"destination must be above controls: %s, bar %s" % [end,screen.command_bar.get_rect()])
	view._gui_input(_button(false,end))
	t.check_eq(screen.game.state["armies"][id]["region"],target,"release executes the actual march")
	var after := screen.game.state.duplicate(true)
	view._gui_input(_button(false,end))
	t.check_eq(screen.game.state,after,"stray second release cannot issue another order")
	screen.free()


func test_cancelled_drag_and_panel_drop_never_move_armies(t) -> void:
	var screen := _screen()
	var view := screen.map_view
	view.set_zoom_level(3.5)
	view.focus_force()
	var at := view.to_screen(view.force_world_position(screen.selected_army))
	var before := screen.game.state.duplicate(true)
	view._gui_input(_button(true,at))
	view._gui_input(_motion(at+Vector2(20,0),Vector2(20,0)))
	view._gui_input(_button(false,Vector2(-20,-20)))
	t.check(not view._left_down and not view._left_dragged,"outside release clears the grab")
	t.check_eq(screen.game.state,before,"outside release issues no order")
	view._gui_input(_button(true,at))
	view._gui_input(_motion(at+Vector2(20,0),Vector2(20,0)))
	view._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	view._gui_input(_button(false,at+Vector2(100,0)))
	t.check_eq(screen.game.state,before,"focus loss cancels the pending army drag")
	var panel := PanelContainer.new()
	panel.position = at+Vector2(60,0)
	panel.size = Vector2(100,100)
	view.add_child(panel)
	t.check(not view._drop_on_map(panel.position+Vector2(20,20)),"map child panels reject drops")
	view._gui_input(_button(true,at))
	view.camera_input_enabled = false
	t.check(not view._left_down,"opening a modal cancels the pending gesture")
	screen.free()


func test_portrait_picking_and_recorded_replay_never_read_a_dead_force(t) -> void:
	var screen := _screen()
	var view := screen.map_view
	view.set_zoom_level(5.5)
	view.focus_force()
	for entry in view.banner_layout():
		if entry.get("portrait",false):
			t.check_eq(view._pick(entry["rect"].get_center())["id"],entry["id"],"portrait is picked exactly where it is painted")
	var id := screen.selected_army
	var from: String = screen.game.state["armies"][id]["region"]
	var to := _target(screen)
	var summary := ReconRules.public_summary(screen.game.data,screen.game.state,id)
	var record := {"id":id,"from":from,"to":to,"summary":summary}
	screen.game.state["armies"].erase(id)
	view.refresh_state()
	var before := screen.game.state.duplicate(true)
	t.check(view.play_sighting(record) > 0,"historical sighting can replay after the force is gone")
	var start: Vector2 = view._sighting["position"]
	view._advance_sighting(1.0)
	t.check(view._sighting["position"] != start,"observed column follows the recorded road")
	t.check_eq(screen.game.state,before,"replay has no simulation or RNG effects")
	view.finish_marches()
	t.check(view._sighting.is_empty(),"skipping clears every historical miniature")
	screen.free()


func test_selecting_another_army_during_planning_changes_the_commander(t) -> void:
	var screen := _screen()
	var game := screen.game
	var original := screen.selected_army
	var other := "army_qa"
	game.state["armies"][other] = game.state["armies"][original].duplicate(true)
	game.state["armies"][other]["general"] = null
	screen.refresh()
	screen._begin_map_order()
	screen._on_force_clicked("army",other)
	t.check_eq(screen.selected_army,other,"clicking our second army selects that army even during a plan")
	t.check(not screen._planning_order,"old commander's draft route is cleared")
	screen.free()


func test_observation_beats_are_private_to_the_observer(t) -> void:
	var game := Game.new_campaign("julii",42)
	var journal: Array = []
	TurnJournal.add(journal,"army_sighted",{"faction":"gaul","other":"julii","region":"britannia","value":200,
		"extra":{"from":"","to":"","summary":{}}})
	t.check_eq(DispatchRules.visible_beats(game.data,game.state,journal,"julii").size(),1,"a recorded observation survives later loss of sight")
	t.check(DispatchRules.visible_beats(game.data,game.state,journal,"gaul").is_empty(),"the subject faction does not receive another faction's intelligence")
	t.check(DispatchRules.visible_beats(game.data,game.state,journal,"junii").is_empty(),"a third party cannot read the observer's report")
