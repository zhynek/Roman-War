extends SceneTree
## Rendered end-to-end map exercise. Screenshots are QA outputs, never assets.
## godot --path . --script res://tools/map_playtest.gd -- out_dir=/tmp/map-playtest
## Uses the real campaign, GUI gestures, command buttons and movement rules.

var _screen: CampaignScreen
var _holder: Control
var _out := "/tmp/map-playtest"
var _failed := false


func _init() -> void:
	# Test/QA scripts must never read or overwrite a player's campaign slot.
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Roman War Map QA/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if _holder != null:
		_holder.size = root.get_visible_rect().size
	return false


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 1000)
	root.grab_focus()
	DirAccess.make_dir_recursive_absolute(_out)
	_holder = Control.new()
	root.add_child(_holder)
	_screen = CampaignScreen.create(Game.new_campaign("julii", 42))
	_holder.add_child(_screen)
	_screen.playback_enabled = false
	_screen.map_view.motion_enabled = true
	for id in _screen.game.state["armies"]:
		if _screen.game.state["armies"][id]["owner"] == "julii":
			_screen.select_force("army", id)
			break
	await _frames(12)
	var view := _screen.map_view
	view.set_zoom_level(0.5)
	view.focus_force()
	await _shot("01-territories")
	view.set_zoom_level(3.5)
	view.focus_force()
	await _shot("02-commander")
	var army_id := _screen.selected_army
	var target := ""
	for id in _screen.game.reachable_regions(army_id)["reach"]:
		var quote := _screen.game.army_order_preview(army_id, id)
		if quote["action"] == "march" and quote["turns"] == 1:
			target = id
			break
	if target == "":
		push_error("map playtest: no reachable destination")
		quit(1)
		return
	var origin: String = _screen.game.state["armies"][army_id]["region"]
	_screen.command_bar.choose.pressed.emit()
	# Frame both towns before clicking: exercise a destination that a player
	# can actually see and reach above the command strip.
	view.set_zoom_level(1.8)
	var midpoint := (view.world_pos(_screen.game.data.regions[origin]) + view.world_pos(_screen.game.data.regions[target])) * 0.5
	view._camera_offset = -midpoint + Vector2(view.size.x * 0.5, (view.size.y - _screen.command_bar.size.y) * 0.5) / view._zoom
	var point := view.to_screen(view.world_pos(_screen.game.data.regions[target]))
	_check(Rect2(Vector2.ZERO, Vector2(view.size.x, _screen.command_bar.position.y)).has_point(point), "the destination is visible above the controls")
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		view._gui_input(event)
	_check(_screen._pinned_target == target, "left-click pins the route")
	_check(_screen.game.state["armies"][army_id]["region"] == origin, "planning is read-only")
	await _shot("03-route-planned")
	view.set_zoom_level(3.5)
	view.focus_force()
	_screen.command_bar.issue.pressed.emit()
	_check(_screen.game.state["armies"][army_id]["region"] == target, "the issued army reaches its destination")
	await create_timer(0.5).timeout
	await _shot("04-on-the-road")
	await create_timer(4.1).timeout
	await _shot("05-arrival")
	_check(view._marches.is_empty(), "the visual march completes")
	view.set_zoom_level(5.5)
	view.focus_force()
	await _shot("06-maximum-detail")
	# Image readback is a synchronous GPU stall, so exclude screenshots and
	# the zoom transition from the frame-time sample.
	await _frames(20)
	var samples: Array = []
	for i in range(90):
		var start := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("map playtest: ", "FAIL" if _failed else "PASS", " · final zoom ", view._zoom,
		" · median frame ms ", samples[45], " · p95 frame ms ", samples[85],
		" · FPS ", Performance.get_monitor(Performance.TIME_FPS))
	quit(1 if _failed else 0)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(label: String) -> void:
	# macOS may suppress draws for an occluded QA window. Explicit frames
	# also allow deferred 3D illustration captures to finish before readback.
	for i in range(6):
		await process_frame
		RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(_out.path_join(label + ".png"))
	print("saved ", _out.path_join(label + ".png"))


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	_failed = _failed or not condition
