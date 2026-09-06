class_name RealismStudy
extends Control
## Development-only presentation overlay. Owns a SubViewport, not a game state.
## Closing/comparing freezes and disables the viewport; the campaign keeps its
## original renderer. Reopening resumes the same paused study.
signal closed
var world: RealismWorld
var viewport: SubViewport
var surface: SubViewportContainer
var settings: Dictionary
var copy: Dictionary
var progress := 0.0
var playing := false
var slider: HSlider
var play_button: Button
var stage_label: Label
var note_label: Label
var fps_label: Label
var markers := {}
var _dragging := false
var _drag_distance := 0.0
var _drag_last := Vector2.ZERO
var _notes_visible := true
var _fps_elapsed := 0.0
var _syncing_slider := false

static func read_settings() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/realism_study.json"))

func _ready() -> void:
	settings = read_settings()
	copy = settings.copy
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	surface = SubViewportContainer.new()
	surface.stretch = true
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface.add_child(viewport)
	world = RealismWorld.new()
	viewport.add_child(world)
	world.build(settings)
	# The viewport container forwards events into its world. A sibling input
	# surface keeps orbit/picking in this UI, above the viewport and below HUD.
	var camera_input := Control.new()
	camera_input.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	camera_input.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(camera_input)
	camera_input.gui_input.connect(_on_surface_input)
	_build_interface()
	visibility_changed.connect(_on_visibility)
	set_progress(0.0)

