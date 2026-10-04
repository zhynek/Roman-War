extends RefCounted
## Original, explicitly interpretive architectural assemblies. Authored envelopes
## and historical status come from the standalone city's data, never game state.
## build() returns local +Y-up geometry; the caller positions/orients its root.

const Geometry = preload("res://src/geometry.gd")

var g: RefCounted
var root: Node3D
var body: StaticBody3D
var materials: Dictionary
var dimensions: Dictionary
var lead: String = "roof"

static func build(item: Dictionary, p_materials: Dictionary) -> Node3D:
	var builder: RefCounted = load("res://src/landmarks.gd").new()
	return builder._build(item,p_materials)

func _build(item: Dictionary, p_materials: Dictionary) -> Node3D:
	materials = p_materials
	g = Geometry.new(materials)
	root = Node3D.new()
	root.name = str(item.get("id","landmark"))
	root.set_meta("landmark_id",str(item.get("id","landmark")))
	root.set_meta("interpretive_geometry",true)
	dimensions = item.get("dimensions",{})
	lead = "lead" if materials.has("lead") else "roof"
	body = StaticBody3D.new()
	body.name = "ArchitecturalCollision"
	root.add_child(body)
	var w: float = float(dimensions.get("width_m",24.0))
	var d: float = float(dimensions.get("depth_m",36.0))
	var h: float = float(dimensions.get("height_m",18.0))
	match str(item.get("kind","church")):
		"hagia_sophia": _hagia_sophia(w,d,h)
		"hippodrome": _hippodrome(w,d,h)
		"monastery": _monastery(w,d,h)
		"palace": _palace(w,d,h)
		"cistern": _cistern(w,d,h)
		"aqueduct": _aqueduct(w,d,h)
		"column": _monument_column(w,d,h)
		"gate": _gate(w,d,h)
		_: _church(w,d,h)
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "OriginalArchitecture"
	mesh_node.mesh = g.finish()
	root.add_child(mesh_node)
	root.set_meta("authored_vertex_count",int(g.vertex_count))
	if not root.has_meta("interior_anchor"):
		root.set_meta("interior_anchor",Vector3(0,2,-d*0.2))
	root.set_meta("entrance_anchor",Vector3(0,2,-d*0.5-4.0))
	return root

func _solid(at: Vector3, size: Vector3, material: String, rotation: Vector3 = Vector3.ZERO) -> void:
	g.box(at,size,material,rotation)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	collision.rotation = rotation
	body.add_child(collision)

func _column(at: Vector3, height: float, radius: float, material: String = "stone") -> void:
	var foot: float = minf(radius*0.65,height*0.08)
	g.box(at+Vector3.UP*foot*0.5,Vector3(radius*2.9,foot,radius*2.9),"stone")
	g.cylinder(at+Vector3.UP*foot*1.4,radius*1.19,foot,material)
	g.cylinder(at+Vector3.UP*height*0.48,radius,height*0.86,material,radius*0.83)
	g.cylinder(at+Vector3.UP*(height-foot*1.4),radius*1.17,foot*1.4,"stone",radius*1.46)
	g.box(at+Vector3.UP*(height-foot*0.35),Vector3(radius*2.95,foot*0.7,radius*2.95),"stone")
	# Carved impost and restrained corner volutes use original geometry.
	for side in [-1.0,1.0]:
		g.box(at+Vector3(side*radius,height-foot*0.75,0),Vector3(radius*0.28,foot*0.65,radius*2.15),"plaster")

func _arcade(a: Vector3, b: Vector3, bays: int, height: float, depth: float, material: String = "stone") -> void:
	bays = maxi(bays,ceili(a.distance_to(b)/maxf(1.0,height*1.20)))
	var direction: Vector3 = (b-a).normalized()
	var spacing: float = a.distance_to(b)/maxi(1,bays)
	var radius: float = minf(spacing*0.105,height*0.085)
	var opening: float = spacing-radius*2.0
	var spring: float = maxf(height*0.25,height-opening*0.5)
	var yaw: float = atan2(-direction.z,direction.x)
	for i in range(bays+1):
		_column(a+direction*spacing*i,spring,radius,material)
	for i in range(bays):
		g.arch(a+direction*spacing*(i+0.5)+Vector3.UP*spring,opening,opening*0.5,depth,maxf(0.20,spacing*0.065),material,yaw)

func _window(at: Vector3, width: float, height: float, yaw: float = 0.0, frame: String = "stone") -> void:
	var basis := Basis(Vector3.UP,yaw)
	var radius: float = width*0.5
	var spring: float = maxf(0.05,height-radius)
	g.box(at+basis*Vector3(0,spring*0.5,0.025),Vector3(width,spring,0.05),"glass",Vector3(0,yaw,0))
	for i in range(12):
		var aa: float = PI*float(i)/12.0
		var ab: float = PI*float(i+1)/12.0
		var center: Vector3 = at+basis*Vector3(0,spring,0)
		var a: Vector3 = at+basis*Vector3(cos(aa)*radius,spring+sin(aa)*radius,0)
		var b: Vector3 = at+basis*Vector3(cos(ab)*radius,spring+sin(ab)*radius,0)
		g.triangle(center,a,b,"glass")
		g.triangle(center,b,a,"glass")
	g.arch(at,width,height,0.22,maxf(0.10,width*0.075),frame,yaw)
	g.box(at+basis*Vector3(0,height*0.40,-0.10),Vector3(maxf(0.045,width*0.07),height*0.8,0.09),"stone",Vector3(0,yaw,0))
	g.box(at+basis*Vector3(0,spring*0.5,-0.10),Vector3(width,0.065,0.09),"stone",Vector3(0,yaw,0))

func _bands(at: Vector3, width: float, depth: float, height: float, material: String = "brick") -> void:
	_solid(at+Vector3.UP*height*0.5,Vector3(width,height,depth),material)
	for f in [0.12,0.39,0.68,0.94]:
		g.box(at+Vector3.UP*(height*f),Vector3(width+0.06,maxf(0.16,height*0.012),depth+0.06),"stone")

func _drum(at: Vector3, radius: float, height: float, windows: int, material: String = "brick") -> void:
	var step: float = TAU/windows
	for i in range(windows):
		var angle: float = step*i
		var pos: Vector3 = at+Vector3(cos(angle),0,sin(angle))*radius
		var tangent_yaw: float = -angle-PI*0.5
		var bay: float = step*radius
		g.box(pos+Vector3.UP*height*0.5,Vector3(bay*0.26,height,0.8),material,Vector3(0,tangent_yaw,0))
		var window_angle: float = angle+step*0.5
		var p: Vector3 = at+Vector3(cos(window_angle),0,sin(window_angle))*radius
		_window(p+Vector3.UP*height*0.12,bay*0.52,height*0.72,-window_angle-PI*0.5)
		g.box(pos+Vector3.UP*(height+0.15),Vector3(bay*1.07,0.32,1.1),"stone",Vector3(0,tangent_yaw,0))
		g.box(pos+Vector3.UP*0.14,Vector3(bay*1.07,0.28,1.1),"stone",Vector3(0,tangent_yaw,0))

