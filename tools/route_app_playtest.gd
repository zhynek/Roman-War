extends SceneTree
## Actual development entry-point smoke at the minimum review window size.
## Pass -- route-qa so its Save/Load namespace is disposable.
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var entry = load("res://src/ui/realism/development.tscn").instantiate()
	root.add_child(entry)
	for i in range(12):
		await process_frame
		RenderingServer.force_draw(false)
	var rect: Rect2 = entry.route_panel.get_rect()
	var command_top := float(entry.screen.command_bar.position.y)
	var ok: bool = rect.end.y < command_top and rect.end.x < entry.screen.map_view.size.x
	print("route app minimum-window briefing fit: ", "PASS" if ok else "FAIL", " ", rect, " command top ", command_top)
	var view: MapView = entry.screen.map_view
	var at := view.to_screen(view.force_world_position(entry.screen.selected_army))
	var focused := Rect2(Vector2.ZERO, Vector2(view.size.x, command_top)).has_point(at)
	print("route app initial army is visible above controls: ", "PASS" if focused else "FAIL")
	ok = ok and focused
	print("route app save isolation: ", OS.get_user_data_dir())
	root.get_texture().get_image().save_png("/tmp/roman-route-app-minimum.png")
	quit(0 if ok else 1)
