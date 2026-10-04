extends Node3D
## Original procedural settlement. One authored record owns rendering and picking.
const Geometry = preload("res://src/geometry.gd")
var data: Dictionary
var materials: Dictionary = {}
var buildings: Array = []
var solids: Array = []
var floors: Array = []
var object_nodes: Dictionary = {}
var stats: Dictionary = {}
var _geo
var _origin := Vector3.ZERO
var _yaw: float = 0.0
var _owner: String = ""

func build(config: Dictionary) -> void:
	data = config
	_materials()
	for record in data.objects:
		if record.kind == "building": buildings.append(record)
	_terrain()
	for record in data.objects:
		if record.kind == "building": _building(record)
		elif record.kind == "path": _path(record)
		elif record.kind == "boundary": _boundary(record)
		elif record.kind == "field": _field(record)
		elif record.kind == "work_area": _work_area(record)
		elif record.kind == "landing": _landing(record)
	_countryside()
	stats = {"authored_objects":data.objects.size(),"buildings":buildings.size(),"collision_pieces":solids.size(),"mesh_instances":object_nodes.size()}

func _materials() -> void:
	var colors := {"earth":Color("8c7658"),"soil":Color("615743"),"grass":Color("717957"),"sand":Color("b1a486"),"silt":Color("5b6653"),"path":Color("897655"),"daub":Color("b6a38c"),"daub_light":Color("c3b39b"),"daub_dark":Color("a29680"),"thatch":Color("847454"),"thatch_light":Color("a18c60"),"thatch_dark":Color("6b644d"),"wood":Color("64513b"),"wood_light":Color("9c8159"),"wood_dark":Color("3b3328"),"stone":Color("89877a"),"pottery":Color("776052"),"pottery_red":Color("9b7257"),"inside":Color("423a32"),"mat":Color("aa9062"),"leaf":Color("4d6146"),"leaf_light":Color("66744d"),"reed":Color("8a9460"),"grain":Color("c1ab74"),"charcoal":Color("383830"),"clay":Color("9f806b")}
	for id in colors:
		var m := ShaderMaterial.new()
		m.shader = load("res://src/earth.gdshader")
		m.set_shader_parameter("pigment",colors[id])
		m.set_shader_parameter("scale", 12.0 if id.begins_with("daub") else 5.0)
		m.set_shader_parameter("grain", .36 if id in ["earth","grass","path","soil"] else .16)
		m.set_shader_parameter("fabric",1 if id.begins_with("thatch") else (2 if id in ["wood","mat"] else 0))
		materials[id] = m
	var water := ShaderMaterial.new()
	water.shader = load("res://src/water.gdshader")
	materials.water = water
	var ground:=ShaderMaterial.new()
	ground.shader=load("res://src/ground.gdshader")
	materials.ground=ground

func hash01(text: String, salt: int = 0) -> float:
	var n:int=(text+":"+str(salt)).hash()
	n=((n^(n>>16))*0x45d9f3b)&0xffffffff
	n=((n^(n>>16))*0x45d9f3b)&0xffffffff
	n=n^(n>>16)
	return float(n)/4294967295.0

func stream_x(z: float) -> float:
	return float(data.terrain.stream_x) + sin(z*.024)*9.0 + sin(z*.07)*2.0

func natural_height(x: float, z: float) -> float:
	var shore: float = float(data.terrain.shore_z) + sin(x*.021)*8.0
	var land: float = (shore-z)*.031 + sin(x*.025)*.5 + sin(z*.022)*.28
	var channel: float = absf(x-stream_x(z))
	var bank: float = smoothstep(float(data.terrain.stream_width),17.0,channel)
	return lerpf(-.6+maxf(0,(-z-40)*.03),land,bank)

func height_raw(x: float,z: float) -> float:
	var h: float = natural_height(x,z)
	for b in buildings:
		var p: Vector2 = Vector2(x-float(b.at[0]),z-float(b.at[1])).rotated(deg_to_rad(float(b.yaw)))
		var excess: float = maxf(absf(p.x)-float(b.size[0])*.5,absf(p.y)-float(b.size[1])*.5)
		var blend: float = 1.0-smoothstep(.5,3.1,excess)
		if blend>0.0: h=lerpf(h,natural_height(b.at[0],b.at[1]),blend)
	return h

func surface_height(x: float,z: float) -> float:
	# Exactly the same diagonal and samples as the rendered terrain triangles.
	var step: float = data.terrain.grid
	var ax: float = floorf(x/step)*step
	var az: float = floorf(z/step)*step
	var u: float = (x-ax)/step
	var v: float = (z-az)/step
	var a: float = height_raw(ax,az)
	var b: float = height_raw(ax+step,az)
	var c: float = height_raw(ax+step,az+step)
	var d: float = height_raw(ax,az+step)
	return a+(b-a)*u+(c-b)*v if u>=v else a+(c-d)*u+(d-a)*v

