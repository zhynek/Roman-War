extends RefCounted

func _screen() -> RomaCityScreen:
	var city := RomaCityScreen.new()
	city.standalone = false
	city.game = Game.new_campaign("senate", 42, "medium", "long", false)
	(Engine.get_main_loop() as SceneTree).root.add_child(city)
	return city

func test_morning_report_guards_double_advance_and_acknowledges_only(t) -> void:
	var city := _screen()
	city.dawn.sound_enabled = false
	city.perform_action("grain_relief")
	city.advance_day()
	t.check_eq(city.status["day"], 2, "day resolves before the ceremony")
	t.check(city.dawn.visible and city.day_button.disabled, "morning report blocks a second day click")
	var resolved := JSON.stringify(city.game.state)
	city.advance_day()
	t.check_eq(JSON.stringify(city.game.state), resolved, "duplicate advance while reading report is ignored")
	city.dawn.dismiss()
	city.show_day_report(false)
	t.check_eq(JSON.stringify(city.game.state), resolved, "replaying the report is read-only")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	city._input(event)
	t.check(not city.dawn.visible, "Escape acknowledges the morning report")
	t.check_eq(JSON.stringify(city.game.state), resolved, "acknowledgment cannot change gameplay or RNG")
	city.free()

func test_future_model_previews_do_not_complete_live_projects(t) -> void:
	var city := _screen()
	city.select_target("tavern", "tavern")
	city.open_drawer("tavern")
	city._choose_dossier_tab("development")
	var live := JSON.stringify(city.game.state)
	city._set_preview_stage("improved")
	var preview = city._building_preview
	t.check_eq(preview.stage, "improved", "future stage is shown in the model viewer")
	t.check(preview.preview_world.project_improvements["improve_tavern"].visible, "viewer uses real completed project meshes")
	t.check(not city.world.project_improvements["improve_tavern"].visible, "live city remains unimproved")
	city._set_preview_stage("construction")
	t.check(preview.preview_world.project_scaffolds["improve_tavern"].visible, "viewer can show work in progress")
	t.check_eq(JSON.stringify(city.game.state), live, "all preview stages leave real projects and RNG unchanged")
	city.free()

func test_muting_and_synthesized_dawn_sound_have_no_gameplay_dependencies(t) -> void:
	var city := _screen()
	city.advance_day()
	var before := JSON.stringify(city.game.state)
	t.check(city.dawn.audio.stream is AudioStreamWAV, "morning strike is generated as PCM audio")
	city.dawn._toggle_sound()
	t.check(not city.dawn.sound_enabled and not city.dawn.audio.playing, "sound may be muted immediately")
	t.check_eq(JSON.stringify(city.game.state), before, "audio and mute cannot advance or alter the city")
	city.free()
