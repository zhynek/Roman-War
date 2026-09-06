class_name MapOverview
extends Control
## A geographic inset keeps close views grounded. Only known ownership and
## our armies are drawn; camera navigation has no effect on the simulation.

var view: MapView


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -190
	offset_right = -14
	offset_top = 14
	offset_bottom = 116
	if DisplayServer.get_name() != "headless":
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _transform() -> Transform2D:
	var bounds := view.geometry.world_rect
	var scale := minf((size.x - 12) / bounds.size.x, (size.y - 12) / bounds.size.y)
	var offset := (size - bounds.size * scale) * 0.5 - bounds.position * scale
	return Transform2D(0, Vector2.ONE * scale, 0, offset)


func _draw() -> void:
	if view == null or view.geometry == null:
		return
	draw_style_box(UiStyle._flat(Color(0.055, 0.105, 0.14, 0.95), 6), Rect2(Vector2.ZERO, size))
	var transform := _transform()
	for id in view.known_cache:
		if view.geometry.cells.has(id):
			for fill in view.geometry.cells[id]["fills"]:
				draw_colored_polygon(transform * fill, Color("#566553"))
	for id in view.visible_cache:
		if not view.geometry.cells.has(id):
			continue
		for fill in view.geometry.cells[id]["fills"]:
			draw_colored_polygon(transform * fill, view.owner_colors.get(id, UiStyle.LAND_BASE))
	for id in view.army_visuals:
		if view.game.state["armies"][id]["owner"] == view.game.state["player_faction"]:
			draw_circle(transform * view.force_world_position(id), 2, Color.WHITE if id == view.selected_force else UiStyle.CAPITAL_GOLD)
	var camera := Rect2(-view._camera_offset, view.size / view._zoom)
	var frame := Rect2(transform * camera.position, camera.size * transform.get_scale())
	draw_rect(frame.intersection(Rect2(Vector2.ONE * 2, size - Vector2.ONE * 4)), Color(0.98, 0.93, 0.75), false, 1)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.ACCENT, 0.55), false, 1)


func _gui_input(event: InputEvent) -> void:
	if view == null or view.geometry == null:
		return
	var pressed: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var dragging: bool = event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT
	if pressed or dragging:
		var world: Vector2 = _transform().affine_inverse() * event.position
		view._panning = false
		view._follow_force = ""
		view._camera_offset = -world + view.size / (2 * view._zoom)
		view._clear_hover()
		queue_redraw()
		accept_event()