func _terrain() -> void:
	_begin("landscape")
	var extent: int = data.terrain.extent
	var step: int = data.terrain.grid
	for z in range(-extent,extent,step):
		for x in range(-extent,extent,step):
			var a := Vector3(x,height_raw(x,z),z)
			var b := Vector3(x+step,height_raw(x+step,z),z)
			var c := Vector3(x+step,height_raw(x+step,z+step),z+step)
			var d := Vector3(x,height_raw(x,z+step),z+step)
			var h: float = (a.y+b.y+c.y+d.y)*.25
			var key := "grass"
			if h<.25: key="silt"
			elif h<1.0: key="sand"
			elif absf(x)<35 and z>-31 and z<37: key="earth"
			_geo.quad(a,b,c,d,"ground")
	# Coarser surrounding land carries the landscape beyond the walking envelope.
	for z in range(-1440,1440,8):
		for x in range(-1440,1440,8):
			if x>=-extent and x<extent and z>=-extent and z<extent:continue
			var a:=Vector3(x,height_raw(x,z),z)
			var b:=Vector3(x+8,height_raw(x+8,z),z)
			var c:=Vector3(x+8,height_raw(x+8,z+8),z+8)
			var d:=Vector3(x,height_raw(x,z+8),z+8)
			_geo.quad(a,b,c,d,"ground")
	_finish()
	_begin("water")
	_geo.quad(Vector3(-1800,0,-1800),Vector3(1800,0,-1800),Vector3(1800,0,1800),Vector3(-1800,0,1800),"water")
	_finish()
	_begin("upstream_water")
	for z in range(-1440,-40,2):
		var x:float=stream_x(z)
		var nx:float=stream_x(z+2)
		var h:float=(-z-40)*.03
		var nh:float=(-z-42)*.03
		_geo.quad(Vector3(x-5,h,z),Vector3(x+5,h,z),Vector3(nx+5,nh,z+2),Vector3(nx-5,nh,z+2),"water")
	_finish()

func _begin(id: String,at: Vector3 = Vector3.ZERO,yaw: float = 0.0) -> void:
	_geo = Geometry.new(materials)
	_owner = id
	_origin = at
	_yaw = yaw

func _finish() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = _owner
	instance.mesh = _geo.finish()
	instance.position = _origin
	instance.rotation.y = _yaw
	add_child(instance)
	object_nodes[_owner] = instance
	return instance

func _solid_box(at: Vector3,size: Vector3,material: String,angle: float = 0.0) -> void:
	_geo.box(at,size,material,Vector3(0,angle,0))
	solids.append({"at":_origin + Basis(Vector3.UP,_yaw)*at,"size":size,"yaw":_yaw+angle,"owner":_owner})

func _solid_rod(a: Vector3,b: Vector3,r: float,material: String) -> void:
	_geo.rod(a,b,r,material)
	if absf(a.y-b.y)>1.0:
		solids.append({"at":_origin+Basis(Vector3.UP,_yaw)*((a+b)*.5),"size":Vector3(r*2,absf(a.y-b.y),r*2),"yaw":_yaw,"owner":_owner})

func building_position(b: Dictionary, local: Vector3 = Vector3.ZERO) -> Vector3:
	return Vector3(b.at[0],natural_height(b.at[0],b.at[1]),b.at[1])+Basis(Vector3.UP,deg_to_rad(float(b.yaw)))*local

