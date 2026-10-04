extends Node3D
## Standalone presentation and authoring. Never imports campaign code or saves.

signal city_ready

const Layout = preload("res://src/layout.gd")
const VARIANT_FILE := "user://creative_variant_v1.json"
const MAX_ADDITIONS := 500
const KIT := ["house", "workshop", "church", "tower"]
enum Navigation { ORBIT, FLY, WALK }

var camera: Camera3D
var world: Node3D
var data: Dictionary = {}
var stats: Dictionary = {}
var current_stage: String = ""
var ready_for_capture := false
var design_objects: Array = []

var _words: Dictionary = {}
var _landmarks: Dictionary = {}
var _sources: Dictionary = {}
var _ordered_ids: Array[String] = []
var _selected_landmark := ""
var _selected_design := ""
var _undo: Array = []
var _next_design_id := 1
# QA overrides this private path before exercising persistence in /tmp.
var _variant_path := VARIANT_FILE
var _navigation: int = Navigation.ORBIT
var _orbit_target := Vector3.ZERO
var _orbit_distance := 1000.0
var _orbit_yaw := deg_to_rad(35.0)
var _orbit_pitch := deg_to_rad(42.0)
var _fly_yaw := 0.0
var _fly_pitch := -0.3
var _fly_speed := 65.0
var _inside_architecture := false
var _interior_center := Vector3.ZERO
var _interior_radius := 100.0
var _interior_floor := 0.0
var _orbit_drag := false
var _pan_drag := false
var _placing := false
var _editing := false
var _bounds := Rect2(-5000.0, -5000.0, 10000.0, 10000.0)
var _daytime := 15.0
var _environment: Environment
var _sun: DirectionalLight3D
var _canvas: CanvasLayer
var _hud: Control
var _status: Label
var _help: Label
var _stats_label: Label
var _stage_picker: OptionButton
var _nav_picker: OptionButton
var _time_slider: HSlider
var _time_label: Label
var _place_list: VBoxContainer
var _info_title: Label
var _info_description: RichTextLabel
var _info_evidence: Label
var _info_sources: Label
var _cutaway_toggle: CheckBox
var _interior_button: Button
var _source_button: Button
var _selected_source_url := ""
var _inspector_content: VBoxContainer
var _inspector_collapse: Button
var _inspector_collapsed := false
var _editor_panel: PanelContainer
var _inspector_panel: PanelContainer
var _kit_picker: OptionButton
var _place_toggle: Button
var _scale_slider: HSlider
var _rotation_slider: HSlider
var _design_label: Label
var _design_count: Label
var _updating_editor := false
var _slider_editing := false


func _ready() -> void:
	_words = _read_dictionary("res://data/ui.json")
	data = _read_dictionary("res://data/city.json")
	_build_lighting()
	camera = Camera3D.new()
	camera.name = "StudyCamera"
	camera.near = 0.25
	camera.far = 32000.0
	camera.fov = 58.0
	camera.current = true
	add_child(camera)
	_index_data()
	_build_ui()
	_set_status("loading")
	await get_tree().process_frame
	await get_tree().process_frame
	if data.is_empty():
		_set_status("data_error")
		return
	var world_script = load("res://src/world.gd")
	if not world_script is Script or not world_script.can_instantiate():
		_set_status("data_error")
		return
	world = world_script.new()
	world.name = "CityWorld"
	add_child(world)
	world.call("configure", data)
	stats = world.get("stats")
	if not data.get("stages", []).is_empty():
		set_stage(str(data["stages"][0]["id"]))
	set_daytime(_daytime)
	home_view()
	_refresh_stats()
	_set_status("ready")
	await get_tree().process_frame
	await get_tree().process_frame
	ready_for_capture = true
	city_ready.emit()


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}


func _t(key: String) -> String:
	return str(_words.get(key, key))


func _index_data() -> void:
	for source in data.get("sources", []):
		_sources[str(source.get("id", ""))] = source
	for landmark in data.get("landmarks", []):
		var identity := str(landmark.get("id", ""))
		_landmarks[identity] = landmark
		_ordered_ids.append(identity)
	var boundary: Array = data.get("site", {}).get("boundary_m", [])
	if not boundary.is_empty():
		var minimum := Vector2(float(boundary[0][0]), float(boundary[0][1]))
		var maximum := minimum
		for point in boundary:
			minimum = minimum.min(Vector2(float(point[0]), float(point[1])))
			maximum = maximum.max(Vector2(float(point[0]), float(point[1])))
		_bounds = Rect2(minimum, maximum - minimum)