func _panel(parent: Node, position_by: Vector2, size_by: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.055,0.06,0.91)
	style.border_color = Color(0.72,0.64,0.43,0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel",style)
	panel.position = position_by
	panel.size = size_by
	parent.add_child(panel)
	return panel

func _label(value: String, font_size: int = 14, tint: Color = Color("#d9dfd6")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(key: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = copy[key]
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34
	button.add_theme_font_size_override("font_size",13)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#253333")
	style.border_color = Color("#647366")
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.set_corner_radius_all(2)
	button.add_theme_stylebox_override("normal",style)
	var hover := style.duplicate()
	hover.bg_color = Color("#465348")
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_color_override("font_color",Color("#eee7d5"))
	button.pressed.connect(callback)
	return button

func _build_interface() -> void:
	var top := _panel(self,Vector2(20,18),Vector2(470,108))
	var titles := VBoxContainer.new()
	top.add_child(titles)
	titles.add_child(_label(copy.eyebrow,11,Color("#c3af7d")))
	var title := _label(copy.name,30,Color("#f1ead9"))
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia","Times New Roman"])
	title.add_theme_font_override("font",serif)
	titles.add_child(title)
	titles.add_child(_label(copy.subtitle,13))
	var compare := _button("classic",dismiss)
	compare.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	compare.position = Vector2(-200,24)
	compare.size = Vector2(180,38)
	add_child(compare)
	# Four camera presets remain in a wrapping row on narrow windows.
	var cameras := HFlowContainer.new()
	cameras.position = Vector2(20,139)
	cameras.size.x = 600
	cameras.add_theme_constant_override("h_separation",7)
	add_child(cameras)
	for key in ["overview","column","woods","pass"]:
		cameras.add_child(_button(key,func(): world.set_camera(key)))
	var info := _panel(self,Vector2.ZERO,Vector2(300,260))
	info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info.offset_left = -320
	info.offset_top = 82
	info.offset_right = -20
	var notes := VBoxContainer.new()
	notes.add_theme_constant_override("separation",9)
	info.add_child(notes)
	notes.add_child(_label(copy.prototype,11,Color("#c3af7d")))
	var scope := _label(copy.scope,13)
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scope.custom_minimum_size.x = 260
	notes.add_child(scope)
	notes.add_child(HSeparator.new())
	stage_label = _label("",15,Color("#eee4cc"))
	stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_child(stage_label)
	note_label = _label("",13)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_child(note_label)
	var route_toggle := CheckBox.new()
	route_toggle.text = copy.route_toggle
	route_toggle.button_pressed = true
	route_toggle.toggled.connect(func(value: bool): world.route_line.visible = value)
	notes.add_child(route_toggle)
	var notes_toggle := CheckBox.new()
	notes_toggle.text = copy.labels_toggle
	notes_toggle.button_pressed = true
	notes_toggle.toggled.connect(func(value: bool): _notes_visible = value)
	notes.add_child(notes_toggle)
	fps_label = _label("",11,Color("#9baca1"))
	fps_label.visible = false
	notes.add_child(fps_label)
	for key in ["lake","marsh","forest","mountain"]:
		var marker := _button(key,func(): show_terrain_note(key))
		marker.add_theme_font_size_override("font_size",10)
		marker.custom_minimum_size.y = 26
		marker.modulate.a = 0.88
		add_child(marker)
		markers[key] = marker
	var bottom := _panel(self,Vector2.ZERO,Vector2.ZERO)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.offset_top = -143
	bottom.offset_bottom = -18
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation",8)
	bottom.add_child(controls)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	controls.add_child(row)
	play_button = _button("play",toggle_play)
	row.add_child(play_button)
	row.add_child(_button("ambush",start_emergence))
	row.add_child(_button("replay",func(): set_progress(0); set_playing(true)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_label(copy.timeline,11,Color("#c3af7d")))
	slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.001
	slider.custom_minimum_size.y = 18
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float):
		if not _syncing_slider:
			set_playing(false)
			set_progress(value))
	controls.add_child(slider)
	controls.add_child(_label(copy.controls,11,Color("#a5b1a5")))

func show_terrain_note(key: String) -> void:
	stage_label.text = copy[key]
	note_label.text = copy[key+"_note"]

func set_progress(value: float) -> void:
	progress = clampf(value,0,1)
	if world == null:
		return
	world.set_progress(progress,playing)
	if slider != null:
		_syncing_slider = true
		slider.value = progress
		_syncing_slider = false
	var phase := "planning" if progress<0.06 else ("marching" if progress<0.50 else ("contact" if progress<0.92 else "arrival"))
	stage_label.text = copy[phase]
	note_label.text = copy[phase+"_note"]

func set_playing(value: bool) -> void:
	playing = value
	play_button.text = copy.pause if playing else (copy.replay if progress>=1 else copy.play)
	world.set_progress(progress,playing)

func toggle_play() -> void:
	if not playing and progress>=1:
		set_progress(0)
	set_playing(not playing)

func start_emergence() -> void:
	world.set_camera("woods")
	set_progress(0.43)
	set_playing(true)

func dismiss() -> void:
	set_playing(false)
	hide()
	closed.emit()

func _on_visibility() -> void:
	if viewport == null:
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if not is_visible_in_tree():
		set_playing(false)
		_dragging = false

func _process(delta: float) -> void:
	if not is_visible_in_tree() or world == null:
		return
	if playing:
		set_progress(progress+delta/float(settings.duration))
		if progress>=1:
			set_playing(false)
	_fps_elapsed += delta
	if _fps_elapsed>0.5:
		fps_label.text = String(copy.fps).replace("{fps}",str(Engine.get_frames_per_second()))
		_fps_elapsed = 0
	for key in markers:
		var marker: Button = markers[key]
		var at: Vector3 = world.marker_positions[key]
		var pixel := world.camera.unproject_position(at)
		marker.visible = _notes_visible and world.distance>45 and not world.camera.is_position_behind(at) and Rect2(20,190,size.x-350,size.y-355).has_point(pixel)
		marker.position = pixel-marker.size*0.5

func _on_surface_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_drag_distance = 0
				_drag_last = event.position
			elif _drag_distance<4 and event.button_index==MOUSE_BUTTON_LEFT:
				var picked := world.pick_formation(event.position)
				if picked!="":
					world.selected_formation = picked
					stage_label.text = copy.unit_title
					note_label.text = copy.unit_note if picked=="friendly" else copy.contact_note
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			world.distance *= exp((-0.10 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.10)*maxf(event.factor,0.05))
			world.update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var relative: Vector2 = event.position-_drag_last
		_drag_last = event.position
		_drag_distance += relative.length()
		if event.shift_pressed or event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var shift := Vector3(-relative.x,0,-relative.y).rotated(Vector3.UP,world.yaw)*world.distance*0.0014
			world.target += shift
		else:
			world.yaw -= relative.x*0.006
			world.pitch += relative.y*0.004
		world.update_camera()
	elif event is InputEventMagnifyGesture:
		world.distance /= maxf(event.factor,0.1)
		world.update_camera()
	elif event is InputEventPanGesture:
		world.yaw -= event.delta.x*0.02
		world.pitch += event.delta.y*0.02
		world.update_camera()
	accept_event()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			dismiss()
		elif event.keycode==KEY_SPACE:
			toggle_play()
		# The overlay owns keyboard focus; campaign shortcuts cannot change state.
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false
		if play_button != null and playing:
			set_playing(false)