func _building(b: Dictionary) -> void:
	var w: float=b.size[0]
	var d: float=b.size[1]
	var h: float=b.wall_height
	var r: float=b.roof_rise
	var hue: String=["daub","daub_light","daub_dark"][int(hash01(b.id)*3)%3]
	_begin(b.id,building_position(b),deg_to_rad(float(b.yaw)))
	var round_house: bool=b.roof=="round"
	if round_house:
		# Short wall segments around an oval; the southern doorway is a real gap.
		for i in range(24):
			var a: float=TAU*i/24.0
			var c: float=TAU*(i+1)/24.0
			if i in [5,6]:continue
			var pa:=Vector3(cos(a)*w*.5,0,sin(a)*d*.5)
			var pc:=Vector3(cos(c)*w*.5,0,sin(c)*d*.5)
			var delta: Vector3=pc-pa
			_solid_box((pa+pc)*.5+Vector3.UP*h*.5,Vector3(delta.length()+.04,h,.24),hue,-atan2(delta.z,delta.x))
			_geo.rod(pa,pa+Vector3.UP*(h+.06),.065,"wood")
		for i in range(48):
			var a: float=TAU*i/48.0
			var c: float=TAU*(i+1)/48.0
			var pa:=Vector3(cos(a)*(w*.5+.5),h,sin(a)*(d*.5+.5))
			var pc:=Vector3(cos(c)*(w*.5+.5),h,sin(c)*(d*.5+.5))
			_geo.triangle(pa,pc,Vector3(0,h+r,0),"thatch")
			_geo.triangle(Vector3(0,h+r-.15,0),pc-Vector3.UP*.14,pa-Vector3.UP*.14,"thatch_dark")
			_geo.rod(pa,Vector3(0,h+r,0),.035,"thatch_light",.025,5)
		_geo.cylinder(Vector3(0,.018,0),minf(w,d)*.49,.08,"earth")
	else:
		# Earthen walls around a 1.15m doorway and a small unglazed side opening.
		_solid_box(Vector3(0,h*.5,-d*.5),Vector3(w,h,.27),hue)
		_solid_box(Vector3(-w*.5,h*.5,0),Vector3(.27,h,d),hue)
		_solid_box(Vector3(w*.5,.7,0),Vector3(.27,1.4,d),hue)
		_solid_box(Vector3(w*.5,1.65,-d*.25-.15),Vector3(.27,.5,d*.5-.3),hue)
		_solid_box(Vector3(w*.5,1.65,d*.25+.15),Vector3(.27,.5,d*.5-.3),hue)
		_solid_box(Vector3(w*.5,(h+1.9)*.5,0),Vector3(.27,h-1.9,d),hue)
		var side: float=(w-1.15)*.5
		for sign_ in [-1.0,1.0]:
			_solid_box(Vector3(sign_*(w+1.15)*.25,h*.5,d*.5),Vector3(side,h,.27),hue)
		_solid_box(Vector3(0,(h+1.98)*.5,d*.5),Vector3(1.15,h-1.98,.27),hue)
		for x in [-w*.5,w*.5]:
			for z in [-d*.5,0.0,d*.5]:
				_geo.rod(Vector3(x,.02,z),Vector3(x,h+.08,z),.075,"wood",.055)
		for x in [-.64,.64]: _geo.rod(Vector3(x,0,d*.5),Vector3(x,2.04,d*.5),.065,"wood")
		_geo.rod(Vector3(-.76,2.02,d*.5),Vector3(.76,2.02,d*.5),.085,"wood")
		_geo.box(Vector3(0,.018,0),Vector3(w-.1,.08,d-.1),"earth")
		_roof(w,d,h,r,b.roof)
		# Low irregular footing stones, separate from the later masonry vocabulary.
		for i in range(int((w+d)*4)):
			var t: float=float(i)/int((w+d)*4)*2.0*(w+d)
			var at: Vector3
			if t<w:at=Vector3(t-w*.5,.055,-d*.5)
			elif t<w+d:at=Vector3(w*.5,.055,t-w-d*.5)
			elif t<2*w+d:at=Vector3(w*.5-(t-w-d),.055,d*.5)
			else:at=Vector3(-w*.5,.055,d*.5-(t-2*w-d))
			if at.z>d*.5-.1 and absf(at.x)<.72:continue
			_rock(at,Vector3(.20,.11+hash01(b.id,i)*.04,.18),"stone")
		# Small patch of exposed woven core on the back, not decorative half-timbering.
		for row in range(9):
			_geo.rod(Vector3(-.9,.2+row*.055,-d*.5-.146),Vector3(-.2,.2+row*.055,-d*.5-.146),.014,"wood_light",.014,5)
		for i in range(5):
			_geo.rod(Vector3(-.88+i*.16,.16,-d*.5-.152),Vector3(-.88+i*.16,.7,-d*.5-.152),.019,"wood",.019,5)
	# Earthen threshold, worn approach, interior furniture all remain original interpretations.
	_geo.box(Vector3(0,.035,d*.5),Vector3(1.12,.07,.6),"path")
	floors.append({"record":b,"height":_origin.y+.06})
	for item in b.furniture: _furnishing(item)
	# Split firewood and baskets beside the threshold make the outdoor room legible.
	for i in range(9):
		var at:=Vector3(-w*.32+(i%3)*.14,.15+floorf(i/3.0)*.12,d*.5+.46)
		_geo.rod(at,at+Vector3(0,0,.68),.07,"wood",.055,8)
	_pot(Vector3(w*.38,.04,d*.5+.6),.28,.48,"pottery")
	_finish()