func _build_lighting() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color("356f9b")
	material.sky_horizon_color = Color("a6c3cf")
	material.ground_bottom_color = Color("536653")
	material.ground_horizon_color = Color("a6c3cf")
	material.sky_curve = 0.32
	material.sky_energy_multiplier = 0.85
	material.ground_energy_multiplier = 0.6
	sky.sky_material = material
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_color = Color("d3e3e5")
	_environment.ambient_light_energy = 0.42
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_exposure = 0.91
	_environment.fog_enabled = true
	_environment.fog_light_color = Color("9ebdc7")
	_environment.fog_density = 0.000015
	_environment.fog_sun_scatter = 0.09
	_environment.ssao_enabled = true
	_environment.ssao_radius = 2.5
	_environment.ssao_intensity = 1.5
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.08
	var environment_node := WorldEnvironment.new()
	environment_node.environment = _environment
	add_child(environment_node)
	_sun = DirectionalLight3D.new()
	_sun.name = "StudySun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 6000.0
	_sun.directional_shadow_blend_splits = true
	_sun.shadow_bias = 0.025
	_sun.shadow_normal_bias = 1.2
	_sun.light_angular_distance = 0.65
	add_child(_sun)


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "StudyInterface"
	add_child(_canvas)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_hud)
	var theme := Theme.new()
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", Color("f0e6cf"))
	theme.set_color("font_color", "Button", Color("f3e8cf"))
	theme.set_color("font_hover_color", "Button", Color("ffffff"))
	theme.set_color("font_color", "OptionButton", Color("f3e8cf"))
	theme.set_color("font_color", "CheckBox", Color("f3e8cf"))
	theme.set_stylebox("normal", "Button", _style(Color("3d504d"), 5))
	theme.set_stylebox("hover", "Button", _style(Color("536b60"), 5))
	theme.set_stylebox("pressed", "Button", _style(Color("8b734e"), 5))
	theme.set_stylebox("normal", "OptionButton", _style(Color("3d504d"), 5))
	theme.set_stylebox("hover", "OptionButton", _style(Color("536b60"), 5))
	theme.set_stylebox("panel", "PopupMenu", _style(Color("243532"), 5))
	theme.set_color("font_color", "PopupMenu", Color("f3e8cf"))
	_hud.theme = theme

	var header := _panel()
	_hud.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 18
	header.offset_right = -18
	header.offset_top = 14
	header.offset_bottom = 80
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 24)
	header.add_child(heading)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_box)
	var title := _label(_t("app_title"), 24, Color("ead5a8"))
	title_box.add_child(title)
	title_box.add_child(_label(_t("app_subtitle"), 12, Color("c1c9bb")))
	var scope := _label(_t("historical_scope"), 13, Color("c1c9bb"))
	scope.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(scope)
	for action in [["home_button", home_view], ["overview_button", overview], ["plan_button", plan_view]]:
		var header_button := _button(str(action[0]), action[1])
		header_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		header_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header_button.custom_minimum_size = Vector2(112, 34)
		heading.add_child(header_button)

	var sidebar := _panel()
	_hud.add_child(sidebar)
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	sidebar.offset_left = 18
	sidebar.offset_right = 262
	sidebar.offset_top = 96
	sidebar.offset_bottom = -112
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 9)
	sidebar.add_child(left)
	left.add_child(_label(_t("places_title"), 13, Color("c8ad79")))
	var note := _label(_t("places_note"), 12, Color("bcc5b6"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_place_list = VBoxContainer.new()
	_place_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_place_list)
	for identity in _ordered_ids:
		var place: Dictionary = _landmarks[identity]
		var button := Button.new()
		button.text = str(place.get("name", identity))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 35
		button.pressed.connect(focus_landmark.bind(identity))
		_place_list.add_child(button)
	left.add_child(_button("tour_button", next_place))
	left.add_child(HSeparator.new())
	left.add_child(_label(_t("stage_label"), 11, Color("c8ad79")))
	_stage_picker = OptionButton.new()
	_stage_picker.custom_minimum_size.y = 34
	_stage_picker.fit_to_longest_item = false
	for stage in data.get("stages", []):
		_stage_picker.add_item(str(stage.get("name", stage["id"])))
	_stage_picker.item_selected.connect(_on_stage_selected)
	left.add_child(_stage_picker)
	left.add_child(_label(_t("nav_label"), 11, Color("c8ad79")))
	_nav_picker = OptionButton.new()
	_nav_picker.custom_minimum_size.y = 34
	for key in ["nav_orbit", "nav_fly", "nav_walk"]:
		_nav_picker.add_item(_t(key))
	_nav_picker.item_selected.connect(_set_navigation)
	left.add_child(_nav_picker)
	var time_row := HBoxContainer.new()
	var time_title := _label(_t("time_label"), 11, Color("c8ad79"))
	time_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(time_title)
	_time_label = _label("", 12, Color("f0e6cf"))
	time_row.add_child(_time_label)
	left.add_child(time_row)
	_time_slider = HSlider.new()
	_time_slider.min_value = 7.0
	_time_slider.max_value = 18.0
	_time_slider.step = 0.1
	_time_slider.value = _daytime
	_time_slider.value_changed.connect(set_daytime)
	left.add_child(_time_slider)
	var quality := CheckBox.new()
	quality.text = _t("quality_label")
	quality.button_pressed = true
	quality.toggled.connect(_set_quality)
	left.add_child(quality)
	left.add_child(_button("edit_button", _toggle_editor))
	left.add_child(_button("open_folder_button", func(): OS.shell_open(ProjectSettings.globalize_path("user://"))))

	_inspector_panel = _panel()
	_hud.add_child(_inspector_panel)
	_inspector_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_inspector_panel.offset_left = -346
	_inspector_panel.offset_right = -18
	_inspector_panel.offset_top = 96
	_inspector_panel.offset_bottom = 480
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	_inspector_panel.add_child(info)
	var info_header := HBoxContainer.new()
	var info_caption := _label(_t("inspector_title"), 11, Color("c8ad79"))
	info_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_header.add_child(info_caption)
	_inspector_collapse = _button("inspector_collapse", _toggle_inspector)
	_inspector_collapse.size_flags_horizontal = Control.SIZE_SHRINK_END
	_inspector_collapse.custom_minimum_size = Vector2(30, 27)
	_inspector_collapse.tooltip_text = _t("inspector_toggle_hint")
	info_header.add_child(_inspector_collapse)
	info.add_child(info_header)
	_inspector_content = VBoxContainer.new()
	_inspector_content.add_theme_constant_override("separation", 10)
	info.add_child(_inspector_content)
	info = _inspector_content
	_info_title = _label("", 23, Color("f3e6c7"))
	_info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_info_title)
	_info_description = RichTextLabel.new()
	_info_description.bbcode_enabled = false
	_info_description.fit_content = false
	_info_description.custom_minimum_size.y = 145
	_info_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_description.add_theme_color_override("default_color", Color("d2d6c7"))
	_info_description.text = _t("inspector_empty")
	info.add_child(_info_description)
	info.add_child(_label(_t("evidence_label"), 11, Color("c8ad79")))
	_info_evidence = _label("", 12, Color("d2d6c7"))
	_info_evidence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_info_evidence)
	_info_sources = _label("", 11, Color("a8b9ad"))
	_info_sources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_sources.max_lines_visible = 3
	_info_sources.custom_minimum_size.y = 44
	_info_sources.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_info_sources)
	_source_button = _button("source_button", _open_selected_source)
	_source_button.visible = false
	info.add_child(_source_button)
	_cutaway_toggle = CheckBox.new()
	_cutaway_toggle.text = _t("cutaway_label")
	_cutaway_toggle.visible = false
	_cutaway_toggle.toggled.connect(set_cutaway)
	info.add_child(_cutaway_toggle)
	info.add_child(_button("focus_button", func(): focus_landmark(_selected_landmark)))
	_interior_button = _button("interior_button", func(): interior_view(_selected_landmark))
	_interior_button.visible = false
	info.add_child(_interior_button)
	_build_editor()

	var footer := _panel()
	_hud.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 18
	footer.offset_right = -18
	footer.offset_top = -95
	footer.offset_bottom = -16
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 4)
	footer.add_child(bottom)
	var status_row := HBoxContainer.new()
	_status = _label("", 13, Color("e8d4a7"))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(_status)
	_stats_label = _label("", 11, Color("aebfae"))
	status_row.add_child(_stats_label)
	bottom.add_child(status_row)
	_help = _label(_t("help_orbit"), 12, Color("c1c9bb"))
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_help)
	_refresh_design_labels()