func _dome_ribs(at: Vector3, radius: float, height: float, count: int, material: String) -> void:
	for rib in range(count):
		var angle: float = TAU*rib/count
		for segment in range(8):
			var aa: float = PI*0.5*segment/8.0
			var ab: float = PI*0.5*(segment+1)/8.0
			var a: Vector3 = at+Vector3(cos(angle)*cos(aa)*radius,sin(aa)*height,sin(angle)*cos(aa)*radius)
			var b: Vector3 = at+Vector3(cos(angle)*cos(ab)*radius,sin(ab)*height,sin(angle)*cos(ab)*radius)
			g.rod(a,b,maxf(0.025,radius*0.004),material,-1.0,6)

func _cross(at: Vector3, size: float) -> void:
	g.box(at+Vector3.UP*size*0.5,Vector3(size*0.095,size,size*0.095),"gold")
	g.box(at+Vector3.UP*size*0.65,Vector3(size*0.57,size*0.095,size*0.095),"gold")

func _hagia_sophia(w: float, d: float, h: float) -> void:
	var radius: float = float(dimensions.get("dome_radius_m",w*0.2123))
	var dome_height: float = float(dimensions.get("dome_height_m",h*0.243))
	var dome_base: float = h-dome_height
	var aisle_height: float = float(dimensions.get("arcade_height_m",h*0.27))
	var outside_height: float = h*0.47
	var wall: float = w*0.018
	for step in range(3):
		_solid(Vector3(0,0.10+step*0.10,0),Vector3(w+3.0-step,0.20,d+4.0-step),"stone")
	# Floor panels and geometric marble inlays are original; no copied mosaic.
	for i in range(9):
		g.box(Vector3((i-4)*w*0.10,0.43,0),Vector3(w*0.099,0.045,d*0.90),"plaster" if i%2 else "stone")
	for z in [-d*0.34,0.0,d*0.32]:
		g.cylinder(Vector3(0,0.465,z),radius*0.24,0.04,"dark")
		g.cylinder(Vector3(0,0.488,z),radius*0.20,0.03,"stone")
		g.cylinder(Vector3(0,0.51,z),radius*0.075,0.03,"green")
	for side in [-1.0,1.0]:
		_bands(Vector3(side*(w*0.5-wall*0.5),0,0),wall,d,outside_height)
		# Side aisle roof and gallery leave the nave genuinely hollow.
		var aisle_width: float = w*0.5-radius
		var aisle_x: float = side*(radius+aisle_width*0.5)
		_solid(Vector3(aisle_x,aisle_height,0),Vector3(aisle_width,0.65,d*0.92),"stone")
		g.roof(Vector3(aisle_x,outside_height,0),aisle_width+0.8,d+0.7,3.0,lead)
		_arcade(Vector3(side*(radius+1.4),0.45,-d*0.35),Vector3(side*(radius+1.4),0.45,d*0.35),9,aisle_height-0.5,1.1,"green")
		_arcade(Vector3(side*(radius+1.3),aisle_height+0.4,-d*0.35),Vector3(side*(radius+1.3),aisle_height+0.4,d*0.35),12,outside_height-aisle_height-0.4,0.9,"stone")
		for i in range(13):
			var z: float = -d*0.44+i*d*0.88/12.0
			_window(Vector3(side*(w*0.5+0.04),outside_height*0.57,z),1.6,4.4,-side*PI*0.5)
			g.box(Vector3(side*(radius+1.25),aisle_height+1.0,z),Vector3(0.34,1.4,d*0.060),"stone")
		# Exterior projecting buttresses, stepped toward the upper masonry.
		for z in [-d*0.31,0.0,d*0.31]:
			_bands(Vector3(side*(w*0.5+1.5),0,z),3.3,4.5,outside_height*0.84)
			g.roof(Vector3(side*(w*0.5+1.5),outside_height*0.84,z),3.8,4.8,2.2,lead)
		# Return walls close both ends of each aisle instead of exposing a
		# cutaway building to the surrounding city.
		for end in [-1.0,1.0]:
			_bands(Vector3(aisle_x,0,end*(d*0.5-wall*0.5)),aisle_width,wall,outside_height)
			for i in range(3):
				_window(Vector3(aisle_x+(i-1)*aisle_width*0.27,outside_height*0.57,end*(d*0.5+0.02)),1.5,4.0,PI if end > 0.0 else 0.0)
	# Western narthex: three actual open doorways, not a solid facade block.
	for i in [-2,-1,0,1,2]:
		var x: float = i*w*0.185
		if abs(i) == 2:
			_bands(Vector3(x,0,-d*0.5),w*0.115,wall,outside_height)
	for side in [-1.0,1.0]:
		_bands(Vector3(side*w*0.07,0,-d*0.5),w*0.055,wall,outside_height)
	g.arch(Vector3(0,0.45,-d*0.5),w*0.085,8.5,wall,0.75,"stone")
	g.box(Vector3(0,17.5,-d*0.5),Vector3(w*0.16,17.0,wall),"brick")
	for x in [-w*0.185,w*0.185]:
		g.arch(Vector3(x,0.45,-d*0.5),w*0.13,9.0,wall,0.85,"stone")
		g.box(Vector3(x,17.5,-d*0.5),Vector3(w*0.18,17.0,wall),"brick")
	for i in range(9):
		_window(Vector3((i-4)*w*0.092,15.1,-d*0.5-wall*0.55),1.35,3.5)
	g.arch(Vector3(0,0.45,-d*0.5-4.0),6.2,8.5,1.5,0.85,"stone")
	_arcade(Vector3(-w*0.43,0.45,-d*0.5-4.0),Vector3(-5.1,0.45,-d*0.5-4.0),5,8.5,1.0)
	_arcade(Vector3(5.1,0.45,-d*0.5-4.0),Vector3(w*0.43,0.45,-d*0.5-4.0),5,8.5,1.0)
	g.roof(Vector3(0,10.0,-d*0.5-2.3),w*0.95,7.0,2.0,lead)
	# Four principal piers and great arches support a ring rather than a box.
	var pier: float = radius*0.30
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			var p := Vector3(sx*(radius+0.1),0,sz*(radius+0.1))
			_bands(p,pier,pier,dome_base-radius*0.42,"stone")
			for f in [0.16,0.35,0.55]:
				g.box(p+Vector3.UP*dome_base*f,Vector3(pier+0.15,0.23,pier+0.15),"green")
	for sign_value in [-1.0,1.0]:
		var clear_span: float = radius*2.0-pier*0.45
		var spring: float = dome_base-clear_span*0.5-0.7
		g.arch(Vector3(0,spring,sign_value*radius),clear_span,clear_span*0.5,2.6,1.25,"stone")
		g.arch(Vector3(sign_value*radius,spring,0),clear_span,clear_span*0.5,2.6,1.25,"stone",PI*0.5)
	# Pendentive approximations bridge each square corner into the dome ring.
	for quadrant in range(4):
		var a0: float = quadrant*PI*0.5
		var corner := Vector3(cos(a0+PI*0.25)*radius*1.37,dome_base-radius*0.46,sin(a0+PI*0.25)*radius*1.37)
		for segment in range(12):
			var a: float = a0+PI*0.5*segment/12.0
			var b: float = a0+PI*0.5*(segment+1)/12.0
			var p := Vector3(cos(a)*radius,dome_base,sin(a)*radius)
			var q := Vector3(cos(b)*radius,dome_base,sin(b)*radius)
			g.triangle(corner,p,q,"gold")
			g.triangle(corner,q,p,"brick")
	_drum(Vector3(0,dome_base-2.6,0),radius,2.6,40)
	g.dome_section(Vector3(0,dome_base,0),radius,dome_height,lead,0.0,TAU,"gold")
	_dome_ribs(Vector3(0,dome_base+0.12,0),radius+0.07,dome_height,40,"stone")
	_cross(Vector3(0,h,0),1.5)
	for side in [-1.0,1.0]:
		var base := Vector3(0,h*0.49,side*radius)
		var start_angle: float = 0.0 if side > 0 else PI
		g.dome_section(base,radius*1.02,dome_base-base.y,lead,start_angle,start_angle+PI,"gold")
		_round_wall_shell(Vector3(base.x,0,base.z),radius*1.02,base.y,start_angle,start_angle+PI,1.05,4.2)
		g.arch(Vector3(0,0.45,side*radius*2.02),8.2,9.6,1.3,0.75,"stone")
		for sx in [-1.0,1.0]:
			var exedra := Vector3(sx*radius*0.66,h*0.33,side*(radius*2.02+0.30))
			g.dome_section(exedra,radius*0.50,h*0.12,lead,start_angle,start_angle+PI,"gold")
			_round_wall_shell(Vector3(exedra.x,0,exedra.z),radius*0.50,exedra.y,start_angle,start_angle+PI,0.75)
		# High tympanum clerestory creates the familiar stepped side silhouette.
		var lower_edge: float = h*0.47
		for segment in range(24):
			var za: float = -radius+segment*radius*2.0/24.0
			var zb: float = za+radius*2.0/24.0
			var z: float = (za+zb)*0.5
			var upper: float = dome_base-radius+sqrt(maxf(0.0,radius*radius-z*z))
			if upper > lower_edge:
				g.box(Vector3(side*(radius+1.25),(upper+lower_edge)*0.5,z),Vector3(1.15,upper-lower_edge,zb-za+0.025),"brick")
		for row in range(2):
			for i in range(7-row*2):
				var z: float = (i-(6-row*2)*0.5)*3.6
				_window(Vector3(side*(radius+1.87),h*0.55+row*3.5,z),1.45,2.8,-side*PI*0.5)
				_window(Vector3(side*(radius+0.62),h*0.55+row*3.5,z),1.45,2.8,side*PI*0.5)
	# Eastern apse shell and a modest sanctuary; no Ottoman furnishings.
	var apse_radius: float = radius*0.47
	for i in range(16):
		var angle: float = PI*float(i)/16.0
		var p := Vector3(cos(angle)*apse_radius,0,d*0.43+sin(angle)*apse_radius)
		_bands(p,PI*apse_radius/16.0+0.15,1.0,h*0.28)
	g.dome_section(Vector3(0,h*0.28,d*0.43),apse_radius,h*0.09,lead,0.0,PI,"gold")
	for side in [-1.0,1.0]:
		var shoulder_width: float = radius-apse_radius+1.2
		var shoulder_x: float = side*(radius+apse_radius)*0.5
		var shoulder_start: float = radius*2.02+0.4
		var shoulder_depth: float = d*0.5-shoulder_start
		_bands(Vector3(shoulder_x,0,d*0.43),shoulder_width,1.0,h*0.33)
		g.roof(Vector3(shoulder_x,h*0.33,shoulder_start+shoulder_depth*0.5),shoulder_width+0.5,shoulder_depth,h*0.055,lead)
		_window(Vector3(shoulder_x,h*0.19,d*0.43+0.57),1.4,3.7,PI)
	_solid(Vector3(0,0.8,d*0.31),Vector3(radius*0.9,0.65,d*0.15),"stone")
	g.box(Vector3(0,1.7,d*0.32),Vector3(3.0,1.25,1.8),"plaster")
	for x in [-2.5,2.5]:
		g.cylinder(Vector3(x,2.3,d*0.32),0.09,2.8,"gold")
	# Hanging lamps make the nave's spatial scale legible without texture art.
	for z in [-radius*0.65,radius*0.65]:
		for x in [-radius*0.55,0.0,radius*0.55]:
			g.rod(Vector3(x,aisle_height+2,z),Vector3(x,6.1,z),0.025,"gold",-1.0,6)
			g.cylinder(Vector3(x,5.9,z),0.65,0.18,"gold")
			g.cylinder(Vector3(x,6.1,z),0.37,0.25,"glass")
			_inspection_light(Vector3(x,6.0,z),Color("#ffe1ac"),4.0,30.0)
	root.set_meta("interior_anchor",Vector3(0,2.2,-radius*0.72))