func _roof(w: float,d: float,h: float,r: float,kind: String) -> void:
	var e: float=w*.5+.47
	var z: float=d*.5+.48
	var hip: float=.65 if kind=="hip" else 0.0
	var a:=Vector3(-e,h,-z)
	var b:=Vector3(e,h,-z)
	var c:=Vector3(e,h,z)
	var f:=Vector3(-e,h,z)
	var p:=Vector3(0,h+r,-z+hip)
	var q:=Vector3(0,h+r,z-hip)
	_geo._oriented_quad(a,f,q,p,Vector3(-1,1,0),"thatch")
	_geo._oriented_quad(b,p,q,c,Vector3(1,1,0),"thatch_light")
	_geo._oriented_quad(p,q,f-Vector3.UP*.16,a-Vector3.UP*.16,Vector3(1,-1,0),"thatch_dark")
	_geo._oriented_quad(c-Vector3.UP*.16,q,p,b-Vector3.UP*.16,Vector3(-1,-1,0),"thatch_dark")
	_geo.triangle(a,b,p,"thatch")
	_geo.triangle(c,f,q,"thatch")
	_geo.triangle(p,b-Vector3.UP*.15,a-Vector3.UP*.15,"thatch_dark")
	_geo.triangle(q,f-Vector3.UP*.15,c-Vector3.UP*.15,"thatch_dark")
	_geo.rod(p,q,.12,"thatch_dark")
	for i in range(int(d/.5)+2):
		var zz: float=lerpf(-d*.5,d*.5,float(i)/(int(d/.5)+1))
		for side in [-1.0,1.0]:
			_geo.rod(Vector3(side*w*.5,h-.12,zz),Vector3(0,h+r-.19,zz),.048,"wood")
		_geo.rod(Vector3(-w*.5,h-.14,zz),Vector3(w*.5,h-.14,zz),.055,"wood")
	# Ragged individual reed bundles and horizontal fixing bands.
	for i in range(int(z*2/.065)):
		var zz: float=-z+i*.065
		var noise_: float=hash01(_owner,i)
		for side in [-1.0,1.0]:
			var end:=Vector3(side*(e+.08*noise_),h-.04-noise_*.08,zz)
			var top:=Vector3(side*.12,h+r-.04,clampf(zz,-z+hip,z-hip))
			_geo.rod(end,top,.026,"thatch_light" if i%3==0 else "thatch",.018,5)
	for side in [-1.0,1.0]:
		for t in [.27,.62]:
			_geo.rod(Vector3(side*e*(1-t),h+r*t+.045,-z+hip*t),Vector3(side*e*(1-t),h+r*t+.045,z-hip*t),.032,"wood_dark",.032,6)

func _pot(at: Vector3,radius: float,h: float,material: String) -> void:
	# Hollow, wheel-free silhouette with irregular hand-built profile and visible rim.
	var profile: Array=[Vector2(.55,0),Vector2(.92,.17),Vector2(1,.48),Vector2(.82,.78),Vector2(.61,.95),Vector2(.64,1)]
	for j in range(profile.size()-1):
		for i in range(20):
			var a: float=TAU*i/20.0
			var b: float=TAU*(i+1)/20.0
			var n: float=1.0+.012*sin(i*TAU*3/20.0)
			var nb:float=1.0+.012*sin((i+1)*TAU*3/20.0)
			var p: Vector2=profile[j]
			var q: Vector2=profile[j+1]
			var v1:=at+Vector3(cos(a)*radius*p.x*n,h*p.y,sin(a)*radius*p.x*n)
			var v2:=at+Vector3(cos(b)*radius*p.x*nb,h*p.y,sin(b)*radius*p.x*nb)
			var v3:=at+Vector3(cos(b)*radius*q.x*nb,h*q.y,sin(b)*radius*q.x*nb)
			var v4:=at+Vector3(cos(a)*radius*q.x*n,h*q.y,sin(a)*radius*q.x*n)
			_geo.quad(v1,v2,v3,v4,material)
			_geo.quad(v4-(v4-at)*.08,v3-(v3-at)*.08,v2-(v2-at)*.08,v1-(v1-at)*.08,"inside")
	for i in range(20):
		var a:float=TAU*i/20.0
		var b:float=TAU*(i+1)/20.0
		_geo.rod(at+Vector3(cos(a)*radius*.63,h,sin(a)*radius*.63),at+Vector3(cos(b)*radius*.63,h,sin(b)*radius*.63),.025,material,.025,5)
	solids.append({"at":_origin+Basis(Vector3.UP,_yaw)*(at+Vector3.UP*h*.5),"size":Vector3(radius*1.7,h,radius*1.7),"yaw":_yaw,"owner":_owner})

