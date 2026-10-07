extends SubViewportContainer
## Isolated, rotatable copy of actual original geometry. No commands or state writes.
var camera: Camera3D
var viewport: SubViewport
var radius: float=5
var yaw: float=.55
var dragging: bool=false
func _init() -> void:
	custom_minimum_size=Vector2(280,170);stretch=true;mouse_filter=Control.MOUSE_FILTER_STOP
	viewport=SubViewport.new();viewport.size=Vector2i(420,255);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;viewport.msaa_3d=Viewport.MSAA_2X;add_child(viewport)
func show_mesh(mesh: Mesh) -> void:
	var shape:=MeshInstance3D.new();shape.mesh=mesh
	var bounds: AABB=mesh.get_aabb();shape.position=-bounds.get_center();radius=maxf(bounds.size.length()*.52,2)
	viewport.add_child(shape)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("263f40");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("fff1d1");env.environment.ambient_light_energy=.7;viewport.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1.7;viewport.add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;viewport.add_child(camera);update_camera()
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:dragging=event.pressed;accept_event()
	elif event is InputEventMouseMotion and dragging:yaw-=event.relative.x*.012;update_camera();accept_event()
func update_camera() -> void:
	camera.position=Vector3(sin(yaw),.62,cos(yaw))*radius*3;camera.look_at(Vector3.ZERO);camera.size=radius*2.1;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