func _build_editor() -> void:
	_editor_panel = _panel()
	_hud.add_child(_editor_panel)
	_editor_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_editor_panel.offset_left = -346
	_editor_panel.offset_right = -18
	_editor_panel.offset_top = 96
	_editor_panel.offset_bottom = -112
	_editor_panel.visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_editor_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	box.add_child(_label(_t("editor_title"), 15, Color("e4c792")))
	var note := _label(_t("editor_note"), 12, Color("d2d6c7"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	box.add_child(_label(_t("kit_label"), 11, Color("c8ad79")))
	_kit_picker = OptionButton.new()
	_kit_picker.custom_minimum_size.y = 36
	for kind in KIT:
		_kit_picker.add_item(_t("kit_" + kind))
	box.add_child(_kit_picker)
	_place_toggle = _button("place_button", _toggle_placement)
	_place_toggle.toggle_mode = true
	box.add_child(_place_toggle)
	box.add_child(_button("select_button", _begin_selection))
	_design_label = _label("", 12, Color("e4c792"))
	_design_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_design_label)
	box.add_child(_label(_t("rotation_label"), 11, Color("c8ad79")))
	_rotation_slider = HSlider.new()
	_rotation_slider.min_value = 0
	_rotation_slider.max_value = 345
	_rotation_slider.step = 15
	_rotation_slider.drag_started.connect(_begin_slider_edit)
	_rotation_slider.drag_ended.connect(_end_slider_edit)
	_rotation_slider.value_changed.connect(_on_rotation_changed)
	box.add_child(_rotation_slider)
	box.add_child(_button("rotate_button", rotate_selected))
	box.add_child(_label(_t("scale_label"), 11, Color("c8ad79")))
	_scale_slider = HSlider.new()
	_scale_slider.min_value = 0.35
	_scale_slider.max_value = 3.0
	_scale_slider.step = 0.05
	_scale_slider.value = 1.0
	_scale_slider.drag_started.connect(_begin_slider_edit)
	_scale_slider.drag_ended.connect(_end_slider_edit)
	_scale_slider.value_changed.connect(_on_scale_changed)
	box.add_child(_scale_slider)
	var actions := HBoxContainer.new()
	actions.add_child(_button("delete_button", delete_selected))
	actions.add_child(_button("undo_button", undo_edit))
	box.add_child(actions)
	box.add_child(HSeparator.new())
	_design_count = _label("", 12, Color("c1c9bb"))
	_design_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_design_count)
	var save_row := HBoxContainer.new()
	save_row.add_child(_button("save_button", save_variant))
	save_row.add_child(_button("load_button", load_variant))
	box.add_child(save_row)
	box.add_child(_button("clear_button", clear_design))
	box.add_child(_button("close_editor", _toggle_editor))