func _furnishing(item: Dictionary) -> void:
	var at:=Vector3(item.at[0],.07,item.at[1])
	match item.kind:
		"mat":
			_geo.box(at+Vector3.UP*.015,Vector3(1.0,.03,1.65),"mat")
			for i in range(42):_geo.rod(at+Vector3(-.49,.036,-.8+i*.039),at+Vector3(.49,.036,-.8+i*.039),.006,"thatch_dark",.006,4)
			_geo.rod(at+Vector3(-.46,.1,-.65),at+Vector3(.46,.1,-.65),.085,"mat",.085,12)
		"pot": _pot(at,.3,.61,"pottery" if hash01(item.id)>.5 else "pottery_red")
		"bowl": _pot(at,.28,.17,"pottery")
		"basket":
			_geo.cylinder(at+Vector3.UP*.2,.31,.4,"mat",.36)
			for i in range(11):
				var y:float=.035+i*.035
				for j in range(16):
					var aa:float=TAU*j/16.0
					var ab:float=TAU*(j+1)/16.0
					_geo.rod(at+Vector3(cos(aa)*(.31+y*.12),y,sin(aa)*(.31+y*.12)),at+Vector3(cos(ab)*(.31+y*.12),y,sin(ab)*(.31+y*.12)),.012,"wood_light",.012,4)
			solids.append({"at":_origin+Basis(Vector3.UP,_yaw)*(at+Vector3.UP*.2),"size":Vector3(.62,.4,.62),"yaw":_yaw,"owner":_owner})
		"quern":
			_rock(at,Vector3(.3,.19,.44),"stone")
			solids.append({"at":_origin+Basis(Vector3.UP,_yaw)*(at+Vector3.UP*.095),"size":Vector3(.58,.19,.85),"yaw":_yaw,"owner":_owner})
			_geo.rod(at+Vector3(-.21,.24,-.04),at+Vector3(.21,.24,-.04),.085,"stone",.065,10)
			for i in range(18):_geo.box(at+Vector3(hash01(item.id,i)*.35-.18,.21,.15+hash01(item.id,i+31)*.16),Vector3(.012,.015,.027),"grain")
		"grain":
			_geo.box(at,Vector3(.9,.025,.9),"mat")
			_geo.dome(at,.3,.13,"grain")
		"clay":
			_geo.dome(at,.28,.22,"clay")
			for i in range(4):_pot(at+Vector3(-.5+i*.34,0,.6),.12,.18,"clay")
			_geo.box(at+Vector3(.05,.24,0),Vector3(.25,.014,.06),"stone")

func _path(record: Dictionary) -> void:
	_begin(record.id)
	var points:Array=record.points
	var centers:Array[Vector2]=[]
	for i in range(points.size()-1):
		var a:=Vector2(points[i][0],points[i][1])
		var b:=Vector2(points[i+1][0],points[i+1][1])
		var before:=Vector2(points[maxi(0,i-1)][0],points[maxi(0,i-1)][1])
		var after:=Vector2(points[mini(points.size()-1,i+2)][0],points[mini(points.size()-1,i+2)][1])
		var steps:int=maxi(4,int(a.distance_to(b)*4))
		for j in range(steps):centers.append(a.cubic_interpolate(b,before,after,float(j)/steps))
	centers.append(Vector2(points[-1][0],points[-1][1]))
	var edges:Array=[]
	for i in range(centers.size()):
		var p:Vector2=centers[i]
		var tangent:Vector2=centers[mini(centers.size()-1,i+1)]-centers[maxi(0,i-1)]
		var normal:=Vector2(-tangent.y,tangent.x).normalized()
		var w:float=record.width*.5*(.9+.09*sin(p.x*1.3+p.y*1.7)+.035*sin(p.y*9.0))
		var pair:Array=[]
		for side in [-1.0,1.0]:
			var v:Vector2=p+normal*w*side
			pair.append(Vector3(v.x,surface_height(v.x,v.y)+.025,v.y))
		edges.append(pair)
	for i in range(edges.size()-1):
		_geo._oriented_quad(edges[i][0],edges[i+1][0],edges[i+1][1],edges[i][1],Vector3.UP,"path")
	_finish()

