extends RefCounted

func test_study_heightfield_is_repeatable(t) -> void:
	var settings := RealismStudy.read_settings()
	var a := RealismTerrain.new(settings)
	var b := RealismTerrain.new(settings)
	for p in [Vector2(-22,-3),Vector2(15,-15),Vector2(3,-57),Vector2(30,20)]:
		t.check_eq(a.height(p.x,p.y),b.height(p.x,p.y),"study geometry is stable across construction")
	t.check(a.height(-20,-3)<settings.lake.level,"the lake occupies a real depression")
	t.check(a.height(1,-64)>18,"the ridge has substantial relief")

func test_study_column_stays_on_land(t) -> void:
	var terrain := RealismTerrain.new(RealismStudy.read_settings())
	var wet := 0
	var unstable := 0
	for i in range(300):
		var d := terrain.route.get_baked_length()*float(i)/299.0
		for side in [-0.915,0.915]:
			var pose := terrain.sample(terrain.route,d,side)
			if pose.origin.y<float(terrain.spec.lake.level)+0.04:
				wet += 1
			if not pose.origin.is_finite() or not pose.basis.is_finite():
				unstable += 1
	t.check_eq(wet,0,"the full four-file formation avoids water along every bend")
	t.check_eq(unstable,0,"route poses are finite, including both endpoints")

func test_realism_is_explicitly_opt_in(t) -> void:
	var screen := CampaignScreen.create(Game.new_campaign("julii",42))
	screen.open_realism_study()
	t.check(screen.realism_study==null,"normal campaigns do not create or load a 3D viewport")
	var menu := screen._build_options_menu()
	t.check_eq(menu.get_popup().get_item_index(CampaignScreen.OPTION_REALISM),-1,"release options exclude the development study")
	menu.free()
	screen.realism_development_enabled = true
	menu = screen._build_options_menu()
	t.check(menu.get_popup().get_item_index(CampaignScreen.OPTION_REALISM)>=0,"the development build exposes the comparison")
	menu.free()
	screen.free()

func test_realism_paths_use_the_same_ground_as_rendering(t) -> void:
	var terrain := RealismTerrain.new(RealismStudy.read_settings())
	for path in [terrain.route,terrain.flank]:
		for i in range(20):
			var d: float = path.get_baked_length()*i/19.0
			var pose := terrain.sample(path,d)
			t.check_near(pose.origin.y,terrain.height(pose.origin.x,pose.origin.z)+0.035,0.0001,"feet use the terrain height, not a flat-plane approximation")

func test_realism_qa_cannot_use_player_save_slot(t) -> void:
	var source := FileAccess.get_file_as_string("res://tools/realism_preview.gd")
	t.check(source.find('application/config/custom_user_dir_name')<source.find('CampaignScreen.create'),"interactive study isolates storage before creating campaign UI")
	t.check(source.contains('Roman War Realism Study/'),"study uses its own per-process save namespace")
	var entry := FileAccess.get_file_as_string("res://src/ui/realism/development_main.gd")
	t.check(entry.find('application/config/custom_user_dir_name')<entry.find('CampaignScreen.create'),"the packaged entry isolates storage before creating UI")


func test_vegetation_position_channels_are_not_correlated(t) -> void:
	var sum_x := 0.0
	var sum_z := 0.0
	var sum_xz := 0.0
	for i in range(1000):
		var x := RealismModels.scatter("tree/%s" % i,0)-0.5
		var z := RealismModels.scatter("tree/%s" % i,1)-0.5
		sum_x += x
		sum_z += z
		sum_xz += x*z
	t.check(absf(sum_xz/1000.0)<0.012,"vegetation does not align in diagonal rows")
	t.check(absf(sum_x/1000.0)<0.04 and absf(sum_z/1000.0)<0.04,"scatter covers both axes")
