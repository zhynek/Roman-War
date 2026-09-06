extends SceneTree
## Interactive comparison, isolated from player saves:
## godot --path . --script res://tools/realism_preview.gd
## Add -- qa out_dir=/tmp/roman-war-realism to capture/check and exit.
var screen: CampaignScreen
var holder: Control
var qa := false
var out_dir := "/tmp/roman-war-realism"
var failed := false

func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","Roman War Realism Study/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for arg in OS.get_cmdline_user_args():
		if arg=="qa":
			qa = true
		elif arg.begins_with("out_dir="):
			out_dir = arg.trim_prefix("out_dir=")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if holder != null:
		holder.size = root.get_visible_rect().size
	return false

func _run() -> void:
	holder = Control.new()
	root.add_child(holder)
	screen = CampaignScreen.create(Game.new_campaign("julii",42))
	screen.realism_development_enabled = true
	holder.add_child(screen)
	screen.playback_enabled = false
	for id in screen.game.state.armies:
		if screen.game.state.armies[id].owner=="julii":
			screen.select_force("army",id)
			break
	screen.map_view.set_zoom_level(3.5)
	screen.map_view.focus_force()
	await frames(4)
	# A persistent comparison button belongs to this dev harness only.
	var compare := Button.new()
	compare.text = RealismStudy.read_settings().copy.reopen
	compare.position = Vector2(16,186)
	compare.pressed.connect(screen.open_realism_study)
	screen.add_child(compare)
	if qa:
		DirAccess.make_dir_recursive_absolute(out_dir)
		await shot("01-existing-campaign")
	var snapshot := JSON.stringify(screen.game.state)
	screen.open_realism_study()
	await frames(8)
	if not qa:
		return
	var study := screen.realism_study
	# Real viewport routing, rather than directly calling the camera helper.
	var yaw_before := study.world.yaw
	var begin := Vector2(540,400)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = begin
	root.push_input(press,true)
	await frames(1)
	var drag := InputEventMouseMotion.new()
	drag.position = begin+Vector2(110,30)
	drag.relative = Vector2(110,30)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag,true)
	await frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = drag.position
	root.push_input(release,true)
	await frames(1)
	check(not is_equal_approx(yaw_before,study.world.yaw),"drag events routed through the viewport orbit the camera")
	study.world.set_camera("overview")
	await shot("02-landscape-planning")
	study.world.set_camera("column")
	study.set_progress(0.28)
	await shot("03-marching-column")
	study.world.set_camera("woods")
	study.set_progress(0.73)
	await shot("04-woodland-emergence")
	study.set_progress(1.0)
	await shot("05-contact-arrival")
	study.world.set_camera("column")
	study.world.target = study.world.friendly.multimesh.get_instance_transform(24).origin
	study.world.distance = 9
	study.world.pitch = 0.26
	study.world.update_camera()
	await shot("06-maximum-troop-detail")
	study.world.set_camera("pass")
	await shot("07-mountain-pass")
	study.world.set_camera("overview")
	study.set_progress(0.55)
	study.set_playing(true)
	var samples: Array[float] = []
	for i in range(75):
		var start := Time.get_ticks_usec()
		await process_frame
		samples.append((Time.get_ticks_usec()-start)/1000.0)
	var gait_before: float = study.world.army_material.get_shader_parameter("walking")
	study.set_playing(false)
	check(study.world.army_material.get_shader_parameter("walking")==gait_before,"pausing freezes the gait instead of resetting it")
	samples.sort()
	print("Realism frame times: median %.1f ms, p95 %.1f ms" % [samples[37],samples[71]])
	check(JSON.stringify(screen.game.state)==snapshot,"camera, scrubbing and playback preserve entire campaign and RNG")
	study.dismiss()
	await frames(3)
	check(study.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"hidden 3D viewport stops rendering")
	check(screen.map_view.camera_input_enabled,"classic map input resumes")
	screen.open_realism_study()
	await frames(3)
	check(study.visible and not study.playing,"comparison reopens paused")
	print("Realism rendered QA: %s" % ("FAILED" if failed else "passed"))
	quit(1 if failed else 0)

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name+".png"))
	print("Saved "+name)

func check(condition: bool, message: String) -> void:
	print(("ok " if condition else "FAIL ")+message)
	failed = failed or not condition