func _boundary(record: Dictionary) -> void:
	_begin(record.id)
	for i in range(record.points.size()-1):
		var p:=Vector2(record.points[i][0],record.points[i][1])
		var q:=Vector2(record.points[i+1][0],record.points[i+1][1])
		var length:float=p.distance_to(q)
		var a:=Vector3(p.x,surface_height(p.x,p.y),p.y)
		var b:=Vector3(q.x,surface_height(q.x,q.y),q.y)
		var mid:Vector3=(a+b)*.5+Vector3.UP*.42
		# A sparse woven screen with a matching solid envelope, below eye level.
		solids.append({"at":mid,"size":Vector3(length,.84,.14),"yaw":-atan2(q.y-p.y,q.x-p.x),"owner":_owner})
		for j in range(int(length/.6)+1):
			var at:Vector3=a.lerp(b,float(j)/maxi(1,int(length/.6)))
			_geo.rod(at,at+Vector3.UP*(.89+hash01(record.id,j)*.1),.035,"wood")
		for row in range(12):
			for j in range(int(length/.3)):
				var aa:Vector3=a.lerp(b,float(j)/int(length/.3))+Vector3(0,.08+row*.06,sin(j*PI*.5)*.025)
				var bb:Vector3=a.lerp(b,float(j+1)/int(length/.3))+Vector3(0,.08+row*.06,sin((j+1)*PI*.5)*.025)
				_geo.rod(aa,bb,.018,"wood_light",.018,5)
	_finish()

func _field(record: Dictionary) -> void:
	_begin(record.id)
	var basis:=Basis(Vector3.UP,deg_to_rad(float(record.yaw)))
	var w:float=record.size[0]
	var d:float=record.size[1]
	for i in range(int(w*d*7)):
		var p:Vector3=Vector3(record.at[0],0,record.at[1])+basis*Vector3((hash01(record.id,i)-.5)*w,0,(hash01(record.id,i+7000)-.5)*d)
		p.y=surface_height(p.x,p.z)
		var h:float=.52+hash01(record.id,i+3100)*.4
		if record.id.ends_with("02") and i%3!=0:h=.12
		var top:Vector3=p+Vector3(.09,h,.03)
		_geo.rod(p,top,.012,"grain",.009,4)
		if h>.2:
			_geo.rod(top,top+Vector3(.025,.12,0),.035,"grain",.018,5)
			_geo.triangle(p+Vector3(0,.25,0),p+Vector3(.21,.45,.02),p+Vector3(.02,.55,0),"reed")
	_finish()

func _work_area(record: Dictionary) -> void:
	var at:=Vector3(record.at[0],surface_height(record.at[0],record.at[1]),record.at[1])
	_begin(record.id,at,deg_to_rad(float(record.yaw)))
	if record.use=="hearth":
		_geo.cylinder(Vector3(0,.03,0),.64,.06,"charcoal")
		for i in range(12):
			var a:float=TAU*i/12.0
			_rock(Vector3(cos(a)*.65,.01,sin(a)*.65),Vector3(.16,.19,.15),"stone")
		for i in range(4):_geo.rod(Vector3(-.32,.12,i*.12-.18),Vector3(.29,.13,i*.12-.13),.055,"charcoal")
		_pot(Vector3(.94,0,.35),.34,.46,"pottery")
		_furnishing({"id":"yard_quern","kind":"quern","at":[-1.6,.4]})
	elif record.use=="fishing":
		for x in [-1.5,1.5]:_solid_rod(Vector3(x,0,0),Vector3(x,1.6,0),.055,"wood")
		_geo.rod(Vector3(-1.65,1.55,0),Vector3(1.65,1.55,0),.07,"wood")
		for i in range(19):_geo.rod(Vector3(-1.4+i*.155,.4,0),Vector3(-1.4+i*.155,1.52,0),.007,"mat",.007,4)
		for i in range(12):_geo.rod(Vector3(-1.4,.43+i*.09,0),Vector3(1.4,.43+i*.09,0),.007,"mat",.007,4)
		_furnishing({"id":"bank_basket","kind":"basket","at":[-1,1]})
	else:
		_furnishing({"id":"clay_work","kind":"clay","at":[0,0]})
		_furnishing({"id":"clay_mat","kind":"mat","at":[-1.4,.1]})
	_finish()

