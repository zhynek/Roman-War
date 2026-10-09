class_name PortView
extends SubViewportContainer
## Inspectable original 3D waterfront. Orbit/zoom never touch campaign state.
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var mesh: MeshInstance3D
var plan: Dictionary = {}
var yaw := 0.22
var pitch := 0.84
var zoom := 110.0
var dragging := false
var pan := Vector3.ZERO

func _ready() -> void:
	stretch = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 500
	world.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-35,0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var ambient := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("14292e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b1c2c3")
	environment.ambient_light_energy = 0.65
	ambient.environment = environment
	world.add_child(ambient)
	mesh = MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.90
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	world.add_child(mesh)
	_pose()

func display(layout: Dictionary, navigation: bool = false) -> void:
	plan = layout
	mesh.mesh = PortModel.build(layout, navigation)
	_pose()

func _pose() -> void:
	camera.size = zoom
	camera.position = pan + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*180
	camera.look_at(pan,Vector3.UP)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom*(0.90 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.10),35,150)
			_pose()
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		if event.shift_pressed:
			pan += Vector3(-event.relative.x,0,-event.relative.y)*zoom/maxf(1,size.y)
			pan.x = clampf(pan.x,-45,45)
			pan.z = clampf(pan.z,-35,35)
		else:
			yaw -= event.relative.x*0.006
			pitch = clampf(pitch+event.relative.y*0.004,0.35,1.4)
		_pose()
		accept_event()