func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _style(Color(0.085, 0.135, 0.125, 0.94), 7)
	style.border_color = Color(0.68, 0.57, 0.36, 0.45)
	style.set_border_width_all(1)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(key: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = _t(key)
	button.custom_minimum_size.y = 34
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


func focus_landmark(identity: String) -> void:
	if not _landmarks.has(identity):
		return
	_selected_landmark = identity
	var landmark: Dictionary = _landmarks[identity]
	_orbit_target = Layout.world(data, landmark["position_m"])
	_orbit_target.y += float(landmark.get("dimensions", {}).get("height_m", 12.0)) * 0.35
	_orbit_distance = clampf(float(landmark.get("tour_distance_m", 220.0)), 45.0, 5000.0)
	_orbit_pitch = deg_to_rad(30.0)
	_orbit_yaw = deg_to_rad(35.0)
	_set_navigation(Navigation.ORBIT)
	_apply_orbit()
	_info_title.text = str(landmark.get("name", identity))
	_info_description.text = str(landmark.get("description", ""))
	_info_evidence.text = str(landmark.get("evidence", ""))
	var source_titles: Array[String] = []
	_selected_source_url = ""
	for source_id in landmark.get("source_ids", []):
		if _sources.has(str(source_id)):
			var source: Dictionary = _sources[str(source_id)]
			source_titles.append(str(source.get("title", "")))
			if _selected_source_url.is_empty() and _safe_source_url(str(source.get("url", ""))):
				_selected_source_url = str(source["url"])
	_info_sources.text = "\n".join(source_titles)
	_info_sources.tooltip_text = _info_sources.text
	_source_button.visible = not _selected_source_url.is_empty()
	_set_status_text(_t("distance_template") % [_info_title.text, int(_orbit_distance)])
	var underground := str(landmark.get("kind", "")) == "cistern" and not bool(landmark.get("dimensions", {}).get("open_top", 0))
	_cutaway_toggle.visible = underground
	_cutaway_toggle.set_pressed_no_signal(underground)
	set_cutaway(underground)
	_interior_button.visible = str(landmark.get("kind", "")) in ["hagia_sophia", "church", "monastery", "palace", "cistern", "hippodrome"]


func _safe_source_url(url: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^https://[A-Za-z0-9.-]+(?:[/?#][^\\s]*)?$")
	return pattern.search(url) != null


func _open_selected_source() -> void:
	if _safe_source_url(_selected_source_url):
		OS.shell_open(_selected_source_url)


func interior_view(identity: String = "") -> void:
	if identity.is_empty():
		identity = _selected_landmark
	if world == null or not _landmarks.has(identity):
		return
	var nodes: Dictionary = world.get("landmark_nodes")
	if not nodes.has(identity):
		return
	focus_landmark(identity)
	var node: Node3D = nodes[identity]
	var anchor: Vector3 = node.get_meta("interior_anchor", Vector3(0, 2, 0))
	_set_navigation(Navigation.FLY)
	if str(_landmarks[identity].get("kind", "")) == "cistern":
		_cutaway_toggle.set_pressed_no_signal(false)
		set_cutaway(false)
	camera.position = node.to_global(anchor)
	var dimensions: Dictionary = _landmarks[identity].get("dimensions", {})
	var depth := float(dimensions.get("depth_m", 30.0))
	camera.look_at(node.to_global(Vector3(0, anchor.y + 3.0, depth * 0.18)), Vector3.UP)
	_fly_pitch = camera.rotation.x
	_fly_yaw = camera.rotation.y
	_fly_speed = 8.0
	_inside_architecture = true
	_interior_center = node.global_position
	_interior_radius = maxf(float(dimensions.get("width_m", 30.0)), depth) * 0.8 + 8.0
	_interior_floor = camera.position.y - 1.7
	_set_status("interior_note")


func set_camera_view(target: Vector3, distance_m: float, yaw_degrees: float, pitch_degrees: float) -> void:
	_orbit_target = target
	_orbit_distance = clampf(distance_m, 8.0, 17000.0)
	_orbit_yaw = deg_to_rad(yaw_degrees)
	_orbit_pitch = deg_to_rad(clampf(pitch_degrees, 1.0, 89.0))
	_set_navigation(Navigation.ORBIT)
	_apply_orbit()
	_set_status("camera_view")


func set_cutaway(enabled: bool) -> void:
	if world != null and world.has_method("set_cutaway"):
		world.call("set_cutaway", enabled)
		var nodes: Dictionary = world.get("landmark_nodes")
		for identity in nodes:
			var node: Node3D = nodes[identity]
			if node.has_meta("enclosure_node"):
				var enclosure := node.get_node_or_null(node.get_meta("enclosure_node"))
				if enclosure is Node3D:
					enclosure.visible = not enabled
	if enabled:
		_set_status("cutaway_note")


func home_view() -> void:
	if _ordered_ids.is_empty():
		return
	focus_landmark(str(data.get("initial_focus", _ordered_ids[0])))


func next_place() -> void:
	if _ordered_ids.is_empty():
		return
	var index := _ordered_ids.find(_selected_landmark)
	focus_landmark(_ordered_ids[(index + 1) % _ordered_ids.size()])


func overview() -> void:
	_orbit_target = Layout.world(data, [_bounds.get_center().x, _bounds.get_center().y])
	_orbit_distance = maxf(_bounds.size.x, _bounds.size.y) * 1.02
	_orbit_pitch = deg_to_rad(49.0)
	_orbit_yaw = deg_to_rad(20.0)
	_set_navigation(Navigation.ORBIT)
	_apply_orbit()


func plan_view() -> void:
	overview()
	_orbit_pitch = deg_to_rad(89.0)
	_orbit_yaw = 0.0
	_apply_orbit()


func set_stage(identity: String) -> void:
	for index in range(data.get("stages", []).size()):
		var stage: Dictionary = data["stages"][index]
		if str(stage["id"]) == identity:
			current_stage = identity
			if world != null:
				world.call("set_stage", identity)
				stats = world.get("stats")
			if _stage_picker != null:
				_stage_picker.select(index)
			_set_status_text(_t("stage_template") % [stage.get("name", identity), stage.get("description", "")])
			_refresh_stats()
			return


func _on_stage_selected(index: int) -> void:
	set_stage(str(data["stages"][index]["id"]))


func set_daytime(value: float) -> void:
	_daytime = clampf(value, 7.0, 18.0)
	var fraction := (_daytime - 6.0) / 13.0
	var elevation := maxf(8.0, sin(fraction * PI) * 67.0)
	_sun.rotation_degrees = Vector3(-elevation, -95.0 + fraction * 175.0, 0.0)
	_sun.light_color = Color("ffe2b4").lerp(Color("fff3db"), sin(fraction * PI))
	_sun.light_energy = 0.92 + sin(fraction * PI) * 0.32
	_environment.ambient_light_energy = 0.36 + sin(fraction * PI) * 0.07
	if _time_label != null:
		_time_label.text = _t("time_template") % [int(_daytime), int(round((_daytime - floor(_daytime)) * 60.0))]
	if _time_slider != null:
		_time_slider.set_value_no_signal(_daytime)


func _set_quality(enabled: bool) -> void:
	_environment.ssao_enabled = enabled
	_environment.glow_enabled = enabled
	_sun.shadow_enabled = true
	get_viewport().msaa_3d = Viewport.MSAA_2X if enabled else Viewport.MSAA_DISABLED
	if world != null and world.has_method("set_quality"):
		world.call("set_quality", enabled)


func _set_navigation(mode: int) -> void:
	_release_mouse()
	_inside_architecture = false
	_fly_speed = 18.0 if _orbit_distance < 350.0 else 65.0
	_navigation = mode
	if _nav_picker != null:
		_nav_picker.select(mode)
	if camera != null:
		_fly_yaw = camera.rotation.y
		_fly_pitch = camera.rotation.x
		if mode == Navigation.WALK:
			camera.position.y = Layout.height_at(data, camera.position.x, -camera.position.z) + 1.75
	if _help != null:
		_help.text = _t(["help_orbit", "help_fly", "help_walk"][mode])
	if mode == Navigation.WALK:
		_set_status("walk_note")


func _apply_orbit() -> void:
	var offset := Vector3(sin(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), cos(_orbit_yaw) * cos(_orbit_pitch)) * _orbit_distance
	camera.position = _orbit_target + offset
	var terrain_height: float = Layout.height_at(data, camera.position.x, -camera.position.z)
	camera.position.y = maxf(camera.position.y, terrain_height + 2.0)
	camera.look_at(_orbit_target, Vector3.UP)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			_hud.visible = not _hud.visible
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_release_mouse()
			_set_placing(false)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F12:
			capture_screenshot()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB and ready_for_capture:
			if _navigation == Navigation.ORBIT:
				_set_navigation(Navigation.FLY)
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null:
				focused.release_focus()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_fly_yaw -= event.relative.x * 0.003
		_fly_pitch = clampf(_fly_pitch - event.relative.y * 0.003, -1.48, 1.48)
		camera.rotation = Vector3(_fly_pitch, _fly_yaw, 0.0)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbit_drag = false
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_drag = false


func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_capture:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_DELETE and _editing:
			delete_selected()
		elif event.keycode == KEY_Z and event.ctrl_pressed and _editing:
			undo_edit()
		elif event.keycode == KEY_R and _editing:
			rotate_selected()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbit_drag = event.pressed and _navigation == Navigation.ORBIT
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_drag = event.pressed and _navigation == Navigation.ORBIT
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _navigation == Navigation.ORBIT:
			_orbit_distance = clampf(_orbit_distance * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.13), 8.0, 17000.0)
			_apply_orbit()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if _editing and _placing:
				_place_at_screen(event.position)
			elif _editing:
				_pick_design(event.position)
			else:
				_pick_landmark(event.position)
	if event is InputEventMouseMotion and _navigation == Navigation.ORBIT:
		if _orbit_drag:
			_orbit_yaw -= event.relative.x * 0.005
			_orbit_pitch = clampf(_orbit_pitch + event.relative.y * 0.005, 0.025, 1.553)
			_apply_orbit()
		elif _pan_drag:
			var right := camera.global_basis.x
			var forward := Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized()
			_orbit_target += (-right * event.relative.x + forward * event.relative.y) * _orbit_distance * 0.0012
			_orbit_target.x = clampf(_orbit_target.x, _bounds.position.x - 1000.0, _bounds.end.x + 1000.0)
			_orbit_target.z = clampf(_orbit_target.z, -_bounds.end.y - 1000.0, -_bounds.position.y + 1000.0)
			_apply_orbit()


func _physics_process(delta: float) -> void:
	if not ready_for_capture or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or _navigation == Navigation.ORBIT:
		return
	var movement := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		movement.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		movement.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		movement.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		movement.x += 1.0
	if _navigation == Navigation.FLY:
		if Input.is_physical_key_pressed(KEY_E):
			movement.y += 1.0
		if Input.is_physical_key_pressed(KEY_Q):
			movement.y -= 1.0
	var speed := _fly_speed if _navigation == Navigation.FLY else 5.0
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 5.0 if _navigation == Navigation.FLY else 2.4
	var direction := camera.global_basis * movement.normalized()
	if _navigation == Navigation.WALK:
		direction.y = 0
		direction = direction.normalized()
	var proposed := camera.position + direction * speed * delta
	proposed.x = clampf(proposed.x, _bounds.position.x - 400.0, _bounds.end.x + 400.0)
	proposed.z = clampf(proposed.z, -_bounds.end.y - 400.0, -_bounds.position.y + 400.0)
	var ground: float = Layout.height_at(data, proposed.x, -proposed.z)
	if _navigation == Navigation.WALK:
		proposed.y = ground + 1.75
		if world.has_method("ground_can_walk") and not world.call("ground_can_walk", proposed):
			return
	else:
		if _inside_architecture:
			if Vector2(proposed.x, proposed.z).distance_to(Vector2(_interior_center.x, _interior_center.z)) > _interior_radius:
				_inside_architecture = false
				_fly_speed = 18.0
			else:
				proposed.y = maxf(proposed.y, _interior_floor + 0.4)
				if direction.length_squared() > 0.001:
					var query := PhysicsRayQueryParameters3D.create(camera.position, proposed + direction * 0.4)
					var collision := get_world_3d().direct_space_state.intersect_ray(query)
					if not collision.is_empty():
						return
		if not _inside_architecture:
			proposed.y = clampf(proposed.y, ground + 2.0, 13000.0)
	camera.position = proposed


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_orbit_drag = false
	_pan_drag = false


func _pick_landmark(screen: Vector2) -> void:
	var best := ""
	var nearest := 75.0
	for identity in _ordered_ids:
		var position: Vector3 = Layout.world(data, _landmarks[identity]["position_m"])
		position.y += float(_landmarks[identity].get("dimensions", {}).get("height_m", 10.0)) * 0.5
		if camera.is_position_behind(position):
			continue
		var distance := camera.unproject_position(position).distance_to(screen)
		if distance < nearest:
			nearest = distance
			best = identity
	if not best.is_empty():
		focus_landmark(best)


func _terrain_pick(screen: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var previous := 0.0
	var step := 5.0
	var distance := 0.0
	for iteration in range(900):
		distance += step
		var point := origin + direction * distance
		var height: float = Layout.height_at(data, point.x, -point.z)
		if point.y <= height:
			var low := previous
			var high := distance
			for refinement in range(15):
				var middle := (low + high) * 0.5
				var sample := origin + direction * middle
				if sample.y > Layout.height_at(data, sample.x, -sample.z):
					low = middle
				else:
					high = middle
			var hit := origin + direction * high
			var map_point := Vector2(hit.x, -hit.z)
			if _inside_city(map_point):
				return map_point
			return null
		previous = distance
		step = minf(step * 1.006, 50.0)
	return null


func _inside_city(point: Vector2) -> bool:
	var boundary: Array = data.get("site", {}).get("boundary_m", [])
	if boundary.size() < 3:
		return _bounds.has_point(point)
	var polygon := PackedVector2Array()
	for pair in boundary:
		polygon.append(Vector2(float(pair[0]), float(pair[1])))
	return Geometry2D.is_point_in_polygon(point, polygon)


func _toggle_editor() -> void:
	_editing = not _editing
	_editor_panel.visible = _editing
	_inspector_panel.visible = not _editing
	_release_mouse()
	if not _editing:
		_set_placing(false)


func _toggle_inspector() -> void:
	_inspector_collapsed = not _inspector_collapsed
	_inspector_content.visible = not _inspector_collapsed
	_inspector_collapse.text = _t("inspector_expand" if _inspector_collapsed else "inspector_collapse")
	_inspector_panel.offset_bottom = 154 if _inspector_collapsed else 480


func _toggle_placement() -> void:
	_set_placing(_place_toggle.button_pressed)


func _set_placing(enabled: bool) -> void:
	_placing = enabled
	if _place_toggle != null:
		_place_toggle.set_pressed_no_signal(enabled)
	if enabled:
		_release_mouse()
		_set_status("placement_active")


func _begin_selection() -> void:
	_set_placing(false)
	_set_status("pick_addition")


func _place_at_screen(screen: Vector2) -> void:
	var position = _terrain_pick(screen)
	if position == null:
		_set_status("placement_outside")
		return
	add_design_object(KIT[_kit_picker.selected], position, _rotation_slider.value, _scale_slider.value)


func add_design_object(kind: String, position: Vector2, rotation_deg: float = 0.0, scale_factor: float = 1.0) -> bool:
	if not KIT.has(kind) or not _inside_city(position) or not is_finite(rotation_deg) or not is_finite(scale_factor):
		return false
	if design_objects.size() >= MAX_ADDITIONS:
		_set_status("placement_limit")
		return false
	_remember_edit()
	var existing_ids := {}
	for item in design_objects:
		existing_ids[item["id"]] = true
	while existing_ids.has("design_%06d" % _next_design_id):
		_next_design_id += 1
	var identity := "design_%06d" % _next_design_id
	_next_design_id += 1
	design_objects.append({"id": identity, "kind": kind, "position_m": [position.x, position.y], "rotation_deg": fposmod(rotation_deg, 360.0), "scale": clampf(scale_factor, 0.35, 3.0)})
	_selected_design = identity
	_rebuild_design()
	_set_status("placed")
	return true


func _pick_design(screen: Vector2) -> void:
	var nearest := 65.0
	var identity := ""
	for item in design_objects:
		var position: Vector3 = Layout.world(data, item["position_m"])
		position.y += 5.0 * float(item["scale"])
		if camera.is_position_behind(position):
			continue
		var distance := camera.unproject_position(position).distance_to(screen)
		if distance < nearest:
			nearest = distance
			identity = str(item["id"])
	_selected_design = identity
	_refresh_design_labels()


func _selected_index() -> int:
	for index in range(design_objects.size()):
		if str(design_objects[index]["id"]) == _selected_design:
			return index
	return -1


func _remember_edit() -> void:
	if _updating_editor:
		return
	_undo.append(design_objects.duplicate(true))
	if _undo.size() > 50:
		_undo.pop_front()


func _begin_slider_edit() -> void:
	_remember_edit()
	_slider_editing = true


func _end_slider_edit(_changed: bool) -> void:
	_slider_editing = false


func rotate_selected() -> void:
	var index := _selected_index()
	if index < 0:
		_rotation_slider.value = fposmod(_rotation_slider.value + 15.0, 360.0)
		return
	_remember_edit()
	design_objects[index]["rotation_deg"] = fposmod(float(design_objects[index]["rotation_deg"]) + 15.0, 360.0)
	_rebuild_design()


func _on_rotation_changed(value: float) -> void:
	if _updating_editor:
		return
	var index := _selected_index()
	if index >= 0:
		if not _slider_editing:
			_remember_edit()
		design_objects[index]["rotation_deg"] = fposmod(value, 360.0)
		_rebuild_design()


func _on_scale_changed(value: float) -> void:
	if _updating_editor:
		return
	var index := _selected_index()
	if index >= 0:
		if not _slider_editing:
			_remember_edit()
		design_objects[index]["scale"] = clampf(value, 0.35, 3.0)
		_rebuild_design()


func delete_selected() -> void:
	var index := _selected_index()
	if index < 0:
		return
	_remember_edit()
	design_objects.remove_at(index)
	_selected_design = ""
	_rebuild_design()
	_set_status("deleted")


func clear_design() -> void:
	if design_objects.is_empty():
		return
	_remember_edit()
	design_objects.clear()
	_selected_design = ""
	_rebuild_design()
	_set_status("cleared")


func undo_edit() -> void:
	if _undo.is_empty():
		return
	design_objects = _undo.pop_back()
	_selected_design = ""
	_rebuild_design()
	_set_status("undone")


func _rebuild_design() -> void:
	if world != null:
		world.call("set_design_objects", design_objects.duplicate(true))
	_refresh_design_labels()


func _refresh_design_labels() -> void:
	if _design_label == null:
		return
	_design_count.text = _t("count_template") % design_objects.size()
	var index := _selected_index()
	if index < 0:
		_design_label.text = _t("nothing_selected")
		return
	var item: Dictionary = design_objects[index]
	_design_label.text = _t("selected_template") % [item["id"], _t("kit_" + str(item["kind"]))]
	_updating_editor = true
	_rotation_slider.set_value_no_signal(float(item["rotation_deg"]))
	_scale_slider.set_value_no_signal(float(item["scale"]))
	_updating_editor = false


func save_variant() -> bool:
	var payload := {"schema_version": 1, "city_id": str(data.get("id", "constantinople_1200")), "historical_status": "creative", "objects": design_objects.duplicate(true)}
	var temp := _variant_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		_set_status("save_error")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(_variant_path)) != OK:
		_set_status("save_error")
		return false
	_set_status("saved")
	return true


func load_variant() -> bool:
	if not FileAccess.file_exists(_variant_path):
		_set_status("load_missing")
		return false
	var file := FileAccess.open(_variant_path, FileAccess.READ)
	if file == null or file.get_length() > 2000000:
		_set_status("load_error")
		return false
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		_set_status("load_error")
		return false
	var checked := validate_variant(parser.data)
	if not checked["valid"]:
		_set_status("load_error")
		return false
	_remember_edit()
	design_objects = checked["objects"]
	_selected_design = ""
	_next_design_id = 1
	var identities := {}
	for item in design_objects:
		identities[item["id"]] = true
	while identities.has("design_%06d" % _next_design_id):
		_next_design_id += 1
	_rebuild_design()
	_set_status("load_clamped" if checked["clamped"] else "loaded")
	return true


func validate_variant(payload: Variant) -> Dictionary:
	var invalid := {"valid": false, "objects": [], "clamped": false}
	if not payload is Dictionary or not _keys_exact(payload, ["schema_version", "city_id", "historical_status", "objects"]):
		return invalid
	if (not payload["schema_version"] is int and not payload["schema_version"] is float) or not payload["city_id"] is String or not payload["historical_status"] is String:
		return invalid
	if float(payload["schema_version"]) != 1.0 or payload["city_id"] != str(data.get("id", "constantinople_1200")) or payload["historical_status"] != "creative":
		return invalid
	if not payload["objects"] is Array or payload["objects"].size() > MAX_ADDITIONS:
		return invalid
	var objects: Array = []
	var ids := {}
	var clamped := false
	var id_pattern := RegEx.new()
	id_pattern.compile("^design_[0-9]{6,9}$")
	for item in payload["objects"]:
		if not item is Dictionary or not _keys_exact(item, ["id", "kind", "position_m", "rotation_deg", "scale"]):
			return invalid
		if not item["id"] is String or id_pattern.search(item["id"]) == null or ids.has(item["id"]) or not KIT.has(item["kind"]):
			return invalid
		if not item["position_m"] is Array or item["position_m"].size() != 2:
			return invalid
		for value in [item["position_m"][0], item["position_m"][1], item["rotation_deg"], item["scale"]]:
			if (not value is float and not value is int) or not is_finite(float(value)) or absf(float(value)) > 10000000.0:
				return invalid
		var position := Vector2(float(item["position_m"][0]), float(item["position_m"][1]))
		if not _inside_city(position):
			return invalid
		var scale_value := clampf(float(item["scale"]), 0.35, 3.0)
		var rotation := fposmod(float(item["rotation_deg"]), 360.0)
		clamped = clamped or scale_value != float(item["scale"]) or rotation != float(item["rotation_deg"])
		ids[item["id"]] = true
		objects.append({"id": item["id"], "kind": item["kind"], "position_m": [position.x, position.y], "rotation_deg": rotation, "scale": scale_value})
	return {"valid": true, "objects": objects, "clamped": clamped}


func _keys_exact(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


func capture_screenshot() -> String:
	await RenderingServer.frame_post_draw
	var folder := "user://captures"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		_set_status("screenshot_error")
		return ""
	var path := folder + "/constantinople_%d.png" % Time.get_ticks_msec()
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		_set_status("screenshot_error")
		return ""
	_set_status_text(_t("screenshot_saved") % ProjectSettings.globalize_path(path))
	return path


func _refresh_stats() -> void:
	if _stats_label != null:
		_stats_label.text = _t("stats_template") % [str(stats.get("building_count", 0)), str(stats.get("landmark_count", 0)), str(stats.get("tree_count", 0))]


func _set_status(key: String) -> void:
	_set_status_text(_t(key))


func _set_status_text(value: String) -> void:
	if _status != null:
		_status.text = value


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_mouse()