func _landing(record: Dictionary) -> void:
	var at:=Vector3(record.at[0],surface_height(record.at[0],record.at[1])+.28,record.at[1])
	_begin(record.id,at,deg_to_rad(-30.0))
	# Hollow dugout-like interpretation; no medieval planks, sail, quay or fittings.
	for j in range(16):
		var z1:float=-2.3+j*4.6/16.0
		var z2:float=-2.3+(j+1)*4.6/16.0
		var w1:float=.54*pow(maxf(0.01,1.0-pow(z1/2.4,2)),.5)
		var w2:float=.54*pow(maxf(0.01,1.0-pow(z2/2.4,2)),.5)
		for i in range(12):
			var a:float=PI*i/12.0
			var b:float=PI*(i+1)/12.0
			var p:=Vector3(cos(a)*w1,.42-sin(a)*.4,z1)
			var q:=Vector3(cos(b)*w1,.42-sin(b)*.4,z1)
			var r:=Vector3(cos(b)*w2,.42-sin(b)*.4,z2)
			var s:=Vector3(cos(a)*w2,.42-sin(a)*.4,z2)
			_geo.quad(p,q,r,s,"wood_dark")
			_geo.quad(s+Vector3.UP*.07,r+Vector3.UP*.07,q+Vector3.UP*.07,p+Vector3.UP*.07,"wood")
	for side in [-1.0,1.0]:
		for j in range(16):
			var z1:float=-2.3+j*4.6/16.0
			var z2:float=-2.3+(j+1)*4.6/16.0
			var w1:float=.54*sqrt(maxf(.01,1-pow(z1/2.4,2)))
			var w2:float=.54*sqrt(maxf(.01,1-pow(z2/2.4,2)))
			_geo.rod(Vector3(side*w1,.43,z1),Vector3(side*w2,.43,z2),.045,"wood")
	for z in [-2.3,2.3]:
		for i in range(12):
			var a:float=PI*i/12.0
			var b:float=PI*(i+1)/12.0
			var center:=Vector3(0,.43,z)
			var pa:=Vector3(cos(a)*.155,.42-sin(a)*.4,z)
			var pb:=Vector3(cos(b)*.155,.42-sin(b)*.4,z)
			_geo.triangle(center,pa,pb,"wood")
			_geo.triangle(center,pb,pa,"wood")
	_geo.rod(Vector3(-.4,.5,-.8),Vector3(.65,.5,.3),.028,"wood_light")
	_geo.box(Vector3(.79,.5,.43),Vector3(.28,.045,.46),"wood_light",Vector3(0,-.75,0))
	solids.append({"at":at+Vector3.UP*.2,"size":Vector3(1.1,.4,4.6),"yaw":_yaw,"owner":_owner})
	_finish()

func _countryside() -> void:
	_begin("vegetation")
	# Deterministic clusters, open approaches, patchy riverside reeds.
	for i in range(210):
		var x:float=(hash01("trees",i)-.5)*360
		var z:float=(hash01("trees",i+500)-.5)*330-55
		if (x>-78 and x<68 and z>-58 and z<90) or surface_height(x,z)<1.3:continue
		_tree(Vector3(x,surface_height(x,z),z),3.5+hash01("tree_height",i)*4.5,i)
	for i in range(1450):
		var z:float=-140+hash01("reeds",i)*254
		var x:float=stream_x(z)+(.5+hash01("reeds",i+2000)*7.5)*(-1 if i%2==0 else 1)
		var p:=Vector3(x,surface_height(x,z),z)
		if p.y<-.1 or p.y>1.5:continue
		var h:float=.6+hash01("reed_h",i)*.9
		_geo.rod(p,p+Vector3(.1,h,.08),.017,"reed",.008,4)
		_geo.rod(p+Vector3(.1,h,.08),p+Vector3(.1,h+.15,.08),.035,"thatch_dark",.028,5)
	for i in range(5000):
		var x:float=(hash01("grass",i)-.5)*310
		var z:float=(hash01("grass",i+8300)-.5)*310
		if (absf(x)<40 and z>-36 and z<50) or surface_height(x,z)<.6:continue
		var p:=Vector3(x,surface_height(x,z),z)
		var h:float=.12+hash01("grass_h",i)*.3
		_geo.triangle(p,p+Vector3(.035,h,.06),p+Vector3(.09,0,0),"reed")
		_geo.triangle(p+Vector3(.09,0,0),p+Vector3(.035,h,.06),p,"reed")
	_finish()
	_begin("yard_traces")
	for i in range(330):
		var x:float=(hash01("stones",i)-.5)*68
		var z:float=(hash01("stones",i+700)-.5)*70
		if absf(x)<3:continue
		var inside:bool=false
		for b in buildings:
			if Vector2(x-b.at[0],z-b.at[1]).length()<4:inside=true
		if inside:continue
		_geo.box(Vector3(x,surface_height(x,z)+.012,z),Vector3(.045+hash01("stone",i)*.12,.03,.07),"stone",Vector3(0,i,.03))
	_finish()

func _rock(at:Vector3,size:Vector3,material:String) -> void:
	for ring in range(4):
		var a:float=PI*.5*ring/4
		var b:float=PI*.5*(ring+1)/4
		for i in range(9):
			var u:float=TAU*i/9
			var v:float=TAU*(i+1)/9
			var p:=at+Vector3(cos(a)*cos(u),sin(a),cos(a)*sin(u))*size
			var q:=at+Vector3(cos(a)*cos(v),sin(a),cos(a)*sin(v))*size
			var r:=at+Vector3(cos(b)*cos(v),sin(b),cos(b)*sin(v))*size
			var t:=at+Vector3(cos(b)*cos(u),sin(b),cos(b)*sin(u))*size
			_geo._oriented_quad(p,q,r,t,((p+q+r+t)*.25-at).normalized(),material)

