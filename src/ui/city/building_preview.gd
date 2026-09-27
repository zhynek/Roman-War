class_name RomaBuildingPreview
extends SubViewportContainer
## Interactive model comparison. The same architecture and future meshes appear
## in the city; neither rotating nor selecting a stage issues a gameplay order.
var stage := "current"
var site_id := ""
var preview_world: RomaCityWorld
var preview_camera: Camera3D
var preview_viewport: SubViewport
var _status: Dictionary = {}
var _layout: Dictionary = {}
var _yaw := 0.48
var _pitch := 0.32
var _zoom := 1.0
var _dragging := false

func _init() -> void:
	custom_minimum_size = Vector2(360,230)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(400,230)
	preview_viewport.own_world_3d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	preview_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(preview_viewport)

func show_building(authored_layout: Dictionary, requested_site: String, status: Dictionary, requested_stage: String = "current") -> void:
	_status = status.duplicate(true)
	if is_instance_valid(preview_world) and site_id == requested_site and _layout == authored_layout:
		set_stage(requested_stage)
		return
	_layout = authored_layout.duplicate(true)
	site_id = requested_site
	if is_instance_valid(preview_world):
		preview_viewport.remove_child(preview_world)
		preview_world.queue_free()
	preview_world = RomaCityWorld.new()
	preview_viewport.add_child(preview_world)
	preview_world.build_preview(_layout,site_id)
	preview_camera = Camera3D.new()
	preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview_camera.current = true
	preview_camera.far = 250.0
	preview_world.add_child(preview_camera)
	_yaw = 0.48
	_pitch = 0.32
	_zoom = 1.0
	set_stage(requested_stage)
	_update_camera()

func set_stage(requested_stage: String) -> void:
	stage = requested_stage if requested_stage in ["current","construction","improved"] else "current"
	if is_instance_valid(preview_world):
		preview_world.preview_stage(_status,stage)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom = clampf(_zoom*(0.91 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.09),0.62,1.65)
			_update_camera()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x*0.012
		_pitch = clampf(_pitch+event.relative.y*0.008,0.12,1.05)
		_update_camera()
		accept_event()

func _update_camera() -> void:
	if not is_instance_valid(preview_camera):
		return
	var target := preview_world.preview_center
	var radius := preview_world.preview_radius
	var at := target+Vector3(sin(_yaw)*cos(_pitch),sin(_pitch),cos(_yaw)*cos(_pitch))*radius*3.2
	preview_camera.transform = Transform3D(Basis.looking_at(target-at,Vector3.UP),at)
	preview_camera.size = radius*1.45*_zoom
