extends "res://tools/integration_guide_checks.gd"
## Actual pointer navigation over the same assertions, with external QA captures.
func _initialize() -> void:
	out_dir="/tmp/village-integration-guide-render";rendered=true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):out_dir=arg.trim_prefix("out_dir=")
	call_deferred("run")
func click(id: String) -> void:
	var button=app.find_child(id,true,false)
	check(button is Button and not button.disabled,"usable pointer control "+id)
	if not button is Button or button.disabled:return
	var parent=button.get_parent()
	while parent!=null:
		if parent is ScrollContainer:parent.ensure_control_visible(button)
		parent=parent.get_parent()
	await process_frame;await process_frame
	var at: Vector2=button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true);await process_frame
	await process_frame;await process_frame
func shot(id: String) -> void:
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(id+".png"));captures.append(id+".png")
func setup_shot() -> void:
	var at: Vector2=app.visual_commands.sheet.get_global_rect().get_center()
	for i in range(12):
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.position=at;event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=pressed
			root.push_input(event,true);await process_frame
	await shot("setup-and-adoption")