func _tree(at: Vector3,h: float,index: int) -> void:
	_geo.rod(at,at+Vector3(.2,h*.72,.1),.16,"wood",.055,8)
	for j in range(5):
		var angle:float=j*2.4+index
		var branch:Vector3=at+Vector3(cos(angle)*h*.28,h*(.62+j*.06),sin(angle)*h*.26)
		_geo.rod(at+Vector3(0,h*.42,0),branch,.058,"wood",.02,6)
		# Original faceted elliptical foliage, no texture billboard.
		var radius:float=h*.26
		for ring in range(5):
			var a:float=-PI*.5+PI*ring/5.0
			var b:float=-PI*.5+PI*(ring+1)/5.0
			for k in range(9):
				var u:float=TAU*k/9.0
				var v:float=TAU*(k+1)/9.0
				var p:=branch+Vector3(cos(a)*cos(u),sin(a)*.8,cos(a)*sin(u))*radius
				var q:=branch+Vector3(cos(a)*cos(v),sin(a)*.8,cos(a)*sin(v))*radius
				var r:=branch+Vector3(cos(b)*cos(v),sin(b)*.8,cos(b)*sin(v))*radius
				var s:=branch+Vector3(cos(b)*cos(u),sin(b)*.8,cos(b)*sin(u))*radius
				_geo._oriented_quad(p,q,r,s,((p+q+r+s)*.25-branch).normalized(),"leaf" if (j+k)%3 else "leaf_light")
	# Trunk obstacle shares the rendered base location.
	solids.append({"at":at+Vector3.UP*h*.35,"size":Vector3(.34,h*.7,.34),"yaw":0.0,"owner":"vegetation"})

func floor_height(x: float,z: float) -> float:
	var h:float=surface_height(x,z)
	for item in floors:
		var b:Dictionary=item.record
		var local:=Vector2(x-b.at[0],z-b.at[1]).rotated(deg_to_rad(float(b.yaw)))
		var inside:bool=absf(local.x)<float(b.size[0])*.5 and absf(local.y)<float(b.size[1])*.5
		if b.roof=="round":inside=pow(local.x/(float(b.size[0])*.5),2)+pow(local.y/(float(b.size[1])*.5),2)<1
		if inside:h=maxf(h,item.height)
	return h

func blocked(point: Vector3, radius: float = .23) -> bool:
	var h:float=floor_height(point.x,point.z)
	if h<.12 or absf(point.x)>data.terrain.walk_limit or absf(point.z)>data.terrain.walk_limit:return true
	for box in solids:
		var at:Vector3=box.at
		var half:Vector3=box.size*.5
		if at.y+half.y<h+.14 or at.y-half.y>h+1.82:continue
		var local:Vector3=Basis(Vector3.UP,-float(box.yaw))*(point-at)
		var dx:float=maxf(absf(local.x)-half.x,0)
		var dz:float=maxf(absf(local.z)-half.z,0)
		if dx*dx+dz*dz<radius*radius:return true
	return false

func walk(from: Vector3,delta: Vector3) -> Vector3:
	var position_:Vector3=from
	var count:int=maxi(1,int(ceil(delta.length()/.09)))
	var step:Vector3=delta/count
	for i in range(count):
		var target:Vector3=position_+Vector3(step.x,0,step.z)
		var next_h:float=floor_height(target.x,target.z)
		if not blocked(target) and absf(next_h-floor_height(position_.x,position_.z))<.27:
			position_=target
		else:
			for part in [Vector3(step.x,0,0),Vector3(0,0,step.z)]:
				var side:Vector3=position_+part
				if not blocked(side) and absf(floor_height(side.x,side.z)-floor_height(position_.x,position_.z))<.27:position_=side
	position_.y=floor_height(position_.x,position_.z)+1.68
	return position_

func pick(origin: Vector3,direction: Vector3,max_distance: float = 180.0) -> Dictionary:
	# Uses the exact same placed nodes and collider pieces as drawing/walking.
	var best:float=max_distance
	var selected:String=""
	for box in solids:
		if not box.owner.begins_with("yk_"):continue
		var basis:=Basis(Vector3.UP,-float(box.yaw))
		var start:Vector3=basis*(origin-box.at)
		var end:Vector3=start+basis*direction*max_distance
		var bounds:=AABB(-box.size*.5,box.size)
		var hit:Variant=bounds.intersects_segment(start,end)
		if hit!=null:
			var distance:float=start.distance_to(hit)
			if distance<best:best=distance;selected=box.owner
	return {"id":selected,"distance":best}
