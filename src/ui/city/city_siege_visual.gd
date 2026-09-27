class_name RomaCitySiegeVisual
extends Node3D
## Entirely cosmetic. Equipment condition is read from a detached snapshot.
var ram: Node3D
var body: MeshInstance3D
var beam: MeshInstance3D
var wheels: Array[Node3D] = []
var flames: Array[MeshInstance3D] = []
var smoke: Array[MeshInstance3D] = []
var light: OmniLight3D
var _clock := 0.0
var _paused := true
var _moving := false
var _striking := false
var _burning := false
var _destroyed := false
var _target := Vector3.ZERO
var _initialized := false
var _wood: ShaderMaterial
var _charred: StandardMaterial3D

func _ready() -> void:
	_wood=ShaderMaterial.new()
	_wood.shader=preload("res://src/ui/city/city_surface.gdshader")
	_charred=StandardMaterial3D.new()
	_charred.albedo_color=Color("#2b2722")
	_charred.roughness=1.0
	ram=Node3D.new()
	ram.name="SiegeRam"
	add_child(ram)
	var b:=RealismModels.new()
	var wood:=Color("#72543b");wood.a=0.25
	var iron:=Color("#494b49")
	for side in [-1.0,1.0]:
		b.box(Vector3(side*1.25,0.95,0),Vector3(0.28,0.4,4.8),wood)
		for z in [-1.6,1.6]:
			b.rod(Vector3(side*1.25,0.95,z),Vector3(side*0.75,3.15,z),0.16,wood)
			b.rod(Vector3(side*1.25,1.15,z),Vector3(-side*0.75,3.05,z),0.09,wood.darkened(0.12))
			var wheel:=Node3D.new()
			wheel.position=Vector3(side*1.65,0.7,z)
			ram.add_child(wheel)
			wheels.append(wheel)
			var rim:=RealismModels.new()
			for i in range(16):
				var a:=i*TAU/16;var c:=(i+1)*TAU/16
				rim.rod(Vector3(0,sin(a)*0.62,cos(a)*0.62),Vector3(0,sin(c)*0.62,cos(c)*0.62),0.11,wood)
				if i%2==0:rim.rod(Vector3.ZERO,Vector3(0,sin(a)*0.56,cos(a)*0.56),0.05,wood)
			rim.rod(Vector3(-0.16,0,0),Vector3(0.16,0,0),0.17,iron)
			_mesh(wheel,rim)
		for plank in range(11):
			var z:float=-2.35+plank*0.47
			b.box(Vector3(side*0.73,3.0,z),Vector3(1.75,0.12,0.45),wood.lightened((plank%3)*0.04),Vector3(0,0,-side*0.30))
	for z in [-1.6,1.6]:
		b.rod(Vector3(-1.8,0.7,z),Vector3(1.8,0.7,z),0.13,wood)
		b.rod(Vector3(-1.1,2.9,z),Vector3(1.1,2.9,z),0.12,wood)
		for side in [-1.0,1.0]:b.rod(Vector3(side*0.35,2.9,z),Vector3(side*0.2,1.7,z),0.025,Color("#8e7959"))
	body=_mesh(ram,b)
	var log:=RealismModels.new()
	log.rod(Vector3(0,1.7,2.3),Vector3(0,1.7,-3.25),0.28,wood,0.34)
	log.rod(Vector3(0,1.7,-2.8),Vector3(0,1.7,-3.45),0.37,iron)
	for z in [-2.5,0,1.8]:log.rod(Vector3(0,1.7,z),Vector3(0,1.7,z+0.12),0.3,iron)
	beam=_mesh(ram,log)
	for i in range(7):
		flames.append(_plume(Vector3((i%3-1)*0.65,2.9,(i/3-1)*1.3),Vector2(1.9,3.8),false))
	for i in range(4):
		smoke.append(_plume(Vector3(i*0.7,5.1+i*1.5,0),Vector2(3.5+i,4.8+i),true))
	light=OmniLight3D.new()
	light.light_color=Color("#ff8938")
	light.omni_range=12
	light.light_energy=2.8
	light.position=Vector3(0,3,0)
	ram.add_child(light)
	ram.hide()

func _mesh(parent: Node3D,b: RealismModels) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=b.finish();node.material_override=_wood
	parent.add_child(node)
	return node

func _plume(at: Vector3,dimensions: Vector2,is_smoke: bool) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	var quad:=QuadMesh.new();quad.size=dimensions
	node.mesh=quad;node.position=at
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=ShaderMaterial.new();mat.shader=preload("res://src/ui/city/siege_fire.gdshader")
	mat.set_shader_parameter("smoke",is_smoke)
	node.material_override=mat
	ram.add_child(node)
	return node

func sync(snapshot: Dictionary) -> void:
	var engine: Dictionary=snapshot.get("siege_engine",{})
	ram.visible=not engine.is_empty() and snapshot.get("active",false)
	if engine.is_empty():
		_initialized=false
		return
	_target=Vector3(float(engine["position"][0])/100,0,float(engine["position"][1])/100)
	if not _initialized or int(snapshot.get("tick",0))==0:
		ram.position=_target
		_clock=0
		_initialized=true
	_paused=snapshot.get("paused",true) or snapshot.get("phase","")!="fighting"
	_moving=engine["moving"]
	_striking=not _moving and engine["crewed"] and int(snapshot.get("gate_integrity",0))>0
	_burning=engine["burning"]
	_destroyed=int(engine["hp"])<=0
	body.material_override=_charred if _destroyed or _burning else _wood
	beam.material_override=_charred if _destroyed else _wood
	for node in flames:node.visible=_burning and not _destroyed
	for node in smoke:node.visible=_burning
	light.visible=_burning and not _destroyed
	body.rotation.z=0.12 if _destroyed else 0.0
	body.position.y=-0.55 if _destroyed else 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not ram.visible:return
	if not _paused:_clock+=delta
	ram.position=ram.position.lerp(_target,1.0-exp(-delta*15))
	if _moving and not _paused:
		for wheel in wheels:wheel.rotation.x-=delta*1.4
	beam.position.z=sin(_clock*3.14)*0.42 if _striking and not _destroyed else 0.0
	beam.position.y=-0.8 if _destroyed else 0.0
	for i in range(flames.size()):
		(flames[i].material_override as ShaderMaterial).set_shader_parameter("clock_time",_clock+i*0.67)
	for i in range(smoke.size()):
		(smoke[i].material_override as ShaderMaterial).set_shader_parameter("clock_time",_clock+i*1.14)
	light.light_energy=2.5+sin(_clock*13)*0.35