func _inspection_light(at: Vector3, color: Color, energy: float, distance: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = distance
	light.omni_attenuation = 0.85
	light.shadow_enabled = false
	light.name = "InterpretiveInteriorLight"
	root.add_child(light)
	var fixture := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	sphere.radial_segments = 12
	sphere.rings = 6
	fixture.mesh = sphere
	fixture.position = at
	fixture.name = "InterpretiveInspectionLamp"
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 2.0
	fixture.material_override = glow
	root.add_child(fixture)

func _round_wall_shell(at: Vector3, radius: float, height: float, start_angle: float, end_angle: float, thickness: float, entry_half_width: float = 0.0) -> void:
	var segments: int = 24
	var angular_step: float = (end_angle-start_angle)/segments
	var span: float = radius*angular_step
	for segment in range(segments):
		var angle: float = start_angle+(segment+0.5)*angular_step
		var p: Vector3 = at+Vector3(cos(angle)*radius,0,sin(angle)*radius)
		var from_y: float = 10.0 if entry_half_width > 0.0 and absf(cos(angle)*radius) < entry_half_width else 0.0
		var wall_height: float = height-from_y
		if wall_height <= 0.0:
			continue
		_solid(p+Vector3.UP*(from_y+wall_height*0.5),Vector3(span+0.05,wall_height,thickness),"brick",Vector3(0,-angle-PI*0.5,0))
		var inward: Vector3 = -Vector3(cos(angle),0,sin(angle))
		var lining: Vector3 = p+inward*(thickness*0.5+0.045)
		# Revetment is original geometric marble paneling. Its layout is explicitly
		# interpretive; no historic inscription, figural mosaic or imported image.
		if from_y == 0.0:
			g.box(lining+Vector3.UP*height*0.16,Vector3(span*0.97,height*0.30,0.065),"plaster",Vector3(0,-angle-PI*0.5,0))
			g.box(lining+inward*0.045+Vector3.UP*height*0.16,Vector3(span*0.70,height*0.245,0.045),"green" if segment%3 == 1 else "stone",Vector3(0,-angle-PI*0.5,0))
			g.box(lining+inward*0.06+Vector3.UP*height*0.32,Vector3(span+0.08,0.16,0.07),"gold",Vector3(0,-angle-PI*0.5,0))
		if segment%3 == 1 and height > 20.0:
			_window(lining+inward*0.08+Vector3.UP*height*0.54,minf(1.25,span*0.7),4.1,-angle+PI*0.5)
		for f in [0.18,0.48,0.86]:
			if height*f >= from_y:
				g.box(p+Vector3.UP*(height*f),Vector3(span+0.08,0.20,thickness+0.10),"stone",Vector3(0,-angle-PI*0.5,0))

func _church(w: float, d: float, h: float) -> void:
	if bool(dimensions.get("basilican",0)):
		_basilica(w,d,h)
		return
	var lower: float = h*0.48
	var arm: float = w*0.36
	var radius: float = float(dimensions.get("dome_radius_m",w*0.205))
	var dome_height: float = float(dimensions.get("dome_height_m",h*0.20))
	var dome_base: float = h-dome_height
	_solid(Vector3(0,0.18,0),Vector3(w+1.3,0.36,d+1.3),"stone")
	for side in [-1.0,1.0]:
		_bands(Vector3(side*w*0.48,0,0),w*0.045,d*0.78,lower)
		g.roof(Vector3(side*w*0.30,lower,0),w*0.38,d*0.87,h*0.09,"roof")
		_bands(Vector3(side*w*0.285,0,-d*0.47),w*0.38,0.7,lower)
		for i in range(4):
			_window(Vector3(side*w*0.505,lower*0.46,(i-1.5)*d*0.20),w*0.07,h*0.15,-side*PI*0.5)
	g.arch(Vector3(0,0.35,-d*0.47),w*0.17,h*0.28,0.85,0.45,"stone")
	g.box(Vector3(0,lower*0.85,-d*0.47),Vector3(w*0.20,lower*0.3,0.7),"brick")
	g.roof(Vector3(0,lower*1.08,-d*0.13),arm,d*0.74,h*0.15,"roof")
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			_column(Vector3(sx*radius*0.82,0.35,sz*radius*0.82),h*0.46,w*0.025,"green")
		g.arch(Vector3(sx*radius,h*0.42,0),radius*1.85,radius*0.925,0.7,0.4,"stone",PI*0.5)
	_drum(Vector3(0,dome_base-h*0.14,0),radius,h*0.14,12)
	g.dome_section(Vector3(0,dome_base,0),radius,dome_height,lead,0,TAU,"gold")
	_dome_ribs(Vector3(0,dome_base+0.05,0),radius+0.04,dome_height,12,"stone")
	_cross(Vector3(0,h,0),maxf(0.5,w*0.055))
	if int(dimensions.get("dome_count",1)) >= 5:
		for position in [Vector3(w*0.33,h*0.63,0),Vector3(-w*0.33,h*0.63,0),Vector3(0,h*0.63,d*0.32),Vector3(0,h*0.63,-d*0.32)]:
			_drum(position,radius*0.64,h*0.10,10)
			g.dome_section(position+Vector3.UP*h*0.10,radius*0.64,h*0.15,lead,0.0,TAU,"gold")
			_cross(position+Vector3.UP*h*0.25,maxf(0.5,w*0.032))
	for i in range(12):
		var angle: float = PI*float(i)/12.0
		var p := Vector3(cos(angle)*arm*0.46,0,d*0.33+sin(angle)*arm*0.46)
		g.box(p+Vector3.UP*lower*0.4,Vector3(arm*0.135,lower*0.8,0.6),"brick",Vector3(0,-angle-PI*0.5,0))
	g.dome_section(Vector3(0,lower*0.8,d*0.33),arm*0.46,h*0.10,"roof",0,PI,"gold")
	g.box(Vector3(0,1.0,d*0.28),Vector3(w*0.12,1.3,d*0.06),"stone")
	root.set_meta("interior_anchor",Vector3(0,1.9,-d*0.23))

func _basilica(w: float, d: float, h: float) -> void:
	var aisle_height: float = h*0.47
	var nave_height: float = h*0.70
	var nave_width: float = float(dimensions.get("nave_width_m",w*0.50))
	var has_dome: bool = int(dimensions.get("dome_count",0)) > 0
	_solid(Vector3(0,0.18,0),Vector3(w+1.2,0.36,d+1.2),"stone")
	for side in [-1.0,1.0]:
		_bands(Vector3(side*w*0.49,0,0),0.85,d*0.91,aisle_height)
		_arcade(Vector3(side*nave_width*0.51,0.36,-d*0.37),Vector3(side*nave_width*0.51,0.36,d*0.32),12,aisle_height-0.36,0.7,"green")
		g.box(Vector3(side*nave_width*0.52,(aisle_height+nave_height)*0.5,0),Vector3(0.8,nave_height-aisle_height,d*0.90),"brick")
		g.roof(Vector3(side*(w+nave_width)*0.25,aisle_height,0),(w-nave_width)*0.5+0.8,d*0.92,1.5,"roof")
		for i in range(11):
			_window(Vector3(side*(nave_width*0.52+0.45),aisle_height+0.7,(i-5)*d*0.075),1.3,maxf(1.8,nave_height-aisle_height-1.6),-side*PI*0.5)
		_bands(Vector3(side*w*0.33,0,-d*0.46),w*0.29,0.8,aisle_height)
	g.arch(Vector3(0,0.36,-d*0.46),w*0.18,aisle_height*0.80,1.0,0.7,"stone")
	_arcade(Vector3(-w*0.45,0.36,-d*0.50-2.0),Vector3(w*0.45,0.36,-d*0.50-2.0),7,aisle_height*0.78,0.75)
	g.roof(Vector3(0,aisle_height*0.90,-d*0.49),w*0.97,6.0,h*0.07,"roof")
	if has_dome:
		var radius: float = float(dimensions.get("dome_radius_m",nave_width*0.49))
		var dome_height: float = float(dimensions.get("dome_height_m",h*0.23))
		var dome_base: float = h-dome_height
		_drum(Vector3(0,nave_height,0),radius,maxf(1.0,dome_base-nave_height),20)
		g.dome_section(Vector3(0,dome_base,0),radius,dome_height,lead,0.0,TAU,"gold")
		_dome_ribs(Vector3(0,dome_base+0.05,0),radius+0.04,dome_height,20,"stone")
		for side in [-1.0,1.0]:
			g.roof(Vector3(0,nave_height,side*(d*0.225+radius*0.5)),nave_width+1.0,d*0.45-radius,h*0.09,"roof")
	else:
		g.roof(Vector3(0,nave_height,0),nave_width+1.0,d*0.91,h*0.12,"roof")
		for i in range(13):
			var z: float = (i-6)*d*0.067
			g.box(Vector3(0,nave_height-0.25,z),Vector3(nave_width,0.30,0.26),"wood")
			g.rod(Vector3(-nave_width*0.5,nave_height,z),Vector3(0,nave_height+h*0.12-0.35,z),0.16,"wood",-1.0,6)
			g.rod(Vector3(nave_width*0.5,nave_height,z),Vector3(0,nave_height+h*0.12-0.35,z),0.16,"wood",-1.0,6)
	var apse: float = nave_width*0.49
	for i in range(16):
		var angle: float = PI*i/16.0
		g.box(Vector3(cos(angle)*apse,aisle_height*0.5,d*0.39+sin(angle)*apse),Vector3(PI*apse/16.0+0.05,aisle_height,0.7),"brick",Vector3(0,-angle-PI*0.5,0))
	g.dome_section(Vector3(0,aisle_height,d*0.39),apse,h*0.12,"roof",0,PI,"gold")
	g.box(Vector3(0,1.2,d*0.30),Vector3(w*0.11,1.1,d*0.045),"stone")

func _monastery(w: float, d: float, h: float) -> void:
	var wing: float = minf(w,d)*0.16
	var wing_height: float = h*0.36
	for side in [-1.0,1.0]:
		_bands(Vector3(side*(w-wing)*0.5,0,0),wing,d,wing_height)
		g.roof(Vector3(side*(w-wing)*0.5,wing_height,0),wing+0.6,d+0.6,wing*0.23,"roof")
		_bands(Vector3(0,0,side*(d-wing)*0.5),w-wing*2.0,wing,wing_height)
		g.roof(Vector3(0,wing_height,side*(d-wing)*0.5),w-wing*2.0+0.6,wing+0.6,wing*0.19,"roof")
		_arcade(Vector3(side*(w*0.5-wing-1.5),0,-d*0.34),Vector3(side*(w*0.5-wing-1.5),0,d*0.34),8,wing_height*0.75,0.7)
		_arcade(Vector3(-w*0.34,0,side*(d*0.5-wing-1.5)),Vector3(w*0.34,0,side*(d*0.5-wing-1.5)),8,wing_height*0.75,0.7)
		for i in range(8):
			_window(Vector3(side*(w*0.5+0.03),wing_height*0.39,(i-3.5)*d*0.11),1.1,2.0,-side*PI*0.5)
	var church_count: int = int(dimensions.get("church_count",1))
	for church_index in range(church_count):
		var church_dimensions: Dictionary = dimensions.duplicate(true)
		church_dimensions.width_m = w*(0.18 if church_count > 1 else 0.38)
		church_dimensions.depth_m = d*0.47
		church_dimensions.height_m = h*(0.88 if church_count > 1 and church_index == 1 else 1.0)
		var church: Node3D = build({"id":"courtyard_church_%s"%church_index,"kind":"church","dimensions":church_dimensions},materials)
		church.position = Vector3((church_index-(church_count-1)*0.5)*w*0.178,0,d*0.04)
		root.add_child(church)
	g.cylinder(Vector3(-w*0.19,0.5,-d*0.16),minf(w,d)*0.035,1.0,"stone")
	g.cylinder(Vector3(-w*0.19,1.02,-d*0.16),minf(w,d)*0.026,0.10,"water")
	for side in [-1.0,1.0]:
		for i in range(5):
			g.box(Vector3(side*w*0.255,0.08,(i-2)*d*0.12),Vector3(w*0.10,0.16,d*0.095),"green")
	root.set_meta("interior_anchor",Vector3(0,2,-d*0.20))

func _palace(w: float, d: float, h: float) -> void:
	if bool(dimensions.get("warehouse",0)):
		_warehouse(w,d,h)
		return
	var wing: float = w*0.18
	var hall_height: float = h*0.72
	_solid(Vector3(0,0.18,0),Vector3(w+2,0.36,d+2),"stone")
	for side in [-1.0,1.0]:
		_bands(Vector3(side*(w-wing)*0.5,0,0),wing,d,h*0.58,"plaster")
		g.roof(Vector3(side*(w-wing)*0.5,h*0.58,0),wing+1.0,d+1.0,wing*0.20,"roof")
		_arcade(Vector3(side*(w*0.5-wing-2.0),0.4,-d*0.38),Vector3(side*(w*0.5-wing-2.0),0.4,d*0.34),10,h*0.26,1.0,"stone")
		_arcade(Vector3(side*(w*0.5-wing-2.0),h*0.30,-d*0.38),Vector3(side*(w*0.5-wing-2.0),h*0.30,d*0.34),10,h*0.23,0.8,"stone")
		_solid(Vector3(side*(w*0.5-wing*0.6),h*0.29,-d*0.02),Vector3(wing*0.8,0.6,d*0.79),"stone")
		for i in range(11):
			_window(Vector3(side*(w*0.5+0.04),h*0.33,(i-5)*d*0.083),1.5,3.4,-side*PI*0.5)
	_bands(Vector3(0,0,d*0.35),w-wing*1.6,d*0.29,hall_height,"plaster")
	g.roof(Vector3(0,hall_height,d*0.35),w-wing*1.5,d*0.30,h*0.15,"roof")
	_arcade(Vector3(-w*0.30,0.4,d*0.18),Vector3(w*0.30,0.4,d*0.18),9,h*0.33,1.6)
	for i in range(7):
		_window(Vector3((i-3)*w*0.073,h*0.41,d*0.20),w*0.035,h*0.16)
	# Entry loggia remains open into the garden court.
	_arcade(Vector3(-w*0.32,0.4,-d*0.43),Vector3(w*0.32,0.4,-d*0.43),9,h*0.31,1.3)
	g.roof(Vector3(0,h*0.34,-d*0.435),w*0.71,d*0.11,h*0.09,"roof")
	g.cylinder(Vector3(0,0.58,-d*0.07),minf(w,d)*0.08,0.8,"stone")
	g.cylinder(Vector3(0,1.01,-d*0.07),minf(w,d)*0.069,0.07,"water")
	g.cylinder(Vector3(0,1.40,-d*0.07),minf(w,d)*0.022,0.8,"stone")
	for side in [-1.0,1.0]:
		for i in range(4):
			g.box(Vector3(side*w*0.18,0.18,-d*0.27+i*d*0.12),Vector3(w*0.12,0.36,d*0.08),"green")
			_cypress(Vector3(side*w*0.265,0.4,-d*0.25+i*d*0.135),h*0.40)
	root.set_meta("interior_anchor",Vector3(0,2,-d*0.22))

func _warehouse(w: float, d: float, h: float) -> void:
	var width: float = w*0.22
	for side in [-1.0,1.0]:
		_bands(Vector3(side*w*0.37,0,0),width,d,h*0.72,"plaster")
		g.roof(Vector3(side*w*0.37,h*0.72,0),width+0.8,d+0.8,h*0.28,"roof")
		for i in range(7):
			var z: float = (i-3)*d*0.12
			g.box(Vector3(side*(w*0.37-width*0.5-0.035),2.4,z),Vector3(0.12,4.8,3.2),"wood")
			for beam in range(3):
				g.box(Vector3(side*(w*0.37-width*0.5-0.12),0.9+beam*1.45,z),Vector3(0.09,0.13,3.3),"dark")
	_bands(Vector3(0,0,d*0.40),w*0.55,d*0.20,h*0.65,"plaster")
	g.roof(Vector3(0,h*0.65,d*0.40),w*0.56,d*0.21,h*0.23,"roof")
	_arcade(Vector3(-w*0.23,0,d*0.26),Vector3(w*0.23,0,d*0.26),12,h*0.55,0.6,"stone")
	for i in range(30):
		var x: float = ((i*7)%13-6)*w*0.025
		var z: float = ((i*11)%17-8)*d*0.034
		g.box(Vector3(x,0.75,z),Vector3(1.8,1.5,1.5),"wood",Vector3(0,float(i%5)*0.10,0))
		if i%3 == 0:
			g.cylinder(Vector3(x+2.1,0.6,z),0.48,1.2,"wood")
	root.set_meta("interior_anchor",Vector3(0,2,-d*0.32))

func _cypress(at: Vector3, height: float) -> void:
	g.cylinder(at+Vector3.UP*height*0.24,height*0.025,height*0.48,"wood")
	g.cylinder(at+Vector3.UP*height*0.55,height*0.10,height*0.80,"green",height*0.012)

func _hippodrome(w: float, d: float, h: float) -> void:
	var radius: float = w*0.5
	var seating: float = w*0.145
	var curve_z: float = d*0.5-radius
	var straight: float = d-radius
	var tiers: int = 18
	_solid(Vector3(0,0.08,-radius*0.5),Vector3(w,0.16,straight),"plaster")
	for side in [-1.0,1.0]:
		for tier in range(tiers):
			var strip: float = seating/tiers
			var x: float = side*(radius-seating+(tier+0.5)*strip)
			var y: float = 0.45+(tier+0.5)*h*0.55/tiers
			g.box(Vector3(x,y,-radius*0.5),Vector3(strip+0.04,h*0.55/tiers,straight),"stone")
		var bays: int = maxi(12,int(straight/9.0))
		_arcade(Vector3(side*(radius-0.8),0,-d*0.5),Vector3(side*(radius-0.8),0,curve_z),bays,h*0.46,2.0)
		g.box(Vector3(side*radius,h*0.61,-radius*0.5),Vector3(1.0,1.0,straight),"stone")
		for i in range(bays+1):
			g.box(Vector3(side*(radius-seating*0.5),h*0.29,-d*0.5+i*straight/bays),Vector3(seating,0.20,0.35),"plaster",Vector3(0,0,side*atan2(h*0.55,seating)))
	# Continuous semicircular sphendone; proper radial tier and retaining faces.
	for segment in range(64):
		var aa: float = PI*segment/64.0
		var ab: float = PI*(segment+1)/64.0
		var center := Vector3(0,0,curve_z)
		g.triangle(center+Vector3.UP*0.10,center+Vector3(cos(aa)*radius,0.10,sin(aa)*radius),center+Vector3(cos(ab)*radius,0.10,sin(ab)*radius),"plaster")
		for tier in range(tiers):
			var ri: float = radius-seating+tier*seating/tiers
			var ro: float = ri+seating/tiers
			var y: float = 0.45+(tier+1)*h*0.55/tiers
			var p: Vector3 = center+Vector3(cos(aa)*ri,y,sin(aa)*ri)
			var q: Vector3 = center+Vector3(cos(ab)*ri,y,sin(ab)*ri)
			var r: Vector3 = center+Vector3(cos(ab)*ro,y,sin(ab)*ro)
			var s: Vector3 = center+Vector3(cos(aa)*ro,y,sin(aa)*ro)
			g._oriented_quad(p,q,r,s,Vector3.UP,"stone")
			g._oriented_quad(p-Vector3.UP*h*0.55/tiers,p,q,q-Vector3.UP*h*0.55/tiers,-Vector3(cos((aa+ab)*0.5),0,sin((aa+ab)*0.5)),"stone")
		var outer_a: Vector3 = center+Vector3(cos(aa)*radius,0,sin(aa)*radius)
		var outer_b: Vector3 = center+Vector3(cos(ab)*radius,0,sin(ab)*radius)
		g._oriented_quad(outer_a,outer_b,outer_b+Vector3.UP*h*0.59,outer_a+Vector3.UP*h*0.59,Vector3(cos((aa+ab)*0.5),0,sin((aa+ab)*0.5)),"brick")
		if segment%4 == 0:
			_bands(center+Vector3(cos(aa)*(radius+0.8),0,sin(aa)*(radius+0.8)),2.0,2.0,h*0.61)
	# Spina with period-inspired monuments, not an imported modern plaza model.
	_solid(Vector3(0,0.70,-d*0.03),Vector3(w*0.065,1.1,d*0.56),"stone")
	_obelisk(Vector3(0,1.25,-d*0.20),w*0.037,h*1.18)
	_obelisk(Vector3(0,1.25,d*0.20),w*0.044,h*1.12)
	for strand in range(3):
		for segment in range(32):
			var ta: float = segment*TAU*2.0/32.0+strand*TAU/3.0
			var tb: float = (segment+1)*TAU*2.0/32.0+strand*TAU/3.0
			g.rod(Vector3(cos(ta)*0.45,1.3+segment*h*0.28/32.0,sin(ta)*0.45),Vector3(cos(tb)*0.45,1.3+(segment+1)*h*0.28/32.0,sin(tb)*0.45),0.17,"green",-1.0,8)
	# Starting-end galleries and the imperial viewing connection are hypotheses.
	_arcade(Vector3(-w*0.37,0,-d*0.5),Vector3(w*0.37,0,-d*0.5),12,h*0.55,2.0)
	g.roof(Vector3(0,h*0.58,-d*0.5),w*0.80,w*0.10,h*0.15,"roof")
	_bands(Vector3(w*0.49,0,-d*0.08),w*0.10,d*0.11,h*0.7)
	_arcade(Vector3(w*0.425,h*0.72,-d*0.13),Vector3(w*0.425,h*0.72,-d*0.035),5,h*0.25,0.7)
	g.roof(Vector3(w*0.49,h*0.98,-d*0.08),w*0.15,d*0.13,h*0.13,"roof")
	root.set_meta("interior_anchor",Vector3(w*0.15,2,-d*0.19))

func _taper_box(at: Vector3, width: float, depth: float, height: float, top_scale: float, material: String) -> void:
	var bottom: Array[Vector3] = [at+Vector3(-width/2,0,-depth/2),at+Vector3(width/2,0,-depth/2),at+Vector3(width/2,0,depth/2),at+Vector3(-width/2,0,depth/2)]
	var top: Array[Vector3] = []
	for point in bottom:
		top.append(at+(point-at)*top_scale+Vector3.UP*height)
	for i in range(4):
		var j: int = (i+1)%4
		var outward: Vector3 = ((bottom[i]+bottom[j])*0.5-at).normalized()
		g._oriented_quad(bottom[i],bottom[j],top[j],top[i],outward,material)
	if top_scale > 0.0:
		g._oriented_quad(top[0],top[1],top[2],top[3],Vector3.UP,material)

func _obelisk(at: Vector3, width: float, height: float) -> void:
	g.box(at+Vector3.UP*width*0.25,Vector3(width*1.8,width*0.5,width*1.8),"stone")
	g.box(at+Vector3.UP*width*0.85,Vector3(width*1.25,width*0.7,width*1.25),"plaster")
	_taper_box(at+Vector3.UP*width*1.2,width,width,height-width*2.0,0.63,"stone")
	_taper_box(at+Vector3.UP*(height-width*0.8),width*0.63,width*0.63,width*0.8,0.0,"stone")
	# Incised bands are restrained original relief, not copied inscriptions.
	for i in range(6):
		g.box(at+Vector3(0,width*1.4+i*width*0.13,-width*0.627),Vector3(width*0.82,width*0.045,0.028),"dark")

func _cistern(w: float, d: float, h: float) -> void:
	var open_top: bool = bool(dimensions.get("open_top",0))
	var floor_y: float = -h
	var thickness: float = minf(w,d)*0.018
	_solid(Vector3(0,floor_y-0.24,0),Vector3(w,0.48,d),"stone")
	for side in [-1.0,1.0]:
		_solid(Vector3(side*(w*0.5-thickness*0.5),floor_y*0.5,0),Vector3(thickness,h,d),"brick")
		_solid(Vector3(0,floor_y*0.5,side*(d*0.5-thickness*0.5)),Vector3(w,h,thickness),"brick")
		g.box(Vector3(side*(w*0.5+0.7),0.15,0),Vector3(thickness+2.0,0.5,d+4.0),"stone")
		g.box(Vector3(0,0.15,side*(d*0.5+0.7)),Vector3(w+4.0,0.5,thickness+2.0),"stone")
	g.box(Vector3(0,floor_y+0.22,0),Vector3(w-thickness*2.1,0.11,d-thickness*2.1),"water")
	if not open_top:
		var count: int = int(dimensions.get("column_count",336))
		var columns: int = int(dimensions.get("column_grid_x",maxi(4,int(round(sqrt(float(count)*w/d))))))
		var rows: int = int(dimensions.get("column_grid_z",maxi(4,int(ceil(float(count)/columns)))))
		var dx: float = (w-thickness*4.0)/(columns+1)
		var dz: float = (d-thickness*4.0)/(rows+1)
		var column_height: float = h*0.72
		var radius: float = minf(dx,dz)*0.095
		var emitted: int = 0
		var vaults: RefCounted = Geometry.new(materials)
		for row in range(rows):
			for col in range(columns):
				if emitted >= count:
					break
				var p := Vector3((col-(columns-1)*0.5)*dx,floor_y+0.28,(row-(rows-1)*0.5)*dz)
				_column(p,column_height,radius,"stone" if emitted%7 else "green")
				if col+1 < columns and emitted+1 < count:
					g.arch(p+Vector3(dx*0.5,column_height,0),dx-radius*2.0,dx*0.5-radius,0.48,0.28,"brick")
				if row+1 < rows and emitted+columns < count:
					g.arch(p+Vector3(0,column_height,dz*0.5),dz-radius*2.0,dz*0.5-radius,0.48,0.28,"brick",PI*0.5)
				if row+1 < rows and col+1 < columns and emitted+columns+1 < count:
					_groin_vault(vaults,p+Vector3(dx*0.5,column_height,dz*0.5),dx,dz,minf(dx,dz)*0.5-radius)
				emitted += 1
		# The cap belongs to a separate node: exterior inspection can deliberately
		# cut it away, while entering the cistern restores a fully enclosed room.
		vaults.box(Vector3(0,0.31,0),Vector3(w,0.62,d),"brick")
		var ceiling := MeshInstance3D.new()
		ceiling.name = "CisternVaultRoof"
		ceiling.mesh = vaults.finish()
		ceiling.visible = false
		root.add_child(ceiling)
		root.set_meta("enclosure_node",NodePath("CisternVaultRoof"))
		for row in range(7):
			for side in [-1.0,1.0]:
				var light_pos := Vector3(side*w*0.18,floor_y+h*0.52,(row-3)*d*0.115)
				_inspection_light(light_pos,Color("#f4bd77"),6.0,minf(w*0.48,32.0))
				g.rod(light_pos+Vector3(0,1.4,0),light_pos,0.018,"gold",-1.0,6)
				g.cylinder(light_pos,0.21,0.14,"gold")
		# A narrow retained vault strip communicates enclosure while the study's
		# roof cutaway keeps the underground interior inspectable from above.
		for side in [-1.0,1.0]:
			g.box(Vector3(side*(w*0.5-thickness-1.3),-0.2,0),Vector3(2.6,0.35,d-thickness*2),"brick")
	# Descending masonry stair links the surface collar with the pit floor.
	var steps: int = maxi(10,int(ceil(h/0.22)))
	var run: float = minf(d*0.28,h*1.85)
	for step in range(steps):
		var fraction: float = float(step+1)/steps
		var y: float = -h*fraction+0.32
		var z: float = -d*0.5+thickness+run*fraction
		_solid(Vector3(-w*0.5+thickness+2.1,y-0.13,z),Vector3(3.2,0.26,run/steps+0.08),"stone")
	root.set_meta("interior_anchor",Vector3(0,floor_y+2.0,-d*0.20))
	root.set_meta("underground",true)
	root.set_meta("roof_cutaway",not open_top)

func _groin_vault(builder: RefCounted, at: Vector3, width: float, depth: float, rise: float) -> void:
	# Intersecting barrel surfaces. The four edge arches meet at a shared
	# springing plane; diagonal groins emerge from the two cylinder envelopes.
	var divisions: int = 6
	for row in range(divisions):
		for col in range(divisions):
			var points: Array[Vector3] = []
			for uv in [Vector2(float(col)/divisions,float(row)/divisions),Vector2(float(col+1)/divisions,float(row)/divisions),Vector2(float(col+1)/divisions,float(row+1)/divisions),Vector2(float(col)/divisions,float(row+1)/divisions)]:
				var u: float = uv.x*2.0-1.0
				var v: float = uv.y*2.0-1.0
				var elevation: float = rise*sqrt(maxf(0.0,1.0-minf(u*u,v*v)))
				points.append(at+Vector3(u*width*0.5,elevation,v*depth*0.5))
			builder._oriented_quad(points[0],points[1],points[2],points[3],Vector3.DOWN,"brick")

func _aqueduct(w: float, d: float, h: float) -> void:
	var bays: int = int(dimensions.get("arch_count",maxi(5,int(w/13.0))))
	var spacing: float = w/bays
	var pier: float = spacing*0.20
	var lower: float = h*0.50
	for level in range(2):
		var base: float = level*lower
		for i in range(bays+1):
			_bands(Vector3(-w*0.5+i*spacing,base,0),pier,d,lower)
		for i in range(bays):
			g.arch(Vector3(-w*0.5+(i+0.5)*spacing,base,0),spacing-pier,lower*0.85,d,maxf(0.4,pier*0.35),"stone")
		g.box(Vector3(0,base+lower,0),Vector3(w+pier,0.75,d+0.2),"stone")
	for side in [-1.0,1.0]:
		g.box(Vector3(0,h+0.8,side*(d*0.5-0.2)),Vector3(w+pier,1.3,0.4),"brick")
	g.box(Vector3(0,h+0.25,0),Vector3(w,0.08,d*0.70),"water")

func _monument_column(w: float, d: float, h: float) -> void:
	var radius: float = float(dimensions.get("shaft_radius_m",minf(w,d)*0.15))
	for i in range(4):
		g.box(Vector3(0,0.22+i*0.40,0),Vector3(w*(1.0-i*0.12),0.44,d*(1.0-i*0.12)),"stone")
	g.box(Vector3(0,h*0.11,0),Vector3(radius*3.0,h*0.13,radius*3.0),"stone")
	g.cylinder(Vector3(0,h*0.54,0),radius,h*0.75,"brick",radius*0.88)
	for i in range(9):
		g.cylinder(Vector3(0,h*0.20+i*h*0.078,0),radius*(1.015-i*0.011),h*0.013,"stone")
	g.cylinder(Vector3(0,h*0.93,0),radius*1.16,h*0.07,"stone",radius*1.42)
	g.box(Vector3(0,h*0.98,0),Vector3(radius*3.0,h*0.03,radius*3.0),"stone")
	if bool(dimensions.get("cross_top",0)):
		_cross(Vector3(0,h,0),radius*1.5)

func _gate(w: float, d: float, h: float) -> void:
	var tower: float = w*0.26
	var tower_height: float = float(dimensions.get("tower_height_m",h))
	var clear: float = w*0.27
	var passage_height: float = minf(h*0.51,clear*1.35)
	for side in [-1.0,1.0]:
		var p := Vector3(side*(w-tower)*0.5,0,0)
		_bands(p,tower,d,tower_height)
		g.box(p+Vector3.UP*(tower_height+0.20),Vector3(tower+0.5,0.5,d+0.5),"stone")
		for f in [0.29,0.61]:
			for x in [-tower*0.23,tower*0.23]:
				_window(p+Vector3(x,tower_height*f,-d*0.5-0.03),0.45,tower_height*0.09,0.0)
		for i in range(5):
			for edge in [-1.0,1.0]:
				g.box(p+Vector3((i-2)*tower/4.5,tower_height+1.05,edge*d*0.47),Vector3(tower*0.12,1.6,d*0.10),"stone")
		for i in range(4):
			for edge in [-1.0,1.0]:
				g.box(p+Vector3(edge*tower*0.47,tower_height+1.05,(i-1.5)*d/4.0),Vector3(tower*0.1,1.6,d*0.12),"stone")
	g.arch(Vector3(0,0,0),clear,passage_height,d*0.80,1.0,"stone")
	var above: float = h*0.77-passage_height-0.8
	if above > 0.0:
		g.box(Vector3(0,passage_height+0.8+above*0.5,0),Vector3(w-tower*1.9,above,d*0.78),"brick")
	g.box(Vector3(0,h*0.78,0),Vector3(w-tower*1.6,0.5,d*0.9),"stone")
	for i in range(7):
		g.box(Vector3((i-3)*(w-tower*1.8)/7.0,h*0.78+0.85,-d*0.42),Vector3(0.8,1.4,0.8),"stone")
	# Open gate leaves lie beside the passage, preserving the opening.
	for side in [-1.0,1.0]:
		g.box(Vector3(side*clear*0.51,passage_height*0.31,0),Vector3(0.22,passage_height*0.61,clear*0.47),"wood")
		for level in range(4):
			g.box(Vector3(side*(clear*0.51-0.13),passage_height*(0.10+level*0.13),0),Vector3(0.07,0.11,clear*0.48),"dark")
